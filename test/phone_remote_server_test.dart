import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/phone_remote.dart';

void main() {
  group('PhoneRemoteServer', () {
    late PhoneRemoteServer server;
    late Uri url;
    final keys = <String>[];
    final texts = <(String, bool)>[];
    var backs = 0;

    setUp(() async {
      keys.clear();
      texts.clear();
      backs = 0;
      server = PhoneRemoteServer(
        onKey: keys.add,
        onText: (t, {bool submit = false}) {
          texts.add((t, submit));
          return t != 'nofield';
        },
        onBack: () => backs++,
      );
      url = (await server.start())!;
    });
    tearDown(() => server.stop());

    Future<(int, String)> call(String method, String path, [Object? body]) async {
      final c = HttpClient();
      final u = Uri(scheme: 'http', host: '127.0.0.1', port: url.port, path: path);
      final req = method == 'GET' ? await c.getUrl(u) : await c.postUrl(u);
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      c.close();
      return (res.statusCode, text);
    }

    test('serves the remote page', () async {
      final (code, html) = await call('GET', url.path);
      expect(code, 200);
      expect(html, contains('IPTV Kumanda'));
      expect(html, contains("k('ok')"));
    });

    test('key presses reach the app, unknown keys are refused', () async {
      expect((await call('POST', '${url.path}/key', {'key': 'down'})).$1, 200);
      expect((await call('POST', '${url.path}/key', {'key': 'ok'})).$1, 200);
      expect((await call('POST', '${url.path}/key', {'key': 'rm -rf'})).$1, 400);
      expect(keys, ['down', 'ok']);
    });

    test('text is forwarded and the result tells whether a field was focused', () async {
      final ok = await call('POST', '${url.path}/text', {'text': 'bein sports', 'submit': true});
      expect(jsonDecode(ok.$2), {'ok': true});
      final none = await call('POST', '${url.path}/text', {'text': 'nofield'});
      expect(jsonDecode(none.$2), {'ok': false});
      expect(texts.first, ('bein sports', true));
    });

    test('back button', () async {
      await call('POST', '${url.path}/back');
      expect(backs, 1);
    });

    test('a wrong token is rejected and nothing is executed', () async {
      expect((await call('POST', '/wrong/key', {'key': 'up'})).$1, 404);
      expect((await call('GET', '/wrong')).$1, 404);
      expect(keys, isEmpty);
    });

    test('malformed JSON does not crash the server', () async {
      final c = HttpClient();
      final req = await c.postUrl(Uri(scheme: 'http', host: '127.0.0.1', port: url.port, path: '${url.path}/key'));
      req.write('{not json');
      expect((await req.close()).statusCode, 400);
      c.close();
      expect((await call('GET', url.path)).$1, 200);
    });
  });
}
