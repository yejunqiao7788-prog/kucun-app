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
