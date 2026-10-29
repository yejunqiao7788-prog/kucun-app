import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../data/entities.dart';
import '../../data/product_sheet.dart';
import '../../design/tokens.dart';
import '../../design/widgets/controls.dart';

import '../../design/widgets/sheets.dart';
import '../../design/widgets/state_views.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// 表格导入。
///
/// 主通道是选 .xlsx 文件：列名识别、箱规校验、库存合计都按原项目网页端的规则来，
/// 商户拿同一张表在两边导，落到 `/products/import` 的行必须一模一样。
/// 粘贴作为回退留着 —— .xls、CSV，或者只想改三五行库存时，从 Excel/WPS 复制区域过来照样能用。
/// 这一页只负责解析与预览：重复 SKU、非法值由服务端判，失败原因原样摊出来，
/// 界面不自作主张去重或补默认价。
class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key, this.canImport = true});

  final bool canImport;

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  /// 服务端一次吃 50 行（原项目的节流值），超出的行由这里分批。
  static const int _chunkSize = 50;

  final TextEditingController _input = TextEditingController();

  List<SheetRow> _rows = const <SheetRow>[];
  List<String> _dropped = const <String>[];
  List<String> _dupSkus = const <String>[];
  String? _source;
  bool _reading = false;
  bool _fixOnly = false;
  bool _running = false;
  int _done = 0;
  int _ok = 0;
  int _bad = 0;
  List<JsonMap> _failures = const <JsonMap>[];
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply(SheetParse parse, {String? fromFile}) {
    final L10n l10n = AppState.of(context).l10n;
    final bool hadPasted = fromFile == null && _input.text.trim().isNotEmpty;
    // 文件与粘贴是两条互斥的通道：选了文件，粘贴框里那份旧内容就不该再算数。
    if (fromFile != null) _input.clear();
    setState(() {
      _rows = parse.rows;
      _dropped = parse.dropped;
      _dupSkus = parse.duplicateSkus;
      _source = fromFile;
      _reading = false;
      _error = switch (parse.failure) {
        SheetFailure.corrupt => l10n.prodImportXlsxEmpty,
        SheetFailure.missingColumns => l10n.prodImportXlsxColumns,
        SheetFailure.noRows => l10n.prodImportXlsxNone,
        null => parse.rows.isEmpty && (fromFile != null || hadPasted) ? l10n.prodImportEmpty : null,
      };
      _ok = 0;
      _bad = 0;
      _failures = const <JsonMap>[];
    });
  }

  void _parse() => _apply(parsePastedText(_input.text));

  Future<void> _pickXlsx() async {
    if (_reading || _running) return;
    final AppState app = AppState.of(context);
    setState(() {
      _reading = true;
      _error = null;
    });
    final SheetParse parse;
    String? name;
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        dialogTitle: app.l10n.prodImportPickXlsx,
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx'],
      );
      if (file == null) {
        if (!mounted) return;
        setState(() => _reading = false);
        return;
      }
      name = file.name;
      // 解析整张工作簿是同步重活，上千行会把界面卡住，所以丢给 isolate。
      parse = await compute(parseXlsxBytes, await file.readAsBytes());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = app.describeError(error);
      });
      return;
    }
    if (!mounted) return;
    _apply(parse, fromFile: name);
  }

  Future<void> _downloadTemplate({required bool withBox}) async {
    final AppState app = AppState.of(context);
    final L10n l10n = app.l10n;
    final String fileName = withBox ? 'import_template.xlsx' : 'import_template_simple.xlsx';
    setState(() {
      _error = null;
    });
    try {
      final Uint8List bytes = buildImportTemplateXlsx(withBox: withBox);
      final Uri? saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: l10n.prodImportTemplate,
      );
      if (!mounted || saved == null) return;
      showToast(context, l10n.prodImportTemplateSaved(fileName));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = app.describeError(error));
    }
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text ?? '';
    if (text.isEmpty) return;
    _input.text = _input.text.isEmpty ? text : '${_input.text}\n$text';
    _parse();
  }

  Future<void> _run() async {
    if (_rows.isEmpty || _running) return;
    final AppState app = AppState.of(context);
    setState(() {
      _running = true;
      _done = 0;
      _ok = 0;
      _bad = 0;
      _failures = const <JsonMap>[];
      _error = null;
    });

    int ok = 0;
    int bad = 0;
    final List<JsonMap> failures = <JsonMap>[];
    final String tenantId = app.profile.tenantId;
    try {
      for (int start = 0; start < _rows.length; start += _chunkSize) {
        final List<Map<String, Object?>> items = _rows
            .skip(start)
            .take(_chunkSize)
            .map((SheetRow row) => row.payload(tenantId))
            .toList(growable: false);
        final ImportOutcome res = await app.guardWrite<ImportOutcome>(
          () => _fixOnly
              ? app.repos.products.importCorrections(items)
              : app.repos.products.importRows(items),
        );
        ok += res.successCount;
        bad += res.failedCount;
        failures.addAll(res.failures);
        if (!mounted) return;
        setState(() {
          _done = (start + _chunkSize) > _rows.length ? _rows.length : start + _chunkSize;
          _ok = ok;
          _bad = bad;
          _failures = List<JsonMap>.unmodifiable(failures);
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = app.describeError(error);
        _running = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final L10n l10n = app.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.prodImport),
        leading: IconButton(
          tooltip: l10n.actClose,
          icon: const Icon(Icons.close_rounded),
          // 只要写过就告诉外面刷新列表，哪怕部分行失败。
          onPressed: () => Navigator.of(context).pop(_ok + _bad > 0),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 32),
        children: <Widget>[
          _fileCard(l10n),
          const VGap(14),
          PillTabs<bool>(
            values: const <bool>[false, true],
            selected: _fixOnly,
            accent: AppInk.products,
            labelOf: (bool value) => value ? l10n.prodImportFixOnly : l10n.prodImport,
            onChanged: (bool value) => setState(() {
              _fixOnly = value;
              _resetPreview();
            }),
          ),
          if (_error != null) ...<Widget>[
            const VGap(14),
            NoticeBanner(text: _error!, color: AppInk.danger, icon: Icons.error_outline_rounded),
          ],
          if (_rows.isNotEmpty) ...<Widget>[
            const VGap(16),
            SectionHeader(
              title: l10n.prodImportReady(_rows.length),
              subtitle: _subtitle(l10n),
              accent: AppInk.products,
            ),
            AppCard(
              accent: AppInk.products,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: <Widget>[
                  for (final SheetRow row in _rows.take(12))
                    TileRow(
                      icon: Icons.inventory_2_rounded,
                      accent: AppInk.products,
                      title: '${row.sku} · ${row.name}',
                      subtitle: '${Fmt.count(row.quantity)} ${row.unit.isEmpty ? '个' : row.unit} · '
                          '${app.formatMoney(row.price)}'
                          '${row.category.isEmpty ? '' : ' · ${row.category}'}'
                          '${row.location.isEmpty ? '' : ' · ${row.location}'}',
                    ),
                  if (_rows.length > 12)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '…',
                        style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_dropped.isNotEmpty) ...<Widget>[
            const VGap(14),
            NoticeBanner(
              text: l10n.prodImportSkipped(_dropped.length),
              color: AppInk.warning,
              icon: Icons.warning_amber_rounded,
            ),
            const VGap(8),
            Text(
              _dropped.take(3).join(' / '),
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
          ],
          if (_dupSkus.isNotEmpty) ...<Widget>[
            const VGap(14),
            NoticeBanner(
              text: l10n.prodImportDup(_dupSkus.length),
              color: AppInk.warning,
              icon: Icons.copy_rounded,
            ),
            const VGap(8),
            Text(
              _dupSkus.take(6).join(' / '),
              style: const TextStyle(fontSize: AppType.foot, color: AppInk.textTertiary),
            ),
          ],
          if (_running || _ok + _bad > 0) ...<Widget>[
            const VGap(16),
            AppCard(
              accent: AppInk.inventory,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _running
                        ? l10n.prodImportRunning(_done, _rows.length)
                        : l10n.prodImportResult(_ok, _bad),
                    style: const TextStyle(fontSize: AppType.body, fontWeight: AppType.semi),
                  ),
                  if (_running) ...<Widget>[
                    const VGap(10),
                    const AppSpinner(color: AppInk.inventory),
                  ],
                  if (_failures.isNotEmpty) ...<Widget>[
                    const VGap(12),
                    Text(
                      l10n.prodImportFailures,
                      style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
                    ),
                    const VGap(6),
                    for (final JsonMap row in _failures.take(12))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${row.asStringOr('sku', '—')} · ${row.asStringOr('reason', row.asStringOr('message', ''))}'.trim(),
                          style: const TextStyle(fontSize: AppType.foot, color: AppInk.danger),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
          const VGap(20),
          PrimaryButton(
            label: l10n.prodImport,
            icon: Icons.upload_rounded,
            color: AppInk.products,
            loading: _running,
            onPressed: _running || _rows.isEmpty || !widget.canImport ? null : _run,
          ),
        ],
      ),
    );
  }

  String? _subtitle(L10n l10n) {
    final List<String> parts = <String>[
      if (_source != null) _source!,
      if (_dropped.isNotEmpty) l10n.prodImportSkipped(_dropped.length),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 文件通道与模板下载放一张卡，粘贴区收在下面 —— 手机上多数时候要的就是「选文件、导入」两步。
  Widget _fileCard(L10n l10n) {
    return AppCard(
      accent: AppInk.products,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PrimaryButton(
            label: _reading ? l10n.prodImportReading : l10n.prodImportPickXlsx,
            icon: Icons.table_chart_rounded,
            color: AppInk.products,
            loading: _reading,
            onPressed: _reading || _running ? null : _pickXlsx,
          ),
          const VGap(12),
          Row(
            children: <Widget>[
              TextAction(
                label: l10n.prodImportTemplateStandard,
                color: AppInk.products,
                onPressed: _reading ? null : () => _downloadTemplate(withBox: true),
              ),
              const HGap(14),
              TextAction(
                label: l10n.prodImportTemplateSimple,
                color: AppInk.products,
                onPressed: _reading ? null : () => _downloadTemplate(withBox: false),
              ),
            ],
          ),
          const VGap(10),
          Text(
            l10n.prodImportTemplatesNote,
            style: const TextStyle(fontSize: AppType.micro, color: AppInk.textTertiary),
          ),
          const VGap(14),
          Text(
            l10n.prodImportHint,
            style: const TextStyle(fontSize: AppType.foot, color: AppInk.textSecondary),
          ),
          const VGap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(color: AppInk.surfaceDim, borderRadius: Radii.control_),
            child: TextField(
              controller: _input,
              minLines: 5,
              maxLines: 12,
              style: const TextStyle(fontSize: AppType.foot),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (_) {
                if (_rows.isNotEmpty) setState(_resetPreview);
              },
            ),
          ),
          const VGap(10),
          Row(
            children: <Widget>[
              TextAction(label: l10n.actPaste, color: AppInk.products, onPressed: _running ? null : _paste),
              const HGap(12),
              TextAction(
                label: l10n.actClear,
                color: AppInk.textSecondary,
                onPressed: _running
                    ? null
                    : () {
                        _input.clear();
                        setState(_resetPreview);
                      },
              ),
              const HGap(12),
              TextAction(
                label: l10n.prodImportPreview,
                color: AppInk.products,
                onPressed: _running ? null : _parse,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _resetPreview() {
    _rows = const <SheetRow>[];
    _dropped = const <String>[];
    _dupSkus = const <String>[];
    _source = null;
    _ok = 0;
    _bad = 0;
    _failures = const <JsonMap>[];
    _error = null;
  }
}
