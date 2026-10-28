import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/data/entities.dart';
import 'package:kucun_app/state/vision_review_model.dart';

/// 拍照录单的复核判定：这一层直接决定「哪些行进单、每行进多少、单价是多少」，
/// 所以必须能在没有网络和 AppState 的情况下跑真回执形状。
void main() {
  /// 服务端把库位行写成 `unit_price` / `stock`，读成 `price` / `quantity` 才算归一成功。
  Map<String, Object?> productRow(String id, String sku, {double price = 10, int stock = 5}) =>
      <String, Object?>{
        'id': id,
        'sku': sku,
        'name': '商品 $sku',
        'unit': '盒',
        'unit_price': price,
        'stock': stock,
        'units_per_box': 10,
        'category_name': '东柜',
      };

  /// 服务端对唯一匹配的行也原样带回整组候选（`product` 就是 `candidates[0]`），
  /// 所以「退回待点选」的行仍然有候选可点，不会变成无匹配。
  Map<String, Object?> uniqueLine(String id, String sku, {int qty = 3, double confidence = 0.9}) =>
      <String, Object?>{
        'matched': true,
        'ambiguous': false,
        'truncated': false,
        'group_size': 1,
        'confidence': confidence,
        'product': productRow(id, sku),
        'candidates': <Object?>[
          <String, Object?>{
            ...productRow(id, sku),
            'match_kind': 'sku_exact',
          },
        ],
        'hint': <String, Object?>{'sku_hint': sku, 'name_hint': '', 'qty': qty},
      };

  Map<String, Object?> ambiguousLine(String sku, List<String> ids, {int qty = 2}) =>
      <String, Object?>{
        'matched': false,
        'ambiguous': true,
        'truncated': false,
        'group_size': ids.length,
        'confidence': 0.6,
        'product': null,
        'candidates': <Object?>[
          for (final String id in ids)
            <String, Object?>{
              ...productRow(id, sku),
              'category_name': id == ids.first ? '东柜' : '西柜',
              'match_kind': 'sku_folded',
            },
        ],
        'hint': <String, Object?>{'sku_hint': sku, 'name_hint': '', 'qty': qty},
      };

  Map<String, Object?> unmatchedLine(String sku) => <String, Object?>{
        'matched': false,
        'ambiguous': false,
        'truncated': false,
        'group_size': 0,
        'confidence': 0.2,
        'product': null,
        'candidates': <Object?>[],
        'hint': <String, Object?>{'sku_hint': '', 'name_hint': sku, 'qty': 1},
      };

  VisionReviewModel buildModel() => VisionReviewModel(VisionDraft(<String, Object?>{
        'customer_hint': '老王',
        'type_hint': 'outbound',
        'items': <Object?>[
          uniqueLine('p1', 'AJ001', qty: 12),
          ambiguousLine('AJ002', <String>['p2a', 'p2b'], qty: 2),
          unmatchedLine('无码散件'),
        ],
      }));

  group('回执解析', () {
    test('数量取自 hint.qty，不是顶层字段', () {
      final VisionLine line = VisionLine(uniqueLine('p1', 'AJ001', qty: 12));
      expect(line.qty, 12, reason: '读成顶层 qty 会永远拿到 0，每行都按 1 进单');
      expect(line.hintWas, 'AJ001');
      expect(line.confidence, 0.9);
    });

    test('matched 行把 unit_price / stock 归一成 price / quantity', () {
      final Product row = VisionLine(uniqueLine('p1', 'AJ001')).product!;
      expect(row.price, 10, reason: '直接读 price 会是 0，识别行以 ¥0 进单');
      expect(row.quantity, 5);
      expect(row.unitsPerBox, 10);
      expect(row.categoryName, '东柜');
    });

    test('歧义行没有 product，但有整组候选；未匹配行两者都没有', () {
      final VisionLine ambiguous = VisionLine(ambiguousLine('AJ002', <String>['p2a', 'p2b']));
      expect(ambiguous.matched, isFalse);
      expect(ambiguous.resolvedProduct, isNull);
      expect(ambiguous.candidates.length, 2);

      final VisionLine blank = VisionLine(unmatchedLine('无码散件'));
      expect(blank.resolvedProduct, isNull);
      expect(blank.candidates, isEmpty);
      expect(blank.nameHint, '无码散件');
    });
  });

  group('勾选与点选', () {
    test('只有库里唯一确定的行会被自动勾上', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      expect(model.isChecked(0), isTrue);
      expect(model.isChecked(1), isFalse, reason: '同码分柜必须由卖家点，服务端刻意不猜 top-1');
      expect(model.isChecked(2), isFalse);
      expect(model.checkedCount, 1);
    });

    test('点定歧义行后立刻变已确定并勾上', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      expect(model.statusOf(1), VisionRowStatus.needsPick);

      model.choose(1, model.draft.items[1].candidates.last.product);
      expect(model.statusOf(1), VisionRowStatus.ready);
      expect(model.isChecked(1), isTrue);
      expect(model.resolvedOf(1)!.id, 'p2b');
      expect(model.counts.needsPick, 0);
      expect(model.counts.ready, 2);
    });

    test('换一行把已确定的行退回待点选并取消勾选', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      model.reselect(0);
      expect(model.statusOf(0), VisionRowStatus.needsPick);
      expect(model.resolvedOf(0), isNull);
      expect(model.isChecked(0), isFalse);
      expect(model.counts.ready, 0);
    });

    test('未匹配行既不会被判成已确定，也进不了单', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      expect(model.statusOf(2), VisionRowStatus.unmatched);
      expect(model.counts.unmatched, 1);
      model.toggle(2); // 界面上这颗勾是禁用的，这里验的是状态机自己也不放行
      expect(model.commit().map((VisionPick r) => r.product.id), <String>['p1']);
    });

    test('全选开关：一次勾满已确定的行，再点一次清空', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      model.choose(1, model.draft.items[1].candidates.first.product);
      expect(model.counts.ready, 2);

      model.toggleAllReady(); // 已全勾 → 清空
      expect(model.checkedCount, 0);
      expect(model.isEveryReadyChecked, isFalse);

      model.toggleAllReady(); // 再点 → 全勾
      expect(model.checkedCount, 2);
      expect(model.isEveryReadyChecked, isTrue);
      expect(model.isChecked(2), isFalse, reason: '未匹配行不参与全选');
    });
  });

  group('进单结果', () {
    test('勾选行的数量走 hint，改过的数量优先', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      model.choose(1, model.draft.items[1].candidates.first.product);
      model.setQty(0, 40);

      final List<VisionPick> rows = model.commit();
      expect(rows.length, 2);
      expect(rows[0].qty, 40);
      expect(rows[1].qty, 2);
    });

    test('数量清零的行不进单，但勾选状态留着', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      model.setQty(0, 0);
      expect(model.commit(), isEmpty);
      expect(model.checkedCount, 1);

      model.setQty(0, 7);
      expect(model.commit().single.qty, 7);
    });

    test('取消勾选后该行不会混进单', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      model.toggle(0);
      expect(model.commit(), isEmpty);
    });
  });

  group('筛选与搜索', () {
    test('过滤按状态，返回的下标仍是结果里的原下标', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      expect(model.visible(VisionFilter.all, ''), <int>[0, 1, 2]);
      expect(model.visible(VisionFilter.needsPick, ''), <int>[1]);
      expect(model.visible(VisionFilter.unmatched, ''), <int>[2]);
    });

    test('搜索能命中模型读到的码，也能命中卖家点定的柜名', () {
      final VisionReviewModel model = buildModel()..autoCheck();
      expect(model.visible(VisionFilter.all, 'aj002'), <int>[1]);
      expect(model.visible(VisionFilter.all, '无码'), <int>[2]);

      model.choose(1, model.draft.items[1].candidates.last.product);
      expect(model.visible(VisionFilter.all, '西柜'), <int>[1]);
      expect(model.visible(VisionFilter.needsPick, '西柜'), isEmpty);
    });
  });
}
