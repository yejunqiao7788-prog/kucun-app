import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';

enum LoadState { idle, loading, refreshing, ready, empty, failed }

class FetchResult<T> {
  const FetchResult({required this.rows, this.hasMore = false, this.stale = false, this.summary});

  final List<T> rows;
  final bool hasMore;
  final bool stale;
  final Object? summary;
}

/// 列表/详情的统一异步状态机：首屏 loading、下拉 refreshing、翻页 loadingMore、
/// 断网回落 stale、失败保留旧数据并给出服务端原文。
class ListController<T> extends ChangeNotifier {
  ListController({required this.fetch, this.keepOldOnError = true});

  /// page 从 1 开始；返回第 1 页时 rows 会整体替换。
  final Future<FetchResult<T>> Function(int page) fetch;
  final bool keepOldOnError;

  final List<T> rows = <T>[];
  LoadState state = LoadState.idle;
  String? errorText;
  String? errorCode;
  bool stale = false;
  bool loadingMore = false;
  bool hasMore = false;
  Object? summary;

  int _page = 0;
  int _generation = 0;

  bool get isBusy => state == LoadState.loading || loadingMore;

  Future<void> load() async {
    final int generation = ++_generation;
    _page = 0;
    if (rows.isEmpty) state = LoadState.loading;
    errorText = null;
    errorCode = null;
    notifyListeners();
    try {
      final FetchResult<T> result = await fetch(1);
      if (generation != _generation) return;
      rows
        ..clear()
        ..addAll(result.rows);
      summary = result.summary;
      stale = result.stale;
      hasMore = result.hasMore;
      _page = 1;
      state = rows.isEmpty ? LoadState.empty : LoadState.ready;
    } on Object catch (error) {
      if (generation != _generation) return;
      _applyError(error, clear: !keepOldOnError && rows.isEmpty);
    }
    notifyListeners();
  }

  /// 下拉刷新：保留旧行，只换状态，避免列表闪白。
  Future<void> refresh() async {
    final int generation = ++_generation;
    state = rows.isEmpty ? LoadState.loading : LoadState.refreshing;
    notifyListeners();
    try {
      final FetchResult<T> result = await fetch(1);
      if (generation != _generation) return;
      rows
        ..clear()
        ..addAll(result.rows);
      summary = result.summary;
      stale = result.stale;
      hasMore = result.hasMore;
      _page = 1;
      errorText = null;
      errorCode = null;
      state = rows.isEmpty ? LoadState.empty : LoadState.ready;
    } on Object catch (error) {
      if (generation != _generation) return;
      _applyError(error, clear: rows.isEmpty);
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore || loadingMore || state == LoadState.failed) return;
    loadingMore = true;
    notifyListeners();
    try {
      final FetchResult<T> result = await fetch(_page + 1);
      _page += 1;
      rows.addAll(result.rows);
      hasMore = result.hasMore;
      stale = result.stale;
      state = rows.isEmpty ? LoadState.empty : LoadState.ready;
    } on Object catch (error) {
      // 翻页失败不打断已有内容，只提示。
      errorText = _describe(error);
      errorCode = error is ApiException ? error.code : null;
    }
    loadingMore = false;
    notifyListeners();
  }

  void _applyError(Object error, {required bool clear}) {
    errorText = _describe(error);
    errorCode = error is ApiException ? error.code : null;
    if (clear) {
      rows.clear();
      state = LoadState.failed;
    } else {
      state = rows.isEmpty ? LoadState.failed : LoadState.ready;
    }
  }

  static String _describe(Object error) {
    if (error is ApiException) return error.display;
    return '$error';
  }

  /// 本地改一行（乐观更新用），不做服务端假设。
  void replaceAt(int index, T row) {
    if (index < 0 || index >= rows.length) return;
    rows[index] = row;
    notifyListeners();
  }

  void removeWhere(bool Function(T row) test) {
    rows.removeWhere(test);
    state = rows.isEmpty ? LoadState.empty : state;
    notifyListeners();
  }
}
