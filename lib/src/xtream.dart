import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

const _userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

enum Kind { live, movie, series }

class Account {
  Account({required this.name, required this.host, required this.username, required this.password});

  final String name;
  final String host; // http://host:port, no trailing slash
  final String username;
  final String password;

  /// Identifies an account without the password.
  String get key => '$host|$username';

  Map<String, String> toJson() => {'name': name, 'host': host, 'username': username, 'password': password};

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        name: j['name'] as String,
        host: j['host'] as String,
        username: j['username'] as String,
        password: j['password'] as String,
      );

  static String normalizeHost(String input) {
    var h = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(h)) h = 'http://$h';
    return h;
  }
}

class AccountInfo {
  AccountInfo({required this.status, this.expiry, required this.maxConnections, this.activeConnections = 0});

  final String status;
  final DateTime? expiry;
  final int maxConnections;
  final int activeConnections;

  /// True when every allowed connection is in use (a new stream will be refused or will kick another device).
  bool get limitReached => maxConnections > 0 && activeConnections >= maxConnections;
}

class Item {
  Item({required this.id, required this.name, required this.logo, required this.group, required this.kind, this.url, this.seriesId, this.added = 0});

  final String id;
  final String name;
  final String logo;
  final String group;
  final Kind kind;
  final String? url; // null for a series (episodes are fetched on demand)
  final int? seriesId;
  final int added; // unix seconds, 0 when unknown

  /// Xtream stream id of a live channel / movie (ids are stored as "l123" / "m123").
  int? get streamId => int.tryParse(id.substring(1));

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'logo': logo, 'group': group, 'kind': kind.name, 'url': url, 'seriesId': seriesId, 'added': added};

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        logo: j['logo'] as String,
        group: j['group'] as String,
        kind: Kind.values.byName(j['kind'] as String),
        url: j['url'] as String?,
        seriesId: j['seriesId'] as int?,
        added: (j['added'] ?? 0) as int,
      );
}

class Episode {
  Episode({required this.season, required this.number, required this.title, required this.url, this.plot = '', this.duration = '', this.image = ''});

  final int season;
  final int number;
  final String title;
  final String url;
  final String plot;
  final String duration;
  final String image;
}

/// Metadata shown on the movie / series detail page.
class Details {
  Details({this.plot = '', this.rating = '', this.year = '', this.duration = '', this.genre = '', this.cast = '', this.director = '', this.backdrop = '', this.poster = ''});

  final String plot;
  final String rating;
  final String year;
  final String duration;
  final String genre;
  final String cast;
  final String director;
  final String backdrop;
  final String poster;
}

class SeriesData {
  SeriesData(this.details, this.episodes);

  final Details details;
  final List<Episode> episodes;
}

/// A programme from the short EPG.
class Programme {
  Programme({required this.title, required this.start, required this.end});

  final String title;
  final DateTime start;
  final DateTime end;

  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }

  double get progress {
    final total = end.difference(start).inSeconds;
    return total <= 0 ? 0 : (DateTime.now().difference(start).inSeconds / total).clamp(0, 1).toDouble();
  }
}

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class XtreamClient {
  XtreamClient(this.acc);

  final Account acc;

  Uri _api(String? action, [Map<String, String> extra = const {}]) {
    final base = Uri.parse('${acc.host}/player_api.php');
    return base.replace(queryParameters: {
      'username': acc.username,
      'password': acc.password,
      if (action != null) 'action': action,
      ...extra,
    });
  }

  String _stream(String kind, Object id, String ext) =>
      '${acc.host}/$kind/${Uri.encodeComponent(acc.username)}/${Uri.encodeComponent(acc.password)}/$id.$ext';

  Future<dynamic> _getJson(Uri uri, {Duration timeout = const Duration(seconds: 90)}) async {
    final http.Response res;
    try {
      res = await http.get(uri, headers: {'User-Agent': _userAgent}).timeout(timeout);
    } catch (e) {
      throw XtreamException('Sunucuya erişilemiyor: $e');
    }
    if (res.statusCode != 200) throw XtreamException('Sunucu HTTP ${res.statusCode} döndürdü');
    final body = res.bodyBytes;
    try {
      // Large lists (tens of thousands of entries) are decoded off the UI isolate.
      return await Isolate.run(() => jsonDecode(utf8.decode(body)));
    } catch (_) {
      throw XtreamException('Sunucu geçersiz (JSON olmayan) yanıt verdi');
    }
  }

  Future<AccountInfo> authenticate() async {
    final data = await _getJson(_api(null), timeout: const Duration(seconds: 30));
    final info = (data is Map ? data['user_info'] : null) as Map?;
    if (info == null || '${info['auth']}' == '0') {
      throw XtreamException('Giriş reddedildi: kullanıcı adı veya parola hatalı');
    }
    final exp = int.tryParse('${info['exp_date']}');
    return AccountInfo(
      status: '${info['status'] ?? ''}',
      expiry: exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: int.tryParse('${info['max_connections']}') ?? 0,
      activeConnections: int.tryParse('${info['active_cons']}') ?? 0,
    );
  }

  Future<Map<String, String>> _categories(String action) async {
    try {
      final list = await _getJson(_api(action));
      if (list is! List) return {};
      return {for (final c in list) '${c['category_id']}': '${c['category_name']}'};
    } catch (_) {
      return {};
    }
  }

  Future<List<Item>> live() async {
    final cats = await _categories('get_live_categories');
    final list = await _getJson(_api('get_live_streams'));
    if (list is! List) return [];
    return [
      for (final s in list)
        Item(
          id: 'l${s['stream_id']}',
          name: '${s['name'] ?? ''}',
          logo: '${s['stream_icon'] ?? ''}',
          group: cats['${s['category_id']}'] ?? 'Kategorisiz',
          kind: Kind.live,
          url: _stream('live', s['stream_id'], 'ts'),
        )
    ];
  }

  Future<List<Item>> movies() async {
    final cats = await _categories('get_vod_categories');
    final list = await _getJson(_api('get_vod_streams'));
    if (list is! List) return [];
    return [
      for (final s in list)
        Item(
          id: 'm${s['stream_id']}',
          name: '${s['name'] ?? ''}',
          logo: '${s['stream_icon'] ?? ''}',
          group: cats['${s['category_id']}'] ?? 'Kategorisiz',
          kind: Kind.movie,
          url: _stream('movie', s['stream_id'], '${(s['container_extension'] ?? 'mp4')}'),
          added: int.tryParse('${s['added']}') ?? 0,
        )
    ];
  }

  Future<List<Item>> series() async {
    final cats = await _categories('get_series_categories');
    final list = await _getJson(_api('get_series'));
    if (list is! List) return [];
    return [
      for (final s in list)
        Item(
          id: 's${s['series_id']}',
          name: '${s['name'] ?? ''}',
          logo: '${s['cover'] ?? ''}',
          group: cats['${s['category_id']}'] ?? 'Kategorisiz',
          kind: Kind.series,
          seriesId: int.tryParse('${s['series_id']}'),
          added: int.tryParse('${s['last_modified']}') ?? 0,
        )
    ];
  }

  static String _first(dynamic v) {
    if (v is List) return v.isEmpty ? '' : '${v.first}';
    return v == null ? '' : '$v';
  }

  static Details _details(Map? info) {
    if (info == null) return Details();
    String year = '${info['releasedate'] ?? info['releaseDate'] ?? info['year'] ?? ''}';
    if (year.length >= 4) year = year.substring(0, 4);
    return Details(
      plot: '${info['plot'] ?? info['description'] ?? ''}',
      rating: '${info['rating'] ?? ''}',
      year: year,
      duration: '${info['duration'] ?? ''}',
      genre: '${info['genre'] ?? ''}',
      cast: '${info['cast'] ?? info['actors'] ?? ''}',
      director: '${info['director'] ?? ''}',
      backdrop: _first(info['backdrop_path']),
      poster: '${info['movie_image'] ?? info['cover'] ?? ''}',
    );
  }

  Future<Details> vodDetails(int streamId) async {
    final data = await _getJson(_api('get_vod_info', {'vod_id': '$streamId'}));
    return _details(data is Map ? data['info'] as Map? : null);
  }

  Future<SeriesData> seriesData(int seriesId) async {
    final data = await _getJson(_api('get_series_info', {'series_id': '$seriesId'}));
    final map = data is Map ? data : const {};
    final eps = map['episodes'];
    final out = <Episode>[];
    void add(String seasonKey, dynamic list) {
      if (list is! List) return;
      for (final e in list) {
        final info = e['info'] is Map ? e['info'] as Map : const {};
        out.add(Episode(
          season: int.tryParse('${e['season'] ?? seasonKey}') ?? 1,
          number: int.tryParse('${e['episode_num']}') ?? 1,
          title: '${e['title'] ?? ''}',
          url: _stream('series', e['id'], '${e['container_extension'] ?? 'mp4'}'),
          plot: '${info['plot'] ?? ''}',
          duration: '${info['duration'] ?? ''}',
          image: '${info['movie_image'] ?? ''}',
        ));
      }
    }

    if (eps is Map) {
      eps.forEach((k, v) => add('$k', v));
    } else if (eps is List) {
      for (var i = 0; i < eps.length; i++) {
        add('${i + 1}', eps[i]);
      }
    }
    out.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    return SeriesData(_details(map['info'] as Map?), out);
  }

  /// Current and upcoming programmes of a live channel (empty when the provider has no EPG).
  Future<List<Programme>> shortEpg(int streamId) async {
    try {
      final data = await _getJson(_api('get_short_epg', {'stream_id': '$streamId', 'limit': '3'}), timeout: const Duration(seconds: 15));
      final list = data is Map ? data['epg_listings'] : null;
      if (list is! List) return [];
      String dec(dynamic v) {
        try {
          return utf8.decode(base64.decode('$v'));
        } catch (_) {
          return '$v';
        }
      }

      DateTime? ts(dynamic v) {
        final n = int.tryParse('$v');
        return n == null ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }

      final out = <Programme>[];
      for (final e in list) {
        final st = ts(e['start_timestamp']);
        final en = ts(e['stop_timestamp']);
        if (st != null && en != null) out.add(Programme(title: dec(e['title']), start: st, end: en));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out.where((p) => p.end.isAfter(DateTime.now())).toList();
    } catch (_) {
      return [];
    }
  }
}
