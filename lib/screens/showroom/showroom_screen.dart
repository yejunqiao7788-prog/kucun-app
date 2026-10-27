import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../shell/module_registry.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';

/// 展厅：一条公开链接把选好的商品摆给客户看。
///
/// 服务端语义决定了两件事：
/// 1. `PATCH /showrooms/:id` 走的是**整行 update**（`saveShowroom` 每次都拼完整 payload），
///    所以编辑页永远提交全量字段，漏传等于清空；
/// 2. 展出商品是 `POST /showrooms/:id/items` 的**整表替换**，最多 500 行、`product_id` 不许重复。
class ShowroomScreen extends StatefulWidget {
  const ShowroomScreen({super.key});

  @override
  State<ShowroomScreen> createState() => _ShowroomScreenState();
}

class _ShowroomScreenState extends State<ShowroomScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<List<Showroom>> _rows =
      ValueLoader<List<Showroom>>(() => _app.repos.showrooms.list());

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final bool? saved = await pushSheet<bool>(
      context,
      child: ShowroomEditor(showroom: null),
    );
    if (saved == true) await _rows.refresh();
  }

  Future<void> _edit(Showroom showroom) async {
    final bool? saved = await pushSheet<bool>(
      context,
      child: ShowroomEditor(showroom: showroom),
    );
    if (saved == true) await _rows.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final l10n = app.l10n;
    final List<Showroom> rows = _rows.value ?? const <Showroom>[];

    return ModuleScaffold(
      title: l10n.moduleShowroom,
      accent: AppInk.showroom,
      onRefresh: _rows.refresh,
      actions: <Widget>[
        RoundIconButton(
          icon: Icons.add_rounded,
          color: AppInk.showroom,
          tooltip: l10n.shrNew,
          onPressed: app.canWrite ? _create : null,
        ),
      ],
      children: <Widget>[
        if (_rows.stale || app.renewalPending)
          NoticeBanner(
            text: _rows.stale ? l10n.commonStaleBanner : l10n.commonExpiredBanner,
            color: _rows.stale ? AppInk.info : AppInk.danger,
            icon: _rows.stale ? Icons.history_rounded : Icons.lock_outline_rounded,
          ),
        if (_rows.loading && rows.isEmpty)
          const SkeletonList(count: 3, itemHeight: 132)
        else if (_rows.errorText != null && rows.isEmpty)
          AppErrorView(message: _rows.errorText!, onRetry: _rows.load)
        else if (rows.isEmpty)
          AppEmpty(
            title: l10n.commonEmptyTitle,
            hint: l10n.shrEmptyHint,
            icon: Icons.storefront_rounded,
            accent: AppInk.showroom,
            action: app.canWrite
                ? PrimaryButton(
                    label: l10n.shrNew,
                    icon: Icons.add_rounded,
                    color: AppInk.showroom,
                    expanded: false,
                    onPressed: _create,
                  )
                : null,
          )
        else
          for (final Showroom showroom in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ShowroomCard(
                showroom: showroom,
                currency: app.profile.currencySymbol,
                onTap: () => _edit(showroom),
              ),
            ),
      ],
    );
  }
}

/// 服务端把展示范围存在 `mode`，类目名只在列表行附带。
String _modeLabel(Showroom showroom, L10n l10n) {
  switch (showroom.mode) {
    case 'all':
      return l10n.shrModeAll;
    case 'category':
      final String? name = showroom.categoryName;
      return name == null ? l10n.shrModeCategory : '${l10n.shrModeCategory} · $name';
    default:
      return '${l10n.shrModeSelected} · ${Fmt.count(showroom.itemCount)}';
  }
}

class _ShowroomCard extends StatelessWidget {  const _ShowroomCard({
    required this.showroom,
    required this.currency,
    required this.onTap,
  });

  final Showroom showroom;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppState.of(context).l10n;
    final bool expired = showroom.expiresAt != null &&
        showroom.expiresAt!.isBefore(DateTime.now());
    final Color statusColor = showroom.status == 'disabled'
        ? AppInk.textTertiary
        : (showroom.status == 'expired' || expired)
            ? AppInk.danger
            : AppInk.success;

    return AppCard(
      accent: AppInk.showroom,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      showroom.name.isEmpty ? l10n.commonUnnamed : showroom.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (showroom.brandName != null) ...<Widget>[
                      const VGap(2),
                      Text(
                        showroom.brandName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const HGap(8),
              StatusPill(
                label: showroom.status == 'disabled'
                    ? l10n.shrStatusDisabled
                    : (showroom.status == 'expired' || expired)
                        ? l10n.shrExpired
                        : l10n.shrEnabled,
                color: statusColor,
                dense: true,
              ),
            ],
          ),
          const VGap(12),
          Row(
            children: <Widget>[
              _Metric(label: l10n.shrItems, value: Fmt.count(showroom.itemCount)),
              _Metric(label: l10n.shrVisits, value: Fmt.count(showroom.visitCount)),
              _Metric(label: l10n.shrOrders, value: Fmt.count(showroom.orderCount)),
            ],
          ),
          const VGap(12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _modeLabel(showroom, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppType.foot,
                    color: AppInk.textTertiary,
                  ),
                ),
              ),
              const HGap(8),
              if (showroom.shareToken != null) ...<Widget>[
                RoundIconButton(
                  icon: Icons.copy_rounded,
                  size: 36,
                  color: AppInk.showroom,
                  tooltip: l10n.actCopy,
                  onPressed: () => _copyLink(context, showroom),
                ),
                const HGap(6),
                RoundIconButton(
                  icon: Icons.open_in_new_rounded,
                  size: 36,
                  color: AppInk.showroom,
                  tooltip: l10n.shrOpenLink,
                  onPressed: () => _openLink(context, showroom),
                ),
              ],
            ],
          ),
          if (showroom.expiresAt != null) ...<Widget>[
            const VGap(8),
            Text(
              '${l10n.shrExpires} ${Fmt.date(showroom.expiresAt)}',
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  static String linkOf(Showroom showroom) {
    final String? absolute = showroom.publicUrl;
    if (absolute != null && absolute.startsWith('http')) return absolute;
    final String token = showroom.shareToken ?? '';
    return token.isEmpty ? '' : '${Env.siteBase}/s/$token';
  }

  Future<void> _copyLink(BuildContext context, Showroom showroom) async {
    final l10n = AppState.of(context).l10n;
    final String link = linkOf(showroom);
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    showToast(context, l10n.commonCopied);
  }

  Future<void> _openLink(BuildContext context, Showroom showroom) async {
    final String link = linkOf(showroom);
    if (link.isEmpty) return;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: AppType.head,
              fontWeight: AppType.heavy,
              color: AppInk.showroom,
            ),
          ),
          const VGap(2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 展厅编辑：基本信息 + 公开页开关，保存后进入选品。
class ShowroomEditor extends StatefulWidget {
  const ShowroomEditor({super.key, this.showroom});

  final Showroom? showroom;

  @override
  State<ShowroomEditor> createState() => _ShowroomEditorState();
}

class _ShowroomEditorState extends State<ShowroomEditor> {
  late final AppState _app = context.read<AppState>();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late final TextEditingController _title =
      TextEditingController(text: widget.showroom?.name ?? '');
  late final TextEditingController _brand =
      TextEditingController(text: widget.showroom?.brandName ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.showroom?.description ?? '');

  late String _mode = widget.showroom?.mode ?? 'selected';
  late String _status = widget.showroom?.status ?? 'active';
  late bool _requirePhone = widget.showroom?.requirePhone ?? true;
  late bool _showPrice = widget.showroom?.showPrice ?? true;
  late bool _showStock = widget.showroom?.showStock ?? false;
  late bool _showName = widget.showroom?.showName ?? true;
  late bool _showCategory = widget.showroom?.showCategory ?? true;
  late bool _allowOrder = widget.showroom?.allowOrder ?? true;
  late String? _categoryId = widget.showroom?.categoryId;
  late String? _customerId = widget.showroom?.customerId;
  late DateTime? _expiresAt = widget.showroom?.expiresAt;

  List<Category> _categories = const <Category>[];
  List<Customer> _customers = const <Customer>[];
  bool _saving = false;

  bool get _isNew => widget.showroom == null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOptions());
  }

  Future<void> _loadOptions() async {
    try {
      final List<Category> categories = await _app.repos.products.categories();
      final List<Customer> customers = await _app.repos.settings.customers();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _customers = customers;
      });
    } on Object {
      // 关联字段只是可选项，拉不到不影响编辑基础信息。
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _brand.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final DateTime first = DateTime.now().subtract(const Duration(days: 1));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: first,
      lastDate: DateTime(first.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_app.canWrite) {
      showToast(context, _app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    final Map<String, Object?> payload = <String, Object?>{
      'title': _title.text.trim(),
      'brand_name': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'mode': _mode,
      'category_id': _mode == 'category' ? _categoryId : null,
      'customer_id': _customerId,
      'status': _status,
      // 整行 update：这几枚布尔必须全量带上，缺省会被服务端当成 true。
      'require_phone': _requirePhone,
      'show_price': _showPrice,
      'show_stock': _showStock,
      'show_name': _showName,
      'show_category': _showCategory,
      'allow_order': _allowOrder,
      'expires_at': _expiresAt == null
          ? null
          : '${_expiresAt!.toIso8601String().split('T').first}T23:59:59.000Z',
    };

    setState(() => _saving = true);
    try {
      await _app.guardWrite<void>(() async {
        if (_isNew) {
          await _app.repos.showrooms.create(payload);
        } else {
          await _app.repos.showrooms.update(widget.showroom!.id, payload);
        }
      });
      if (!mounted) return;
      showToast(context, _app.l10n.commonSaved);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _delete() async {
    final Showroom? origin = widget.showroom;
    if (origin == null) return;
    final bool sure = await confirmAction(
      context,
      title: origin.name,
      message: _app.l10n.shrDeleteConfirm,
      confirmLabel: _app.l10n.actDelete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await _app.guardWrite<void>(() => _app.repos.showrooms.remove(origin.id));
      if (!mounted) return;
      showToast(context, _app.l10n.commonDeleted);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  Future<void> _editItems() async {
    final Showroom? origin = widget.showroom;
    if (origin == null) return;
    await pushSheet<void>(context, child: ShowroomItemsScreen(showroom: origin));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.shrNew : l10n.actEdit),
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
            AppCard(
              accent: AppInk.showroom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(title: l10n.shrBasics, accent: AppInk.showroom),
                  AppTextField(
                    label: l10n.shrTitle,
                    controller: _title,
                    validator: (String? v) =>
                        (v ?? '').trim().isEmpty ? l10n.shrTitleRequired : null,
                  ),
                  const VGap(12),
                  AppTextField(label: l10n.shrBrand, controller: _brand),
                  const VGap(12),
                  AppTextField(
                    label: l10n.prodDescription,
                    controller: _description,
                    maxLines: 3,
                    hint: l10n.shrDescHint,
                  ),
                ],
              ),
            ),
            const VGap(14),
            AppCard(
              accent: AppInk.products,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    title: l10n.shrMode,
                    accent: AppInk.products,
                    subtitle: l10n.shrModeHint,
                  ),
                  PillTabs<String>(
                    values: const <String>['selected', 'category', 'all'],
                    selected: _mode,
                    accent: AppInk.products,
                    labelOf: (String value) => switch (value) {
                      'selected' => l10n.shrModeSelected,
                      'category' => l10n.shrModeCategory,
                      _ => l10n.shrModeAll,
                    },
                    onChanged: (String value) => setState(() => _mode = value),
                  ),
                  if (_mode == 'category') ...<Widget>[
                    const VGap(14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final Category category in _categories)
                          _ChoiceChip(
                            label: category.name,
                            selected: _categoryId == category.id,
                            accent: AppInk.products,
                            onTap: () => setState(() => _categoryId = category.id),
                          ),
                        if (_categories.isEmpty)
                          Text(l10n.setCategories,
                              style: const TextStyle(color: AppInk.textTertiary)),
                      ],
                    ),
                  ],
                  if (_mode != 'selected')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l10n.shrModeAutoNote,
                        style: const TextStyle(
                            fontSize: AppType.foot, color: AppInk.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
            const VGap(14),
            AppCard(
              accent: AppInk.showroom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(title: l10n.shrPublicPage, accent: AppInk.showroom),
                  PillTabs<String>(
                    values: const <String>['active', 'disabled', 'expired'],
                    selected: _status,
                    accent: AppInk.showroom,
                    labelOf: (String value) => switch (value) {
                      'disabled' => l10n.shrStatusDisabled,
                      'expired' => l10n.shrStatusExpired,
                      _ => l10n.shrStatusActive,
                    },
                    onChanged: (String value) => setState(() => _status = value),
                  ),
                  const VGap(14),
                  _SwitchRow(
                    label: l10n.shrRequirePhone,
                    value: _requirePhone,
                    onChanged: (bool v) => setState(() => _requirePhone = v),
                  ),
                  _SwitchRow(
                    label: l10n.shrShowPrice,
                    value: _showPrice,
                    onChanged: (bool v) => setState(() => _showPrice = v),
                  ),
                  _SwitchRow(
                    label: l10n.shrShowStock,
                    value: _showStock,
                    onChanged: (bool v) => setState(() => _showStock = v),
                  ),
                  _SwitchRow(
                    label: l10n.shrShowName,
                    value: _showName,
                    onChanged: (bool v) => setState(() => _showName = v),
                  ),
                  _SwitchRow(
                    label: l10n.shrShowCategory,
                    value: _showCategory,
                    onChanged: (bool v) => setState(() => _showCategory = v),
                  ),
                  _SwitchRow(
                    label: l10n.shrAllowOrder,
                    value: _allowOrder,
                    onChanged: (bool v) => setState(() => _allowOrder = v),
                  ),
                ],
              ),
            ),
            const VGap(14),
            AppCard(
              accent: AppInk.finance,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(title: l10n.shrLinkCustomer, accent: AppInk.finance),
                  if (_customers.isEmpty)
                    Text(l10n.setCustomersInSettings,
                        style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _ChoiceChip(
                          label: l10n.ordNoCustomer,
                          selected: _customerId == null,
                          accent: AppInk.finance,
                          onTap: () => setState(() => _customerId = null),
                        ),
                        for (final Customer customer in _customers.take(12))
                          _ChoiceChip(
                            label: customer.name,
                            selected: _customerId == customer.id,
                            accent: AppInk.finance,
                            onTap: () => setState(() => _customerId = customer.id),
                          ),
                      ],
                    ),
                  const VGap(14),
                  TileRow(
                    icon: Icons.event_rounded,
                    title: l10n.shrExpires,
                    accent: AppInk.finance,
                    trailing: Text(
                      _expiresAt == null ? l10n.commonNone : Fmt.date(_expiresAt),
                      style: const TextStyle(
                          fontSize: AppType.foot, fontWeight: AppType.semi),
                    ),
                    onTap: _pickExpiry,
                  ),
                  if (_expiresAt != null)
                    TextAction(
                      label: l10n.shrNeverExpires,
                      color: AppInk.textTertiary,
                      onPressed: () => setState(() => _expiresAt = null),
                    ),
                ],
              ),
            ),
            const VGap(20),
            PrimaryButton(
              label: _saving ? l10n.commonSaving : l10n.actSave,
              icon: Icons.check_rounded,
              color: AppInk.showroom,
              loading: _saving,
              onPressed: app.canWrite ? _save : null,
            ),
            if (!_isNew) ...<Widget>[
              const VGap(12),
              GhostButton(
                label: l10n.shrItems,
                icon: Icons.dashboard_customize_outlined,
                color: AppInk.products,
                onPressed: _mode == 'selected' && app.canWrite ? _editItems : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 展出商品：读详情 → 本地编辑 → 整表替换写回。
class ShowroomItemsScreen extends StatefulWidget {
  const ShowroomItemsScreen({super.key, required this.showroom});

  final Showroom showroom;

  @override
  State<ShowroomItemsScreen> createState() => _ShowroomItemsScreenState();
}

class _ShowroomItemsScreenState extends State<ShowroomItemsScreen> {
  late final AppState _app = context.read<AppState>();
  late final ValueLoader<Showroom> _detail =
      ValueLoader<Showroom>(() => _app.repos.showrooms.detail(widget.showroom.id));

  /// 编辑态：`product_id` 为键，保住顺序、展厅价与显隐。
  final List<_ShelfLine> _lines = <_ShelfLine>[];
  bool _synced = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _detail.load();
    _syncFromDetail();
  }

  void _syncFromDetail() {
    final Showroom? data = _detail.value;
    if (data == null || _synced) return;
    setState(() {
      _synced = true;
      _lines
        ..clear()
        ..addAll(
          data.items.map((JsonMap row) {
            final JsonMap product = JsonMap.from(row.raw('products'));
            return _ShelfLine(
              productId: row.asStringOr('product_id', product.asStringOr('id', '')),
              name: product.asStringOr('name', ''),
              sku: product.asStringOr('sku', ''),
              price: product.asDoubleOr('price', 0),
              unit: product.asStringOr('unit', ''),
              imageUrl: product.asString('image_url'),
              customPrice: row.asDouble('custom_price'),
              visible: row.asBool('is_visible', fallback: true),
            );
          }).where((_ShelfLine line) => line.productId.isNotEmpty).toList(),
        );
    });
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _addProducts() async {
    final List<Product> picked = await pushSheet<List<Product>>(
      context,
      child: _ProductPickerScreen(
        excluded: _lines.map((_ShelfLine line) => line.productId).toSet(),
      ),
    ) ??
        const <Product>[];
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final Product product in picked) {
        if (_lines.any((_ShelfLine line) => line.productId == product.id)) continue;
        _lines.add(
          _ShelfLine(
            productId: product.id,
            name: product.name,
            sku: product.sku,
            price: product.price,
            unit: product.unit,
            imageUrl: product.imageUrl,
            customPrice: null,
            visible: true,
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    if (!_app.canWrite) {
      showToast(context, _app.l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    if (_lines.length > 500) {
      showToast(context, _app.l10n.shrItemsMax, danger: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _app.guardWrite<void>(() => _app.repos.showrooms.replaceItems(
            widget.showroom.id,
            <Map<String, Object?>>[
              for (int index = 0; index < _lines.length; index++)
                <String, Object?>{
                  'product_id': _lines[index].productId,
                  'sort_order': index,
                  'custom_price': _lines[index].customPrice,
                  'is_visible': _lines[index].visible,
                }
            ],
          ));
      if (!mounted) return;
      showToast(context, _app.l10n.commonSaved);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _app.describeError(error), danger: true);
    }
  }

  void _move(int index, int delta) {
    final int target = index + delta;
    if (target < 0 || target >= _lines.length) return;
    setState(() {
      final _ShelfLine line = _lines.removeAt(index);
      _lines.insert(target, line);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shrItems)),
      body: AnimatedBuilder(
        animation: _detail,
        builder: (BuildContext context, Widget? _) {
          if (_detail.loading && !_synced) {
            return const SafeArea(child: SkeletonList(count: 5, itemHeight: 76));
          }
          if (_detail.errorText != null && !_synced) {
            return SafeArea(
              child: AppErrorView(message: _detail.errorText!, onRetry: _load),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 100),
            children: <Widget>[
              Text(
                l10n.shrItemsHint,
                style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
              ),
              const VGap(12),
              if (_lines.isEmpty)
                AppEmpty(
                  title: l10n.commonEmptyTitle,
                  hint: l10n.shrPickItems,
                  icon: Icons.dashboard_outlined,
                  accent: AppInk.products,
                )
              else
                for (int index = 0; index < _lines.length; index++)
                  _ShelfRow(
                    line: _lines[index],
                    currency: app.profile.currencySymbol,
                    canUp: index > 0,
                    canDown: index < _lines.length - 1,
                    onUp: () => _move(index, -1),
                    onDown: () => _move(index, 1),
                    onRemove: () => setState(() => _lines.removeAt(index)),
                    onToggleVisible: (bool value) =>
                        setState(() => _lines[index].visible = value),
                    onCustomPrice: (double? value) =>
                        setState(() => _lines[index].customPrice = value),
                  ),
              const VGap(16),
              GhostButton(
                label: l10n.shrAddProducts,
                icon: Icons.add_rounded,
                color: AppInk.products,
                onPressed: _lines.length >= 500 ? null : _addProducts,
              ),
              const VGap(20),
              PrimaryButton(
                label: _saving ? l10n.commonSaving : l10n.actSave,
                icon: Icons.check_rounded,
                color: AppInk.showroom,
                loading: _saving,
                onPressed: app.canWrite ? _save : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShelfLine {
  _ShelfLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    required this.unit,
    required this.imageUrl,
    required this.customPrice,
    required this.visible,
  });

  final String productId;
  final String name;
  final String sku;
  final double price;
  final String unit;
  final String? imageUrl;
  double? customPrice;
  bool visible;
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.line,
    required this.currency,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
    required this.onToggleVisible,
    required this.onCustomPrice,
  });

  final _ShelfLine line;
  final String currency;
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggleVisible;
  final ValueChanged<double?> onCustomPrice;

  Future<void> _editPrice(BuildContext context) async {
    final l10n = AppState.of(context).l10n;
    final TextEditingController controller =
        TextEditingController(text: line.customPrice?.toString() ?? '');
    final double? result = await showDrawer<double>(
      context,
      title: l10n.shrCustomPrice,
      accent: AppInk.showroom,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NumberField(
            label: l10n.shrCustomPrice,
            controller: controller,
            suffix: currency,
            autofocus: true,
          ),
          const VGap(8),
          Text(
            '${l10n.prodPrice} ${Fmt.money(line.price, symbol: currency)}',
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
          ),
          const VGap(16),
          PrimaryButton(
            label: l10n.actSave,
            color: AppInk.showroom,
            onPressed: () => Navigator.of(sheetContext).pop(
              double.tryParse(controller.text.trim()),
            ),
          ),
          const VGap(8),
          TextAction(
            label: l10n.shrUseDefaultPrice,
            color: AppInk.textTertiary,
            onPressed: () => Navigator.of(sheetContext).pop(-1),
          ),
        ],
      ),
    );
    if (result == null) return;
    onCustomPrice(result < 0 ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppState.of(context).l10n;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      accent: line.visible ? AppInk.showroom : null,
      child: Row(
        children: <Widget>[
          RoundIconButton(
            icon: Icons.visibility_off_rounded,
            size: 36,
            color: line.visible ? AppInk.textTertiary : AppInk.warning,
            tooltip: line.visible ? l10n.shrHide : l10n.shrShow,
            onPressed: () => onToggleVisible(!line.visible),
          ),
          const HGap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.name.isEmpty ? line.sku : line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: AppType.semi,
                    decoration: line.visible ? null : TextDecoration.lineThrough,
                    color: line.visible ? null : AppInk.textTertiary,
                  ),
                ),
                const VGap(4),
                Row(
                  children: <Widget>[
                    Text(
                      line.customPrice == null
                          ? Fmt.money(line.price, symbol: currency)
                          : '${Fmt.money(line.customPrice!, symbol: currency)} · ${l10n.shrCustomPrice}',
                      style: TextStyle(
                        fontSize: AppType.foot,
                        color: line.customPrice == null
                            ? AppInk.textTertiary
                            : AppInk.showroom,
                        fontWeight: AppType.semi,
                      ),
                    ),
                    const HGap(6),
                    TextAction(
                      label: l10n.actEdit,
                      color: AppInk.textTertiary,
                      onPressed: () => _editPrice(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const HGap(6),
          RoundIconButton(
            icon: Icons.arrow_upward_rounded,
            size: 32,
            color: AppInk.textTertiary,
            onPressed: canUp ? onUp : null,
          ),
          RoundIconButton(
            icon: Icons.arrow_downward_rounded,
            size: 32,
            color: AppInk.textTertiary,
            onPressed: canDown ? onDown : null,
          ),
          RoundIconButton(
            icon: Icons.close_rounded,
            size: 32,
            color: AppInk.danger,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 商品多选：搜索 + 勾选，确认才返回，符合「一次只做一件事」。
class _ProductPickerScreen extends StatefulWidget {
  const _ProductPickerScreen({required this.excluded});

  final Set<String> excluded;

  @override
  State<_ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends State<_ProductPickerScreen> {
  late final AppState _app = context.read<AppState>();
  final TextEditingController _search = TextEditingController();
  final List<Product> _results = <Product>[];
  final Set<String> _picked = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _searchNow() async {
    final String keyword = _search.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Product> rows = await _app.repos.products.search(keyword, limit: 30);
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(rows.where((Product p) => !widget.excluded.contains(p.id)));
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _app.describeError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppState.of(context).l10n;
    final List<Product> picked =
        _results.where((Product p) => _picked.contains(p.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.shrPickItems),
        actions: <Widget>[
          if (picked.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).pop(picked),
              child: Text('${l10n.actDone} (${picked.length})'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 8),
            child: SearchField(
              controller: _search,
              hintText: l10n.actSearch,
              autofocus: true,
              onChanged: (String _) => setState(() {}),
              onSubmitted: (String _) => _searchNow(),
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonList(count: 6, itemHeight: 64)
                : _error != null
                    ? AppErrorView(message: _error!, onRetry: _searchNow)
                    : _results.isEmpty
                        ? AppEmpty(
                            title: l10n.commonEmptyTitle,
                            hint: l10n.ordPickProduct,
                            icon: Icons.search_rounded,
                            accent: AppInk.products,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 24),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const VGap(8),
                            itemBuilder: (BuildContext context, int index) {
                              final Product product = _results[index];
                              final bool on = _picked.contains(product.id);
                              return AppCard(
                                padding: const EdgeInsets.all(12),
                                accent: on ? AppInk.products : null,
                                onTap: () => setState(() =>
                                    on ? _picked.remove(product.id) : _picked.add(product.id)),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            product.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                          const VGap(2),
                                          Text(
                                            '${product.sku} · ${Fmt.money(product.price, symbol: _app.profile.currencySymbol)}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      on
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: on ? AppInk.products : AppInk.textTertiary,
                                    ),
                                  ],
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: Radii.control_,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppInk.showroom,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : AppInk.surfaceDim,
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
