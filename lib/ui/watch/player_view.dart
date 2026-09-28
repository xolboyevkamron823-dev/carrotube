import 'dart:async';
import 'dart:ui' as ui;

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../queue/queue_sheet.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';

/// The video area of the watch page: live texture (or YouTube Music style artwork in
/// audio-only mode), controls overlay, double-tap seeking, buffering and error states.
/// With [expanded] false it only renders the media (mini player / transitions).
class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({
    super.key,
    this.expanded = true,
    this.fullscreen = false,
    this.pipMode = false,
    this.onMinimize,
    this.onToggleFullscreen,
  });

  final bool expanded;
  final bool fullscreen;
  final bool pipMode;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> with TickerProviderStateMixin {
  bool _controlsVisible = false;
  Timer? _hideTimer;

  // Double-tap seeking (accumulates like YouTube: 10, 20, 30 seconds ...).
  int _seekSide = 0;
  int _seekSeconds = 0;
  Timer? _seekResetTimer;
  Offset _lastTapPosition = Offset.zero;
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  bool _scrubbing = false;

  @override
  void didUpdateWidget(PlayerView old) {
    super.didUpdateWidget(old);
    if (!widget.expanded && _controlsVisible) {
      _hideTimer?.cancel();
      _controlsVisible = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekResetTimer?.cancel();
    _ripple.dispose();
    super.dispose();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final s = ref.read(playerProvider);
      if (s.playing && !_scrubbing && s.error == null) {
        setState(() => _controlsVisible = false);
      } else {
        _scheduleHide();
      }
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
  }

  void _onTap() {
    if (_seekSide != 0 && _seekResetTimer?.isActive == true) {
      // Taps right after a double tap keep seeking on the same side (YouTube behaviour).
      _seekAt(_lastTapPosition);
      return;
    }
    _controlsVisible ? _hideControls() : _showControls();
  }

  void _seekAt(Offset position) {
    final width = context.size?.width ?? 1;
    final side = position.dx < width / 2 ? -1 : 1;
    if (side != _seekSide) _seekSeconds = 0;
    _seekSide = side;
    _seekSeconds += 10;
    ref.read(playerProvider.notifier).seekRelative(10 * side);
    _ripple.forward(from: 0);
    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _seekSide = 0;
        _seekSeconds = 0;
      });
    });
    setState(() {});
  }

  Future<void> _startPip() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final ok = await ref.read(playerProvider.notifier).startPip(rect);
    if (!ok && mounted) showToast(context, context.tr('pip_unavailable'));
  }

  @override
  Widget build(BuildContext context) {
    final media = _PlayerMedia(fullscreen: widget.fullscreen);
    if (widget.pipMode || !widget.expanded) {
      return ColoredBox(color: Colors.black, child: media);
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          media,
          // Gesture layer.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _lastTapPosition = d.localPosition,
            onTap: _onTap,
            onDoubleTapDown: (d) => _lastTapPosition = d.localPosition,
            onDoubleTap: () => _seekAt(_lastTapPosition),
          ),
          if (_seekSide != 0) _SeekRipple(side: _seekSide, seconds: _seekSeconds, animation: _ripple),
          _BufferingIndicator(controlsVisible: _controlsVisible),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _ControlsOverlay(
                fullscreen: widget.fullscreen,
                onInteraction: _scheduleHide,
                onScrubbing: (v) => _scrubbing = v,
                onMinimize: widget.onMinimize,
                onToggleFullscreen: widget.onToggleFullscreen,
                onPip: _startPip,
              ),
            ),
          ),
          if (!_controlsVisible && !widget.fullscreen)
            const Positioned(left: 0, right: 0, bottom: 0, child: _ThinProgress()),
          const _ErrorOverlay(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------------------
class _PlayerMedia extends ConsumerWidget {
  const _PlayerMedia({required this.fullscreen});
  final bool fullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (video, textureId, audioOnly, aspect) = ref.watch(
      playerProvider.select((s) => (s.current, s.textureId, s.audioOnly, s.aspectRatio)),
    );
    if (video == null) return const ColoredBox(color: Colors.black);
    final Widget child;
    if (!audioOnly && textureId != null) {
      child = Center(
        key: ValueKey('tex$textureId'),
        child: AspectRatio(
          aspectRatio: aspect > 0 ? aspect : 16 / 9,
          child: Texture(textureId: textureId, filterQuality: FilterQuality.medium),
        ),
      );
    } else if (audioOnly) {
      child = AudioArtwork(key: ValueKey('art${video.id}'), video: video);
    } else {
      child = Center(
        key: ValueKey('thumb${video.id}'),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: NetImage(video.maxThumbnailUrl, fallbackUrl: video.thumbnailUrl),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child),
    );
  }
}

/// YouTube Music style artwork: blurred cover in the background, square art on top.
class AudioArtwork extends StatelessWidget {
  const AudioArtwork({super.key, required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxHeight < 120;
        final cover = NetImage(video.maxThumbnailUrl, fallbackUrl: video.thumbnailUrl);
        if (compact) return SizedBox.expand(child: cover);
        final side = (c.maxHeight - 32).clamp(0.0, c.maxWidth - 32);
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36, tileMode: TileMode.clamp),
              child: NetImage(video.thumbnailUrl),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            Center(
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
                ),
                clipBehavior: Clip.antiAlias,
                child: cover,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------
// Overlays
// ---------------------------------------------------------------------------------------
class _BufferingIndicator extends ConsumerWidget {
  const _BufferingIndicator({required this.controlsVisible});
  final bool controlsVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (buffering, hasError) = ref.watch(playerProvider.select((s) => (s.buffering, s.error != null)));
    // With controls visible the spinner replaces the play button instead.
    if (!buffering || hasError || controlsVisible) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Center(
        child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3.5, color: Colors.white)),
      ),
    );
  }
}

class _ErrorOverlay extends ConsumerWidget {
  const _ErrorOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(playerProvider.select((s) => s.error));
    if (error == null) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 36),
              const SizedBox(height: 8),
              Text(
                context.tr('playback_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  final s = ref.read(playerProvider);
                  final cur = s.current;
                  if (cur != null) ref.read(playerProvider.notifier).playVideo(cur, queue: s.queue);
                },
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.tr('retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinProgress extends ConsumerWidget {
  const _ThinProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pos, dur, buf) = ref.watch(playerProvider.select((s) => (s.position, s.duration, s.buffered)));
    final d = dur.inMilliseconds;
    final played = d > 0 ? (pos.inMilliseconds / d).clamp(0.0, 1.0) : 0.0;
    final buffered = d > 0 ? (buf.inMilliseconds / d).clamp(0.0, 1.0) : 0.0;
    return IgnorePointer(
      child: SizedBox(
        height: 2,
        child: CustomPaint(
          painter: _TrackPainter(played: played, buffered: buffered, trackHeight: 2),
        ),
      ),
    );
  }
}

class _SeekRipple extends StatelessWidget {
  const _SeekRipple({required this.side, required this.seconds, required this.animation});
  final int side;
  final int seconds;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final left = side < 0;
    return IgnorePointer(
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: 0.42,
          heightFactor: 1,
          child: ClipPath(
            clipper: _ArcClipper(left: left),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value;
                return ColoredBox(
                  color: Colors.white.withValues(alpha: 0.10 + 0.08 * (1 - t)),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Chevrons(left: left, t: t),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('seconds_n', {'n': '$seconds'}),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Three triangles lighting up one after another.
class _Chevrons extends StatelessWidget {
  const _Chevrons({required this.left, required this.t});
  final bool left;
  final double t;

  @override
  Widget build(BuildContext context) {
    final icons = List.generate(3, (i) {
      final phase = (t * 3 - i).clamp(0.0, 1.0);
      final opacity = 0.35 + 0.65 * (phase < 0.5 ? phase * 2 : 2 - phase * 2);
      return Icon(
        left ? Icons.arrow_left_rounded : Icons.arrow_right_rounded,
        color: Colors.white.withValues(alpha: opacity.clamp(0.35, 1.0)),
        size: 26,
      );
    });
    return Row(mainAxisSize: MainAxisSize.min, children: left ? icons.reversed.toList() : icons);
  }
}

class _ArcClipper extends CustomClipper<Path> {
  const _ArcClipper({required this.left});
  final bool left;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final rect = left
        ? Rect.fromLTRB(-w * 1.1, -h * 0.35, w, h * 1.35)
        : Rect.fromLTRB(0, -h * 0.35, w * 2.1, h * 1.35);
    return Path()..addOval(rect);
  }

  @override
  bool shouldReclip(_ArcClipper oldClipper) => oldClipper.left != left;
}

// ---------------------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------------------
class _ControlsOverlay extends ConsumerStatefulWidget {
  const _ControlsOverlay({
    required this.fullscreen,
    required this.onInteraction,
    required this.onScrubbing,
    required this.onPip,
    this.onMinimize,
    this.onToggleFullscreen,
  });

  final bool fullscreen;
  final VoidCallback onInteraction;
  final ValueChanged<bool> onScrubbing;
  final VoidCallback onPip;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends ConsumerState<_ControlsOverlay> {
  Duration? _scrub;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(playerProvider);
    final ctrl = ref.read(playerProvider.notifier);
    final fs = widget.fullscreen;
    final pos = _scrub ?? s.position;
    final ended = s.state == NativePlaybackState.ended;
    final bigIcon = fs ? 64.0 : 52.0;
    const iconColor = Colors.white;
    final video = s.current;

    Widget iconButton(IconData icon, VoidCallback? onPressed, {double size = 24, String? tooltip}) => IconButton(
      onPressed: onPressed == null
          ? null
          : () {
              widget.onInteraction();
              onPressed();
            },
      tooltip: tooltip,
      icon: Icon(icon, size: size),
      color: iconColor,
      disabledColor: Colors.white38,
    );

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: SafeArea(
        top: fs,
        bottom: fs,
        left: fs,
        right: fs,
        child: Stack(
          children: [
            // Top bar.
            Positioned(
              left: 4,
              right: 4,
              top: 2,
              child: Row(
                children: [
                  if (!fs && widget.onMinimize != null)
                    iconButton(
                      Icons.keyboard_arrow_down_rounded,
                      widget.onMinimize,
                      size: 30,
                      tooltip: context.tr('minimize'),
                    ),
                  if (fs && video != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  iconButton(Icons.playlist_play_rounded, () => showQueueSheet(context), tooltip: context.tr('queue')),
                  if (!s.audioOnly && s.textureId != null)
                    iconButton(Icons.picture_in_picture_alt_rounded, widget.onPip, tooltip: context.tr('pip')),
                  iconButton(
                    Icons.settings_outlined,
                    () => showPlayerSettings(context),
                    tooltip: context.tr('settings'),
                  ),
                ],
              ),
            ),
            // Centre transport.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconButton(Icons.skip_previous_rounded, s.isActive ? ctrl.previous : null, size: 36),
                  SizedBox(width: fs ? 48 : 28),
                  SizedBox(
                    width: bigIcon + 16,
                    height: bigIcon + 16,
                    child: s.buffering && s.error == null
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 3.5, color: Colors.white),
                          )
                        : IconButton(
                            onPressed: () {
                              widget.onInteraction();
                              if (ended) {
                                ctrl.seek(Duration.zero).then((_) => ctrl.play());
                              } else {
                                ctrl.togglePlay();
                              }
                            },
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                              child: Icon(
                                ended
                                    ? Icons.replay_rounded
                                    : (s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                key: ValueKey('${s.playing}$ended'),
                                size: bigIcon,
                              ),
                            ),
                            color: iconColor,
                          ),
                  ),
                  SizedBox(width: fs ? 48 : 28),
                  iconButton(Icons.skip_next_rounded, s.hasNext ? ctrl.next : null, size: 36),
                ],
              ),
            ),
            // Bottom: time + fullscreen + seek bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatDuration(pos),
                                style: const TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text:
                                    ' / ${video?.isLive == true ? context.tr('live_badge') : formatDuration(s.duration)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        if (s.speed != 1.0)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text('${s.speed}x', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (widget.onToggleFullscreen != null)
                          iconButton(
                            fs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            widget.onToggleFullscreen,
                            size: 26,
                            tooltip: context.tr('fullscreen'),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(fs ? 16 : 0, 0, fs ? 16 : 0, fs ? 12 : 0),
                    child: YtSeekBar(
                      position: pos,
                      duration: s.duration,
                      buffered: s.buffered,
                      onScrubStart: () {
                        widget.onScrubbing(true);
                        widget.onInteraction();
                      },
                      onScrubUpdate: (d) => setState(() => _scrub = d),
                      onSeek: (d) {
                        widget.onScrubbing(false);
                        widget.onInteraction();
                        ctrl.seek(d);
                        setState(() => _scrub = null);
                      },
                    ),
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

/// YouTube seek bar: grey track, lighter buffered part, red played part and red thumb.
class YtSeekBar extends StatefulWidget {
  const YtSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    this.onScrubStart,
    this.onScrubUpdate,
  });

  final Duration position, duration, buffered;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;

  @override
  State<YtSeekBar> createState() => _YtSeekBarState();
}

class _YtSeekBarState extends State<YtSeekBar> {
  double? _drag;

  Duration _at(double fraction) => Duration(milliseconds: (widget.duration.inMilliseconds * fraction).round());

  double _fraction(Offset local, double width) => (local.dx / (width <= 0 ? 1 : width)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final d = widget.duration.inMilliseconds;
    final played = _drag ?? (d > 0 ? (widget.position.inMilliseconds / d).clamp(0.0, 1.0) : 0.0);
    final buffered = d > 0 ? (widget.buffered.inMilliseconds / d).clamp(0.0, 1.0) : 0.0;
    final enabled = d > 0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: !enabled
              ? null
              : (e) {
                  widget.onScrubStart?.call();
                  setState(() => _drag = _fraction(e.localPosition, w));
                },
          onHorizontalDragUpdate: !enabled
              ? null
              : (e) {
                  final f = _fraction(e.localPosition, w);
                  setState(() => _drag = f);
                  widget.onScrubUpdate?.call(_at(f));
                },
          onHorizontalDragEnd: !enabled
              ? null
              : (_) {
                  final f = _drag ?? played;
                  setState(() => _drag = null);
                  widget.onSeek(_at(f));
                },
          onTapUp: !enabled
              ? null
              : (e) {
                  widget.onScrubStart?.call();
                  widget.onSeek(_at(_fraction(e.localPosition, w)));
                },
          child: SizedBox(
            height: 24,
            width: w,
            child: CustomPaint(
              painter: _TrackPainter(
                played: played,
                buffered: buffered,
                trackHeight: _drag != null ? 4 : 3,
                thumbRadius: _drag != null ? 8 : 6,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.played, required this.buffered, required this.trackHeight, this.thumbRadius = 0});
  final double played, buffered, trackHeight, thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final top = y - trackHeight / 2;
    final w = size.width;
    final paint = Paint();
    canvas.drawRect(Rect.fromLTWH(0, top, w, trackHeight), paint..color = Colors.white.withValues(alpha: 0.3));
    canvas.drawRect(
      Rect.fromLTWH(0, top, w * buffered, trackHeight),
      paint..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawRect(Rect.fromLTWH(0, top, w * played, trackHeight), paint..color = YtColors.red);
    if (thumbRadius > 0) {
      canvas.drawCircle(
        Offset((w * played).clamp(thumbRadius, w - thumbRadius), y),
        thumbRadius,
        paint..color = YtColors.red,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.trackHeight != trackHeight ||
      old.thumbRadius != thumbRadius;
}

// ---------------------------------------------------------------------------------------
// Settings sheet (quality, speed, audio-only)
// ---------------------------------------------------------------------------------------
const playbackSpeeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

String speedLabel(BuildContext context, double s) => s == 1.0 ? context.tr('normal') : '${s}x';

Future<void> showPlayerSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => const _PlayerSettingsSheet(),
  );
}

class _PlayerSettingsSheet extends ConsumerWidget {
  const _PlayerSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(playerProvider);
    final ctrl = ref.read(playerProvider.notifier);
    final choices = s.streams?.videoChoices ?? const <StreamChoice>[];
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: Text(context.tr('quality')),
            trailing: Text(s.audioOnly ? context.tr('audio_only') : (s.quality?.label ?? '—'), style: secondary),
            enabled: !s.audioOnly && choices.isNotEmpty,
            onTap: () => _pick<StreamChoice>(
              context,
              title: context.tr('quality'),
              values: choices,
              label: (c) => c.label,
              selected: (c) => c.height == s.quality?.height,
              onSelected: ctrl.setQuality,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.slow_motion_video_rounded),
            title: Text(context.tr('speed')),
            trailing: Text(speedLabel(context, s.speed), style: secondary),
            onTap: () => _pick<double>(
              context,
              title: context.tr('speed'),
              values: playbackSpeeds,
              label: (v) => speedLabel(context, v),
              selected: (v) => v == s.speed,
              onSelected: ctrl.setSpeed,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones_rounded),
            title: Text(context.tr('audio_only')),
            subtitle: Text(context.tr('audio_only_sub')),
            value: s.audioOnly,
            onChanged: ctrl.setAudioOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: Text(context.tr('autoplay')),
            value: s.autoplay,
            onChanged: ctrl.setAutoplay,
          ),
          if (s.streams?.audioBitrateKbps != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.graphic_eq_rounded),
              title: Text(context.tr('audio_stream')),
              trailing: Text(
                '${s.streams!.audioCodec ?? ''} ${s.streams!.audioBitrateKbps} kbps'.trim(),
                style: secondary,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _pick<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required String Function(T) label,
    required bool Function(T) selected,
    required Future<void> Function(T) onSelected,
  }) {
    final nav = Navigator.of(context)..pop();
    showModalBottomSheet<void>(
      context: nav.context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              for (final v in values)
                ListTile(
                  leading: selected(v) ? const Icon(Icons.check_rounded) : const SizedBox(width: 24),
                  title: Text(label(v)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSelected(v);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
