import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xtream.dart';

/// One watched item (a live channel, a movie or a single episode).
class HistoryEntry {
  HistoryEntry({required this.url, required this.title, required this.logo, required this.kind, this.positionMs = 0, this.durationMs = 0, required this.updatedMs});

  final String url;
  final String title;
  final String logo;
  final Kind kind;
  int positionMs;
  int durationMs;
  int updatedMs;

  bool get resumable => kind != Kind.live && positionMs >= 20000 && (durationMs == 0 || durationMs - positionMs >= 60000);
  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'logo': logo, 'kind': kind.name, 'pos': positionMs, 'dur': durationMs, 'at': updatedMs};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        url: j['url'] as String,
        title: j['title'] as String,
        logo: (j['logo'] ?? '') as String,
        kind: Kind.values.byName(j['kind'] as String),
        positionMs: (j['pos'] ?? 0) as int,
        durationMs: (j['dur'] ?? 0) as int,
        updatedMs: (j['at'] ?? 0) as int,
      );
}

/// Favorites and watch history.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  static const _maxHistory = 60;

  final Map<String, Item> _favorites = {};
  final List<HistoryEntry> _history = []; // newest first

  List<Item> get favorites => _favorites.values.toList();
  bool isFavorite(Item i) => _favorites.containsKey(i.id);

  List<HistoryEntry> get history => List.unmodifiable(_history);
  List<HistoryEntry> get continueWatching => _history.where((e) => e.resumable).toList();

  HistoryEntry? _find(String url) {
    for (final e in _history) {
      if (e.url == url) return e;
    }
    return null;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final f = p.getString('favorites');
      if (f != null) {
        for (final j in jsonDecode(f) as List) {
          final it = Item.fromJson(j as Map<String, dynamic>);
          _favorites[it.id] = it;
        }
      }
      final h = p.getString('history');
      if (h != null) {
        _history.addAll([for (final j in jsonDecode(h) as List) HistoryEntry.fromJson(j as Map<String, dynamic>)]);
      }
    } catch (_) {
      // corrupt data: start fresh
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Item i) async {
    if (_favorites.remove(i.id) == null) _favorites[i.id] = i;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('favorites', jsonEncode([for (final f in _favorites.values) f.toJson()]));
  }

  Duration? positionFor(String url) {
    final e = _find(url);
    return e == null || !e.resumable ? null : Duration(milliseconds: e.positionMs);
  }

  /// Record that [url] was opened (moves it to the top of the history).
  Future<void> touch({required String url, required String title, required String logo, required Kind kind}) async {
    final old = _find(url);
    _history.removeWhere((e) => e.url == url);
    _history.insert(0, HistoryEntry(url: url, title: title, logo: logo, kind: kind, positionMs: old?.positionMs ?? 0, durationMs: old?.durationMs ?? 0, updatedMs: DateTime.now().millisecondsSinceEpoch));
    if (_history.length > _maxHistory) _history.removeRange(_maxHistory, _history.length);
    notifyListeners();
    await _persist();
  }

  Future<void> savePosition(String url, Duration position, Duration total) async {
    final e = _find(url);
    if (e == null || e.kind == Kind.live) return;
    final finished = total > Duration.zero && total - position < const Duration(seconds: 60);
    e.positionMs = finished ? 0 : position.inMilliseconds;
    e.durationMs = total.inMilliseconds;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('history', jsonEncode([for (final e in _history) e.toJson()]));
  }
}
