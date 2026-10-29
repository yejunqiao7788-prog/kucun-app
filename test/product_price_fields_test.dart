import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/formatters.dart';
import 'package:kucun_app/design/widgets/controls.dart';
import 'package:kucun_app/design/widgets/surfaces.dart';

/// 商品编辑里的「售价 + 成本」是两个 Expanded 并排，外面还套了货币符号 suffix。
/// release 模式下布局异常只会画成灰块、不报红屏，只能把这一行单独 pump 出来才看得见。
/// 而且 `find.text` 只证明组件树里有这串字、不证明它被画得出来 —— 必须量输入区自己的宽度。
void main() {
  // PATCH 是整行替换：框里的初值就是即将写回库的值，所以 0 与「没设过」必须长得不一样。
  test('价格框初值把 0 和 null 分得开', () {
    expect(Fmt.decimalSeed(null), '');
    expect(Fmt.decimalSeed(0), '0.00');
    expect(Fmt.decimalSeed(92.4), '92.40');
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  testWidgets('售价/成本并排两栏在窄屏上照常渲染，不出灰块', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0; // ≈ 360 逻辑宽
    addTearDown(tester.view.reset);

    final TextEditingController price = TextEditingController(text: '1234.50');
    final TextEditingController cost = TextEditingController(text: '678.00');

    await tester.pumpWidget(host(
      Row(
        children: <Widget>[
          Expanded(
            child: NumberField(label: '售价', controller: price, suffix: r'$'),
          ),
          const HGap(10),
          Expanded(
            child: NumberField(label: '成本', controller: cost, suffix: r'$'),
          ),
        ],
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('售价'), findsOneWidget);
    expect(find.text('成本'), findsOneWidget);
    expect(find.text('1234.50'), findsOneWidget);
    expect(find.text('678.00'), findsOneWidget);

    // 后缀一旦占位不当，输入区会被挤成 0 宽：数字全画不出来，屏上只剩一个「$」。
    expect(find.byType(EditableText), findsNWidgets(2));
    for (int i = 0; i < 2; i++) {
      expect(
        tester.getSize(find.byType(EditableText).at(i)).width,
        greaterThan(60),
        reason: '第 ${i + 1} 个价格输入区被货币后缀挤掉了',
      );
    }
  });

  testWidgets('后缀是单位词（比符号宽）时输入区照样留得下', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      SizedBox(
        width: 160,
        child: NumberField(
          label: '每箱数量',
          controller: TextEditingController(text: '100'),
          suffix: '件',
        ),
      ),
    ));

    expect(tester.getSize(find.byType(EditableText)).width, greaterThan(60));
  });

  testWidgets('零值与空值都不该把整栏挤掉', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      Row(
        children: <Widget>[
          Expanded(child: NumberField(label: '售价', controller: TextEditingController())),
          const HGap(10),
          Expanded(child: NumberField(label: '成本', controller: TextEditingController())),
        ],
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('售价'), findsOneWidget);
    expect(find.text('成本'), findsOneWidget);
  });
}
