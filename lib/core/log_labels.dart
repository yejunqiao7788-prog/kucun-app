import '../data/entities.dart';
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

/// `库存 4 → 539 · 仓位 A1 → B2`，无变更时回空串（调用方据此决定要不要占一行）。
String logChangesLine(L10n l10n, OperationLog log) => log.changes
    .map((LogChange change) => '${logFieldLabel(l10n, change.field)} ${change.from} → ${change.to}')
    .join(' · ');

String logActorLabel(L10n l10n, OperationLog log) =>
    log.actor.isEmpty ? l10n.dashLogSystem : log.actor;

/// 一行读完的动态：谁 · 做了什么 · 哪件货（带变更）。网页端是三段小块，移动端压成一行。
String logLine(L10n l10n, OperationLog log) {
  final String changes = logChangesLine(l10n, log);
  final List<String> parts = <String>[
    logActorLabel(l10n, log),
    logActionLabel(l10n, log.action),
    log.target,
    if (changes.isNotEmpty) changes,
  ];
  return parts.join(' · ');
}
