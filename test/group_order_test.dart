import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends XtreamClient {
  _FakeClient() : super(Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p'));

  @override
  Future<List<Item>> live() async => [
        for (final g in ['Haber', 'Sinema', 'Spor', 'Belgesel'])
          for (var i = 0; i < 2; i++) Item(id: 'l${g.hashCode}$i', name: '$g $i', logo: '', group: g, kind: Kind.live, url: 'u'),
      ];

  @override
  Future<List<Item>> movies() async => [];
  @override
  Future<List<Item>> series() async => [];
}

void main() {
  group('orderedGroups', () {
    test('ordered names first, the rest keep provider order', () {
      final s = AppSettings.instance..groupOrder = {'live': ['Spor', 'Haber']};
      expect(s.orderedGroups(Kind.live, ['Haber', 'Sinema', 'Spor', 'Belgesel']), ['Spor', 'Haber', 'Sinema', 'Belgesel']);
    });

    test('names that no longer exist are dropped, new ones appended', () {
      final s = AppSettings.instance..groupOrder = {'live': ['Eski', 'Spor']};
      expect(s.orderedGroups(Kind.live, ['Spor', 'Yeni']), ['Spor', 'Yeni']);
    });

    test('order is stored per kind', () {
      final s = AppSettings.instance..groupOrder = {'live': ['B']};
      expect(s.orderedGroups(Kind.movie, ['A', 'B']), ['A', 'B']);
    });
  });

  testWidgets('moving a category to the top reorders the sidebar and is persisted', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppSettings.instance
      ..tvMode = false
      ..groupOrder = {}
      ..hiddenGroups = {};

    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        client: _FakeClient(),
        info: AccountInfo(status: 'Active', maxConnections: 1),
        account: Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p'),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byIcon(Icons.tv));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(y('Haber') < y('Spor'), isTrue, reason: 'provider order first');

    await tester.tap(find.byTooltip('Kategorileri düzenle / gizle'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // the dialog lists Haber, Sinema, Spor, Belgesel: send "Spor" (3rd) to the top
    await tester.tap(find.byTooltip('En üste al').at(2));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(AppSettings.instance.groupOrder['live']!.first, 'Spor');

    await tester.tap(find.text('Tamam'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(y('Spor') < y('Haber'), isTrue, reason: 'Spor must now be above Haber in the sidebar');

    // saved to disk
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('groupOrder'), contains('Spor'));
  });

  testWidgets('hiding a category removes it from the sidebar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppSettings.instance
      ..tvMode = false
      ..groupOrder = {}
      ..hiddenGroups = {};

    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        client: _FakeClient(),
        info: AccountInfo(status: 'Active', maxConnections: 1),
        account: Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p'),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byIcon(Icons.tv));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Sinema'), findsWidgets);

    await tester.tap(find.byTooltip('Kategorileri düzenle / gizle'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byType(Checkbox).at(1)); // Sinema
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Tamam'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(AppSettings.instance.hiddenGroups, contains('live:Sinema'));
    expect(find.text('Sinema'), findsNothing);
  });
}
