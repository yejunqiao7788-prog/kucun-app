import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/design/tokens.dart';
import 'package:kucun_app/design/widgets/product_identity.dart';

/// 商品标识行的两条硬规矩：SKU 恒 ≥ 名称（码是唯一标识，名称是库位名），
/// 以及关掉名称之后副行不留孤立的「·」、库存箱规那一截不跟着消失。
///
/// 字号用 RenderParagraph 的实际 style 断言，不用 find.text —— 后者只证明组件存在，
/// 证明不了「码有没有被压成灰色小字」。
void main() {
  const String sku = 'AJ-001';
  const String name = '阿胶固元糕 500g 礼盒装';

  Widget pump(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 360, child: child),
          ),
        ),
      );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

  testWidgets('md 与 sm 两档都保证 SKU ≥ 名称，且码真的占得到宽度', (WidgetTester tester) async {
    for (final IdentitySize size in IdentitySize.values) {
      await tester.pumpWidget(pump(ProductIdentity(sku: sku, name: name, size: size)));
      final double skuSize = styleOf(tester, sku).fontSize!;
      final double nameSize = styleOf(tester, name).fontSize!;
      expect(skuSize, IdentityType.sku(size), reason: '$size 的码字号要出自唯一出处');
      expect(nameSize, IdentityType.name(size));
      expect(skuSize, greaterThanOrEqualTo(nameSize), reason: '$size: SKU 恒 ≥ 名称');
      expect(tester.getSize(find.text(sku)).width, greaterThan(0));
      // 码是等宽半粗，名称是常规副行：同一行里码读得更重。
      expect(styleOf(tester, sku).fontWeight, AppType.semi);
      expect(styleOf(tester, sku).fontFamily, 'monospace');
    }
  });

  testWidgets('关掉名称：名称整行不渲染，副行那一截还在，且不留孤立的分隔符',
      (WidgetTester tester) async {
    await tester.pumpWidget(pump(const ProductIdentity(
      sku: sku,
      name: name,
      showName: false,
      secondary: '库存 12',
    )));
    expect(find.text(sku), findsOneWidget);
    expect(find.text(name), findsNothing);
    expect(find.text('库存 12'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('名称开着：分隔符由组件插入，名称与副行合成一行', (WidgetTester tester) async {
    await tester.pumpWidget(pump(const ProductIdentity(
      sku: sku,
      name: name,
      secondary: '库存 12',
    )));
    expect(find.text('$name · 库存 12'), findsOneWidget);
  });

  testWidgets('只有名称没有副行时不插分隔符；只有副行时名称关掉也不空一行',
      (WidgetTester tester) async {
    await tester.pumpWidget(pump(const ProductIdentity(sku: sku, name: name)));
    expect(find.text(name), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);

    await tester.pumpWidget(pump(const ProductIdentity(
      sku: sku,
      name: name,
      showName: false,
    )));
    expect(find.text(sku), findsOneWidget);
    expect(find.text(name), findsNothing);
  });

  testWidgets('已拣划线：码与名称一起划，不是只划名称', (WidgetTester tester) async {
    await tester.pumpWidget(pump(const ProductIdentity(
      sku: sku,
      name: name,
      struck: true,
    )));
    expect(styleOf(tester, sku).decoration, TextDecoration.lineThrough);
    expect(styleOf(tester, name).decoration, TextDecoration.lineThrough);
  });

  testWidgets('单行面 SkuText 与两行面同源：空码回「—」，字号不出第二套',
      (WidgetTester tester) async {
    await tester.pumpWidget(pump(const Row(
      children: <Widget>[
        SkuText(sku: '  '),
        SkuText(sku: sku, size: IdentitySize.sm),
      ],
    )));
    expect(find.text('—'), findsOneWidget);
    expect(styleOf(tester, sku).fontSize, IdentityType.sku(IdentitySize.sm));
    expect(
      IdentityType.sku(IdentitySize.sm),
      greaterThanOrEqualTo(IdentityType.name(IdentitySize.sm)),
    );
  });
}