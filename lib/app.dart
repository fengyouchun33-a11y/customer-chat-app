import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'pages/tenant_select_page.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能客服',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const _RootGate(),
    );
  }
}

/// 根路由只做三件事：
/// 未登录 → 登录页；平台超管未选租户 → 强制选租户；其余 → 工作台。
/// 同时把前后台状态同步给后台保活任务，避免在看消息时还弹通知。
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前后台判定是后台提醒的唯一开关，它没触发的话心跳会永远报“在前台”
    debugPrint('[lifecycle] $state');
    context.read<AppState>().setAppForeground(
          state == AppLifecycleState.resumed,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.restoring) return const _SplashPage();
        if (state.admin == null) return const LoginPage();
        if (state.needTenantSelect) return const TenantSelectPage(mandatory: true);
        // 切换租户后整棵工作台重建，会话/统计按新租户重新拉取
        return HomeShell(key: ValueKey<int>(state.tenant?.id ?? 0));
      },
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 56),
            SizedBox(height: 18),
            Text(
              '智能客服',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
