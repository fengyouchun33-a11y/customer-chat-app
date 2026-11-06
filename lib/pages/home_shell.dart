import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/background_watch_service.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'chat_page.dart';
import 'conversations_page.dart';
import 'stats_page.dart';
import 'tenant_select_page.dart';

/// 工作台外壳：底部两个 Tab（会话 / 统计），顶栏放租户、自动翻译与退出。
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
      // 冷启动时兜底再启动一次常驻服务（系统限制/首帧时序都可能导致首次启动失败）
      unawaited(BackgroundWatchService.start());
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
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启消息提醒'),
        content: Text(
          android
              ? '为了在后台及时收到访客消息，智能客服需要显示常驻通知并允许后台运行。\n\n建议同时允许忽略电池优化；部分手机还需在系统设置中允许自启动。'
              : '为了在通知栏收到访客消息，请允许通知权限。\n\niOS 的实时提醒由系统推送（APNs）负责，无需保持 APP 在后台运行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去开启'),
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
    var battery = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      battery = await BackgroundWatchService.requestBatteryOptimization();
    }
    await BackgroundWatchService.start();
    if (!mounted) return;

    final parts = <String>[granted ? '通知已开启' : '通知未授权'];
    if (defaultTargetPlatform == TargetPlatform.android) {
      parts.add(battery ? '后台运行已允许' : '后台运行未授权');
    }
    showSnack(context, parts.join('，'));

    if (!granted) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('通知未授权'),
          content: const Text('需要在系统设置里允许通知，才能在通知栏看到新消息。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('打开设置'),
            ),
          ],
        ),
      );
      if (open == true) await BackgroundWatchService.openSystemSettings();
    }
  }

  Future<void> _toggleSound() async {
    final state = context.read<AppState>();
    final next = !state.soundEnabled;
    await state.setSoundEnabled(next);
    if (!mounted) return;
    showSnack(context, next ? '已开启新消息提示音' : '已关闭新消息提示音');
    // 开启时试听一次，方便确认音量与音效
    if (next) unawaited(SoundService.instance.playNewMessage());
  }

  Future<void> _openTenantPicker() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TenantSelectPage()),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleTranslate() async {
    final state = context.read<AppState>();
    final next = !(state.admin?.autoTranslate ?? false);
    try {
      await state.setAutoTranslate(next);
      if (mounted) showSnack(context, next ? '已开启自动翻译' : '已关闭自动翻译');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().logout();
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
    final unread = state.unreadTotal;
    final tenantName = state.tenant?.companyName ?? '未选择租户';
    final autoTranslate = state.admin?.autoTranslate ?? false;
    final soundOn = state.soundEnabled;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '客服工作台',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.domain_outlined, size: 11, color: AppColors.textMute),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tenantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMute),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (state.isPlatform)
            IconButton(
              tooltip: '切换租户',
              onPressed: _openTenantPicker,
              icon: const Icon(Icons.swap_horiz, size: 20, color: AppColors.textDim),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textDim),
            onSelected: (v) {
              switch (v) {
                case 'translate':
                  _toggleTranslate();
                  break;
                case 'sound':
                  _toggleSound();
                  break;
                case 'tenant':
                  _openTenantPicker();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              _menuItem(
                'translate',
                autoTranslate ? Icons.translate : Icons.translate_outlined,
                autoTranslate ? '自动翻译：已开启' : '自动翻译：已关闭',
              ),
              _menuItem(
                'sound',
                soundOn ? Icons.volume_up : Icons.volume_off,
                soundOn ? '提示音：已开启' : '提示音：已关闭',
              ),
              if (state.isPlatform)
                _menuItem('tenant', Icons.swap_horiz, '切换租户'),
              const PopupMenuDivider(),
              _menuItem('logout', Icons.logout, '退出登录'),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [ConversationsPage(), StatsPage()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
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
            label: '会话',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: '统计',
          ),
        ],
      ),
    );
  }
}
