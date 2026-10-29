import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../core/print_sheet.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart' show RowCard, Thumbnail;
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import 'order_create_screen.dart' show pickProductForOrder;

/// 订单详情：草稿可改，已定稿只读。
///
/// 定稿是服务端一支原子 RPC（任一商品不足整单回滚），失败文案由服务端给出，
/// 客户端原样展示；明细改数量同样会重算应收，所以每次写完都要重读整单。
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.focusPayment = false,
  });

  final String orderId;
  final bool focusPayment;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final Repos _repos = context.read<AppState>().repos;

  Order? _order;
  List<PaymentRecord> _payments = const <PaymentRecord>[];
  Map<int, PickingMark> _marks = <int, PickingMark>{};
  bool _loading = true;
  bool _busy = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      // 从欠款列表/工作台「收款」入口进来时，读完单就直接弹收款抽屉。
      if (mounted && widget.focusPayment) await _openPayment();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ApiResponse<Order> res = await _repos.orders.detail(widget.orderId);
      final Order order = res.data;
      final List<PickingMark> marks = order.showInPickingList
          ? await _repos.orders.pickingMarks(orderId: order.id)
          : const <PickingMark>[];
      final List<PaymentRecord> payments = order.type == OrderType.outbound
          ? await _repos.orders.payments(order.id)
          : const <PaymentRecord>[];
      if (!mounted) return;
      setState(() {
        _order = order;
        _marks = <int, PickingMark>{
          for (final PickingMark mark in marks) mark.itemIndex: mark,
        };
        _payments = payments;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      final AppState app = AppState.of(context);
      setState(() {
        _error = app.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? okMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (okMessage != null) showToast(context, okMessage);
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, AppState.of(context).describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ 备货勾选

  /// `item_index` 就是明细数组下标：服务端主键是 `(order_id, item_index)`，
  /// 网页端备货页读的是同一支 `shapeOrders` 顺序，两端保持一致。
  Future<void> _setPicked(int index, int quantity, int max) => _run(() async {
        final AppState app = AppState.of(context);
        final Order order = _order!;
        await app.guardWrite<void>(() async {
          if (quantity <= 0) {
            await _repos.orders.clearPickingMark(order.id, index);
          } else {
            await _repos.orders.savePickingMark(
              orderId: order.id,
              itemIndex: index,
              pickedCount: quantity,
              maxQuantity: max,
            );
          }
        });
      });

  Future<void> _togglePickingList(bool visible) => _run(() async {
        final AppState app = AppState.of(context);
        await app.guardWrite<void>(
          () => _repos.orders.setPickingList(_order!.id, visible),
        );
      });

  // ------------------------------------------------------------ 明细

  Future<void> _addItem() async {
    final AppState app = AppState.of(context);
    final Order order = _order!;
    final bool inbound = order.type == OrderType.inbound;
    final Product? picked = await pickProductForOrder(context, inbound: inbound);
    if (picked == null || !mounted) return;
    final int? quantity = await _askQuantity(
      title: picked.name,
      initial: 1,
      unit: picked.unit,
      accent: inbound ? AppInk.finance : AppInk.products,
    );
    if (quantity == null || !mounted) return;
    // 出库单加行时服务端就会校验现存量，「库存不足」原文直接回显。
    await _run(() => app.guardWrite<void>(() async {
          await _repos.orders.addItem(order.id, <String, Object?>{
            'product_id': picked.id,
            'quantity': quantity,
          });
        }));
  }

  Future<void> _editItem(OrderItem item) async {
    final AppState app = AppState.of(context);
    final int? quantity = await _askQuantity(
      title: item.productName.isEmpty ? item.productSku : item.productName,
      initial: item.quantity,
      accent: AppInk.products,
    );
    if (quantity == null || quantity == item.quantity || !mounted) return;
    await _run(() => app.guardWrite<void>(() async {
          // 服务端只持久化 quantity 与重算出的 subtotal，unit_price 必须原样回传，
          // 否则 subtotal 会按 0 单价重算。
          await _repos.orders.updateItem(item.id!, <String, Object?>{
            'quantity': quantity,
            'unit_price': item.unitPrice,
          });
        }));
  }

  Future<void> _removeItem(OrderItem item) async {
    final AppState app = AppState.of(context);
    final bool sure = await confirmAction(
      context,
      title: item.productName,
      message: app.l10n.ordDeleteConfirm,
      confirmLabel: app.l10n.actDelete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    await _run(
      () => app.guardWrite<void>(() async {
        await _repos.orders.removeItem(item.id!);
      }),
      okMessage: app.l10n.commonDeleted,
    );
  }

  // ------------------------------------------------------------ 整单

  Future<void> _finalize() async {
    final AppState app = AppState.of(context);
    final bool sure = await confirmAction(
      context,
      title: app.l10n.ordFinalise,
      message: app.l10n.ordFinaliseHint,
      confirmLabel: app.l10n.ordFinalise,
    );
    if (!sure || !mounted) return;
    await _run(
      () => app.guardWrite<void>(() async {
        await _repos.orders.finalize(_order!.id);
      }),
      okMessage: app.l10n.ordFinalisedOk,
    );
  }

  Future<void> _delete() async {
    final AppState app = AppState.of(context);
    final bool sure = await confirmAction(
      context,
      title: _order!.orderNumber,
      message: app.l10n.ordDeleteConfirm,
      confirmLabel: app.l10n.actDelete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await app.guardWrite<void>(() => _repos.orders.remove(_order!.id));
      if (!mounted) return;
      showToast(context, app.l10n.commonDeleted);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }

  // ------------------------------------------------------------ 打印单据

  /// 单据在客户端出 PDF：读一次 `/print-settings`（模板尺寸与三个显示开关），排好版
  /// 再交给系统打印面板。纸张尺寸由模板定死，不让面板二次排版；收款信息照网页端约定
  /// 不上单据。
  Future<void> _print() async {
    final AppState app = AppState.of(context);
    final Order? order = _order;
    if (order == null || _busy || _printing) return;
    setState(() => _printing = true);
    try {
      final PrintSettings settings = await _repos.settings.printSettings();
      final Uint8List pdf = await OrderSheet.build(
        order: order,
        settings: settings,
        l10n: app.l10n,
        currencySymbol: app.profile.currencySymbol,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        name: order.orderNumber,
        dynamicLayout: false,
        onLayout: (_) async => pdf,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _openPayment() async {
    final AppState app = AppState.of(context);
    final Order? order = _order;
    if (order == null || order.type != OrderType.outbound) return;
    final PaymentDraft? draft = await showDrawer<PaymentDraft>(
      context,
      accent: AppInk.finance,
      title: app.l10n.ordPayment,
      builder: (BuildContext sheetContext) => PaymentSheet(
        order: order,
        currency: app.profile.currencySymbol,
        l10n: app.l10n,
      ),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => app.guardWrite<void>(() async {
        await _repos.orders.recordPayment(order.id, <String, Object?>{
          'received_amount': draft.received,
          'method': draft.method,
          'paid_at': Fmt.isoDate(draft.paidAt),
          if (draft.notes.isNotEmpty) 'notes': draft.notes,
        });
      }),
      okMessage: app.l10n.commonSaved,
    );
  }

  Future<int?> _askQuantity({
    required String title,
    required int initial,
    String? unit,
    required Color accent,
  }) {
    return showDrawer<int>(
      context,
      accent: accent,
      title: title,
      maxHeightFactor: 0.5,
      builder: (BuildContext sheetContext) => _QuantitySheet(
        initial: initial,
        unit: unit,
        accent: accent,
      ),
    );
  }

  // ------------------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final Order? order = _order;

    final bool draft = order?.status == OrderStatus.pending;
    final bool canPay = order != null &&
        order.type == OrderType.outbound &&
        order.outstandingAmount > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order?.orderNumber ?? l10n.navOrders,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (order != null)
            IconButton(
              tooltip: l10n.ordPrintTitle,
              onPressed: _busy || _printing ? null : _print,
              icon: _printing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
            ),
          if (order != null && draft && app.canWrite)
            IconButton(
              tooltip: l10n.actDelete,
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppInk.danger),
            ),
        ],
      ),
      bottomNavigationBar: order == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (draft && app.canWrite) ...<Widget>[
                      GhostButton(
                        label: l10n.ordAddItem,
                        icon: Icons.add_rounded,
                        onPressed: _busy ? null : _addItem,
                      ),
                      const VGap(10),
                    ],
                    if (draft && app.canWrite)
                      PrimaryButton(
                        label: l10n.ordFinalise,
                        icon: Icons.check_circle_outline_rounded,
                        color: AppInk.orders,
                        loading: _busy,
                        onPressed: _busy ? null : _finalize,
                      )
                    else if (canPay && app.canWrite)
                      PrimaryButton(
                        label: '${l10n.ordPayment} · ${app.formatMoney(order.outstandingAmount)}',
                        icon: Icons.payments_outlined,
                        color: AppInk.finance,
                        loading: _busy,
                        onPressed: _busy ? null : _openPayment,
                      ),
                  ],
                ),
              ),
            ),
      body: _buildBody(app, l10n, order, draft),
    );
  }

  Widget _buildBody(AppState app, L10n l10n, Order? order, bool draft) {
    if (_loading && order == null) return const SkeletonList(count: 5);
    if (order == null) {
      return AppErrorView(message: _error ?? l10n.commonErrorTitle, onRetry: _load);
    }

    final Color accent = order.type == OrderType.inbound
        ? AppInk.finance
        : AppInk.products;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppInk.orders,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
        children: <Widget>[
          if (!app.online)
            NoticeBanner(
              text: l10n.commonOfflineBanner,
              color: AppInk.warning,
              icon: Icons.wifi_off_rounded,
            ),
          _SummaryCard(order: order, l10n: l10n, app: app, accent: accent),
          const VGap(14),
          if (order.showInPickingList) ...<Widget>[
            _PickingCard(
              order: order,
              marks: _marks,
              l10n: l10n,
              busy: _busy,
              onPicked: _setPicked,
            ),
            const VGap(14),
          ] else if (draft && app.canWrite)
            AppCard(
              accent: AppInk.showroom,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: SwitchListTile(
                value: order.showInPickingList,
                onChanged: _busy ? null : _togglePickingList,
                title: Text(l10n.ordShowInPicking),
                subtitle: Text(l10n.ordPickingListHint,
                    style: Theme.of(context).textTheme.bodySmall),
                activeThumbColor: AppInk.showroom,
              ),
            ),
          if (!app.canWrite && draft) ...<Widget>[
            const VGap(14),
            NoticeBanner(
              text: l10n.setWriteBlockedOffline,
              color: AppInk.warning,
              icon: Icons.lock_outline_rounded,
            ),
          ],
          const VGap(18),
          SectionHeader(
            title: '${l10n.ordItems} · ${order.itemCount}',
            accent: accent,
            subtitle: draft ? null : l10n.ordFinaliseHint,
          ),
          if (order.items.isEmpty)
            AppCard(
              accent: accent,
              child: Text(l10n.commonEmptyTitle,
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            for (int index = 0; index < order.items.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItemRow(
                  item: order.items[index],
                  index: index,
                  order: order,
                  app: app,
                  l10n: l10n,
                  editable: draft && app.canWrite,
                  picked: _marks[index]?.pickedCount ?? 0,
                  onEdit: () => _editItem(order.items[index]),
                  onRemove: () => _removeItem(order.items[index]),
                ),
              ),
          if (_payments.isNotEmpty) ...<Widget>[
            const VGap(18),
            SectionHeader(title: l10n.finRecords, accent: AppInk.finance),
            AppCard(
              accent: AppInk.finance,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: <Widget>[
                  for (final PaymentRecord record in _payments)
                    _PaymentLine(record: record, app: app, l10n: l10n),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.order,
    required this.l10n,
    required this.app,
    required this.accent,
  });

  final Order order;
  final L10n l10n;
  final AppState app;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool outbound = order.type == OrderType.outbound;
    return AppCard(
      accent: AppInk.orders,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusPill(
                label: outbound ? l10n.ordOutbound : l10n.ordInbound,
                color: accent,
                icon: outbound ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              ),
              const HGap(6),
              StatusPill(
                label: order.status == OrderStatus.pending ? l10n.ordPending : l10n.ordCompleted,
                color: order.status == OrderStatus.pending ? AppInk.textSecondary : AppInk.success,
              ),
              if (order.isPreparing && order.status == OrderStatus.pending) ...<Widget>[
                const HGap(6),
                StatusPill(label: l10n.dashPicking, color: AppInk.showroom),
              ],
            ],
          ),
          const VGap(14),
          KeyValueRow(label: l10n.ordCustomer, value: order.customerName),
          KeyValueRow(label: l10n.ordDate, value: order.orderDate ?? '—'),
          if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
            KeyValueRow(label: l10n.setCustomerPhone, value: order.customerPhone!),
          KeyValueRow(
            label: l10n.ordTotalAmount,
            value: '${Fmt.count(order.totalQuantity)} · ${app.formatMoney(order.totalAmount)}',
          ),
          if (outbound) ...<Widget>[
            KeyValueRow(label: l10n.ordPayable, value: app.formatMoney(order.payableAmount)),
            KeyValueRow(label: l10n.ordPaid, value: app.formatMoney(order.paidAmount)),
            KeyValueRow(
              label: l10n.ordOutstanding,
              value: app.formatMoney(order.outstandingAmount),
              accent: order.outstandingAmount > 0 ? AppInk.danger : AppInk.success,
            ),
          ],
          if ((order.notes ?? '').isNotEmpty) ...<Widget>[
            const VGap(6),
            Text(order.notes!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.index,
    required this.order,
    required this.app,
    required this.l10n,
    required this.editable,
    required this.picked,
    required this.onEdit,
    required this.onRemove,
  });

  final OrderItem item;
  final int index;
  final Order order;
  final AppState app;
  final L10n l10n;
  final bool editable;
  final int picked;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final int perBox = (item.unitsPerBox ?? 0) > 1 ? item.unitsPerBox! : 0;
    final String quantityText = perBox > 0
        ? '${Fmt.count(item.quantity)}（${Fmt.count(item.quantity ~/ perBox)}${l10n.unitBox}）'
        : Fmt.count(item.quantity);
    return RowCard(
      accent: order.type == OrderType.inbound ? AppInk.finance : AppInk.products,
      leading: Thumbnail(
        url: item.imageUrl ?? (item.imageUrls.isEmpty ? null : item.imageUrls.first),
      ),
      title: item.productName.isEmpty ? item.productSku : item.productName,
      subtitle: <String>[
        item.productSku,
        if ((item.categoryName ?? '').isNotEmpty) item.categoryName!,
      ].join(' · '),
      trailing: editable
          ? RoundIconButton(icon: Icons.edit_rounded, size: 38, onPressed: onEdit)
          : null,
      footRow: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$quantityText × ${app.formatMoney(item.unitPrice)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const HGap(8),
          Text(
            app.formatMoney(item.subtotal),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (editable) ...<Widget>[
            const HGap(4),
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18, color: AppInk.danger),
            ),
          ],
        ],
      ),
      badges: picked > 0
          ? <Widget>[
              StatusPill(
                label: '${l10n.ordPicked} ${Fmt.count(picked)}/${Fmt.count(item.quantity)}',
                color: picked >= item.quantity ? AppInk.success : AppInk.showroom,
                dense: true,
                icon: Icons.check_rounded,
              ),
            ]
          : const <Widget>[],
    );
  }
}

class _PickingCard extends StatelessWidget {
  const _PickingCard({
    required this.order,
    required this.marks,
    required this.l10n,
    required this.busy,
    required this.onPicked,
  });

  final Order order;
  final Map<int, PickingMark> marks;
  final L10n l10n;
  final bool busy;
  final Future<void> Function(int index, int picked, int max) onPicked;

  @override
  Widget build(BuildContext context) {
    final List<OrderItem> items = order.items;
    final int total = items.fold<int>(0, (int sum, OrderItem item) => sum + item.quantity);
    final int done = <int>[
      for (int index = 0; index < items.length; index++)
        (marks[index]?.pickedCount ?? 0).clamp(0, items[index].quantity),
    ].fold<int>(0, (int sum, int value) => sum + value);

    return AppCard(
      accent: AppInk.showroom,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: l10n.ordPickingList,
            accent: AppInk.showroom,
            subtitle: '${l10n.ordPicked} ${Fmt.count(done)}/${Fmt.count(total)}',
          ),
          for (int index = 0; index < items.length; index++)
            _PickingLine(
              item: items[index],
              picked: (marks[index]?.pickedCount ?? 0).clamp(0, items[index].quantity),
              busy: busy,
              onChanged: (int value) => onPicked(index, value, items[index].quantity),
            ),
        ],
      ),
    );
  }
}

class _PickingLine extends StatelessWidget {
  const _PickingLine({
    required this.item,
    required this.picked,
    required this.busy,
    required this.onChanged,
  });

  final OrderItem item;
  final int picked;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool done = picked >= item.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: done ? AppInk.success : AppInk.textTertiary,
          ),
          const HGap(8),
          Expanded(
            child: Text(
              item.productName.isEmpty ? item.productSku : item.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const HGap(6),
          SizedBox(
            width: 56,
            child: Text(
              '$picked/${item.quantity}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
            ),
          ),
          const HGap(4),
          RoundIconButton(
            icon: Icons.remove_rounded,
            size: 34,
            color: AppInk.showroom,
            onPressed: busy || picked <= 0 ? null : () => onChanged(picked - 1),
          ),
          const HGap(2),
          RoundIconButton(
            icon: Icons.add_rounded,
            size: 34,
            color: AppInk.showroom,
            onPressed: busy || picked >= item.quantity ? null : () => onChanged(picked + 1),
          ),
        ],
      ),
    );
  }
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine({required this.record, required this.app, required this.l10n});

  final PaymentRecord record;
  final AppState app;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.method == 'transfer' ? l10n.ordTransfer : l10n.ordCash,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  Fmt.dateTime(record.paidAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                app.formatMoney(record.applied),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppInk.finance),
              ),
              if (record.change > 0)
                Text('${l10n.ordChange} ${app.formatMoney(record.change)}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// 加行/改行的数量抽屉：绝对数量，与服务端口径一致（不做 +/- 增量）。
class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({
    required this.initial,
    required this.accent,
    this.unit,
  });

  final int initial;
  final String? unit;
  final Color accent;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late final TextEditingController _value =
      TextEditingController(text: '${widget.initial}');

  int get _number => int.tryParse(_value.text.trim()) ?? 0;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(Localizations.localeOf(context));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NumberField(
          label: l10n.prodQty,
          controller: _value,
          allowDecimal: false,
          autofocus: true,
          suffix: widget.unit ?? l10n.unitPiece,
          onChanged: (_) => setState(() {}),
        ),
        const VGap(14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            QtyStepper(
              value: _number,
              min: 1,
              onChanged: (int value) => setState(() => _value.text = '$value'),
            ),
          ],
        ),
        const VGap(18),
        PrimaryButton(
          label: l10n.actConfirm,
          icon: Icons.check_rounded,
          color: widget.accent,
          onPressed: () => Navigator.of(context).pop(_number < 1 ? null : _number),
        ),
      ],
    );
  }
}

class PaymentDraft {
  const PaymentDraft({
    required this.received,
    required this.method,
    required this.paidAt,
    required this.notes,
  });

  final double received;
  final String method;
  final DateTime paidAt;
  final String notes;
}

enum PaymentHintKind { change, shortfall, exact }

/// 收款抽屉里那条实时提示，规则抄网页端 `OrderPaymentDialog.tsx` 的 `hint`：
/// 差额 = 实收 - 未收余额，用 0.005 容差判平（浮点减法不该拿 `== 0` 比），
/// 实收还没填就整条不出。三态必须都露出来 —— 只报找零、把欠的钳成 0，
/// 用户看着「找零 $0.00」一动不动，读起来就是这块没在刷新。
({PaymentHintKind kind, double amount})? paymentHint({
  required double received,
  required double outstanding,
}) {
  if (received <= 0) return null;
  final double diff = received - outstanding;
  if (diff > 0.005) {
    return (kind: PaymentHintKind.change, amount: diff);
  }
  if (diff < -0.005) {
    return (kind: PaymentHintKind.shortfall, amount: -diff);
  }
  return (kind: PaymentHintKind.exact, amount: 0);
}

/// 收款抽屉：只提交实收/方式/日期/备注，找零与冲抵由服务端算。
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.order,
    required this.currency,
    required this.l10n,
  });

  final Order order;
  final String currency;
  final L10n l10n;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final TextEditingController _received =
      TextEditingController(text: widget.order.outstandingAmount.toStringAsFixed(2));
  final TextEditingController _notes = TextEditingController();

  String _method = 'cash';
  DateTime _paidAt = DateTime.now();

  double get _amount => double.tryParse(_received.text.trim()) ?? 0;

  @override
  void dispose() {
    _received.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = widget.l10n;
    final double outstanding = widget.order.outstandingAmount;
    final ({PaymentHintKind kind, double amount})? hint =
        paymentHint(received: _amount, outstanding: outstanding);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyValueRow(label: l10n.ordPayable, value: Fmt.money(outstanding, symbol: widget.currency)),
        const VGap(12),
        PillTabs<String>(
          values: const <String>['cash', 'transfer'],
          selected: _method,
          accent: AppInk.finance,
          scrollable: false,
          labelOf: (String value) => value == 'cash' ? l10n.ordCash : l10n.ordTransfer,
          onChanged: (String value) => setState(() => _method = value),
        ),
        const VGap(12),
        NumberField(
          label: l10n.ordReceived,
          controller: _received,
          prefix: widget.currency,
          onChanged: (_) => setState(() {}),
        ),
        const VGap(10),
        if (hint != null) ...<Widget>[
          _HintBand(
            text: switch (hint.kind) {
              PaymentHintKind.change => l10n.ordHintChange(
                  Fmt.money(hint.amount, symbol: widget.currency),
                ),
              PaymentHintKind.shortfall => l10n.ordHintShort(
                  Fmt.money(hint.amount, symbol: widget.currency),
                ),
              PaymentHintKind.exact => l10n.ordHintExact,
            },
            color: switch (hint.kind) {
              PaymentHintKind.change => AppInk.warning,
              PaymentHintKind.shortfall => AppInk.danger,
              PaymentHintKind.exact => AppInk.success,
            },
            icon: switch (hint.kind) {
              PaymentHintKind.change => Icons.savings_rounded,
              PaymentHintKind.shortfall => Icons.pending_actions_rounded,
              PaymentHintKind.exact => Icons.check_circle_outline_rounded,
            },
          ),
          const VGap(10),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextAction(
            label: '${l10n.ordDate} · ${Fmt.date(_paidAt)}',
            color: AppInk.finance,
            onPressed: _pickDate,
          ),
        ),
        const VGap(12),
        AppTextField(label: l10n.ordNotes, controller: _notes, hint: l10n.ordNotesHint),
        const VGap(18),
        PrimaryButton(
          label: l10n.ordPayment,
          icon: Icons.check_rounded,
          color: AppInk.finance,
          onPressed: _amount <= 0
              ? null
              : () => Navigator.of(context).pop(PaymentDraft(
                    received: _amount,
                    method: _method,
                    paidAt: _paidAt,
                    notes: _notes.text.trim(),
                  )),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paidAt = picked);
  }
}

/// 实时提示条：色底 + 图标 + 一句话，随输入逐键重算。
class _HintBand extends StatelessWidget {
  const _HintBand({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppInk.tint(color, alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const HGap(8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
