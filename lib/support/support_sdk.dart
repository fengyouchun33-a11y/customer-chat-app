import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'support_config.dart';

/// Support SDK entry: resolve (or reuse) the fixed chat URL for the signed-in agent.
///
/// Same flow as supportWin.nvue:
/// 1. chat_url is cached and bound to the agent uid, so the same agent always
///    lands back in the same conversation;
/// 2. on cache miss, POST /api/open/conversation (X-App-Id/X-App-Key) to create/reuse;
/// 3. fall back to the anonymous link (header=0) so the entry never breaks.
class SupportSdk {
  SupportSdk._();
  static final SupportSdk instance = SupportSdk._();

  static const String _tag = '[support]';
  static const String _urlKey = 'support_chat_url';
  static const String _uidKey = 'support_chat_uid';
  static const String _convKeyKey = 'support_chat_conv_key';

  /// Chat URL for the current agent; null means hard failure (not configured, no fallback)
  Future<String?> resolveChatUrl(AdminUser admin) async {
    if (!SupportConfig.isConfigured) {
      debugPrint('$_tag appId/appKey not configured, cannot create fixed conversation');
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    // The cache must be bound to the current account: a different agent signing
    // in invalidates the old link, otherwise conversations would get crossed
    final cached = prefs.getString(_urlKey);
    if (cached != null &&
        cached.isNotEmpty &&
        prefs.getString(_uidKey) == admin.id.toString()) {
      // A link cached by an older build carries no require_info, and the H5 now
      // defaults the pre-chat form on, so normalize the cached value too.
      return _noGate(cached);
    }
    try {
      final url = await _createConv(admin, prefs);
      if (url != null) return url;
    } catch (e) {
      debugPrint('$_tag create conversation failed, falling back to anonymous link: $e');
    }
    // Cache the anonymous fallback per uid too, so every entry does not hit an
    // open API that is bound to fail
    return SupportConfig.fallbackUrl;
  }

  /// conv_key of the current conversation (for extensions such as unread badges); empty when absent
  Future<String> conversationKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_convKeyKey) ?? '';
  }

  /// Clear the cached conversation on logout so the next account never reuses it
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_uidKey);
    await prefs.remove(_convKeyKey);
  }

  /// The visitor H5 asks for a name/email before starting a chat by default
  /// (require_info). Agents are already signed in here, so the embedded page
  /// must opt out explicitly instead of relying on the H5 default.
  static String _noGate(String url) =>
      url.contains('require_info=') ? url : '$url&require_info=0';

  Future<String?> _createConv(AdminUser admin, SharedPreferences prefs) async {
    final userInfo = <String, dynamic>{
      // Server-side user_info is "overwrite only when present": send non-empty
      // fields only, empty values would wipe existing profile data
      if (admin.nickname.isNotEmpty || admin.name.isNotEmpty)
        'name': admin.nickname.isNotEmpty ? admin.nickname : admin.name,
      if (admin.account.isNotEmpty) 'account': admin.account,
      if (admin.account.isNotEmpty) 'email': admin.account,
      if (admin.avatar.isNotEmpty) 'avatar': admin.avatar,
    };
    final resp = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        // The open API is not under AppConfig.defaultBaseUrl and needs no admin auth headers
        headers: {
          'Content-Type': 'application/json',
          'X-App-Id': SupportConfig.appId,
          'X-App-Key': SupportConfig.appKey,
        },
      ),
    ).post<dynamic>(
      '${SupportConfig.apiBase}/api/open/conversation',
      data: {
        // Namespaced prefix avoids external_user_id collisions with other integrators
        'external_user_id': 'chatapp-${admin.id}',
        'user_info': userInfo,
        'lang': AppStrings.httpLanguageTag,
        'content': '',
        'theme': {
          'color': '#0A7FD4',
          'bg': '#0B1117',
          'header': 0,
          'title': '',
        },
      },
    );
    final body = resp.data;
    if (body is! Map || body['code'] != 0) {
      debugPrint('$_tag unexpected open API response: $body');
      return null;
    }
    final data = body['data'];
    final raw = (data is Map ? data['chat_url'] : null)?.toString() ?? '';
    if (raw.isEmpty) return null;
    final url = _noGate(raw);
    await prefs.setString(_urlKey, url);
    await prefs.setString(_uidKey, admin.id.toString());
    final convKey = (data['conv_key'] ?? '').toString();
    if (convKey.isNotEmpty) await prefs.setString(_convKeyKey, convKey);
    return url;
  }
}
