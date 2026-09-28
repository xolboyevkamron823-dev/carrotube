import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../widgets/avatar.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// Subscriptions: channel avatars row + latest uploads of every subscribed channel.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    final feed = ref.watch(subscriptionFeedProvider);
    final channels = subs.value ?? const <ChannelItem>[];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('subscriptions'))),
      body: subs.when(
        loading: () => const Shimmer(child: ChannelTileSkeleton()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(subscriptionsProvider)),
        data: (_) => channels.isEmpty
            ? EmptyView(
                icon: Icons.subscriptions_outlined,
                message: context.tr('no_subscriptions'),
                subtitle: context.tr('no_subscriptions_sub'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(subscriptionFeedProvider.future).catchError((_) => <VideoItem>[]),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: channels.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _ChannelBubble(channel: channels[i]),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: Divider()),
                    ...feed.when(
                      skipLoadingOnRefresh: true,
                      loading: () => [SliverToBoxAdapter(child: SkeletonList.cards(count: 3))],
                      error: (e, _) => [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ErrorView(error: e, onRetry: () => ref.invalidate(subscriptionFeedProvider)),
                        ),
                      ],
                      data: (videos) => [
                        if (videos.isEmpty)
                          const SliverFillRemaining(hasScrollBody: false, child: EmptyView())
                        else
                          SliverList.builder(
                            itemCount: videos.length,
                            itemBuilder: (context, i) => VideoCard(video: videos[i]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ChannelBubble extends ConsumerWidget {
  const _ChannelBubble({required this.channel});
  final ChannelItem channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openChannel(context, channel.id, title: channel.title),
      onLongPress: () async {
        final actions = ref.read(libraryActionsProvider);
        final ok = await showConfirmDialog(
          context,
          title: context.tr('unsubscribe_q', {'name': channel.title}),
          confirmLabel: context.tr('unsubscribe'),
        );
        if (ok) await actions.setSubscribed(channel, false);
      },
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            AppAvatar(url: channel.avatarUrl, name: channel.title, size: 56),
            const SizedBox(height: 6),
            Text(
              channel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
