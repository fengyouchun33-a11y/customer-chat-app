/// 全局常量。
///
/// 服务器地址固定为正式域名，App 内不提供修改入口。
class AppConfig {
  /// 正式服务器地址（固定值）。本地联调需要换地址时改这一行重新打包。
  static const String defaultBaseUrl = 'https://support.breathmeters.net';

  /// 管理端接口统一前缀，与 keiyo-chat-server 的 router 一致
  static const String apiPrefix = '/api';

  static const int pageSize = 20;
  static const Duration listPollInterval = Duration(seconds: 5);
  static const Duration chatPollInterval = Duration(seconds: 5);

  /// 生成 AI 总结要现场跑大模型，和服务端一样给足 90 秒
  static const Duration summaryTimeout = Duration(seconds: 90);

  static const int statRangeDays = 30;
  static const List<int> statRanges = [7, 30, 90];
}
