import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';

/// 服务端时间是 MySQL datetime 字符串（本地时区口径），直接按本地时间解析。
DateTime? parseServerTime(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

/// 会话列表用：今天只显示 HH:mm，昨天显示「昨天 HH:mm」，更早显示 MM-dd
String fmtTimeShort(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('HH:mm').format(t);
  if (diff == 1) return AppStrings.current.yesterday(DateFormat('HH:mm').format(t));
  if (t.year == now.year) return DateFormat('MM-dd').format(t);
  return DateFormat('yyyy-MM-dd').format(t);
}

/// 消息气泡用：MM-dd HH:mm
String fmtTime(DateTime? t) {
  if (t == null) return '';
  return DateFormat('MM-dd HH:mm').format(t);
}

String fmtDateTime(DateTime? t) {
  if (t == null) return '';
  return DateFormat('yyyy-MM-dd HH:mm').format(t);
}

/// 千分位
String fmtNumber(num? v) {
  final n = (v ?? 0).round();
  return NumberFormat.decimalPattern().format(n);
}

/// 0~1 小数转百分比；null 表示区间内没有埋点数据，显示 —
String fmtPercent(double? v) {
  if (v == null) return '—';
  final p = v * 100;
  final fixed = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  return '$fixed%';
}
