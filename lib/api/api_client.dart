import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../l10n/app_strings.dart';

/// 服务端统一返回 { code, msg, data }，非 0 一律抛这个异常，页面只负责提示。
class ApiException implements Exception {
  final int code;
  final String message;

  const ApiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 管理端 HTTP 客户端：自动带 X-Token / X-Tenant-Id，统一解包 data。
class ApiClient {
  ApiClient(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalize(baseUrl) + AppConfig.apiPrefix,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
          // 业务错误码由我们自己判断，不要让 Dio 把 4xx 直接抛成网络异常
          validateStatus: (status) => status != null && status < 500,
        ));

  final Dio _dio;

  String? _token;
  int _tenantId = 0;

  /// 登录过期回调，由 AppState 注入（清本地态并回登录页）
  void Function()? onUnauthorized;

  static String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  String get baseUrl => _dio.options.baseUrl;

  void setAuth({String? token, int tenantId = 0}) {
    _token = token;
    _tenantId = tenantId;
  }

  Options _options({Duration? receiveTimeout}) {
    final headers = <String, dynamic>{};
    if (_token != null && _token!.isNotEmpty) headers['X-Token'] = _token;
    // 平台超管的当前租户：登录/切换后由 AppState 写入，普通成员为 0 时不带
    if (_tenantId > 0) headers['X-Tenant-Id'] = '$_tenantId';
    return Options(
      headers: headers,
      receiveTimeout: receiveTimeout,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? receiveTimeout}) {
    return _request(() => _dio.get<dynamic>(path, queryParameters: _cleanQuery(query), options: _options(receiveTimeout: receiveTimeout)));
  }

  Future<dynamic> post(String path, {Object? data, Duration? receiveTimeout}) {
    return _request(() => _dio.post<dynamic>(path, data: data, options: _options(receiveTimeout: receiveTimeout)));
  }

  Map<String, dynamic>? _cleanQuery(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  Future<dynamic> _request(Future<Response<dynamic>> Function() run) async {
    try {
      final resp = await run();
      final body = resp.data;
      if (body is Map) {
        final m = Map<String, dynamic>.from(body);
        final code = (m['code'] is num) ? (m['code'] as num).toInt() : 0;
        if (code == -401) {
          onUnauthorized?.call();
          throw ApiException(
            code,
            (m['msg'] ?? AppStrings.current.sessionExpired).toString(),
          );
        }
        if (code != 0) {
          throw ApiException(code, (m['msg'] ?? AppStrings.current.requestFailed).toString());
        }
        return m['data'];
      }
      // 极少数非包装响应（例如网关错误页）
      if (resp.statusCode == 401) {
        onUnauthorized?.call();
        throw ApiException(-401, AppStrings.current.sessionExpired);
      }
      return body;
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        onUnauthorized?.call();
        throw ApiException(-401, AppStrings.current.sessionExpired);
      }
      throw ApiException(-1, _networkMessage(e));
    }
  }

  String _networkMessage(DioException e) {
    final s = AppStrings.current;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return s.networkTimeout;
      case DioExceptionType.connectionError:
        return s.cannotConnect;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final data = e.response?.data;
        if (data is Map && data['msg'] != null) return data['msg'].toString();
        return s.httpError('$status');
      default:
        return e.message ?? s.networkError;
    }
  }
}
