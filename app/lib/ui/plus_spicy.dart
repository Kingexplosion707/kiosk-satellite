import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'video_surface.dart';

/// One timed word of a Spicy Lyrics line.
class SpicyWord {
  const SpicyWord(this.text, this.startMs, this.endMs, this.attached);

  final String text;
  final int startMs;
  final int endMs;

  /// Glued to the word before it, with no space between.
  final bool attached;
}

class SpicyLine {
  const SpicyLine(this.text, this.startMs, this.endMs, this.words, this.background);

  final String text;
  final int startMs;
  final int endMs;
  final List<SpicyWord> words;
  final bool background;
}

/// What Spicy Lyrics Plus says plays now (its NowPlayingProvider).
class SpicyNow {
  SpicyNow({
    required this.title,
    required this.artist,
    required this.positionMs,
    required this.playing,
    required this.lines,
    required this.motionCoverUrl,
    required this.canvasUrl,
    required this.at,
  });

  final String title;
  final String artist;
  final int positionMs;
  final bool playing;
  final List<SpicyLine> lines;
  final String? motionCoverUrl;
  final String? canvasUrl;

  /// When [positionMs] was read, to carry it on between reads.
  final DateTime at;

  int positionNow() =>
      playing ? positionMs + DateTime.now().difference(at).inMilliseconds : positionMs;

  static SpicyNow? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final title = m['title'] as String?;
    if (title == null) return null;
    final lines = <SpicyLine>[];
    for (final raw in (m['lines'] as List<dynamic>? ?? const [])) {
      final l = raw as Map<String, dynamic>;
      lines.add(SpicyLine(
        l['text'] as String? ?? '',
        (l['startMs'] as num?)?.toInt() ?? 0,
        (l['endMs'] as num?)?.toInt() ?? 0,
        [
          for (final w in (l['words'] as List<dynamic>? ?? const []))
            SpicyWord(
              (w as Map<String, dynamic>)['text'] as String? ?? '',
              (w['startMs'] as num?)?.toInt() ?? 0,
              (w['endMs'] as num?)?.toInt() ?? 0,
              w['attached'] == true,
            ),
        ],
        l['background'] == true,
      ));
    }
    return SpicyNow(
      title: title,
      artist: m['artist'] as String? ?? '',
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      playing: m['playing'] == true,
      lines: lines,
      motionCoverUrl: m['motionCoverUrl'] as String?,
      canvasUrl: m['canvasUrl'] as String?,
      at: DateTime.now(),
    );
  }
}

/// Spicy Lyrics Plus, from the kiosk: its now playing, read once a second
/// while someone listens, and its always-on display as the screensaver.
class SpicyFeed {
  SpicyFeed._();

  static final instance = SpicyFeed._();
  static const _channel = MethodChannel('kiosk_satellite/background');

  final now = ValueNotifier<SpicyNow?>(null);
  Timer? _poll;
  int _listeners = 0;

  void listen() {
    if (_listeners++ == 0) {
      unawaited(_read());
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_read()));
    }
  }

  void unlisten() {
    if (--_listeners <= 0) {
      _listeners = 0;
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _read() async {
    try {
      final json = await _channel.invokeMethod<String>('spicyNowPlaying');
      final next = SpicyNow.parse(json);
      // Keep the same lines object across reads of one song, so what draws
      // them only rebuilds when the song or its lyrics change.
      final last = now.value;
      if (next != null && last != null && last.title == next.title && last.lines.length == next.lines.length) {
        now.value = SpicyNow(
          title: next.title, artist: next.artist, positionMs: next.positionMs, playing: next.playing,
          lines: last.lines, motionCoverUrl: next.motionCoverUrl, canvasUrl: next.canvasUrl, at: next.at,
        );
      } else {
        now.value = next;
      }
    } catch (_) {
      now.value = null;
    }
  }

  /// Opens Spicy's always-on display over the kiosk; false without Spicy.
  Future<bool> openAod() async {
    try {
      return await _channel.invokeMethod<bool>('openSpicyAod') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Spicy's lyrics, word by word: the line being sung lit as it's sung, the
/// next ones after it dimmer, in Spicy Lyrics' manner.
class SpicyLyricsPanel extends StatefulWidget {
  const SpicyLyricsPanel({super.key, required this.now, this.fontSize = 34});

  final SpicyNow now;
  final double fontSize;

  @override
  State<SpicyLyricsPanel> createState() => _SpicyLyricsPanelState();
}

class _SpicyLyricsPanelState extends State<SpicyLyricsPanel> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _position = 0;

  @override
  void initState() {
    super.initState();
    _position = widget.now.positionNow();
    _ticker = createTicker((_) {
      final p = widget.now.positionNow();
      if ((p - _position).abs() >= 16) setState(() => _position = p);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.now.lines.where((l) => !l.background).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    var at = lines.lastIndexWhere((l) => l.startMs <= _position);
    if (at < 0) at = 0;
    final shown = lines.sublist(at, (at + 3).clamp(0, lines.length));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: child),
            ),
            child: Padding(
              key: ValueKey('${shown[i].startMs}-$i'),
              padding: const EdgeInsets.only(bottom: 10),
              child: i == 0
                  ? _sung(shown[i], widget.fontSize)
                  : Text(shown[i].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: i == 1 ? 0.42 : 0.24),
                        fontSize: widget.fontSize * 0.82,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      )),
            ),
          ),
      ],
    );
  }

  /// The line being sung: each word fills from dim to white as it's sung,
  /// with a soft glow on the word under way.
  Widget _sung(SpicyLine line, double size) {
    final words = line.words.isEmpty ? [SpicyWord(line.text, line.startMs, line.endMs, false)] : line.words;
    final spans = <InlineSpan>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final span = (w.endMs - w.startMs).clamp(1, 1 << 30);
      final t = ((_position - w.startMs) / span).clamp(0.0, 1.0);
      final singing = t > 0 && t < 1;
      final text = (i > 0 && !w.attached ? ' ' : '') + w.text;
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          color: Color.lerp(Colors.white.withValues(alpha: 0.38), Colors.white, t),
          shadows: singing ? [Shadow(color: Colors.white.withValues(alpha: 0.55 * t), blurRadius: 18)] : null,
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.3),
    );
  }
}

/// A muted, looping video (an animated cover or a Spotify Canvas), cropped
/// to fill its box. Shows [fallback] until its first frame, or if it fails.
class LoopVideo extends StatefulWidget {
  const LoopVideo({super.key, required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  State<LoopVideo> createState() => _LoopVideoState();
}

class _LoopVideoState extends State<LoopVideo> {
  VideoPlayerController? _video;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final video = await openVideo(
        (type) => VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: mutedVideoOptions, viewType: type),
      );
      if (_gone) {
        await video.dispose();
        return;
      }
      await video.setVolume(0);
      await video.setLooping(true);
      await video.play();
      if (mounted) setState(() => _video = video);
    } catch (_) {
      // The still cover stays.
    }
  }

  @override
  void dispose() {
    _gone = true;
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.fallback,
        if (video != null && video.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)),
          ),
      ],
    );
  }
}
