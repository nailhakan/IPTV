import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/accounts.dart';
import 'package:iptv_app/src/login_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = Account(name: 'Ev', host: 'http://a.example:8080', username: 'ua', password: 'pa');
final _b = Account(name: 'Ofis', host: 'http://b.example:8080', username: 'ub', password: 'pb');

class _Fake extends XtreamClient {
  _Fake(super.acc, this.log, {this.gate, this.fail = false});

  final List<String> log;
  final Completer<void>? gate;
  final bool fail;

  @override
  Future<AccountInfo> authenticate() async {
    log.add(acc.name);
    await gate?.future;
    if (fail) throw XtreamException('Sunucuya erişilemiyor');
    return AccountInfo(status: 'Active', maxConnections: 1);
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<List<String>> _pump(WidgetTester tester, {required bool auto, List<Account> saved = const [], String? last, Completer<void>? gate, bool fail = false}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  AppSettings.instance.tvMode = false;
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    if (saved.isNotEmpty) await AccountStore.save(saved);
    if (last != null) await AccountStore.saveLast(last);
  });
  final log = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: LoginPage(
      autoLogin: auto,
      clientFactory: (a) => _Fake(a, log, gate: gate, fail: fail),
      homeBuilder: (c, i, a) => Builder(builder: (ctx) => Scaffold(body: Column(children: [Text('HOME ${a.name}'), BackButton(onPressed: () => Navigator.of(ctx).pop())]))),
    ),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _settle(tester);
  return log;
}

void main() {
  testWidgets('auto-login signs in the last used account without showing the login form', (tester) async {
    final log = await _pump(tester, auto: true, saved: [_a, _b], last: _b.key);
    expect(find.text('HOME Ofis'), findsOneWidget);
    expect(log, ['Ofis']);
  });

  testWidgets('without autoLogin the profile cards are shown and nothing is signed in', (tester) async {
    final log = await _pump(tester, auto: false, saved: [_a, _b], last: _a.key);
    expect(find.text('Kullanıcı seç'), findsOneWidget);
    expect(find.text('Ev'), findsOneWidget);
    expect(find.text('Ofis'), findsOneWidget);
    expect(find.text('Son kullanılan'), findsOneWidget);
    expect(log, isEmpty);
    await tester.tap(find.text('Ofis'));
    await _settle(tester);
    expect(find.text('HOME Ofis'), findsOneWidget);
  });

  testWidgets('last used account is listed first', (tester) async {
    await _pump(tester, auto: false, saved: [_a, _b], last: _b.key);
    expect(tester.getTopLeft(find.text('Ofis')).dx < tester.getTopLeft(find.text('Ev')).dx, isTrue);
  });

  testWidgets('first run (no accounts) shows the form directly', (tester) async {
    await _pump(tester, auto: true);
    expect(find.text('Giriş bilgilerinizi girin'), findsOneWidget);
    expect(find.text('Kullanıcı Ekle'), findsOneWidget);
  });

  testWidgets('cancelling the auto-login stays on the profile page even if the server answers later', (tester) async {
    final gate = Completer<void>();
    await _pump(tester, auto: true, saved: [_a], last: _a.key, gate: gate);
    expect(find.textContaining('giriş yapılıyor'), findsOneWidget);
    await tester.tap(find.text('Vazgeç / kullanıcı değiştir'));
    await _settle(tester, 3);
    expect(find.text('Kullanıcı seç'), findsOneWidget);
    gate.complete();
    await _settle(tester);
    expect(find.textContaining('HOME'), findsNothing);
    expect(find.text('Kullanıcı seç'), findsOneWidget);
  });

  testWidgets('a failed auto-login falls back to the profiles with the error', (tester) async {
    await _pump(tester, auto: true, saved: [_a], last: _a.key, fail: true);
    expect(find.text('Kullanıcı seç'), findsOneWidget);
    expect(find.text('Sunucuya erişilemiyor'), findsOneWidget);
  });

  testWidgets('switching user (leaving the app) does not auto-login again', (tester) async {
    final log = await _pump(tester, auto: true, saved: [_a], last: _a.key);
    expect(find.text('HOME Ev'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(find.text('Kullanıcı seç'), findsOneWidget);
    expect(log, ['Ev'], reason: 'must not authenticate a second time');
  });

  testWidgets('delete mode removes a profile after confirmation', (tester) async {
    await _pump(tester, auto: false, saved: [_a, _b], last: _a.key);
    await tester.tap(find.text('Kullanıcıları düzenle'));
    await _settle(tester, 3);
    await tester.tap(find.text('Ofis'));
    await _settle(tester, 5);
    expect(find.text('Kullanıcı silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Sil'));
    await _settle(tester, 5);
    expect(find.text('Ofis'), findsNothing);
    expect(find.text('Ev'), findsOneWidget);
    final left = await tester.runAsync(AccountStore.load);
    expect(left!.map((a) => a.name), ['Ev']);
  });
}
