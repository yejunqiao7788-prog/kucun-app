import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/design/theme.dart';
import 'package:kucun_app/design/widgets/controls.dart';

/// 数字框两侧的小尾巴（货币符号 / 单位 / 百分号）。
///
/// 判定标准只能靠量：`find.text` 查得到符号、符号也可能正飘在数字右上角当上标。
/// 网页端 `fields.tsx` 的处理是符号与数字同字号、同一条基线，货币在左（`prefixIcon={symbol}`）、
/// 单位与 `%` 在右，两者都离边框 `left-3 / right-3`。这里逐条钉住。
void main() {
  Widget field({
    String? prefix,
    String? suffix,
    String value = '1200',
    double width = 165,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: NumberField(
              label: '售价',
              controller: TextEditingController(text: value),
              prefix: prefix,
              suffix: suffix,
            ),
          ),
        ),
      ),
    );
  }

  Rect glyphOf(WidgetTester tester, String glyph) => tester.getRect(
        find
            .descendant(of: find.text(glyph), matching: find.byType(RichText))
            .first,
      );

  testWidgets('符号与数字共用一条基线：行盒同高、中线重合', (WidgetTester tester) async {
    await tester.pumpWidget(field(prefix: '\$'));
    await tester.pumpAndSettle();

    final Rect digits = tester.getRect(find.byType(EditableText));
    final Rect symbol = glyphOf(tester, '\$');
    expect(symbol.height, digits.height);
    expect(symbol.center.dy, closeTo(digits.center.dy, 0.5));
  });

  testWidgets('货币在左、单位在右，且都离边框 12', (WidgetTester tester) async {
    await tester.pumpWidget(field(prefix: '\$'));
    await tester.pumpAndSettle();
    final Rect box = tester.getRect(find.byType(TextFormField));
    final Rect symbol = glyphOf(tester, '\$');
    expect(symbol.left, lessThan(tester.getRect(find.byType(EditableText)).left),
        reason: '符号必须落在数字左边，和网页端一致');
    expect(symbol.left - box.left, closeTo(12, 1));

    await tester.pumpWidget(field(suffix: '盒'));
    await tester.pumpAndSettle();
    final Rect box2 = tester.getRect(find.byType(TextFormField));
    final Rect unit = glyphOf(tester, '盒');
    expect(box2.right - unit.right, closeTo(12, 1));
    expect(unit.center.dy, closeTo(tester.getRect(find.byType(EditableText)).center.dy, 0.5));
  });

  testWidgets('加了符号，输入区还是够宽：别再退化成 0 宽的空框', (WidgetTester tester) async {
    await tester.pumpWidget(field(prefix: '\$', width: 165));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(EditableText)).width, greaterThan(100));

    // 右槽留着 Material 的 48 宽下限，等价于网页端给输入区预留的 `pr-9`：
    // 数字再长也不会怼到单位脸上，所以这里只要求「还写得下三位数」。
    await tester.pumpWidget(field(suffix: '盒', width: 165));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(EditableText)).width, greaterThan(60));
  });

  testWidgets('单位和符号同字号，谁都不比谁小一号', (WidgetTester tester) async {
    await tester.pumpWidget(field(prefix: '฿', suffix: '件'));
    await tester.pumpAndSettle();
    final Rect digits = tester.getRect(find.byType(EditableText));
    expect(glyphOf(tester, '฿').height, digits.height);
    expect(glyphOf(tester, '件').height, digits.height);
  });
}
