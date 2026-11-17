import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_container.dart';
import 'glance_row.dart';
import 'lyrics_view.dart';
import 'plus_spicy.dart';

/// Kiosk Satellite Plus's home: a native screen in front of the Home
/// Assistant dashboard, which stays loaded underneath (and the Voice
/// Satellite with it). A clock and the At a Glance chips, the playing song
/// with its controls and its lyrics (word by word from Spicy Lyrics Plus,
/// else the kiosk's own), its animated cover and Spotify Canvas, and tiles
/// for the dashboard, the music library, apps, settings and the screensaver.
///
/// It shows on start, when Back is pressed over the dashboard, and after
/// [idleReturn] without a touch on the dashboard.
class PlusHome extends StatefulWidget {
  const PlusHome({
    super.key,
    required this.container,
    required this.visible,
    required this.onSettings,
  });

  final AppContainer container;

  /// Whether the home is in front; the screen sets it false for the
  /// dashboard and true to come back.
  final ValueNotifier<bool> visible;

  final VoidCallback onSettings;

  /// How long the dashboard may sit untouched before the home comes back.
  static const idleReturn = Duration(minutes: 5);

  @override
  State<PlusHome> createState() => _PlusHomeState();
}

class _PlusHomeState extends State<PlusHome> {
  AppContainer get c => widget.container;
  late final Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.visible.value) setState(() => _now = DateTime.now());
    });
    widget.visible.addListener(_followSpicy);
    _followSpicy();
  }

  bool _listening = false;

  /// Spicy's now playing is read only while the home is in front.
  void _followSpicy() {
    final want = widget.visible.value;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      SpicyFeed.instance.listen();
    } else {
      SpicyFeed.instance.unlisten();
    }
  }

  @override
  void dispose() {
    _clock.cancel();
    widget.visible.removeListener(_followSpicy);
    if (_listening) SpicyFeed.instance.unlisten();
    super.dispose();
  }

  /// Spicy Lyrics' always-on display when it's installed, else the kiosk's own screensaver.
  Future<void> _screensaver() async {
    if (await SpicyFeed.instance.openAod()) return;
    unawaited(c.commands.execute('startScreensaver', const {}));
  }

  void _dashboard() => widget.visible.value = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.visible,
      builder: (context, shown, child) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: shown ? 1 : 1.04,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            // Off screen, its tickers and clock rest.
            child: TickerMode(enabled: shown, child: child!),
          ),
        ),
      ),
      child: ValueListenableBuilder<Map<String, Object?>?>(
        valueListenable: c.sendspin.nowPlaying,
        builder: (context, now, _) => ValueListenableBuilder<SpicyNow?>(
          valueListenable: SpicyFeed.instance.now,
          builder: (context, spicy, _) => _body(context, now, spicy),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, Object?>? now, SpicyNow? spicy) {
    final art = '${now?['artworkUrl'] ?? ''}';
    final wide = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(artworkUrl: art, canvasUrl: spicy?.canvasUrl),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _left(context, now, spicy)),
                      const SizedBox(width: 32),
                      Expanded(flex: 4, child: _tiles(context, columns: 2)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: _left(context, now, spicy)),
                      const SizedBox(height: 24),
                      Expanded(flex: 4, child: _tiles(context, columns: 3)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _left(BuildContext context, Map<String, Object?>? now, SpicyNow? spicy) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final date = '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '$hour:$minute',
            style: const TextStyle(fontSize: 112, fontWeight: FontWeight.w200, height: 1, color: Colors.white, letterSpacing: -2),
          ),
        ),
        const SizedBox(height: 6),
        Text(date, style: TextStyle(fontSize: 22, color: Colors.white.withValues(alpha: 0.78), fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        GlanceRow(container: c),
        const SizedBox(height: 18),
        Expanded(child: _lyrics(now, spicy)),
        const SizedBox(height: 14),
        if (now != null)
          _NowPlayingCard(container: c, now: now, motionCoverUrl: spicy?.motionCoverUrl)
        else if (spicy != null)
          _SpicyCard(spicy: spicy)
        else
          _Idle(onDashboard: _dashboard),
      ],
    );
  }

  /// The song's lyrics: Spicy's, word by word, when it follows the same song
  /// (or the kiosk plays nothing itself), else the kiosk's own synced lines.
  Widget _lyrics(Map<String, Object?>? now, SpicyNow? spicy) {
    final kioskTitle = '${now?['title'] ?? ''}'.toLowerCase();
    final same = spicy != null && (now == null || kioskTitle.isEmpty || spicy.title.toLowerCase() == kioskTitle);
    final Widget lyrics;
    if (same && spicy.lines.isNotEmpty) {
      lyrics = Align(alignment: Alignment.bottomLeft, child: SpicyLyricsPanel(key: ValueKey(spicy.title), now: spicy));
    } else if (now != null) {
      lyrics = LyricsView(container: c, fontSize: 30);
    } else {
      lyrics = const SizedBox.shrink();
    }
    return ShaderMask(
      // The lines fade in at the top instead of being cut.
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white],
        stops: [0, 0.18, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: lyrics,
    );
  }

  Widget _tiles(BuildContext context, {required int columns}) {
    final tiles = <_Tile>[
      _Tile(Icons.dashboard_rounded, 'Home Assistant', 'Dashboard', const Color(0xFF41BDF5), _dashboard),
      _Tile(Icons.library_music_rounded, 'Music', 'Library', const Color(0xFFB57BFF), () => unawaited(c.musicLibrary.open())),
      _Tile(Icons.apps_rounded, 'Apps', 'Open an app', const Color(0xFF4ADE80), () => c.launcher.open()),
      _Tile(Icons.settings_rounded, 'Settings', 'Kiosk Satellite', const Color(0xFF9CA3AF), widget.onSettings),
      _Tile(Icons.nights_stay_rounded, 'Screensaver', 'Lyrics and clock', const Color(0xFFFACC15), () => unawaited(_screensaver())),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final rows = (tiles.length / columns).ceil();
        const gap = 14.0;
        final height = (box.maxHeight - gap * (rows - 1)) / rows;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final tile in tiles) SizedBox(width: width, height: height, child: _TileView(tile))],
        );
      },
    );
  }
}

/// The blurred album art when something plays, else a slow, soft gradient.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.artworkUrl, this.canvasUrl});

  final String artworkUrl;

  /// The song's Spotify Canvas, from Spicy Lyrics Plus: played behind
  /// everything in place of the blurred cover when there is one.
  final String? canvasUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E1726), Color(0xFF1B1036), Color(0xFF071A1E)],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: canvasUrl != null
              ? LoopVideo(key: ValueKey(canvasUrl), url: canvasUrl!, fallback: const SizedBox.expand())
              : artworkUrl.isEmpty
              ? const SizedBox.expand(key: ValueKey('none'))
              : ImageFiltered(
                  key: ValueKey(artworkUrl),
                  imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
                  child: Image.network(artworkUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.expand()),
                ),
        ),
        // A veil so white text reads over any cover.
        DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.42))),
      ],
    );
  }
}

/// Frosted glass, the look every card here shares.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 26, this.onTap});

  final Widget child;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: Colors.white.withValues(alpha: 0.09),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.container, required this.now, this.motionCoverUrl});

  final AppContainer container;
  final Map<String, Object?> now;

  /// The record's animated cover, from Spicy Lyrics Plus, over the still one.
  final String? motionCoverUrl;

  @override
  Widget build(BuildContext context) {
    final playing = now['playing'] == true;
    final art = '${now['artworkUrl'] ?? ''}';
    final title = '${now['title'] ?? ''}';
    final artist = '${now['artist'] ?? ''}';
    final control = container.sendspin.control;
    return _Glass(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.square(
                dimension: 96,
                child: _cover(art),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 16)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _RoundButton(Icons.skip_previous_rounded, () => unawaited(control('previous'))),
                      const SizedBox(width: 8),
                      _RoundButton(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, () => unawaited(control('toggle')), big: true),
                      const SizedBox(width: 8),
                      _RoundButton(Icons.skip_next_rounded, () => unawaited(control('next'))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _NowPlayingCard {
  Widget _cover(String art) {
    final still = art.isEmpty
        ? const ColoredBox(color: Color(0x22FFFFFF), child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 40))
        : Image.network(art, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x22FFFFFF)));
    final motion = motionCoverUrl;
    return motion == null ? still : LoopVideo(key: ValueKey(motion), url: motion, fallback: still);
  }
}

/// What Spicy Lyrics Plus follows when the kiosk plays nothing itself (a
/// phone app on this tablet): the song, with its animated cover.
class _SpicyCard extends StatelessWidget {
  const _SpicyCard({required this.spicy});

  final SpicyNow spicy;

  @override
  Widget build(BuildContext context) {
    final motion = spicy.motionCoverUrl;
    const still = ColoredBox(color: Color(0x22FFFFFF), child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 36));
    return _Glass(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: 72,
                child: motion == null ? still : LoopVideo(key: ValueKey(motion), url: motion, fallback: still),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(spicy.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(spicy.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.onDashboard});

  final VoidCallback onDashboard;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      onTap: onDashboard,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Icon(Icons.music_off_rounded, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Nothing playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 18)),
            ),
            Text('Open dashboard', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(this.icon, this.onTap, {this.big = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: big ? Colors.white : Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(big ? 12 : 9),
          child: Icon(icon, size: big ? 30 : 24, color: big ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.icon, this.title, this.subtitle, this.color, this.onTap);

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _TileView extends StatelessWidget {
  const _TileView(this.tile);

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      onTap: tile.onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tile.color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
              child: Icon(tile.icon, color: tile.color, size: 26),
            ),
            const Spacer(),
            Text(tile.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(tile.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
