import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_strings.dart';

/// 本地通知。主 isolate 负责接收点击，后台保活 isolate 负责展示新消息。
///
/// 是否应该通知由调用方决定：后台轮询用的仍是当前管理员的 token 与租户，
/// 服务端会按租户 + 授权项目过滤，所以只会提醒"权限范围内"的会话。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String channelId = 'keiyo_chat_messages';
  // 渠道名/描述按当前语言展示；Android 重复创建同名 id 的渠道会覆盖旧文案
  static String get channelName => AppStrings.current.notifChannelName;
  // 关闭提示音时走这个无声渠道：Android 8+ 声音是渠道级属性，单条通知改不了
  static const String silentChannelId = 'keiyo_chat_messages_silent';
  static String get silentChannelName => AppStrings.current.notifChannelSilentName;
  static String get channelDescription => AppStrings.current.notifChannelDesc;
  static const String groupKey = 'keiyo_chat';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Future<void>? _initFuture;
  String? _launchPayload;

  /// 用户点击通知时回调，参数是会话 JSON（可直接给 Conversation.fromJson）
  void Function(String payload)? onTap;

  /// APP 由通知点击冷启动时携带的 payload，根路由登录后再消费
  String? get launchPayload => _launchPayload;

  static const InitializationSettings _settings = InitializationSettings(
    // 必须是单色剪影：Android 8+ 下 @mipmap/ic_launcher 解析到的是 adaptive-icon，
    // 拿它当通知小图标会被系统按 alpha 蒙版涂成整块白
    android: AndroidInitializationSettings('@drawable/ic_stat_keiyo'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );

  /// [handlesTap] 只有主 isolate 需要监听点击；后台 isolate 传 false。
  Future<void> ensureInitialized({bool handlesTap = true}) async {
    if (_initialized) return;
    // 并发调用共享同一次初始化；失败时清空缓存，下次调用可重试
    final running = _initFuture;
    if (running != null) {
      await running;
      return;
    }
    final future = _doInitialize(handlesTap);
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  Future<void> _doInitialize(bool handlesTap) async {
    await _plugin.initialize(
      _settings,
      onDidReceiveNotificationResponse: handlesTap ? _handleResponse : null,
    );
    if (handlesTap) {
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        if (details?.didNotificationLaunchApp == true) {
          _launchPayload = details?.notificationResponse?.payload;
        }
      } catch (_) {
        // 部分平台/版本拿不到启动详情，忽略
      }
    }
    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    onTap?.call(payload);
  }

  /// Android 8+ 必须先建渠道：FCM 下发的通知指定了 channel_id，
  /// 渠道不存在时系统会丢弃这条通知。主 isolate 与保活 isolate 都调用一次。
  ///
  /// 这里必须用默认的 handlesTap: true：main 在启动时就调用了本方法，
  /// 若此时以“不处理点击”的方式初始化，后续所有调用都会因已初始化而短路，
  /// 通知点击回调与冷启动 payload 就永远绑不上了。后台 isolate 没有 onTap，
  /// 绑定一个空回调无副作用。
  Future<void> ensureChannel() async {
    await ensureInitialized();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          silentChannelId,
          silentChannelName,
          description: channelDescription,
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
        ),
      );
    } catch (_) {}
  }

  /// 请求通知权限。Android 13+ / iOS 都会弹系统授权框。
  Future<bool> requestPermissions() async {
    await ensureInitialized();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {
      // 用户拒绝或系统不支持时不抛给页面
    }
    return false;
  }

  /// 展示一条会话新消息通知。同一个会话使用相同 id，后续消息会覆盖而不是堆叠。
  /// [playSound] 跟随菜单里的提示音开关：关闭时仍展示通知，只是不发声。
  Future<void> showMessage({
    required int id,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    int badge = 0,
    bool playSound = true,
  }) async {
    await ensureInitialized(handlesTap: false);
    final android = AndroidNotificationDetails(
      playSound ? channelId : silentChannelId,
      playSound ? channelName : silentChannelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: groupKey,
      channelShowBadge: true,
      enableVibration: true,
      playSound: playSound,
      ticker: title,
      number: badge,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      threadIdentifier: groupKey,
      badgeNumber: badge > 0 ? badge : null,
    );
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
      payload: jsonEncode(data),
    );
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// 退出登录 / 切换租户时清掉旧租户的通知，避免残留与 id 串台
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
