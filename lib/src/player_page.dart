import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'library.dart';
import 'settings.dart';
import 'xtream.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.url, required this.title, this.logo = '', this.kind = Kind.movie, this.epg, this.client});

  final String url;
  final String title;
  final String logo;
  final Kind kind;

  /// Loads now/next programmes (live channels only).
  final Future<List<Programme>> Function()? epg;

  /// Used to tell "connection limit reached" apart from other failures.
  final XtreamClient? client;

  bool get live => kind == Kind.live;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  Timer? _saveTimer;
  final ValueNotifier<String?> _error = ValueNotifier(null);
  final List<StreamSubscription<dynamic>> _subs = [];
  int _retries = 0;
  Future<List<Programme>>? _epg;

  @override
  void initState() {
    super.initState();
    _epg = widget.epg?.call();
    // The lists behind the player hold decoded posters; release them while a video plays.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _start();
  }

  Future<void> _start() async {
    final s = AppSettings.instance;
    // mpv options (media_kit exposes them on the native platform player)
    final native = _player.platform as dynamic;
    Future<void> set(String k, String v) async {
      try {
        await native.setProperty(k, v);
      } catch (_) {
        // property not supported on this platform: ignore
      }
    }

    await set('hwdec', s.hwdec ? 'auto-safe' : 'no');
    await set('cache-secs', '${s.cacheSecs}');
    await set('demuxer-readahead-secs', '${s.cacheSecs}');
    if (s.tvMode) {
      // TV sticks have ~1 GB RAM: mpv's default demuxer cache (150 MiB forward + 150 MiB back) makes
      // the system swap. Keep it small and seek to the nearest keyframe (much faster than exact seeks).
      await set('demuxer-max-bytes', '48MiB');
      await set('demuxer-max-back-bytes', '16MiB');
      await set('hr-seek', 'no');
    }
    if (s.alang.isNotEmpty) await set('alang', s.alang);
    if (s.slang.isNotEmpty) {
      await set('slang', s.slang);
      await set('sid', 'auto');
    }

    Library.instance.touch(url: widget.url, title: widget.title, logo: widget.logo, kind: widget.kind);

    _subs.add(_player.stream.error.listen(_onError));
    _subs.add(_player.stream.playing.listen((playing) {
      if (playing) {
        _retries = 0;
        if (_error.value != null) _error.value = null;
      }
    }));
    if (widget.live) {
      // A live stream that "ends" has dropped: reconnect.
      _subs.add(_player.stream.completed.listen((done) {
        if (done) _onError('stream ended');
      }));
    }

    await _open();

    if (!widget.live) {
      if (s.resume) {
        final saved = Library.instance.positionFor(widget.url);
        if (saved != null) {
          await _player.stream.duration.firstWhere((d) => d > Duration.zero);
          await _player.seek(saved);
        }
      }
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    }
  }

  Future<void> _open() => _player.open(Media(widget.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));

  Future<AccountInfo?> _accountInfo() async {
    try {
      return await widget.client?.authenticate().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _onError(String message) async {
    if (!mounted) return;
    // Is the account's connection limit used up (e.g. watching on the PC and the TV stick at once)?
    final info = await _accountInfo();
    if (!mounted) return;
    if (info != null && info.limitReached) {
      final n = '${info.activeConnections}/${info.maxConnections}';
      if (widget.live && _retries < 3) {
        // The server may still count our own dropped connection for a few seconds: wait and retry.
        _retries++;
        _error.value = 'Bağlantı sınırı dolu ($n). Başka bir cihazda izleme açık olabilir ya da önceki bağlantın henüz kapanmadı. Yeniden deneniyor ($_retries/3)...';
        Future.delayed(Duration(seconds: 4 * _retries), () {
          if (mounted) _open();
        });
        return;
      }
      _error.value = 'Bağlantı sınırı dolu ($n).\n\nHesabın aynı anda en fazla ${info.maxConnections} cihazda izlemeye izin veriyor. '
          'Başka bir cihazda (TV, telefon, bilgisayar) açık yayını kapat, birkaç saniye bekle ve Tekrar dene.';
      return;
    }
    if (widget.live && _retries < 3) {
      _retries++;
      _error.value = 'Bağlantı koptu, yeniden deneniyor ($_retries/3)...';
      Future.delayed(Duration(seconds: 2 * _retries), () {
        if (mounted) _open();
      });
      return;
    }
    final refused = RegExp(r'(401|403|404|509|884|forbidden|unauthorized)', caseSensitive: false).hasMatch(message);
    _error.value = refused
        ? 'Yayın açılamadı. Sağlayıcı isteği reddetti (hesap süresi dolmuş ya da bağlantı sınırı olabilir).\n\n$message'
        : 'Yayın açılamadı.\n\n$message';
  }

  void _retry() {
    _retries = 0;
    _error.value = null;
    _open();
  }

  void _save() {
    if (widget.live) return;
    Library.instance.savePosition(widget.url, _player.state.position, _player.state.duration);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _save();
    _error.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Video(
        controller: _controller,
        controls: (state) => _Controls(state: state, player: _player, title: widget.title, live: widget.live, error: _error, onRetry: _retry, epg: _epg),
      ),
    );
  }
}

String _fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String _trackLabel(String id, String? title, String? language) {
  if (id == 'auto') return 'Otomatik';
  if (id == 'no') return 'Kapalı';
  final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
  return parts.isEmpty ? 'Parça $id' : parts.join(' · ');
}

class _Controls extends StatefulWidget {
  const _Controls({required this.state, required this.player, required this.title, required this.live, required this.error, required this.onRetry, this.epg});

  final VideoState state;
  final Player player;
  final String title;
  final bool live;
  final ValueNotifier<String?> error;
  final VoidCallback onRetry;
  final Future<List<Programme>>? epg;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _visible = true;
  int _hideToken = 0;
  String? _osd;
  int _osdToken = 0;
  double _lastVolume = 100;
  final FocusNode _root = FocusNode(debugLabel: 'player-root');
  final FocusNode _playNode = FocusNode(debugLabel: 'player-play');
  bool _barFocused = false; // remote focus is on the control bar (TV mode)

  Player get p => widget.player;
  bool get _tv => AppSettings.instance.tvMode;
  Duration get _skip => Duration(seconds: AppSettings.instance.skipSecs);

  void _poke() {
    if (!mounted) return;
    setState(() => _visible = true);
    final token = ++_hideToken;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && token == _hideToken && p.state.playing && !_barFocused) setState(() => _visible = false);
    });
  }

  void _flash(String text) {
    setState(() => _osd = text);
    final token = ++_osdToken;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && token == _osdToken) setState(() => _osd = null);
    });
  }

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _pending.dispose();
    _root.dispose();
    _playNode.dispose();
    super.dispose();
  }

  // Remote-friendly seeking: each press moves a pending target (steps grow while the key is held or tapped
  // quickly), the real seek happens once the user pauses.
  final ValueNotifier<Duration?> _pending = ValueNotifier(null);
  Timer? _commitTimer;
  int _scrubStreak = 0;
  DateTime _lastScrub = DateTime.fromMillisecondsSinceEpoch(0);

  void _scrub(int dir) {
    if (widget.live) return;
    final now = DateTime.now();
    _scrubStreak = now.difference(_lastScrub) < const Duration(milliseconds: 900) ? _scrubStreak + 1 : 0;
    _lastScrub = now;
    final ladder = [_skip.inSeconds, _skip.inSeconds, _skip.inSeconds, 30, 30, 60, 60, 120, 120, 300, 300, 600];
    final step = ladder[_scrubStreak.clamp(0, ladder.length - 1)];
    final total = p.state.duration;
    var target = (_pending.value ?? p.state.position) + Duration(seconds: dir * step);
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    _pending.value = target;
    _flash('${_fmt(target)}${total > Duration.zero ? ' / ${_fmt(total)}' : ''}   (${dir > 0 ? '+' : '−'}${step >= 60 ? '${step ~/ 60} dk' : '$step sn'})');
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 700), _commitScrub);
    _poke();
  }

  void _commitScrub() {
    _commitTimer?.cancel();
    final t = _pending.value;
    _pending.value = null;
    if (t != null) p.seek(t);
  }

  void _enterBar() {
    _barFocused = true;
    _poke();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playNode.requestFocus();
    });
  }

  void _leaveBar() {
    _barFocused = false;
    _root.requestFocus();
    _poke();
  }

  Future<void> _goTo() async {
    if (widget.live) return;
    final total = p.state.duration;
    final picked = await showDialog<Duration>(
      context: context,
      builder: (_) => _GoToDialog(initial: p.state.position, total: total),
    );
    if (picked != null) {
      p.seek(picked);
      _flash('→ ${_fmt(picked)}');
    }
    _poke();
  }

  void _seekBy(Duration delta) {
    if (widget.live) return;
    final target = p.state.position + delta;
    p.seek(target < Duration.zero ? Duration.zero : target);
    _flash('${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()} sn');
  }

  void _setVolume(double v) {
    final vol = v.clamp(0, 100).toDouble();
    p.setVolume(vol);
    _flash('Ses ${vol.round()}%');
  }

  void _toggleMute() {
    if (p.state.volume > 0) {
      _lastVolume = p.state.volume;
      p.setVolume(0);
      _flash('Sessiz');
    } else {
      p.setVolume(_lastVolume == 0 ? 100 : _lastVolume);
      _flash('Ses açık');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;

    // Media keys (remote controls, keyboards)
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause) {
      p.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_skip * 3);
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_skip * 3);
      _poke();
      return KeyEventResult.handled;
    }

    final isSelect = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;

    if (_tv) {
      // Bar mode: the arrows move between the buttons, OK presses them, Up goes back to the video.
      if (_barFocused) {
        if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.arrowUp) {
          _leaveBar();
          return KeyEventResult.handled;
        }
        _poke();
        return KeyEventResult.ignored;
      }
      // Video mode: Up/Down open the control bar (it is not built while hidden, so focus it after the next frame).
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        _enterBar();
        return KeyEventResult.handled;
      }
      if (isSelect) {
        if (_pending.value != null) {
          _commitScrub();
        } else {
          p.playOrPause();
        }
        _poke();
        return KeyEventResult.handled;
      }
      // Left/Right fall through to the scrubbing below.
    }

    if (k == LogicalKeyboardKey.space) {
      p.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _scrub(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _scrub(-1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(p.state.volume + 5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(p.state.volume - 5);
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyF) {
      widget.state.toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      // (Android's Back key is handled by the system; handling it here as well popped several routes at once.)
      if (widget.state.isFullscreen()) {
        widget.state.exitFullscreen();
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    _poke();
    return KeyEventResult.handled;
  }

  Future<void> _pick<T>(String title, List<T> options, T current, String Function(T) label, void Function(T) set) async {
    final choice = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final t in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(children: [SizedBox(width: 28, child: t == current ? const Icon(Icons.check, size: 18) : null), Expanded(child: Text(label(t)))]),
            ),
        ],
      ),
    );
    if (choice != null) set(choice);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _root,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _poke(),
        cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            p.playOrPause();
            _poke();
          },
          onDoubleTap: () => widget.state.toggleFullscreen(),
          child: Stack(children: [
            // buffering indicator
            Center(
              child: StreamBuilder<bool>(
                stream: p.stream.buffering,
                builder: (_, s) => (s.data ?? false) ? const CircularProgressIndicator() : const SizedBox.shrink(),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: widget.error,
              builder: (_, msg, _) {
                if (msg == null) return const SizedBox.shrink();
                final retrying = msg.contains('Yeniden deneniyor') || msg.startsWith('Bağlantı koptu');
                return Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(msg, textAlign: TextAlign.center),
                      if (!retrying) ...[
                        const SizedBox(height: 16),
                        FilledButton(autofocus: true, onPressed: widget.onRetry, child: const Text('Tekrar dene')),
                      ],
                    ]),
                  ),
                );
              },
            ),
            if (_osd != null)
              Positioned(
                top: 60,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(_osd!, style: const TextStyle(fontSize: 16)),
                ),
              ),
            // Not built at all while hidden, so position/volume streams don't rebuild an invisible UI.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _visible ? KeyedSubtree(key: const ValueKey('chrome'), child: _chrome(context)) : const SizedBox.expand(key: ValueKey('hidden')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87], stops: [0, .25, .65, 1]),
      ),
      child: Column(children: [
        Row(children: [
          BackButton(onPressed: () => Navigator.of(context).maybePop()),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              if (widget.epg != null)
                FutureBuilder<List<Programme>>(
                  future: widget.epg,
                  builder: (_, snap) {
                    final list = snap.data ?? const <Programme>[];
                    if (list.isEmpty) return const SizedBox.shrink();
                    final now = list.where((p) => p.isNow).firstOrNull;
                    final next = list.where((p) => p.start.isAfter(DateTime.now())).firstOrNull;
                    return Text(
                      [if (now != null) 'Şimdi: ${now.title}', if (next != null) 'Sıradaki: ${next.title}'].join('   ·   '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
            ]),
          ),
        ]),
        const Spacer(),
        if (!widget.live) ExcludeFocus(excluding: _tv, child: _seekBar()),
        FocusScope(
          onFocusChange: (focused) => _barFocused = focused && _tv,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Row(children: [
            StreamBuilder<bool>(
              stream: p.stream.playing,
              builder: (_, s) => IconButton(focusNode: _playNode, iconSize: 32, icon: Icon((s.data ?? p.state.playing) ? Icons.pause : Icons.play_arrow), onPressed: p.playOrPause),
            ),
            if (!widget.live) ...[
              IconButton(icon: const Icon(Icons.replay_10), onPressed: () => _seekBy(-_skip)),
              IconButton(icon: const Icon(Icons.forward_10), onPressed: () => _seekBy(_skip)),
              IconButton(tooltip: 'Zamana git', icon: const Icon(Icons.schedule), onPressed: _goTo),
            ],
            StreamBuilder<double>(
              stream: p.stream.volume,
              builder: (_, s) {
                final v = s.data ?? p.state.volume;
                return Row(children: [
                  IconButton(icon: Icon(v == 0 ? Icons.volume_off : Icons.volume_up), onPressed: _toggleMute),
                  // A slider eats the left/right keys, which would trap the remote's focus here. The TV has its own volume.
                  if (!_tv) SizedBox(width: 110, child: Slider(value: v.clamp(0, 100).toDouble(), max: 100, onChanged: p.setVolume)),
                ]);
              },
            ),
            const Spacer(),
            if (!widget.live)
              StreamBuilder<double>(
                stream: p.stream.rate,
                builder: (_, s) {
                  final r = s.data ?? p.state.rate;
                  return TextButton(
                    onPressed: () => _pick<double>('Oynatma hızı', const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], r, (v) => v == 1.0 ? 'Normal' : '${v}x', p.setRate),
                    child: Text(r == 1.0 ? '1x' : '${r}x'),
                  );
                },
              ),
            StreamBuilder<Tracks>(
              stream: p.stream.tracks,
              builder: (_, _) {
                final t = p.state.tracks;
                final cur = p.state.track;
                int real(Iterable<dynamic> l) => l.where((x) => x.id != 'auto' && x.id != 'no').length;
                return Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.audiotrack),
                    label: Text('Ses (${real(t.audio)})'),
                    onPressed: () => _pick<AudioTrack>('Ses', t.audio, cur.audio, (a) => _trackLabel(a.id, a.title, a.language), p.setAudioTrack),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.subtitles),
                    label: Text('Altyazı (${real(t.subtitle)})'),
                    onPressed: () => _pick<SubtitleTrack>('Altyazı', t.subtitle, cur.subtitle, (s) => _trackLabel(s.id, s.title, s.language), p.setSubtitleTrack),
                  ),
                ]);
              },
            ),
            IconButton(icon: const Icon(Icons.fullscreen), onPressed: () => widget.state.toggleFullscreen()),
          ]),
        )),
      ]),
    );
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      builder: (_, pos) => StreamBuilder<Duration>(
        stream: p.stream.duration,
        builder: (_, dur) {
          final total = dur.data ?? p.state.duration;
          final max = total.inMilliseconds.toDouble();
          return ValueListenableBuilder<Duration?>(
            valueListenable: _pending,
            builder: (_, pending, _) {
              final cur = pending ?? pos.data ?? p.state.position;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text(_fmt(cur), style: pending == null ? null : const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Slider(
                      value: max <= 0 ? 0 : cur.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: max <= 0 ? null : (v) => p.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text(max <= 0 ? '--:--' : _fmt(total)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

/// "Go to time" picker that works with a TV remote: ↑/↓ change the focused unit, ←/→ switch unit, OK confirms.
class _GoToDialog extends StatefulWidget {
  const _GoToDialog({required this.initial, required this.total});

  final Duration initial;
  final Duration total;

  @override
  State<_GoToDialog> createState() => _GoToDialogState();
}

class _GoToDialogState extends State<_GoToDialog> {
  late int _h = widget.initial.inHours;
  late int _m = widget.initial.inMinutes % 60;
  late int _s = widget.initial.inSeconds % 60;

  Duration get _value {
    final d = Duration(hours: _h, minutes: _m, seconds: _s);
    return widget.total > Duration.zero && d > widget.total ? widget.total : d;
  }

  Widget _unit(String label, int value, int max, void Function(int) set, {bool autofocus = false}) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp) {
          setState(() => set(value >= max ? 0 : value + 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          setState(() => set(value <= 0 ? max : value - 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          Navigator.pop(context, _value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: focused ? Colors.white : Colors.white24, width: focused ? 3 : 1),
            color: focused ? scheme.primary.withValues(alpha: 0.25) : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: () => setState(() => set(value >= max ? 0 : value + 1)), child: const Icon(Icons.keyboard_arrow_up)),
            Text(value.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
            InkWell(onTap: () => setState(() => set(value <= 0 ? max : value - 1)), child: const Icon(Icons.keyboard_arrow_down)),
            Text(label, style: const TextStyle(fontSize: 11)),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final maxH = total > Duration.zero ? total.inHours : 99;
    return AlertDialog(
      title: const Text('Zamana git'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          _unit('saat', _h, maxH, (v) => _h = v),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 30))),
          _unit('dakika', _m, 59, (v) => _m = v, autofocus: true),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 30))),
          _unit('saniye', _s, 59, (v) => _s = v),
        ]),
        const SizedBox(height: 12),
        Text(total > Duration.zero ? 'Toplam süre: ${_fmt(total)}' : '', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        const Text('↑↓ değiştir · ←→ alan seç · OK git', style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(onPressed: () => Navigator.pop(context, _value), child: const Text('Git')),
      ],
    );
  }
}
