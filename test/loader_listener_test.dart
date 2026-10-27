import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/state/value_loader.dart';

void main() {
  testWidgets('listener added in initState repaints when load() notifies',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Probe())));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('done'), findsOneWidget);
  });

  // 「我的」页的经营数字卡踩到的坑：ListView 的子项滚出可视区 + cacheExtent 会被销毁，
  // 所以异步取数必须由常驻的父级 State 持有，否则每滑回来都重发一次请求、重铺一次骨架屏。
  testWidgets('a list item owning its loader re-fetches on scroll; a shared loader does not',
      (WidgetTester tester) async {
    final List<int> selfOwnedFetches = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            _SelfOwnedItem(fetches: selfOwnedFetches),
            for (int i = 0; i < 12; i++) const SizedBox(height: 220),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(selfOwnedFetches.length, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2400));
    await tester.pumpAndSettle();
    expect(selfOwnedFetches.length, 2, reason: '子项自建 loader：滚回来时 State 重建，又取了一次数');

    final List<int> sharedFetches = <int>[];
    final ValueLoader<int> shared =
        ValueLoader<int>(() async {
      sharedFetches.add(1);
      return 7;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            _SharedItem(loader: shared),
            for (int i = 0; i < 12; i++) const SizedBox(height: 220),
          ],
        ),
      ),
    ));
    await shared.load();
    await tester.pumpAndSettle();
    expect(sharedFetches.length, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2400));
    await tester.pumpAndSettle();
    expect(sharedFetches.length, 1, reason: 'loader 常驻父级：子项重建不会再取数');
    shared.dispose();
  });
}

class _SelfOwnedItem extends StatefulWidget {
  const _SelfOwnedItem({required this.fetches});

  final List<int> fetches;

  @override
  State<_SelfOwnedItem> createState() => _SelfOwnedItemState();
}

class _SelfOwnedItemState extends State<_SelfOwnedItem> {
  late final ValueLoader<int> _loader = ValueLoader<int>(() async {
    widget.fetches.add(1);
    return 7;
  });

  @override
  void initState() {
    super.initState();
    _loader.load();
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 120, child: Text('self'));
  }
}

class _SharedItem extends StatelessWidget {
  const _SharedItem({required this.loader});

  final ValueLoader<int> loader;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loader,
      builder: (BuildContext context, Widget? _) =>
          SizedBox(height: 120, child: Text('shared ${loader.value ?? 0}')),
    );
  }
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final ValueLoader<String> _loader =
      ValueLoader<String>(() async => 'done');

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loader.addListener(_repaint);
    _loader.load();
  }

  @override
  void dispose() {
    _loader.removeListener(_repaint);
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_loader.loading ? 'loading' : '${_loader.value}');
  }
}
