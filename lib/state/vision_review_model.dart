import '../data/entities.dart';

/// 复核页交回开单页的一行：商品与数量。单价不在这里定，回开单页按库覆盖。
class VisionPick {
  const VisionPick({required this.product, required this.qty});

  final Product product;
  final int qty;
}

enum VisionRowStatus { ready, needsPick, unmatched }

enum VisionFilter { all, needsPick, unmatched }

class VisionCounts {
  const VisionCounts({
    required this.all,
    required this.ready,
    required this.needsPick,
    required this.unmatched,
  });

  final int all;
  final int ready;
  final int needsPick;
  final int unmatched;

  int byFilter(VisionFilter filter) => switch (filter) {
        VisionFilter.all => all,
        VisionFilter.needsPick => needsPick,
        VisionFilter.unmatched => unmatched,
      };
}

/// 拍照识别结果的复核状态机，逐条抄网页端 `VisionOrderDialog.tsx` 的四个 state：
/// `_picks` = 卖家点定的行（覆盖服务端判定），`_reopened` = 从「已确定」退回待点选，
/// `_checked` = 勾上的行，`_qty` = 改过的数量，全部以结果里的下标为键。
///
/// 刻意抽成纯 Dart：判定逻辑（谁算已确定、勾选与数量怎么走到进单）是这一页唯一会写错钱的地方，
/// 它必须能在没有网络、没有 AppState 的情况下跑真数据。
class VisionReviewModel {
  VisionReviewModel(this.draft);

  VisionDraft draft;

  final Map<int, Product> _picks = <int, Product>{};
  final Set<int> _reopened = <int>{};
  final Set<int> _checked = <int>{};
  final Map<int, int> _qty = <int, int>{};

  List<VisionLine> get _lines => draft.items;

  /// 底部按钮的计数口径与网页端一致：数的是勾选，不是最终进单行数
  /// （勾上但数量清零的行会在 commit 时被丢掉，那是收单那一刻的事）。
  int get checkedCount => _checked.length;

  bool isChecked(int index) => _checked.contains(index);

  /// 新结果到手时的初始勾选：只勾库里唯一确定的行。歧义行必须由卖家点，
  /// 服务端也刻意不猜 top-1 —— 柜名是唯一区分维度。
  void autoCheck() {
    _checked.clear();
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].matched && !_lines[i].ambiguous) _checked.add(i);
    }
  }

  VisionRowStatus statusOf(int index) {
    if (_picks.containsKey(index)) return VisionRowStatus.ready;
    final VisionLine line = _lines[index];
    if (_reopened.contains(index)) {
      return line.candidates.isEmpty
          ? VisionRowStatus.unmatched
          : VisionRowStatus.needsPick;
    }
    if (line.resolvedProduct != null) return VisionRowStatus.ready;
    return line.candidates.isEmpty
        ? VisionRowStatus.unmatched
        : VisionRowStatus.needsPick;
  }

  /// 这一行进单的商品：卖家点定的优先，其次是被服务端唯一确定且没被退回的行。
  Product? resolvedOf(int index) {
    return _picks[index] ??
        (_reopened.contains(index) ? null : _lines[index].resolvedProduct);
  }

  int qtyOf(int index) => _qty[index] ?? _lines[index].qty;

  /// 改过的数量一律记下，包括改成 0：0 是卖家明确表达「这一行不要」，
  /// 让它退回识别数就等于替他改回了主意。
  void setQty(int index, int value) {
    _qty[index] = value < 0 ? 0 : value;
  }

  void choose(int index, Product product) {
    _picks[index] = product;
    _reopened.remove(index);
    _checked.add(index);
  }

  /// 「换一行」：把服务端当初判成唯一匹配的行退回待点选，并取消勾选。
  void reselect(int index) {
    _picks.remove(index);
    _reopened.add(index);
    _checked.remove(index);
  }

  void toggle(int index) {
    if (!_checked.remove(index)) _checked.add(index);
  }

  /// 一次点选 40 行在手机上也是十几次点击，所以「全部已确定的行」给一个总开关。
  void toggleAllReady() {
    final List<int> ready = <int>[
      for (int i = 0; i < _lines.length; i++)
        if (statusOf(i) == VisionRowStatus.ready) i,
    ];
    if (ready.isEmpty) return;
    final bool every = ready.every(_checked.contains);
    for (final int index in ready) {
      if (every) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    }
  }

  bool get isEveryReadyChecked {
    final List<int> ready = <int>[
      for (int i = 0; i < _lines.length; i++)
        if (statusOf(i) == VisionRowStatus.ready) i,
    ];
    return ready.isNotEmpty && ready.every(_checked.contains);
  }

  VisionCounts get counts {
    int ready = 0;
    int needsPick = 0;
    int unmatched = 0;
    for (int i = 0; i < _lines.length; i++) {
      switch (statusOf(i)) {
        case VisionRowStatus.ready:
          ready += 1;
        case VisionRowStatus.needsPick:
          needsPick += 1;
        case VisionRowStatus.unmatched:
          unmatched += 1;
      }
    }
    return VisionCounts(
      all: _lines.length,
      ready: ready,
      needsPick: needsPick,
      unmatched: unmatched,
    );
  }

  /// 下标必须原样返回：勾选、点选、数量全部按下标记账，返回副本就会全部错位。
  List<int> visible(VisionFilter filter, String query) {
    final String q = query.trim().toLowerCase();
    final List<int> rows = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      if (filter != VisionFilter.all && statusOf(i) != _statusOfFilter(filter)) {
        continue;
      }
      if (q.isNotEmpty) {
        final VisionLine line = _lines[i];
        final Product? resolved = resolvedOf(i);
        final String hay = <String>[
          line.skuHint,
          line.nameHint,
          line.categoryHint,
          resolved?.sku ?? '',
          resolved?.name ?? '',
          resolved?.categoryName ?? '',
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) continue;
      }
      rows.add(i);
    }
    return rows;
  }

  static VisionRowStatus _statusOfFilter(VisionFilter filter) =>
      filter == VisionFilter.needsPick
          ? VisionRowStatus.needsPick
          : VisionRowStatus.unmatched;

  /// 勾上、能解析出商品、数量大于零，三条都满足才进单。
  List<VisionPick> commit() {
    final List<VisionPick> rows = <VisionPick>[];
    for (int i = 0; i < _lines.length; i++) {
      if (!_checked.contains(i)) continue;
      final Product? product = resolvedOf(i);
      if (product == null) continue;
      final int qty = qtyOf(i);
      if (qty > 0) rows.add(VisionPick(product: product, qty: qty));
    }
    return rows;
  }
}
