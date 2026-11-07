import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  final FocusNode _pwdFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _pwdCtrl.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final account = _accountCtrl.text.trim();
    final passwd = _pwdCtrl.text;
    if (account.isEmpty || passwd.isEmpty) {
      setState(() => _error = AppStrings.current.loginEmptyError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // 成功后根路由会切到租户选择（平台超管）或工作台
      await context.read<AppState>().login(account, passwd);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static const String _registerUrl = 'https://support.breathmeters.net/';

  /// 平台介绍：底部弹层，纯展示
  void _showIntro() {
    final s = AppStrings.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.loginIntroEntry,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  s.introBody,
                  style: const TextStyle(
                      fontSize: 13, height: 1.8, color: AppColors.textMute),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(s.close),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _showRegister();
                        },
                        child: Text(s.loginRegisterEntry),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 企业注册：引导到 PC 浏览器，并提供链接复制
  Future<void> _showRegister() async {
    final s = AppStrings.of(context);
    final shouldCopy = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(
          s.loginRegisterEntry,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.registerBody,
              style: const TextStyle(
                  fontSize: 13, height: 1.8, color: AppColors.textMute),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const SelectableText(
                _registerUrl,
                style: TextStyle(fontSize: 12.5, color: AppColors.accentStrong),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.copyLink),
          ),
        ],
      ),
    );
    if (shouldCopy != true) return;
    await Clipboard.setData(const ClipboardData(text: _registerUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.linkCopied),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _TechBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const BrandMark(size: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.appName,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s.loginSubtitle,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.textMute),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: s.language,
                            onPressed: () => showLanguagePicker(context),
                            icon: const Icon(Icons.language,
                                size: 20, color: AppColors.textMute),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _accountCtrl,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              onSubmitted: (_) => _pwdFocus.requestFocus(),
                              decoration: InputDecoration(
                                hintText: s.account,
                                prefixIcon: const Icon(Icons.person_outline,
                                    size: 18, color: AppColors.textMute),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pwdCtrl,
                              focusNode: _pwdFocus,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                hintText: s.password,
                                prefixIcon: const Icon(Icons.lock_outline,
                                    size: 18, color: AppColors.textMute),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? s.showPassword
                                      : s.hidePassword,
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 18,
                                    color: AppColors.textMute,
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          AppColors.danger.withOpacity(0.35)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        size: 15, color: AppColors.danger),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.danger,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 46,
                              child: FilledButton(
                                onPressed: _submitting ? null : _submit,
                                child: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF04121B),
                                        ),
                                      )
                                    : Text(s.loginButton),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 2,
                        children: [
                          TextButton.icon(
                            onPressed: _showIntro,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.info_outline,
                                size: 15, color: AppColors.textMute),
                            label: Text(
                              s.loginIntroEntry,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textMute),
                            ),
                          ),
                          Container(
                              width: 1, height: 12, color: AppColors.border),
                          TextButton.icon(
                            onPressed: _showRegister,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.business_outlined,
                                size: 15, color: AppColors.accentStrong),
                            label: Text(
                              s.loginRegisterEntry,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.accentStrong),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 登录页背景：深色渐变 + 淡网格 + 上浮微粒（邻近连线）+ 下移的扫描光带。
/// 12 秒一个循环，透明度压在 0.03~0.5，有科技感但不抢表单注意力。
class _TechBackdrop extends StatefulWidget {
  const _TechBackdrop();

  @override
  State<_TechBackdrop> createState() => _TechBackdropState();
}

class _TechBackdropState extends State<_TechBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 系统开启“减弱动态效果”时停掉动画，只保留静态背景
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A1720), AppColors.bg, Color(0xFF061018)],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) =>
                    CustomPaint(painter: _DriftPainter(_ctrl.value)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 静态网格，只画一次，不参与每帧重绘
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double _step = 46;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// 动态层：呼吸光晕 + 扫描光带 + 微粒
class _DriftPainter extends CustomPainter {
  const _DriftPainter(this.t);

  /// 0~1 的循环进度
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGlow(canvas, size);
    _paintScanBand(canvas, size);
    _paintParticles(canvas, size);
  }

  /// 两团缓慢呼吸的冷光，右上为主、左下为辅
  void _paintGlow(Canvas canvas, Size size) {
    final breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final breath2 = 0.5 + 0.5 * math.sin(t * 2 * math.pi + 1.6);
    _drawGlow(
      canvas,
      size,
      center: Offset(size.width * 0.86, size.height * 0.05),
      radius: math.max(size.width, size.height) * 0.62,
      alpha: 0.10 + 0.06 * breath,
    );
    _drawGlow(
      canvas,
      size,
      center: Offset(size.width * 0.1, size.height * 0.86),
      radius: math.max(size.width, size.height) * 0.45,
      alpha: 0.05 + 0.04 * breath2,
    );
  }

  void _drawGlow(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radius,
    required double alpha,
  }) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: alpha),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// 从上往下扫过的光带，中间带一条细亮线，让移动更容易被看见
  void _paintScanBand(Canvas canvas, Size size) {
    const bandHeight = 260.0;
    final top = (t * 1.6 - 0.35) * size.height;
    final rect = Rect.fromLTWH(0, top, size.width, bandHeight);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.accent.withValues(alpha: 0.09),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, top + bandHeight / 2, size.width, 1.5),
      Paint()..color = AppColors.accentStrong.withValues(alpha: 0.16),
    );
  }

  /// 26 颗上浮微粒，距离较近的用细线相连，形成缓慢流动的星座感
  void _paintParticles(Canvas canvas, Size size) {
    const count = 26;
    final points = <Offset>[];
    for (int i = 0; i < count; i++) {
      final seed = i / count;
      final x = ((seed * 7.3) % 1.0) * size.width;
      final speed = 0.3 + (i % 6) * 0.12;
      final progress = (t * speed + seed * 1.7) % 1.0;
      points.add(Offset(x, (1 - progress) * size.height));
    }

    // 先画连线，避免线压住圆点
    final maxDist = math.min(size.width, size.height) * 0.22;
    final linePaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        if ((points[i] - points[j]).distance < maxDist) {
          canvas.drawLine(points[i], points[j], linePaint);
        }
      }
    }

    for (int i = 0; i < points.length; i++) {
      final radius = 1.4 + (i % 4) * 0.55;
      final twinkle = 0.5 + 0.5 * math.sin(t * 6 * math.pi + i * 1.7);
      final color = i % 7 == 0 ? AppColors.signal : AppColors.accent;
      canvas.drawCircle(
        points[i],
        radius,
        Paint()..color = color.withValues(alpha: 0.16 + 0.30 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DriftPainter oldDelegate) => oldDelegate.t != t;
}
