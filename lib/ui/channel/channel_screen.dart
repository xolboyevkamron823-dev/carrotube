import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/feed.dart';
import '../../data/models.dart';
import '../../data/youtube_service.dart';
import '../nav.dart';
import '../widgets/avatar.dart';
import '../widgets/channel_tile.dart';
import '../widgets/chips.dart';
import '../widgets/playlist_tile.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';
import '../widgets/video_card.dart';

typedef ChannelUploadsKey = (String channelId, bool popular);

final channelUploadsProvider = NotifierProvider.autoDispose
    .family<ChannelUploadsNotifier, PagedState<VideoItem>, ChannelUploadsKey>(ChannelUploadsNotifier.new);

class ChannelUploadsNotifier extends PagedNotifier<VideoItem> {
  ChannelUploadsNotifier(this.key);
  final ChannelUploadsKey key;

  @override
  String? keyOf(VideoItem item) => item.id;

  @override
  Future<Paged<VideoItem>?> fetchFirst() => ref.read(youtubeServiceProvider).channelUploads(key.$1, popular: key.$2);
}

/// Playlists of a channel, looked up by the channel title.
final channelPlaylistsProvider = FutureProvider.autoDispose.family<List<PlaylistItem>, String>(
  (ref, title) => ref.watch(youtubeServiceProvider).channelPlaylists(title),
  retry: noRetry,
);

/// YouTube channel page: banner, avatar, name, subscribers, Subscribe, Videos/Playlists.
class ChannelScreen extends ConsumerWidget {
  const ChannelScreen({super.key, required this.channelId, this.title});
  final String channelId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(channelInfoProvider(channelId));
    final channel = info.value;
    final name = channel?.title ?? title ?? '';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerScrolled) => [
            SliverAppBar(
              pinned: true,
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [IconButton(onPressed: () => openSearchTab(context), icon: const Icon(Icons.search_rounded))],
            ),
            SliverToBoxAdapter(
              child: info.when(
                data: (c) => _ChannelHeader(channel: c),
                loading: () => _HeaderSkeleton(name: name),
                error: (e, _) => Column(
                  children: [
                    if (name.isNotEmpty)
                      _ChannelHeader(
                        channel: ChannelItem(id: channelId, title: name),
                      ),
                    ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(channelInfoProvider(channelId))),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: Theme.of(context).colorScheme.onSurface,
                  labelColor: Theme.of(context).colorScheme.onSurface,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: context.tr('videos')),
                    Tab(text: context.tr('playlists')),
                  ],
                ),
                Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _UploadsTab(channelId: channelId),
              _PlaylistsTab(channelTitle: name),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel});
  final ChannelItem channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final meta = [
      if (channel.subscriberCount != null) context.tr('subscribers_n', {'n': compactNumber(channel.subscriberCount)}),
      if (channel.videoCount != null) context.tr('videos_n', {'n': compactNumber(channel.videoCount)}),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (channel.bannerUrl != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 6.2, child: NetImage(channel.bannerUrl)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              AppAvatar(url: channel.avatarUrl, name: channel.title, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (meta.isNotEmpty) ...[const SizedBox(height: 4), Text(meta, style: secondary)],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (channel.description != null && channel.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(channel.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: secondary),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: SubscribeButton(channel: channel),
          ),
        ),
      ],
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            AspectRatio(aspectRatio: 6.2, child: SkeletonBox(radius: 12)),
            SizedBox(height: 16),
            Row(
              children: [
                SkeletonBox(width: 72, height: 72, circle: true),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 20, width: 180),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 120),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            SkeletonBox(height: 36, radius: 18),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.color);
  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: color, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar || old.color != color;
}

class _UploadsTab extends ConsumerStatefulWidget {
  const _UploadsTab({required this.channelId});
  final String channelId;

  @override
  ConsumerState<_UploadsTab> createState() => _UploadsTabState();
}

class _UploadsTabState extends ConsumerState<_UploadsTab> with AutomaticKeepAliveClientMixin {
  bool _popular = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final key = (widget.channelId, _popular);
    final state = ref.watch(channelUploadsProvider(key));
    final notifier = ref.read(channelUploadsProvider(key).notifier);

    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            YtChip(label: context.tr('latest'), selected: !_popular, onTap: () => setState(() => _popular = false)),
            const SizedBox(width: 8),
            YtChip(label: context.tr('popular'), selected: _popular, onTap: () => setState(() => _popular = true)),
          ],
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: InfiniteScroll(
        onLoadMore: notifier.loadMore,
        child: CustomScrollView(
          key: PageStorageKey('uploads-${widget.channelId}-$_popular'),
          slivers: [
            SliverToBoxAdapter(child: chips),
            if (state.loading)
              SliverToBoxAdapter(child: SkeletonList.cards(count: 3))
            else if (state.error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(error: state.error, onRetry: notifier.retry),
              )
            else if (state.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: EmptyView())
            else ...[
              SliverList.builder(
                itemCount: state.items.length,
                itemBuilder: (context, i) => VideoCard(
                  video: state.items[i],
                  showAvatar: false,
                  onTap: () => openVideo(ref, state.items[i], queue: state.items),
                ),
              ),
              SliverToBoxAdapter(
                child: LoadMoreFooter(
                  loading: state.loadingMore || state.hasMore,
                  error: state.moreError,
                  onRetry: () => notifier.loadMore(force: true),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerStatefulWidget {
  const _PlaylistsTab({required this.channelTitle});
  final String channelTitle;

  @override
  ConsumerState<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<_PlaylistsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.channelTitle.isEmpty) {
      return SkeletonList(count: 6, itemBuilder: (_) => const VideoTileSkeleton());
    }
    final value = ref.watch(channelPlaylistsProvider(widget.channelTitle));
    return value.when(
      loading: () =>
          SingleChildScrollView(child: SkeletonList(count: 6, itemBuilder: (_) => const VideoTileSkeleton())),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(channelPlaylistsProvider(widget.channelTitle))),
      data: (list) => list.isEmpty
          ? const EmptyView(icon: Icons.playlist_play_rounded)
          : RefreshIndicator(
              onRefresh: () => ref.refresh(channelPlaylistsProvider(widget.channelTitle).future),
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => PlaylistTile.remote(context, list[i]),
              ),
            ),
    );
  }
}
