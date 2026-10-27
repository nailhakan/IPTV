import 'package:flutter/material.dart';

import 'library.dart';
import 'player_page.dart';
import 'title_utils.dart';
import 'xtream.dart';

/// Detail page for a movie or a series (with seasons and episodes).
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.client, required this.item});

  final XtreamClient client;
  final Item item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final Future<SeriesData> _series;
  late final Future<Details> _movie;

  bool get _isSeries => widget.item.kind == Kind.series;

  @override
  void initState() {
    super.initState();
    if (_isSeries) {
      _series = widget.client.seriesData(widget.item.seriesId!);
    } else {
      _movie = widget.client.vodDetails(widget.item.streamId!);
    }
  }

  void _play(String url, String title, {String? logo}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(url: url, title: title, logo: logo ?? widget.item.logo, kind: widget.item.kind == Kind.live ? Kind.live : widget.item.kind, client: widget.client),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(parsedTitleOf(widget.item).title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _isSeries
          ? FutureBuilder<SeriesData>(
              future: _series,
              builder: (context, snap) => _build(context, snap.connectionState, snap.error, snap.data?.details, snap.data?.episodes),
            )
          : FutureBuilder<Details>(
              future: _movie,
              builder: (context, snap) => _build(context, snap.connectionState, snap.error, snap.data, null),
            ),
    );
  }

  Widget _build(BuildContext context, ConnectionState state, Object? error, Details? d, List<Episode>? episodes) {
    final loading = state != ConnectionState.done;
    final details = d ?? Details();
    final poster = details.poster.isNotEmpty ? details.poster : widget.item.logo;

    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final fav = Library.instance.isFavorite(widget.item);
        final resume = !_isSeries ? Library.instance.positionFor(widget.item.url!) : null;
        return Stack(children: [
          if (details.backdrop.isNotEmpty)
            Positioned.fill(
              child: Opacity(opacity: .18, child: Image.network(details.backdrop, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
            ),
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 190,
                    height: 285,
                    child: poster.isEmpty ? Container(color: Colors.white10) : Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Colors.white10)),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(parsedTitleOf(widget.item).title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      if (details.rating.isNotEmpty && details.rating != '0') _chip(Icons.star, details.rating),
                      if (details.year.isNotEmpty || parsedTitleOf(widget.item).year != null) _chip(Icons.calendar_today, details.year.isNotEmpty ? details.year : parsedTitleOf(widget.item).year!),
                      for (final t in parsedTitleOf(widget.item).tags) _chip(Icons.translate, t),
                      if (details.duration.isNotEmpty) _chip(Icons.schedule, details.duration),
                      if (details.genre.isNotEmpty) _chip(Icons.category, details.genre),
                    ]),
                    const SizedBox(height: 16),
                    if (loading) const LinearProgressIndicator(),
                    if (error != null) Text('Bilgi alınamadı: $error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    if (details.plot.isNotEmpty) Text(details.plot, style: Theme.of(context).textTheme.bodyMedium),
                    if (details.cast.isNotEmpty) ...[const SizedBox(height: 12), Text('Oyuncular: ${details.cast}', style: Theme.of(context).textTheme.bodySmall)],
                    if (details.director.isNotEmpty) ...[const SizedBox(height: 4), Text('Yönetmen: ${details.director}', style: Theme.of(context).textTheme.bodySmall)],
                    const SizedBox(height: 20),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      if (!_isSeries)
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(resume == null ? 'Oynat' : 'Devam et (${_fmt(resume)})'),
                          onPressed: () => _play(widget.item.url!, widget.item.name),
                        ),
                      OutlinedButton.icon(
                        icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.redAccent : null),
                        label: Text(fav ? 'Favorilerde' : 'Favorilere ekle'),
                        onPressed: () => Library.instance.toggleFavorite(widget.item),
                      ),
                    ]),
                  ]),
                ),
              ]),
              if (_isSeries) ..._episodeSections(context, episodes, loading),
            ],
          ),
        ]);
      },
    );
  }

  Widget _chip(IconData icon, String text) => Chip(
        avatar: Icon(icon, size: 16),
        label: Text(text),
        visualDensity: VisualDensity.compact,
      );

  List<Widget> _episodeSections(BuildContext context, List<Episode>? episodes, bool loading) {
    if (loading) return const [];
    if (episodes == null || episodes.isEmpty) return const [Padding(padding: EdgeInsets.only(top: 32), child: Text('Bölüm bulunamadı'))];
    final seasons = <int, List<Episode>>{};
    for (final e in episodes) {
      seasons.putIfAbsent(e.season, () => []).add(e);
    }
    String two(int n) => n.toString().padLeft(2, '0');

    return [
      const SizedBox(height: 28),
      Text('Bölümler', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final s in seasons.entries)
        ExpansionTile(
          initiallyExpanded: seasons.length == 1,
          title: Text('${s.key}. Sezon (${s.value.length} bölüm)'),
          children: [
            for (final e in s.value)
              ListTile(
                leading: e.image.isEmpty
                    ? const SizedBox(width: 96, child: Icon(Icons.play_circle_outline))
                    : ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 96, height: 54, child: Image.network(e.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Colors.white10)))),
                title: Text('${e.number}. Bölüm${e.title.isEmpty ? '' : ' - ${e.title}'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (Library.instance.positionFor(e.url) != null) 'Devam ediliyor (${_fmt(Library.instance.positionFor(e.url)!)})',
                    if (e.duration.isNotEmpty) e.duration,
                    if (e.plot.isNotEmpty) e.plot,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _play(e.url, '${widget.item.name} S${two(s.key)}E${two(e.number)}', logo: e.image.isNotEmpty ? e.image : widget.item.logo),
              ),
          ],
        ),
    ];
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}
