/// JSON 行的宽松读取视图。服务端加字段不需要发版客户端，缺字段按 null/默认处理。
class JsonMap {
  const JsonMap(this.json);

  final Map<String, Object?> json;

  static const JsonMap empty = JsonMap(<String, Object?>{});

  static JsonMap from(Object? source) => JsonMap(normalize(source));

  static List<JsonMap> listOf(Object? source, List<String> keys) =>
      rawListOf(source, keys).map((Map<String, Object?> row) => JsonMap(row)).toList(growable: false);

  /// 出参里的行集合位置不唯一（顶层数组 / `data` / 资源名），统一按候选键取第一个命中的。
  static List<Map<String, Object?>> rawListOf(Object? source, List<String> keys) {
    if (source is List) {
      return source.map(normalize).toList(growable: false);
    }
    final Map<String, Object?> map = normalize(source);
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is List) {
        return value.map(normalize).toList(growable: false);
      }
    }
    return const <Map<String, Object?>>[];
  }

  /// 详情接口常见 `{order:…, items:[…]}` 拆分形状，合并成一行可读实体。
  static JsonMap mergeFrom(Object? source, String innerKey, String listKey) {
    final JsonMap map = JsonMap.from(source);
    final Object? inner = map.raw(innerKey);
    if (inner is Map) {
      final Map<String, Object?> merged = <String, Object?>{...normalize(inner)};
      if (!merged.containsKey(listKey) && map.raw(listKey) != null) {
        merged[listKey] = map.raw(listKey);
      }
      return JsonMap(merged);
    }
    return map;
  }

  Object? raw(String key) => json[key];

  String? asString(String key) {
    final Object? value = json[key];
    if (value == null) return null;
    return '$value';
  }

  String asStringOr(String key, String fallback) => asString(key) ?? fallback;

  double? asDouble(String key) {
    final Object? value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double asDoubleOr(String key, double fallback) => asDouble(key) ?? fallback;

  int? asInt(String key) {
    final Object? value = json[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    return null;
  }

  int asIntOr(String key, int fallback) => asInt(key) ?? fallback;

  bool asBool(String key, {bool fallback = false}) {
    final Object? value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == 'true' || value == '1';
    return fallback;
  }

  DateTime? asDate(String key) {
    final String? value = asString(key);
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  JsonMap asMap(String key) => JsonMap.from(json[key]);

  List<JsonMap> asList(String key) => listOf(json[key], const <String>[]);

  /// 实体构造器收的是裸 Map（继承 JsonMap 的 super 参数），所以行数组要绕开 asList 那层包装。
  List<R> asEntities<R>(String key, R Function(Map<String, Object?> row) build) =>
      rawListOf(json[key], const <String>[]).map(build).toList(growable: false);

  List<Map<String, Object?>> asRawList(String key) =>
      rawListOf(json[key], const <String>[]);

  List<String> asStringList(String key) {
    final Object? value = json[key];
    if (value is List) {
      return value
          .where((Object? item) => item != null)
          .map((Object? item) => '$item')
          .toList(growable: false);
    }
    return const <String>[];
  }

  Map<String, bool> asBoolMap(String key) {
    final JsonMap value = asMap(key);
    return value.json.map(
      (String k, Object? v) => MapEntry<String, bool>(
        k,
        v == true || v == 1 || v == 'true',
      ),
    );
  }
}

/// JSON 反序列化结果的键类型不保证是 String，这里统一收口成可读 Map。
Map<String, Object?> normalize(Object? source) {
  if (source is Map) {
    return source.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  return <String, Object?>{};
}
