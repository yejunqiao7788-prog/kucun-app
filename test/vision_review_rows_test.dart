import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/l10n.dart';
import 'package:kucun_app/data/entities.dart';
import 'package:kucun_app/design/widgets/product_identity.dart';
import 'package:kucun_app/screens/orders/vision_review_screen.dart';
import 'package:kucun_app/state/vision_review_model.dart';

/// 复核页一行的排版。真机截图上整块列表是一片灰：release 包里布局异常不弹红屏，
/// 只把出错的子树画成灰块，所以行排版必须在测试里真的摆一遍。
void main() {
  const L10n l10n = L10n('zh');

  Map<String, Object?> row(String id, String sku, {String? cabinet}) =>
      <String, Object?>{
        'id': id,
        'sku': sku,
        'name': '阿胶固元糕 500g 礼盒装 附赠手提袋与说明书一份',
        'unit': '盒',
        'unit_price': 68.5,
        'stock': 120,
        'units_per_box': 12,
        'box_price': 822,
        'category_name': cabinet ?? '东柜·阿胶区',
      };

  Map<String, Object?> candidate(String id, String sku) => <String, Object?>{
        ...row(id, sku, cabinet: id.endsWith('b') ? '西柜·阿胶区' : '东柜·阿胶区'),
        'match_kind': 'sku_folded',
      };

  Widget pump(VisionLine line, VisionRowStatus status,
      {Product? resolved, bool showName = true}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: VisionRowCard(
              line: line,
              status: status,
              resolved: resolved,
              checked: true,
              qty: 12,
              currency: '¥',
              l10n: l10n,
              showName: showName,
              onToggle: () {},
              onChoose: (_) {},
              onReselect: () {},
              onManual: () {},
              onQty: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('已确定的行：码、库位名、柜名/库存/单价/箱规都摆得下', (WidgetTester tester) async {
    final VisionLine line = VisionLine(<String, Object?>{
      'matched': true,
      'ambiguous': false,
      'confidence': 0.93,
      'product': row('p1', 'AJ-001'),
      'candidates': <Object?>[candidate('p1', 'AJ-001')],
      'hint': <String, Object?>{
        'sku_hint': 'AJ-001',
        'name_hint': '阿胶固元糕',
        'category_hint': '阿胶类',
        'note': '整箱发货，勿拆',
        'qty': 12,
      },
    });

    await tester.pumpWidget(pump(line, VisionRowStatus.ready, resolved: line.product));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AJ-001'), findsOneWidget);
    expect(find.textContaining('东柜·阿胶区'), findsWidgets);
    expect(find.textContaining('822'), findsWidgets, reason: '箱价要在行里读得到');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('待点选的行：候选逐条列出，每条都能点', (WidgetTester tester) async {
    final VisionLine line = VisionLine(<String, Object?>{
      'matched': false,
      'ambiguous': true,
      'group_size': 2,
      'confidence': 0.6,
      'candidates': <Object?>[candidate('p2a', 'AJ-002'), candidate('p2b', 'AJ-002')],
      'hint': <String, Object?>{'sku_hint': 'AJ-002', 'qty': 2},
    });

    await tester.pumpWidget(pump(line, VisionRowStatus.needsPick));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AJ-002'), findsNWidgets(2));
    expect(find.textContaining('西柜·阿胶区'), findsOneWidget);
  });

  testWidgets('无匹配的行：不崩，且留得下手选入口', (WidgetTester tester) async {
    final VisionLine line = VisionLine(<String, Object?>{
      'matched': false,
      'ambiguous': false,
      'confidence': 0.2,
      'candidates': <Object?>[],
      'hint': <String, Object?>{'name_hint': '无码散件 枸杞 250g', 'qty': 1},
    });

    await tester.pumpWidget(pump(line, VisionRowStatus.unmatched));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('无码散件'), findsWidgets);
  });

  testWidgets('码的字号不小于库位名：复核页照着码找货，码不能被压成小字',
      (WidgetTester tester) async {
    final VisionLine line = VisionLine(<String, Object?>{
      'matched': true,
      'confidence': 0.93,
      'product': row('p1', 'AJ-001'),
      'candidates': <Object?>[candidate('p1', 'AJ-001')],
      'hint': <String, Object?>{'sku_hint': 'AJ-001', 'qty': 12},
    });
    await tester.pumpWidget(pump(line, VisionRowStatus.ready, resolved: line.product));
    await tester.pumpAndSettle();

    double fontOf(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text).first).text.style!.fontSize!;
    const String name = '阿胶固元糕 500g 礼盒装 附赠手提袋与说明书一份';
    expect(fontOf('AJ-001'), IdentityType.sku(IdentitySize.md));
    expect(fontOf('AJ-001'), greaterThanOrEqualTo(fontOf(name)));
    expect(tester.getSize(find.text('AJ-001').first).width, greaterThan(0));
  });

  testWidgets('关掉名称：已确定行与候选行都只剩码，柜名/箱价这些作业信息不跟着消失',
      (WidgetTester tester) async {
    const String name = '阿胶固元糕 500g 礼盒装 附赠手提袋与说明书一份';
    final VisionLine ready = VisionLine(<String, Object?>{
      'matched': true,
      'confidence': 0.93,
      'product': row('p1', 'AJ-001'),
      'candidates': <Object?>[candidate('p1', 'AJ-001')],
      'hint': <String, Object?>{'sku_hint': 'AJ-001', 'qty': 12},
    });
    await tester.pumpWidget(
        pump(ready, VisionRowStatus.ready, resolved: ready.product, showName: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AJ-001'), findsOneWidget);
    expect(find.text(name), findsNothing);
    expect(find.textContaining('东柜·阿胶区'), findsWidgets);
    expect(find.textContaining('822'), findsWidgets);

    final VisionLine pick = VisionLine(<String, Object?>{
      'matched': false,
      'ambiguous': true,
      'group_size': 2,
      'candidates': <Object?>[candidate('p2a', 'AJ-002'), candidate('p2b', 'AJ-002')],
      'hint': <String, Object?>{'sku_hint': 'AJ-002', 'qty': 2},
    });
    await tester.pumpWidget(pump(pick, VisionRowStatus.needsPick, showName: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AJ-002'), findsNWidgets(2));
    expect(find.text(name), findsNothing);
    expect(find.textContaining('西柜·阿胶区'), findsOneWidget);
  });
}
