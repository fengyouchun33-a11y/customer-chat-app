import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/background_watch_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/sound_service.dart';

/// 全局会话状态：登录身份、当前租户、未读汇总、自动翻译开关。
/// 只负责"谁在用什么租户"，页面数据各自维护。
class AppState extends ChangeNotifier {
  AppState(this.api) {
    api.onUnauthorized = _handleUnauthorized;
    // 会话摘要（未读总数/预览）由全局 socket 推送，列表与角标共用
    realtime.convUpdates.listen(_onConvUpdated);
    // 推送点击与本地通知点击走同一条 pendingConversation 链路
    PushService.instance.onOpenConversation = openConversationFromMap;
    // FCM token 轮换后重新登记，否则会推到旧设备令牌上
    PushService.instance.onTokenChanged = _syncPush;
    // 保活 isolate 不能用 SharedPreferences，基线只能回传这里落盘
    BackgroundWatchService.addTaskDataCallback(_onWatchTaskData);
  }

  final ApiClient api;

  /// 管理端全局长连接：登录并选租户后建立，退出/换租户时重建
  final RealtimeService realtime = RealtimeService();

  SharedPreferences? _prefs;
  String _token = '';
  bool _restoring = true;

  /// 语言偏好：`system` 表示跟随系统，其余为 zh_CN / zh_TW / en 等语言码
  String _langPref = AppStrings.systemPref;

  AdminUser? admin;
  Tenant? tenant;
  int unreadTotal = 0;

  /// 服务器地址固定为正式域名，App 内不再提供修改入口
  String get baseUrl => AppConfig.defaultBaseUrl;

  bool _appInForeground = true;
  String? _openConvKey;
  Map<String, dynamic>? _pendingConversation;

  /// 前台心跳：保活 isolate 只能靠推过来的证据判断 APP 是否在前台，
  /// 所以证据必须持续刷新，而不是只在生命周期回调那一下发一次
  Timer? _watchBeat;

  /// 服务刚起来时把本地基线交给保活 isolate 几次，之后它自己会回写，不再搬
  int _watchSeedBeats = 0;

  bool get restoring => _restoring;

  /// 语言偏好值：`system` 或具体语言码
  String get languagePref => _langPref;

  /// MaterialApp 的 locale 覆盖值；null 即跟随系统
  Locale? get localeOverride =>
      _langPref == AppStrings.systemPref ? null : AppStrings.localeOf(_langPref);

  bool get isLoggedIn => admin != null;
  bool get isPlatform => admin?.isPlatform == true;
  bool get hasPendingConversation => _pendingConversation != null;
  bool get appInForeground => _appInForeground;

  /// 新消息提示音开关（菜单里切换，状态由 SoundService 落到本地）
  bool get soundEnabled => SoundService.instance.enabled;

  /// 平台超管登录后必须选一家租户才能进业务页（会话/统计都按租户过滤）
  bool get needTenantSelect => admin != null && isPlatform && tenant == null;

  Future<void> bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    // 语言偏好在登录前就要生效：登录页、错误提示和通知文案都依赖它
    _langPref = _prefs!.getString('keiyo_chat_lang') ?? AppStrings.systemPref;
    AppStrings.current = AppStrings.forCode(AppStrings.effectiveCode(_langPref));
    // 提示音开关存在本地，登录前就要能读，冷启动首条消息也不漏响
    await SoundService.instance.load();
    // 服务器地址已固定，清掉旧版本遗留的自定义地址配置
    await _prefs!.remove('keiyo_base_url');

    _token = _prefs!.getString('keiyo_token') ?? '';
    final adminRaw = _prefs!.getString('keiyo_admin');
    final tenantRaw = _prefs!.getString('keiyo_tenant');

    if (_token.isNotEmpty && adminRaw != null) {
      try {
        admin = AdminUser.fromJson(Map<String, dynamic>.from(jsonDecode(adminRaw) as Map));
        if (tenantRaw != null) {
          tenant = Tenant.fromJson(Map<String, dynamic>.from(jsonDecode(tenantRaw) as Map));
        }
        api.setAuth(token: _token, tenantId: tenant?.id ?? 0);
      } catch (_) {
        await _clearAuth();
      }
    } else {
      await _clearAuth();
    }

    _restoring = false;
    if (admin != null && tenant != null) {
      _watchSeedBeats = 5;
      unawaited(BackgroundWatchService.start());
      _pushWatchUiState();
      _connectRealtime();
      _syncPush();
    }
    notifyListeners();
  }

  Future<AdminUser> login(String account, String passwd) async {
    final data = await api.post('/admin/login', data: {'account': account.trim(), 'passwd': passwd});
    final m = Map<String, dynamic>.from((data ?? {}) as Map);
    final user = AdminUser.fromLogin(m);
    _token = (m['token'] ?? '').toString();
    if (_token.isEmpty) throw ApiException(-1, AppStrings.current.loginTokenMissing);

    admin = user;
    // 平台超管每次登录都要重新选租户；普通成员直接用自己所属租户
    if (user.isPlatform) {
      tenant = null;
    } else {
      final tid = user.currentTenantId > 0 ? user.currentTenantId : user.tenantId;
      final tname = user.currentTenantName.isNotEmpty ? user.currentTenantName : user.companyName;
      tenant = tid > 0 ? Tenant(id: tid, companyName: tname) : null;
    }
    api.setAuth(token: _token, tenantId: tenant?.id ?? 0);
    await _persistAuth();

    // 平台超管先不启动后台轮询，选完租户后再启用
    if (tenant != null) {
      await BackgroundWatchService.clearSnapshot();
      _watchSeedBeats = 5;
      await BackgroundWatchService.start();
      _pushWatchUiState();
      _connectRealtime();
      _syncPush();
    }

    // 补齐 auto_translate 等登录接口没给的偏好字段；失败不影响进入
    if (tenant != null) {
      try {
        await loadProfile();
      } catch (_) {}
    }
    notifyListeners();
    return user;
  }

  Future<void> loadProfile() async {
    final data = await api.get('/admin/profile');
    if (data is Map) {
      final fresh = AdminUser.fromProfile(Map<String, dynamic>.from(data));
      // 保留登录时拿到的 is_platform（profile 也有，直接用 fresh）
      admin = fresh;
      await _persistAuth();
      notifyListeners();
    }
  }

  Future<List<Tenant>> fetchTenants() async {
    final data = await api.get('/admin/tenant/options');
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => Tenant.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// 平台超管切换/首次选择租户：落库最近使用 + 更新请求头
  Future<Tenant> selectTenant(Tenant t) async {
    final data = await api.post('/admin/tenant/switch', data: {'tenant_id': t.id});
    final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    final picked = Tenant(
      id: asInt(m['id'], t.id),
      companyName: asString(m['company_name'], t.companyName),
    );
    tenant = picked;
    api.setAuth(token: _token, tenantId: picked.id);
    await _persistAuth();

    // 换租户后旧租户的通知与未读基线都失效
    _openConvKey = null;
    await BackgroundWatchService.clearSnapshot();
    unawaited(NotificationService.instance.cancelAll());
    _watchSeedBeats = 5;
    await BackgroundWatchService.start();
    _pushWatchUiState();
    // 会话房间与管理员房间都按租户识别，换租户必须重建连接
    _connectRealtime();
    _syncPush();
    notifyListeners();
    // 换租户后偏好/租户上下文都以新租户为准
    try {
      await loadProfile();
    } catch (_) {}
    return picked;
  }

  Future<void> setAutoTranslate(bool enabled) async {
    await api.post('/admin/profile/update', data: {'auto_translate': enabled ? 1 : 0});
    final current = admin;
    if (current != null) {
      admin = current.copyWith(autoTranslate: enabled);
      await _persistAuth();
      notifyListeners();
    }
  }

  /// 新消息提示音开关：只影响前台播放，不同步到服务端
  Future<void> setSoundEnabled(bool enabled) async {
    await SoundService.instance.setEnabled(enabled);
    notifyListeners();
  }

  /// 切换界面语言：`system` 跟随系统，其余为语言码。
  /// 选择落本地，后台 isolate 通过心跳下发拿到同一个语言。
  Future<void> setLanguage(String pref) async {
    if (pref == _langPref) return;
    _langPref = pref;
    AppStrings.current = AppStrings.forCode(AppStrings.effectiveCode(pref));
    await _prefs?.setString('keiyo_chat_lang', pref);
    // 立刻把新语言推给保活 isolate，后台通知不会停在旧语言上
    _pushWatchUiState();
    // 常驻通知是系统里已经发出去的那一条，只能主动刷新文案
    unawaited(BackgroundWatchService.refreshNotification());
    notifyListeners();
  }

  /// 客服上线/下线：只影响新会话的转人工分配，已接待的会话不受影响
  Future<void> setOnline(bool online) async {
    await api.post('/admin/profile/update', data: {'online_status': online ? 1 : 0});
    final current = admin;
    if (current != null) {
      admin = current.copyWith(onlineStatus: online);
      await _persistAuth();
      notifyListeners();
    }
  }

  Future<void> logout() async {
    // 客服退出即下线：否则人已经走了，新会话还会被优先派给他
    final current = admin;
    if (current != null && !current.isAdmin && current.onlineStatus) {
      try {
        await api.post('/admin/profile/update', data: {'online_status': 0});
      } catch (_) {}
    }
    // 先摘掉推送令牌：登出接口会让 token 失效，之后就无权注销了
    try {
      await PushService.instance.unregister(api);
    } catch (_) {}
    try {
      await api.post('/admin/logout');
    } catch (_) {
      // 令牌可能已过期，忽略
    }
    await _clearAuth();
    notifyListeners();
  }

  void setUnread(int n) {
    if (n == unreadTotal) return;
    unreadTotal = n;
    notifyListeners();
  }

  /// APP 前后台变化：后台保活任务据此决定是否弹通知
  void setAppForeground(bool foreground) {
    _appInForeground = foreground;
    if (foreground) {
      // 长时间挂起后 socket 可能已被系统断开，回前台补一次连接与推送登记
      _connectRealtime();
      _syncPush();
    } else {
      // 退后台立即停掉心跳：这一条 foreground:false 有可能被 ROM 截在半路，
      // 但只要心跳不再新鲜，isolate 超过窗口就会回到后台口径开始弹通知
      _watchBeat?.cancel();
      _watchBeat = null;
    }
    _pushWatchUiState();
    // 前后台切换是服务端“要不要发系统推送”的唯一凭据，不能等下一轮心跳：
    // 退后台那一下报迟了，中间来的消息就既没推送也没人看见
    realtime.reportPresence();
    // 后台不弹的唯一开关就在这一行上；日志里没进来说明生命周期回调没递到
    debugPrint('[watch] setAppForeground=$foreground beat=${_watchBeat?.isActive == true}');
  }

  /// 当前正在看的会话，同会话新消息不再弹通知
  void setOpenConversation(String? convKey) {
    _openConvKey = convKey;
    _pushWatchUiState();
  }

  void clearOpenConversation(String convKey) {
    if (_openConvKey != convKey) return;
    _openConvKey = null;
    _pushWatchUiState();
  }

  void _pushWatchUiState() {
    if (admin == null || tenant == null) return;
    _pushWatchContext();
    if (!_appInForeground) return;
    if (_watchBeat?.isActive == true) return;
    _watchBeat = Timer.periodic(const Duration(seconds: 2), (_) => _pushWatchContext());
  }

  /// 把登录态与偏好交给保活 isolate：它在自己的 isolate 里读不到
  /// SharedPreferences（JNI 实例只注册在主 isolate），不推过来就只能拿到空 token。
  void _pushWatchContext() {
    final t = tenant;
    if (t == null) return;
    String? seed;
    if (_watchSeedBeats > 0) {
      _watchSeedBeats--;
      final raw = _prefs?.getString(BackgroundWatchService.snapshotKey);
      seed = (raw == null || raw.isEmpty) ? '{}' : raw;
    }
    BackgroundWatchService.pushContext(
      foreground: _appInForeground,
      token: _token,
      tenantId: t.id,
      soundEnabled: SoundService.instance.enabled,
      pushRegistered: _prefs?.getBool(PushService.registeredKey) ?? false,
      lang: AppStrings.current.code,
      openConvKey: _openConvKey,
      baselineSeed: seed,
    );
  }

  void _onWatchTaskData(Map<Object?, Object?> data) {
    if (data['type'] != 'baseline') return;
    final json = data['json'];
    final prefs = _prefs;
    if (json is! String || prefs == null) return;
    unawaited(() async {
      await prefs.setString(BackgroundWatchService.snapshotKey, json);
      await prefs.setBool(BackgroundWatchService.readyKey, true);
    }());
  }

  /// 通知点击（本地通知 payload 或 FCM data），等根路由具备进入条件后由工作台消费
  void openConversationFromMap(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _pendingConversation = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  void openConversationFromNotification(String payload) {
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return;
      openConversationFromMap(Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  /// 服务端只推给有权限的管理员；平台超管可能同时收到其他租户的摘要，这里再滤一层
  void _onConvUpdated(Map<String, dynamic> payload) {
    final raw = payload['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final tid = asInt(data['tenant_id']);
    final myTenant = tenant?.id ?? 0;
    if (tid > 0 && myTenant > 0 && tid != myTenant) return;
    var total = asInt(data['total_unread']);
    final convKey = asString(data['conv_key']);
    // 正在看的会话马上会被沟通页清零，先扣掉避免角标闪一下
    if ((_openConvKey ?? '') == convKey) {
      total -= asInt(data['admin_unread']);
    }
    setUnread(total < 0 ? 0 : total);
    // 访客新消息（服务端只在 sender=visitor 时推 conv_updated）：前台按开关播提示音
    if (_appInForeground) unawaited(SoundService.instance.playNewMessage());
    // 前台也要在通知栏留痕。原先前台一律不弹，声音就只剩页面内 audioplayers 一根独木桥：
    // 它走 notification 音量通道，铃声音量被调低或被系统音频策略压住时表现为"完全没提示"，
    // 而横幅+渠道声音是盯着屏幕时唯一能同时看见听见的兜底。正在看的那条会话不打扰自己。
    if (_appInForeground &&
        asInt(data['admin_unread']) > 0 &&
        convKey.isNotEmpty &&
        convKey != (_openConvKey ?? '')) {
      unawaited(_notifyWhileForeground(data, total < 0 ? 0 : total));
    }
  }

  /// 前台横幅：与保活 isolate 用同一条渠道、同一个会话 id。
  /// 前后台各由 _appInForeground / _foreground 一侧判定，互斥所以不会弹两条；
  /// 真撞上同一会话也只是按 id 覆盖，不会在通知栏堆叠。
  Future<void> _notifyWhileForeground(Map<String, dynamic> data, int badge) async {
    final conv = Conversation.fromJson(data);
    final s = AppStrings.current;
    // 标题只放人名：会话标题是首条消息，拿来当人名会变成「你好 发来新消息」
    final name = conv.userName.trim().isNotEmpty ? conv.userName.trim() : s.visitor;
    final preview = conv.lastMsg.trim();
    final body = preview.isNotEmpty
        ? preview
        : s.unreadMessages('${conv.adminUnread > 0 ? conv.adminUnread : 1}');
    try {
      await NotificationService.instance.showMessage(
        id: conv.id > 0 ? conv.id : (conv.convKey.hashCode & 0x7fffffff),
        title: s.newMessageTitle(name),
        body: body,
        data: data,
        badge: badge,
        playSound: SoundService.instance.enabled,
      );
    } catch (_) {
      // 通知权限被拒时静默失败，角标与提示音不受影响
    }
  }

  void _connectRealtime() {
    final a = admin;
    final t = tenant;
    if (a == null || t == null || _token.isEmpty) {
      realtime.disconnect();
      return;
    }
    // 在线判定的口径：只有 APP 真在前台时才算“实时链路能弹出来”，服务端这时
    // 才不再补一条系统推送；退到后台就交回 FCM/APNs
    realtime.presenceActive = () => _appInForeground;
    if (realtime.presenceDeviceId.isEmpty) {
      unawaited(_fillPresenceDeviceId());
    }
    realtime.connect(baseUrl: baseUrl, token: _token, tenantId: t.id);
  }

  // 设备标识存在本地，读一次就够了；失败也不用重试，服务端按空串记一行也能判定
  Future<void> _fillPresenceDeviceId() async {
    try {
      realtime.presenceDeviceId = await PushService.instance.deviceId();
    } catch (_) {}
  }

  /// 把 FCM token 登记到当前账号；失败静默，下次登录/回前台再试
  void _syncPush() {
    final t = tenant;
    if (t == null) return;
    unawaited(PushService.instance.sync(api, tenantId: t.id));
  }

  Map<String, dynamic>? takePendingConversation() {
    final data = _pendingConversation;
    _pendingConversation = null;
    return data;
  }

  Future<void> _persistAuth() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('keiyo_token', _token);
    if (admin != null) {
      await _prefs!.setString('keiyo_admin', jsonEncode(admin!.toJson()));
    }
    if (tenant != null) {
      await _prefs!.setString('keiyo_tenant', jsonEncode(tenant!.toJson()));
    } else {
      await _prefs!.remove('keiyo_tenant');
    }
  }

  Future<void> _clearAuth() async {
    // 先摘推送令牌：logout 接口只让 admin token 失效，不处理设备 token
    if (_token.isNotEmpty) {
      try {
        await PushService.instance.unregister(api);
      } catch (_) {}
    }
    realtime.disconnect();
    _watchBeat?.cancel();
    _watchBeat = null;
    _watchSeedBeats = 0;
    _token = '';
    admin = null;
    tenant = null;
    unreadTotal = 0;
    _openConvKey = null;
    _pendingConversation = null;
    api.setAuth(token: null);

    // 退出/令牌失效时同步停掉常驻服务，避免无身份轮询与残留通知
    await BackgroundWatchService.stop();
    await BackgroundWatchService.clearSnapshot();
    unawaited(NotificationService.instance.cancelAll());

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove('keiyo_token');
    await _prefs!.remove('keiyo_admin');
    await _prefs!.remove('keiyo_tenant');
  }

  void _handleUnauthorized() {
    if (admin == null) return;
    // 请求回调里可能正处于页面构建/路由切换，延后一帧再改状态更安全
    scheduleMicrotask(() async {
      await _clearAuth();
      notifyListeners();
    });
  }
}
