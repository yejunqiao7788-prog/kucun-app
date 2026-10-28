import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/get_cache.dart';

/// 单对象加载器（工作台汇总、财务概览、AI 配置这类一屏一份数据的接口）。
///
/// [cacheKey] 指向 `GetCache` 里那条 60 秒记忆（形状和仓储层 `_cached` 用的同一个键）。
/// 首次进屏照常吃缓存、秒显；下拉刷新必须绕过去，所以 `refresh()` 先把这条作废。
class ValueLoader<T> extends ChangeNotifier {
  ValueLoader(this._load, {this.cacheKey});

  final Future<T> Function() _load;
  final String? cacheKey;

  T? value;
  String? errorText;
  String? errorCode;
  bool loading = true;
  DateTime? loadedAt;

  /// 屏幕上还有可读的旧值：这时失败该挂横幅，不该整屏换成错误页。
  bool get hasValue => value != null;

  Future<void> load() async {
    loading = true;
    errorText = null;
    errorCode = null;
    notifyListeners();
    try {
      value = await _load();
      loadedAt = DateTime.now();
    } on ApiException catch (error) {
      // 失败只记错误、不清值：一次超时不该把用户正在看的整屏打回错误页。
      // 但错误必须照常留下——旧值还在时若不记，这次下拉刷新失败就悄无声息，
      // 用户会一直当屏幕上的数据是最新的。
      errorText = error.display;
      errorCode = error.code;
    } on Object catch (error) {
      errorText = '$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final String? key = cacheKey;
    if (key != null) GetCache.instance.drop(key);
    await load();
  }

  static String describe(Object error) =>
      error is ApiException ? error.display : '$error';
}
