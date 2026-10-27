import 'package:flutter/material.dart';

import 'detail_page.dart';
import 'epg_widgets.dart';
import 'library.dart';
import 'player_page.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'title_utils.dart';
import 'tv_text_field.dart';
import 'xtream.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.info, required this.account});

  final XtreamClient client;
  final AccountInfo info;
  final Account account;

  @override
  State<HomePage> createState() => _HomePageState();
}

// Navigation tabs: 0 home, 1 live, 2 movies, 3 series, 4 favorites, 5 settings
enum _Sort { provider, added, name, year }

const _homeTab = 0;
const _favoritesTab = 4;
const _settingsTab = 5;

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  final Map<Kind, List<Item>> _items = {};
  final Map<Kind, String?> _errors = {};
  final Set<Kind> _loading = {};
  String? _group;
  String _query = '';
  _Sort _sort = _Sort.provider;

  Kind? get _kind => _tab >= 1 && _tab <= 3 ? Kind.values[_tab - 1] : null;

  late final EpgCache _epg = EpgCache(widget.client);

  @override
  void initState() {
    super.initState();
    // The home tab shows recently added movies/series.
    _ensureLoaded(Kind.movie);
    _ensureLoaded(Kind.series);
  }

  Future<void> _ensureLoaded(Kind kind) async {
    if (_items.containsKey(kind) || _loading.contains(kind)) return;
    setState(() {
      _loading.add(kind);
      _errors[kind] = null;
    });
    try {
      final c = widget.client;
      _items[kind] = switch (kind) {
        Kind.live => await c.live(),
        Kind.movie => await c.movies(),
        Kind.series => await c.series(),
      };
    } on XtreamException catch (e) {
      _errors[kind] = e.message;
    } finally {
      if (mounted) setState(() => _loading.remove(kind));
    }
  }

  void _select(int tab) {
    setState(() {
      _tab = tab;
      _group = null;
      _query = '';
    });
    final k = _kind;
    if (k != null) _ensureLoaded(k);
  }

  void _open(Item item) {
    if (item.kind == Kind.live) {
      _playLive(item);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(client: widget.client, item: item)));
    }
  }

  void _playLive(Item item) {
    final id = item.streamId;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(url: item.url!, title: item.name, logo: item.logo, kind: Kind.live, epg: id == null ? null : () => _epg.get(id), client: widget.client),
    ));
  }

  void _openHistory(HistoryEntry e) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(url: e.url, title: e.title, logo: e.logo, kind: e.kind, client: widget.client)));
  }

  bool _allowed(Item i) {
    final s = AppSettings.instance;
    if (s.hiddenGroups.contains(AppSettings.groupKey(i.kind, i.group))) return false;
    return !s.hideAdult || !(AppSettings.adultPattern.hasMatch(i.group) || AppSettings.adultPattern.hasMatch(i.name));
  }

  List<Item> _sorted(List<Item> items) {
    switch (_sort) {
      case _Sort.provider:
        return items;
      case _Sort.added:
        return [...items]..sort((a, b) => b.added.compareTo(a.added));
      case _Sort.name:
        return [...items]..sort((a, b) => parsedTitleOf(a).title.toLowerCase().compareTo(parsedTitleOf(b).title.toLowerCase()));
      case _Sort.year:
        int y(Item i) => int.tryParse(parsedTitleOf(i).year ?? '') ?? 0;
        return [...items]..sort((a, b) => y(b).compareTo(y(a)));
    }
  }

  static final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Keeps the first entry of each name (case, spacing and punctuation ignored).
  static final _nameKeys = Expando<String>();

  List<Item> _dedupe(List<Item> items) {
    final seen = <String>{};
    return [for (final i in items) if (seen.add(_nameKeys[i] ??= i.name.toLowerCase().replaceAll(_nonAlnum, ''))) i];
  }

  /// Right-click menu on a category: move to top / hide.
  Future<void> _groupMenu(Kind kind, String name, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'top', child: Text('En üste al')),
        PopupMenuItem(value: 'hide', child: Text('Gizle')),
        PopupMenuItem(value: 'edit', child: Text('Kategorileri düzenle...')),
      ],
    );
    final s = AppSettings.instance;
    final all = _allGroups(kind);
    switch (choice) {
      case 'top':
        final order = s.orderedGroups(kind, all)..remove(name);
        s.update(groupOrder: {...s.groupOrder, kind.name: [name, ...order]});
      case 'hide':
        s.update(hiddenGroups: {...s.hiddenGroups, AppSettings.groupKey(kind, name)});
        if (_group == name) setState(() => _group = null);
      case 'edit':
        _manageGroups(kind);
    }
  }

  /// All category names of a kind in provider order (hidden ones included).
  List<String> _allGroups(Kind kind) {
    final seen = <String>{};
    return [for (final i in _items[kind] ?? const <Item>[]) if (seen.add(i.group)) i.group];
  }

  Future<void> _manageGroups(Kind kind) async {
    final counts = <String, int>{};
    for (final i in _items[kind] ?? const <Item>[]) {
      counts[i.group] = (counts[i.group] ?? 0) + 1;
    }
    String filter = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final s = AppSettings.instance;
          final ordered = s.orderedGroups(kind, counts.keys);
          final visible = [for (final n in ordered) if (filter.isEmpty || n.toLowerCase().contains(filter.toLowerCase())) n];
          final canReorder = filter.isEmpty;

          void save(List<String> order) {
            s.update(groupOrder: {...s.groupOrder, kind.name: order});
            setLocal(() {});
          }

          void move(int from, int to) {
            final list = [...ordered];
            final item = list.removeAt(from);
            list.insert(to.clamp(0, list.length), item);
            save(list);
          }

          Widget tile(int index, String n) {
            final key = AppSettings.groupKey(kind, n);
            return ListTile(
              key: ValueKey(n),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 0, right: 4),
              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                if (canReorder)
                  ReorderableDragStartListener(index: index, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_indicator, size: 20))),
                Checkbox(
                  value: !s.hiddenGroups.contains(key),
                  onChanged: (v) {
                    final next = {...s.hiddenGroups};
                    (v ?? true) ? next.remove(key) : next.add(key);
                    s.update(hiddenGroups: next);
                    setLocal(() {});
                  },
                ),
              ]),
              title: Text(groupLabel(n), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${counts[n]} öğe', style: const TextStyle(fontSize: 11)),
              trailing: canReorder
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'En üste al', visualDensity: VisualDensity.compact, icon: const Icon(Icons.vertical_align_top, size: 18), onPressed: index == 0 ? null : () => move(index, 0)),
                      IconButton(tooltip: 'Yukarı', visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_up, size: 20), onPressed: index == 0 ? null : () => move(index, index - 1)),
                      IconButton(tooltip: 'Aşağı', visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_down, size: 20), onPressed: index >= ordered.length - 1 ? null : () => move(index, index + 1)),
                    ])
                  : null,
            );
          }

          return AlertDialog(
            title: const Text('Kategorileri düzenle'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Sürükleyerek ya da oklarla sırayı değiştir. Kutuyu kaldırarak kategoriyi gizle.', style: TextStyle(fontSize: 12))),
                const SizedBox(height: 8),
                RemoteTextField(
                  onChanged: (v) => setLocal(() => filter = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Kategori ara (arama sırasında sıralama kapalı)', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: canReorder
                      ? ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: visible.length,
                          onReorderItem: (from, to) => move(from, to),
                          itemBuilder: (_, i) => tile(i, visible[i]),
                        )
                      : ListView(children: [for (var i = 0; i < visible.length; i++) tile(i, visible[i])]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  s.update(groupOrder: {...s.groupOrder}..remove(kind.name));
                  setLocal(() {});
                },
                child: const Text('Sırayı sıfırla'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.instance, Library.instance]),
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              minWidth: 76,
              leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Icon(Icons.live_tv, size: 26)),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.home), label: Text('Ana Sayfa')),
                NavigationRailDestination(icon: Icon(Icons.tv), label: Text('Canlı TV')),
                NavigationRailDestination(icon: Icon(Icons.movie), label: Text('Filmler')),
                NavigationRailDestination(icon: Icon(Icons.video_library), label: Text('Diziler')),
                NavigationRailDestination(icon: Icon(Icons.favorite), label: Text('Favoriler')),
                NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Ayarlar')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_tab == _homeTab) return _homeView();
    if (_tab == _settingsTab) {
      return SettingsPage(info: widget.info, account: widget.account, client: widget.client, onLogout: () => Navigator.of(context).pop());
    }
    if (_tab == _favoritesTab) {
      final favs = Library.instance.favorites.where(_allowed).where((i) => _query.isEmpty || i.name.toLowerCase().contains(_query.toLowerCase())).toList();
      return Column(children: [
        _searchBar(),
        Expanded(child: favs.isEmpty ? const Center(child: Text('Henüz favori yok. Bir içeriğin kalp ikonuna dokun.')) : _mixedList(favs)),
      ]);
    }

    final kind = _kind!;
    final all = (_items[kind] ?? const <Item>[]).where(_allowed).toList();
    final groups = <String, int>{};
    for (final i in all) {
      groups[i.group] = (groups[i.group] ?? 0) + 1;
    }
    final q = _query.toLowerCase();
    var shown = all.where((i) => (_group == null || i.group == _group) && (q.isEmpty || i.name.toLowerCase().contains(q))).toList();
    // Same title listed in several categories: collapse only in the mixed "Tümü" view.
    final collapse = kind != Kind.live && AppSettings.instance.dedupe;
    if (collapse && _group == null) shown = _dedupe(shown);
    final totalCount = collapse ? _dedupe(all).length : all.length;
    if (kind != Kind.live) shown = _sorted(shown);

    return Row(
      children: [
        SizedBox(
          width: 260,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(children: [
                  Expanded(child: Text(widget.account.name, style: Theme.of(context).textTheme.titleSmall)),
                  IconButton(tooltip: 'Kategorileri düzenle / gizle', icon: const Icon(Icons.tune, size: 20), onPressed: () => _manageGroups(kind)),
                ]),
              ),
              ListTile(dense: true, selected: _group == null, title: const Text('Tümü'), trailing: Text('$totalCount'), onTap: () => setState(() => _group = null)),
              for (final name in AppSettings.instance.orderedGroups(kind, groups.keys))
                Tooltip(
                  message: name,
                  waitDuration: const Duration(milliseconds: 500),
                  child: GestureDetector(
                    // right click: quick pin / hide
                    onSecondaryTapUp: (d) => _groupMenu(kind, name, d.globalPosition),
                    child: ListTile(
                      dense: true,
                      selected: _group == name,
                      title: Text(groupLabel(name), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text('${groups[name]}'),
                      onTap: () => setState(() => _group = name),
                      onLongPress: () => _manageGroups(kind),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: Column(children: [_searchBar(withSort: kind != Kind.live), Expanded(child: _body(kind, shown))])),
      ],
    );
  }

  // ─── Home tab ──────────────────────────────────────────────

  Widget _homeView() {
    final lib = Library.instance;
    final continueList = lib.continueWatching.take(20).toList();
    final recent = lib.history.take(20).toList();
    List<Item> latest(Kind k) {
      final l = (_items[k] ?? const <Item>[]).where(_allowed).where((i) => i.added > 0).toList()..sort((a, b) => b.added.compareTo(a.added));
      return l.take(20).toList();
    }

    final movies = latest(Kind.movie);
    final series = latest(Kind.series);
    final loadingLatest = _loading.contains(Kind.movie) || _loading.contains(Kind.series);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (continueList.isNotEmpty) _row('Kaldığın yerden devam et', [for (final e in continueList) _historyCard(e, showProgress: true)]),
        if (recent.isNotEmpty) _row('Son izlenenler', [for (final e in recent) _historyCard(e)]),
        if (movies.isNotEmpty) _row('Son eklenen filmler', [for (final i in movies) _itemCard(i)]),
        if (series.isNotEmpty) _row('Son eklenen diziler', [for (final i in series) _itemCard(i)]),
        if (loadingLatest) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (!loadingLatest && continueList.isEmpty && recent.isEmpty && movies.isEmpty && series.isEmpty)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Burada izlediklerin ve yeni eklenenler görünecek.\nSolden bir kategori seç.', textAlign: TextAlign.center))),
      ],
    );
  }

  Widget _row(String title, List<Widget> cards) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
        ]),
      );

  Widget _card({required String logo, required String title, required VoidCallback onTap, String? year, List<String> tags = const [], double? progress, IconData? badge}) => SizedBox(
        width: 125,
        child: PosterCard(logo: logo, title: title, year: year, tags: tags, progress: progress, badge: badge, onTap: onTap),
      );

  Widget _itemCard(Item i) {
    final t = parsedTitleOf(i);
    return _card(logo: i.logo, title: t.title, year: t.year, tags: t.tags, onTap: () => _open(i));
  }

  Widget _historyCard(HistoryEntry e, {bool showProgress = false}) {
    final t = parseTitle(e.title);
    return _card(
      logo: e.logo,
      title: t.title,
      year: t.year,
      tags: t.tags,
      progress: showProgress ? e.progress : null,
      badge: e.kind == Kind.live ? Icons.tv : null,
      onTap: () => _openHistory(e),
    );
  }

  Widget _searchBar({bool withSort = false}) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: RemoteTextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ara', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          if (withSort) ...[
            const SizedBox(width: 12),
            Icon(Icons.sort, size: 20, color: Theme.of(context).hintColor),
            const SizedBox(width: 6),
            DropdownButton<_Sort>(
              value: _sort,
              underline: const SizedBox.shrink(),
              onChanged: (v) => setState(() => _sort = v ?? _sort),
              items: const [
                DropdownMenuItem(value: _Sort.provider, child: Text('Varsayılan')),
                DropdownMenuItem(value: _Sort.added, child: Text('Yeni eklenen')),
                DropdownMenuItem(value: _Sort.name, child: Text('A – Z')),
                DropdownMenuItem(value: _Sort.year, child: Text('Yıl (yeni → eski)')),
              ],
            ),
          ],
        ]),
      );

  Widget _body(Kind kind, List<Item> shown) {
    if (_loading.contains(kind)) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Yükleniyor...')]));
    }
    final err = _errors[kind];
    if (err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(err),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _ensureLoaded(kind), child: const Text('Tekrar dene')),
        ]),
      );
    }
    if (shown.isEmpty) return const Center(child: Text('Sonuç yok'));
    return kind == Kind.live ? _liveList(shown) : _posterGrid(shown);
  }

  Widget _heart(Item it, {double size = 22}) => IconButton(
        iconSize: size,
        visualDensity: VisualDensity.compact,
        tooltip: Library.instance.isFavorite(it) ? 'Favorilerden çıkar' : 'Favorilere ekle',
        icon: Icon(Library.instance.isFavorite(it) ? Icons.favorite : Icons.favorite_border, color: Library.instance.isFavorite(it) ? Colors.redAccent : null),
        onPressed: () => Library.instance.toggleFavorite(it),
      );

  Widget _liveList(List<Item> shown) => ListView.builder(
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final it = shown[i];
          return ListTile(
            leading: PosterImage(it.logo, size: 40, fit: BoxFit.contain),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: NowPlaying(cache: _epg, item: it, fallback: it.group),
            trailing: _heart(it),
            onTap: () => _open(it),
          );
        },
      );

  Widget _posterGrid(List<Item> shown) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 0.6, crossAxisSpacing: 14, mainAxisSpacing: 14),
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final it = shown[i];
          final t = parsedTitleOf(it);
          return PosterCard(
            logo: it.logo,
            title: t.title,
            year: t.year,
            tags: t.tags,
            onTap: () => _open(it),
            topRight: DecoratedBox(decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: _heart(it, size: 18)),
          );
        },
      );

  Widget _mixedList(List<Item> items) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          final icon = switch (it.kind) { Kind.live => Icons.tv, Kind.movie => Icons.movie, Kind.series => Icons.video_library };
          return ListTile(
            leading: Stack(children: [PosterImage(it.logo, size: 44, fit: BoxFit.contain), Positioned(right: 0, bottom: 0, child: Icon(icon, size: 14, color: Colors.white70))]),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(it.group, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _heart(it),
            onTap: () => _open(it),
          );
        },
      );
}

