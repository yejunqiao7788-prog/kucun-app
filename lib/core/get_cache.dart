/// 进程内 GET 记忆，形状抄网页端 `hooks/useAsyncLoad.ts` 的 `staleTime`。
///
/// 为什么要它：根标签是 IndexedStack，开机那几个签一起建，同一支低频接口（分类、客户、
/// 价目表、打印设置）会被打两遍；从模块退回再进又是新的一轮转圈。网页端靠 60 秒新鲜期
/// 把这些重复请求吃掉，读到的还是同一份数据。
///
/// 两遍一起发的时候新鲜期还没建立，所以再加一层"同键合流"：并发的那几个 awaiter 共用一次
/// 请求。合流只覆盖同一支接口，不同接口该并发还是并发。
///
/// 键带租户前缀（`keyFor`），登出与换账号时整表作废：留在内存里的是上一个租户的数据。
/// 写操作成功也整表作废——宁可多发一次 GET，不让界面拿着改之前的数显示。
class GetCache {
  GetCache._();

  static final GetCache instance = GetCache._();

  /// 和网页端默认值一致：60 秒内算新鲜，不重发请求。
  static const Duration staleTime = Duration(seconds: 60);

  /// 上限照抄网页端的 CACHE_MAX_SIZE；到顶淘汰最旧的一条，不整表清空。
  static const int _maxEntries = 100;

  final Map<String, _CachedValue> _entries = <String, _CachedValue>{};
  final Map<String, Future<Object?>> _pending = <String, Future<Object?>>{};

  /// 作废计数：出发去读的那次如果在途时表被清过（写成功、登出、下拉刷新），
  /// 这份响应就是改之前的，不能再塞回缓存。
  int _generation = 0;

  /// 仓储层与界面共用这一个键形状：`refresh()` 要作废的正是 `categories()` 写过的那条。
  static String keyFor(String tenantId, String name) => '$tenantId#$name';

  /// 新鲜才给值；过期或没有都返回 null，让调用方照常打接口。
  Object? peek(String key) {
    final _CachedValue? hit = _entries[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.stamp) >= staleTime) return null;
    return hit.value;
  }

  void put(String key, Object? value) {
    if (_entries.length >= _maxEntries) _evictOldest();
    _entries[key] = _CachedValue(value, DateTime.now());
  }

  void drop(String key) {
    _pending.remove(key);
    _entries.remove(key);
    _generation += 1;
  }

  void dropAll() {
    _pending.clear();
    _entries.clear();
    _generation += 1;
  }

  /// 读一支接口的唯一入口：命中新鲜值就直接给，否则打接口，并让同时在途的调用共用这一次。
  ///
  /// 出错的合流不会留下痕迹（`finally` 里删掉），否则一次超时会把错误钉在键上，
  /// 后面每次进屏都拿到同一个旧异常、再也不重试。
  Future<T> remember<T>(String key, Future<T> Function() load) {
    final Object? hit = peek(key);
    if (hit is T) return Future<T>.value(hit);
    final Future<Object?>? flying = _pending[key];
    if (flying != null) return flying.then<T>((Object? value) => value as T);
    final Future<Object?> future = _start(key, load);
    _pending[key] = future;
    return future.then<T>((Object? value) => value as T);
  }

  Future<Object?> _start(String key, Future<Object?> Function() load) async {
    final int generation = _generation;
    try {
      final Object? value = await load();
      if (generation == _generation) put(key, value);
      return value;
    } finally {
      // 无条件删：这一路走完时，留在键上的只会是自己，或者是一次已经作废过本条的
      // `drop` 之后新起的请求。后者最多多发一次 GET，不值得为它加身份比对。
      _pending.remove(key);
    }
  }

  void _evictOldest() {
    String? oldestKey;
    DateTime? oldestStamp;
    for (final MapEntry<String, _CachedValue> entry in _entries.entries) {
      if (oldestStamp == null || entry.value.stamp.isBefore(oldestStamp)) {
        oldestKey = entry.key;
        oldestStamp = entry.value.stamp;
      }
    }
    if (oldestKey != null) _entries.remove(oldestKey);
  }
}

class _CachedValue {
  const _CachedValue(this.value, this.stamp);

  final Object? value;
  final DateTime stamp;
}
