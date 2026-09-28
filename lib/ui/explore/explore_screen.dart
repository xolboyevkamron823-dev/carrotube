import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/feed.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../widgets/chips.dart';
import '../widgets/playlist_tile.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';
import '../widgets/video_card.dart';

/// YouTube Music style tab: mood chips, Quick picks, Listen again, Charts, New releases,
/// Moods & genres and Trending.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  Future<void> _refresh(WidgetRef ref, Mood? mood) async {
    if (mood != null) {
      ref.invalidate(moodShelvesProvider(mood.query));
      await ref.read(moodShelvesProvider(mood.query).future).catchError((_) => const MoodShelves([], []));
      return;
    }
    ref
      ..invalidate(exploreQuickPicksProvider)
      ..invalidate(exploreChartsProvider)
      ..invalidate(exploreNewReleasesProvider)
      ..invalidate(exploreTrendingProvider);
    await ref.read(exploreTrendingProvider.future).catchError((_) => <VideoItem>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(selectedMoodProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: RefreshIndicator(
        edgeOffset: topInset + kToolbarHeight + 48,
        onRefresh: () => _refresh(ref, mood),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              titleSpacing: 12,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: YtColors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(context.tr('music'), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                ],
              ),
              actions: [
                IconButton(onPressed: () => openSearchTab(context), icon: const Icon(Icons.search_rounded)),
                IconButton(onPressed: () => openSettings(context), icon: const Icon(Icons.settings_outlined)),
                const SizedBox(width: 4),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    itemCount: moods.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final m = moods[i];
                      final selected = mood?.query == m.query;
                      return YtChip(
                        label: context.tr(m.labelKey),
                        selected: selected,
                        onTap: () => ref.read(selectedMoodProvider.notifier).select(selected ? null : m),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (mood != null) ..._moodSlivers(context, ref, mood) else ..._homeSlivers(context, ref),
            SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }

  List<Widget> _homeSlivers(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider).value ?? const <VideoItem>[];
    final listenAgain = history.where((v) => !v.isLive).take(12).toList();
    return [
      SliverToBoxAdapter(
        child: _AsyncShelf<List<VideoItem>>(
          title: context.tr('quick_picks'),
          value: ref.watch(exploreQuickPicksProvider),
          onRetry: () => ref.invalidate(exploreQuickPicksProvider),
          skeleton: const _QuickPicksSkeleton(),
          playAll: (items) => items,
          builder: (items) => _QuickPicksGrid(items: items),
        ),
      ),
      if (listenAgain.isNotEmpty)
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(context.tr('listen_again'), subtitle: context.tr('history')),
              _Carousel(
                height: 150 + 56,
                children: [
                  for (final v in listenAgain)
                    MusicCard(
                      video: v,
                      onTap: () => openVideo(ref, v, queue: listenAgain),
                    ),
                ],
              ),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: _AsyncShelf<List<PlaylistItem>>(
          title: context.tr('charts'),
          value: ref.watch(exploreChartsProvider),
          onRetry: () => ref.invalidate(exploreChartsProvider),
          skeleton: const ShelfSkeleton(),
          builder: (items) => _Carousel(
            height: 150 + 60,
            children: [for (final p in items) PlaylistCard(playlist: p)],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _AsyncShelf<List<VideoItem>>(
          title: context.tr('new_releases'),
          value: ref.watch(exploreNewReleasesProvider),
          onRetry: () => ref.invalidate(exploreNewReleasesProvider),
          skeleton: const ShelfSkeleton(),
          playAll: (items) => items,
          builder: (items) => _Carousel(
            height: 150 + 56,
            children: [
              for (final v in items)
                MusicCard(
                  video: v,
                  onTap: () => openVideo(ref, v, queue: items),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _MoodsGrid(onSelected: (m) => ref.read(selectedMoodProvider.notifier).select(m))),
      SliverToBoxAdapter(
        child: _AsyncShelf<List<VideoItem>>(
          title: context.tr('trending'),
          value: ref.watch(exploreTrendingProvider),
          onRetry: () => ref.invalidate(exploreTrendingProvider),
          skeleton: SkeletonList(count: 5, itemBuilder: (_) => const VideoTileSkeleton(thumbWidth: 120)),
          playAll: (items) => items,
          builder: (items) => Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _RankedRow(
                  rank: i + 1,
                  video: items[i],
                  onTap: () => openVideo(ref, items[i], queue: items),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _moodSlivers(BuildContext context, WidgetRef ref, Mood mood) {
    final shelves = ref.watch(moodShelvesProvider(mood.query));
    return shelves.when(
      loading: () => [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.only(top: 16), child: ShelfSkeleton()),
        ),
        SliverToBoxAdapter(child: SkeletonList(count: 6, itemBuilder: (_) => const VideoTileSkeleton(thumbWidth: 120))),
      ],
      error: (e, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(error: e, onRetry: () => ref.invalidate(moodShelvesProvider(mood.query))),
        ),
      ],
      data: (data) => [
        if (data.playlists.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(context.tr('featured_playlists'), subtitle: context.tr(mood.labelKey)),
                _Carousel(
                  height: 150 + 60,
                  children: [for (final p in data.playlists) PlaylistCard(playlist: p)],
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: SectionHeader(
            context.tr('songs'),
            trailing: data.videos.isEmpty
                ? null
                : _PlayAllButton(onPressed: () => openVideo(ref, data.videos.first, queue: data.videos)),
          ),
        ),
        if (data.videos.isEmpty)
          SliverToBoxAdapter(child: EmptyView(message: context.tr('no_results')))
        else
          SliverList.builder(
            itemCount: data.videos.length,
            itemBuilder: (context, i) => _SongRow(
              video: data.videos[i],
              onTap: () => openVideo(ref, data.videos[i], queue: data.videos),
            ),
          ),
      ],
    );
  }
}

/// Section with a title that renders an async value (skeleton / error / content).
class _AsyncShelf<T> extends ConsumerWidget {
  const _AsyncShelf({
    required this.title,
    required this.value,
    required this.builder,
    required this.skeleton,
    required this.onRetry,
    this.playAll,
  });

  final String title;
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget skeleton;
  final VoidCallback onRetry;
  final List<VideoItem> Function(T data)? playAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = value.value;
    final queue = data == null || playAll == null ? null : playAll!(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          trailing: queue == null || queue.isEmpty
              ? null
              : _PlayAllButton(onPressed: () => openVideo(ref, queue.first, queue: queue)),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: value.when(
            skipLoadingOnRefresh: true,
            data: (d) => KeyedSubtree(key: const ValueKey('data'), child: builder(d)),
            loading: () => KeyedSubtree(key: const ValueKey('loading'), child: skeleton),
            error: (e, _) => KeyedSubtree(
              key: const ValueKey('error'),
              child: ErrorView(error: e, onRetry: onRetry, compact: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(context.tr('play_all')),
    );
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.height, required this.children});
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return EmptyView(message: context.tr('no_results'));
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// YouTube Music "Quick picks": horizontally paged columns of 4 song rows.
class _QuickPicksGrid extends ConsumerStatefulWidget {
  const _QuickPicksGrid({required this.items});
  final List<VideoItem> items;

  @override
  ConsumerState<_QuickPicksGrid> createState() => _QuickPicksGridState();
}

class _QuickPicksGridState extends ConsumerState<_QuickPicksGrid> {
  final _pages = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return EmptyView(message: context.tr('no_results'));
    final columns = <List<VideoItem>>[
      for (var i = 0; i < items.length; i += 4) items.sublist(i, i + 4 > items.length ? items.length : i + 4),
    ];
    return SizedBox(
      height: 4 * 64,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: columns.length,
        itemBuilder: (context, c) => Column(
          children: [
            for (final v in columns[c])
              _SongRow(
                video: v,
                onTap: () => openVideo(ref, v, queue: items),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickPicksSkeleton extends StatelessWidget {
  const _QuickPicksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(
          4,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SkeletonBox(width: 48, height: 48, radius: 4),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [SkeletonBox(height: 12), SizedBox(height: 6), SkeletonBox(width: 120, height: 11)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Song row: square artwork, title, artist, menu.
class _SongRow extends StatelessWidget {
  const _SongRow({required this.video, required this.onTap});
  final VideoItem video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showVideoMenu(context, video),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(width: 48, height: 48, child: NetImage(video.thumbnailUrl, cacheWidth: 86)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    videoMetaLine(context, video),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: () => showVideoMenu(context, video), icon: const Icon(Icons.more_vert, size: 20)),
          ],
        ),
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.rank, required this.video, required this.onTap});
  final int rank;
  final VideoItem video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showVideoMenu(context, video),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text('$rank', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Icon(Icons.arrow_drop_up_rounded, color: Colors.green.shade400, size: 18),
                ],
              ),
            ),
            SizedBox(width: 120, child: VideoThumbnail(video: video, radius: 6, cacheWidth: 120)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.25),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    videoMetaLine(context, video),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: () => showVideoMenu(context, video), icon: const Icon(Icons.more_vert, size: 20)),
          ],
        ),
      ),
    );
  }
}

/// "Moods & genres": two rows of coloured tiles scrolling horizontally.
class _MoodsGrid extends StatelessWidget {
  const _MoodsGrid({required this.onSelected});
  final ValueChanged<Mood> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.tr('moods')),
        SizedBox(
          height: 2 * 52 + 10,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 170,
            ),
            itemCount: moods.length,
            itemBuilder: (context, i) {
              final m = moods[i];
              return Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(m),
                  child: Row(
                    children: [
                      Container(width: 6, color: Color(m.color)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr(m.labelKey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
