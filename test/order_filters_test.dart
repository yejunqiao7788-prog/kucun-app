import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/screens/orders/orders_screen.dart';

void main() {
  test('「全部」就是把该维度落回 null，不是保持原值', () {
    const OrderFilters pending = OrderFilters(status: 'pending');
    expect(pending.withStatus(null).status, isNull);
    expect(pending.withStatus('completed').status, 'completed');

    const OrderFilters searched = OrderFilters(search: '阿胶');
    expect(searched.withSearch(null).search, isNull);
    expect(searched.withSearch('党参').search, '党参');
  });

  test('改状态不能顺手动别的维度', () {
    const OrderFilters base = OrderFilters(
      search: '阿胶',
      type: 'inbound',
      paymentStatus: 'unpaid',
      dateFrom: '2026-01-01',
      dateTo: '2026-01-31',
    );
    final OrderFilters next = base.withStatus('completed');
    expect(next.status, 'completed');
    expect(next.search, '阿胶');
    expect(next.type, 'inbound');
    expect(next.paymentStatus, 'unpaid');
    expect(next.dateFrom, '2026-01-01');
    expect(next.dateTo, '2026-01-31');
  });

  test('抽屉一次提交类型与付款状态，另一维保持当前值', () {
    const OrderFilters base = OrderFilters(status: 'pending', type: 'inbound');
    final OrderFilters next = base.replaced(type: null, paymentStatus: 'paid');
    expect(next.type, isNull);
    expect(next.paymentStatus, 'paid');
    expect(next.status, 'pending');
    expect(next.dirty, isTrue);

    // 类型与付款都回「全部」，dirty 必须跟着落回 false，否则筛选键一直高亮。
    expect(
      const OrderFilters(type: 'outbound', paymentStatus: 'paid')
          .replaced(type: null, paymentStatus: null)
          .dirty,
      isFalse,
    );
  });
}
