import 'package:intl/intl.dart';

/// 展示层格式化。金额/数量的"真相"永远来自服务端字段，这里只做呈现；
/// 任何带名词的文字（箱/分/天前）都属于 l10n，不进这个文件。
class Fmt {
  const Fmt._();

  /// 金额：符号取自 `profile.currency_symbol`（服务端兜底是 `$`，不是 ₴）。
  static String money(num amount, {String symbol = r'$', bool compact = false}) {
    if (compact && amount.abs() >= 10000) {
      final num scaled = amount.abs() >= 1000000 ? amount / 1000000 : amount / 1000;
      final String sign = amount < 0 ? '-' : '';
      final String unit = scaled.abs() >= 1000 ? 'M' : 'k';
      return '$sign$symbol${NumberFormat('#,##0.##').format(scaled.abs())}$unit';
    }
    return '$symbol${NumberFormat('#,##0.00').format(amount)}';
  }

  static String signedMoney(num amount, {String symbol = r'$'}) {
    final String body = money(amount.abs(), symbol: symbol);
    if (amount > 0) return '+$body';
    if (amount < 0) return '-$body';
    return body;
  }

  /// 编辑框初值：`null` 留空（新建态、没设过的整箱价），真实的 0 写 `0.00`。
  ///
  /// 把 0 折叠成空框会让「没定价」和「定价就是 0」在屏幕上看不出区别，
  /// 而商品 PATCH 是整行替换——用户以为空着就不动，实际把价格写回 0。
  /// 与网页端 `ProductEditor.tsx` 的 `String(p.price)` / `box_price != null` 两条分支一致。
  static String decimalSeed(double? value) => value == null ? '' : value.toStringAsFixed(2);

  /// 整数计数不带小数点，避免"12.00 单"这种读法。
  static String count(num value) => NumberFormat('#,##0').format(value);

  static String signedCount(num value) =>
      value > 0 ? '+${count(value)}' : count(value);

  static String percent(double ratio, {int digits = 1}) =>
      '${(ratio * 100).toStringAsFixed(digits)}%';

  static String date(DateTime? value) =>
      value == null ? '—' : DateFormat('yyyy-MM-dd').format(value);

  static String dateTime(DateTime? value) =>
      value == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(value);

  static String time(DateTime? value) =>
      value == null ? '—' : DateFormat('HH:mm').format(value);

  static String monthDay(DateTime? value) =>
      value == null ? '—' : DateFormat('MM-dd').format(value);

  /// 订单日期参数：服务端只吃 `YYYY-MM-DD`。
  static String isoDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  static DateTime? parseIsoDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// 相对时间的骨架：数值 + 档位，由 l10n 决定单位词与"前"的语序。
  static ({int value, RelUnit unit}) elapsed(DateTime? value) {
    if (value == null) return (value: 0, unit: RelUnit.now);
    final Duration diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return (value: 0, unit: RelUnit.now);
    if (diff.inHours < 1) return (value: diff.inMinutes, unit: RelUnit.minute);
    if (diff.inDays < 1) return (value: diff.inHours, unit: RelUnit.hour);
    if (diff.inDays < 7) return (value: diff.inDays, unit: RelUnit.day);
    return (value: diff.inDays, unit: RelUnit.date);
  }
}

enum RelUnit { now, minute, hour, day, date }
