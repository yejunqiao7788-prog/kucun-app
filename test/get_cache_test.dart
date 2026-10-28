import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/core/get_cache.dart';
import 'package:kucun_app/state/value_loader.dart';

void main() {
  setUp(GetCache.instance.dropAll);

  test('同一支读在新鲜期内只打一次，refresh 才会绕过去', () async {
    int fetches = 0;
    final String key = GetCache.keyFor('t1', 'categories');
    Future<List<String>> load() async {
      fetches += 1;
      return <String>['A'];
    }

    final ValueLoader<List<String>> loader = ValueLoader<List<String>>(
      () => GetCache.instance.remember<List<String>>(key, load),
      cacheKey: key,
    );

    await loader.load();
    await loader.load();
    expect(fetches, 1, reason: '60 秒内重复进屏不该再打接口');
    expect(loader.value, <String>['A']);

    await loader.refresh();
    expect(fetches, 2, reason: '下拉刷新必须绕开新鲜期，否则永远刷不出新数据');
    loader.dispose();
  });

  test('开机几个签一起建时，同键的并发读合流成一次请求', () async {
    int fetches = 0;
    final Completer<List<String>> gate = Completer<List<String>>();
    final String key = GetCache.keyFor('t1', 'customers');
    Future<List<String>> load() {
      fetches += 1;
      return gate.future;
    }

    final Future<List<String>> a =
        GetCache.instance.remember<List<String>>(key, load);
    final Future<List<String>> b =
        GetCache.instance.remember<List<String>>(key, load);
    gate.complete(<String>['张三']);
    expect(await a, <String>['张三']);
    expect(await b, <String>['张三']);
    expect(fetches, 1);
    // 合流结束后键上要留的是值，不是那次已完成的 future，否则下一次进屏还得等它。
    expect(GetCache.instance.peek(key), <String>['张三']);
  });

  test('失败不留痕：下一次进屏照常重试', () async {
    int fetches = 0;
    final String key = GetCache.keyFor('t1', 'plans');
    Future<List<String>> load() async {
      fetches += 1;
      if (fetches == 1) throw Exception('超时');
      return <String>['¥199'];
    }

    await expectLater(
        GetCache.instance.remember<List<String>>(key, load), throwsA(anything));
    expect(GetCache.instance.peek(key), isNull);
    expect(await GetCache.instance.remember<List<String>>(key, load),
        <String>['¥199']);
    expect(fetches, 2);
  });

  test('在途时写成功整表作废，那份旧响应不许塞回缓存', () async {
    final String key = GetCache.keyFor('t1', 'print_settings');
    final Completer<List<String>> gate = Completer<List<String>>();
    final Future<List<String>> flying =
        GetCache.instance.remember<List<String>>(key, () => gate.future);
    // 写接口的成功回调就是在这里跑的 dropAll：它比在途的 GET 后完成。
    GetCache.instance.dropAll();
    gate.complete(<String>['旧值']);
    expect(await flying, <String>['旧值'], reason: '已经发出去的请求该把结果给回去');
    expect(GetCache.instance.peek(key), isNull,
        reason: '但作废之后落进来的旧值不能留在表里');
  });

  test('键带租户前缀；类型不符当没命中', () async {
    GetCache.instance.put(GetCache.keyFor('t1', 'list'), <int>[1]);
    expect(GetCache.instance.peek(GetCache.keyFor('t2', 'list')), isNull,
        reason: '换租户不能读到上一个租户的数据');
    expect(GetCache.instance.peek(GetCache.keyFor('t1', 'other')), isNull);

    // 同名不同形状：脏命中比多发一次 GET 危险。
    final Object? hit = GetCache.instance.peek(GetCache.keyFor('t1', 'list'));
    expect(hit is List<String>, isFalse);

    expect(
        await GetCache.instance.remember<List<String>>(
            GetCache.keyFor('t1', 'list'), () async => <String>['A']),
        <String>['A']);
  });

  test('到上限淘汰最旧的一条，不是整表清空', () {
    for (int i = 0; i < 100; i++) {
      GetCache.instance.put('old$i', i);
    }
    GetCache.instance.put('fresh', 'F');
    expect(GetCache.instance.peek('fresh'), 'F');
    expect(GetCache.instance.peek('old0'), isNull);
  });
}
