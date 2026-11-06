import 'dart:async';
import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// 管理端全局长连接（L1）。
///
/// 登录并选定租户后建立一条 socket，服务端按 token 识别身份并加入
/// `admin_{id}` 房间，之后任何有权限的会话产生访客消息都会推 `conv_updated`
/// 摘要。会话列表用它做秒级刷新，沟通页用 `new_msg` 做即时刷新，5 秒轮询
/// 继续保留作为兜底（断线、代理不支持 websocket、多 worker 漏推）。
///
/// 同一份连接只允许存在一条：沟通页 join/leave 的是会话房间，不再各自建连接。
///
/// 连上之后还会持续上报在线心跳（reportPresence）：服务端只有在这台设备实时弹不出
/// 提醒时才会去走 FCM/APNs，两边共用同一条链路才能不弹两遍、也不漏弹。
class RealtimeService {
  io.Socket? _socket;

  String _baseUrl = '';
  String _token = '';
  int _tenantId = 0;
  String? _convKey;

  final StreamController<Map<String, dynamic>> _convUpdates =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _newMessages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _convReads =
      StreamController<Map<String, dynamic>>.broadcast();

  /// 会话摘要：{ data: { conv_key, admin_unread, total_unread, ... } }
  Stream<Map<String, dynamic>> get convUpdates => _convUpdates.stream;

  /// 当前打开会话的新消息：{ data: { conversation_id, id, ... } }
  Stream<Map<String, dynamic>> get newMessages => _newMessages.stream;

  /// 同一账号其他设备读完了某会话：{ conv_key, conversation_id }
  Stream<Map<String, dynamic>> get convReads => _convReads.stream;

  bool get connected => _socket?.connected == true;

  /// 在线判定的口径由宿主给出：只有“此刻真能弹提醒”才返回 true（APP 在前台）。
  /// 没设置它的连接（保活 isolate 自己那条）完全不参与上报：它在后台收到摘要后
  /// 依然把提醒交给系统推送，报“在线”只会把唯一的提醒渠道挡掉。
  bool Function()? presenceActive;

  /// 设备标识，与 FCM/APNs token 登记同源；只用于服务端把两边对上，拿不到不影响判定
  String presenceDeviceId = '';
  Timer? _presenceTimer;

  /// 心跳间隔必须明显小于服务端的判活窗口（45 秒），否则一次网络抖动就会被当成掉线
  static const Duration _presenceBeat = Duration(seconds: 15);

  String get _identity => '$_baseUrl|$_token|$_tenantId';

  /// 登录态或租户变化时调用；参数相同则复用现有连接。
  /// token/tenant 为空（未登录、平台超管未选租户）时断开。
  void connect({
    required String baseUrl,
    required String token,
    required int tenantId,
  }) {
    if (baseUrl.isEmpty || token.isEmpty || tenantId <= 0) {
      disconnect();
      return;
    }
    if (_socket != null && _identity == '$baseUrl|$token|$tenantId') {
      if (!connected) _socket!.connect();
      return;
    }
    disconnect();
    _baseUrl = baseUrl;
    _token = token;
    _tenantId = tenantId;
    try {
      final socket = io.io(
        baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setPath('/chat-ws')
            .disableAutoConnect()
            .build(),
      );
      _socket = socket;
      // 每次（重）连上都要重新识别身份并重新加入当前会话房间，
      // socket.io 的自动重连不会保留服务端的房间成员资格
      socket.onConnect((_) => _onConnected());
      socket.on('conv_updated', (payload) => _emit(_convUpdates, payload));
      socket.on('conv_read', (payload) => _emit(_convReads, payload));
      socket.on('new_msg', (payload) => _emit(_newMessages, payload));
      socket.connect();
    } catch (_) {
      // 平台不支持 / 参数异常：列表与沟通页的轮询仍然工作
      _socket = null;
    }
  }

  void _onConnected() {
    final socket = _socket;
    if (socket == null) return;
    socket.emit('identify', {'token': _token, 'tenant_id': _tenantId});
    // 重连后服务端身份要重新落定，在线心跳也紧接着补一次，别等下一轮定时
    reportPresence();
    final key = _convKey;
    if (key != null && key.isNotEmpty) {
      socket.emit('join', {'convKey': key});
    }
  }

  /// 上报“本机此刻能不能实时弹提醒”。服务端只在它不为 true（或心跳超时）时才去走
  /// FCM/APNs，避免前台已经弹过一次、系统推送又弹第二条。
  ///
  /// 前后台切换要立即调一次：退后台那一下如果等到下一轮心跳，中间十几秒来的消息
  /// 就既没推送也没人看见。之后靠定时续期，断网/被冻结都只是停止续期，
  /// 服务端超时自动降级成离线，失败方向是多推一条而不是漏推。
  void reportPresence() {
    if (presenceActive == null) return;
    _sendPresence(presenceActive!() == true);
    _stopPresenceBeat();
    // 已经是离线就报一次就够：服务端把这行当离线处理，继续续期只会多写几次库。
    // 回到前台时会重新调 reportPresence，心跳跟着重起
    if (presenceActive!() != true) return;
    _presenceTimer = Timer.periodic(_presenceBeat, (_) {
      if (!connected) {
        // 断线就停心跳：剩下的交给服务端超时，不必自己再判一次“算不算在线”
        _stopPresenceBeat();
        return;
      }
      final active = presenceActive!() == true;
      _sendPresence(active);
      if (!active) _stopPresenceBeat();
    });
  }

  void _stopPresenceBeat() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  void _sendPresence(bool active) {
    final socket = _socket;
    if (socket == null || !connected) return;
    socket.emit('presence', <String, dynamic>{
      'client': Platform.isIOS ? 'app_ios' : 'app_android',
      'device_id': presenceDeviceId,
      'active': active,
    });
  }

  /// 沟通页进入时加入会话房间；同一条连接切换会话时先退出上一个
  void joinConversation(String convKey) {
    if (convKey.isEmpty) return;
    if (_convKey != null && _convKey != convKey && _socket?.connected == true) {
      _socket!.emit('leave', {'convKey': _convKey});
    }
    _convKey = convKey;
    if (_socket?.connected == true) {
      _socket!.emit('join', {'convKey': convKey});
    }
  }

  void leaveConversation(String convKey) {
    if (_convKey != convKey) return;
    if (_socket?.connected == true) {
      _socket!.emit('leave', {'convKey': convKey});
    }
    _convKey = null;
  }

  void disconnect() {
    _convKey = null;
    _stopPresenceBeat();
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _baseUrl = '';
    _token = '';
    _tenantId = 0;
  }

  void _emit(StreamController<Map<String, dynamic>> target, dynamic payload) {
    if (payload is! Map) return;
    target.add(Map<String, dynamic>.from(payload));
  }
}
