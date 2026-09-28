import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../data/models.dart';
import '../nav.dart';
import 'thumbnail.dart';

/// Stacked-thumbnail playlist artwork with the video count overlay (YouTube style).
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({super.key, this.url, this.count, this.radius = 8, this.icon, this.square = false});
  final String? url;
  final int? count;
  final double radius;
  final IconData? icon;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: square ? 1 : 16 / 9,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The "stack" hint above the artwork.
          Positioned(
            left: 10,
            right: 10,
            top: -4,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    NetImage(url)
                  else
                    ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(icon ?? Icons.playlist_play_rounded, size: 40, color: scheme.onSurfaceVariant),
                    ),
                  if (count != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.playlist_play_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact playlist row (search results, library, channel playlists).
class PlaylistTile extends StatelessWidget {
  const PlaylistTile({
    super.key,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.count,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.icon,
    this.thumbWidth = 160,
  });

  /// Row of a YouTube playlist.
  factory PlaylistTile.remote(BuildContext context, PlaylistItem p, {Key? key}) => PlaylistTile(
    key: key,
    title: p.title,
    subtitle: [if (p.author != null && p.author!.isNotEmpty) p.author!, context.tr('playlist')].join(' · '),
    thumbnailUrl: p.thumbnailUrl,
    count: p.videoCount,
    onTap: () => openPlaylist(context, p.id),
  );

  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final int? count;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final IconData? icon;
  final double thumbWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: thumbWidth,
              child: PlaylistArtwork(url: thumbnailUrl, count: count, icon: icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Square playlist card for Music shelves (charts, moods).
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.size = 150});
  final PlaylistItem playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => openPlaylist(context, playlist.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            SizedBox(
              width: size,
              height: size,
              child: PlaylistArtwork(url: playlist.thumbnailUrl, count: playlist.videoCount, radius: 6, square: true),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.25),
            ),
            const SizedBox(height: 2),
            Text(
              playlist.author ?? context.tr('playlist'),
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
