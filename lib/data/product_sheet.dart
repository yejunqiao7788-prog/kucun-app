import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

// 商品表格导入的解析与模板生成。
//
// 列名识别、箱规校验、库存合计三条规则逐条对齐原项目 `dataImportExport.ts`
// （`detectColumnKey` / `parseImportFile` / `downloadImportTemplate`），
// 因为商户手里那份模板是从网页端下载的 —— 同一张表在 App 里必须读出同一批行。
// 校验交给服务端：这里只保证「认得出的列按生产规则填进字段」。

/// 一行待导入的商品。字段名与 `/products/import` 认的形状一致。
class SheetRow {
  const SheetRow({
    required this.sku,
    required this.name,
    required this.category,
    required this.price,
    required this.cost,
    required this.unit,
    required this.perBox,
    required this.boxPrice,
    required this.quantity,
    required this.minStock,
    required this.location,
  });

  final String sku;
  final String name;
  final String category;
  final double price;
  final double cost;
  final String unit;
  final int? perBox;
  final double? boxPrice;
  final int quantity;
  final int minStock;
  final String location;

  /// `unit` 与 `max_stock` 用原项目的默认值；空类目回 `null` 而不是空串，否则平台侧筛不到。
  Map<String, Object?> payload(String tenantId) => <String, Object?>{
        'tenant_id': tenantId,
        'sku': sku,
        'name': name,
        'category': category.isEmpty ? null : category,
        'price': price,
        'cost': cost,
        'unit': unit.isEmpty ? '个' : unit,
        'units_per_box': perBox,
        'box_price': boxPrice,
        'quantity': quantity,
        'min_stock': minStock,
        'max_stock': 500,
        'location': location,
      };
}

/// 解析失败的原因，由界面翻成文案（数据层不碰 l10n）。
enum SheetFailure { corrupt, missingColumns, noRows }

class SheetParse {
  const SheetParse(this.rows, this.dropped) : failure = null;
  const SheetParse.failed(this.failure) : rows = const <SheetRow>[], dropped = const <String>[];

  final List<SheetRow> rows;

  /// 被丢掉的行（缺名称或缺 SKU），原文照抄，由界面取前几条当样本。
  final List<String> dropped;
  final SheetFailure? failure;

  bool get ok => failure == null;

  /// 文件内部重复的 SKU。服务端逐行走 saveProduct，那里有 SKU 唯一性检查，
  /// 所以同一份表里重复的那几行注定失败 —— 网页端在导入前就把它们挑出来，
  /// 这里提前一行到预览阶段，商户按「添加」之前就能看见。
  List<String> get duplicateSkus {
    final Map<String, int> seen = <String, int>{};
    for (final SheetRow row in rows) {
      seen[row.sku] = (seen[row.sku] ?? 0) + 1;
    }
    return seen.entries.where((MapEntry<String, int> e) => e.value > 1).map((MapEntry<String, int> e) => e.key).toList(growable: false);
  }
}

// ———————————————————————————— xlsx ————————————————————————————

/// 只有 OOXML（.xlsx）能在这儿被解出来 —— .xls 与 CSV 走粘贴通道。
SheetParse parseXlsxBytes(Uint8List bytes) {
  final List<List<String>> grid;
  try {
    grid = _firstSheetGrid(bytes);
  } on Object {
    return const SheetParse.failed(SheetFailure.corrupt);
  }
  if (grid.length < 2) return const SheetParse.failed(SheetFailure.corrupt);

  final Map<String, int> columns = _xlsxColumnsOf(grid.first);
  if (!columns.containsKey('name') || !columns.containsKey('sku')) {
    return const SheetParse.failed(SheetFailure.missingColumns);
  }

  final List<SheetRow> rows = <SheetRow>[];
  final List<String> dropped = <String>[];
  for (final List<String> cells in grid.skip(1)) {
    final SheetRow? row = _rowFrom(cells, columns);
    if (row == null) {
      if (cells.any((String cell) => cell.isNotEmpty)) dropped.add(cells.where((String cell) => cell.isNotEmpty).join(' · '));
      continue;
    }
    rows.add(row);
  }
  if (rows.isEmpty) return const SheetParse.failed(SheetFailure.noRows);
  return SheetParse(rows, dropped);
}

/// xlsx 的第一张表 → 文本网格。
///
/// 不用 package:excel 读：它解析 styles.xml 时对任何 `numFmtId < 164` 的声明直接抛
/// `Exception`，而 Excel/WPS 会把内置会计格式（41–44，中文环境就是那几套带 ￥ 的）
/// 原样写进 `<numFmts>`。于是商户手里最常见的表在 App 里变成「文件为空或格式不正确」，
/// 而网页端用 SheetJS，同一张表照读不误。导入只关心单元格的值，样式一律不看，
/// 所以这里自己拆 zip 读 sheet XML；生成模板仍然走 package:excel。
List<List<String>> _firstSheetGrid(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final List<String> shared = _sharedStrings(_zipText(archive, 'xl/sharedStrings.xml'));
  final String? sheetXml = _zipText(archive, _firstSheetPath(archive));
  if (sheetXml == null) throw const FormatException('xlsx 里没有工作表');
  return _sheetGrid(sheetXml, shared);
}

String? _zipText(Archive archive, String name) {
  final ArchiveFile? file = archive.findFile(name);
  if (file == null || !file.isFile) return null;
  final Object? content = file.content;
  if (content is! List<int>) return null;
  return utf8.decode(content, allowMalformed: true);
}

/// 表名随商户自己改的文件走，所以按 workbook 里第一张表的顺序找文件，不猜文件名。
String _firstSheetPath(Archive archive) {
  const String fallback = 'xl/worksheets/sheet1.xml';
  final String? workbook = _zipText(archive, 'xl/workbook.xml');
  final String? rels = _zipText(archive, 'xl/_rels/workbook.xml.rels');
  if (workbook == null || rels == null) return fallback;
  final XmlElement? sheets = _child(
    XmlDocument.parse(workbook).rootElement,
    'sheets',
  );
  if (sheets == null || sheets.findElements('sheet').isEmpty) return fallback;
  final XmlElement first = sheets.findElements('sheet').first;
  final String? rid = first.getAttribute('r:id') ?? first.getAttribute('id');
  if (rid == null) return fallback;
  final Iterable<XmlElement> matches = XmlDocument.parse(rels)
      .rootElement
      .findElements('Relationship')
      .where((XmlElement e) => e.getAttribute('Id') == rid);
  if (matches.isEmpty) return fallback;
  final String target = matches.first.getAttribute('Target') ?? 'worksheets/sheet1.xml';
  if (target.startsWith('/')) return target.substring(1);
  return target.startsWith('xl/') ? target : 'xl/$target';
}

List<String> _sharedStrings(String? xmlText) {
  if (xmlText == null) return const <String>[];
  return XmlDocument.parse(xmlText)
      .rootElement
      .findElements('si')
      .map((XmlElement si) => _textOf(si))
      .toList(growable: false);
}

List<List<String>> _sheetGrid(String sheetXml, List<String> shared) {
  final XmlElement? data = _child(XmlDocument.parse(sheetXml).rootElement, 'sheetData');
  if (data == null) return const <List<String>>[];
  final List<List<String>> grid = <List<String>>[];
  for (final XmlElement row in data.findElements('row')) {
    final List<String> cells = <String>[];
    for (final XmlElement cell in row.findElements('c')) {
      // 空单元格在 xlsx 里根本不写，所以列位必须按 `r="D3"` 这种引用对齐，
      // 不能按出现顺序数 —— 否则商户留空的价格列会把成本拽进价格字段。
      final String? ref = cell.getAttribute('r');
      final int at = ref == null ? cells.length : _columnIndexOf(ref);
      while (cells.length < at) {
        cells.add('');
      }
      cells.add(_cellText(cell, shared));
    }
    grid.add(cells);
  }
  return grid;
}

String _cellText(XmlElement cell, List<String> shared) {
  final String type = cell.getAttribute('t') ?? 'n';
  if (type == 'inlineStr') {
    final XmlElement? inline = _child(cell, 'is');
    return inline == null ? '' : _textOf(inline).trim();
  }
  final XmlElement? value = _child(cell, 'v');
  if (value == null) return '';
  final String raw = value.innerText.trim();
  if (type == 's') {
    final int? index = int.tryParse(raw);
    if (index == null || index < 0 || index >= shared.length) return raw;
    return shared[index].trim();
  }
  if (type == 'b') return raw == '1' ? 'true' : 'false';
  return raw;
}

int _columnIndexOf(String ref) {
  int index = 0;
  for (final int unit in ref.codeUnits) {
    if (unit < 65 || unit > 122) break;
    final int letter = (unit & 0x5F) - 64;
    if (letter < 1 || letter > 26) break;
    index = index * 26 + letter;
  }
  return index == 0 ? 0 : index - 1;
}

XmlElement? _child(XmlElement node, String name) {
  for (final XmlNode child in node.children) {
    if (child is XmlElement && child.name.local == name) return child;
  }
  return null;
}

/// `<si>` 的正文：直挂的 `<t>` 与富文本 run 都要拼，`<rPh>` 里的注音串不算正文。
String _textOf(XmlElement node) {
  final StringBuffer buf = StringBuffer();
  for (final XmlElement t in node.findElements('t')) {
    buf.write(t.innerText);
  }
  for (final XmlElement r in node.findElements('r')) {
    for (final XmlElement t in r.findElements('t')) {
      buf.write(t.innerText);
    }
  }
  return buf.toString();
}

/// 列名 → 字段，顺序敏感：箱规/整箱价/箱数必须排在价格与数量之前，
/// 否则「库存箱数」会被泛化的「数量」先抢走。
String? _columnKeyOf(String header) {
  if (header.isEmpty) return null;
  final String h = header.toLowerCase();
  if (header.contains('名称') || h.contains('name')) return 'name';
  if (h.contains('sku')) return 'sku';
  if (header.contains('分类') || h.contains('category')) return 'category';
  if (header.contains('箱规') ||
      h.contains('units per box') ||
      h.contains('units_per_box') ||
      h.contains('per box')) {
    return 'units_per_box';
  }
  if (header.contains('整箱价') || h.contains('box price') || h.contains('box_price')) return 'box_price';
  if (header.contains('箱数') || h.contains('box qty') || h.contains('boxes')) return 'box_quantity';
  if (header.contains('成本') || h.contains('cost')) return 'cost';
  if (header.contains('预警') || h.contains('min')) return 'min_stock';
  if (header.contains('价格') || h.contains('price')) return 'price';
  if (header.contains('数量') || h.contains('stock') || h.contains('quantity')) return 'quantity';
  if (header.contains('位置') || h.contains('location')) return 'location';
  return null;
}

Map<String, int> _xlsxColumnsOf(List<String> headers) {
  final Map<String, int> out = <String, int>{};
  for (int i = 0; i < headers.length; i++) {
    final String? key = _columnKeyOf(headers[i]);
    if (key != null) out.putIfAbsent(key, () => i);
  }
  return out;
}

/// 一行 → 商品；缺名称或 SKU 返回 null（原项目同样按行丢弃，不报错）。
SheetRow? _rowFrom(List<String> cells, Map<String, int> columns) {
  String pick(String key) {
    final int? index = columns[key];
    if (index == null || index >= cells.length) return '';
    return cells[index];
  }

  final String name = pick('name');
  final String sku = pick('sku');
  if (name.isEmpty || sku.isEmpty) return null;

  // 箱规必须 > 1 才算支持整箱（网页端 `upb <= 1` 就删），且整箱价跟着一起作废。
  int? perBox = _positiveInt(pick('units_per_box'));
  if (perBox != null && perBox <= 1) perBox = null;
  double? boxPrice = pick('box_price').isEmpty ? null : _decimal(pick('box_price'));
  if (perBox == null) boxPrice = null;

  int quantity = _decimal(pick('quantity')).round();
  final int boxQuantity = _positiveInt(pick('box_quantity')) ?? 0;
  if (perBox != null && boxQuantity > 0) quantity = boxQuantity * perBox + quantity;

  return SheetRow(
    sku: sku,
    name: name,
    category: pick('category'),
    price: _decimal(pick('price')),
    cost: _decimal(pick('cost')),
    unit: pick('unit'),
    perBox: perBox,
    boxPrice: boxPrice,
    quantity: quantity,
    minStock: pick('min_stock').isEmpty ? 10 : _decimal(pick('min_stock')).round(),
    location: pick('location'),
  );
}

// ———————————————————————————— 粘贴 ————————————————————————————

/// 表头别名 → 规范字段。剪贴板里的表头是四种语言、各种叫法，认不出的列直接丢；
/// 一行都对不上字段时按 [_pastePositional] 的位置回退。
const Map<String, List<String>> _pasteAliases = <String, List<String>>{
  'sku': <String>['sku', 'артикул', 'code', '货号', '编码', '商品编码', '商品货号'],
  'name': <String>['name', 'title', '品名', '名称', '商品名称', '描述'],
  'category': <String>['category', '分类', '类目', '品类'],
  'price': <String>['price', '售价', '价格', '单价'],
  'cost': <String>['cost', '成本', '成本价'],
  'quantity': <String>['quantity', 'qty', 'stock', '数量', '库存', '现存'],
  'min_stock': <String>['min_stock', 'min', '最低库存', '安全库存', '预警值'],
  'units_per_box': <String>['units_per_box', 'per_box', '每箱', '每箱数量', '箱规'],
  'box_price': <String>['box_price', '箱价', '整箱价'],
  'location': <String>['location', '库位', '位置', '货位'],
  'unit': <String>['unit', '单位'],
};

const List<String> _pastePositional = <String>[
  'sku',
  'name',
  'category',
  'price',
  'cost',
  'quantity',
  'min_stock',
  'location',
];

/// 从 Excel/WPS 复制过来的区域：制表符分隔优先，否则按带引号的逗号切。
SheetParse parsePastedText(String text) {
  final List<String> lines = text
      .split(RegExp(r'\r\n|\r|\n'))
      .where((String line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const SheetParse(<SheetRow>[], <String>[]);

  final List<List<String>> table = lines.map(_splitLine).toList(growable: false);
  final Map<String, int> columns = _pasteHeaderOf(table.first);
  final List<List<String>> body = columns.isEmpty ? table : table.skip(1).toList(growable: false);

  final List<SheetRow> rows = <SheetRow>[];
  final List<String> dropped = <String>[];
  for (final List<String> cells in body) {
    String pick(String key) {
      int? index;
      if (columns.isEmpty) {
        final int pos = _pastePositional.indexOf(key);
        index = pos >= 0 && pos < cells.length ? pos : null;
      } else {
        index = columns[key];
      }
      if (index == null || index >= cells.length) return '';
      return cells[index].trim();
    }

    final String sku = pick('sku');
    final String name = pick('name');
    if (sku.isEmpty || name.isEmpty) {
      dropped.add(cells.join(' · ').trim());
      continue;
    }
    rows.add(
      SheetRow(
        sku: sku,
        name: name,
        category: pick('category'),
        price: _decimal(pick('price')),
        cost: _decimal(pick('cost')),
        unit: pick('unit'),
        perBox: _positiveInt(pick('units_per_box')),
        boxPrice: pick('box_price').isEmpty ? null : _decimal(pick('box_price')),
        quantity: _decimal(pick('quantity')).round(),
        minStock: pick('min_stock').isEmpty ? 10 : _decimal(pick('min_stock')).round(),
        location: pick('location'),
      ),
    );
  }
  return SheetParse(rows, dropped);
}

Map<String, int> _pasteHeaderOf(List<String> cells) {
  final Map<String, int> out = <String, int>{};
  for (int i = 0; i < cells.length; i++) {
    final String key = cells[i].trim().toLowerCase().replaceAll(RegExp(r'[\s_\-·、（）()]'), '');
    for (final MapEntry<String, List<String>> entry in _pasteAliases.entries) {
      if (entry.value.contains(key)) {
        out.putIfAbsent(entry.key, () => i);
        break;
      }
    }
  }
  // 至少认出 SKU 或名称才算表头，否则整表按位置解析。
  return out.containsKey('sku') || out.containsKey('name') ? out : const <String, int>{};
}

List<String> _splitLine(String line) {
  if (line.contains('\t')) return line.split('\t');
  final List<String> out = <String>[];
  final StringBuffer buf = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < line.length; i++) {
    final String ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

// ———————————————————————————— 模板 ————————————————————————————

/// 两份模板与网页端逐列对齐：简版只有纯数量，标准版多箱规/整箱价/库存箱数/散装数四列。
Uint8List buildImportTemplateXlsx({required bool withBox}) {
  const String sheetName = '导入模板';
  final Excel excel = Excel.createExcel();
  excel.rename(excel.tables.keys.first, sheetName);
  excel.setDefaultSheet(sheetName);
  for (final List<Object?> line in withBox ? _standardTemplate : _simpleTemplate) {
    excel.appendRow(sheetName, line.map(_cellValue).toList(growable: false));
  }
  final List<int>? bytes = excel.save(fileName: withBox ? 'import_template.xlsx' : 'import_template_simple.xlsx');
  if (bytes == null) return Uint8List(0);
  return Uint8List.fromList(bytes);
}

CellValue? _cellValue(Object? value) {
  if (value == null || (value is String && value.isEmpty)) return null;
  if (value is int) return IntCellValue(value);
  if (value is double) return DoubleCellValue(value);
  if (value is bool) return BoolCellValue(value);
  return TextCellValue('$value');
}

const List<List<Object?>> _simpleTemplate = <List<Object?>>[
  <Object?>['商品名称', 'SKU', '分类', '价格', '成本', '库存数量', '预警库存', '仓库位置'],
  <Object?>['示例商品', 'EXAMPLE-001', '办公用品', 99, 50, 100, 10, '仓库A'],
];

const List<List<Object?>> _standardTemplate = <List<Object?>>[
  <Object?>['商品名称', 'SKU', '分类', '价格', '成本', '箱规(个/箱)', '整箱价', '库存箱数', '库存数量(散)', '预警库存', '仓库位置'],
  <Object?>['示例商品（整箱+散装）', 'EXAMPLE-001', '办公用品', 99, 50, 12, 1100, 5, 8, 10, '仓库A'],
  <Object?>['示例商品（仅散装）', 'EXAMPLE-002', '办公用品', 25, 12, '', '', '', 100, 10, '仓库A'],
];

// ———————————————————————————— 数字 ————————————————————————————

double _decimal(String raw) {
  final String cleaned = raw.replaceAll(RegExp(r'[^0-9.\-,]'), '');
  if (cleaned.isEmpty) return 0;
  if (cleaned.contains('.') && cleaned.contains(',')) {
    return double.tryParse(cleaned.replaceAll(',', '')) ?? 0;
  }
  if (cleaned.contains(',')) {
    final int lastComma = cleaned.lastIndexOf(',');
    final bool thousands = cleaned.length - lastComma - 1 == 3 && lastComma > 0;
    return double.tryParse(thousands ? cleaned.replaceAll(',', '') : cleaned.replaceAll(',', '.')) ?? 0;
  }
  return double.tryParse(cleaned) ?? 0;
}

int? _positiveInt(String raw) {
  if (raw.trim().isEmpty) return null;
  final int value = _decimal(raw).round();
  return value > 0 ? value : null;
}
