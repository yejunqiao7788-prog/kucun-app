import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';

/// 商品编辑器。
///
/// 服务端 PATCH 是**整行替换**（不传的字段回到默认：价格 0、描述 null、库存 0、图清空），
/// 所以保存时永远提交完整载荷；`sku` 与 `name` 是硬必填。
/// 图片只能带公开桶回来的 http(s) 地址，最多 5 张，第一张即封面。
Future<bool> openProductEditor(BuildContext context, {Product? product}) async {
  final bool? saved = await pushSheet<bool>(
    context,
    child: ProductEditScreen(product: product),
  );
  return saved ?? false;
}

class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({super.key, this.product, this.focusQuantity = false});

  final Product? product;
  final bool focusQuantity;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final FocusNode _qtyFocus = FocusNode();
  late final List<String> _images = <String>[...?widget.product?.imageUrls];

  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final TextEditingController _price = _decimal(widget.product?.price);
  late final TextEditingController _cost = _decimal(widget.product?.cost);
  late final TextEditingController _unit = TextEditingController(text: widget.product?.unit ?? '');
  late final TextEditingController _qty = TextEditingController(text: '${widget.product?.quantity ?? 0}');
  late final TextEditingController _min = TextEditingController(text: '${widget.product?.minStock ?? 0}');
  late final TextEditingController _max = TextEditingController(text: '${widget.product?.maxStock ?? 1000}');
  late final TextEditingController _location = TextEditingController(text: widget.product?.location ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.product?.description ?? '');
  late final TextEditingController _perBox = TextEditingController(
    text: (widget.product?.unitsPerBox ?? 0) > 1 ? '${widget.product!.unitsPerBox}' : '',
  );
  late final TextEditingController _boxPrice = _decimal(widget.product?.boxPrice);

  List<Category> _categories = const <Category>[];
  String? _categoryId;
  bool _categoryTouched = false;
  late bool _perBoxOn = (widget.product?.unitsPerBox ?? 0) > 1;
  bool _uploading = false;
  bool _saving = false;

  /// 成交行只在编辑已有商品时才有意义，新建态不构造这个加载器。
  late final ValueLoader<List<ProductHistoryEntry>> _history =
      ValueLoader<List<ProductHistoryEntry>>(
    () => context.read<AppState>().repos.orders.productHistory(widget.product!.id, limit: 8),
  );

  bool get _isNew => widget.product == null;

  static TextEditingController _decimal(double? value) =>
      TextEditingController(text: (value ?? 0) == 0 ? '' : value!.toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    _categoryId = widget.product?.categoryId;
    unawaited(_loadCategories());
    if (!_isNew) {
      _history.addListener(_repaint);
      unawaited(_history.load());
    }
    if (widget.focusQuantity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _qtyFocus.requestFocus();
      });
    }
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCategories() async {
    final AppState app = AppState.of(context);
    try {
      final List<Category> rows = await app.repos.products.categories();
      if (!mounted) return;
      setState(() => _categories = rows);
    } on Object {
      // 类目只是可选项，拉不到不影响编辑。
    }
  }

  @override
  void dispose() {
    if (!_isNew) {
      _history.removeListener(_repaint);
      _history.dispose();
    }
    _qtyFocus.dispose();
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    _unit.dispose();
    _qty.dispose();
    _min.dispose();
    _max.dispose();
    _location.dispose();
    _description.dispose();
    _perBox.dispose();
    _boxPrice.dispose();
    super.dispose();
  }

  double _asDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  int _asInt(TextEditingController controller, {int fallback = 0}) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _pickImage(ImageSource source) async {
    final AppState app = AppState.of(context);
    final XFile? file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (file == null) return;
    if (!mounted) return;
    if (_images.length >= 5) {
      showToast(context, app.l10n.prodImagesMax, danger: true);
      return;
    }
    setState(() => _uploading = true);
    try {
      final String url = await app.storage.uploadProductImage(
        tenantId: app.profile.tenantId,
        bytes: await file.readAsBytes(),
        fileName: file.name,
        sequence: _images.length,
      );
      if (!mounted) return;
      setState(() => _images.add(url));
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addImage() async {
    if (_uploading) return;
    final AppState app = AppState.of(context);
    final ImageSource? source = await showDrawer<ImageSource>(
      context,
      accent: AppInk.marketplace,
      title: app.l10n.prodImages,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TileRow(
            icon: Icons.photo_camera_rounded,
            title: app.l10n.prodShootCamera,
            accent: AppInk.marketplace,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          TileRow(
            icon: Icons.photo_library_rounded,
            title: app.l10n.prodShootAlbum,
            accent: AppInk.marketplace,
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null) return;
    await _pickImage(source);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final AppState app = AppState.of(context);
    if (!app.canWrite) {
      showToast(context, app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    final Product? origin = widget.product;
    final bool identityChanged = origin != null &&
        (origin.sku != _sku.text.trim() || origin.name != _name.text.trim());
    final int perBox = _perBoxOn ? _asInt(_perBox) : 0;

    final Map<String, Object?> payload = <String, Object?>{
      'sku': _sku.text.trim(),
      'name': _name.text.trim(),
      'price': _asDouble(_price),
      'cost': _asDouble(_cost),
      'unit': _unit.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'units_per_box': perBox > 1 ? perBox : null,
      'box_price': perBox > 1 && _asDouble(_boxPrice) > 0 ? _asDouble(_boxPrice) : null,
      'category_id': _categoryTouched ? _categoryId : origin?.categoryId,
      'quantity': _asInt(_qty),
      'min_stock': _asInt(_min),
      'max_stock': _asInt(_max, fallback: 1000),
      'location': _location.text.trim(),
      // 空数组是「明确清空画廊」；不传这个键才会保持原图不动。
      'image_urls': _images,
      if (identityChanged) 'sync_order_items': true,
    };

    setState(() => _saving = true);
    try {
      await app.guardWrite<void>(() async {
        if (origin == null) {
          await app.repos.products.create(payload);
        } else {
          await app.repos.products.update(origin.id, payload);
        }
      });
      if (!mounted) return;
      showToast(context, app.l10n.commonSaved);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, app.describeError(error), danger: true);
    }
  }

  Future<void> _delete() async {
    final Product? origin = widget.product;
    if (origin == null) return;
    final AppState app = AppState.of(context);
    final bool sure = await confirmAction(
      context,
      title: origin.name,
      message: app.l10n.prodDeleteConfirm,
      confirmLabel: app.l10n.actDelete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await app.guardWrite<void>(() => app.repos.products.remove(origin.id));
      if (!mounted) return;
      showToast(context, app.l10n.commonDeleted);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.prodNew : l10n.prodEdit),
        actions: <Widget>[
          if (!_isNew)
            IconButton(
              tooltip: l10n.actDelete,
              onPressed: app.canWrite && !_saving ? _delete : null,
              icon: const Icon(Icons.delete_outline_rounded, color: AppInk.danger),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 40),
          children: <Widget>[
            if (!app.online)
              NoticeBanner(
                text: l10n.setWriteBlockedOffline,
                color: AppInk.warning,
                icon: Icons.wifi_off_rounded,
              ),
            _group(
              title: l10n.prodName,
              accent: AppInk.products,
              note: _isNew ? null : l10n.prodSkuLocked,
              children: <Widget>[
                AppTextField(
                  label: l10n.prodName,
                  controller: _name,
                  validator: (String? v) => (v ?? '').trim().isEmpty ? l10n.prodNameRequired : null,
                ),
                const VGap(12),
                AppTextField(
                  label: l10n.prodSku,
                  controller: _sku,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => (v ?? '').trim().isEmpty ? l10n.prodSkuRequired : null,
                ),
              ],
            ),
            _group(
              title: l10n.navInventory,
              accent: AppInk.inventory,
              note: l10n.prodStockAbsolute,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: NumberField(
                        label: l10n.prodQty,
                        controller: _qty,
                        focusNode: _qtyFocus,
                        allowDecimal: false,
                        suffix: _unit.text.trim().isEmpty ? l10n.unitPiece : _unit.text.trim(),
                      ),
                    ),
                    const HGap(10),
                    QtyStepper(
                      value: _asInt(_qty),
                      onChanged: (int value) => setState(() => _qty.text = '$value'),
                    ),
                  ],
                ),
                const VGap(12),
                Row(
                  children: <Widget>[
                    Expanded(child: NumberField(label: l10n.prodMinStock, controller: _min, allowDecimal: false)),
                    const HGap(10),
                    Expanded(child: NumberField(label: l10n.prodMaxStock, controller: _max, allowDecimal: false)),
                  ],
                ),
                const VGap(12),
                AppTextField(label: l10n.prodLocation, controller: _location, hint: l10n.invDefaultLocation),
              ],
            ),
            _group(
              title: l10n.prodPrice,
              accent: AppInk.finance,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: NumberField(
                        label: l10n.prodPrice,
                        controller: _price,
                        suffix: app.profile.currencySymbol,
                      ),
                    ),
                    const HGap(10),
                    Expanded(
                      child: NumberField(
                        label: l10n.prodCost,
                        controller: _cost,
                        suffix: app.profile.currencySymbol,
                      ),
                    ),
                  ],
                ),
                const VGap(12),
                AppTextField(label: l10n.prodUnit, controller: _unit, hint: l10n.unitPiece),
                const VGap(14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _BoxToggle(
                        label: _perBoxOn ? l10n.prodBoxOn : l10n.prodBoxOff,
                        active: _perBoxOn,
                        onTap: () => setState(() => _perBoxOn = !_perBoxOn),
                      ),
                    ),
                  ],
                ),
                if (_perBoxOn) ...<Widget>[
                  const VGap(12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: NumberField(
                          label: l10n.prodPerBox,
                          controller: _perBox,
                          allowDecimal: false,
                        ),
                      ),
                      const HGap(10),
                      Expanded(
                        child: NumberField(
                          label: l10n.prodBoxPrice,
                          controller: _boxPrice,
                          suffix: app.profile.currencySymbol,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            _group(
              title: l10n.prodCategory,
              accent: AppInk.dashboard,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _CategoryChip(
                      label: l10n.commonNone,
                      selected: _categoryTouched && _categoryId == null,
                      onTap: () => setState(() {
                        _categoryTouched = true;
                        _categoryId = null;
                      }),
                    ),
                    for (final Category category in _categories)
                      _CategoryChip(
                        label: category.name,
                        selected: _categoryId == category.id,
                        onTap: () => setState(() {
                          _categoryTouched = true;
                          _categoryId = category.id;
                        }),
                      ),
                  ],
                ),
                const VGap(16),
                AppTextField(
                  label: l10n.prodDescription,
                  controller: _description,
                  maxLines: 3,
                  hint: l10n.prodDescHint,
                ),
              ],
            ),
            _group(
              title: l10n.prodImages,
              accent: AppInk.marketplace,
              note: '${l10n.prodImagesMax}（${_images.length}/5）',
              children: <Widget>[
                const VGap(4),
                ImageStrip(
                  urls: _images,
                  busy: _uploading,
                  onAdd: _addImage,
                  onRemove: (int index) => setState(() => _images.removeAt(index)),
                ),
              ],
            ),
            if (!_isNew) _historyGroup(l10n),
            const VGap(20),
            PrimaryButton(
              label: _saving ? l10n.commonSaving : l10n.actSave,
              icon: Icons.check_rounded,
              color: AppInk.products,
              loading: _saving,
              onPressed: app.canWrite && !_uploading ? _save : null,
            ),
            const VGap(12),
          ],
        ),
      ),
    );
  }

  /// 成交行：改价、补货前先看这支货实际怎么走的，省掉跳订单页再搜一遍。
  Widget _historyGroup(L10n l10n) {
    final List<ProductHistoryEntry> rows = _history.value ?? const <ProductHistoryEntry>[];
    final TextStyle? small = Theme.of(context).textTheme.bodySmall;
    return _group(
      title: l10n.prodHistory,
      accent: AppInk.orders,
      note: (!_history.loading && _history.errorText == null && rows.isNotEmpty)
          ? l10n.prodHistoryNote(rows.length)
          : null,
      children: <Widget>[
        const VGap(4),
        if (_history.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: AppSpinner()),
          )
        else if (_history.errorText != null)
          Text(_history.errorText!, style: small)
        else if (rows.isEmpty)
          Text(l10n.prodHistoryEmpty, style: small)
        else
          for (final ProductHistoryEntry row in rows) _historyRow(l10n, row),
      ],
    );
  }

  Widget _historyRow(L10n l10n, ProductHistoryEntry row) {
    final bool inbound = row.type == OrderType.inbound;
    final Color tint = inbound ? AppInk.finance : AppInk.products;
    return TileRow(
      icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
      accent: AppInk.orders,
      title: '${row.orderNumber} · '
          '${row.customerName.isEmpty ? l10n.commonNone : row.customerName}',
      // 单据类型写在副标题里：历史行没有订单 id，读不出方向就会把出库当入库。
      subtitle:
          '${inbound ? l10n.ordInbound : l10n.ordOutbound} · ${l10n.elapsed(row.orderDate)}',
      trailing: Text(
        Fmt.count(row.quantity),
        style: TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy, color: tint),
      ),
    );
  }

  Widget _group({
    required String title,
    required Color accent,
    required List<Widget> children,
    String? note,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(title: title, accent: accent, subtitle: note),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

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
          color: selected ? AppInk.dashboard : AppInk.surfaceDim,
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

class _BoxToggle extends StatelessWidget {
  const _BoxToggle({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppInk.finance : AppInk.textTertiary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppInk.tint(color, alpha: active ? 0.16 : 0.06),
          borderRadius: Radii.control_,
          border: Border.all(color: active ? color : AppInk.hairline),
        ),
        child: Row(
          children: <Widget>[
            Icon(active ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 18, color: color),
            const HGap(8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppType.foot,
                  fontWeight: AppType.semi,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
