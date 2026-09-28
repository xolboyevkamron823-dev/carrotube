import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import 'avatar.dart';

/// Search-result style channel row: big avatar, name, subscribers / videos, Subscribe.
class ChannelTile extends ConsumerWidget {
  const ChannelTile({super.key, required this.channel, this.onTap, this.showSubscribe = true});
  final ChannelItem channel;
  final VoidCallback? onTap;
  final bool showSubscribe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (channel.subscriberCount != null) context.tr('subscribers_n', {'n': compactNumber(channel.subscriberCount)}),
      if (channel.videoCount != null) context.tr('videos_n', {'n': compactNumber(channel.videoCount)}),
    ];
    return InkWell(
      onTap: onTap ?? () => openChannel(context, channel.id, title: channel.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 136,
              child: Center(
                child: AppAvatar(url: channel.avatarUrl, name: channel.title, size: 88),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (parts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      parts.join(' · '),
                      maxLines: 2,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (showSubscribe) ...[const SizedBox(height: 8), SubscribeButton(channel: channel, dense: true)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// YouTube Subscribe / Subscribed pill (local subscriptions).
class SubscribeButton extends ConsumerWidget {
  const SubscribeButton({super.key, required this.channel, this.dense = false});
  final ChannelItem channel;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final subscribed = ref.watch(isSubscribedProvider(channel.id)).value ?? false;
    final padding = EdgeInsets.symmetric(horizontal: dense ? 14 : 16);
    final size = Size(0, dense ? 32 : 36);
    void toggle() => ref.read(libraryActionsProvider).setSubscribed(channel, !subscribed);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: subscribed
          ? FilledButton.tonalIcon(
              key: const ValueKey('subscribed'),
              onPressed: toggle,
              icon: const Icon(Icons.notifications_none_rounded, size: 18),
              label: Text(context.tr('subscribed')),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundColor: scheme.onSurface,
                padding: padding,
                minimumSize: size,
                visualDensity: VisualDensity.compact,
              ),
            )
          : FilledButton(
              key: const ValueKey('subscribe'),
              onPressed: toggle,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onSurface,
                foregroundColor: scheme.surface,
                padding: padding,
                minimumSize: size,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(context.tr('subscribe')),
            ),
    );
  }
}
