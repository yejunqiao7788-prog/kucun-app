import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/formatters.dart';
import 'package:kucun_app/design/widgets/controls.dart';
import 'package:kucun_app/design/widgets/surfaces.dart';

/// 商品编辑里的「售价 + 成本」是两个 Expanded 并排，外面还套了货币符号 suffix。
/// release 模式下布局异常只会画成灰块、不报红屏，只能把这一行单独 pump 出来才看得见。
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
