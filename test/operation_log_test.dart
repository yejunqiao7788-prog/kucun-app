import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/data/entities.dart';

void main() {
  test('两套键名的日志都能读出摘要', () {
    const OperationLog business = OperationLog(<String, Object?>{
      'username': '张伟',
      'action': '入库',
      'name': '阿胶糕',
      'sku': 'AJ001',
      'detail': '入库 12 箱',
    });
    expect(business.summary, '张伟 · 入库 · 阿胶糕 · 入库 12 箱');

    const OperationLog web = OperationLog(<String, Object?>{
      'user_name': 'Maria',
      'operation_type': 'update',
      'details': <String, Object?>{
        'sku': 'AJ001',
        'changes': <String, Object?>{
          'quantity': <String, Object?>{'from': 12, 'to': 8},
        },
      },
    });
    expect(web.summary, 'Maria · update · AJ001 · quantity: 12 → 8');
  });

  test('字段缺失时摘要跳过空段，不留空行', () {
    const OperationLog sparse = OperationLog(<String, Object?>{
      'action': 'login',
    });
    expect(sparse.summary, 'login');
    expect(const OperationLog(<String, Object?>{}).summary, '—');
  });
}
