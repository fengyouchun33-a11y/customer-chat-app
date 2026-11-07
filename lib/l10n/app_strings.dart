import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strings_ar.dart';
import 'strings_de.dart';
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_fr.dart';
import 'strings_ja.dart';
import 'strings_ko.dart';
import 'strings_pt.dart';
import 'strings_ru.dart';
import 'strings_zh_cn.dart';
import 'strings_zh_tw.dart';

/// 轻量本地化：不依赖 ARB 生成代码，词条以 key→文案 的形式放在
/// [strings_*.dart] 中。页面里用 `AppStrings.of(context)` 取当前语言，
/// 后台 isolate / 网络层等没有 BuildContext 的场景用 `AppStrings.current`。
class AppStrings {
  const AppStrings._(this.code, this._map);

  final String code;
  final Map<String, String> _map;

  static const Map<String, Map<String, String>> _all = {
    'zh_CN': zhCnStrings,
    'zh_TW': zhTwStrings,
    'en': enStrings,
    'ja': jaStrings,
    'ko': koStrings,
    'es': esStrings,
    'fr': frStrings,
    'de': deStrings,
    'pt': ptStrings,
    'ru': ruStrings,
    'ar': arStrings,
  };

  static const Map<String, String> _nativeNames = {
    'zh_CN': '简体中文',
    'zh_TW': '繁體中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'ru': 'Русский',
    'ar': 'العربية',
  };

  /// 语言偏好里表示“跟随系统”的值
  static const String systemPref = 'system';

  static const List<Locale> supportedLocales = [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('pt'),
    Locale('ru'),
    Locale('ar'),
  ];

  /// 当前生效的本地化对象。主 isolate 由 delegate load 更新，
  /// 后台 isolate / 网络层由调用方显式设置。
  static AppStrings current = forCode('zh_CN');

  static AppStrings forCode(String? code) {
    final normalized = _all.containsKey(code) ? code! : 'zh_CN';
    return AppStrings._(normalized, _all[normalized]!);
  }

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ?? current;
  }

  static String nativeName(String code) => _nativeNames[code] ?? code;

  static List<String> get supportedCodes => _all.keys.toList();

  /// 把系统 locale 归一化为内置语言码；未支持的语言回落到英文。
  static String codeOf(Locale locale) {
    if (locale.languageCode == 'zh') {
      final country = (locale.countryCode ?? '').toUpperCase();
      final isTraditional = locale.scriptCode == 'Hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO';
      return isTraditional ? 'zh_TW' : 'zh_CN';
    }
    if (_all.containsKey(locale.languageCode)) return locale.languageCode;
    return 'en';
  }

  static Locale localeOf(String code) {
    switch (code) {
      case 'zh_CN':
        return const Locale('zh', 'CN');
      case 'zh_TW':
        return const Locale('zh', 'TW');
      default:
        return _all.containsKey(code) ? Locale(code) : const Locale('en');
    }
  }

  /// 把持久化的语言偏好（`system` 或语言码）解析成实际语言码。
  static String effectiveCode(String? pref) {
    if (pref == null || pref.isEmpty || pref == systemPref) {
      return codeOf(WidgetsBinding.instance.platformDispatcher.locale);
    }
    return _all.containsKey(pref) ? pref : codeOf(WidgetsBinding.instance.platformDispatcher.locale);
  }

  /// MaterialApp 的系统语言解析回调：按语言匹配，并处理 zh 的简繁之分。
  static Locale? resolveSystemLocales(List<Locale>? locales, Iterable<Locale> supported) {
    if (locales == null || locales.isEmpty) return null;
    return localeOf(codeOf(locales.first));
  }

  String _t(String key) => _map[key] ?? enStrings[key] ?? key;

  String _fmt(String key, List<String> args) {
    var text = _t(key);
    for (var i = 0; i < args.length; i++) {
      text = text.replaceFirst('{$i}', args[i]);
    }
    return text;
  }

  // 通用
  String get appName => _t('appName');
  String get workbenchTitle => _t('workbenchTitle');
  String get cancel => _t('cancel');
  String get retry => _t('retry');
  String get close => _t('close');
  String get later => _t('later');
  String get logout => _t('logout');
  String get logoutConfirm => _t('logoutConfirm');
  String get logoutAction => _t('logoutAction');
  String get followSystem => _t('followSystem');
  String get language => _t('language');
  String languageMenu(String name) => _fmt('languageMenu', [name]);

  // 登录
  String get loginSubtitle => _t('loginSubtitle');
  String get account => _t('account');
  String get password => _t('password');
  String get showPassword => _t('showPassword');
  String get hidePassword => _t('hidePassword');
  String get loginButton => _t('loginButton');
  String get loginEmptyError => _t('loginEmptyError');
  String get loginTokenMissing => _t('loginTokenMissing');

  // 租户
  String get selectTenantTitle => _t('selectTenantTitle');
  String get searchTenantHint => _t('searchTenantHint');
  String platformAdmin(String name) => _fmt('platformAdmin', [name]);
  String get tenantSelectHint => _t('tenantSelectHint');
  String get tenantLoadFailed => _t('tenantLoadFailed');
  String get noTenants => _t('noTenants');
  String get noMatchingTenants => _t('noMatchingTenants');
  String get noTenantsHint => _t('noTenantsHint');
  String get tryAnotherKeyword => _t('tryAnotherKeyword');
  String get tenantSwitchHint => _t('tenantSwitchHint');
  String tenantFallback(String id) => _fmt('tenantFallback', [id]);
  String get currentTenant => _t('currentTenant');
  String tenantIdLabel(String id) => _fmt('tenantIdLabel', [id]);
  String get noTenantSelected => _t('noTenantSelected');

  // 工作台
  String get keepAliveTitle => _t('keepAliveTitle');
  String get keepAliveAndroidBody => _t('keepAliveAndroidBody');
  String get keepAliveIosBody => _t('keepAliveIosBody');
  String get goEnable => _t('goEnable');
  String get notifOn => _t('notifOn');
  String get notifOff => _t('notifOff');
  String get bgOn => _t('bgOn');
  String get bgOff => _t('bgOff');
  String get listSeparator => _t('listSeparator');
  String get notifOffDialogBody => _t('notifOffDialogBody');
  String get openSettings => _t('openSettings');
  String get soundOnToast => _t('soundOnToast');
  String get soundOffToast => _t('soundOffToast');
  String get translateOnToast => _t('translateOnToast');
  String get translateOffToast => _t('translateOffToast');
  String get switchTenant => _t('switchTenant');
  String get autoTranslateOn => _t('autoTranslateOn');
  String get autoTranslateOff => _t('autoTranslateOff');
  String get soundMenuOn => _t('soundMenuOn');
  String get soundMenuOff => _t('soundMenuOff');
  String get tabConversations => _t('tabConversations');
  String get tabStats => _t('tabStats');

  // 状态
  String get statusActive => _t('statusActive');
  String get statusHuman => _t('statusHuman');
  String get statusClosed => _t('statusClosed');
  String get statusUnknown => _t('statusUnknown');
  String get all => _t('all');
  String get allProjects => _t('allProjects');
  String get projectFilter => _t('projectFilter');
  String projectFallback(String id) => _fmt('projectFallback', [id]);

  // 会话列表
  String get onlineOnToast => _t('onlineOnToast');
  String get onlineOffToast => _t('onlineOffToast');
  String get switching => _t('switching');
  String get online => _t('online');
  String get offline => _t('offline');
  String get conversationQueue => _t('conversationQueue');
  String totalCount(String n) => _fmt('totalCount', [n]);
  String get resetFilters => _t('resetFilters');
  String get searchConversationHint => _t('searchConversationHint');
  String get clear => _t('clear');
  String get conversationLoadFailed => _t('conversationLoadFailed');
  String get noConversations => _t('noConversations');
  String get noConversationsHint => _t('noConversationsHint');
  String loadMore(String loaded, String total) => _fmt('loadMore', [loaded, total]);
  String allLoaded(String n) => _fmt('allLoaded', [n]);
  String agentLabel(String name) => _fmt('agentLabel', [name]);
  String get unassigned => _t('unassigned');

  // 聊天
  String get senderAgent => _t('senderAgent');
  String get senderAi => _t('senderAi');
  String get senderSystem => _t('senderSystem');
  String get imageUploadFailed => _t('imageUploadFailed');
  String maxImages(String n) => _fmt('maxImages', [n]);
  String imagesTooLarge(String n) => _fmt('imagesTooLarge', [n]);
  String pickImageFailed(String e) => _fmt('pickImageFailed', [e]);
  String get imagePlaceholder => _t('imagePlaceholder');
  String get imageLoadFailed => _t('imageLoadFailed');
  String get closeConversation => _t('closeConversation');
  String get closeConversationBody => _t('closeConversationBody');
  String get conversationClosed => _t('conversationClosed');
  String get conversationReopened => _t('conversationReopened');
  String historyForms(String n) => _fmt('historyForms', [n]);
  String get noForms => _t('noForms');
  String get formData => _t('formData');
  String get refreshMessages => _t('refreshMessages');
  String get reopenConversation => _t('reopenConversation');
  String newMessages(String n) => _fmt('newMessages', [n]);
  String get messageLoadFailed => _t('messageLoadFailed');
  String get noMessages => _t('noMessages');
  String get noMessagesHint => _t('noMessagesHint');
  String get loadOlder => _t('loadOlder');
  String formTag(String id) => _fmt('formTag', [id]);
  String get showTranslation => _t('showTranslation');
  String get showOriginal => _t('showOriginal');
  String formSubmitNo(String n) => _fmt('formSubmitNo', [n]);
  String get formParseFailed => _t('formParseFailed');
  String openLinkFailed(String uri) => _fmt('openLinkFailed', [uri]);
  String get closedBarHint => _t('closedBarHint');
  String get replyHint => _t('replyHint');

  // 统计
  String get summaryUpdated => _t('summaryUpdated');
  String daysRange(String n) => _fmt('daysRange', [n]);
  String get kpiConversations => _t('kpiConversations');
  String kpiConversationsSub(String days) => _fmt('kpiConversationsSub', [days]);
  String get kpiAiAnswers => _t('kpiAiAnswers');
  String kpiAiSub(String avg) => _fmt('kpiAiSub', [avg]);
  String get kpiHuman => _t('kpiHuman');
  String kpiHumanSubWithRate(String rate, String transfers) =>
      _fmt('kpiHumanSubWithRate', [rate, transfers]);
  String kpiHumanSubNoRate(String transfers) => _fmt('kpiHumanSubNoRate', [transfers]);
  String get kpiKb => _t('kpiKb');
  String kpiKbSub(String searches, String hits) => _fmt('kpiKbSub', [searches, hits]);
  String get kpiKbEmpty => _t('kpiKbEmpty');
  String get chartConvTitle => _t('chartConvTitle');
  String get chartConvTip => _t('chartConvTip');
  String get legendNewConv => _t('legendNewConv');
  String get legendAiAnswer => _t('legendAiAnswer');
  String get chartHumanTitle => _t('chartHumanTitle');
  String get chartHumanTip => _t('chartHumanTip');
  String get legendHumanConv => _t('legendHumanConv');
  String get legendTransfer => _t('legendTransfer');
  String get legendHuman => _t('legendHuman');
  String get legendTransferShort => _t('legendTransferShort');
  String get chartKbTitle => _t('chartKbTitle');
  String get chartKbTip => _t('chartKbTip');
  String get legendKbSearch => _t('legendKbSearch');
  String get legendKbHit => _t('legendKbHit');
  String get noDataInRange => _t('noDataInRange');
  String get tooltipSearch => _t('tooltipSearch');
  String get tooltipHit => _t('tooltipHit');
  String get keywordsTitle => _t('keywordsTitle');
  String get keywordsTip => _t('keywordsTip');
  String get keywordsEmpty => _t('keywordsEmpty');
  String get topKbTitle => _t('topKbTitle');
  String get topKbTip => _t('topKbTip');
  String get topKbEmpty => _t('topKbEmpty');
  String get summaryTitle => _t('summaryTitle');
  String get summaryTip => _t('summaryTip');
  String get genSummary => _t('genSummary');
  String summaryMeta(String model, String time) => _fmt('summaryMeta', [model, time]);
  String get summaryLoading => _t('summaryLoading');
  String get summaryEmpty => _t('summaryEmpty');
  String get summaryNote => _t('summaryNote');

  // 错误
  String get sessionExpired => _t('sessionExpired');
  String get requestFailed => _t('requestFailed');
  String get networkTimeout => _t('networkTimeout');
  String get cannotConnect => _t('cannotConnect');
  String httpError(String status) => _fmt('httpError', [status]);
  String get networkError => _t('networkError');

  // 通知
  String get notifChannelName => _t('notifChannelName');
  String get notifChannelSilentName => _t('notifChannelSilentName');
  String get notifChannelDesc => _t('notifChannelDesc');
  String get fgChannelName => _t('fgChannelName');
  String get fgChannelDesc => _t('fgChannelDesc');
  String get fgNotificationText => _t('fgNotificationText');
  String get visitor => _t('visitor');
  String unreadMessages(String n) => _fmt('unreadMessages', [n]);
  String newMessageTitle(String name) => _fmt('newMessageTitle', [name]);

  // 其他
  String yesterday(String time) => _fmt('yesterday', [time]);
}

/// 把 [AppStrings] 挂到 Localizations 树上，语言变化时整棵页面树会重建。
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) {
    final strings = AppStrings.forCode(AppStrings.codeOf(locale));
    AppStrings.current = strings;
    return SynchronousFuture<AppStrings>(strings);
  }

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
