import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/data/entities.dart';

/// 端点把行放在资源名底下（而不是 `data`/`items`），`Paged.of` 漏认就整屏恒空且不报错。
/// 这两支的载荷形状照 `getOperationLogs` 与 `listAllChannelPayments` 的 return 抄。
void main() {
  test('dashboard/logs 的 {logs:[…]} 能读出行', () {
    final Paged<OperationLog> page = Paged.of<OperationLog>(
      <String, Object?>{
        'logs': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'l1',
            'operation_type': 'UPDATE',
            'table_name': 'products',
            'user_name': 'yejunqiao888',
            'details': <String, Object?>{
              'sku': '6666',
              'changes': <String, Object?>{
                'quantity': <String, Object?>{'from': 4, 'to': 539},
              },
            },
            'created_at': '2026-10-28T17:30:09.000Z',
          },
          <String, Object?>{
            'id': 'l2',
            'operation_type': 'DELETE',
            'table_name': 'products',
            'details': <String, Object?>{'kind': 'retention_cleanup'},
            'created_at': '2026-10-28T20:38:21.000Z',
          },
        ],
      },
      OperationLog.new,
    );

    expect(page.rows, hasLength(2));
    expect(page.rows.first.actor, 'yejunqiao888');
    expect(page.rows.first.changes.single.to, '539');
    // 不分页的端点不该假装还有下一页。
    expect(page.hasMore, isFalse);
  });

  test('payments 的 {payments:[…]} 能读出行', () {
    final Paged<PaymentRecord> page = Paged.of<PaymentRecord>(
      <String, Object?>{
        'payments': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'p1',
            'provider': 'monobank',
            'status': 'succeeded',
            'amount': 19.9,
            'created_at': '2026-10-27T10:00:00.000Z',
          },
        ],
      },
      PaymentRecord.new,
    );

    expect(page.rows, hasLength(1));
    expect(page.hasMore, isFalse);
  });

  test('真正的分页出参仍走 data，不被资源名键抢掉', () {
    final Paged<OperationLog> page = Paged.of<OperationLog>(
      <String, Object?>{
        'data': <Map<String, Object?>>[<String, Object?>{'id': 'a'}],
        'logs': <Map<String, Object?>>[<String, Object?>{'id': 'b'}],
        'count': 57,
        'page': 1,
        'pageSize': 24,
        'totalPages': 3,
      },
      OperationLog.new,
    );

    expect(page.rows.single.id, 'a');
    expect(page.hasMore, isTrue);
  });
}
