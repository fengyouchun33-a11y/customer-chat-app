import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 统一提示条：错误用红、成功用绿，避免各页面自己拼 SnackBar。
void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: error ? AppColors.danger : AppColors.ok,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}

String unreadText(int n) => n > 99 ? '99+' : '$n';

/// 语言选择弹窗：跟随系统 + 内置语言，选择后立即生效并落本地。
Future<void> showLanguagePicker(BuildContext context) async {
  final state = context.read<AppState>();
  final current = state.languagePref;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final s = AppStrings.of(ctx);
      return SimpleDialog(
        title: Text(s.language),
        children: [
          _languageTile(ctx, AppStrings.systemPref, s.followSystem, current),
          for (final code in AppStrings.supportedCodes)
            _languageTile(ctx, code, AppStrings.nativeName(code), current),
        ],
      );
    },
  );
  if (picked != null) await state.setLanguage(picked);
}

Widget _languageTile(BuildContext ctx, String value, String label, String current) {
  final selected = value == current;
  return ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
    title: Text(
      label,
      style: TextStyle(
        fontSize: 13.5,
        color: selected ? AppColors.accentStrong : AppColors.text,
      ),
    ),
    trailing: selected ? const Icon(Icons.check, size: 18, color: AppColors.accent) : null,
    onTap: () => Navigator.of(ctx).pop(value),
  );
}

/// 品牌标，登录页与启动页共用。
///
/// 与 Web 管理端同一张图（透明底 PNG），直接压在深色面板上：
/// 不自绘背景、不加圆角边框，避免两端口径不一致。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/support-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      // 与 Web 端 aria-hidden="true" 一致：品牌文字在图片旁边，图本身不重复报读
      excludeFromSemantics: true,
    );
  }
}

/// 会话状态胶囊：进行中 / 需人工 / 已关闭
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.compact = false});

  final int status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        statusText(status),
        style: TextStyle(color: color, fontSize: compact ? 10 : 11, height: 1.2),
      ),
    );
  }
}

/// 圆形首字头像：列表、聊天头、消息气泡共用。
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.text, this.size = 36});

  final String text;
  final double size;

  static const List<Color> _palette = [
    Color(0xFF2F6E93),
    Color(0xFF3B7A5E),
    Color(0xFF8A6134),
    Color(0xFF6A548F),
    Color(0xFF87515A),
  ];

  String get _initial {
    final t = text.trim();
    if (t.isEmpty) return '·';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  Color get _color {
    if (text.isEmpty) return _palette[0];
    var hash = 0;
    for (final code in text.runes) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withOpacity(0.22),
        border: Border.all(color: _color.withOpacity(0.55)),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          height: 1,
        ),
      ),
    );
  }
}

/// 圆形头像：优先显示服务端下发的头像地址，为空/加载失败时回退首字。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.text,
    this.url = '',
    this.size = 36,
  });

  final String text;
  final String url;
  final double size;

  String get _src {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    // 个别头像存的是 /public/... 相对路径，按当前域名补齐
    if (u.startsWith('/')) return '${AppConfig.defaultBaseUrl}$u';
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final src = _src;
    if (src.isEmpty) return InitialAvatar(text: text, size: size);
    return ClipOval(
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        // 头像未下完前先用首字占位，列表不会因为网络闪白
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : InitialAvatar(text: text, size: size),
        errorBuilder: (_, __, ___) => InitialAvatar(text: text, size: size),
      ),
    );
  }
}

/// 可点选的胶囊筛选按钮（状态、区间等）。
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.14) : AppColors.panel2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent.withOpacity(0.55) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: selected ? AppColors.accentStrong : AppColors.textDim,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 带描边与标题的卡片容器，统计页与加载失败页复用。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.tip,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    required this.child,
  });

  final String? title;
  final String? tip;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasHead = title != null;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHead) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                          height: 1.3,
                        ),
                      ),
                      if (tip != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          tip!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMute,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.text,
    this.hint,
    this.icon = Icons.forum_outlined,
    this.action,
  });

  final String text;
  final String? hint;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.textMute),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMute, height: 1.5),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 请求失败提示条，带可选重试按钮。
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.danger, height: 1.45),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(AppStrings.of(context).retry, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
