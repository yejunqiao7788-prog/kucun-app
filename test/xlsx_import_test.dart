import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/data/product_sheet.dart';

void main() {
  group('导入模板下载 → 再读回来', () {
    test('标准模板：11 列，库存总数 = 箱数 × 箱规 + 散装数', () {
      final Uint8List bytes = buildImportTemplateXlsx(withBox: true);
      expect(bytes, isNotEmpty);

      final SheetParse parse = parseXlsxBytes(bytes);
      expect(parse.ok, isTrue);
      expect(parse.rows.length, 2);

      final SheetRow boxed = parse.rows.first;
      expect(boxed.name, '示例商品（整箱+散装）');
      expect(boxed.sku, 'EXAMPLE-001');
      expect(boxed.category, '办公用品');
      expect(boxed.price, 99);
      expect(boxed.cost, 50);
      expect(boxed.perBox, 12);
      expect(boxed.boxPrice, 1100);
      expect(boxed.quantity, 68);
      expect(boxed.minStock, 10);
      expect(boxed.location, '仓库A');

      // 箱规留空的那一行：整箱价跟着一起作废，数量就是散装数。
      final SheetRow loose = parse.rows.last;
      expect(loose.sku, 'EXAMPLE-002');
      expect(loose.perBox, isNull);
      expect(loose.boxPrice, isNull);
      expect(loose.quantity, 100);
    });

    test('简版模板：8 列，只有纯数量', () {
      final SheetParse parse =
          parseXlsxBytes(buildImportTemplateXlsx(withBox: false));
      expect(parse.ok, isTrue);
      expect(parse.rows.length, 1);
      expect(parse.rows.first.quantity, 100);
      expect(parse.rows.first.perBox, isNull);
    });

    test('payload 按服务端认的形状出字段', () {
      final SheetRow row =
          parseXlsxBytes(buildImportTemplateXlsx(withBox: true)).rows.first;
      final Map<String, Object?> payload = row.payload('tenant-1');
      expect(payload['tenant_id'], 'tenant-1');
      expect(payload['units_per_box'], 12);
      expect(payload['unit'], '个');
      expect(payload['quantity'], 68);
    });

    test('表头缺 SKU 就报缺列，和网页端一样', () {
      final Uint8List bytes = buildImportTemplateXlsx(withBox: false);
      final SheetParse parse = parseXlsxBytes(bytes);
      expect(parse.rows, isNotEmpty);
      // 把名称/SKU 两列换成认不出的字面，等价于商户自己改了表头。
      expect(parseXlsxBytes(_renameHeader(bytes, 'SKU', '编号')).failure,
          SheetFailure.missingColumns);
    });
  });

  group('粘贴通道', () {
    test('制表符分隔、表头自动对上字段', () {
      final SheetParse parse = parsePastedText(
        'SKU\t商品名称\t库存数量\t售价\n'
        'A-1\t螺丝\t20\t3.5\n'
        '\t空行不算\t\t\n',
      );
      expect(parse.rows.length, 1);
      expect(parse.rows.first.sku, 'A-1');
      expect(parse.rows.first.price, 3.5);
      expect(parse.dropped.length, 1);
    });
  });

  group('商户真实形状的 xlsx', () {
    test('内置会计格式（numFmtId 41）不再让整张表读成「格式不正确」', () {
      final SheetParse parse = parseXlsxBytes(_accountingXlsx());
      expect(parse.failure, isNull, reason: '样式里的 ￥ 格式一度会抛异常，被吞成 corrupt');
      expect(parse.rows.length, 4);
      expect(parse.dropped, isEmpty);
    });

    test('空着不写的单元格按 r="I2" 对齐，价格列不会串到成本列', () {
      final SheetParse parse = parseXlsxBytes(_accountingXlsx());
      // 第 2 行：价格、成本、箱规那几格在 XML 里根本不存在，散装数在 I 列。
      final SheetRow emptyPrice = parse.rows.first;
      expect(emptyPrice.name, '9号库');
      expect(emptyPrice.sku, '25662');
      expect(emptyPrice.category, '1月30号柜');
      expect(emptyPrice.price, 0);
      expect(emptyPrice.cost, 0);
      expect(emptyPrice.perBox, isNull);
      expect(emptyPrice.quantity, 5);
      expect(emptyPrice.minStock, 1);
      expect(emptyPrice.location, '9号库1-2');
    });

    test('箱规 > 1 才算整箱，= 1 时整箱价一起作废（网页端同规则）', () {
      final SheetParse parse = parseXlsxBytes(_accountingXlsx());
      final SheetRow boxed = parse.rows[1];
      expect(boxed.perBox, 12);
      expect(boxed.boxPrice, 130);
      // 5 箱 × 12 + 散装 3
      expect(boxed.quantity, 63);

      final SheetRow onePerBox = parse.rows[2];
      expect(onePerBox.perBox, isNull);
      expect(onePerBox.boxPrice, isNull);
      expect(onePerBox.quantity, 4);
    });

    test('文件内重复的 SKU 在预览阶段就挑出来', () {
      final SheetParse parse = parseXlsxBytes(_accountingXlsx());
      expect(parse.duplicateSkus, <String>['206']);
      // 最后一行才是那个重复 SKU：其余字段照常读，只是提前告诉商户会被拒。
      final SheetRow priced = parse.rows.last;
      expect(priced.name, '螺丝');
      expect(priced.sku, '206');
      expect(priced.price, 12.5);
      expect(priced.quantity, 7);
      expect(priced.location, isEmpty);
      expect(
          parseXlsxBytes(buildImportTemplateXlsx(withBox: true)).duplicateSkus,
          isEmpty);
    });
  });
}

/// 改一个表头字面量，重写出同一张 xlsx —— 用来验证缺列这条判定真的在表头上起作用。
Uint8List _renameHeader(Uint8List source, String from, String to) {
  // 直接重建：第一行表头换掉 SKU 那一格。
  final Excel excel = Excel.decodeBytes(source);
  final String sheet = excel.tables.keys.first;
  excel.updateCell(
      sheet,
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
      TextCellValue(to));
  return Uint8List.fromList(excel.save(fileName: 'x.xlsx')!);
}

/// 手工拼一份 xlsx，形状照着商户那份来：
/// 样式里声明内置会计格式 41/43（Excel 与 WPS 在中文环境都会写），
/// 空单元格一个都不写，列位只由 `r` 引用决定。package:excel 4.0.6 解析这种
/// styles.xml 会直接抛 `Exception`，导入因此报「文件为空或格式不正确」。
Uint8List _accountingXlsx() {
  const List<String> strings = <String>[
    '商品名称',
    'SKU',
    '分类',
    '价格',
    '成本',
    '箱规(个/箱)',
    '整箱价',
    '库存箱数',
    '库存数量(散)',
    '预警库存',
    '仓库位置',
    '9号库',
    '1月30号柜',
    '9号库1-2',
    '螺丝',
  ];

  final String sheet = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1">${_headerCells()}
</row>
<row r="2"><c r="A2" t="s"><v>11</v></c><c r="B2"><v>25662</v></c><c r="C2" t="s"><v>12</v></c><c r="I2"><v>5</v></c><c r="J2"><v>1</v></c><c r="K2" t="s"><v>13</v></c></row>
<row r="3"><c r="A3" t="s"><v>11</v></c><c r="B3"><v>206</v></c><c r="C3" t="s"><v>12</v></c><c r="E3"><v>7</v></c><c r="F3"><v>12</v></c><c r="G3" s="1"><v>130</v></c><c r="H3"><v>5</v></c><c r="I3"><v>3</v></c><c r="J3"><v>1</v></c><c r="K3" t="s"><v>13</v></c></row>
<row r="4"><c r="A4" t="s"><v>11</v></c><c r="B4"><v>777</v></c><c r="F4"><v>1</v></c><c r="G4"><v>50</v></c><c r="H4"><v>2</v></c><c r="I4"><v>4</v></c></row>
<row r="5"><c r="A5" t="s"><v>14</v></c><c r="B5"><v>206</v></c><c r="D5" s="1"><v>12.5</v></c><c r="I5"><v>7</v></c><c r="J5"><v>2</v></c></row>
</sheetData></worksheet>''';

  return _buildXlsx(<String, String>{
    '[Content_Types].xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>''',
    '_rels/.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
    'xl/workbook.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="1月30号柜" sheetId="1" r:id="rId1"/></sheets></workbook>''',
    'xl/_rels/workbook.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>''',
    'xl/styles.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="41" formatCode="_(&quot;¥&quot;)_ * #,##0.00_-;_(&quot;¥&quot;)_ * -#,##0.00_-;_(&quot;¥&quot;)_ * &quot;-&quot;??-;_@_-"/><numFmt numFmtId="43" formatCode="_(&quot;£&quot;)_ * #,##0.00_-;_(&quot;£&quot;)_ * -#,##0.00_-;_(&quot;£&quot;)_ * &quot;-&quot;??-;_@_-"/></numFmts><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" xfId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" xfId="0"/><xf numFmtId="41" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>''',
    'xl/sharedStrings.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${strings.length}" uniqueCount="${strings.length}">${strings.map((String s) => '<si><t>$s</t></si>').join()}</sst>''',
    'xl/worksheets/sheet1.xml': sheet,
  });
}

String _headerCells() => List<String>.generate(
      11,
      (int i) => '<c r="${String.fromCharCode(65 + i)}1" t="s"><v>$i</v></c>',
    ).join();

Uint8List _buildXlsx(Map<String, String> parts) {
  final Archive archive = Archive();
  parts.forEach((String name, String xml) {
    final List<int> bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive) as List<int>);
}
