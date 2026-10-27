import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';

/// 经营数字：库存总量与货值、低库存预警、今日出入库。
///
/// 从工作台搬进「我的」，是因为主屏会被人从背后瞥一眼，家底不该露在那儿。
/// 数字默认打码，眼睛键只在这页有效 —— 取数依旧走服务端，权限位不在就整块不渲染。
class BusinessNumbersCard extends StatefulWidget {
  const BusinessNumbersCard({super.key});

  @override
  State<BusinessNumbersCard> createState() => BusinessNumbersCardState();
}

class BusinessNumbersCardState extends State<BusinessNumbersCard> {
  late final AppState _app = context.read<AppState>();
  bool _stale = false;
  late final ValueLoader<DashboardStats> _stats = ValueLoader<DashboardStats>(
    () async {
      // stale 只能在这里取：ValueLoader 自己不带这个信号。
      final ApiResponse<DashboardStats> res = await _app.repos.dashboard.stats();
      _stale = res.stale;
      return res.data;
    },
  );
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _stats.load();
  }

  @override
  void dispose() {
    _stats.dispose();
    super.dispose();
  }

  /// 供「我的」页下拉刷新调用：数字要跟着开单、入库一起动。
  Future<void> reload() => _stats.refresh();

  void _toggle() => setState(() => _revealed = !_revealed);

  @override
  Widget build(BuildContext context) {
    final L10n l10n = _app.l10n;
    return AnimatedBuilder(
      animation: _stats,
      builder: (BuildContext context, Widget? _) => AppCard(
        accent: AppInk.inventory,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: l10n.meBizTitle,
              subtitle: l10n.meBizHint,
              accent: AppInk.inventory,
              trailing: _RevealButton(
                revealed: _revealed,
                showLabel: l10n.meBizShow,
                hideLabel: l10n.meBizHide,
                onPressed: _toggle,
              ),
            ),
            if (_stats.loading && _stats.value == null)
              const SkeletonList(count: 2, itemHeight: 84)
            else if (_stats.value == null)
              AppErrorView(
                message: _stats.errorText ?? l10n.commonErrorTitle,
                onRetry: _stats.load,
              )
            else ...<Widget>[
              _Numbers(stats: _stats.value!, revealed: _revealed, currency: _app.profile.currencySymbol),
              const VGap(12),
              _Footnote(stats: _stats.value!, revealed: _revealed, currency: _app.profile.currencySymbol),
            ],
            if (_stale && _app.online && _stats.value != null) ...<Widget>[
              const VGap(10),
              Text(
                l10n.commonStaleBanner,
                style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.stats, required this.revealed, required this.currency});

  final DashboardStats stats;
  final bool revealed;
  final String currency;

  String _mask(String value) => revealed ? value : kMask;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: l10n.dashProducts,
                value: _mask(Fmt.count(stats.totalProducts)),
                accent: AppInk.products,
                icon: Icons.inventory_2_rounded,
              ),
            ),
            const HGap(10),
            Expanded(
              child: StatTile(
                label: l10n.dashStockQty,
                value: _mask(Fmt.count(stats.totalStock)),
                accent: AppInk.inventory,
                icon: Icons.layers_rounded,
                footnote: revealed
                    ? '${l10n.dashStockValue} ${Fmt.money(stats.totalValue, symbol: currency, compact: true)}'
                    : null,
              ),
            ),
          ],
        ),
        const VGap(10),
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: l10n.dashLowStock,
                value: _mask(Fmt.count(stats.lowStock)),
                accent: stats.lowStock > 0 ? AppInk.warning : AppInk.success,
                icon: Icons.warning_amber_rounded,
                onTap: () => RootTabs.openInventory(context),
              ),
            ),
            const HGap(10),
            Expanded(
              child: StatTile(
                label: l10n.dashInToday,
                value: _mask('${Fmt.count(stats.inboundToday)} · ${Fmt.count(stats.inboundQtyToday)}'),
                accent: AppInk.finance,
                icon: Icons.swap_vert_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 打码时不重复堆四块格子，一行说清今天的进出即可。
class _Footnote extends StatelessWidget {
  const _Footnote({required this.stats, required this.revealed, required this.currency});

  final DashboardStats stats;
  final bool revealed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Text(
      revealed
          ? '${l10n.dashOutToday} ${Fmt.count(stats.outboundToday)} · '
              '${Fmt.count(stats.outboundQtyToday)} · '
              '${l10n.dashStockValue} ${Fmt.money(stats.totalValue, symbol: currency, compact: true)}'
          : '${l10n.dashInToday} $kMask · ${l10n.dashOutToday} $kMask',
      style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
    );
  }
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({
    required this.revealed,
    required this.showLabel,
    required this.hideLabel,
    required this.onPressed,
  });

  final bool revealed;
  final String showLabel;
  final String hideLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextAction(
      label: revealed ? hideLabel : showLabel,
      color: revealed ? AppInk.textSecondary : AppInk.inventory,
      onPressed: onPressed,
    );
  }
}

const String kMask = '••••';
