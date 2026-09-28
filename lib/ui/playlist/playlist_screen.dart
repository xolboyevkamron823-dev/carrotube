import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../data/paging.dart';
import '../../data/youtube_service.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';
import '../widgets/video_card.dart';

final playlistInfoProvider = FutureProvider.autoDispose.family<PlaylistItem, String>(
  (ref, id) => ref.watch(youtubeServiceProvider).playlist(id),
  retry: noRetry,
);

final playlistVideosProvider = FutureProvider.autoDispose.family<List<VideoItem>, String>(
  (ref, id) => ref.watch(youtubeServiceProvider).playlistVideos(id),
  retry: noRetry,
);

/// YouTube playlist page: blurred header, big artwork, title, author, count,
/// Play all / Shuffle and the numbered list.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  Future<void> _saveLocally(BuildContext context, WidgetRef ref, PlaylistItem? info, List<VideoItem> videos) async {
    final actions = ref.read(libraryActionsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final done = context.tr('saved_to_library');
    final id = await actions.createPlaylist(info?.title ?? context.tr('playlist'));
    for (final v in videos) {
      await actions.addToPlaylist(id, v);
    }
    messenger?.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(playlistInfoProvider(playlistId));
    final videos = ref.watch(playlistVideosProvider(playlistId));
    final list = videos.value ?? const <VideoItem>[];
    final p = info.value;
    final player = ref.read(playerProvider.notifier);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(playlistInfoProvider(playlistId));
          await ref.refresh(playlistVideosProvider(playlistId).future).catchError((_) => <VideoItem>[]);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(p?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                if (list.isNotEmpty)
                  PopupMenuButton<int>(
                    onSelected: (_) => _saveLocally(context, ref, p, list),
                    itemBuilder: (context) => [PopupMenuItem(value: 0, child: Text(context.tr('save_to_library')))],
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: PlaylistHeader(
                title: p?.title,
                lines: [
                  if (p?.author != null && p!.author!.isNotEmpty) p.author!,
                  if (p?.videoCount != null || list.isNotEmpty)
                    context.tr('videos_n', {'n': '${p?.videoCount ?? list.length}'}),
                ],
                description: p?.description,
                artworkUrl: list.isNotEmpty ? list.first.maxThumbnailUrl : p?.thumbnailUrl,
                fallbackUrl: list.isNotEmpty ? list.first.thumbnailUrl : null,
                loading: info.isLoading && p == null,
                onPlayAll: list.isEmpty ? null : () => playList(ref, list),
                onShuffle: list.isEmpty ? null : () => playList(ref, list, shuffle: true),
              ),
            ),
            ...videos.when(
              skipLoadingOnRefresh: true,
              loading: () => [
                SliverToBoxAdapter(child: SkeletonList(count: 8, itemBuilder: (_) => const VideoTileSkeleton())),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(error: e, onRetry: () => ref.invalidate(playlistVideosProvider(playlistId))),
                ),
              ],
              data: (items) => [
                if (items.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: EmptyView())
                else
                  SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => VideoTile(
                      video: items[i],
                      index: i + 1,
                      thumbWidth: 140,
                      onTap: () => openVideo(ref, items[i], queue: items),
                      menuActions: [
                        VideoMenuAction(
                          icon: Icons.playlist_play_rounded,
                          label: context.tr('play_from_here'),
                          onTap: () => player.playQueue(items, start: i),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }
}

/// Header shared by remote and local playlists.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.title,
    required this.lines,
    this.description,
    this.artworkUrl,
    this.fallbackUrl,
    this.loading = false,
    this.onPlayAll,
    this.onShuffle,
    this.extraActions = const [],
  });

  final String? title;
  final List<String> lines;
  final String? description;
  final String? artworkUrl;
  final String? fallbackUrl;
  final bool loading;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Stack(
      children: [
        // Blurred artwork fading into the background (YouTube playlist header).
        if (artworkUrl != null)
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
              ).createShader(r),
              child: Opacity(
                opacity: dark ? 0.55 : 0.35,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                  child: NetImage(fallbackUrl ?? artworkUrl),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: loading || artworkUrl == null
                          ? const Shimmer(child: SkeletonBox(radius: 12))
                          : NetImage(artworkUrl, fallbackUrl: fallbackUrl),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (loading)
                const Shimmer(child: SkeletonBox(height: 24, width: 220))
              else
                Text(
                  title ?? '',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                ),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(l, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              if (description != null && description!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(context.tr('play_all')),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.onSurface,
                        foregroundColor: scheme.surface,
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onShuffle,
                      icon: const Icon(Icons.shuffle_rounded),
                      label: Text(context.tr('shuffle')),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                        foregroundColor: scheme.onSurface,
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ),
                  ...extraActions,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
