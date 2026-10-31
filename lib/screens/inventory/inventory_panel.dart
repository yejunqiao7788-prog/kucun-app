import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../data/repositories.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/paged_view.dart';
import '../../design/widgets/product_identity.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/value_loader.dart';

/// 库存视图：`GET /products/inventory` 一次回全量，客户端只做分档与分组，不再分页。
///
/// 快调必须写回**整行**（服务端 PATCH 是整体替换），所以先按 SKU 取回完整商品，
/// 只改 `quantity`，其余字段原样带回去；库存永远是绝对值，不是增减量。
class InventoryPanel extends StatefulWidget {
  const InventoryPanel({super.key});

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _StockSnapshot {
  const _StockSnapshot(this.rows, this.stale);

  final List<InventoryRow> rows;
  final bool stale;
}

class _InventoryPanelState extends State<InventoryPanel> {
  late final Repos _repos = context.read<AppState>().repos;
  final TextEditingController _search = TextEditingController();

  StockTier? _tier;
  bool _groupByLocation = false;
  bool _writing = false;

  late final ValueLoader<_StockSnapshot> _loader =
      ValueLoader<_StockSnapshot>(() async {
    final ApiResponse<List<InventoryRow>> res = await _repos.products.inventory();
    return _StockSnapshot(res.data, res.stale);
  });

  /// build 里直接读 `_loader.value`，没有 AnimatedBuilder 接手，所以自己挂监听：
  /// 否则数据回来后没人重绘，页面会一直停在骨架屏。
  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loader.addListener(_repaint);
    _loader.load();
  }

  @override
  void dispose() {
    _loader.removeListener(_repaint);
    _search.dispose();
    _loader.dispose();
    super.dispose();
  }

  List<InventoryRow> get _all => _loader.value?.rows ?? const <InventoryRow>[];

  List<InventoryRow> get _visible {
    final String keyword = _search.text.trim().toLowerCase();
    return _all
        .where((InventoryRow row) =>
            (_tier == null || row.tier == _tier) &&
            (keyword.isEmpty ||
                row.name.toLowerCase().contains(keyword) ||
                row.sku.toLowerCase().contains(keyword) ||
                row.locationGroup.toLowerCase().contains(keyword)))
        .toList(growable: false);
  }

  Future<void> _adjust(InventoryRow row) async {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    if (!app.canWrite) {
      showToast(context, l10n.setWriteBlockedOffline, danger: true);
      return;
    }
    final int? target = await showDrawer<int>(
      context,
      accent: AppInk.inventory,
      title: '${l10n.invAdjust} · ${row.name}',
      builder: (BuildContext sheetContext) => _AdjustDrawer(row: row, l10n: l10n),
    );
    if (target == null || target == row.quantity || !mounted) return;

    setState(() => _writing = true);
    try {
      await app.guardWrite<void>(() async {
        final Product? full =
            await _repos.products.fullRow(id: row.productId, sku: row.sku);
        if (full == null) {
          throw ApiException(
            status: 404,
            code: 'NOT_FOUND',
            serverMessage: l10n.commonErrorTitle,
          );
        }
        await _repos.products.update(full.id, _writePayload(full, quantity: target));
      });
      if (!mounted) return;
      showToast(context, l10n.invAfter(target));
      await _loader.refresh();
    } on Object catch (error) {
      if (!mounted) return;
      showToast(context, app.describeError(error), danger: true);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  /// 整行替换载荷：`sku`/`name` 是硬必填，画廊与描述必须原样带回，否则会被清空。
  static Map<String, Object?> _writePayload(Product row, {required int quantity}) {
    final int? perBox = row.unitsPerBox;
    return <String, Object?>{
      'sku': row.sku,
      'name': row.name,
      'price': row.price,
      'cost': row.cost,
      'unit': row.unit,
      'description': row.description,
      'units_per_box': (perBox != null && perBox > 1) ? perBox : null,
      'box_price': (perBox != null && perBox > 1) ? row.boxPrice : null,
      'category_id': row.categoryId,
      'quantity': quantity,
      'min_stock': row.minStock,
      'max_stock': row.maxStock,
      'location': row.location ?? '',
      'image_urls': row.imageUrls,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

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
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const HGap(8),
              RoundIconButton(
                icon: _groupByLocation
                    ? Icons.group_work_rounded
                    : Icons.filter_none_rounded,
                color: _groupByLocation ? AppInk.inventory : null,
                tooltip: l10n.invByLocation,
                onPressed: () => setState(() => _groupByLocation = !_groupByLocation),
              ),
            ],
          ),
        ),
        PillTabs<StockTier?>(
          values: const <StockTier?>[null, StockTier.out, StockTier.low, StockTier.overflow, StockTier.normal],
          selected: _tier,
          accent: AppInk.inventory,
          labelOf: (StockTier? value) => switch (value) {
            null => l10n.commonAll,
            StockTier.out => l10n.invOutOf,
            StockTier.low => l10n.invLow,
            StockTier.overflow => l10n.invOverflow,
            StockTier.normal => l10n.invNormal,
          },
          onChanged: (StockTier? value) => setState(() => _tier = value),
        ),
        const VGap(6),
        if (_writing)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 8),
            child: NoticeBanner(
              text: l10n.commonSaving,
              color: AppInk.info,
              icon: Icons.sync_rounded,
            ),
          )
        else if (_loader.value != null && _loader.value!.stale && app.online)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 8),
            child: NoticeBanner(
              text: l10n.commonStaleBanner,
              color: AppInk.info,
              icon: Icons.history_rounded,
            ),
          )
        else if (_loader.hasValue && _loader.errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 0),
            child: RefreshFailureBanner.stale(_loader),
          ),
        Expanded(child: _body(l10n)),
      ],
    );
  }

  Widget _body(L10n l10n) {
    if (_loader.loading && _loader.value == null) {
      return const SkeletonList(count: 6, itemHeight: 76);
    }
    if (_loader.errorText != null && _loader.value == null) {
      return AppErrorView(message: _loader.errorText!, onRetry: _loader.load);
    }
    final List<InventoryRow> rows = _visible;
    if (rows.isEmpty) {
      return AppEmpty(
        title: l10n.commonEmptyTitle,
        hint: l10n.invMovementsNote,
        icon: Icons.layers_outlined,
        accent: AppInk.inventory,
      );
    }

    if (!_groupByLocation) {
      return RefreshIndicator(
        onRefresh: _loader.refresh,
        color: AppInk.inventory,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 120),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const VGap(10),
          itemBuilder: (BuildContext context, int index) => _row(rows[index], l10n),
        ),
      );
    }

    final Map<String, List<InventoryRow>> groups = <String, List<InventoryRow>>{};
    for (final InventoryRow row in rows) {
      final String key =
          row.locationGroup.isEmpty ? l10n.invUnassigned : row.locationGroup;
      groups.putIfAbsent(key, () => <InventoryRow>[]).add(row);
    }
    final List<String> keys = groups.keys.toList()
      ..sort((String a, String b) => a.compareTo(b));

    return RefreshIndicator(
      onRefresh: _loader.refresh,
      color: AppInk.inventory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 120),
        children: <Widget>[
          for (final String key in keys) ...<Widget>[
            SectionHeader(
              title: key,
              accent: AppInk.inventory,
              subtitle: '${Fmt.count(groups[key]!.length)} · '
                  '${Fmt.count(groups[key]!.fold<int>(0, (int sum, InventoryRow r) => sum + r.quantity))}',
            ),
            for (final InventoryRow row in groups[key]!)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _row(row, l10n)),
            const VGap(10),
          ],
        ],
      ),
    );
  }

  Widget _row(InventoryRow row, L10n l10n) {
    final Color color = tierColor(row.tier);
    final String tierLabel = switch (row.tier) {
      StockTier.out => l10n.invOutOf,
      StockTier.low => l10n.invLow,
      StockTier.overflow => l10n.invOverflow,
      StockTier.normal => l10n.invNormal,
    };
    return RowCard(
      accent: AppInk.inventory,
      onTap: () => _adjust(row),
      identity: ProductIdentity(
        sku: row.sku,
        name: row.name,
        showName: AppState.of(context).productNameVisible,
        secondary: row.categoryName ?? l10n.commonNone,
      ),
      leading: Thumbnail(url: row.imageUrl),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            '${Fmt.count(row.quantity)}${row.unit}',
            style: TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy, color: color),
          ),
          const VGap(2),
          Text(
            '${l10n.prodMinStock} ${row.minStock} / ${l10n.prodMaxStock} ${row.maxStock}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      badges: <Widget>[
        if (row.tier != StockTier.normal)
          StatusPill(label: tierLabel, color: color, dense: true),
        StatusPill(
          label: row.locationGroup.isEmpty ? l10n.invUnassigned : row.locationGroup,
          color: AppInk.settings,
          dense: true,
        ),
      ],
      footRow: Row(
        children: <Widget>[
          Expanded(
            child: Text(l10n.invAdjust,
                style: TextStyle(fontSize: AppType.foot, color: AppInk.inventory, fontWeight: AppType.semi)),
          ),
          const Icon(Icons.edit_rounded, size: 16, color: AppInk.inventory),
        ],
      ),
    );
  }
}

Color tierColor(StockTier tier) {
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

/// 快调抽屉：默认填「变动量」，因为数货的人知道多了几件；也可以切换成直接设定绝对值。
class _AdjustDrawer extends StatefulWidget {
  const _AdjustDrawer({required this.row, required this.l10n});

  final InventoryRow row;
  final L10n l10n;

  @override
  State<_AdjustDrawer> createState() => _AdjustDrawerState();
}

class _AdjustDrawerState extends State<_AdjustDrawer> {
  final TextEditingController _value = TextEditingController();
  bool _absolute = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  int get _target {
    final int parsed = int.tryParse(_value.text.trim()) ?? 0;
    if (_absolute) return parsed < 0 ? 0 : parsed;
    final int next = widget.row.quantity + parsed;
    return next < 0 ? 0 : next;
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = widget.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        KeyValueRow(label: l10n.prodSku, value: widget.row.sku),
        KeyValueRow(
          label: l10n.prodQty,
          value: '${Fmt.count(widget.row.quantity)}${widget.row.unit}',
          accent: tierColor(widget.row.tier),
        ),
        const VGap(14),
        PillTabs<bool>(
          values: const <bool>[false, true],
          selected: _absolute,
          accent: AppInk.inventory,
          scrollable: false,
          labelOf: (bool v) => v ? l10n.invSetAbsolute : l10n.invDelta,
          onChanged: (bool v) => setState(() => _absolute = v),
        ),
        const VGap(14),
        Row(
          children: <Widget>[
            Expanded(
              child: NumberField(
                label: _absolute ? l10n.prodQty : l10n.invDelta,
                controller: _value,
                autofocus: true,
                allowNegative: !_absolute,
                allowDecimal: false,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const HGap(10),
            QtyStepper(
              value: int.tryParse(_value.text.trim()) ?? 0,
              min: _absolute ? 0 : -widget.row.quantity,
              max: 999999,
              onChanged: (int v) => setState(() => _value.text = '$v'),
            ),
          ],
        ),
        const VGap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final int step in const <int>[-10, -1, 1, 10, 50, 100])
              if (!_absolute || step > 0)
                GestureDetector(
                  onTap: () => setState(() => _value.text = '$step'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppInk.tint(AppInk.inventory, alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      _absolute ? '$step' : Fmt.signedCount(step),
                      style: const TextStyle(
                          fontSize: AppType.foot, fontWeight: AppType.semi, color: AppInk.inventory),
                    ),
                  ),
                ),
          ],
        ),
        const VGap(18),
        Text(
          l10n.invAfter(_target),
          style: TextStyle(fontSize: AppType.head, fontWeight: AppType.heavy, color: AppInk.inventory),
        ),
        const VGap(16),
        PrimaryButton(
          label: l10n.actSave,
          icon: Icons.check_rounded,
          color: AppInk.inventory,
          onPressed: () => Navigator.of(context).pop(_target),
        ),
        const VGap(8),
      ],
    );
  }
}
