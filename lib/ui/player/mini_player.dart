import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../player/player_controller.dart';
import '../queue/queue_sheet.dart';

/// Height of the collapsed player bar.
const double kMiniPlayerHeight = 60;

/// Right part of the YouTube mini player: title, channel, play/pause and close. The
/// video (texture or thumbnail) on the left is the shrunken watch-page player itself, so
/// expanding/collapsing is one continuous animation.
class MiniPlayerInfo extends ConsumerWidget {
  const MiniPlayerInfo({super.key, required this.onExpand, required this.onClose});
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (video, playing, buffering) = ref.watch(
      playerProvider.select((s) => (s.current, s.playing, s.buffering && s.error == null)),
    );
    final ctrl = ref.read(playerProvider.notifier);
    if (video == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      onLongPress: () => showQueueSheet(context),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    video.title,
                    key: ValueKey(video.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  video.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: buffering && !playing
                ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5))
                : IconButton(
                    onPressed: ctrl.togglePlay,
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                  ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 26)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Thin red progress line of the mini player.
class MiniProgressLine extends ConsumerWidget {
  const MiniProgressLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pos, dur) = ref.watch(playerProvider.select((s) => (s.position, s.duration)));
    final d = dur.inMilliseconds;
    final value = d > 0 ? (pos.inMilliseconds / d).clamp(0.0, 1.0) : 0.0;
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      color: YtColors.red,
      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
    );
  }
}
