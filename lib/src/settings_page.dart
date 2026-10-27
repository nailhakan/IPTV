import 'package:flutter/material.dart';

import 'settings.dart';
import 'xtream.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.info, required this.account, required this.client, required this.onLogout});

  final XtreamClient client;
  final AccountInfo info;
  final Account account;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final exp = info.expiry;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Section('Hesap', [
              ListTile(leading: const Icon(Icons.person), title: Text(account.name), subtitle: Text(account.host)),
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Abonelik bitiş tarihi'),
                subtitle: Text(exp == null ? 'Bilinmiyor' : '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}.${exp.year}'),
              ),
              _ConnectionTile(client: client, initial: info),
              ListTile(leading: const Icon(Icons.logout), title: const Text('Kullanıcı değiştir'), onTap: onLogout),
            ]),
            _Section('Oynatıcı', [
              _Choice<String>(
                icon: Icons.audiotrack,
                title: 'Tercih edilen ses dili',
                value: s.audioLang,
                options: const {'auto': 'Dosya varsayılanı', 'tr': 'Türkçe', 'en': 'İngilizce'},
                onChanged: (v) => s.update(audioLang: v),
              ),
              _Choice<String>(
                icon: Icons.subtitles,
                title: 'Tercih edilen altyazı',
                value: s.subLang,
                options: const {'off': 'Kapalı', 'tr': 'Türkçe', 'en': 'İngilizce'},
                onChanged: (v) => s.update(subLang: v),
              ),
              _Choice<int>(
                icon: Icons.fast_forward,
                title: 'İleri/geri sarma süresi',
                value: s.skipSecs,
                options: const {5: '5 sn', 10: '10 sn', 30: '30 sn'},
                onChanged: (v) => s.update(skipSecs: v),
              ),
              _Choice<int>(
                icon: Icons.storage,
                title: 'Ön bellek (tampon)',
                value: s.cacheSecs,
                options: const {10: '10 sn', 30: '30 sn', 60: '60 sn', 120: '120 sn'},
                onChanged: (v) => s.update(cacheSecs: v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.memory),
                title: const Text('Donanım hızlandırma'),
                subtitle: const Text('Video takılıyor ya da bozuk görünüyorsa kapatmayı dene'),
                value: s.hwdec,
                onChanged: (v) => s.update(hwdec: v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.history),
                title: const Text('Kaldığım yerden devam et'),
                subtitle: const Text('Film ve dizilerde son konumu hatırla'),
                value: s.resume,
                onChanged: (v) => s.update(resume: v),
              ),
            ]),
            _Section('İçerik', [
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Yetişkin içeriği gizle'),
                subtitle: const Text('Adı veya kategorisi "adult, xxx, 18+" içerenleri listelerden çıkarır'),
                value: s.hideAdult,
                onChanged: (v) => s.update(hideAdult: v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.content_copy),
                title: const Text('Yinelenen filmleri/dizileri gizle'),
                subtitle: const Text('"Tümü" görünümünde aynı adı taşıyan kayıtlardan yalnızca biri gösterilir'),
                value: s.dedupe,
                onChanged: (v) => s.update(dedupe: v),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('Gizlenen kategoriler'),
                subtitle: Text(s.hiddenGroups.isEmpty ? 'Yok. Bir kategoriyi gizlemek için listenin üstündeki ayar ikonunu kullan.' : '${s.hiddenGroups.length} kategori gizli'),
                trailing: s.hiddenGroups.isEmpty ? null : TextButton(onPressed: () => s.update(hiddenGroups: <String>{}), child: const Text('Hepsini göster')),
              ),
            ]),
            _Section('Görünüm', [
              _Choice<double>(
                icon: Icons.zoom_in,
                title: 'Arayüz ölçeği',
                value: const [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.4].contains(s.uiScale) ? s.uiScale : 1.0,
                options: {0.5: '%50', 0.6: '%60', 0.7: '%70', 0.8: '%80', 0.9: '%90', 1.0: '%100', 1.2: '%120', 1.4: '%140'},
                onChanged: (v) => s.update(uiScale: v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.settings_remote),
                title: const Text('Kumanda (TV) modu'),
                subtitle: const Text('Büyük yazı, belirgin odak çerçevesi ve kumanda ile gezinme. Android TV / Fire Stick\'te otomatik açık'),
                value: s.tvMode,
                onChanged: (v) => s.update(tvMode: v),
              ),
            ]),
            _Section('Kısayollar', const [
              ListTile(dense: true, title: Text('Boşluk'), trailing: Text('Oynat / duraklat')),
              ListTile(dense: true, title: Text('← / →'), trailing: Text('Geri / ileri sar')),
              ListTile(dense: true, title: Text('↑ / ↓'), trailing: Text('Ses aç / kıs')),
              ListTile(dense: true, title: Text('M'), trailing: Text('Sessiz')),
              ListTile(dense: true, title: Text('F'), trailing: Text('Tam ekran')),
              ListTile(dense: true, title: Text('Esc'), trailing: Text('Tam ekrandan çık / geri')),
            ]),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary))),
          Card(margin: EdgeInsets.zero, child: Column(children: children)),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.value, required this.options, required this.onChanged});

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// "Active connections: 1/2" with a refresh button, so it is easy to see whether another device is streaming.
class _ConnectionTile extends StatefulWidget {
  const _ConnectionTile({required this.client, required this.initial});

  final XtreamClient client;
  final AccountInfo initial;

  @override
  State<_ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<_ConnectionTile> {
  late AccountInfo _info = widget.initial;
  bool _busy = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final i = await widget.client.authenticate();
      if (mounted) setState(() => _info = i);
    } on XtreamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final text = i.maxConnections > 0 ? '${i.activeConnections} / ${i.maxConnections} kullanımda' : 'Sınır bilinmiyor';
    return ListTile(
      leading: Icon(Icons.devices, color: i.limitReached ? Theme.of(context).colorScheme.error : null),
      title: const Text('Eşzamanlı bağlantılar'),
      subtitle: Text(_error ?? (i.limitReached ? '$text. Sınır dolu: başka bir cihazda izleme açık olabilir.' : text)),
      trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh), onPressed: _refresh),
    );
  }
}
