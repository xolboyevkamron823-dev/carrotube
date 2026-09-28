import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../playlist/playlist_screen.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';
import 'library_screen.dart';

/// A local playlist: Play all / Shuffle, drag to reorder, swipe to remove, rename/delete.
class LocalPlaylistScreen extends ConsumerStatefulWidget {
  const LocalPlaylistScreen({super.key, required this.playlist});
  final LocalPlaylist playlist;

  @override
  ConsumerState<LocalPlaylistScreen> createState() => _LocalPlaylistScreenState();
}

class _LocalPlaylistScreenState extends ConsumerState<LocalPlaylistScreen> {
  /// Local copy so reorders and removals show instantly.
  List<VideoItem>? _items;
  List<VideoItem>? _source;

  int get _id => widget.playlist.id;

  void _sync(List<VideoItem> fromDb) {
    if (identical(fromDb, _source)) return;
    _source = fromDb;
    _items = List.of(fromDb);
  }

  /// [to] is the final index of the moved item (onReorderItem semantics).
  void _reorder(int from, int to) {
    final items = _items;
    if (items == null) return;
    setState(() {
      final v = items.removeAt(from);
      items.insert(to.clamp(0, items.length), v);
    });
    ref.read(libraryActionsProvider).reorderPlaylist(_id, items.map((e) => e.id).toList());
  }

  void _remove(VideoItem v) {
    setState(() => _items?.removeWhere((e) => e.id == v.id));
    ref.read(libraryActionsProvider).removeFromPlaylist(_id, v.id);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider).value;
    final current = playlists?.firstWhere((p) => p.id == _id, orElse: () => widget.playlist) ?? widget.playlist;
    final videos = ref.watch(localPlaylistVideosProvider(_id));
    final fromDb = videos.value;
    if (fromDb != null) _sync(fromDb);
    final items = _items ?? const <VideoItem>[];
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'rename') {
                    await renameLocalPlaylist(context, ref, current);
                  } else if (await deleteLocalPlaylist(context, ref, current) && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text(context.tr('rename'))),
                  PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: PlaylistHeader(
              title: current.name,
              lines: [
                context.tr('private'),
                context.tr('videos_n', {'n': '${items.length}'}),
              ],
              artworkUrl: items.isNotEmpty ? items.first.maxThumbnailUrl : current.cover,
              fallbackUrl: items.isNotEmpty ? items.first.thumbnailUrl : null,
              loading: fromDb == null && videos.isLoading,
              onPlayAll: items.isEmpty ? null : () => playList(ref, List.of(items)),
              onShuffle: items.isEmpty ? null : () => playList(ref, List.of(items), shuffle: true),
            ),
          ),
          if (fromDb == null && videos.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(error: videos.error, onRetry: () => ref.invalidate(localPlaylistVideosProvider(_id))),
            )
          else if (fromDb == null)
            SliverToBoxAdapter(child: SkeletonList.tiles(count: 5))
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyView(icon: Icons.playlist_add_rounded, message: context.tr('playlist_empty')),
            )
          else
            SliverReorderableList(
              itemCount: items.length,
              onReorderItem: _reorder,
              proxyDecorator: (child, _, _) =>
                  Material(elevation: 6, color: theme.colorScheme.surfaceContainerHighest, child: child),
              itemBuilder: (context, i) {
                final v = items[i];
                return Dismissible(
                  key: ValueKey('lp-${v.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: YtColors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) => _remove(v),
                  child: VideoTile(
                    video: v,
                    thumbWidth: 128,
                    onTap: () => playList(ref, List.of(items), start: i),
                    menuActions: [
                      VideoMenuAction(
                        icon: Icons.delete_outline_rounded,
                        label: context.tr('remove_from_playlist'),
                        onTap: () => _remove(v),
                      ),
                    ],
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onPressed: () => showVideoMenu(
                            context,
                            v,
                            extra: [
                              VideoMenuAction(
                                icon: Icons.delete_outline_rounded,
                                label: context.tr('remove_from_playlist'),
                                onTap: () => _remove(v),
                              ),
                            ],
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(0, 16, 12, 16),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}
