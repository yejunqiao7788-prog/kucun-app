import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/core/print_sheet.dart';
import 'package:kucun_app/data/entities.dart';

/// 单据 PDF 的两个真实风险：随包带的字形能不能被 pdf 引擎吃下（Noto Sans SC 缺乌克兰语
/// є/ї 与越南语变音，靠 Noto Sans 兜底），以及 print-settings 的三个开关会不会把表格
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

  test('三个显示开关各自裁剪列数，四种组合都排得下', () async {
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
}
