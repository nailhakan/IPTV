import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/xtream.dart';

/// Serves a fake Xtream `player_api.php` that returns [userInfo].
Future<(HttpServer, XtreamClient)> _fake(Map<String, dynamic> userInfo) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({'user_info': userInfo}));
    req.response.close();
  });
  final client = XtreamClient(Account(name: 't', host: 'http://127.0.0.1:${server.port}', username: 'u', password: 'p'));
  return (server, client);
}

void main() {
  test('reports active/max connections and detects a full limit', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'exp_date': '1893456000', 'active_cons': '2', 'max_connections': '2'});
    final info = await client.authenticate();
    expect(info.activeConnections, 2);
    expect(info.maxConnections, 2);
    expect(info.limitReached, isTrue);
    expect(info.expiry, isNotNull);
    await server.close(force: true);
  });

  test('limit is not reached while a connection is free', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'active_cons': '1', 'max_connections': '2'});
    final info = await client.authenticate();
    expect(info.limitReached, isFalse);
    await server.close(force: true);
  });

  test('unknown limit (0) never counts as reached', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'active_cons': '3', 'max_connections': '0'});
    expect((await client.authenticate()).limitReached, isFalse);
    await server.close(force: true);
  });

  test('wrong credentials raise a clear error', () async {
    final (server, client) = await _fake({'auth': 0});
    expect(client.authenticate(), throwsA(isA<XtreamException>()));
    await server.close(force: true);
  });
}
