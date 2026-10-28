import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_nav.dart';
import 'remote_entry.dart';

/// (logical key, physical key, typed character) for every key the phone remote may press.
final Map<String, (LogicalKeyboardKey, PhysicalKeyboardKey, String?)> _keys = {
  'up': (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp, null),
  'down': (LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown, null),
  'left': (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft, null),
  'right': (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight, null),
  'ok': (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter, null),
  'space': (LogicalKeyboardKey.space, PhysicalKeyboardKey.space, ' '),
  'mute': (LogicalKeyboardKey.keyM, PhysicalKeyboardKey.keyM, 'm'),
  'fullscreen': (LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF, 'f'),
};

bool isRemoteKey(String name) => _keys.containsKey(name);

/// Presses and releases [name] as if it came from a real keyboard / TV remote, so the focus
/// traversal, shortcuts and the player's own key handling all react exactly as they do for the real thing.
///
/// Sending raw `KeyData` would not work (Flutter holds it back until the matching raw message of a real key
/// press arrives), so the event is delivered the way the focus system does it: from the focused node up
/// through its ancestors until one of them handles it.
void injectKey(String name) {
  final k = _keys[name];
  if (k == null) return;

  void send(KeyEvent event) {
    // Shortcuts look at the set of pressed keys, so keep HardwareKeyboard in sync.
    HardwareKeyboard.instance.handleKeyEvent(event);
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return;
    for (final node in <FocusNode>[focused, ...focused.ancestors]) {
      final result = node.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
      if (result == KeyEventResult.handled || result == KeyEventResult.skipRemainingHandlers) break;
    }
  }

  final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  send(KeyDownEvent(physicalKey: k.$2, logicalKey: k.$1, character: k.$3, timeStamp: now));
  send(KeyUpEvent(physicalKey: k.$2, logicalKey: k.$1, timeStamp: now));
}

/// Replaces the content of the text field that currently has focus. Returns false if no field is focused.
bool applyTextToFocusedField(String text, {bool submit = false}) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final state = ctx?.findAncestorStateOfType<EditableTextState>();
  if (state == null) return false;
  state.userUpdateTextEditingValue(
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
    SelectionChangedCause.keyboard,
  );
  if (submit) state.widget.onSubmitted?.call(text);
  return true;
}

void goBack() => appNavigatorKey.currentState?.maybePop();

/// Small LAN web server: phone browser -> remote control page. Only started when the user enables it.
class PhoneRemoteServer {
  PhoneRemoteServer({this.onKey = injectKey, this.onText = applyTextToFocusedField, this.onBack = goBack});

  final void Function(String key) onKey;
  final bool Function(String text, {bool submit}) onText;
  final VoidCallback onBack;

  HttpServer? _server;
  final String token = RemoteEntryServer.newToken();

  Future<Uri?> start() async {
    final ip = await RemoteEntryServer.localAddress();
    if (ip == null) return null;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle);
    return Uri(scheme: 'http', host: ip, port: server.port, path: '/$token');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/$token') {
        res.headers.contentType = ContentType.html;
        res.write(_page);
      } else if (req.method == 'POST' && path.startsWith('/$token/')) {
        final raw = await utf8.decoder.bind(req).join().timeout(const Duration(seconds: 5));
        if (raw.length > 4096) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
        } else {
          final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
          switch (path.substring(token.length + 2)) {
            case 'key':
              final key = '${body['key']}';
              if (isRemoteKey(key)) {
                onKey(key);
              } else {
                res.statusCode = HttpStatus.badRequest;
              }
            case 'text':
              final ok = onText('${body['text'] ?? ''}', submit: body['submit'] == true);
              res.write(jsonEncode({'ok': ok}));
            case 'back':
              onBack();
            default:
              res.statusCode = HttpStatus.notFound;
          }
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      res.statusCode = HttpStatus.badRequest;
    } finally {
      await res.close();
    }
  }
}

/// App-wide switch for the phone remote (started from main() and from the settings page).
class PhoneRemote extends ChangeNotifier {
  PhoneRemote._();
  static final PhoneRemote instance = PhoneRemote._();

  PhoneRemoteServer? _server;
  Uri? url;
  String? error;

  bool get running => _server != null;

  Future<void> setEnabled(bool on) async {
    if (on == running) return;
    if (!on) {
      await _server?.stop();
      _server = null;
      url = null;
      error = null;
    } else {
      final server = PhoneRemoteServer();
      try {
        final u = await server.start();
        if (u == null) {
          error = 'Ağ adresi bulunamadı. Wi-Fi/Ethernet bağlı mı?';
        } else {
          _server = server;
          url = u;
          error = null;
        }
      } catch (e) {
        error = 'Kumanda sunucusu başlatılamadı: $e';
      }
    }
    notifyListeners();
  }
}

String get _page => '''<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no"><title>IPTV Kumanda</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{font-family:system-ui,sans-serif;background:#16151a;color:#eee;margin:0;padding:18px;max-width:420px;margin:auto;user-select:none}
h1{font-size:18px;text-align:center;margin:6px 0 16px;color:#b9b0ff}
.pad{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
button{font-size:20px;padding:18px 0;border-radius:14px;border:0;background:#2a2833;color:#fff}
button:active{background:#6c5ce7;transform:scale(.97)}
.ok{background:#6c5ce7;font-weight:700}
.row{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}
.row.two{grid-template-columns:repeat(2,1fr)}
small{display:block;text-align:center;color:#8a879a;margin:18px 0 6px}
.txt{display:flex;gap:8px;margin-top:6px}
input{flex:1;font-size:17px;padding:14px;border-radius:12px;border:1px solid #444;background:#222;color:#fff;min-width:0;user-select:text}
.txt button{padding:0 16px;font-size:15px;white-space:nowrap}
#st{text-align:center;color:#8a879a;font-size:12px;height:16px;margin-top:10px}
</style></head><body>
<h1>IPTV Kumanda</h1>
<div class="pad">
<span></span><button onclick="k('up')">▲</button><span></span>
<button onclick="k('left')">◀</button><button class="ok" onclick="k('ok')">OK</button><button onclick="k('right')">▶</button>
<button onclick="b()">↩︎ Geri</button><button onclick="k('down')">▼</button><span></span>
</div>
<small>Oynatıcı</small>
<div class="row"><button onclick="k('left')">⏪</button><button onclick="k('space')">⏯</button><button onclick="k('right')">⏩</button></div>
<div class="row two"><button onclick="k('mute')">🔇 Sessiz</button><button onclick="k('fullscreen')">⛶ Tam ekran</button></div>
<small>Yazı yaz (seçili kutuya)</small>
<div class="txt"><input id="t" placeholder="Ara / yaz..." autocomplete="off" autocapitalize="off">
<button onclick="s(false)">Yaz</button><button onclick="s(true)">Yaz + OK</button></div>
<div id="st"></div>
<script>
const base=location.pathname;
function post(p,d){if(navigator.vibrate)navigator.vibrate(12);return fetch(base+'/'+p,{method:'POST',body:JSON.stringify(d||{})}).then(r=>r.ok?r.text():Promise.reject()).catch(()=>{st('Bağlantı yok');return ''})}
function st(m){const e=document.getElementById('st');e.textContent=m;setTimeout(()=>e.textContent='',1800)}
function k(x){post('key',{key:x})}
function b(){post('back')}
async function s(submit){const v=document.getElementById('t').value;const r=await post('text',{text:v,submit:submit});try{if(!JSON.parse(r).ok)st('TV\\'de yazılacak bir kutu seçili değil')}catch(e){}}
</script></body></html>''';
