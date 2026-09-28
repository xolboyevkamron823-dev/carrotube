import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/feed.dart';
import '../../data/models.dart';
import '../nav.dart';
import 'avatar.dart';
import 'sheets.dart';
import 'thumbnail.dart';

/// Avatar of a channel that is looked up lazily (letter avatar until it arrives).
class ChannelAvatar extends ConsumerWidget {
  const ChannelAvatar({super.key, required this.channelId, required this.name, this.size = 36});
  final String? channelId;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = channelId;
    final url = id == null ? null : ref.watch(channelInfoProvider(id)).value?.avatarUrl;
    return AppAvatar(url: url, name: name, size: size);
  }
}

/// Big home-feed card: 16:9 thumbnail, avatar, title, meta line and 3-dot menu.
class VideoCard extends ConsumerWidget {
  const VideoCard({super.key, required this.video, this.onTap, this.menuActions = const [], this.showAvatar = true});

  final VideoItem video;
  final VoidCallback? onTap;
  final List<VideoMenuAction> menuActions;
  final bool showAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return InkWell(
      onTap: onTap ?? () => openVideo(ref, video),
      onLongPress: () => showVideoMenu(context, video, extra: menuActions),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: VideoThumbnail(video: video, highRes: width > 480, cacheWidth: width),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAvatar) ...[
                    GestureDetector(
                      onTap: video.channelId == null
                          ? null
                          : () => openChannel(context, video.channelId!, title: video.channelName),
                      child: ChannelAvatar(channelId: video.channelId, name: video.channelName),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          videoMetaLine(context, video),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _MoreButton(onPressed: () => showVideoMenu(context, video, extra: menuActions)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.more_vert, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
    );
  }
}

/// Compact row (Up next, playlists, history, queue).
class VideoTile extends ConsumerWidget {
  const VideoTile({
    super.key,
    required this.video,
    this.onTap,
    this.onLongPress,
    this.menuActions = const [],
    this.index,
    this.highlighted = false,
    this.trailing,
    this.thumbWidth = 160,
    this.showMenu = true,
    this.progress,
    this.subtitle,
  });

  final VideoItem video;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<VideoMenuAction> menuActions;

  /// Optional leading position number (playlists).
  final int? index;
  final bool highlighted;

  /// Replaces the 3-dot menu (e.g. drag handle in the queue).
  final Widget? trailing;
  final double thumbWidth;
  final bool showMenu;
  final double? progress;

  /// Replaces the meta line.
  final Widget? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 12);
    final meta = videoMetaLine(context, video, withChannel: false);
    return Material(
      color: highlighted ? theme.colorScheme.surfaceContainerHighest : Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => openVideo(ref, video),
        onLongPress: onLongPress ?? () => showVideoMenu(context, video, extra: menuActions),
        child: Padding(
          padding: EdgeInsets.fromLTRB(index == null ? 12 : 4, 6, 0, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index != null)
                SizedBox(
                  width: 28,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: highlighted
                        ? const Icon(Icons.play_arrow_rounded, size: 18, color: YtColors.red)
                        : Text('$index', textAlign: TextAlign.center, style: secondary),
                  ),
                ),
              SizedBox(
                width: thumbWidth,
                child: VideoThumbnail(video: video, radius: 8, cacheWidth: thumbWidth, progress: progress),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(video.channelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                    if (subtitle != null)
                      subtitle!
                    else if (meta.isNotEmpty)
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (showMenu)
                _MoreButton(onPressed: () => showVideoMenu(context, video, extra: menuActions))
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square YouTube Music style card for horizontal shelves.
class MusicCard extends ConsumerWidget {
  const MusicCard({super.key, required this.video, this.size = 150, this.onTap});
  final VideoItem video;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap ?? () => openVideo(ref, video),
        onLongPress: () => showVideoMenu(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(video.thumbnailUrl, cacheWidth: size * 16 / 9),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.25),
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
    );
  }
}
