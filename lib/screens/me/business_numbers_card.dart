import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

/// 取数快照：`ValueLoader` 只存 `T`，离线兜底信号得跟数据一起带进来。
class BusinessNumbers {
  const BusinessNumbers(this.stats, this.stale);

  final DashboardStats stats;
  final bool stale;
}

/// 经营数字：库存总量与货值、低库存预警、今日出入库。
///
/// 从工作台搬进「我的」，是因为主屏会被人从背后瞥一眼，家底不该露在那儿。
/// 数字默认打码，眼睛键只在这页有效 —— 取数依旧走服务端，权限位不在就整块不渲染。
///
/// loader 由「我的」页的 State 持有：这张卡在 `ListView` 里，滚出可视区就会被销毁，
/// 自己取数的话每次滑回来都要重发请求、重铺骨架屏，看上去就是一块空白。
class BusinessNumbersCard extends StatefulWidget {
  const BusinessNumbersCard({super.key, required this.numbers});

  final ValueLoader<BusinessNumbers> numbers;

  @override
  State<BusinessNumbersCard> createState() => _BusinessNumbersCardState();
}

class _BusinessNumbersCardState extends State<BusinessNumbersCard> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    return AnimatedBuilder(
      animation: widget.numbers,
      builder: (BuildContext context, Widget? _) {
        final BusinessNumbers? snapshot = widget.numbers.value;
        return AppCard(
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
                  onPressed: () => setState(() => _revealed = !_revealed),
                ),
              ),
              if (widget.numbers.loading && snapshot == null)
                const SkeletonList(count: 2, itemHeight: 84)
              else if (snapshot == null)
                AppErrorView(
                  message: widget.numbers.errorText ?? l10n.commonErrorTitle,
                  onRetry: widget.numbers.load,
                )
              else ...<Widget>[
                _Numbers(
                  stats: snapshot.stats,
                  revealed: _revealed,
                  currency: app.profile.currencySymbol,
                ),
                const VGap(12),
                _Footnote(
                  stats: snapshot.stats,
                  revealed: _revealed,
                  currency: app.profile.currencySymbol,
                ),
              ],
              if (snapshot != null && snapshot.stale && app.online) ...<Widget>[
                const VGap(10),
                Text(
                  l10n.commonStaleBanner,
                  style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
                ),
              ],
            ],
          ),
        );
      },
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
