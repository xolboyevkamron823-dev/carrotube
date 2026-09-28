import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/download_manager.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../widgets/playlist_tile.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';
import 'downloads_screen.dart';
import 'history_screen.dart';
import 'liked_screen.dart';
import 'subscriptions_screen.dart';

/// "Library" / "You" tab: history carousel, downloads, liked, subscriptions and the
/// local playlists.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final liked = ref.watch(likedProvider).value;
    final subs = ref.watch(subscriptionsProvider).value;
    final downloads = ref.watch(downloadManagerProvider);
    final playlists = ref.watch(localPlaylistsProvider);
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final doneDownloads = downloads.values.where((d) => d.status == DownloadStatus.done).length;
    final activeDownloads = downloads.values
        .where((d) => d.status == DownloadStatus.running || d.status == DownloadStatus.queued)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('library')),
        actions: [
          IconButton(onPressed: () => openSearchTab(context), icon: const Icon(Icons.search_rounded)),
          IconButton(onPressed: () => openSettings(context), icon: const Icon(Icons.settings_outlined)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(historyProvider)
            ..invalidate(likedProvider)
            ..invalidate(subscriptionsProvider)
            ..invalidate(localPlaylistsProvider);
          await ref.read(localPlaylistsProvider.future).catchError((_) => <LocalPlaylist>[]);
        },
        child: ListView(
          children: [
            SectionHeader(
              context.tr('history'),
              trailing: TextButton(
                onPressed: () => pushInTab<void>(context, const HistoryScreen()),
                child: Text(context.tr('view_all')),
              ),
            ),
            SizedBox(
              height: 150,
              child: history.when(
                loading: () => const ShelfSkeleton(size: 90),
                error: (e, _) => ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(historyProvider)),
                data: (list) => list.isEmpty
                    ? Center(child: Text(context.tr('history_empty'), style: secondary))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: list.length.clamp(0, 30),
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) => _HistoryCard(video: list[i]),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            _EntryTile(
              icon: Icons.download_outlined,
              title: context.tr('downloads'),
              subtitle: activeDownloads > 0
                  ? context.tr('downloading_n', {'n': '$activeDownloads'})
                  : context.tr('videos_n', {'n': '$doneDownloads'}),
              onTap: () => pushInTab<void>(context, const DownloadsScreen()),
            ),
            _EntryTile(
              icon: Icons.thumb_up_outlined,
              title: context.tr('liked_videos'),
              subtitle: liked == null ? null : context.tr('videos_n', {'n': '${liked.length}'}),
              onTap: () => pushInTab<void>(context, const LikedScreen()),
            ),
            _EntryTile(
              icon: Icons.subscriptions_outlined,
              title: context.tr('subscriptions'),
              subtitle: subs == null ? null : context.tr('channels_n', {'n': '${subs.length}'}),
              onTap: () => pushInTab<void>(context, const SubscriptionsScreen()),
            ),
            const Divider(),
            SectionHeader(
              context.tr('playlists'),
              trailing: TextButton.icon(
                onPressed: () => createPlaylistFlow(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('new_playlist')),
              ),
            ),
            ...playlists.when(
              loading: () => [SkeletonList(count: 3, itemBuilder: (_) => const VideoTileSkeleton())],
              error: (e, _) => [
                ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(localPlaylistsProvider)),
              ],
              data: (list) => list.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(context.tr('no_playlists'), style: secondary)),
                      ),
                    ]
                  : [for (final p in list) LocalPlaylistTile(playlist: p)],
            ),
            SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.title, required this.onTap, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openVideo(ref, video),
        onLongPress: () => showVideoMenu(
          context,
          video,
          extra: [
            VideoMenuAction(
              icon: Icons.delete_outline_rounded,
              label: context.tr('remove_from_history'),
              onTap: () => ref.read(libraryActionsProvider).removeHistory(video.id),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoThumbnail(video: video, radius: 8, cacheWidth: 160),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            Text(
              video.channelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of a local playlist with rename / delete menu.
class LocalPlaylistTile extends ConsumerWidget {
  const LocalPlaylistTile({super.key, required this.playlist});
  final LocalPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlaylistTile(
      title: playlist.name,
      subtitle: '${context.tr('private')} · ${context.tr('videos_n', {'n': '${playlist.count}'})}',
      thumbnailUrl: playlist.cover,
      count: playlist.count,
      icon: Icons.playlist_play_rounded,
      thumbWidth: 140,
      onTap: () => openLocalPlaylist(context, playlist),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) =>
            v == 'rename' ? renameLocalPlaylist(context, ref, playlist) : deleteLocalPlaylist(context, ref, playlist),
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(context.tr('rename'))),
          PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
        ],
      ),
    );
  }
}

Future<void> renameLocalPlaylist(BuildContext context, WidgetRef ref, LocalPlaylist p) async {
  final actions = ref.read(libraryActionsProvider);
  final name = await showTextInputDialog(
    context,
    title: context.tr('rename'),
    initial: p.name,
    hint: context.tr('playlist_name'),
    confirmLabel: context.tr('ok'),
  );
  if (name != null) await actions.renamePlaylist(p.id, name);
}

/// Returns true when the playlist was deleted.
Future<bool> deleteLocalPlaylist(BuildContext context, WidgetRef ref, LocalPlaylist p) async {
  final actions = ref.read(libraryActionsProvider);
  final ok = await showConfirmDialog(
    context,
    title: context.tr('delete_playlist_q', {'name': p.name}),
    confirmLabel: context.tr('delete'),
  );
  if (ok) await actions.deletePlaylist(p.id);
  return ok;
}
