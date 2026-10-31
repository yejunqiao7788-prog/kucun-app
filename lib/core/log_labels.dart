import '../data/entities.dart';
import 'formatters.dart';
import 'l10n.dart';

/// 动态行的文案组装。网页端把这套 switch 写在 `DashboardPanel.tsx` 的组件里，
/// App 有两个消费方（首页与 AI 本地问答），收到一处才不会同一个枚举两套译法。
String logActionLabel(L10n l10n, String operation) => switch (operation) {
      'CREATE' => l10n.dashLogCreate,
      'UPDATE' => l10n.dashLogUpdate,
      'DELETE' => l10n.dashLogDelete,
      'FINALIZE' => l10n.dashLogFinalize,
      'SYNC' => l10n.dashLogSync,
      // 库里还躺着 PAYMENT / MP_LISTING_* / ADMIN_FIX_NEGATIVE_STOCK 这些没登记的取值：
      // 原样显示好过译错，也保留了「服务端加了新动作」这件事在界面上的可见性。
      _ => operation,
    };

/// 变更字段的库列名（`quantity`、`price`…）翻成人话，逐条抄网页端 `changeLabel`。
String logFieldLabel(L10n l10n, String field) => switch (field) {
      'quantity' => l10n.dashFieldQuantity,
      'min_stock' => l10n.dashFieldMinStock,
      'max_stock' => l10n.dashFieldMaxStock,
      'location' => l10n.dashFieldLocation,
      'sku' => l10n.dashFieldSku,
      'name' => l10n.dashFieldName,
      'price' => l10n.dashFieldPrice,
      'cost' => l10n.dashFieldCost,
      _ => field,
    };

/// 变更值按字段性质排版：价格类走货币，其余原样。
/// `price 12.5 → 15` 在屏幕上和数量改动分不出来，加符号才读得出这是钱。
String logChangeValue(String field, String value, {String? currency}) {
  if (currency == null || !_isMoneyField(field)) return value;
  final double? amount = double.tryParse(value);
  return amount == null ? value : Fmt.money(amount, symbol: currency);
}

bool _isMoneyField(String field) =>
    field == 'price' || field == 'cost' || field.endsWith('_price') || field.endsWith('_cost');

/// 逐字段变更，一条一小块 —— 网页端 `details.changes` 就是 per-field chips。
/// 没有 `changes` 的那几支（批量改价 / 外部同步 / 保留期清理）改从 `details` 的
/// 参数与计数里读出「干了什么」，否则整行只剩一个动作胶囊。
/// 调用方自己决定摆成 chips 还是拼成一行文本。
List<String> logChangeChips(L10n l10n, OperationLog log, {String? currency}) {
  final List<LogChange> changes = log.changes;
  if (changes.isNotEmpty) {
    return changes
        .map((LogChange change) => '${logFieldLabel(l10n, change.field)} '
            '${logChangeValue(change.field, change.from, currency: currency)} → '
            '${logChangeValue(change.field, change.to, currency: currency)}')
        .toList(growable: false);
  }
  return _logDetailChips(l10n, log, currency: currency);
}

/// 已经变成对象名或行文本、不需要再单独摆出来的键。
const Set<String> _detailSpent = <String>{
  'sku',
  'name',
  'changes',
  'source',
  'requestId',
  'ip',
  'action',
  'kind',
  'triggered_by',
};

List<String> _logDetailChips(L10n l10n, OperationLog log, {String? currency}) {
  final details = log.details;
  final List<String> chips = <String>[];
  final Set<String> used = <String>{};

  final String mode = details.asStringOr('mode', '');
  if (mode.isNotEmpty) {
    final String value = _batchValueLabel(details.raw('value'), mode, currency);
    final String label = _batchModeLabel(l10n, mode);
    chips.add(value.isEmpty ? label : '$label $value');
    used.addAll(<String>['mode', 'value']);
  }
  final Object? total = details.raw('total');
  final Object? updated = details.raw('updated');
  final Object? unchanged = details.raw('unchanged');
  final Object? failed = details.raw('failed');
  if (total != null && updated != null) {
    chips.add(l10n.dashBatchTotal(total));
    used.add('total');
  }
  if (updated != null && unchanged != null && failed != null) {
    chips.add(l10n.prodBatchResult(
      updated: updated,
      unchanged: unchanged,
      failed: failed,
    ));
    used.addAll(<String>['updated', 'unchanged', 'failed']);
  }
  final Object? newFound = details.raw('new_found');
  if (newFound != null) {
    chips.add(l10n.dashNewFound(newFound));
    used.add('new_found');
  }
  if (details.raw('soft_deleted_count') != null || details.raw('hard_deleted_count') != null) {
    chips.add(l10n.dashRetentionCounts(
      soft: details.asIntOr('soft_deleted_count', 0),
      hard: details.asIntOr('hard_deleted_count', 0),
    ));
    used.addAll(<String>['soft_deleted_count', 'hard_deleted_count']);
  }
  final String priceTarget = details.asStringOr('price_target', '');
  if (priceTarget.isNotEmpty) {
    chips.add(l10n.dashPriceTarget(logFieldLabel(l10n, priceTarget)));
    used.add('price_target');
  }
  // 认不出的键原样打印：服务端新加一个参数时，动态里读到 `foo_bar 3` 远好过什么都没显示。
  for (final MapEntry<String, Object?> entry in details.json.entries) {
    if (_detailSpent.contains(entry.key) || used.contains(entry.key)) continue;
    final Object? value = entry.value;
    if (value == null || value is Map || value is List) continue;
    chips.add('${entry.key} $value');
  }
  return chips;
}

String _batchModeLabel(L10n l10n, String mode) => switch (mode) {
      'set' => l10n.prodModeSet,
      'markup_cost' => l10n.prodModeMarkupCost,
      'percent' => l10n.prodModePercent,
      'amount' => l10n.prodModeAmount,
      _ => mode,
    };

/// 百分比档留原值加 `%`，金额档走货币；和商品页批量改价面板同一读法。
String _batchValueLabel(Object? value, String mode, String? currency) {
  if (value == null) return '';
  final String plain = '$value';
  if (mode == 'percent' || mode == 'markup_cost') return '$plain%';
  final double? amount = double.tryParse(plain);
  return amount == null ? plain : Fmt.money(amount, symbol: currency ?? '');
}

/// 动态行的对象名。网页端是 `(showName && details.name) || details.sku || '—'`，但批量改价
/// 与外部同步两支服务端两个键都没写，手机上就是一个孤零零的「—」，读不出这一行说的是什么。
///
/// 关掉名称时优先读码；没有码的系统写仍回落到那一句汇总，不留「—」。
String logObjectLabel(L10n l10n, OperationLog log, {bool showName = true}) {
  if (!showName && log.productSku.isNotEmpty) return log.productSku;
  final String target = log.target;
  if (target != '—') return target;
  final details = log.details;
  if (details.asStringOr('action', '') == 'batch_price') return l10n.dashBatchPrice;
  final String source = details.asStringOr('source', '');
  if (source.isNotEmpty) return l10n.dashSyncedFrom(source);
  return target;
}


/// `库存 4 → 539 · 仓位 A1 → B2`，无变更时回空串（调用方据此决定要不要占一行）。
String logChangesLine(L10n l10n, OperationLog log, {String? currency}) =>
    logChangeChips(l10n, log, currency: currency).join(' · ');

String logActorLabel(L10n l10n, OperationLog log) =>
    log.actor.isEmpty ? l10n.dashLogSystem : log.actor;

/// 一行读完的动态：谁 · 做了什么 · 哪件货（带变更）。网页端是三段小块，移动端压成一行。
String logLine(L10n l10n, OperationLog log, {bool showName = true}) {
  final String changes = logChangesLine(l10n, log);
  final List<String> parts = <String>[
    logActorLabel(l10n, log),
    logActionLabel(l10n, log.action),
    logObjectLabel(l10n, log, showName: showName),
    if (changes.isNotEmpty) changes,
  ];
  return parts.join(' · ');
}
