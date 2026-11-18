import 'package:permission_handler/permission_handler.dart';

/// 后台消息提醒现在完全交由 FCM (Android) / APNs (iOS) 系统推送负责，
/// 不再使用前台服务保活。本类仅保留通知权限引导等辅助功能。
class BackgroundWatchService {
  BackgroundWatchService._();

  /// 兼容旧调用点（main.dart），保留空壳。
  static void init() {}

  /// 兼容旧调用点（app_state、home_shell），保留空壳。
  static Future<void> start() async {}

  /// 兼容旧调用点，保留空壳。
  static Future<void> stop() async {}

  static Future<void> refreshNotification() async {}

  static Future<void> clearSnapshot() async {}

  static void pushContext({
    required bool foreground,
    required String token,
    required int tenantId,
    required bool soundEnabled,
    required bool pushRegistered,
    String? lang,
    String? openConvKey,
    String? baselineSeed,
  }) {}

  static void addTaskDataCallback(void Function(Map<Object?, Object?> data) onMessage) {}

  static Future<bool> requestBatteryOptimization() async => false;

  static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}
