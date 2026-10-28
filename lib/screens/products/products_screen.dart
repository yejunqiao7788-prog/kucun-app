import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/access.dart';
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
import '../../state/app_state.dart';
import '../../state/list_controller.dart';
import '../inventory/inventory_panel.dart';
import 'product_edit_screen.dart';
import 'product_import_screen.dart';

/// 「商品」页 = 商品清单 + 库存视图两段。
///
/// 库存不单占一位底部导航：它和商品是同一批数据的两个看法，
/// 用顶部分段控件切换比两个入口更符合苹果的「一屏一件事」。
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.segment});

  final ValueNotifier<int>? segment;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late int _segment = widget.segment?.value ?? 0;

  @override
  void initState() {
    super.initState();
    widget.segment?.addListener(_onExternalSegment);
  }

  void _onExternalSegment() {
    final int? value = widget.segment?.value;
    if (value == null || value == _segment) return;
    setState(() => _segment = value);
  }

  @override
  void dispose() {
    widget.segment?.removeListener(_onExternalSegment);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final bool canSeeStock = app.canOpenModule(ModuleKey.inventory);

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
                    l10n.navProducts,
                    style: const TextStyle(
                      fontSize: AppType.huge,
                      fontWeight: AppType.heavy,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: Icons.upload_rounded,
                  color: AppInk.products,
                  tooltip: l10n.prodImport,
                  onPressed: app.canWrite
                      ? () async {
                          final bool? done = await pushSheet<bool>(
                            context,
                            child: ProductImportScreen(canImport: app.canWrite),
                          );
                          if (done == true && mounted) _notifyProductsChanged();
                        }
                      : null,
                ),
                const HGap(8),
                RoundIconButton(
                  icon: Icons.add_rounded,
                  color: AppInk.products,
                  tooltip: l10n.prodNew,
                  onPressed: app.canWrite
                      ? () async {
                          if (await openProductEditor(context)) {
                            if (mounted) _notifyProductsChanged();
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (canSeeStock)
            PillTabs<int>(
              values: const <int>[0, 1],
              selected: _segment,
              accent: _segment == 0 ? AppInk.products : AppInk.inventory,
              labelOf: (int value) => value == 0 ? l10n.navProducts : l10n.navInventory,
              onChanged: (int value) => setState(() => _segment = value),
            )
          else
            const VGap(4),
          Expanded(
            child: _segment == 0
                ? ProductPanel(key: ValueKey<int>(_generation))
                : InventoryPanel(key: ValueKey<int>(_generation)),
          ),
        ],
      ),
    );
  }

  static int _generation = 0;

  void _notifyProductsChanged() => setState(() => _generation += 1);
}

/// 商品清单：搜索 + 筛选抽屉 + 长按多选批量改价/批量删除。
class ProductPanel extends StatefulWidget {
  const ProductPanel({super.key});

  @override
  State<ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends State<ProductPanel> {
  late final Repos _repos = context.read<AppState>().repos;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  late final ListController<Product> _list = ListController<Product>(
    fetch: (int page) async {
      final ApiResponse<Paged<Product>> res = await _repos.products.list(
        page: page,
        search: _filters.search,
        categoryId: _filters.categoryId,
        lowStockOnly: _filters.lowStockOnly,
        hideZeroStock: _filters.hideZeroStock,
        orderBy: _filters.orderBy,
        ascending: _filters.ascending,
      );
      return FetchResult<Product>(
        rows: res.data.rows,
        hasMore: res.data.hasMore,
        stale: res.stale,
        summary: res.data.summary,
      );
    },
  );

  _ProductFilters _filters = const _ProductFilters();
  final Set<String> _selected = <String>{};

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

  void _apply(_ProductFilters next) {
    setState(() => _filters = next);
    _selected.clear();
    _list.load();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _apply(_filters.copyWith(search: value.trim().isEmpty ? null : value.trim()));
    });
  }

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _toggleSelect(Product row, {bool force = false}) async {
    if (!_selecting && !force) {
      await openProductEditor(context, product: row);
      if (!mounted) return;
      await _list.refresh();
      return;
    }
    setState(() {
      if (_selected.contains(row.id)) {
        _selected.remove(row.id);
      } else {
        _selected.add(row.id);
      }
    });
  }

  Future<void> _batchDelete() async {
    final AppState app = AppState.of(context);
    final List<String> ids = _selected.toList();
    if (ids.isEmpty) return;
    final bool sure = await confirmAction(
      context,
      title: app.l10n.prodBatchDelete,
      message: app.l10n.prodSelected(ids.length),
      confirmLabel: app.l10n.actDelete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await app.guardWrite<void>(() => _repos.products.batchDelete(ids));
      if (!mounted) return;
      showToast(context, app.l10n.commonDeleted);
      setState(_selected.clear);
      await _list.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }

  Future<void> _batchPrice() async {
    final AppState app = AppState.of(context);
    final _PriceEdit? edit = await showDrawer<_PriceEdit>(
      context,
      accent: AppInk.products,
      title: app.l10n.prodBatchPrice,
      builder: (BuildContext sheetContext) => const _PriceDrawer(),
    );
    if (edit == null || !mounted) return;
    final List<String> ids = _selected.toList();
    try {
      await app.guardWrite<void>(
        () => _repos.products.batchPrice(ids: ids, mode: edit.mode, value: edit.value),
      );
      if (!mounted) return;
      showToast(context, app.l10n.commonSaved);
      setState(_selected.clear);
      await _list.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    }
  }

  Future<void> _openFilters() async {
    final AppState app = AppState.of(context);
    List<Category> categories;
    try {
      categories = await _repos.products.categories();
    } on Object {
      categories = const <Category>[];
    }
    if (!mounted) return;
    final _ProductFilters? next = await showDrawer<_ProductFilters>(
      context,
      accent: AppInk.products,
      title: app.l10n.actFilter,
      builder: (BuildContext sheetContext) => _FilterDrawer(
        initial: _filters,
        categories: categories,
        l10n: app.l10n,
      ),
    );
    if (next == null || !mounted) return;
    _apply(next);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final JsonMap summary = _list.summary is JsonMap ? _list.summary as JsonMap : JsonMap.empty;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SearchField(
                  controller: _search,
                  hintText: l10n.prodSearchHint,
                  onChanged: _onSearchChanged,
                ),
              ),
              const HGap(8),
              RoundIconButton(
                icon: Icons.tune_rounded,
                color: _filters.dirty ? AppInk.products : null,
                tooltip: l10n.actFilter,
                onPressed: _openFilters,
              ),
            ],
          ),
        ),
        if (_selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.prodSelected(_selected.length),
                    style: TextStyle(
                      fontSize: AppType.foot,
                      fontWeight: AppType.semi,
                      color: AppInk.products,
                    ),
                  ),
                ),
                TextAction(label: l10n.prodBatchPrice, color: AppInk.products, onPressed: _batchPrice),
                TextAction(label: l10n.actDelete, color: AppInk.danger, onPressed: _batchDelete),
                TextAction(
                  label: l10n.actClose,
                  onPressed: () => setState(_selected.clear),
                ),
              ],
            ),
          )
        else if (summary.json.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 6),
            child: Text(
              '${l10n.commonTotal} ${Fmt.count(summary.asIntOr('product_count', 0))} · '
              '${Fmt.count(summary.asIntOr('total_quantity', 0))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: PagedView<Product>(
            controller: _list,
            accent: AppInk.products,
            emptyTitle: l10n.commonEmptyTitle,
            emptyHint: l10n.prodSearchHint,
            emptyIcon: Icons.inventory_2_outlined,
            emptyAction: app.canWrite
                ? PrimaryButton(
                    label: l10n.prodNew,
                    icon: Icons.add_rounded,
                    color: AppInk.products,
                    expanded: false,
                    onPressed: () async {
                      if (await openProductEditor(context)) await _list.refresh();
                    },
                  )
                : null,
            itemBuilder: (BuildContext context, Product row, int index) => _ProductRow(
              product: row,
              currency: app.profile.currencySymbol,
              selected: _selected.contains(row.id),
              selecting: _selecting,
              onTap: () => _toggleSelect(row),
              onLongPress: () => _toggleSelect(row, force: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.currency,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final Product product;
  final String currency;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static Color _tierColor(StockTier tier) {
    switch (tier) {
      case StockTier.out:
        return AppInk.danger;
      case StockTier.low:
        return AppInk.warning;
      case StockTier.overflow:
        return AppInk.info;
      case StockTier.normal:
        return AppInk.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final String tierLabel = switch (product.tier) {
      StockTier.out => l10n.invOutOf,
      StockTier.low => l10n.invLow,
      StockTier.overflow => l10n.invOverflow,
      StockTier.normal => l10n.invNormal,
    };

    return GestureDetector(
      onLongPress: onLongPress,
      child: RowCard(
        accent: AppInk.products,
        onTap: onTap,
        title: product.name,
        subtitle: product.sku.isEmpty
            ? (product.categoryName ?? '')
            : '${product.sku} · ${product.categoryName ?? l10n.commonNone}',
        leading: selecting
            ? Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppInk.products : AppInk.textTertiary,
                size: 24,
              )
            : Thumbnail(url: product.imageUrl),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              '${Fmt.count(product.quantity)}${product.unit}',
              style: TextStyle(
                fontSize: AppType.head,
                fontWeight: AppType.heavy,
                color: _tierColor(product.tier),
              ),
            ),
            const VGap(2),
            Text(
              Fmt.money(product.price, symbol: currency),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        badges: <Widget>[
          if (product.tier != StockTier.normal)
            StatusPill(label: tierLabel, color: _tierColor(product.tier), dense: true),
          if (product.sellsByBox)
            StatusPill(
              label: '${l10n.unitBox} × ${product.unitsPerBox}',
              color: AppInk.finance,
              dense: true,
            ),
          if (product.location != null && product.location!.isNotEmpty)
            StatusPill(label: product.location!, color: AppInk.inventory, dense: true),
        ],
      ),
    );
  }
}

class _ProductFilters {
  const _ProductFilters({
    this.search,
    this.categoryId,
    this.lowStockOnly = false,
    this.hideZeroStock = false,
    this.orderBy = 'updated_at',
    this.ascending = false,
  });

  final String? search;
  final String? categoryId;
  final bool lowStockOnly;
  final bool hideZeroStock;
  final String orderBy;
  final bool ascending;

  bool get dirty => lowStockOnly || hideZeroStock || categoryId != null;

  _ProductFilters copyWith({
    String? search,
    String? categoryId,
    bool? lowStockOnly,
    bool? hideZeroStock,
    String? orderBy,
    bool? ascending,
  }) =>
      _ProductFilters(
        search: search,
        categoryId: categoryId,
        lowStockOnly: lowStockOnly ?? this.lowStockOnly,
        hideZeroStock: hideZeroStock ?? this.hideZeroStock,
        orderBy: orderBy ?? this.orderBy,
        ascending: ascending ?? this.ascending,
      );
}

class _FilterDrawer extends StatefulWidget {
  const _FilterDrawer({
    required this.initial,
    required this.categories,
    required this.l10n,
  });

  final _ProductFilters initial;
  final List<Category> categories;
  final L10n l10n;

  @override
  State<_FilterDrawer> createState() => _FilterDrawerState();
}

class _FilterDrawerState extends State<_FilterDrawer> {
  late _ProductFilters _draft = widget.initial;

  /// 排序白名单在服务端（created_at/updated_at/name/sku/price），客户端不得自造列名。
  static const List<String> _sortKeys = <String>['updated_at', 'name', 'sku', 'price'];

  String _labelOf(String key) {
    switch (key) {
      case 'name':
        return widget.l10n.prodSortName;
      case 'sku':
        return widget.l10n.prodSortSku;
      case 'price':
        return widget.l10n.prodSortPrice;
      default:
        return widget.l10n.prodSortUpdated;
    }
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = widget.l10n;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (widget.categories.isNotEmpty) ...<Widget>[
          Text(l10n.prodCategory, style: Theme.of(context).textTheme.titleMedium),
          const VGap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Chip(
                label: l10n.commonAll,
                selected: _draft.categoryId == null,
                onTap: () => setState(() => _draft = _draft.copyWith(categoryId: null)),
              ),
              for (final Category category in widget.categories)
                _Chip(
                  label: category.name,
                  selected: _draft.categoryId == category.id,
                  onTap: () => setState(() => _draft = _draft.copyWith(categoryId: category.id)),
                ),
            ],
          ),
          const VGap(18),
        ],
        _SwitchRow(
          label: l10n.prodLowOnly,
          value: _draft.lowStockOnly,
          onChanged: (bool v) => setState(() => _draft = _draft.copyWith(lowStockOnly: v)),
        ),
        _SwitchRow(
          label: l10n.prodHideZero,
          value: _draft.hideZeroStock,
          onChanged: (bool v) => setState(() => _draft = _draft.copyWith(hideZeroStock: v)),
        ),
        const VGap(18),
        Text(l10n.actSort, style: Theme.of(context).textTheme.titleMedium),
        const VGap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String key in _sortKeys)
              _Chip(
                label: _labelOf(key),
                selected: _draft.orderBy == key,
                onTap: () => setState(() => _draft = _draft.copyWith(orderBy: key)),
              ),
          ],
        ),
        const VGap(12),
        _SwitchRow(
          label: l10n.prodSortAsc,
          value: _draft.ascending,
          onChanged: (bool v) => setState(() => _draft = _draft.copyWith(ascending: v)),
        ),
        const VGap(20),
        PrimaryButton(
          label: l10n.actApply,
          color: AppInk.products,
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
        const VGap(10),
      ],
    );
  }
}

class _PriceEdit {
  const _PriceEdit(this.mode, this.value);

  final String mode;
  final double value;
}

class _PriceDrawer extends StatefulWidget {
  const _PriceDrawer();

  @override
  State<_PriceDrawer> createState() => _PriceDrawerState();
}

class _PriceDrawerState extends State<_PriceDrawer> {
  final TextEditingController _value = TextEditingController();

  /// 服务端只认这四支模式，`set`/`markup_cost` 还拒绝负数。
  static const List<String> _modes = <String>['set', 'markup_cost', 'percent', 'amount'];

  String _mode = 'percent';

  bool get _allowNegative => _mode == 'percent' || _mode == 'amount';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  String _labelOf(L10n l10n, String mode) {
    switch (mode) {
      case 'set':
        return l10n.prodModeSet;
      case 'markup_cost':
        return l10n.prodModeMarkupCost;
      case 'amount':
        return l10n.prodModeAmount;
      default:
        return l10n.prodModePercent;
    }
  }

  String _hintOf(L10n l10n) {
    switch (_mode) {
      case 'set':
        return l10n.prodBatchHintSet;
      case 'markup_cost':
        return l10n.prodBatchHintMarkup;
      case 'amount':
        return l10n.prodBatchHintAmount;
      default:
        return l10n.prodBatchHintPercent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String mode in _modes)
              _Chip(
                label: _labelOf(l10n, mode),
                selected: _mode == mode,
                onTap: () => setState(() => _mode = mode),
              ),
          ],
        ),
        const VGap(16),
        NumberField(
          key: ValueKey<String>(_mode),
          label: l10n.prodBatchValue,
          controller: _value,
          allowNegative: _allowNegative,
          hint: _hintOf(l10n),
          suffix: _mode == 'percent' || _mode == 'markup_cost' ? '%' : app.profile.currencySymbol,
        ),
        const VGap(20),
        PrimaryButton(
          label: l10n.actApply,
          color: AppInk.products,
          onPressed: () {
            final double parsed = double.tryParse(_value.text.trim()) ?? 0;
            if (parsed == 0) return;
            Navigator.of(context).pop(_PriceEdit(_mode, parsed));
          },
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
          color: selected ? AppInk.products : AppInk.surfaceDim,
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(label, style: const TextStyle(fontSize: AppType.body)),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppInk.products,
      ),
    );
  }
}
