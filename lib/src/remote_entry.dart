import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Tiny one-shot web server on the local network. The TV shows a QR code; the user opens the page
/// on a phone/PC, types the login there and it is sent back, so nothing has to be typed with a remote.
class RemoteEntryServer {
  HttpServer? _server;
  final String token = newToken();

  static String newToken() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Best guess of this device's address on the home network.
  static Future<String?> localAddress() async {
    final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final candidates = [for (final i in all) for (final a in i.addresses) if (!a.isLoopback) a.address];
    for (final prefix in ['192.168.', '10.', '172.']) {
      for (final a in candidates) {
        if (a.startsWith(prefix)) return a;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<Uri?> start(void Function(Map<String, String>) onSubmit) async {
    final ip = await localAddress();
    if (ip == null) return null;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((req) async {
      final path = req.uri.path;
      try {
        if (req.method == 'GET' && path == '/$token') {
          _html(req, _form());
        } else if (req.method == 'POST' && path == '/$token') {
          final body = await utf8.decoder.bind(req).join().timeout(const Duration(seconds: 10));
          if (body.length > 4096) {
            req.response.statusCode = HttpStatus.requestEntityTooLarge;
            await req.response.close();
            return;
          }
          final data = Uri.splitQueryString(body);
          _html(req, _page('<h2>Gönderildi ✓</h2><p>Giriş bilgileri TV\'ye iletildi. Bu sayfayı kapatabilirsin.</p>'));
          onSubmit(data);
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      } catch (_) {
        try {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
        } catch (_) {}
      }
    });
    return Uri(scheme: 'http', host: ip, port: server.port, path: '/$token');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static void _html(HttpRequest req, String body) {
    req.response.headers.contentType = ContentType.html;
    req.response.write(body);
    req.response.close();
  }

  static String _page(String inner) => '''<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>IPTV giriş</title>
<style>body{font-family:system-ui,sans-serif;background:#16151a;color:#eee;margin:0;padding:24px;max-width:420px;margin:auto}
input,button{width:100%;box-sizing:border-box;padding:14px;margin:8px 0;border-radius:10px;border:1px solid #555;background:#222;color:#fff;font-size:17px}
button{background:#6c5ce7;border:0;font-weight:600}h2{margin-top:32px}</style></head><body>$inner</body></html>''';

  static String _form() => _page('''<h2>IPTV giriş bilgileri</h2>
<form method="post" autocomplete="off">
<input name="name" placeholder="Ad (isteğe bağlı)">
<input name="host" placeholder="Sunucu (http://example.com:8080)" autocapitalize="off" autocorrect="off" required>
<input name="username" placeholder="Kullanıcı adı" autocapitalize="off" autocorrect="off" required>
<input name="password" type="password" placeholder="Parola" autocapitalize="off" autocorrect="off" required>
<button type="submit">TV'ye gönder</button></form>''');
}

/// Shows the QR code and waits for the phone to submit. Pops with the submitted fields.
class RemoteEntryDialog extends StatefulWidget {
  const RemoteEntryDialog({super.key});

  @override
  State<RemoteEntryDialog> createState() => _RemoteEntryDialogState();
}

class _RemoteEntryDialogState extends State<RemoteEntryDialog> {
  final _server = RemoteEntryServer();
  Uri? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server.start((data) {
      if (mounted) Navigator.of(context).pop(data);
    }).then((u) {
      if (!mounted) return;
      setState(() {
        _url = u;
        if (u == null) _error = 'Ağ adresi bulunamadı. Wi-Fi/Ethernet bağlı mı?';
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Sunucu başlatılamadı: $e');
    });
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Telefondan giriş'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) Text(_error!),
          if (_url == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          if (_url != null) ...[
            const Text('Telefonun kamerasıyla okut (telefon ve bu cihaz aynı Wi-Fi/ağda olmalı):', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(data: _url.toString(), size: 190, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            SelectableText(_url.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Bilgiler yalnızca yerel ağda iletilir.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
          ],
        ])),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('İptal'))],
    );
  }
}
