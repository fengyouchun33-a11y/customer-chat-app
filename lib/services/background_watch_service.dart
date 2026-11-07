import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'notification_service.dart';
import 'realtime_service.dart';

/// 后台保活与消息提醒。
///
/// Android 用前台服务（常驻通知）保证进程存活：任务 isolate 里维持一条
/// socket（L2）接实时摘要，socket 在线时轮询降级为 60 秒自检，断线立即回到
/// 15 秒 HTTP 轮询；iOS 的 BGTask 只能短暂唤醒，实时提醒依靠 FCM/APNs（L3）。
///
/// 轮询沿用当前管理员的 X-Token + X-Tenant-Id，服务端按租户与授权项目过滤，
/// 因此只会对"权限范围内"的会话发通知；回复产生的新消息不会增加管理员未读，
/// 也不会误报。
class BackgroundWatchService {
  BackgroundWatchService._();

  static const String snapshotKey = 'keiyo_watch_snapshot';
  static const String readyKey = 'keiyo_watch_ready';

  /// 主 isolate 启动时调用一次（main 里，runApp 之前）
  static void init() {
    if (kIsWeb) return;
    final s = AppStrings.current;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'keiyo_chat_service',
        channelName: s.fgChannelName,
        channelDescription: s.fgChannelDesc,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// 登录成功 / 已选租户后启动；已在运行则直接返回
  static Future<void> start() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final s = AppStrings.current;
      await FlutterForegroundTask.startService(
        serviceId: 2601,
        // 与 AndroidManifest 中的 android:foregroundServiceType 保持一致
        serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: s.fgChannelName,
        notificationText: s.fgNotificationText,
        callback: keiyoWatchCallback,
      );
    } catch (_) {
      // 权限未授予、系统限制或服务已在运行时忽略，页面轮询仍可用
    }
  }

  /// 切换语言后刷新常驻通知文案：服务只在登录/换租户时重建，
  /// 不主动更新的话通知栏会一直停在切换前的语言。
  static Future<void> refreshNotification() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      final s = AppStrings.current;
      await FlutterForegroundTask.updateService(
        notificationTitle: s.fgChannelName,
        notificationText: s.fgNotificationText,
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// 把登录态与 UI 状态推给保活 isolate：token/租户/提示音开关这些只能从主
  /// isolate 拿到（见 KeiyoWatchTaskHandler 字段说明），前台状态则靠心跳时效判定。
  /// snapshot 只在此 isolate 还没基线时交接一次，避免每 2 秒搬一叠会话 JSON。
  static void pushContext({
    required bool foreground,
    required String token,
    required int tenantId,
    required bool soundEnabled,
    required bool pushRegistered,
    String? lang,
    String? openConvKey,
    String? baselineSeed,
  }) {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.sendDataToTask({
        'type': 'watch_context',
        'foreground': foreground,
        'open_conv_key': openConvKey ?? '',
        'token': token,
        'tenant_id': tenantId,
        'sound_enabled': soundEnabled,
        'push_registered': pushRegistered,
        'lang': lang,
        'baseline_seed': baselineSeed,
      });
    } catch (e) {
      // 送达失败时闸门会停在最后一次状态上，不记日志就永远是“后台不弹但查不出原因”
      debugPrint('[watch] sendDataToTask failed: $e');
    }
  }

  /// 主 isolate 注册回调，接收保活 isolate 发来的基线落盘/补种请求
  static void addTaskDataCallback(void Function(Map<Object?, Object?> data) onMessage) {
    if (kIsWeb) return;
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is Map) onMessage(data);
    });
  }

  /// 切换租户 / 退出登录时清空快照，避免把上一租户的未读当成新消息
  static Future<void> clearSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(snapshotKey);
      await prefs.remove(readyKey);
    } catch (_) {}
  }

  /// Android 关闭电池优化（各家 ROM 还需用户在设置里允许自启动/后台运行）
  static Future<bool> requestBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;
      final result = await Permission.ignoreBatteryOptimizations.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void keiyoWatchCallback() {
  FlutterForegroundTask.setTaskHandler(KeiyoWatchTaskHandler());
}

class KeiyoWatchTaskHandler extends TaskHandler {
  static const int _pageSize = 100;

  /// 前台心跳的有效窗口：超过这个时间没收到 foreground:true，就当作已不在前台。
  /// 主 isolate 每 2 秒发一次心跳，这里给到 4 个周期的容错。
  static const int _beatTtlMs = 8000;

  bool _busy = false;
  bool _foreground = false;
  DateTime _lastForegroundBeat = DateTime.fromMillisecondsSinceEpoch(0);

  /// 登录态与偏好由主 isolate 心跳下发，这里绝不能用 SharedPreferences：
  /// shared_preferences_android 已改为 JNI 实现，api 实例由 native 侧注册到主
  /// isolate，task isolate 里 getInstance() 必报“No instance with no name has been
  /// registered”，导致每轮 tick 都在第一行抛错、后台一条提醒都发不出去。
  String _token = '';
  int _tenantId = 0;
  bool _soundOn = true;
  bool _pushRegistered = false;

  /// 已提醒到的未读基线：以内存为准，变更后回写主 isolate 落盘；
  /// 冷启动时靠主 isolate 交接的种子接续，避免补发登录前的历史未读。
  Map<String, int> _baseline = <String, int>{};
  bool _baselineReady = false;

  int _tickCount = 0;
  RealtimeService? _realtime;
  String _rtIdentity = '';
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  /// 保活 socket 最后一次真正收到数据（或刚刚建好连接）的时刻。
  /// 只能在收到数据时刷新：要是每轮 tick 都重置，僵尸连接就永远不会被判过期。
  DateTime _lastSocketData = DateTime.fromMillisecondsSinceEpoch(0);

  /// socket 在线但多久没收到任何数据就算“僵尸”，恢复全量轮询兜底。
  /// 判据只能用新鲜度，不能用 connected：真机实测退到后台后 connected 仍为
  /// true、轮询被它一路抑制，而服务端推的 conv_updated 其实一条都没进 isolate，
  /// 后台发多少消息都毫无反应。
  static const int _socketStaleMs = 45000;

  /// 是否该因为“APP 在前台”而不弹系统通知。
  ///
  /// 前台状态只能由主 isolate 推过来，而 APP 退到后台/被 ROM 冻结后，
  /// 主 isolate 连那条 foreground:false 都发不出来。只认最后一次推送的值的话，
  /// 闸门会永远卡在“前台”，后台通知一条都不弹。所以这里只在心跳仍然是新鲜的时候
  /// 才不弹：拿不到新证据时默认当作后台，宁可多发一条也不能漏。
  bool get _inForegroundNow {
    if (!_foreground) return false;
    return DateTime.now().difference(_lastForegroundBeat).inMilliseconds < _beatTtlMs;
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      // FCM 下发时指定了同一个 channel_id，必须先把渠道建好
      await NotificationService.instance.ensureChannel();
    } catch (e) {
      // 渠道没建好时系统会丢弃整条通知，这里不能静默
      debugPrint('[watch] ensureChannel failed: $e');
    }
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _rtSub?.cancel();
    _rtSub = null;
    _realtime?.disconnect();
    _realtime = null;
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data['type'] != 'watch_context') return;
    final token = (data['token'] ?? '').toString();
    final tenantId = asInt(data['tenant_id']);
    // 换账号或换租户后旧基线全部作废：拿上一租户的未读数当基线会把新消息当旧的吞掉
    if (tenantId != _tenantId || (token.isNotEmpty && token != _token)) {
      _baseline = <String, int>{};
      _baselineReady = false;
    }
    _token = token;
    _tenantId = tenantId;
    _soundOn = data['sound_enabled'] != false;
    _pushRegistered = data['push_registered'] == true;
    // 保活 isolate 的 Localizations 树不存在，通知文案只能靠语言码自己切
    final lang = data['lang'];
    if (lang is String && lang.isNotEmpty) {
      AppStrings.current = AppStrings.forCode(lang);
    }
    final fg = data['foreground'] == true;
    if (fg != _foreground) debugPrint('[watch] context foreground $_foreground->$fg');
    _foreground = fg;
    // 只有前台心跳刷新时间戳；退后台时那一下要立即放行通知，不能等到超时
    if (_foreground) _lastForegroundBeat = DateTime.now();
    // 种子只在还没基线时接一次；主 isolate 没给或给空就维持“首轮只建基线”口径
    if (!_baselineReady && data['baseline_seed'] is String) {
      final seed = _readSnapshot(data['baseline_seed'] as String);
      if (seed.isNotEmpty) {
        _baseline = seed;
        _baselineReady = true;
        debugPrint('[watch] baseline seeded from main isolate: ${seed.length} convs');
      }
    }
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      // 登录态由主 isolate 心跳下发：这一层绝对不碰 SharedPreferences，
      // 它在本 isolate 里必定抛 ArgumentError（JNI 实例只注册在主 isolate）
      if (_token.isEmpty || _tenantId <= 0) {
        // 冷启动后主 isolate 的首轮心跳还没到，下一轮再试，不能停服务
        debugPrint('[watch] no context from main isolate yet'
            ' (token=${_token.isNotEmpty} tenant=$_tenantId)');
        return;
      }
      // 服务器地址固定为正式域名，不读本地配置
      const baseUrl = AppConfig.defaultBaseUrl;
      final token = _token;
      final tenantId = _tenantId;

      // L2：保活 isolate 内维持一条 socket，后台也能秒收会话摘要；
      // socket 确实在收数据时轮询降为 60 秒自检，一旦僵尸或断线立即回到 15 秒全量轮询
      await _ensureRealtime(baseUrl, token, tenantId);
      _tickCount++;
      final socketAlive = _realtime?.connected == true;
      final socketFresh = socketAlive &&
          DateTime.now()
                  .difference(_lastSocketData)
                  .inMilliseconds <
              _socketStaleMs;
      // 每约 60 秒留一行存活证据：排查“后台完全不提醒”时，最先要区分的
      // 就是“保活 isolate 已停”和“还在跑但没有新消息”，两者在日志上本来长一模一样
      if (_tickCount % 4 == 0) {
        debugPrint('[watch] alive tick=$_tickCount'
            ' socket=$socketAlive fresh=$socketFresh'
            ' foreground=$_inForegroundNow tenant=$tenantId');
      }
      // connected 只是客户端自己记的标志，半开连接不会翻成 false；
      // 长时间没收到任何包时不能继续信任它，必须让轮询顶上
      if (socketFresh && _tickCount % 4 != 0) return;

      // FCM 已登记时系统推送由服务端负责，本地通知只作为未配置 Firebase 的兜底
      final pushRegistered = _pushRegistered;

      final api = ApiClient(baseUrl)
        ..setAuth(token: token, tenantId: tenantId);
      final data = await api.get(
        '/admin/conversation/list',
        query: {'page': 1, 'pageSize': _pageSize},
      );
      final rawList = data is Map ? data['list'] : null;
      if (rawList is! List) {
        debugPrint('[watch] list api returned no list (tenant=$tenantId)');
        return;
      }

      final list = rawList
          .whereType<Map>()
          .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.convKey.isNotEmpty)
          .toList();

      if (!_baselineReady) {
        // 首轮成功轮询只建立基线，不补发登录前/启动前的历史未读
        debugPrint('[watch] build baseline: ${list.length} convs');
        for (final c in list) {
          _baseline[c.convKey] = c.adminUnread;
        }
        _baselineReady = true;
        _pushBaselineToMain();
        return;
      }

      final totalUnread =
          list.fold<int>(0, (sum, c) => sum + (c.adminUnread > 0 ? c.adminUnread : 0));

      for (final c in list) {
        final prev = _baseline[c.convKey] ?? 0;
        _baseline[c.convKey] = c.adminUnread;
        if (c.adminUnread <= prev || c.adminUnread <= 0) continue;
        // APP 在前台时由 L1 页面实时刷新，不弹系统通知（与 socket 路径同一口径）
        if (_inForegroundNow) {
          debugPrint('[watch] skip poll notify: foreground ${c.convKey} $prev->${c.adminUnread}');
          continue;
        }
        if (pushRegistered) {
          debugPrint('[watch] skip poll notify: fcm registered ${c.convKey}');
          continue;
        }
        debugPrint('[watch] poll notify ${c.convKey} $prev->${c.adminUnread}');
        await _notify(c, totalUnread, tenantId);
      }

      _pushBaselineToMain();
    } catch (e) {
      // 网络波动、令牌过期、系统限制都不打扰用户，下一轮再试
      debugPrint('[watch] tick failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// 保活 isolate 内的长连接：只有 Android 前台服务能长期存活；
  /// iOS 后台只做短暂唤醒，实时提醒交给 APNs，不在后台维持 socket。
  ///
  /// 这条连接故意不设 presenceActive，因而不上报在线心跳：后台收到摘要时它仍然
  /// 把提醒交给系统推送（见上面的 _pushRegistered 分支），报“在线”只会把唯一的
  /// 提醒渠道挡掉。
  Future<void> _ensureRealtime(String baseUrl, String token, int tenantId) async {
    _tenantId = tenantId;
    if (Platform.isIOS) return;
    final identity = '$baseUrl|$token|$tenantId';
    if (_realtime == null || _rtIdentity != identity) {
      await _rtSub?.cancel();
      _rtSub = null;
      _realtime?.disconnect();
      final rt = RealtimeService();
      // 收到任何一包都证明这条链路真的活着；换连接时旧的订阅先 cancel，
      // 否则会越挂越多，同一包数据被提醒好几次
      _rtSub = rt.convUpdates.listen((payload) {
        _lastSocketData = DateTime.now();
        _onRealtimeConvUpdated(payload);
      });
      _realtime = rt;
      _rtIdentity = identity;
      // 新建连接给一个新鲜窗口，免得还在握手的几秒被当成僵尸白跑一轮轮询
      _lastSocketData = DateTime.now();
    }
    if (_realtime!.connected == false) {
      _realtime!.connect(baseUrl: baseUrl, token: token, tenantId: tenantId);
    }
  }

  /// socket 推送的会话摘要与轮询同口径：只看访客新消息带来的未读增长
  Future<void> _onRealtimeConvUpdated(Map<String, dynamic> payload) async {
    final raw = payload['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final tid = asInt(data['tenant_id']);
    if (tid > 0 && _tenantId > 0 && tid != _tenantId) return;
    final convKey = asString(data['conv_key']);
    final unread = asInt(data['admin_unread']);
    if (convKey.isEmpty || unread <= 0) return;
    // APP 在前台时由 L1 的页面实时刷新，不弹系统通知
    // 注意不能再看 _openConvKey：退出到后台后它仍停在最后打开的会话，
    // 以它为准会把“后台时该会话的新消息”静默吞掉
    if (_inForegroundNow) {
      debugPrint('[watch] skip socket notify: foreground $convKey ->$unread');
      return;
    }
    // 已提醒到的未读数以内存基线为准（与轮询同源）：
    // 客服读完会话后未读会回落，只看历史最大值会把“读完后的第一条新消息”当成旧的吞掉
    final prev = _baseline[convKey] ?? 0;
    if (unread <= prev) {
      debugPrint('[watch] skip socket notify: no growth $convKey $prev->$unread');
      return;
    }
    // 先落基线再提醒：轮询下一轮对比时不会重复弹同一条
    _baseline[convKey] = unread;
    _pushBaselineToMain();
    // FCM 已登记时由系统推送负责，避免与本地通知重复弹两条
    if (_pushRegistered) {
      debugPrint('[watch] skip socket notify: fcm registered $convKey');
      return;
    }
    final conv = Conversation.fromJson(data);
    final total = asInt(data['total_unread'], unread);
    debugPrint('[watch] socket notify $convKey ->$unread');
    unawaited(_notify(conv, total, _tenantId));
  }

  Future<void> _notify(Conversation c, int totalUnread, int tenantId) async {
    final s = AppStrings.current;
    // 标题只放人名：会话标题是首条消息，拿来当人名会变成「你好 发来新消息」
    final name = c.userName.trim().isNotEmpty ? c.userName.trim() : s.visitor;
    // 通知栏正文用最新一条消息（服务端已压成单行：图片→[图片]），与微信一致；
    // 拿不到正文时才回退到未读数，不再用会话标题（首条消息）冒充最新内容
    final preview = c.lastMsg.trim();
    final body = preview.isNotEmpty
        ? preview
        : s.unreadMessages('${c.adminUnread > 0 ? c.adminUnread : 1}');

    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'id': c.id,
      'project_id': c.projectId,
      'conv_key': c.convKey,
      'visitor_id': c.visitorId,
      'user_name': c.userName,
      'title': c.title,
      'status': c.status,
      'agent_id': c.agentId,
      'agent_name': c.agentName,
      'admin_unread': c.adminUnread,
      'last_msg_time': c.lastMsgTime?.toIso8601String() ?? '',
      'create_time': c.createTime?.toIso8601String() ?? '',
      'project_name': c.projectName,
    };

    // 提示音开关由主 isolate 心跳下发：关闭后通知仍然展示，只是不发声
    final playSound = _soundOn;

    try {
      await NotificationService.instance.showMessage(
        id: c.id > 0 ? c.id : (c.convKey.hashCode & 0x7fffffff),
        title: s.newMessageTitle(name),
        body: body,
        data: payload,
        badge: totalUnread,
        playSound: playSound,
      );
    } catch (e) {
      // 通知权限被拒、渠道不可用等都会走到这里，不记日志就永远是静默无提醒
      debugPrint('[watch] showMessage failed: $e');
    }
  }

  /// 把基线回写主 isolate 落盘：本 isolate 不能用 SharedPreferences，而冷启动
  /// 后要靠它把上一轮基线作为种子交回来，避免把已提醒过的消息再弹一次。
  void _pushBaselineToMain() {
    try {
      FlutterForegroundTask.sendDataToMain({
        'type': 'baseline',
        'tenant_id': _tenantId,
        'json': jsonEncode(_baseline),
      });
    } catch (e) {
      // 主 isolate 已被冻结时没人接收，只会丢失这次落盘，不影响本 isolate 判定
      debugPrint('[watch] baseline writeback failed: $e');
    }
  }

  Map<String, int> _readSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), asInt(v)));
      }
    } catch (_) {}
    return <String, int>{};
  }
}
