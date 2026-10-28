import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/access.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/list_controller.dart';
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
  late final ListController<OperationLog> _logs = ListController<OperationLog>(
    fetch: (int page) async {
      final Paged<OperationLog> res = await _repos.dashboard.logs(page: page, pageSize: 8);
      return FetchResult<OperationLog>(rows: res.rows, hasMore: res.hasMore);
    },
  );

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

    return Scaffold(
      body: AnimatedBuilder(
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
              if (_logs.state == LoadState.loading && _logs.rows.isEmpty)
                const SkeletonList(count: 3, itemHeight: 44)
              else
                ..._logs.rows.take(6).map(
                      (OperationLog log) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 66,
                              child: Text(
                                l10n.elapsed(log.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                log.actor.isEmpty
                                    ? '${log.action} · ${log.detail}'.trim()
                                    : '${log.actor} · ${log.action}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              if (_logs.state == LoadState.failed && _logs.rows.isEmpty)
                Text(
                  _logs.errorText ?? l10n.commonErrorTitle,
                  style: const TextStyle(color: AppInk.textTertiary, fontSize: AppType.foot),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHead extends StatelessWidget {
  const _PageHead({required this.title, required this.subtitle});

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
