import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/feed.dart';
import '../nav.dart';
import '../widgets/chips.dart';
import '../widgets/logo.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// YouTube home: logo app bar, category chips and an infinite feed of big video cards.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(selectedFeedCategoryProvider);
    final feed = ref.watch(homeFeedProvider(category));
    final notifier = ref.read(homeFeedProvider(category).notifier);
    final topInset = MediaQuery.paddingOf(context).top;

    final Widget body;
    if (feed.loading) {
      body = SliverToBoxAdapter(child: SkeletonList.cards());
    } else if (feed.error != null) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorView(error: feed.error, onRetry: notifier.retry),
      );
    } else if (feed.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyView(icon: Icons.video_library_outlined, message: context.tr('no_results')),
      );
    } else {
      body = SliverList.builder(
        itemCount: feed.items.length + 1,
        itemBuilder: (context, i) {
          if (i == feed.items.length) {
            return LoadMoreFooter(
              loading: feed.loadingMore || feed.hasMore,
              error: feed.moreError,
              onRetry: () => notifier.loadMore(force: true),
            );
          }
          return VideoCard(video: feed.items[i]);
        },
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        edgeOffset: topInset + kToolbarHeight + 48,
        onRefresh: notifier.refresh,
        child: InfiniteScroll(
          onLoadMore: notifier.loadMore,
          child: CustomScrollView(
            key: PageStorageKey('home-${category.name}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                titleSpacing: 12,
                title: const CarroTubeLogo(),
                actions: [
                  IconButton(
                    tooltip: context.tr('search'),
                    onPressed: () => openSearchTab(context),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: context.tr('settings'),
                    onPressed: () => openSettings(context),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const SizedBox(width: 4),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: _CategoryChips(
                    selected: category,
                    onSelected: (c) => ref.read(selectedFeedCategoryProvider.notifier).select(c),
                  ),
                ),
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});
  final FeedCategory selected;
  final ValueChanged<FeedCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        itemCount: FeedCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = FeedCategory.values[i];
          return YtChip(label: context.tr(c.labelKey), selected: c == selected, onTap: () => onSelected(c));
        },
      ),
    );
  }
}
