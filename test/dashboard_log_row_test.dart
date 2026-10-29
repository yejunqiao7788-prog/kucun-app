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

  testWidgets('变更逐条摆开，第 4 条起报数而不是沉默', (WidgetTester tester) async {
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
    // 后两条挤不进来了，但必须说一声还有几条，不能让人以为改动只有这些。
    expect(find.text('+2 项'), findsOneWidget);
    expect(find.textContaining('预警上限'), findsNothing);
    expect(find.text('AJ001'), findsOneWidget);

    final Size chip = tester.getSize(find.text('库存 4 → 539'));
    expect(chip.width, greaterThan(60));
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
