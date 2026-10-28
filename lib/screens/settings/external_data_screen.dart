import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';
import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// 外部商品源（YML / XML）。
///
/// 解析、字段映射、图片下载全部在服务端做，客户端只发地址、拿回整店统计与待写行，
/// 再把 `items` 原样分块回传 —— 所以这里不校对价格、不去重 SKU，重复由服务端按 SKU 覆盖。
/// 一次请求 60 s 封顶，整批必须按 25 行一块（生产 web 同一节流值）滚动提交，
/// 进度与失败明细都按块累加；「跳过已有 SKU」是唯一一次客户端过滤，靠全量商品索引比对。
class ExternalDataScreen extends StatefulWidget {
  const ExternalDataScreen({super.key});

  @override
  State<ExternalDataScreen> createState() => _ExternalDataScreenState();
}

class _ExternalDataScreenState extends State<ExternalDataScreen> {
  static const int _chunkSize = 25;
  static const int _maxExamples = 20;
  static const String _prefsKey = 'kucun.external.feedUrl';

  final TextEditingController _url = TextEditingController();
  final TextEditingController _markup = TextEditingController();

  ExternalPreview? _preview;
  ImportOutcome? _importResult;
  ExternalSyncOutcome? _syncResult;
  String? _error;
  bool _parsing = false;
  bool _running = false;
  bool _syncing = false;
  int _done = 0;
  int _total = 0;

  bool _downloadImages = true;
  bool _skipExisting = true;
  bool _priceAsCost = false;
  bool _updatePrice = true;
  bool _updateStock = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreUrl());
  }

  @override
  void dispose() {
    _url.dispose();
    _markup.dispose();
    super.dispose();
  }

  Future<void> _restoreUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_prefsKey);
    if (saved == null || saved.isEmpty || !mounted) return;
    setState(() => _url.text = saved);
  }

  Future<void> _rememberUrl(String url) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, url);
  }

  int? get _markupPercent {
    final int? value = int.tryParse(_markup.text.trim());
    return (value == null || value <= 0) ? null : value;
  }

  bool get _busy => _parsing || _running;

  Future<void> _parse() async {
    final String url = _url.text.trim();
    if (url.isEmpty || _busy) return;
    final AppState app = AppState.of(context);
    setState(() {
      _parsing = true;
      _error = null;
      _preview = null;
      _importResult = null;
      _syncResult = null;
    });
    unawaited(_rememberUrl(url));
    try {
      final ExternalPreview preview = await app.repos.settings.externalPreview(url);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _parsing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _error = app.describeError(error);
      });
    }
  }

  Future<void> _pasteUrl() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = (data?.text ?? '').trim();
    if (text.isEmpty) return;
    setState(() => _url.text = text);
  }

  Future<void> _runImport() async {
    final ExternalPreview? preview = _preview;
    if (preview == null || preview.items.isEmpty || _running) return;
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;

    List<JsonMap> items = preview.items;
    if (_skipExisting) {
      try {
        final Set<String> known =
            (await app.repos.products.searchIndex()).map((Product p) => p.sku).toSet();
        items = items
            .where((JsonMap row) => !known.contains(row.asStringOr('sku', '')))
            .toList(growable: false);
      } on Object catch (error) {
        if (!mounted) return;
        setState(() => _error = app.describeError(error));
        return;
      }
    }
    if (items.isEmpty) {
      if (mounted) showToast(context, l10n.extEmpty);
      return;
    }
    if (!mounted) return;
    final bool sure = await confirmAction(
      context,
      title: l10n.extImport(items.length),
      message: l10n.extImportConfirm(items.length),
      confirmLabel: l10n.actConfirm,
    );
    if (!sure || !mounted) return;
    await _importChunks(items);
  }

  Future<void> _importChunks(List<JsonMap> items) async {
    final AppState app = AppState.of(context);
    setState(() {
      _running = true;
      _syncing = false;
      _done = 0;
      _total = items.length;
      _error = null;
      _importResult = null;
    });

    int ok = 0;
    int bad = 0;
    int imageFailed = 0;
    final List<Map<String, Object?>> examples = <Map<String, Object?>>[];
    try {
      for (int start = 0; start < items.length; start += _chunkSize) {
        final List<JsonMap> chunk =
            items.skip(start).take(_chunkSize).toList(growable: false);
        final ImportOutcome res = await app.guardWrite<ImportOutcome>(
          () => app.repos.settings.externalImportChunk(
            chunk,
            downloadImages: _downloadImages,
            priceAsCost: _priceAsCost,
            markupPercent: _markupPercent,
          ),
        );
        ok += res.successCount;
        bad += res.failedCount;
        imageFailed += res.imageFailedCount;
        for (final JsonMap row in res.failures) {
          if (examples.length >= _maxExamples) break;
          examples.add(row.json);
        }
        if (!mounted) return;
        setState(() => _done = (start + _chunkSize).clamp(0, items.length));
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = app.describeError(error);
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _importResult = ImportOutcome(<String, Object?>{
        'success_count': ok,
        'failed_count': bad,
        'image_failed_count': imageFailed,
        'failed_examples': examples,
      });
    });
  }

  Future<void> _runSync() async {
    final ExternalPreview? preview = _preview;
    if (preview == null || preview.items.isEmpty || _running) return;
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final bool sure = await confirmAction(
      context,
      title: l10n.extSync,
      message: l10n.extSyncConfirm,
      confirmLabel: l10n.actConfirm,
    );
    if (!sure || !mounted) return;

    final List<JsonMap> items = preview.items;
    setState(() {
      _running = true;
      _syncing = true;
      _done = 0;
      _total = items.length;
      _error = null;
      _syncResult = null;
    });

    int updated = 0;
    int unchanged = 0;
    int skipped = 0;
    int failed = 0;
    final List<Map<String, Object?>> examples = <Map<String, Object?>>[];
    final List<JsonMap> newItems = <JsonMap>[];
    final String source = _url.text.trim();
    try {
      for (int start = 0; start < items.length; start += _chunkSize) {
        final List<JsonMap> chunk =
            items.skip(start).take(_chunkSize).toList(growable: false);
        final ExternalSyncOutcome res = await app.guardWrite<ExternalSyncOutcome>(
          () => app.repos.settings.externalSyncChunk(
            chunk,
            updatePrice: _updatePrice,
            updateStock: _updateStock,
            priceTarget: _priceAsCost ? 'cost' : 'price',
            markupPercent: _priceAsCost ? _markupPercent : null,
            source: source,
          ),
        );
        updated += res.updatedCount;
        unchanged += res.unchangedCount;
        skipped += res.skippedCount;
        failed += res.failedCount;
        for (final JsonMap row in res.failures) {
          if (examples.length >= _maxExamples) break;
          examples.add(row.json);
        }
        newItems.addAll(res.newItems);
        if (!mounted) return;
        setState(() => _done = (start + _chunkSize).clamp(0, items.length));
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = app.describeError(error);
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _syncResult = ExternalSyncOutcome(<String, Object?>{
        'updated_count': updated,
        'unchanged_count': unchanged,
        'skipped_count': skipped,
        'failed_count': failed,
        'failed_examples': examples,
        'new_items': newItems.map((JsonMap row) => row.json).toList(growable: false),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;
    final ExternalPreview? preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setExternal),
        leading: IconButton(
          tooltip: l10n.actClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 32),
        children: <Widget>[
          if (!app.online)
            NoticeBanner(
              text: l10n.setWriteBlockedOffline,
              color: AppInk.warning,
              icon: Icons.wifi_off_rounded,
            ),
          Text(
            l10n.setExternalNote,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
          ),
          const VGap(12),
          _group(
            title: l10n.extShop,
            accent: AppInk.inventory,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      label: l10n.extUrl,
                      controller: _url,
                      keyboardType: TextInputType.url,
                      hint: l10n.extUrlPlaceholder,
                      enabled: !_busy,
                    ),
                  ),
                  const HGap(8),
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: RoundIconButton(
                      icon: Icons.content_paste_rounded,
                      size: 38,
                      color: AppInk.inventory,
                      tooltip: l10n.actPaste,
                      onPressed: _busy ? null : _pasteUrl,
                    ),
                  ),
                ],
              ),
              const VGap(14),
              PrimaryButton(
                label: _parsing ? l10n.extParsing : l10n.extParse,
                icon: Icons.bolt_rounded,
                color: AppInk.inventory,
                loading: _parsing,
                onPressed: (_url.text.trim().isEmpty || _busy) ? null : _parse,
              ),
            ],
          ),
          if (_error != null)
            NoticeBanner(
              text: _error!,
              color: AppInk.danger,
              icon: Icons.error_outline_rounded,
            ),
          if (preview != null) ...<Widget>[
            _group(
              title: l10n.prodImportPreview,
              accent: AppInk.products,
              note: preview.shopName.isEmpty ? null : preview.shopName,
              children: <Widget>[
                _statGrid(<(String, String)>[
                  (l10n.extTotal, Fmt.count(preview.total)),
                  (l10n.extWithImage, Fmt.count(preview.withImageCount)),
                  (l10n.extWithBox, Fmt.count(preview.withBoxCount)),
                  (l10n.extCategories, Fmt.count(preview.categoriesCount)),
                ]),
              ],
            ),
            _group(
              title: l10n.extImportOptions,
              accent: AppInk.marketplace,
              children: <Widget>[
                _switch(l10n.extDownloadImages, _downloadImages,
                    (bool v) => setState(() => _downloadImages = v)),
                _switch(l10n.extSkipExisting, _skipExisting,
                    (bool v) => setState(() => _skipExisting = v)),
                _switch(l10n.extPriceAsCost, _priceAsCost,
                    (bool v) => setState(() => _priceAsCost = v)),
                if (_priceAsCost) ...<Widget>[
                  const VGap(10),
                  NumberField(
                    label: l10n.extMarkup,
                    controller: _markup,
                    allowDecimal: false,
                    suffix: '%',
                  ),
                  const VGap(8),
                  Text(
                    l10n.extMarkupHint,
                    style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
                  ),
                ],
              ],
            ),
            _group(
              title: l10n.extSyncOptions,
              accent: AppInk.finance,
              note: l10n.extSyncNote,
              children: <Widget>[
                _switch(l10n.extSyncPrice, _updatePrice,
                    (bool v) => setState(() => _updatePrice = v)),
                _switch(l10n.extSyncStock, _updateStock,
                    (bool v) => setState(() => _updateStock = v)),
              ],
            ),
            if (_running) _progress(l10n),
            Row(
              children: <Widget>[
                Expanded(
                  child: PrimaryButton(
                    label: _running && !_syncing
                        ? l10n.prodImportRunning(_done, _total)
                        : l10n.extImport(preview.items.length),
                    icon: Icons.upload_rounded,
                    color: AppInk.products,
                    loading: _running && !_syncing,
                    onPressed: app.canWrite && !_busy ? _runImport : null,
                  ),
                ),
                const HGap(10),
                Expanded(
                  child: GhostButton(
                    label: _running && _syncing
                        ? l10n.extSyncing(_done, _total)
                        : l10n.extSync,
                    icon: Icons.sync_rounded,
                    color: AppInk.finance,
                    onPressed: app.canWrite && !_busy && (_updatePrice || _updateStock)
                        ? _runSync
                        : null,
                  ),
                ),
              ],
            ),
            const VGap(16),
            if (_importResult != null) _importResultCard(l10n, _importResult!),
            if (_syncResult != null) _syncResultCard(l10n, app, _syncResult!),
          ],
        ],
      ),
    );
  }

  Widget _importResultCard(L10n l10n, ImportOutcome res) => _group(
        title: l10n.prodImportResult(res.successCount, res.failedCount),
        accent: res.failedCount == 0 ? AppInk.success : AppInk.warning,
        note: l10n.extImportResult(res.successCount, res.failedCount, res.imageFailedCount),
        children: _failureRows(l10n, res.failures),
      );

  Widget _syncResultCard(L10n l10n, AppState app, ExternalSyncOutcome res) => _group(
        title: l10n.extSync,
        accent: res.failedCount == 0 ? AppInk.success : AppInk.warning,
        note: l10n.extSyncResult(
          res.updatedCount,
          res.unchangedCount,
          res.skippedCount,
          res.failedCount,
        ),
        children: <Widget>[
          ..._failureRows(l10n, res.failures),
          if (res.newItems.isNotEmpty) ...<Widget>[
            const VGap(10),
            Text(
              l10n.extNewItems(res.newItems.length),
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
            ),
            const VGap(10),
            PrimaryButton(
              label: l10n.extImportNew(res.newItems.length),
              icon: Icons.playlist_add_rounded,
              color: AppInk.products,
              loading: _running && !_syncing,
              onPressed: app.canWrite && !_busy
                  ? () => _importChunks(res.newItems)
                  : null,
            ),
          ],
        ],
      );

  /// 服务端失败原因字段名不统一（reason / message），两种都取，界面不再猜。
  List<Widget> _failureRows(L10n l10n, List<JsonMap> failures) {
    if (failures.isEmpty) return const <Widget>[];
    return <Widget>[
      const VGap(10),
      Text(
        l10n.prodImportFailures,
        style: const TextStyle(fontSize: AppType.foot, fontWeight: AppType.semi),
      ),
      const VGap(6),
      for (final JsonMap row in failures.take(10))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: KeyValueRow(
            label: row.asStringOr('sku', row.asStringOr('name', '—')),
            value: row.asStringOr('reason', row.asStringOr('message', '—')),
            accent: AppInk.danger,
          ),
        ),
    ];
  }

  Widget _progress(L10n l10n) {
    final int percent = _total == 0 ? 0 : (_done * 100 / _total).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _syncing
                      ? l10n.extSyncing(_done, _total)
                      : l10n.prodImportRunning(_done, _total),
                  style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
                ),
              ),
              Text('$percent%', style: const TextStyle(fontSize: AppType.foot)),
            ],
          ),
          const VGap(6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: percent / 100, minHeight: 6),
          ),
          const VGap(8),
        ],
      ),
    );
  }

  Widget _statGrid(List<(String, String)> cells) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: StatTile(label: cells[0].$1, value: cells[0].$2, accent: AppInk.products)),
            const HGap(10),
            Expanded(
                child: StatTile(
                    label: cells[1].$1, value: cells[1].$2, accent: AppInk.marketplace)),
          ],
        ),
        const VGap(10),
        Row(
          children: <Widget>[
            Expanded(child: StatTile(label: cells[2].$1, value: cells[2].$2, accent: AppInk.inventory)),
            const HGap(10),
            Expanded(child: StatTile(label: cells[3].$1, value: cells[3].$2, accent: AppInk.orders)),
          ],
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        value: value,
        onChanged: _busy ? null : onChanged,
        title: Text(label, style: const TextStyle(fontSize: AppType.body)),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppInk.inventory,
      );

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
