import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/sound_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'chat_page.dart';

/// 会话队列：与管理端 ConversationList 左侧栏同口径
/// - 项目 / 状态 / 关键词筛选，pageSize=20
/// - 全局长连接（L1）推送会话摘要，未读秒级更新；5 秒静默轮询兜底
/// - 点条目进聊天页，返回后静默同步
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _poll;
  Timer? _rtDebounce;
  StreamSubscription<Map<String, dynamic>>? _convSub;
  StreamSubscription<Map<String, dynamic>>? _readSub;

  List<Conversation> _items = const [];
  List<Project> _projects = const [];
  int _page = 1;
  int _total = 0;
  int _status = -1;
  int _projectId = 0;
  String _keyword = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _polling = false;
  bool _togglingStatus = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 全局长连接（L1）：访客新消息的摘要按管理员房间实时下发
    final state = context.read<AppState>();
    _convSub = state.realtime.convUpdates.listen(_onRealtimeUpdate);
    _readSub = state.realtime.convReads.listen(_onRealtimeRead);
    _loadProjects();
    _refresh();
    _syncOnlineStatus();
    _poll = Timer.periodic(AppConfig.listPollInterval, (_) => _pollTick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _rtDebounce?.cancel();
    _convSub?.cancel();
    _readSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query(int page) => {
        'page': page,
        'pageSize': AppConfig.pageSize,
        'keyword': _keyword,
        if (_projectId > 0) 'project_id': _projectId,
        if (_status >= 0) 'status': _status,
      };

  List<Conversation> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _loadProjects() async {
    final api = context.read<AppState>().api;
    try {
      final data = await api.get('/admin/project/options');
      if (!mounted) return;
      setState(() {
        _projects = data is List
            ? data
                .whereType<Map>()
                .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [];
      });
    } catch (_) {
      // 项目下拉拿不到不阻塞会话列表，仍可按状态/关键词筛
    }
  }

  /// replaceList=false 时只刷新第一页与未读角标，不动已翻到后面的列表
  Future<void> _refresh({bool silent = false, bool replaceList = true}) async {
    final state = context.read<AppState>();
    try {
      final data = await state.api.get('/admin/conversation/list', query: _query(1));
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final list = _parseList(m['list']);
      final total = asInt(m['total']);
      if (!mounted) return;
      setState(() {
        if (replaceList) {
          _items = list;
          _page = 1;
        }
        _total = total;
        _loading = false;
        _error = null;
      });
      // 角标优先用服务端口径（不受筛选影响，与推送 total_unread 一致）；
      // 老版本服务端没有该字段时回退到最新一页求和
      final unreadTotal = m['unread_total'];
      final nextUnread = unreadTotal == null
          ? list.fold<int>(0, (sum, c) => sum + c.adminUnread)
          : asInt(unreadTotal);
      // 长连接断开时轮询兜底：未读总数增加同样说明来了新消息，按开关响提示音
      if (nextUnread > state.unreadTotal && state.appInForeground) {
        unawaited(SoundService.instance.playNewMessage());
      }
      state.setUnread(nextUnread);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = e.toString();
      });
      if (_items.isNotEmpty && !silent) {
        showSnack(context, e.toString(), error: true);
      }
    }
  }

  /// 服务端推送的会话摘要：先本地更新未读（秒级），再去重后静默拉一次列表补全字段与排序
  void _onRealtimeUpdate(Map<String, dynamic> payload) {
    if (!mounted) return;
    final raw = payload['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final tid = asInt(data['tenant_id']);
    final myTenant = context.read<AppState>().tenant?.id ?? 0;
    if (tid > 0 && myTenant > 0 && tid != myTenant) return;
    _applyUnread(data['conv_key'], data['admin_unread']);
    _scheduleRealtimeRefresh();
  }

  /// 同一账号其他设备读完了某会话：本机同步清未读
  void _onRealtimeRead(Map<String, dynamic> payload) {
    if (!mounted) return;
    _applyUnread(payload['conv_key'], 0);
    _scheduleRealtimeRefresh();
  }

  void _applyUnread(dynamic convKey, dynamic unread) {
    final key = asString(convKey);
    if (key.isEmpty) return;
    final idx = _items.indexWhere((c) => c.convKey == key);
    if (idx < 0) return;
    final next = [..._items];
    next[idx] = next[idx].copyWith(adminUnread: asInt(unread));
    setState(() => _items = next);
  }

  /// 短时间多条消息只拉一次，避免访客连续发消息时打满接口
  void _scheduleRealtimeRefresh() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _refresh(silent: true, replaceList: _page == 1);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    final next = _page + 1;
    final state = context.read<AppState>();
    setState(() => _loadingMore = true);
    try {
      final data = await state.api.get('/admin/conversation/list', query: _query(next));
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final list = _parseList(m['list']);
      if (!mounted) return;
      final exists = _items.map((e) => e.id).toSet();
      setState(() {
        _items = [..._items, ...list.where((c) => !exists.contains(c.id))];
        _page = next;
        _total = asInt(m['total'], _total);
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _pollTick() async {
    if (!mounted || _polling || _loading || _loadingMore) return;
    // 聊天页盖在上面时由它自己轮询，列表不重复打接口
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _polling = true;
    try {
      await _refresh(silent: true, replaceList: _page == 1);
    } finally {
      _polling = false;
    }
  }

  void _resetAndLoad() {
    setState(() {
      _page = 1;
      _items = const [];
      _total = 0;
      _loading = true;
      _error = null;
    });
    _refresh();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _refresh();
  }

  void _setStatus(int s) {
    if (_status == s) return;
    setState(() => _status = s);
    _resetAndLoad();
  }

  void _setProject(int id) {
    if (_projectId == id) return;
    setState(() => _projectId = id);
    _resetAndLoad();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // 同步清除按钮的显示
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final kw = value.trim();
      if (kw == _keyword) return;
      setState(() => _keyword = kw);
      _resetAndLoad();
    });
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    final kw = value.trim();
    if (kw == _keyword) return;
    setState(() => _keyword = kw);
    _resetAndLoad();
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _keyword = '';
      _status = -1;
      _projectId = 0;
    });
    _resetAndLoad();
  }

  Future<void> _openChat(Conversation c) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ChatPage(conversation: c)),
    );
    if (!mounted) return;
    // 聊天页读消息会清零未读，回复也可能改变状态/负责人
    await _refresh(silent: true, replaceList: _page == 1);
  }

  /// 客服的上线状态以服务端为准：本地缓存可能是旧值（比如在别的设备上下线过）
  Future<void> _syncOnlineStatus() async {
    final state = context.read<AppState>();
    final user = state.admin;
    if (user == null || user.isAdmin) return;
    try {
      await state.loadProfile();
    } catch (_) {
      // 拉不到就沿用本地缓存，不阻塞会话列表
    }
  }

  Future<void> _toggleOnline(bool current) async {
    if (_togglingStatus) return;
    final state = context.read<AppState>();
    final next = !current;
    setState(() => _togglingStatus = true);
    try {
      await state.setOnline(next);
      if (!mounted) return;
      final s = AppStrings.current;
      showSnack(context, next ? s.onlineOnToast : s.onlineOffToast);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _togglingStatus = false);
    }
  }

  /// 接单状态胶囊：在线绿点，离线灰点，点击切换
  Widget _onlinePill(bool online) {
    final busy = _togglingStatus;
    return GestureDetector(
      onTap: busy ? null : () => _toggleOnline(online),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: online ? AppColors.ok.withOpacity(0.14) : AppColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: online ? AppColors.ok.withOpacity(0.55) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: online ? AppColors.ok : AppColors.textMute,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              busy
                  ? AppStrings.current.switching
                  : (online ? AppStrings.current.online : AppStrings.current.offline),
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: online ? AppColors.ok : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final hasFilter = _keyword.isNotEmpty || _status >= 0 || _projectId > 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    s.conversationQueue,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.totalCount('$_total'),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMute),
                  ),
                  const Spacer(),
                  // 上线/下线只对客服有意义：管理员与平台超管不参与新会话分配
                  Consumer<AppState>(
                    builder: (context, state, _) {
                      final user = state.admin;
                      if (user == null || user.isAdmin) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _onlinePill(user.onlineStatus),
                      );
                    },
                  ),
                  if (hasFilter)
                    TextButton(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(s.resetFilters, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: s.searchConversationHint,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMute),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.clear,
                          onPressed: () {
                            _searchCtrl.clear();
                            _submitSearch('');
                          },
                          icon: const Icon(Icons.close, size: 16, color: AppColors.textMute),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    PillButton(
                      label: s.all,
                      selected: _status < 0,
                      onTap: () => _setStatus(-1),
                    ),
                    const SizedBox(width: 6),
                    PillButton(
                      label: s.statusActive,
                      selected: _status == 0,
                      onTap: () => _setStatus(0),
                    ),
                    const SizedBox(width: 6),
                    PillButton(
                      label: s.statusHuman,
                      selected: _status == 1,
                      onTap: () => _setStatus(1),
                    ),
                    const SizedBox(width: 6),
                    PillButton(
                      label: s.statusClosed,
                      selected: _status == 2,
                      onTap: () => _setStatus(2),
                    ),
                    const SizedBox(width: 10),
                    _buildProjectFilter(),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildProjectFilter() {
    final s = AppStrings.current;
    var label = s.allProjects;
    if (_projectId > 0) {
      label = s.projectFallback('$_projectId');
      for (final p in _projects) {
        if (p.id == _projectId) {
          label = p.name;
          break;
        }
      }
    }
    final active = _projectId > 0;
    return PopupMenuButton<int>(
      tooltip: s.projectFilter,
      onSelected: _setProject,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        PopupMenuItem<int>(value: 0, child: Text(s.allProjects)),
        ..._projects.map((p) => PopupMenuItem<int>(value: p.id, child: Text(p.name))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.14) : AppColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.accent.withOpacity(0.55) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: active ? AppColors.accentStrong : AppColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 14, color: AppColors.textMute),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: Icons.cloud_off_outlined,
            text: AppStrings.current.conversationLoadFailed,
            hint: _error,
            action: FilledButton.tonal(
              onPressed: _retry,
              child: Text(AppStrings.current.retry),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: Icons.forum_outlined,
              text: AppStrings.current.noConversations,
              hint: AppStrings.current.noConversationsHint,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _items.length) return _buildFooter();
          return _buildTile(_items[index]);
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_items.length < _total) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: Text(
              AppStrings.current.loadMore('${_items.length}', '$_total'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          AppStrings.current.allLoaded('$_total'),
          style: const TextStyle(fontSize: 11, color: AppColors.textMute),
        ),
      ),
    );
  }

  Widget _buildTile(Conversation c) {
    final closed = c.status == 2;
    final unread = c.adminUnread > 0;
    final s = AppStrings.current;
    final owner = c.agentName.isNotEmpty
        ? s.agentLabel(c.agentName)
        : (c.status == 1 ? s.unassigned : '');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openChat(c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: unread ? AppColors.accent.withOpacity(0.38) : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialAvatar(text: c.userLabel, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              color: closed ? AppColors.textDim : AppColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fmtTimeShort(c.lastMsgTime ?? c.createTime),
                          style: const TextStyle(fontSize: 10, color: AppColors.textMute),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c.userLabel} · ${c.projectName.isEmpty ? '-' : c.projectName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                          ),
                        ),
                        const SizedBox(width: 6),
                        StatusPill(status: c.status, compact: true),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadText(c.adminUnread),
                              style: const TextStyle(
                                fontSize: 9.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (owner.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.headset_mic_outlined,
                            size: 11,
                            color: c.status == 1 ? AppColors.signal : AppColors.textMute,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            owner,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: c.status == 1 ? AppColors.signal : AppColors.textMute,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
