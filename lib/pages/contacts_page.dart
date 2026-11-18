import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'chat_page.dart';

/// 联系人页：与 Web 管理端 UserList 同口径
/// - 关键词 / 项目筛选，pageSize=20 分页；数据来自 /admin/user/list（仅租户管理员可见此 tab）
/// - 联系人由开放接口 user_info 同步创建，本页只维护展示资料（编辑/删除/打开会话）
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Contact> _items = const [];
  List<Project> _projects = const [];
  int _page = 1;
  int _total = 0;
  int _projectId = 0;
  String _keyword = '';
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query(int page) => {
        'page': page,
        'pageSize': AppConfig.pageSize,
        'keyword': _keyword,
        if (_projectId > 0) 'project_id': _projectId,
      };

  List<Contact> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Contact.fromJson(Map<String, dynamic>.from(e)))
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
      // 项目下拉拿不到不阻塞联系人列表
    }
  }

  Future<void> _refresh() async {
    final api = context.read<AppState>().api;
    try {
      final data = await api.get('/admin/user/list', query: _query(1));
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final list = _parseList(m['list']);
      final total = asInt(m['total']);
      if (!mounted) return;
      setState(() {
        _items = list;
        _page = 1;
        _total = total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = e.toString();
      });
      if (_items.isNotEmpty) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    final next = _page + 1;
    final api = context.read<AppState>().api;
    setState(() => _loadingMore = true);
    try {
      final data = await api.get('/admin/user/list', query: _query(next));
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
      _projectId = 0;
    });
    _resetAndLoad();
  }

  void _applyUpdate(Contact next) {
    if (!mounted) return;
    final idx = _items.indexWhere((c) => c.id == next.id);
    if (idx < 0) return;
    setState(() {
      final list = [..._items];
      list[idx] = next;
      _items = list;
    });
  }

  /// 打开该联系人的会话：按 user_id 查最新一条，直接进聊天页（与管理端「打开会话」同跳转）
  Future<void> _openConversation(Contact c) async {
    final api = context.read<AppState>().api;
    final s = AppStrings.current;
    try {
      final data = await api.get('/admin/conversation/list',
          query: {'page': 1, 'pageSize': 1, 'user_id': c.id});
      final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
      final raw = m['list'];
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <Conversation>[];
      if (!mounted) return;
      if (list.isEmpty) {
        showSnack(context, s.noConversations, error: true);
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ChatPage(conversation: list.first)),
      );
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  /// 编辑资料：字段与 /admin/user/update 白名单一致（外部用户ID只读）
  Future<void> _showEditSheet(Contact c) async {
    final api = context.read<AppState>().api;
    final s = AppStrings.current;
    final accountCtrl = TextEditingController(text: c.account);
    final nameCtrl = TextEditingController(text: c.name);
    final phoneCtrl = TextEditingController(text: c.phone);
    final emailCtrl = TextEditingController(text: c.email);
    final remarkCtrl = TextEditingController(text: c.remark);
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> save() async {
              if (saving) return;
              setSheetState(() => saving = true);
              try {
                await api.post('/admin/user/update', data: {
                  'id': c.id,
                  'account': accountCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'remark': remarkCtrl.text.trim(),
                });
                _applyUpdate(c.copyWith(
                  account: accountCtrl.text.trim(),
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  remark: remarkCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                showSnack(context, s.contactSaved);
              } catch (e) {
                setSheetState(() => saving = false);
                if (ctx.mounted) showSnack(ctx, e.toString(), error: true);
              }
            }

            Widget field(String label, TextEditingController ctrl,
                {bool enabled = true, TextInputType? keyboard, int maxLines = 1}) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctrl,
                  enabled: enabled,
                  maxLines: maxLines,
                  keyboardType: keyboard,
                  decoration: InputDecoration(
                    labelText: label,
                    isDense: true,
                    labelStyle: const TextStyle(fontSize: 12, color: AppColors.textMute),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      s.editContact,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        field(s.userExternalId, TextEditingController(text: c.externalUserId), enabled: false),
                        field(s.userAccount, accountCtrl),
                        field(s.userName, nameCtrl),
                        field(s.userPhone, phoneCtrl, keyboard: TextInputType.phone),
                        field(s.userEmail, emailCtrl, keyboard: TextInputType.emailAddress),
                        field(s.userRemark, remarkCtrl, maxLines: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: Text(s.cancel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving ? null : save,
                          child: Text(s.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    accountCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    remarkCtrl.dispose();
  }

  /// 详情面板：字段与 Web 列表一致，值可点选复制；底部操作 打开会话/编辑/删除
  void _showDetailSheet(Contact c) {
    final s = AppStrings.current;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        Widget row(String label, String value, {bool copyable = true}) {
          final empty = value.isEmpty;
          final text = empty ? '-' : value;
          return InkWell(
            onTap: copyable && !empty
                ? () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (sheetCtx.mounted) {
                      showSnack(sheetCtx, AppStrings.of(sheetCtx).copied);
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMute, height: 1.5),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: empty ? AppColors.textMute : AppColors.text,
                        decoration: copyable && !empty ? TextDecoration.underline : null,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: AppColors.textMute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    UserAvatar(text: c.displayName, url: c.avatar, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    _statusPill(c.status == 1),
                  ],
                ),
                const SizedBox(height: 6),
                row(s.userName, c.name),
                row(s.userAccount, c.account),
                row(s.userPhone, c.phone, copyable: false),
                row(s.userEmail, c.email),
                row(s.userExternalId, c.externalUserId),
                row(s.userProject, c.projects),
                row(s.userRegTime, fmtDateTime(c.createTime), copyable: false),
                row(s.userRemark, c.remark),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _openConversation(c);
                        },
                        child: Text(s.openConversation),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _showEditSheet(c);
                        },
                        child: Text(s.editContact),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 列表项不再展示启用/停用状态（contactEnabled/Disabled 仅详情面板用）
  Widget _statusPill(bool enabled) {
    final color = enabled ? AppColors.ok : AppColors.textMute;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        enabled ? AppStrings.current.contactEnabled : AppStrings.current.contactDisabled,
        style: TextStyle(fontSize: 10, height: 1.2, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final hasFilter = _keyword.isNotEmpty || _projectId > 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    s.tabContacts,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.totalCount('$_total'),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMute),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 6),
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: s.contactsSearchHint,
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
              Row(
                children: [
                  _buildProjectFilter(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.contactsSyncTip,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMute,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
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
            text: AppStrings.current.contactsLoadFailed,
            hint: _error,
            action: FilledButton.tonal(
              onPressed: () => _refresh(),
              child: Text(AppStrings.current.retry),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: Icons.people_outline,
              text: AppStrings.current.contactsEmpty,
              hint: AppStrings.current.contactsSyncTip,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
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

  Widget _buildTile(Contact c) {
    final sub = c.phone.isNotEmpty
        ? c.phone
        : (c.email.isNotEmpty
            ? c.email
            : (c.account.isNotEmpty ? c.account : c.externalUserId));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailSheet(c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              UserAvatar(text: c.displayName, url: c.avatar, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.displayName,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fmtTimeShort(c.createTime),
                          style: const TextStyle(fontSize: 10, color: AppColors.textMute),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub.isEmpty ? '-' : sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (c.projects.isNotEmpty)
                          Flexible(
                            child: Text(
                              c.projects,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
                            ),
                          ),
                      ],
                    ),
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
