import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';

/// 单对象加载器（工作台汇总、财务概览、AI 配置这类一屏一份数据的接口）。
class ValueLoader<T> extends ChangeNotifier {
  ValueLoader(this._load);

  final Future<T> Function() _load;

  T? value;
  String? errorText;
  String? errorCode;
  bool loading = true;
  DateTime? loadedAt;

  Future<void> load() async {
    loading = true;
    errorText = null;
    errorCode = null;
    notifyListeners();
    try {
      value = await _load();
      loadedAt = DateTime.now();
    } on ApiException catch (error) {
      // 已有数据时失败只记错误、不清值：一次超时不该把用户正在看的整屏打回错误页。
      if (value == null) {
        errorText = error.display;
        errorCode = error.code;
      }
    } on Object catch (error) {
      if (value == null) errorText = '$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  static String describe(Object error) =>
      error is ApiException ? error.display : '$error';
}
