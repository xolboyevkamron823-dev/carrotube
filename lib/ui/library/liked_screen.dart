import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/library.dart';
import '../nav.dart';
import '../playlist/playlist_screen.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// Liked videos (local), shown like a playlist.
class LikedScreen extends ConsumerWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedProvider);
    final list = liked.value ?? const [];
    final actions = ref.read(libraryActionsProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(pinned: true, title: Text(context.tr('liked_videos'))),
          SliverToBoxAdapter(
            child: PlaylistHeader(
              title: context.tr('liked_videos'),
              lines: [
                context.tr('private'),
                context.tr('videos_n', {'n': '${list.length}'}),
              ],
              artworkUrl: list.isNotEmpty ? list.first.maxThumbnailUrl : null,
              fallbackUrl: list.isNotEmpty ? list.first.thumbnailUrl : null,
              loading: liked.isLoading && !liked.hasValue,
              onPlayAll: list.isEmpty ? null : () => playList(ref, list),
              onShuffle: list.isEmpty ? null : () => playList(ref, list, shuffle: true),
            ),
          ),
          ...liked.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => [SliverToBoxAdapter(child: SkeletonList.tiles())],
            error: (e, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(error: e, onRetry: () => ref.invalidate(likedProvider)),
              ),
            ],
            data: (items) => [
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(icon: Icons.thumb_up_outlined, message: context.tr('liked_empty')),
                )
              else
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => VideoTile(
                    video: items[i],
                    index: i + 1,
                    thumbWidth: 140,
                    onTap: () => playList(ref, items, start: i),
                    menuActions: [
                      VideoMenuAction(
                        icon: Icons.thumb_down_outlined,
                        label: context.tr('remove_from_liked'),
                        onTap: () => actions.setLiked(items[i], false),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}
