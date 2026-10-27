import 'package:flutter/material.dart';

import 'accounts.dart';
import 'focus_frame.dart';
import 'home_page.dart';
import 'remote_entry.dart';
import 'settings.dart';
import 'tv_text_field.dart';
import 'xtream.dart';

typedef ClientFactory = XtreamClient Function(Account account);
typedef HomeBuilder = Widget Function(XtreamClient client, AccountInfo info, Account account);

XtreamClient _defaultClient(Account a) => XtreamClient(a);
Widget _defaultHome(XtreamClient c, AccountInfo i, Account a) => HomePage(client: c, info: i, account: a);

/// Start page. Saved accounts are shown as profile cards; with [autoLogin] the account used last is
/// signed in right away (the user can cancel). Returning from the app (switch user) never auto-logs in again.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.autoLogin = false, this.clientFactory = _defaultClient, this.homeBuilder = _defaultHome});

  final bool autoLogin;
  final ClientFactory clientFactory;
  final HomeBuilder homeBuilder;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;
  bool _busy = false;
  String? _error;
  List<Account> _accounts = [];
  String? _lastKey;
  bool _loaded = false; // wait for saved accounts so the right item gets the initial focus
  bool _showForm = false;
  bool _editing = false; // profile edit mode (tap a card to delete it)
  Account? _auto; // account being signed in automatically (shows the splash)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final accounts = await AccountStore.load();
    final last = await AccountStore.loadLast();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _lastKey = last;
      _loaded = true;
      _showForm = accounts.isEmpty;
    });
    if (widget.autoLogin && last != null) {
      final acc = accounts.where((a) => a.key == last).firstOrNull;
      if (acc != null) {
        setState(() => _auto = acc);
        _signIn(acc, auto: true);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Saved accounts, the one used last first.
  List<Account> get _ordered {
    final list = [..._accounts];
    list.sort((a, b) => (b.key == _lastKey ? 1 : 0) - (a.key == _lastKey ? 1 : 0));
    return list;
  }

  Future<void> _signIn(Account acc, {bool save = false, bool auto = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = widget.clientFactory(acc);
      final info = await client.authenticate();
      if (auto && _auto == null) return; // cancelled while connecting
      if (save) {
        _accounts = [..._accounts.where((a) => a.key != acc.key), acc];
        await AccountStore.save(_accounts);
      }
      _lastKey = acc.key;
      await AccountStore.saveLast(acc.key);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.homeBuilder(client, info, acc)));
    } on XtreamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _auto = null; // back on the profile page (failed, cancelled or signed out)
        });
      }
    }
  }

  void _cancelAuto() => setState(() => _auto = null);

  Future<void> _confirmDelete(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcı silinsin mi?'),
        content: Text('"${a.name}" kayıtlı kullanıcılardan kaldırılacak. Tekrar girmek için bilgilerini yeniden yazman gerekir.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _accounts = _accounts.where((x) => x.key != a.key).toList();
      if (_accounts.isEmpty) {
        _editing = false;
        _showForm = true;
      }
    });
    await AccountStore.save(_accounts);
  }

  Future<void> _fromPhone() async {
    final data = await showDialog<Map<String, String>>(context: context, builder: (_) => const RemoteEntryDialog());
    if (data == null || !mounted) return;
    final host = (data['host'] ?? '').trim();
    final user = (data['username'] ?? '').trim();
    final pass = data['password'] ?? '';
    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Telefondan gelen bilgiler eksik');
      return;
    }
    final name = (data['name'] ?? '').trim();
    _signIn(Account(name: name.isEmpty ? user : name, host: Account.normalizeHost(host), username: user, password: pass), save: true);
  }

  void _add() {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Sunucu, kullanıcı adı ve parola gerekli');
      return;
    }
    final acc = Account(
      name: _name.text.trim().isEmpty ? _user.text.trim() : _name.text.trim(),
      host: Account.normalizeHost(_host.text),
      username: _user.text.trim(),
      password: _pass.text,
    );
    _signIn(acc, save: true);
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  Widget _brand({double size = 40}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(size / 4)),
        child: Icon(Icons.play_arrow_rounded, size: size * 0.7, color: scheme.onPrimary),
      ),
      const SizedBox(width: 10),
      Text('IPTV', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold();
    return Scaffold(
      body: Center(
        child: _auto != null ? _splash(_auto!) : SingleChildScrollView(padding: const EdgeInsets.all(20), child: _showForm ? _form() : _profiles()),
      ),
    );
  }

  Widget _splash(Account a) => Column(mainAxisSize: MainAxisSize.min, children: [
        _brand(size: 56),
        const SizedBox(height: 28),
        const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 18),
        Text('${a.name} olarak giriş yapılıyor...'),
        const SizedBox(height: 14),
        TextButton(autofocus: AppSettings.instance.tvMode, onPressed: _cancelAuto, child: const Text('Vazgeç / kullanıcı değiştir')),
      ]);

  Widget _profiles() {
    final scheme = Theme.of(context).colorScheme;
    final ordered = _ordered;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _brand(),
        const SizedBox(height: 26),
        Text(_editing ? 'Silinecek kullanıcıyı seç' : 'Kullanıcı seç', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 22),
        Wrap(spacing: 22, runSpacing: 22, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < ordered.length; i++)
            _ProfileCard(
              account: ordered[i],
              isLast: ordered[i].key == _lastKey,
              editing: _editing,
              autofocus: AppSettings.instance.tvMode && i == 0,
              onTap: _busy ? null : () => _editing ? _confirmDelete(ordered[i]) : _signIn(ordered[i]),
            ),
          if (!_editing) _AddCard(onTap: () => setState(() {
                _showForm = true;
                _error = null;
              })),
        ]),
        const SizedBox(height: 24),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error))),
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        TextButton.icon(
          onPressed: () => setState(() => _editing = !_editing),
          icon: Icon(_editing ? Icons.check : Icons.edit_outlined, size: 18),
          label: Text(_editing ? 'Bitti' : 'Kullanıcıları düzenle'),
        ),
      ]),
    );
  }

  Widget _form() {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: _brand()),
        const SizedBox(height: 18),
        Text(_accounts.isEmpty ? 'Giriş bilgilerinizi girin' : 'Yeni kullanıcı ekle', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        // Typing with a TV remote is painful: offer entering the login on a phone first.
        OutlinedButton.icon(
          autofocus: AppSettings.instance.tvMode,
          onPressed: _busy ? null : _fromPhone,
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Telefondan gir (QR)'),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('veya elle girin', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
        RemoteTextField(controller: _name, decoration: const InputDecoration(labelText: 'Ad (isteğe bağlı)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        RemoteTextField(controller: _host, decoration: const InputDecoration(labelText: 'Sunucu (http://example.com:8080)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        RemoteTextField(controller: _user, decoration: const InputDecoration(labelText: 'Kullanıcı adı', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        RemoteTextField(
          controller: _pass,
          obscureText: !_showPass,
          onSubmitted: (_) => _busy ? null : _add(),
          decoration: InputDecoration(
            labelText: 'Parola',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: scheme.error))),
        if (AppSettings.instance.tvMode)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Bir alana OK ile girip yazın; yukarı/aşağı ile alanlar arasında gezin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kullanıcı Ekle'),
        ),
        if (_accounts.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() {
              _showForm = false;
              _error = null;
            }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Kayıtlı kullanıcılara dön'),
          ),
      ]),
    );
  }
}

Color _avatarColor(String seed) {
  final h = (seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFF)) % 360;
  return HSLColor.fromAHSL(1, h.toDouble(), 0.45, 0.42).toColor();
}

/// A saved account as a large, focusable card (profile-picker style).
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.account, required this.isLast, required this.editing, required this.onTap, this.autofocus = false});

  final Account account;
  final bool isLast;
  final bool editing;
  final bool autofocus;
  final VoidCallback? onTap;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final initial = a.name.trim().isEmpty ? '?' : a.name.trim().characters.first.toUpperCase();
    final host = Uri.tryParse(a.host)?.host ?? a.host;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: FocusFrame(
          radius: 14,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: SizedBox(
              width: 140,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    CircleAvatar(radius: 40, backgroundColor: _avatarColor(a.key), child: Text(initial, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white))),
                    if (widget.editing)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: CircleAvatar(radius: 13, backgroundColor: scheme.error, child: Icon(Icons.delete_outline, size: 16, color: scheme.onError)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
                  if (widget.isLast && !widget.editing)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Son kullanılan', style: TextStyle(fontSize: 10.5)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCard extends StatefulWidget {
  const _AddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddCard> createState() => _AddCardState();
}

class _AddCardState extends State<_AddCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: FocusFrame(
          radius: 14,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: SizedBox(
              width: 140,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 40, backgroundColor: Colors.white10, child: const Icon(Icons.add, size: 36)),
                  const SizedBox(height: 12),
                  Text('Kullanıcı ekle', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(' ', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
