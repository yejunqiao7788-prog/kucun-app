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
  bool stale = false;
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
      errorText = error.display;
      errorCode = error.code;
    } on Object catch (error) {
      errorText = '$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  static String describe(Object error) =>
      error is ApiException ? error.display : '$error';
}
