import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/core/print_sheet.dart';
import 'package:kucun_app/data/entities.dart';

/// 单据 PDF 的两个真实风险：随包带的字形能不能被 pdf 引擎吃下（Noto Sans SC 缺乌克兰语
/// є/ї 与越南语变音，靠 Noto Sans 兜底），以及 print-settings 的四个开关会不会把表格
/// 列数配崩。这里都不连网、不进设备。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Order order = Order(<String, Object?>{
    'id': 'o-1',
    'order_number': 'OUT-2026-0007',
    'type': 'outbound',
    'order_date': '2026-10-28',
    'customer_name': '张家口同仁堂',
    'customer_phone': '13800000000',
    'notes': '本周三前发货',
    'items': <Map<String, Object?>>[
      <String, Object?>{
        'product_name': '阿胶糕（核桃红枣）',
        'product_sku': 'AJ-001',
        'category_name': '阿胶制品',
        'quantity': 26,
        'box_count': 2,
        'units_per_box': 12,
        'unit_price': 180,
        'subtotal': 4680,
      },
      <String, Object?>{
        'product_name': '西洋参片',
        'product_sku': 'XY-014',
        'quantity': 5,
        'box_count': 0,
        'units_per_box': 1,
        'unit_price': 96.5,
        'subtotal': 482.5,
      },
    ],
  });

  Future<Uint8List> render(PrintSettings settings, L10n l10n) => OrderSheet.build(
        order: order,
        settings: settings,
        l10n: l10n,
        currencySymbol: '¥',
        generatedAt: DateTime.parse('2026-10-28T15:30:00'),
      );

  test('字形随包发布，中文单据能出 PDF', () async {
    for (final String asset in <String>[
      'assets/fonts/NotoSansSC-Regular.ttf', // 汉字兜底
      'assets/fonts/NotoSans-Regular.ttf', // є/ї 与越南语变音只有这份有
      'assets/fonts/NotoSans-Bold.ttf',
    ]) {
      final ByteData data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(100000), reason: asset);
    }

    final Uint8List pdf = await render(PrintSettings.defaults, L10n('zh'));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    // 明细两行 + 合计 + 抬头，页面必然不止一个对象；只挡「空文档」这一类回归。
    expect(pdf.lengthInBytes, greaterThan(4000));
  });

  test('价格/SKU/图片三个开关各自裁剪列数（名称开着），四种组合都排得下', () async {
    for (final String lang in <String>['zh', 'en', 'uk', 'vi']) {
      final L10n l10n = L10n(lang);
      for (final PrintSettings settings in <PrintSettings>[
        const PrintSettings(<String, Object?>{
          'template_id': 'compact',
          'show_price': true,
          'show_sku': true,
          'show_image': false,
        }),
        const PrintSettings(<String, Object?>{
          'template_id': 'standard',
          'show_price': false,
          'show_sku': false,
          'show_image': false,
        }),
        const PrintSettings(<String, Object?>{
          'template_id': 'standard',
          'show_price': true,
          'show_sku': false,
          'show_image': false,
        }),
        const PrintSettings(<String, Object?>{
          'template_id': 'compact',
          'show_price': false,
          'show_sku': true,
          'show_image': false,
        }),
      ]) {
        final Uint8List pdf = await render(settings, l10n);
        expect(pdf.lengthInBytes, greaterThan(4000), reason: '$lang / ${settings.json}');
      }
    }
  });

  test('没有明细也不塌，出的是带表头的空单', () async {
    const Order empty = Order(<String, Object?>{
      'order_number': 'IN-2026-0001',
      'type': 'inbound',
      'order_date': '2026-10-28',
      'items': <Object?>[],
    });
    final Uint8List pdf = await OrderSheet.build(
      order: empty,
      settings: PrintSettings.defaults,
      l10n: L10n('zh'),
      currencySymbol: '¥',
      generatedAt: DateTime.parse('2026-10-28T15:30:00'),
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  /// 四个开关 = 16 种列组合。pdf 的 TableRow 没有 colspan，合计行与空行都按同一份列数
  /// 逐格补齐，所以这里逐格对账：列数、合计标签格、数量格，三者不许重合或越界。
  group('SheetLayout 16 种开关组合', () {
    for (final bool name in <bool>[true, false]) {
      for (final bool sku in <bool>[true, false]) {
        for (final bool price in <bool>[true, false]) {
          for (final bool image in <bool>[true, false]) {
            final String label = 'name=$name sku=$sku price=$price image=$image';
            test(label, () {
              final SheetLayout layout = SheetLayout(
                showImage: image,
                showName: name,
                showSku: sku,
                showPrice: price,
                imgMm: 16,
              );
              expect(
                layout.count,
                2 + (name ? 1 : 0) + (sku ? 1 : 0) + (image ? 1 : 0) + (price ? 2 : 0),
                reason: label,
              );
              expect(layout.labelAt, inInclusiveRange(0, layout.count - 1));
              expect(layout.qtyAt, inInclusiveRange(0, layout.count - 1));
              // 合计标签与总数量落在同一格 = 数量被「合计」两个字盖掉。
              expect(layout.labelAt, isNot(layout.qtyAt), reason: label);
              if (name) {
                expect(layout.labelAt, layout.nameAt);
              } else if (sku) {
                expect(layout.labelAt, layout.skuAt);
              } else {
                expect(layout.labelAt, 0, reason: '两个都关时退到序号列');
              }
              if (sku) {
                // 名称列关掉后，码这一格接管腾出来的宽度，不再是固定 92。
                expect(
                  layout.columns[layout.skuAt],
                  name ? isA<pw.FixedColumnWidth>() : isA<pw.FlexColumnWidth>(),
                  reason: label,
                );
              }
            });
          }
        }
      }
    }
  });

  test('关掉名称：单据照样出得来，四种语言 × 两种模板都不塌', () async {
    for (final String lang in <String>['zh', 'en', 'uk', 'vi']) {
      for (final String template in <String>['standard', 'compact']) {
        final Uint8List pdf = await render(
          PrintSettings(<String, Object?>{
            'template_id': template,
            'show_price': true,
            'show_sku': true,
            'show_image': false,
            'show_product_name': false,
          }),
          L10n(lang),
        );
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: '$lang / $template');
        expect(pdf.lengthInBytes, greaterThan(4000), reason: '$lang / $template');
      }
    }
  });

  test('名称开关默认 true：服务端没给这一列时不能把名称藏起来', () {
    expect(PrintSettings.defaults.showProductName, isTrue);
    expect(const PrintSettings(<String, Object?>{}).showProductName, isTrue);
    expect(
      const PrintSettings(<String, Object?>{'show_product_name': false}).showProductName,
      isFalse,
    );
    // 整行 upsert 的白名单必须带上它，否则保存一次就把租户的选择冲掉。
    expect(PrintSettings.defaults.toPayload().containsKey('show_product_name'), isTrue);
    expect(
      PrintSettings.defaults.copyWith(showProductName: false).toPayload()['show_product_name'],
      isFalse,
    );
  });
}
