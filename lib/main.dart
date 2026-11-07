import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'config/app_config.dart';
import 'l10n/app_strings.dart';
import 'services/background_watch_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先恢复语言偏好：通知渠道名、常驻通知文案在初始化时就要用对语言
  final prefs = await SharedPreferences.getInstance();
  AppStrings.current = AppStrings.forCode(
    AppStrings.effectiveCode(prefs.getString('keiyo_chat_lang')),
  );

  // 初始化前台服务与本地通知通道（必须在 runApp 之前）
  BackgroundWatchService.init();
  // FCM 后台入口必须在 runApp 之前注册；没配 Firebase 也不会报错
  PushService.registerBackgroundHandler();
  try {
    await NotificationService.instance.ensureChannel();
  } catch (_) {
    // 平台不支持通知时不影响 APP 正常使用
  }

  final state = AppState(ApiClient(AppConfig.defaultBaseUrl));

  // 通知点击（含冷启动）统一交给 AppState，等登录/选租户完成后由工作台打开会话
  NotificationService.instance.onTap = state.openConversationFromNotification;
  final launchPayload = NotificationService.instance.launchPayload;
  if (launchPayload != null && launchPayload.isNotEmpty) {
    state.openConversationFromNotification(launchPayload);
  }

  // 初始化 Firebase：未提供 google-services.json / GoogleService-Info.plist 时
  // 会在内部静默失败，socket + 轮询继续保持可用
  unawaited(PushService.instance.init());

  // 恢复本地登录态；完成后 AppState 通知根路由切换页面
  unawaited(state.bootstrap());

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const ChatApp(),
    ),
  );
}
