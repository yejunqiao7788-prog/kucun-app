import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/list_controller.dart';
import 'order_create_screen.dart';
import 'order_detail_screen.dart';

/// 订单页：状态用胶囊一划就切，其余条件收进筛选抽屉。
///
/// 建单动作在底部导航中央那颗键上，这里的新建按钮只是同一个出口的第二次落点。
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final Repos _repos = context.read<AppState>().repos;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  OrderFilters _filters = const OrderFilters();

  late final ListController<Order> _list = ListController<Order>(
    fetch: (int page) async {
      final ApiResponse<Paged<Order>> res = await _repos.orders.list(
        page: page,
        pageSize: 20,
        search: _filters.search,
        status: _filters.status,
        type: _filters.type,
        paymentStatus: _filters.paymentStatus,
        dateFrom: _filters.dateFrom,
        dateTo: _filters.dateTo,
      );
      return FetchResult<Order>(
        rows: res.data.rows,
        hasMore: res.data.hasMore,
        stale: res.stale,
      );
    },
  );

  @override
  void initState() {
    super.initState();
    _list.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  void _apply(OrderFilters next) {
    setState(() => _filters = next);
    _list.load();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final String trimmed = value.trim();
      _apply(_filters.withSearch(trimmed.isEmpty ? null : trimmed));
    });
  }

  Future<void> _openFilters() async {
    final AppState app = AppState.of(context);
    final OrderFilters? next = await showDrawer<OrderFilters>(
      context,
      accent: AppInk.orders,
      title: app.l10n.actFilter,
      builder: (BuildContext sheetContext) =>
          _OrderFilterDrawer(initial: _filters, l10n: app.l10n),
    );
    if (next == null || !mounted) return;
    _apply(next);
  }

  Future<void> _openDetail(Order order) async {
    await pushSheet<void>(context, child: OrderDetailScreen(orderId: order.id));
    if (!mounted) return;
    await _list.refresh();
  }

  void _create() {
    final ShellScope? shell = ShellScope.maybeOf(context);
    if (shell != null) {
      shell.openCreateOrder();
    } else {
      pushSheet<void>(context, child: const OrderCreateScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.navOrders,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppType.huge,
                      fontWeight: AppType.heavy,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: Icons.add_rounded,
                  color: AppInk.orders,
                  tooltip: l10n.ordNew,
                  onPressed: app.canWrite ? _create : null,
                ),
              ],
            ),
          ),
          PillTabs<String?>(
            values: const <String?>[null, 'pending', 'completed'],
            selected: _filters.status,
            accent: AppInk.orders,
            scrollable: false,
            labelOf: (String? value) => switch (value) {
              null => l10n.commonAll,
              'pending' => l10n.ordPending,
              _ => l10n.ordCompleted,
            },
            onChanged: (String? value) => _apply(_filters.withStatus(value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SearchField(
                    controller: _search,
                    hintText: l10n.ordSearchHint,
                    onChanged: _onSearchChanged,
                  ),
                ),
                const HGap(8),
                RoundIconButton(
                  icon: Icons.tune_rounded,
                  color: _filters.dirty ? AppInk.orders : null,
                  tooltip: l10n.actFilter,
                  onPressed: _openFilters,
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedView<Order>(
              controller: _list,
              accent: AppInk.orders,
              emptyTitle: l10n.commonEmptyTitle,
              emptyHint: l10n.ordSearchHint,
              emptyIcon: Icons.receipt_long_outlined,
              emptyAction: app.canWrite
                  ? PrimaryButton(
                      label: l10n.ordNew,
                      icon: Icons.add_rounded,
                      color: AppInk.orders,
                      expanded: false,
                      onPressed: _create,
                    )
                  : null,
              itemBuilder: (BuildContext context, Order row, int index) =>
                  _OrderRow(
                order: row,
                currency: app.profile.currencySymbol,
                onTap: () => _openDetail(row),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.currency,
    required this.onTap,
  });

  final Order order;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    final Color statusColor = order.isPreparing
        ? AppInk.showroom
        : order.status == OrderStatus.pending
            ? AppInk.textSecondary
            : AppInk.success;
    final Color payColor = switch (order.paymentStatus) {
      PaymentStatus.paid => AppInk.success,
      PaymentStatus.partial => AppInk.warning,
      PaymentStatus.unpaid => AppInk.danger,
    };

    return RowCard(
      accent: AppInk.orders,
      onTap: onTap,
      title: order.orderNumber,
      subtitle:
          '${order.customerName} · ${order.orderDate ?? Fmt.date(order.createdAt)}',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            Fmt.money(order.totalAmount, symbol: currency),
            style: const TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy),
          ),
          const VGap(2),
          Text(
            '${Fmt.count(order.totalQuantity)} ${l10n.unitPiece}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      badges: <Widget>[
        StatusPill(
          label: order.type == OrderType.inbound ? l10n.ordInbound : l10n.ordOutbound,
          color: order.type == OrderType.inbound ? AppInk.finance : AppInk.products,
          dense: true,
        ),
        StatusPill(
          label: order.isPreparing
              ? l10n.dashPicking
              : order.status == OrderStatus.pending
                  ? l10n.ordPending
                  : l10n.ordCompleted,
          color: statusColor,
          dense: true,
        ),
        if (order.type == OrderType.outbound && order.paymentStatus != PaymentStatus.paid)
          StatusPill(
            label: order.paymentStatus == PaymentStatus.partial
                ? l10n.ordPartial
                : l10n.ordUnpaid,
            color: payColor,
            dense: true,
          ),
        if (order.outstandingAmount > 0)
          StatusPill(
            label:
                '${l10n.ordOutstanding} ${Fmt.money(order.outstandingAmount, symbol: currency, compact: true)}',
            color: AppInk.danger,
            dense: true,
          ),
      ],
    );
  }
}

/// 筛选条件：`null` 就是「全部」，所以每个维度都有专属的 setter，
/// 不用 copyWith 传 null（那样分不清「没改」和「清空」）。
class OrderFilters {
  const OrderFilters({
    this.search,
    this.status,
    this.type,
    this.paymentStatus,
    this.dateFrom,
    this.dateTo,
  });

  final String? search;
  final String? status;
  final String? type;
  final String? paymentStatus;
  final String? dateFrom;
  final String? dateTo;

  bool get dirty =>
      type != null || paymentStatus != null || dateFrom != null || dateTo != null;

  // 「全部」在这些过滤里就是 null，所以必须直接赋值：写成 `value ?? this.value`
  // 等于「null 表示没改」，切回全部时旧过滤留着不动，点上去自然没反应。
  // 清空搜索框走的是同一支，也一样要能落回 null。
  OrderFilters withSearch(String? value) => OrderFilters(
        search: value,
        status: status,
        type: type,
        paymentStatus: paymentStatus,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

  OrderFilters withStatus(String? value) => OrderFilters(
        search: search,
        status: value,
        type: type,
        paymentStatus: paymentStatus,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

  OrderFilters replaced({String? type, String? paymentStatus}) => OrderFilters(
        search: search,
        status: status,
        type: type,
        paymentStatus: paymentStatus,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

  OrderFilters withDates(String? from, String? to) => OrderFilters(
        search: search,
        status: status,
        type: type,
        paymentStatus: paymentStatus,
        dateFrom: from,
        dateTo: to,
      );
}

class _OrderFilterDrawer extends StatefulWidget {
  const _OrderFilterDrawer({required this.initial, required this.l10n});

  final OrderFilters initial;
  final L10n l10n;

  @override
  State<_OrderFilterDrawer> createState() => _OrderFilterDrawerState();
}

class _OrderFilterDrawerState extends State<_OrderFilterDrawer> {
  late OrderFilters _draft = widget.initial;

  Future<void> _pickDate({required bool from}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: Fmt.parseIsoDate(from ? _draft.dateFrom : _draft.dateTo) ??
          DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    final String iso = Fmt.isoDate(picked);
    setState(() {
      _draft = from
          ? _draft.withDates(iso, _draft.dateTo)
          : _draft.withDates(_draft.dateFrom, iso);
    });
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = widget.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Text(l10n.ordType, style: text.titleMedium),
        const VGap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _Chip(
              label: l10n.commonAll,
              selected: _draft.type == null,
              onTap: () => setState(
                  () => _draft = _draft.replaced(type: null, paymentStatus: _draft.paymentStatus)),
            ),
            _Chip(
              label: l10n.ordInbound,
              selected: _draft.type == 'inbound',
              onTap: () => setState(() => _draft = _draft.replaced(
                  type: 'inbound', paymentStatus: _draft.paymentStatus)),
            ),
            _Chip(
              label: l10n.ordOutbound,
              selected: _draft.type == 'outbound',
              onTap: () => setState(() => _draft = _draft.replaced(
                  type: 'outbound', paymentStatus: _draft.paymentStatus)),
            ),
          ],
        ),
        const VGap(18),
        Text(l10n.ordPayment, style: text.titleMedium),
        const VGap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String? value in const <String?>[null, 'unpaid', 'partial', 'paid'])
              _Chip(
                label: switch (value) {
                  null => l10n.commonAll,
                  'unpaid' => l10n.ordUnpaid,
                  'partial' => l10n.ordPartial,
                  _ => l10n.ordFullyPaid,
                },
                selected: _draft.paymentStatus == value,
                onTap: () => setState(() => _draft = _draft.replaced(
                    type: _draft.type, paymentStatus: value)),
              ),
          ],
        ),
        const VGap(18),
        Text(l10n.ordDate, style: text.titleMedium),
        const VGap(8),
        Row(
          children: <Widget>[
            Expanded(
              child: GhostButton(
                label: _draft.dateFrom ?? l10n.ordDateFrom,
                icon: Icons.event_rounded,
                onPressed: () => _pickDate(from: true),
              ),
            ),
            const HGap(10),
            Expanded(
              child: GhostButton(
                label: _draft.dateTo ?? l10n.ordDateTo,
                icon: Icons.event_rounded,
                onPressed: () => _pickDate(from: false),
              ),
            ),
          ],
        ),
        const VGap(8),
        TextAction(
          label: l10n.actClear,
          onPressed: () => setState(() => _draft = _draft.withDates(null, null)),
        ),
        const VGap(18),
        PrimaryButton(
          label: l10n.actApply,
          color: AppInk.orders,
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
        const VGap(8),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppInk.orders : AppInk.surfaceDim,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.foot,
            fontWeight: AppType.semi,
            color: selected ? Colors.white : AppInk.textSecondary,
          ),
        ),
      ),
    );
  }
}
