import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/core/log_labels.dart';
import 'package:kucun_app/data/entities.dart';

/// 载荷形状取自现网 `operation_logs` 的 `details` 原文（`getOperationLogs` 会补 `user_name`）。
void main() {
  const L10n zh = L10n('zh');

  test('两套键名的日志都能读出结构化字段', () {
    const OperationLog business = OperationLog(<String, Object?>{
      'username': '张伟',
      'action': 'UPDATE',
      'name': '阿胶糕',
      'sku': 'AJ001',
    });
    expect(business.actor, '张伟');
    expect(business.action, 'UPDATE');
    expect(business.target, '阿胶糕');
    expect(business.productSku, 'AJ001');

    const OperationLog web = OperationLog(<String, Object?>{
      'user_name': 'Maria',
      'operation_type': 'UPDATE',
      'details': <String, Object?>{
        'sku': 'AJ001',
        'changes': <String, Object?>{
          'quantity': <String, Object?>{'from': 12, 'to': 8},
        },
      },
    });
    expect(web.actor, 'Maria');
    expect(web.target, 'AJ001');
    expect(web.changes, hasLength(1));
    expect(web.changes.single.field, 'quantity');
    expect(web.changes.single.from, '12');
    expect(web.changes.single.to, '8');
  });

  test('动作与字段名按语言翻译，未登记的取值原样透出', () {
    expect(logActionLabel(zh, 'CREATE'), '新增');
    expect(logActionLabel(zh, 'FINALIZE'), '完成备货');
    expect(logFieldLabel(zh, 'min_stock'), '预警下限');
    expect(logFieldLabel(zh, 'cost'), '成本');
    // 库里确实躺着这些没登记的动作：译错比原样显示更糟。
    expect(logActionLabel(zh, 'MP_LISTING_PAUSE'), 'MP_LISTING_PAUSE');
    expect(logFieldLabel(zh, 'box_price'), 'box_price');
  });

  test('一行动态 = 人 · 动作 · 对象 · 变更', () {
    const OperationLog log = OperationLog(<String, Object?>{
      'user_name': 'yejunqiao888',
      'operation_type': 'UPDATE',
      'table_name': 'products',
      'details': <String, Object?>{
        'sku': '6666',
        'name': '箱包',
        'changes': <String, Object?>{
          'quantity': <String, Object?>{'from': 4, 'to': 539},
          'location': <String, Object?>{'from': 'A1', 'to': 'B2'},
        },
      },
    });
    expect(logLine(zh, log), 'yejunqiao888 · 修改 · 箱包 · 库存 4 → 539 · 仓位 A1 → B2');
  });

  test('没有单品名的系统写（保留策略清理）照样成行，操作人缺位回「系统」', () {
    const OperationLog cleanup = OperationLog(<String, Object?>{
      'operation_type': 'DELETE',
      'table_name': 'products',
      'details': <String, Object?>{
        'kind': 'retention_cleanup',
        'name': '保留策略清理：零库存满 30 天软删 178 件',
      },
    });
    expect(cleanup.changes, isEmpty);
    expect(logLine(zh, cleanup), '系统 · 删除 · 保留策略清理：零库存满 30 天软删 178 件');

    const OperationLog empty = OperationLog(<String, Object?>{});
    expect(empty.target, '—');
  });
}
