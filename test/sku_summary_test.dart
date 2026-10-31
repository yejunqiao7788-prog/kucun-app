import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/formatters.dart';
import 'package:kucun_app/data/entities.dart';

/// 备货清单的 SKU 摘要：服务端 `dashboard/orders` 交回的是未截断的去重清单，
/// 「显示前几个 + 还剩几项」只由 Fmt.skuSummary 裁决一次。
///
/// 注意口径范围：订单**列表**刻意不显示 SKU 摘要（租户端只要单号与客户），
/// 所以这一支的唯一展示面是首页的备货清单。
void main() {
  test('去重 + 去空白 + 丢掉空码，保持服务端给的顺序', () {
    expect(
      Fmt.skuSummary(<String?>['AJ-001', ' AJ-001 ', '', null, 'XY-014', '  ']),
      'AJ-001 · XY-014',
    );
  });

  test('超过三个折成 +N，而不是把整单几十个码铺满屏幕', () {
    expect(
      Fmt.skuSummary(<String>['A', 'B', 'C', 'D', 'E']),
      'A · B · C +2',
    );
    expect(Fmt.skuSummary(<String>['A', 'B', 'C']), 'A · B · C');
  });

  test('一个可用的码都没有时回空串：调用方据此整行不渲染，不印一个「—」', () {
    expect(Fmt.skuSummary(<String?>[]), '');
    expect(Fmt.skuSummary(<String?>[null, '', '   ']), '');
  });

  test('Order.skus 读的是服务端那一列，缺失时是空清单而不是 null', () {
    const Order withSkus = Order(<String, Object?>{
      'order_number': 'OUT-1',
      'skus': <String>['AJ-001', 'XY-014'],
    });
    expect(Fmt.skuSummary(withSkus.skus), 'AJ-001 · XY-014');

    const Order without = Order(<String, Object?>{'order_number': 'OUT-2'});
    expect(without.skus, isEmpty);
    expect(Fmt.skuSummary(without.skus), '');
  });
}