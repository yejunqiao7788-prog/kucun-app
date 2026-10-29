import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/core/log_labels.dart';
import 'package:kucun_app/data/entities.dart';
import 'package:kucun_app/screens/dashboard/dashboard_screen.dart';

/// 首页动态一行的排版。改动都落在「看得见」这一层：名字有没有被挤掉、
/// 变更是不是只露出前两条就沉默、价格有没有被读成数量。
void main() {
  const L10n zh = L10n('zh');

  OperationLog log({Map<String, Object?>? changes, String name = '阿胶固元糕 500g 礼盒装 附赠手提袋'}) {
    return OperationLog(<String, Object?>{
      'id': 'l-1',
      'user_name': 'yejunqiao888',
      'operation_type': 'UPDATE',
      'table_name': 'products',
      'created_at': DateTime.now().subtract(const Duration(minutes: 7)).toIso8601String(),
      'details': <String, Object?>{
        'name': name,
        'sku': 'AJ001',
        if (changes != null) 'changes': changes,
      },
    });
  }

  Widget pump(OperationLog row) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, child: LogRowCard(log: row, l10n: zh, currency: r'$')),
          ),
        ),
      );

  test('价格/成本按货币排版，数量保持原样', () {
    final List<String> chips = logChangeChips(
      zh,
      log(changes: <String, Object?>{
        'price': <String, Object?>{'from': 12.5, 'to': 15},
        'cost': <String, Object?>{'from': 8, 'to': 9},
        'quantity': <String, Object?>{'from': 4, 'to': 539},
        'box_price': <String, Object?>{'from': 100, 'to': 120},
      }),
      currency: r'$',
    );
    expect(chips, <String>[
      '售价 \$12.50 → \$15.00',
      '成本 \$8.00 → \$9.00',
      '库存 4 → 539',
      'box_price \$100.00 → \$120.00',
    ]);
  });

  test('不传货币就一个字符都不变，AI 页那套文本照样读', () {
    expect(
      logChangesLine(
        zh,
        log(changes: <String, Object?>{
          'price': <String, Object?>{'from': 12.5, 'to': 15},
        }),
      ),
      '售价 12.5 → 15',
    );
  });

  testWidgets('长名字拿回整行宽度，不再被 190px 上限截断', (WidgetTester tester) async {
    await tester.pumpWidget(pump(log()));
    await tester.pumpAndSettle();

    final Size name = tester.getSize(find.text('阿胶固元糕 500g 礼盒装 附赠手提袋'));
    expect(name.width, greaterThan(250));
    expect(name.height, lessThan(30));
  });

  testWidgets('五条变更全摆出来，不再截成前三条报个数', (WidgetTester tester) async {
    await tester.pumpWidget(pump(log(changes: <String, Object?>{
      'quantity': <String, Object?>{'from': 4, 'to': 539},
      'location': <String, Object?>{'from': 'A1', 'to': 'B2'},
      'min_stock': <String, Object?>{'from': 0, 'to': 10},
      'max_stock': <String, Object?>{'from': 100, 'to': 200},
      'price': <String, Object?>{'from': 12.5, 'to': 15},
    })));
    await tester.pumpAndSettle();

    expect(find.text('库存 4 → 539'), findsOneWidget);
    expect(find.text('仓位 A1 → B2'), findsOneWidget);
    expect(find.text('预警下限 0 → 10'), findsOneWidget);
    // 以前第 4、5 条被折成「+2 项」，而这一栏存在的意义就是说清楚改了哪些字段。
    expect(find.text('预警上限 100 → 200'), findsOneWidget);
    expect(find.text('售价 \$12.50 → \$15.00'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(find.text('AJ001'), findsOneWidget);

    final Size chip = tester.getSize(find.text('库存 4 → 539'));
    expect(chip.width, greaterThan(60));
  });

  test('批量改价没有 changes，就从 details 的参数与计数读出干了什么', () {
    final OperationLog row = OperationLog(<String, Object?>{
      'id': 'l-2',
      'operation_type': 'UPDATE',
      'table_name': 'products',
      'user_name': 'yejunqiao888',
      'created_at': DateTime.now().toIso8601String(),
      'details': <String, Object?>{
        'action': 'batch_price',
        'mode': 'markup_cost',
        'value': 20,
        'total': 768,
        'updated': 42,
        'unchanged': 720,
        'failed': 6,
        'requestId': 'req-1',
      },
    });
    expect(logObjectLabel(zh, row), '批量改价');
    expect(logChangeChips(zh, row, currency: r'$'), <String>[
      '在成本上加价 20%',
      '共 768 件',
      '更新 42 · 无变化 720 · 失败 6',
    ]);
  });

  test('成本加价档带百分号，统一售价档带货币符号', () {
    List<String> chips(String mode, Object value) => logChangeChips(
          zh,
          OperationLog(<String, Object?>{
            'operation_type': 'UPDATE',
            'details': <String, Object?>{'action': 'batch_price', 'mode': mode, 'value': value},
          }),
          currency: r'$',
        );
    expect(chips('markup_cost', 20), <String>['在成本上加价 20%']);
    expect(chips('set', 99), <String>['设为同一售价 \$99.00']);
  });

  test('外部同步：对象名读数据源，改动数与售价来源各一块', () {
    final OperationLog row = OperationLog(<String, Object?>{
      'id': 'l-3',
      'operation_type': 'SYNC',
      'table_name': 'products',
      'created_at': DateTime.now().toIso8601String(),
      'details': <String, Object?>{
        'source': 'rozetka',
        'price_target': 'cost',
        'markup_percent': 15,
        'updated': 20,
        'unchanged': 5,
        'failed': 1,
        'new_found': 3,
        'ip': '10.0.0.1',
      },
    });
    expect(logObjectLabel(zh, row), '外部同步 rozetka');
    expect(logChangeChips(zh, row), <String>[
      '更新 20 · 无变化 5 · 失败 1',
      '新增 3 个 SKU',
      '售价取自 成本',
      'markup_percent 15',
    ]);
  });

  test('bookkeeping 键（requestId / ip / name / sku）永远不摆进 chips', () {
    expect(
      logChangeChips(
        zh,
        OperationLog(<String, Object?>{
          'operation_type': 'DELETE',
          'details': <String, Object?>{
            'name': '旧货', 'sku': 'X1', 'requestId': 'r', 'ip': '1.2.3.4', 'triggered_by': 'cron',
          },
        }),
      ),
      isEmpty,
    );
  });

  test('保留期清理的软删/硬删数从 details 读出来', () {
    expect(
      logChangeChips(zh, OperationLog(<String, Object?>{
        'operation_type': 'DELETE',
        'details': <String, Object?>{
          'kind': 'retention_cleanup',
          'name': '保留策略清理：零库存满 90 天软删 12 件',
          'soft_deleted_count': 12,
          'hard_deleted_count': 3,
        },
      })),
      <String>['软删 12 · 硬删 3'],
    );
  });

  testWidgets('批量改价行不再是一个光秃秃的「—」', (WidgetTester tester) async {
    await tester.pumpWidget(pump(OperationLog(<String, Object?>{
      'operation_type': 'UPDATE',
      'table_name': 'products',
      'user_name': 'yejunqiao888',
      'created_at': DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
      'details': <String, Object?>{
        'action': 'batch_price',
        'mode': 'percent',
        'value': -10,
        'total': 50,
        'updated': 48,
        'unchanged': 2,
        'failed': 0,
      },
    })));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsNothing);
    expect(find.text('批量改价'), findsOneWidget);
    expect(find.text('按百分比 -10%'), findsOneWidget);
    expect(find.text('共 50 件'), findsOneWidget);
    final Size name = tester.getSize(find.text('批量改价'));
    expect(name.width, greaterThan(40));
  });

  testWidgets('人 · 时间在页脚成一行，动作块在左侧撑得住', (WidgetTester tester) async {
    await tester.pumpWidget(pump(log()));
    await tester.pumpAndSettle();

    final Size foot = tester.getSize(find.text('yejunqiao888 · 7 分钟前'));
    expect(foot.width, greaterThan(100));
    expect(tester.getRect(find.byIcon(Icons.edit_rounded)).width, greaterThanOrEqualTo(16));
    expect(tester.getRect(find.text('修改')).top, closeTo(tester.getRect(find.text('阿胶固元糕 500g 礼盒装 附赠手提袋')).top, 20));
  });
}
