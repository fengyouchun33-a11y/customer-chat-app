import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/background_watch_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../support/support_sdk.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'chat_page.dart';
import 'conversations_page.dart';
import 'contacts_page.dart';
import 'more_page.dart';
import 'stats_page.dart';
import 'tenant_select_page.dart';

/// 工作台外壳：底部 Tab（会话 / 联系人 / 统计 / 更多），顶栏放租户切换与退出。
/// 联系人与 Web 后台同口径对全员开放：服务端 /admin/user/list 按客服授权项目收敛数据范围。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const String _keepAlivePromptKey = 'keiyo_keepalive_prompted';

  int _tab = 0;
  AppState? _state;
  bool _openingPending = false;
  bool _openedFromNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      _state = state;
      state.addListener(_onStateChanged);
      state.setAppForeground(true);
      _maybeOpenPending();
      _maybePromptKeepAlive();
    });
  }

  @override
  void dispose() {
    _state?.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (_state?.hasPendingConversation == true) {
      // 通知点击回调可能落在构建期间，延后一帧再导航
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeOpenPending();
      });
    }
  }

  /// 点通知进入指定会话；平台超管还没选租户时先留在选租户页
  Future<void> _maybeOpenPending() async {
    if (!mounted || _openingPending) return;
    final state = _state;
    if (state == null || !state.hasPendingConversation) return;
    final payload = state.takePendingConversation();
    if (payload == null) return;

    final tenantId = asInt(payload['tenant_id']);
    if (tenantId > 0 && tenantId != (state.tenant?.id ?? 0)) return;

    final conv = Conversation.fromJson(payload);
    if (conv.convKey.isEmpty) return;

    _openingPending = true;
    _openedFromNotification = true;
    try {
      if (!mounted) return;
      setState(() => _tab = 0);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ChatPage(conversation: conv)),
      );
    } finally {
      _openingPending = false;
    }
    // 打开会话期间可能又点了另一条通知：返回后继续消费
    if (mounted && _state?.hasPendingConversation == true) {
      unawaited(_maybeOpenPending());
    }
  }

  /// 首次进入工作台说明后台提醒；只提示一次，之后可从菜单重新授权
  Future<void> _maybePromptKeepAlive() async {
    // 从通知点进来的用户已经能收到提醒，不再弹引导
    if (_openedFromNotification) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keepAlivePromptKey) == true) return;
    await prefs.setBool(_keepAlivePromptKey, true);
    if (!mounted) return;

    final android = defaultTargetPlatform == TargetPlatform.android;
    final s = AppStrings.current;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.keepAliveTitle),
        content: Text(android ? s.keepAliveAndroidBody : s.keepAliveIosBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.goEnable),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _enableBackground();
    }
  }

  Future<void> _enableBackground() async {
    final granted = await NotificationService.instance.requestPermissions();
    if (!mounted) return;

    final s = AppStrings.current;
    showSnack(context, granted ? s.notifOn : s.notifOff);

    if (!granted) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.notifOff),
          content: Text(s.notifOffDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.openSettings),
            ),
          ],
        ),
      );
      if (open == true) await BackgroundWatchService.openSystemSettings();
    }
  }

  Future<void> _openTenantPicker() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TenantSelectPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _logout() async {
    final s = AppStrings.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.logout),
        content: Text(s.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.logoutAction),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // context must not be used after an await; capture the state first
      final state = context.read<AppState>();
      // The support conversation is bound to the account: clear the cache on
      // logout so the next one never inherits it
      await SupportSdk.instance.clear();
      await state.logout();
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textDim),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings.of(context);
    final unread = state.unreadTotal;
    final tenantName = state.tenant?.companyName ?? s.noTenantSelected;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.workbenchTitle,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.domain_outlined,
                  size: 11,
                  color: AppColors.textMute,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tenantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMute,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (state.isPlatform)
            IconButton(
              tooltip: s.switchTenant,
              onPressed: _openTenantPicker,
              icon: const Icon(
                Icons.swap_horiz,
                size: 20,
                color: AppColors.textDim,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textDim),
            onSelected: (v) {
              switch (v) {
                case 'tenant':
                  _openTenantPicker();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              if (state.isPlatform) ...[
                _menuItem('tenant', Icons.swap_horiz, s.switchTenant),
                const PopupMenuDivider(),
              ],
              _menuItem('logout', Icons.logout, s.logout),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _clampTab(_tab),
        children: const [
          ConversationsPage(),
          ContactsPage(),
          StatsPage(),
          MorePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _clampTab(_tab),
        onTap: (i) => setState(() => _tab = i),
        items: [
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unreadText(unread)),
              child: const Icon(Icons.forum_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unreadText(unread)),
              child: const Icon(Icons.forum),
            ),
            label: s.tabConversations,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_outline),
            activeIcon: const Icon(Icons.people),
            label: s.tabContacts,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.insights_outlined),
            activeIcon: const Icon(Icons.insights),
            label: s.tabStats,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.more_horiz),
            label: s.tabMore,
          ),
        ],
      ),
    );
  }

  /// Tab index clamp. The bar is a fixed 4 tabs (conv/contacts/stats/more),
  /// MorePage always last; clamping only guards a stale out-of-range index.
  int _clampTab(int tab) {
    return tab > 3 ? 3 : (tab < 0 ? 0 : tab);
  }
}
