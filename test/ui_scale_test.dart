import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/ui_scale.dart';

Widget _app(double scale, VoidCallback onTap) => MaterialApp(
      builder: (context, child) => UiScale(scale: scale, child: child!),
      home: Scaffold(
        body: Stack(children: [
          // a button in every corner and the middle
          Align(alignment: Alignment.topLeft, child: TextButton(key: const Key('tl'), onPressed: onTap, child: const Text('tl'))),
          Align(alignment: Alignment.topRight, child: TextButton(key: const Key('tr'), onPressed: onTap, child: const Text('tr'))),
          Align(alignment: Alignment.bottomLeft, child: TextButton(key: const Key('bl'), onPressed: onTap, child: const Text('bl'))),
          Align(alignment: Alignment.bottomRight, child: TextButton(key: const Key('br'), onPressed: onTap, child: const Text('br'))),
        ]),
      ),
    );

void main() {
  dropdownTests();
  for (final scale in [0.5, 0.7, 1.0, 1.4]) {
    testWidgets('every corner stays clickable at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var taps = 0;
      await tester.pumpWidget(_app(scale, () => taps++));
      for (final key in ['tl', 'tr', 'bl', 'br']) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
      }
      expect(taps, 4, reason: 'all four corner buttons must receive taps');
    });

    testWidgets('content fills the window at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(scale, () {}));
      final br = tester.getBottomRight(find.byKey(const Key('br')));
      // bottom-right button hugs the bottom-right corner of the window
      expect(br.dx, closeTo(1200, 2));
      expect(br.dy, closeTo(800, 2));
    });
  }
}

void dropdownTests() {
  for (final scale in [0.5, 0.7, 1.4]) {
    testWidgets('dropdown opens and selects at scale $scale (even in the far corner)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var value = 'a';
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => UiScale(scale: scale, child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.bottomRight,
              child: DropdownButton<String>(
                key: const Key('dd'),
                value: value,
                items: const [DropdownMenuItem(value: 'a', child: Text('Birinci')), DropdownMenuItem(value: 'b', child: Text('İkinci'))],
                onChanged: (v) => setState(() => value = v!),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('dd')));
      await tester.pumpAndSettle();
      expect(find.text('İkinci'), findsOneWidget, reason: 'menu must open');
      await tester.tap(find.text('İkinci').last);
      await tester.pumpAndSettle();
      expect(value, 'b');
    });
  }
}
