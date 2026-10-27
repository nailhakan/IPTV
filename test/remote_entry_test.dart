import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/remote_entry.dart';

void main() {
  test('phone form is served and submission reaches the callback', () async {
    final server = RemoteEntryServer();
    Map<String, String>? received;
    final url = await server.start((d) => received = d);
    expect(url, isNotNull);

    final client = HttpClient();
    final base = Uri(scheme: 'http', host: '127.0.0.1', port: url!.port, path: url.path);

    final get = await (await client.getUrl(base)).close();
    expect(get.statusCode, 200);
    expect(await utf8.decoder.bind(get).join(), contains('name="password"'));

    final post = await client.postUrl(base);
    post.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    post.write('name=Ev&host=http%3A%2F%2Fexample.com%3A8080&username=u+1&password=p%26w');
    final res = await post.close();
    expect(res.statusCode, 200);
    await res.drain<void>();

    expect(received, {'name': 'Ev', 'host': 'http://example.com:8080', 'username': 'u 1', 'password': 'p&w'});

    // wrong token is rejected
    final bad = await (await client.getUrl(base.replace(path: '/wrong'))).close();
    expect(bad.statusCode, 404);
    await bad.drain<void>();

    client.close();
    await server.stop();
  });
}
