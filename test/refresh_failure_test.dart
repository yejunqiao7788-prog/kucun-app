import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kucun_app/design/widgets/state_views.dart';
import 'package:kucun_app/state/value_loader.dart';

/// 下拉刷新失败过去是静默的：`ValueLoader` 只在没有值时记错误，旧值还在就什么都不留，
/// 屏幕看着正常，其实已经不更新了。这里同时验加载器的记账和界面把它换成横幅。
void main() {
  ValueLoader<int> buildLoader() {
    int attempt = 0;
    return ValueLoader<int>(() async {
      attempt++;
      if (attempt > 1) throw StateError('timeout');
      return 7;
    });
  }

  test('刷新失败保留旧值，但错误照常记下', () async {
    final ValueLoader<int> loader = buildLoader();
    await loader.load();
    expect(loader.value, 7);
    expect(loader.errorText, isNull);

    await loader.refresh();
    expect(loader.value, 7, reason: '一次失败不该把整屏数据打回空');
    expect(loader.hasValue, isTrue);
    expect(loader.errorText, contains('timeout'));
    loader.dispose();
  });

  testWidgets('有旧值时刷新失败挂横幅，而不是换成错误页', (WidgetTester tester) async {
    int attempt = 0;
    final ValueLoader<int> loader = ValueLoader<int>(() async {
      attempt++;
      if (attempt == 2) throw StateError('timeout');
      return 7;
    });
    await loader.load();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: loader,
          builder: (BuildContext context, Widget? _) =>
              Column(children: <Widget>[RefreshFailureBanner.stale(loader)]),
        ),
      ),
    ));
    expect(find.byType(NoticeBanner), findsNothing);

    await loader.refresh();
    await tester.pump();
    expect(find.textContaining('timeout'), findsOneWidget);
    expect(find.byType(AppErrorView), findsNothing);

    // 重试成功后横幅消失，不用退出重进。
    await loader.refresh();
    await tester.pump();
    expect(find.byType(NoticeBanner), findsNothing);

    loader.dispose();
  });
}
