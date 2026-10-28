import 'dart:typed_data';

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
      final SheetParse parse = parseXlsxBytes(buildImportTemplateXlsx(withBox: false));
      expect(parse.ok, isTrue);
      expect(parse.rows.length, 1);
      expect(parse.rows.first.quantity, 100);
      expect(parse.rows.first.perBox, isNull);
    });

    test('payload 按服务端认的形状出字段', () {
      final SheetRow row = parseXlsxBytes(buildImportTemplateXlsx(withBox: true)).rows.first;
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
      expect(parseXlsxBytes(_renameHeader(bytes, 'SKU', '编号')).failure, SheetFailure.missingColumns);
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
}

/// 改一个表头字面量，重写出同一张 xlsx —— 用来验证缺列这条判定真的在表头上起作用。
Uint8List _renameHeader(Uint8List source, String from, String to) {
  // 直接重建：第一行表头换掉 SKU 那一格。
  final Excel excel = Excel.decodeBytes(source);
  final String sheet = excel.tables.keys.first;
  excel.updateCell(sheet, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0), TextCellValue(to));
  return Uint8List.fromList(excel.save(fileName: 'x.xlsx')!);
}
