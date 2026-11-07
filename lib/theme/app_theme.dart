import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// 视觉规范对齐 keiyo-chat-admin 的暗色信号台：
/// 深蓝黑底 + 蓝 accent + 琥珀 signal + 绿色 ok，卡片 14px 圆角、1px 细描边。
class AppColors {
  static const Color bg = Color(0xFF08131A);
  static const Color panel = Color(0xFF0E1D26);
  static const Color panel2 = Color(0xFF13242F);
  static const Color border = Color(0xFF1C2E3A);
  static const Color borderStrong = Color(0xFF2A4150);
  static const Color accent = Color(0xFF4BA6DE);
  static const Color accentStrong = Color(0xFF7CC4EE);
  static const Color signal = Color(0xFFE2A03F);
  static const Color ok = Color(0xFF4CAF7D);
  static const Color danger = Color(0xFFE0705F);
  static const Color text = Color(0xFFE7F1F8);
  static const Color textDim = Color(0xFF9FB4C2);
  static const Color textMute = Color(0xFF6B8494);
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.signal,
        surface: AppColors.panel,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.panel,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.panel2,
        hintStyle: const TextStyle(color: AppColors.textMute, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF04121B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.panel,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMute,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.panel2,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.panel2,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.text, fontSize: 13),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 13.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(color: AppColors.textDim, fontSize: 13.5, height: 1.6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: Color(0xFF152833),
      ),
    );
  }
}

/// 状态色：0 进行中(蓝) / 1 需人工(琥珀) / 2 已关闭(灰)
Color statusColor(int status) {
  switch (status) {
    case 0:
      return AppColors.accent;
    case 1:
      return AppColors.signal;
    default:
      return const Color(0xFF3A4A55);
  }
}

String statusText(int status) {
  final s = AppStrings.current;
  switch (status) {
    case 0:
      return s.statusActive;
    case 1:
      return s.statusHuman;
    case 2:
      return s.statusClosed;
    default:
      return s.statusUnknown;
  }
}
