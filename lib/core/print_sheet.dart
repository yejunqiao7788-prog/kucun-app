import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/entities.dart';
import 'formatters.dart';
import 'l10n.dart';

/// 明细表的列计划：四个开关决定列数，以及「合计标签」与「数量」各自落在哪一格。
///
/// 抽成值对象是因为 pdf 的 TableRow 没有 colspan —— 合计行与「无明细」行都要按同一份
/// 列数逐格补齐，算错一格就是「合计」两个字盖掉总数量。16 种开关组合在
/// `test/print_sheet_test.dart` 里逐格对账。
class SheetLayout {
  const SheetLayout({
    required this.showImage,
    required this.showName,
    required this.showSku,
    required this.showPrice,
    required this.imgMm,
  });

  final bool showImage;
  final bool showName;
  final bool showSku;
  final bool showPrice;
  final double imgMm;

  List<pw.TableColumnWidth> get columns => <pw.TableColumnWidth>[
        const pw.FixedColumnWidth(26),
        if (showImage) pw.FixedColumnWidth(PdfPageFormat.mm * (imgMm + 4)),
        if (showName) const pw.FlexColumnWidth(3),
        // 名称列被关掉时，码这一格接管它腾出来的宽度（网页端 td.sku 的 width: auto）。
        if (showSku)
          showName ? const pw.FixedColumnWidth(92) : const pw.FlexColumnWidth(3),
        const pw.FixedColumnWidth(58),
        if (showPrice) const pw.FixedColumnWidth(72),
        if (showPrice) const pw.FixedColumnWidth(80),
      ];

  int get count => columns.length;

  int get nameAt => 1 + (showImage ? 1 : 0);

  int get skuAt => nameAt + (showName ? 1 : 0);

  /// 「无明细」与合计标签落在第一个商品标识列上：名称开着是名称列，关着是 SKU 列。
  /// 两个都关（服务端拦着这一档，但旧行可能已经是这样）时退到序号列，绝不与数量格重合。
  int get labelAt => showName ? nameAt : (showSku ? skuAt : 0);

  /// 数量列在单价之前，不开单价时它就是最后一列。
  int get qtyAt => count - 1 - (showPrice ? 1 : 0);
}

/// 入库单 / 出库单的 PDF 版式，逐块对齐网页端 `utils/printOrder.ts` 的打印 HTML：
/// 抬头（logo · 公司 · 联系方式）、单据标题、单据信息行、明细表、合计行、备注、
/// 经办人与客户签收行、页脚（租户自定义文字 + 出单时间）。
///
/// 网页端把 HTML 写进新窗口交给浏览器打印；客户端没有那条路径，这里用同一份数据
/// 直接出 PDF。模板尺寸与四个显示开关读 `/print-settings`，收款信息一律不上单据。
/// 「显示商品名称」关掉时名称整列消失，列数与合计行的补格跟着它走。
class OrderSheet {
  OrderSheet._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF111111);
  static const PdfColor _soft = PdfColor.fromInt(0xFF555555);
  static const PdfColor _faint = PdfColor.fromInt(0xFF999999);
  static const PdfColor _line = PdfColor.fromInt(0xFFCCCCCC);
  static const PdfColor _headBg = PdfColor.fromInt(0xFFF2ECDF);
  static const PdfColor _badgeLine = PdfColor.fromInt(0xFFDCD3BE);
  static const PdfColor _bandBg = PdfColor.fromInt(0xFFF9F4EA);
  static const PdfColor _accent = PdfColor.fromInt(0xFF9E2A1F);

  static pw.Font? _latin;
  static pw.Font? _latinBold;
  static pw.Font? _cjk;

  /// PDF 引擎不吃系统字体，单据上的中文只能随包带字形。正文走 Noto Sans，这样常规与粗体
  /// 是同一套字面的两个字重；缺字时再落到 Noto Sans SC。SC 没有乌克兰语 є/ї 与越南语变音，
  /// 所以它只做汉字兜底，不当主字体。
  static Future<pw.ThemeData> _theme() async {
    _latin ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _latinBold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    _cjk ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
    return pw.ThemeData.withFont(
      base: _latin,
      bold: _latinBold,
      fontFallback: <pw.Font>[_cjk!],
    );
  }

  static Future<Uint8List> build({
    required Order order,
    required PrintSettings settings,
    required L10n l10n,
    required String currencySymbol,
    DateTime? generatedAt,
  }) async {
    final pw.ThemeData theme = await _theme();
    final bool compact = settings.templateId == 'compact';
    // 紧凑模板 = A5 + 11pt + 12mm 图片；标准 = A4 + 12pt + 16mm。
    final double pt = compact ? 11 : 12;
    final double imgMm = compact ? 12 : 16;
    final List<OrderItem> items = order.items;
    // 图片列要开关打开、且至少一行真有图才占位，否则整列空白。
    final bool showImage =
        settings.showImage && items.any((OrderItem it) => (it.imageUrl ?? '').isNotEmpty);
    final bool showSku = settings.showSku;
    final bool showPrice = settings.showPrice;
    // 租户级「显示商品名称」：关掉之后单据上只剩码（仓管/贴码场景）。
    // 服务端保证「名称与 SKU 至少留一个」，所以这里不需要再兜一次底。
    final bool showName = settings.showProductName;
    final Map<String, pw.MemoryImage> images =
        showImage ? await _loadImages(items) : const <String, pw.MemoryImage>{};
    final pw.MemoryImage? logo =
        settings.logoUrl.isEmpty ? null : await _loadImage(settings.logoUrl);

    final pw.Document doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: compact ? PdfPageFormat.a5 : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 42, 34, 34),
        footer: (pw.Context context) => _footer(settings, pt, generatedAt ?? DateTime.now()),
        build: (pw.Context context) => <pw.Widget>[
          _header(settings, pt, logo),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              order.type == OrderType.inbound ? l10n.sheetDocInbound : l10n.sheetDocOutbound,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: pt + 4,
                letterSpacing: 4,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          _meta(order, l10n, pt),
          pw.SizedBox(height: 8),
          _itemsTable(
            items: items,
            l10n: l10n,
            pt: pt,
            currency: currencySymbol,
            showImage: showImage,
            showSku: showSku,
            showName: showName,
            showPrice: showPrice,
            imgMm: imgMm,
            images: images,
          ),
          if ((order.notes ?? '').isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _notes(order.notes!, l10n, pt),
          ],
          pw.SizedBox(height: 20),
          _signatures(l10n, pt),
        ],
      ),
    );
    return doc.save();
  }

  /// 抬头三项全空（新租户的 print_settings 默认就是空串）时整块不渲染，
  /// 否则单据顶部只剩一条没有内容的粗横线。
  static pw.Widget _header(PrintSettings settings, double pt, pw.MemoryImage? logo) {
    if (settings.companyName.isEmpty && settings.contactInfo.isEmpty && logo == null) {
      return pw.SizedBox.shrink();
    }
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 2, color: _ink)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          if (logo != null) ...<pw.Widget>[
            pw.Image(logo, width: 40, height: 40, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                if (settings.companyName.isNotEmpty)
                  pw.Text(
                    settings.companyName,
                    style: pw.TextStyle(fontSize: pt + 6, letterSpacing: 1.2),
                  ),
                if (settings.contactInfo.isNotEmpty)
                  pw.Text(
                    settings.contactInfo,
                    style: pw.TextStyle(fontSize: pt - 1.5, color: _soft),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _meta(Order order, L10n l10n, double pt) => pw.Wrap(
        spacing: 20,
        runSpacing: 4,
        children: <pw.Widget>[
          _metaLine(l10n.sheetMetaOrderNo, order.orderNumber, pt, strong: true),
          _metaLine(l10n.sheetMetaDate, order.orderDate ?? '', pt),
          if (order.customerName.isNotEmpty)
            _metaLine(l10n.sheetMetaCustomer, order.customerName, pt),
          if ((order.customerPhone ?? '').isNotEmpty)
            _metaLine(l10n.sheetMetaPhone, order.customerPhone!, pt),
        ],
      );

  static pw.Widget _metaLine(String label, String value, double pt, {bool strong = false}) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            '$label · ',
            style: pw.TextStyle(fontSize: pt - 1.5, color: _soft),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: strong ? pt : pt - 1.5,
              color: strong ? _ink : _soft,
            ),
          ),
        ],
      );

  static pw.Widget _itemsTable({
    required List<OrderItem> items,
    required L10n l10n,
    required double pt,
    required String currency,
    required bool showImage,
    required bool showSku,
    required bool showName,
    required bool showPrice,
    required double imgMm,
    required Map<String, pw.MemoryImage> images,
  }) {
    final double cell = pt - 1.5;
    final SheetLayout layout = SheetLayout(
      showImage: showImage,
      showName: showName,
      showSku: showSku,
      showPrice: showPrice,
      imgMm: imgMm,
    );
    final List<pw.TableColumnWidth> cols = layout.columns;
    final int columns = layout.count;
    final int labelAt = layout.labelAt;
    final int qtyAt = layout.qtyAt;

    pw.Widget head(String text, pw.Alignment align) => _pad(
          pw.Align(
            alignment: align,
            child: pw.Text(
              text,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: cell),
            ),
          ),
        );

    pw.Widget body(pw.Widget child) => _pad(child);

    return pw.Table(
      columnWidths: <int, pw.TableColumnWidth>{
        for (int i = 0; i < columns; i++) i: cols[i],
      },
      defaultColumnWidth: const pw.FlexColumnWidth(),
      border: pw.TableBorder.all(color: _line, width: 0.7),
      children: <pw.TableRow>[
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _headBg),
          children: <pw.Widget>[
            head('#', pw.Alignment.center),
            if (showImage) head(l10n.sheetColImage, pw.Alignment.center),
            if (showName) head(l10n.sheetColProduct, pw.Alignment.centerLeft),
            if (showSku) head('SKU', pw.Alignment.centerLeft),
            head(l10n.sheetColQty, pw.Alignment.centerRight),
            if (showPrice) head(l10n.sheetColUnitPrice, pw.Alignment.centerRight),
            if (showPrice) head(l10n.sheetColSubtotal, pw.Alignment.centerRight),
          ],
        ),
        if (items.isEmpty)
          pw.TableRow(
            children: <pw.Widget>[
              for (int i = 0; i < columns; i++)
                i == labelAt
                    ? body(pw.Center(
                        child: pw.Text(
                          l10n.sheetEmptyRows,
                          style: pw.TextStyle(fontSize: cell, color: _faint),
                        ),
                      ))
                    : body(pw.SizedBox.shrink()),
            ],
          )
        else
          for (int i = 0; i < items.length; i++)
            pw.TableRow(
              children: <pw.Widget>[
                body(pw.Center(
                  child: pw.Text('${i + 1}', style: pw.TextStyle(fontSize: cell, color: _soft)),
                )),
                if (showImage) body(_image(items[i], imgMm, images)),
                if (showName) body(_name(items[i], cell)),
                if (showSku) body(_sku(items[i], cell, withCategory: !showName)),
                body(pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: <pw.Widget>[
                      pw.Text(Fmt.count(items[i].quantity), style: pw.TextStyle(fontSize: cell)),
                      if (items[i].boxCount > 0 && (items[i].unitsPerBox ?? 0) > 1)
                        pw.Text(
                          _boxLine(l10n, items[i]),
                          style: pw.TextStyle(fontSize: cell - 1, color: _soft),
                        ),
                    ],
                  ),
                )),
                if (showPrice)
                  body(pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      Fmt.money(items[i].unitPrice, symbol: currency),
                      style: pw.TextStyle(fontSize: cell),
                    ),
                  )),
                if (showPrice)
                  body(pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      Fmt.money(items[i].subtotal, symbol: currency),
                      style: pw.TextStyle(fontSize: cell),
                    ),
                  )),
              ],
            ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: _bandBg,
            border: pw.Border(top: pw.BorderSide(width: 2, color: _ink)),
          ),
          children: <pw.Widget>[
            for (int i = 0; i < columns; i++)
              if (i == labelAt)
                body(pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    l10n.sheetTotal,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: pt - 0.5),
                  ),
                ))
              else if (i == qtyAt)
                body(pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    Fmt.count(items.fold<int>(0, (int s, OrderItem it) => s + it.quantity)),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: pt - 0.5),
                  ),
                ))
              else if (showPrice && i == columns - 1)
                body(pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    Fmt.money(
                        items.fold<double>(0, (double s, OrderItem it) => s + it.subtotal),
                        symbol: currency),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: pt - 0.5),
                  ),
                ))
              else
                body(pw.SizedBox.shrink()),
          ],
        ),
      ],
    );
  }

  static pw.Widget _pad(pw.Widget child) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: child,
      );

  static pw.Widget _name(OrderItem item, double cell) => pw.Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: pw.WrapCrossAlignment.center,
        children: <pw.Widget>[
          pw.Text(item.productName, style: pw.TextStyle(fontSize: cell)),
          if ((item.categoryName ?? '').isNotEmpty) _categoryBadge(item.categoryName!, cell),
        ],
      );

  /// SKU 与名称**同字号同墨色**：这一格以前是 cell-0.5 + #555，比名称小半号还发灰，
  /// 而单据上最难认的恰好是拣货要照着找货的那个码。字号与 `ProductIdentity` 手工对账
  /// （PDF 用不了那个组件），改那边的档位必须同时改这里。
  ///
  /// 网页端这一格是 ui-monospace；客户端只随包带 Noto Sans / Noto Sans SC 两套字形，
  /// 没有等宽字体，所以靠加粗与同墨色把码读重，不额外塞一份字体进 APK。
  ///
  /// 名称列被关掉时，类目徽章跟着搬到这一格（否则整张单据看不到类目）。
  static pw.Widget _sku(OrderItem item, double cell, {bool withCategory = false}) => pw.Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: pw.WrapCrossAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            item.productSku,
            style: pw.TextStyle(
              fontSize: cell,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          if (withCategory && (item.categoryName ?? '').isNotEmpty)
            _categoryBadge(item.categoryName!, cell),
        ],
      );

  static pw.Widget _categoryBadge(String category, double cell) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: pw.BoxDecoration(
          color: _headBg,
          border: pw.Border.all(color: _badgeLine, width: 0.6),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(
          category,
          style: pw.TextStyle(fontSize: cell - 1.5),
        ),
      );

  static pw.Widget _image(
    OrderItem item,
    double imgMm,
    Map<String, pw.MemoryImage> images,
  ) {
    final pw.MemoryImage? image = images[item.imageUrl ?? ''];
    if (image == null) return pw.SizedBox.shrink();
    final double side = PdfPageFormat.mm * imgMm;
    return pw.Center(
      child: pw.ClipRRect(
        horizontalRadius: 3,
        verticalRadius: 3,
        child: pw.Image(image, width: side, height: side, fit: pw.BoxFit.cover),
      ),
    );
  }

  static String _boxLine(L10n l10n, OrderItem item) {
    final int perBox = item.unitsPerBox ?? 0;
    final int loose = item.quantity - item.boxCount * perBox;
    final String line = l10n.sheetBoxLine(boxes: item.boxCount, perBox: perBox);
    return loose > 0 ? '$line+$loose' : line;
  }

  static pw.Widget _notes(String notes, L10n l10n, double pt) => pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(
          color: _bandBg,
          border: const pw.Border(left: pw.BorderSide(width: 3, color: _accent)),
        ),
        child: pw.Text(
          '${l10n.sheetNotesPrefix}: $notes',
          style: pw.TextStyle(fontSize: pt - 1.5),
        ),
      );

  static pw.Widget _signatures(L10n l10n, double pt) => pw.Row(
        children: <pw.Widget>[
          pw.Expanded(child: _signBox(l10n.sheetSignHandler, pt)),
          pw.SizedBox(width: 18),
          pw.Expanded(child: _signBox(l10n.sheetSignCustomer, pt)),
        ],
      );

  static pw.Widget _signBox(String label, double pt) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 22),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 1, color: _faint)),
        ),
        child: pw.Center(
          child: pw.Text(label, style: pw.TextStyle(fontSize: pt - 1.5, color: _soft)),
        ),
      );

  /// 页脚每页都盖一次出单时间，多页单据翻到第二页也知道是哪一份。
  static pw.Widget _footer(PrintSettings settings, double pt, DateTime generatedAt) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1, color: _line, style: pw.BorderStyle.dashed),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                settings.footerText,
                style: pw.TextStyle(fontSize: pt - 2, color: _soft),
              ),
            ),
            pw.Text(
              Fmt.dateTime(generatedAt),
              style: pw.TextStyle(fontSize: pt - 2, color: _soft),
            ),
          ],
        ),
      );

  static Future<Map<String, pw.MemoryImage>> _loadImages(List<OrderItem> items) async {
    final Map<String, pw.MemoryImage> loaded = <String, pw.MemoryImage>{};
    for (final OrderItem item in items) {
      final String url = item.imageUrl ?? '';
      if (url.isEmpty || loaded.containsKey(url)) continue;
      final pw.MemoryImage? image = await _loadImage(url);
      if (image != null) loaded[url] = image;
    }
    return loaded;
  }

  /// 图片和 logo 都走公开 URL，拉不到就留空格：网页端同样是坏图不挡出单。
  static Future<pw.MemoryImage?> _loadImage(String url) async {
    try {
      final http.Response res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return pw.MemoryImage(res.bodyBytes);
    } on Object {
      return null;
    }
  }
}
