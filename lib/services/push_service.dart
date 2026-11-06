import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// 后台推送（L3）：Android 走 FCM，iOS 直连 APNs（不再经 Firebase/FCM 转发）。
///
/// 服务端在访客发消息时下发通知 + 业务字段，因此 APP 被系统挂起或进程被杀后
/// 仍能收到系统通知；点击通知时把载荷交给 AppState，复用现有 pendingConversation
/// 链路直接打开会话。
///
/// iOS 这一侧只依赖 ios/Runner/AppDelegate.swift 里的 keiyo/push_bridge 通道，
/// 不需要 GoogleService-Info.plist；Android 缺 google-services.json 时初始化会失败，
/// 这里静默降级：socket + 轮询仍然可用。
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// 与 AppDelegate.swift 约定的通道名（getToken / takePendingTap / onToken / onTap）
  static const MethodChannel _apns = MethodChannel('keiyo/push_bridge');

  static const String _tokenKey = 'keiyo_push_token';
  static const String _deviceKey = 'keiyo_device_id';

  /// 服务端是否已登记本机 token：保活 isolate 据此决定是否还弹本地通知
  static const String registeredKey = 'keiyo_push_registered';

  bool _initialized = false;
  bool _available = false;
  Future<void>? _initFuture;
  String? _lastRegisteredToken;

  /// 通知点击（含冷启动）回调，参数是会话字段 map
  void Function(Map<String, dynamic> data)? onOpenConversation;

  /// FCM token 轮换时回调，由 AppState 重新登记到服务端
  void Function()? onTokenChanged;

  /// 必须在 runApp 之前调用：注册后台消息入口。
  /// 只有 Android 用得到；iOS 直连 APNs，不碰 Firebase。
  static void registerBackgroundHandler() {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      FirebaseMessaging.onBackgroundMessage(keiyoFirebaseBackgroundHandler);
    } catch (_) {}
  }

  Future<void> init() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_initialized) return;
    final running = _initFuture;
    if (running != null) {
      await running;
      return;
    }
    final future = _doInit();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  Future<void> _doInit() async {
    if (Platform.isIOS) {
      try {
        await _initApnsBridge();
      } finally {
        // 这一步不能漏：没置位的话每次 sync 都会重挂 handler、重取一次待办点击
        _initialized = true;
      }
      return;
    }
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;

      // 通知权限与本地通知是同一个系统开关；这里只负责推送侧
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // 前台不弹横幅：会话列表/沟通页由 socket 实时更新，避免与本地通知重复。
      // 角标仍由服务端下发的未读总数控制。
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      _lastMessage = await messaging.getInitialMessage();
      if (_lastMessage != null) _handleMessage(_lastMessage!);

      messaging.onTokenRefresh.listen((token) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        _lastRegisteredToken = null;
        onTokenChanged?.call();
      });

      _available = true;
    } catch (e) {
      // 没有 Firebase 配置文件 / 模拟器不支持推送：保持不可用状态
      debugPrint('[push] Firebase unavailable: $e');
    } finally {
      _initialized = true;
    }
  }

  RemoteMessage? _lastMessage;

  /// iOS：挂上 AppDelegate 的 APNs 通道。探不到通道（旧包 / 没接好的构建）就保持
  /// 不可用，行为与 Firebase 缺配置时一致：只停系统推送，socket + 轮询照走。
  Future<void> _initApnsBridge() async {
    try {
      _apns.setMethodCallHandler(_handleApnsCall);
      final token = await _apns.invokeMethod<String>('getToken');
      _available = true;
      if (token != null && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
      }
      // 点通知时 Dart 侧 handler 可能还没挂上（冷启动、进程被系统杀掉后点开），
      // 原生把点击载荷暂存成一份，这里取一次清一次，不会重复打开会话
      final pending = await _takePendingTap();
      if (pending != null) onOpenConversation?.call(pending);
    } catch (e) {
      debugPrint('[push] APNs bridge unavailable: $e');
    }
  }

  Future<void> _handleApnsCall(MethodCall call) async {
    if (call.method == 'onToken') {
      final token = await _apns.invokeMethod<String>('getToken');
      if (token == null || token.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_tokenKey) ?? '';
      await prefs.setString(_tokenKey, token);
      // APNs 令牌会随重装/恢复备份轮换，变了就要重新登记到服务端
      if (stored != token) onTokenChanged?.call();
    } else if (call.method == 'onTap') {
      final data = await _takePendingTap();
      if (data != null) onOpenConversation?.call(data);
    }
  }

  Future<Map<String, dynamic>?> _takePendingTap() async {
    try {
      final raw = await _apns.invokeMethod<Map<dynamic, dynamic>>('takePendingTap');
      if (raw == null || raw.isEmpty) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// 登录成功 / 切换租户 / 回到前台时调用：拿到设备 token 并登记到服务端。
  /// 失败不打扰用户，下次登录或 token 刷新会再试。
  Future<void> sync(ApiClient api, {required int tenantId}) async {
    if (kIsWeb || tenantId <= 0) return;
    await init();
    if (!_available) return;
    try {
      final token = Platform.isIOS
          ? await _apnsTokenWithRetry()
          : await _getTokenWithRetry();
      if (token == null || token.isEmpty) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      final deviceId = await _deviceId();
      await api.post('/admin/push/register', data: {
        'token': token,
        'platform': platform,
        'device_id': deviceId,
      });
      _lastRegisteredToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setBool(registeredKey, true);
    } catch (e) {
      debugPrint('[push] register failed: $e');
    }
  }

  /// 退出登录前调用：把本机 token 从当前账号摘掉，避免继续推给已退出的人
  Future<void> unregister(ApiClient api) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _lastRegisteredToken ?? prefs.getString(_tokenKey) ?? '';
      if (token.isEmpty) return;
      await api.post('/admin/push/unregister', data: {'token': token});
      _lastRegisteredToken = null;
      await prefs.remove(_tokenKey);
      await prefs.setBool(registeredKey, false);
    } catch (_) {
      // 令牌可能已过期，忽略；服务端会在推送失败时清理失效 token
    }
  }

  // Android：FCM 首次注册可能慢于登录，取不到就稍后再试
  Future<String?> _getTokenWithRetry() async {
    for (var i = 0; i < 3; i++) {
      try {
        return await FirebaseMessaging.instance.getToken();
      } catch (_) {
        if (i < 2) await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  /// iOS：授权弹窗要等人点，首启时 token 可能还没回来，稍后再探两次
  Future<String?> _apnsTokenWithRetry() async {
    for (var i = 0; i < 3; i++) {
      try {
        final token = await _apns.invokeMethod<String>('getToken');
        if (token != null && token.isNotEmpty) return token;
      } catch (_) {
        return null;
      }
      if (i < 2) await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  /// 本机设备标识：与 token 登记同源，在线心跳也带上它，服务端排查时能把
  /// 在线记录与推送设备对上。拿不到也不影响判定（服务端按空串记一行）。
  Future<String> deviceId() => _deviceId();

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey) ?? '';
    if (id.isEmpty) {
      final rand = Random();
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
          rand.nextInt(1 << 32).toRadixString(36);
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  void _handleMessage(RemoteMessage message) {
    final data = <String, dynamic>{};
    message.data.forEach((k, v) => data[k] = v is String ? v : v.toString());
    if (data.isEmpty) return;
    onOpenConversation?.call(data);
  }
}

/// FCM 在后台/被终止时由系统直接展示 notification 部分，
/// 这个入口只用于保证插件要求的顶层 handler 存在。
@pragma('vm:entry-point')
Future<void> keiyoFirebaseBackgroundHandler(RemoteMessage message) async {}
