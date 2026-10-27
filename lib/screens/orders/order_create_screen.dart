import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart' show RowCard, Thumbnail;
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// 明细行选商品：开单页与订单详情页共用同一支搜索抽屉。
/// 入库默认带出成本、出库默认带出售价，方向决定预填价。
Future<Product?> pickProductForOrder(BuildContext context, {required bool inbound}) =>
    pushSheet<Product>(context, child: _ProductSearchSheet(inbound: inbound));

/// 开单：一屏完成「方向 / 客户 / 明细」，底部两颗键分别对应草稿与定稿。
///
/// 建单永远先存成 `is_preparing: true` 的草稿 —— 服务端只有定稿才动库存，
/// 客户端不做任何本地库存增减；明细至少一行，服务端拒绝空单。
class OrderCreateScreen extends StatefulWidget {
  const OrderCreateScreen({super.key, this.inbound = false});

  final bool inbound;

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

/// 本地明细行：数量按「整箱 × 每箱数 + 散件」组合录入，服务端只吃绝对 `quantity`。
class _DraftLine {
  _DraftLine({
    required this.product,
    required this.unitPrice,
    this.loose = 0,
  });

  final Product product;
  double unitPrice;
  int boxCount = 0;
  int loose;

  int get perBox => (product.unitsPerBox ?? 0) > 1 ? product.unitsPerBox! : 0;

  int get quantity => perBox > 0 ? boxCount * perBox + loose : loose;

  set quantity(int value) {
    if (perBox > 0) {
      boxCount = value ~/ perBox;
      loose = value % perBox;
    } else {
      boxCount = 0;
      loose = value;
    }
  }

  double get subtotal => double.parse((quantity * unitPrice).toStringAsFixed(2));

  Map<String, Object?> toPayload() => <String, Object?>{
        'product_id': product.id,
        'product_name': product.name,
        'product_sku': product.sku,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'box_count': boxCount,
        'units_per_box': perBox > 0 ? perBox : null,
      };
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final List<_DraftLine> _lines = <_DraftLine>[];
  final TextEditingController _notes = TextEditingController();

  bool _inbound = false;
  DateTime _date = DateTime.now();
  Customer? _customer;
  List<Customer> _customers = const <Customer>[];
  bool _showInPicking = false;
  bool _busy = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _inbound = widget.inbound;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final AppState app = AppState.of(context);
    try {
      final List<Customer> rows = await app.repos.settings.customers();
      if (mounted) setState(() => _customers = rows);
    } on Object {
      // 客户只是可选项，拉不到不影响开单。
    }
  }

  int get _totalQty => _lines.fold<int>(0, (int sum, _DraftLine l) => sum + l.quantity);

  double get _totalAmount =>
      double.parse(_lines.fold<double>(0, (double sum, _DraftLine l) => sum + l.subtotal).toStringAsFixed(2));

  Future<void> _pickProduct() async {
    final Product? picked =
        await pickProductForOrder(context, inbound: _inbound);
    if (picked == null) return;
    setState(() {
      final int existing = _lines.indexWhere((_DraftLine l) => l.product.id == picked.id);
      if (existing >= 0) {
        _lines[existing].quantity += 1;
      } else {
        _lines.add(_DraftLine(
          product: picked,
          unitPrice: _inbound ? picked.cost : picked.price,
          loose: 1,
        ));
      }
    });
  }

  Future<void> _scanReceipt() async {
    final AppState app = AppState.of(context);
    if (_scanning) return;
    final ImageSource? source = await showDrawer<ImageSource>(
      context,
      accent: AppInk.ai,
      title: app.l10n.ordVision,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TileRow(
            icon: Icons.photo_camera_rounded,
            title: app.l10n.prodShootCamera,
            accent: AppInk.ai,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          TileRow(
            icon: Icons.photo_library_rounded,
            title: app.l10n.prodShootAlbum,
            accent: AppInk.ai,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null) return;

    setState(() => _scanning = true);
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      final String dataUrl =
          'data:image/jpeg;base64,${base64Encode(await file.readAsBytes())}';
      final List<VisionLine> rows =
          await app.repos.orders.visionDraft(dataUrl: dataUrl);
      if (!mounted) return;
      await _applyVision(rows);
    } on Object catch (error) {
      if (mounted) {
        showToast(context, app.describeError(error), danger: true);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// 识别结果只填 matched 且非歧义的行；歧义行必须人工从候选里选，服务端刻意不猜 top-1。
  Future<void> _applyVision(List<VisionLine> rows) async {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final List<VisionLine> ambiguous = rows
        .where((VisionLine line) => line.needsManualPick && line.candidates.isNotEmpty)
        .toList(growable: false);

    for (final VisionLine line in rows) {
      final Product? product = line.product;
      if (product == null || !line.matched) continue;
      _addVisionLine(product, line.qty);
    }
    setState(() {});

    if (ambiguous.isNotEmpty) {
      showToast(context, l10n.ordVisionAmbiguous(ambiguous.length));
      for (final VisionLine line in ambiguous) {
        final Product? chosen = await showDrawer<Product>(
          context,
          accent: AppInk.ai,
          title: l10n.ordVisionPick,
          builder: (BuildContext sheetContext) => _CandidateSheet(
            line: line,
            l10n: l10n,
          ),
        );
        if (chosen != null) _addVisionLine(chosen, line.qty);
      }
      setState(() {});
    }
  }

  void _addVisionLine(Product product, int qty) {
    final int quantity = qty <= 0 ? 1 : qty;
    final int existing = _lines.indexWhere((_DraftLine l) => l.product.id == product.id);
    if (existing >= 0) {
      _lines[existing].quantity += quantity;
      return;
    }
    _lines.add(_DraftLine(
      product: product,
      unitPrice: product.price > 0 ? product.price : _inbound ? product.cost : 0,
    )..quantity = quantity);
  }

  Future<void> _save({required bool finalize}) async {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    if (_lines.isEmpty || _lines.every((_DraftLine l) => l.quantity <= 0)) {
      showToast(context, l10n.ordEmptyItems, danger: true);
      return;
    }
    if (!app.canWrite) {
      showToast(context, l10n.setWriteBlockedOffline, danger: true);
      return;
    }

    setState(() => _busy = true);
    String? orderId;
    try {
      orderId = await app.guardWrite<String>(() => app.repos.orders.createDraft(
            orderData: <String, Object?>{
              'type': _inbound ? 'inbound' : 'outbound',
              'status': 'pending',
              'is_preparing': !finalize,
              'order_date': Fmt.isoDate(_date),
              'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              'customer_id': _customer?.id,
            },
            items: _lines
                .where((_DraftLine l) => l.quantity > 0)
                .map((_DraftLine l) => l.toPayload())
                .toList(growable: false),
            showInPickingList: _showInPicking,
          ));
      if (finalize && orderId.isNotEmpty) {
        await app.repos.orders.finalize(orderId);
      }
      if (!mounted) return;
      showToast(context, finalize ? l10n.ordFinalisedOk : l10n.ordSavedDraft);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final String detail = app.describeError(error);
      if (orderId != null && orderId.isNotEmpty) {
        // 单已经落成草稿（定稿失败＝没动库存），此时留在本页会诱导重复建单，直接退出。
        showToast(context, l10n.ordDeductFailed(detail), danger: true);
        Navigator.of(context).pop();
      } else {
        showToast(context, detail, danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ordNew),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.ordVision,
            onPressed: _scanning || _busy ? null : _scanReceipt,
            icon: _scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
        children: <Widget>[
          if (!app.online)
            NoticeBanner(
              text: l10n.setWriteBlockedOffline,
              color: AppInk.warning,
              icon: Icons.wifi_off_rounded,
            ),
          AppCard(
            accent: _inbound ? AppInk.finance : AppInk.products,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DirectionSwitch(
                  inbound: _inbound,
                  inboundLabel: l10n.ordInbound,
                  outboundLabel: l10n.ordOutbound,
                  onChanged: (bool value) => setState(() => _inbound = value),
                ),
                const VGap(14),
                KeyValueRow(
                  label: l10n.ordDate,
                  value: Fmt.isoDate(_date),
                ),
                TextAction(
                  label: l10n.actEdit,
                  color: _inbound ? AppInk.finance : AppInk.products,
                  onPressed: _pickDate,
                ),
                const VGap(8),
                _CustomerRow(
                  label: l10n.ordCustomer,
                  name: _customer?.name,
                  onTap: _pickCustomer,
                  onClear: _customer == null
                      ? null
                      : () => setState(() => _customer = null),
                ),
                const VGap(8),
                AppTextField(
                  label: l10n.ordNotes,
                  controller: _notes,
                  maxLines: 2,
                  hint: l10n.ordNotesHint,
                ),
                const VGap(6),
                SwitchListTile(
                  value: _showInPicking,
                  onChanged: (bool v) => setState(() => _showInPicking = v),
                  title: Text(l10n.ordShowInPicking,
                      style: const TextStyle(fontSize: AppType.body)),
                  subtitle: Text(l10n.ordPickingListHint,
                      style: Theme.of(context).textTheme.bodySmall),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppInk.orders,
                ),
              ],
            ),
          ),
          const VGap(14),
          SectionHeader(
            title: l10n.ordItems,
            accent: AppInk.orders,
            trailing: RoundIconButton(
              icon: Icons.add_rounded,
              color: AppInk.orders,
              tooltip: l10n.ordAddItem,
              onPressed: _pickProduct,
            ),
          ),
          if (_lines.isEmpty)
            AppCard(
              accent: AppInk.orders,
              onTap: _pickProduct,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.add_shopping_cart_rounded, color: AppInk.orders),
                  const HGap(10),
                  Expanded(
                    child: Text(
                      l10n.ordAddItem,
                      style: const TextStyle(
                          fontSize: AppType.body, fontWeight: AppType.semi, color: AppInk.orders),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int index = 0; index < _lines.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LineCard(
                  line: _lines[index],
                  currency: app.profile.currencySymbol,
                  accent: _inbound ? AppInk.finance : AppInk.products,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _lines.removeAt(index)),
                ),
              ),
          const VGap(14),
          AppCard(
            accent: AppInk.orders,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.ordTotalAmount,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${Fmt.count(_totalQty)} ${l10n.unitPiece} · ${Fmt.money(_totalAmount, symbol: app.profile.currencySymbol)}',
                  style: const TextStyle(
                      fontSize: AppType.head, fontWeight: AppType.heavy, color: AppInk.orders),
                ),
              ],
            ),
          ),
          const VGap(16),
          PrimaryButton(
            label: _busy ? l10n.commonSaving : l10n.ordCreateAndFinalize,
            icon: Icons.check_circle_rounded,
            color: _inbound ? AppInk.finance : AppInk.orders,
            loading: _busy,
            onPressed: app.canWrite && !_busy ? () => _save(finalize: true) : null,
          ),
          const VGap(10),
          GhostButton(
            label: l10n.ordSaveDraft,
            icon: Icons.edit_outlined,
            onPressed: app.canWrite && !_busy ? () => _save(finalize: false) : null,
          ),
          const VGap(8),
          Text(
            _inbound ? l10n.ordFinaliseInHint : l10n.ordFinaliseHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCustomer() async {
    final AppState app = AppState.of(context);
    final Customer? picked = await showDrawer<Customer>(
      context,
      accent: AppInk.orders,
      title: app.l10n.ordPickCustomer,
      builder: (BuildContext sheetContext) {
        if (_customers.isEmpty) {
          return AppEmpty(
            title: app.l10n.commonEmptyTitle,
            hint: app.l10n.setCustomersInSettings,
            icon: Icons.people_outline_rounded,
            accent: AppInk.orders,
          );
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            for (final Customer customer in _customers)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(customer.name),
                subtitle: customer.phone == null ? null : Text(customer.phone!),
                trailing: const Icon(Icons.check_rounded, size: 18, color: AppInk.orders),
                onTap: () => Navigator.of(sheetContext).pop(customer),
              ),
          ],
        );
      },
    );
    if (picked != null) setState(() => _customer = picked);
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.label,
    required this.name,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? name;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: Radii.chip_,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    const VGap(2),
                    Text(
                      name ?? l10n.ordNoCustomer,
                      style: TextStyle(
                        fontSize: AppType.head,
                        fontWeight: AppType.semi,
                        color: name == null ? AppInk.textTertiary : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onClear != null)
            RoundIconButton(icon: Icons.close_rounded, onPressed: onClear, size: 38),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.currency,
    required this.accent,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftLine line;
  final String currency;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return AppCard(
      accent: accent,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Thumbnail(url: line.product.imageUrl, size: 40),
              const HGap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(line.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(line.product.sku, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              RoundIconButton(
                icon: Icons.delete_outline_rounded,
                color: AppInk.danger,
                size: 38,
                onPressed: onRemove,
              ),
            ],
          ),
          const VGap(10),
          if (line.perBox > 0) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _MiniStepper(
                    label: '${l10n.unitBox} × ${line.perBox}',
                    value: line.boxCount,
                    accent: accent,
                    onChanged: (int v) {
                      line.boxCount = v;
                      onChanged();
                    },
                  ),
                ),
                const HGap(10),
                Expanded(
                  child: _MiniStepper(
                    label: l10n.ordLooseCount,
                    value: line.loose,
                    accent: accent,
                    onChanged: (int v) {
                      line.loose = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ] else
            _MiniStepper(
              label: l10n.prodQty,
              value: line.quantity,
              accent: accent,
              onChanged: (int v) {
                line.quantity = v;
                onChanged();
              },
            ),
          const VGap(10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: _InlinePrice(
                  value: line.unitPrice,
                  currency: currency,
                  onChanged: (double v) {
                    line.unitPrice = v;
                    onChanged();
                  },
                ),
              ),
              const HGap(10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(l10n.commonTotal, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    Fmt.money(line.subtotal, symbol: currency),
                    style: const TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy),
                  ),
                ],
              ),
            ],
          ),
          if (line.perBox > 0) ...<Widget>[
            const VGap(6),
            Text(
              '${Fmt.count(line.quantity)}${line.product.unit}',
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const VGap(4),
        Row(
          children: <Widget>[
            RoundIconButton(
              icon: Icons.remove_rounded,
              color: accent,
              size: 36,
              onPressed: value <= 0 ? null : () => onChanged(value - 1),
            ),
            Expanded(
              child: Text('$value', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy)),
            ),
            RoundIconButton(
              icon: Icons.add_rounded,
              color: accent,
              size: 36,
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlinePrice extends StatefulWidget {
  const _InlinePrice({
    required this.value,
    required this.currency,
    required this.onChanged,
  });

  final double value;
  final String currency;
  final ValueChanged<double> onChanged;

  @override
  State<_InlinePrice> createState() => _InlinePriceState();
}

class _InlinePriceState extends State<_InlinePrice> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toStringAsFixed(2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = AppState.of(context).l10n;
    return AppTextField(
      label: '${l10n.ordUnitPrice}（${widget.currency}）',
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onChanged: (String raw) {
        final double? parsed = double.tryParse(raw.trim());
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}

/// 商品选择页：服务端 `/products/search` 已经做了模糊匹配与清洗，客户端不再二次打分。
class _ProductSearchSheet extends StatefulWidget {
  const _ProductSearchSheet({required this.inbound});

  final bool inbound;

  @override
  State<_ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<_ProductSearchSheet> {
  final TextEditingController _search = TextEditingController();
  List<Product> _rows = const <Product>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String keyword) async {
    final AppState app = AppState.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Product> rows = keyword.trim().isEmpty
          ? (await app.repos.products.list(pageSize: 30, orderBy: 'updated_at')).data.rows
          : await app.repos.products.search(keyword.trim());
      if (mounted) setState(() => _rows = rows);
    } on Object catch (error) {
      if (mounted) setState(() => _error = app.describeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ordPickProduct)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 8),
            child: SearchField(
              controller: _search,
              hintText: l10n.prodSearchHint,
              autofocus: true,
              onChanged: (String value) {
                if (value.trim().length < 2 && value.trim().isNotEmpty) return;
                _run(value);
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: NoticeBanner(text: _error!, color: AppInk.danger),
            ),
          Expanded(
            child: _loading
                ? const SkeletonList(count: 5, itemHeight: 68)
                : _rows.isEmpty
                    ? AppEmpty(
                        title: l10n.commonEmptyTitle,
                        hint: l10n.prodSearchHint,
                        icon: Icons.search_rounded,
                        accent: AppInk.orders,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 32),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const VGap(8),
                        itemBuilder: (BuildContext context, int index) {
                          final Product row = _rows[index];
                          return RowCard(
                            accent: widget.inbound ? AppInk.finance : AppInk.products,
                            onTap: () => Navigator.of(context).pop(row),
                            title: row.name,
                            subtitle: '${row.sku} · ${widget.inbound ? l10n.prodCost : l10n.prodPrice} '
                                '${Fmt.money(widget.inbound ? row.cost : row.price, symbol: app.profile.currencySymbol)}',
                            leading: Thumbnail(url: row.imageUrl, size: 40),
                            trailing: Text(
                              '${Fmt.count(row.quantity)}${row.unit}',
                              style: const TextStyle(fontSize: AppType.foot),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.line, required this.l10n});

  final VisionLine line;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (line.hintLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${l10n.ordVisionHint}：${line.hintLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final VisionCandidate candidate in line.candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              accent: AppInk.ai,
              padding: const EdgeInsets.all(12),
              onTap: () => Navigator.of(context).pop(candidate.product),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(candidate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${candidate.sku} · ${Fmt.count(candidate.product.quantity)}${candidate.product.unit}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (candidate.matchKind.isSkuBased)
                    StatusPill(
                      label: candidate.matchKind.name,
                      color: AppInk.ai,
                      dense: true,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
