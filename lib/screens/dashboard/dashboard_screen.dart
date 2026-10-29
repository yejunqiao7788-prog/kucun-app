import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/access.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/log_labels.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';
import '../orders/order_detail_screen.dart';

/// 工作台：只留「今天该干什么」 —— 待备货的单、快捷入口、最近动态。
///
/// 库存数量、货值这类家底数字不在这一页显示，收进「我的」里的经营数字卡，
/// 主屏被人瞥一眼看不出规模；低频模块仍从这里的一排快捷入口进。
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final Repos _repos = context.read<AppState>().repos;

  late final ValueLoader<DashboardOrders> _orders =
      ValueLoader<DashboardOrders>(() async => (await _repos.dashboard.orders()).data);
  // 服务端这支只有 `limit`、没有 offset，翻页拿回来的是同一批行，所以这里不该用 ListController。
  // 拉几条就摆几条：以前拉 8 只显示 6，那两条永远读不到，还像是丢数据。
  // 网页端那个 360px 高的滚动框里放 30 条，移动端跟着抄会把待备货的单挤出屏幕，10 条是这一屏的容量上限。
  late final ValueLoader<List<OperationLog>> _logs =
      ValueLoader<List<OperationLog>>(() => _repos.dashboard.logs(limit: 10));

  @override
  void initState() {
    super.initState();
    _orders.load();
    _logs.load();
  }

  @override
  void dispose() {
    _orders.dispose();
    _logs.dispose();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait<void>(<Future<void>>[
        _orders.refresh(),
        _logs.refresh(),
      ]);

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final List<OperationLog> logs = _logs.value ?? const <OperationLog>[];

    // 与另外三个根标签同形：最外层 SafeArea(bottom: false)。
    // 工作台原先是唯一没有顶部安全区的根标签，列表首行从 y=8 起就压在状态栏下面，
    // 这才是它「看起来溢出」、其它页不溢出的原因。
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_orders, _logs]),
        builder: (BuildContext context, Widget? _) => RefreshIndicator(
          onRefresh: _refresh,
          color: AppInk.dashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
            children: <Widget>[
              _PageHead(
                title: app.profile.tenantName.isEmpty ? l10n.navDashboard : app.profile.tenantName,
                subtitle: l10n.dashToday(Fmt.date(DateTime.now())),
              ),
              const VGap(10),
              if (!app.online)
                NoticeBanner(
                  text: l10n.commonOfflineBanner,
                  color: AppInk.warning,
                  icon: Icons.wifi_off_rounded,
                ),
              if (app.renewalPending)
                NoticeBanner(
                  text: l10n.commonExpiredBanner,
                  color: AppInk.danger,
                  icon: Icons.lock_outline_rounded,
                  action: TextAction(
                    label: l10n.finRenew,
                    color: AppInk.danger,
                    onPressed: () => ModuleKey.settings.jumpTo(context),
                  ),
                ),
              const VGap(14),
              // 下拉刷新失败但旧数据还在：整屏看着正常，其实已经不掉新数了，得说一声。
              RefreshFailureBanner.stale(_orders),
              RefreshFailureBanner(errorText: _logs.hasValue ? _logs.errorText : null, onRetry: _logs.refresh),
              SectionHeader(title: l10n.dashQuickActions, accent: AppInk.dashboard),
              QuickActionRow(l10n: l10n, app: app),
              const VGap(22),
              if (_orders.value != null) ...<Widget>[
                SectionHeader(
                  title: l10n.dashPicking,
                  accent: AppInk.orders,
                  trailing: TextAction(
                    label: l10n.actMore,
                    onPressed: () => RootTabs.openOrders(context),
                  ),
                ),
                _PickingList(
                  orders: _orders.value!.recent(privileged: app.isAdmin),
                  picking: _orders.value!.picking,
                  l10n: l10n,
                ),
                const VGap(22),
              ],
              SectionHeader(title: l10n.dashActivity, accent: AppInk.ai),
              if (_logs.loading && logs.isEmpty)
                const SkeletonList(count: 3, itemHeight: 44)
              else if (logs.isEmpty)
                // 这一栏此前连空态都没有：没数据时标题下面一片空白，读起来像坏了。
                Text(
                  _logs.errorText ?? l10n.dashNoLogs,
                  style: const TextStyle(color: AppInk.textTertiary, fontSize: AppType.foot),
                )
              else
                ...logs.map(
                  (OperationLog log) => LogRowCard(
                    log: log,
                    l10n: l10n,
                    currency: app.profile.currencySymbol,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一条动态：`动作块 | 胶囊 + 对象名 / SKU + 逐字段变更 / 操作人 · 时间`。
/// 网页端 `LogsSection` 是「图标块 + 胶囊 + 名称 + SKU 块 + 变更块 + 人·时间」六段。
/// 之前移动端把最宽的 66px 左栏给了相对时间，名字被压到 190px 上限、变更压成两行省略号 ——
/// 现在左栏换成一眼可辨的动作色块，时间落进页脚（与网页端同位），变更逐条摆开不再被截掉。
class LogRowCard extends StatelessWidget {
  const LogRowCard({
    super.key,
    required this.log,
    required this.l10n,
    required this.currency,
  });

  final OperationLog log;
  final L10n l10n;
  final String currency;

  static Color _actionColor(String operation) => switch (operation) {
        'CREATE' => AppInk.ai,
        'DELETE' => AppInk.danger,
        'FINALIZE' => AppInk.success,
        'SYNC' => AppInk.info,
        _ => AppInk.warning,
      };

  static IconData _actionIcon(String operation) => switch (operation) {
        'CREATE' => Icons.add_rounded,
        'DELETE' => Icons.delete_outline_rounded,
        'FINALIZE' => Icons.check_circle_outline_rounded,
        'SYNC' => Icons.sync_rounded,
        _ => Icons.edit_rounded,
      };

  // 一次改动可能牵扯七个字段，网页端全摆，这里也全摆：截断成 3 条曾经把
  // 「到底改了什么」藏进「+4 项」，正是这一栏最没用的状态。
  @override
  Widget build(BuildContext context) {
    final Color accent = _actionColor(log.action);
    final String sku = log.productSku;
    final String objectName = logObjectLabel(l10n, log);
    final List<String> chips = logChangeChips(l10n, log, currency: currency);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppInk.tint(accent, alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Icon(_actionIcon(log.action), size: 16, color: accent),
          ),
          const HGap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusPill(
                      label: logActionLabel(l10n, log.action),
                      color: accent,
                      dense: true,
                    ),
                    const HGap(6),
                    Expanded(
                      child: Text(
                        objectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppType.body, fontWeight: AppType.semi),
                      ),
                    ),
                  ],
                ),
                if (chips.isNotEmpty || sku.isNotEmpty && objectName != sku) ...<Widget>[
                  const VGap(5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      if (sku.isNotEmpty && objectName != sku) _MetaChip(text: sku, muted: true),
                      for (final String chip in chips) _MetaChip(text: chip),
                    ],
                  ),
                ],
                const VGap(4),
                Text(
                  '${logActorLabel(l10n, log)} · ${l10n.elapsed(log.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 变更/SKU 的小块：淡底微字，和上方的动作文案分层。
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final Color ink = muted ? AppInk.textTertiary : AppInk.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppInk.tint(ink, alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppType.micro, color: ink),
      ),
    );
  }
}

class _PageHead extends StatelessWidget {  const _PageHead({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 与网页端同形：标题就是租户名，用户名只出现在「我的」的账号卡里。
        // 大号字加行人名曾经把顶部顶出屏幕，这里限一行并留省略号。
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AppType.head,
            fontWeight: AppType.heavy,
            letterSpacing: -0.4,
          ),
        ),
        const VGap(3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
        ),
      ],
    );
  }
}

class _PickingList extends StatelessWidget {
  const _PickingList({required this.orders, required this.picking, required this.l10n});

  final List<Order> orders;
  final List<Order> picking;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final List<Order> rows = (picking.isNotEmpty ? picking : orders).take(4).toList();
    if (rows.isEmpty) {
      return AppCard(
        accent: AppInk.orders,
        child: Text(l10n.commonEmptyTitle, style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return Column(
      children: rows
          .map(
            (Order order) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                accent: AppInk.orders,
                padding: const EdgeInsets.all(12),
                onTap: () => pushSheet<void>(context, child: OrderDetailScreen(orderId: order.id)),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(order.orderNumber, style: Theme.of(context).textTheme.titleMedium),
                          const VGap(2),
                          Text(
                            order.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const HGap(8),
                    StatusPill(
                      label: order.isPreparing
                          ? l10n.dashPicking
                          : order.status == OrderStatus.pending
                              ? l10n.ordPending
                              : l10n.ordCompleted,
                      color: order.isPreparing
                          ? AppInk.showroom
                          : order.status == OrderStatus.pending
                              ? AppInk.textSecondary
                              : AppInk.success,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// 低频模块的入口条：权限决定显隐，颜色与模块一致。
class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key, required this.l10n, required this.app});

  final L10n l10n;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[];
    for (final ModuleEntry entry in kSecondaryModules) {
      if (!app.canOpenModule(entry.key)) continue;
      tiles.add(
        Expanded(
          child: _QuickTile(
            icon: entry.icon,
            label: entry.titleOf(l10n),
            accent: entry.accent,
            onTap: () => entry.open(context),
          ),
        ),
      );
      if (tiles.length == 4) break;
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        for (int index = 0; index < tiles.length; index++) ...<Widget>[
          if (index > 0) const HGap(10),
          tiles[index],
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      child: Column(
        children: <Widget>[
          Icon(icon, color: accent, size: 24),
          const VGap(8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
          ),
        ],
      ),
    );
  }
}
