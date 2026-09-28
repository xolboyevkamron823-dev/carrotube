import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../player/mini_player.dart';
import '../watch/player_view.dart';
import '../watch/watch_page.dart';

/// The watch page / mini player surface. [t] is the expansion progress (0 = mini player
/// above the bottom bar, 1 = full watch page). The player itself shrinks into the mini
/// player's thumbnail so the transition is one continuous motion like on YouTube.
class PlayerPanel extends ConsumerWidget {
  const PlayerPanel({
    super.key,
    required this.t,
    required this.screenSize,
    required this.topInset,
    required this.fullscreen,
    required this.onExpand,
    required this.onCollapse,
    required this.onClose,
    required this.onToggleFullscreen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double t;
  final Size screenSize;
  final double topInset;
  final bool fullscreen;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onClose;
  final VoidCallback onToggleFullscreen;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (audioOnly, aspect) = ref.watch(playerProvider.select((s) => (s.audioOnly, s.aspectRatio)));

    if (fullscreen) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          // Swipe down leaves full screen (YouTube).
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 250) onToggleFullscreen();
          },
          child: PlayerView(expanded: true, fullscreen: true, onToggleFullscreen: onToggleFullscreen),
        ),
      );
    }

    final w = screenSize.width;
    final h = screenSize.height;
    final double fullVideoH = audioOnly
        ? math.min(w, h * 0.46)
        : (w / (aspect > 0 ? aspect : 16 / 9)).clamp(w * 9 / 16, h * 0.6).toDouble();
    const miniH = kMiniPlayerHeight;
    const miniW = miniH * 16 / 9;
    final videoW = lerpDouble(miniW, w, t)!;
    final videoH = lerpDouble(miniH, fullVideoH, t)!;
    final topPad = topInset * t;
    final expanded = t >= 0.999;
    final miniOpacity = (1 - t * 3).clamp(0.0, 1.0);
    final detailsOpacity = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    final miniBg = dark ? scheme.surfaceContainer : scheme.surface;
    final bg = Color.lerp(miniBg, scheme.surface, t)!;

    final content = Stack(
      children: [
        Column(
          children: [
            if (topPad > 0) Container(height: topPad, color: Colors.black),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: expanded ? null : onExpand,
              onVerticalDragStart: onDragStart,
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: SizedBox(
                height: videoH,
                child: Row(
                  children: [
                    SizedBox(
                      width: videoW,
                      height: videoH,
                      child: PlayerView(
                        expanded: expanded,
                        onMinimize: onCollapse,
                        onToggleFullscreen: onToggleFullscreen,
                      ),
                    ),
                    Expanded(
                      child: miniOpacity > 0
                          ? Opacity(
                              opacity: miniOpacity,
                              child: MiniPlayerInfo(onExpand: onExpand, onClose: onClose),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            if (t > 0.001)
              Expanded(
                child: IgnorePointer(
                  ignoring: !expanded,
                  child: Opacity(
                    opacity: detailsOpacity,
                    child: MediaQuery.removePadding(context: context, removeTop: true, child: const WatchDetails()),
                  ),
                ),
              ),
          ],
        ),
        if (miniOpacity > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Opacity(opacity: miniOpacity, child: const MiniProgressLine()),
          ),
      ],
    );

    final panel = ScaffoldMessenger(
      child: Scaffold(backgroundColor: bg, resizeToAvoidBottomInset: false, body: content),
    );

    return t > 0.5 ? AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: panel) : panel;
  }
}
