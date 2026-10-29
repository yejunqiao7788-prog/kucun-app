import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/data/entities.dart';
import 'package:kucun_app/screens/orders/order_detail_screen.dart';

/// 收款抽屉的找零/仍欠提示。规则与网页端 `OrderPaymentDialog.tsx` 的 `hint` 一致：
/// 实收 - 未收余额，0.005 容差判平，实收没填就不出这条。
void main() {
  const L10n zh = L10n('zh');

  group('派生规则', () {
    test('实收大于余额是找零，小于余额是仍欠，都不许被钳成 0', () {
      expect(paymentHint(received: 120, outstanding: 100)!.kind, PaymentHintKind.change);
      expect(paymentHint(received: 120, outstanding: 100)!.amount, closeTo(20, 0.0001));
      expect(paymentHint(received: 60, outstanding: 100)!.kind, PaymentHintKind.shortfall);
      expect(paymentHint(received: 60, outstanding: 100)!.amount, closeTo(40, 0.0001));
    });

    test('半分以内的差算结清，浮点减法不拿 == 0 比', () {
      expect(paymentHint(received: 100.004, outstanding: 100)!.kind, PaymentHintKind.exact);
      expect(paymentHint(received: 99.996, outstanding: 100)!.kind, PaymentHintKind.exact);
      expect(paymentHint(received: 100, outstanding: 100)!.amount, 0);
    });

    test('还没填实收时整条不出', () {
      expect(paymentHint(received: 0, outstanding: 100), isNull);
      expect(paymentHint(received: -5, outstanding: 100), isNull);
    });
  });

  group('抽屉里的实时性', () {
    const Order owed100 = Order(<String, Object?>{
      'id': 'o-1',
      'order_number': 'CK2026-1029-01',
      'payable_amount': 100,
      'paid_amount': 0,
    });

    Widget sheet() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: PaymentSheet(order: owed100, currency: r'$', l10n: zh),
              ),
            ),
          ),
        );

    testWidgets('打开就是「正好结清」，改一个数字立刻跟着变', (WidgetTester tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      final TextFormField seed = tester.widget<TextFormField>(
        find.descendant(
          of: find.byType(PaymentSheet),
          matching: find.byType(TextFormField),
        ).first,
      );
      expect(seed.controller!.text, '100.00');
      expect(find.text('本次收款正好结清'), findsOneWidget);

      // 货币符号已经搬到数字左边（全 App 与网页端 `prefixIcon={symbol}` 统一）。
      expect(find.text('\$'), findsOneWidget);
      expect(tester.getRect(find.text('\$')).left,
          lessThan(tester.getRect(find.byType(EditableText).first).left));

      await tester.enterText(find.byType(TextFormField).first, '120');
      await tester.pump();
      expect(find.text('找零 \$20.00'), findsOneWidget);
      expect(find.text('本次收款正好结清'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, '135.5');
      await tester.pump();
      expect(find.text('找零 \$35.50'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '60');
      await tester.pump();
      expect(find.text('本次收款后仍欠 \$40.00'), findsOneWidget);
    });

    testWidgets('清空实收，提示条整块让位，不留 0 值的死行', (WidgetTester tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      expect(find.textContaining(RegExp('找零|仍欠|正好结清')), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, '180');
      await tester.pump();
      expect(find.text('找零 \$80.00'), findsOneWidget);
    });

    testWidgets('提示条占得到宽度：release 下画不出来的东西 find.text 也照样查得到',
        (WidgetTester tester) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '160');
      await tester.pump();

      // find.text 只证明这行字在树上；量出宽高才证明它真被摆到了屏幕上，
      // 这个项目已经吃过两次「组件在、宽度 0」的亏。
      final Size glyph = tester.getSize(find.text('找零 \$60.00'));
      expect(glyph.width, greaterThan(120));
      expect(glyph.height, greaterThanOrEqualTo(16));

      final Rect text = tester.getRect(find.text('找零 \$60.00'));
      final Rect field = tester.getRect(find.byType(TextFormField).first);
      // 提示条必须落在输入框下方，否则它跟着变也变在看不见的地方。
      expect(text.top, greaterThan(field.bottom));
    });
  });
}
