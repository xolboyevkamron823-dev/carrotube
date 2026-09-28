import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../player/player_controller.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// Opens the play queue (reorder, swipe to remove, shuffle / repeat / autoplay).
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _QueueSheet(scroll: scroll),
    ),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (queue, index, shuffle, repeat, autoplay) = ref.watch(
      playerProvider.select((s) => (s.queue, s.index, s.shuffle, s.repeat, s.autoplay)),
    );
    final ctrl = ref.read(playerProvider.notifier);
    final current = index >= 0 && index < queue.length ? queue[index] : null;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('queue'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [if (current != null) current.title, '${index + 1} / ${queue.length}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ToggleIcon(
                icon: Icons.shuffle_rounded,
                active: shuffle,
                tooltip: context.tr('shuffle'),
                onPressed: ctrl.toggleShuffle,
              ),
              _ToggleIcon(
                icon: repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                active: repeat != RepeatMode.off,
                tooltip: context.tr(switch (repeat) {
                  RepeatMode.off => 'repeat_off',
                  RepeatMode.all => 'repeat_all',
                  RepeatMode.one => 'repeat_one',
                }),
                onPressed: ctrl.cycleRepeat,
              ),
              const Spacer(),
              Text(context.tr('autoplay'), style: theme.textTheme.bodyMedium),
              const SizedBox(width: 4),
              Switch(value: autoplay, onChanged: ctrl.setAutoplay),
            ],
          ),
          const Divider(),
        ],
      ),
    );

    if (queue.isEmpty) {
      return ListView(
        controller: scroll,
        children: [
          header,
          EmptyView(icon: Icons.queue_music_rounded, message: context.tr('queue_empty')),
        ],
      );
    }

    return ReorderableListView.builder(
      scrollController: scroll,
      buildDefaultDragHandles: false,
      header: header,
      itemCount: queue.length,
      // onReorderItem gives the final index; the controller expects the classic one.
      onReorderItem: (from, to) => ctrl.reorder(from, to > from ? to + 1 : to),
      proxyDecorator: (child, _, _) =>
          Material(elevation: 6, color: theme.colorScheme.surfaceContainerHighest, child: child),
      itemBuilder: (context, i) {
        final v = queue[i];
        final isCurrent = i == index;
        final tile = VideoTile(
          video: v,
          thumbWidth: 112,
          highlighted: isCurrent,
          onTap: () => ctrl.jumpTo(i),
          onLongPress: () {},
          subtitle: isCurrent
              ? Row(
                  children: [
                    const Icon(Icons.equalizer_rounded, size: 14, color: YtColors.red),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('now_playing'),
                      style: theme.textTheme.bodySmall?.copyWith(color: YtColors.red, fontWeight: FontWeight.w500),
                    ),
                  ],
                )
              : null,
          trailing: ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              child: Icon(Icons.drag_handle_rounded),
            ),
          ),
        );
        return Dismissible(
          key: ValueKey('q-${v.id}-$i'),
          direction: isCurrent ? DismissDirection.none : DismissDirection.horizontal,
          background: const _DismissBackground(alignment: Alignment.centerLeft),
          secondaryBackground: const _DismissBackground(alignment: Alignment.centerRight),
          onDismissed: (_) => ctrl.removeAt(i),
          child: tile,
        );
      },
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YtColors.red,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.icon, required this.active, required this.onPressed, this.tooltip});
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: active,
      style: IconButton.styleFrom(backgroundColor: active ? scheme.onSurface.withValues(alpha: 0.12) : null),
      icon: Icon(icon, color: active ? scheme.onSurface : scheme.onSurfaceVariant),
    );
  }
}
