import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/avatar.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import 'watch_providers.dart';

/// Comments panel (paged). Shows "Comments are unavailable" when YouTube returns none.
Future<void> showCommentsSheet(BuildContext context, String videoId) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _CommentsList(videoId: videoId, scroll: scroll),
    ),
  );
}

class _CommentsList extends ConsumerWidget {
  const _CommentsList({required this.videoId, required this.scroll});
  final String videoId;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(commentsProvider(videoId));
    final notifier = ref.read(commentsProvider(videoId).notifier);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('comments'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );

    Widget body;
    if (state.loading) {
      body = SkeletonList(count: 6, itemBuilder: (_) => const _CommentSkeleton());
    } else if (state.unavailable || (state.isEmpty && state.error == null)) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: EmptyView(icon: Icons.comments_disabled_outlined, message: context.tr('comments_off')),
      );
    } else if (state.error != null) {
      body = ErrorView(error: state.error, onRetry: notifier.retry);
    } else {
      body = const SizedBox.shrink();
    }

    final showList = !state.loading && state.items.isNotEmpty;
    return InfiniteScroll(
      onLoadMore: notifier.loadMore,
      child: ListView.builder(
        controller: scroll,
        itemCount: showList ? state.items.length + 3 : 3,
        itemBuilder: (context, i) {
          if (i == 0) return header;
          if (i == 1) return const Divider(height: 1);
          if (!showList) return body;
          if (i - 2 < state.items.length) return CommentTile(comment: state.items[i - 2]);
          return LoadMoreFooter(
            loading: state.loadingMore,
            error: state.moreError,
            onRetry: () => notifier.loadMore(force: true),
          );
        },
      ),
    );
  }
}

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 32, height: 32, circle: true),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 11),
                SizedBox(height: 8),
                SkeletonBox(height: 12),
                SizedBox(height: 6),
                SkeletonBox(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CommentTile extends StatefulWidget {
  const CommentTile({super.key, required this.comment});
  final CommentItem comment;

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final author = c.author.startsWith('@') ? c.author : '@${c.author}';
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(name: c.author.replaceFirst('@', ''), size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$author · ${c.publishedTime}', style: secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topCenter,
                    child: Text(
                      c.text,
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.thumb_up_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      if (c.likeCount > 0) Text(compactNumber(c.likeCount), style: secondary),
                      const SizedBox(width: 20),
                      Icon(Icons.thumb_down_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      if (c.isHearted) ...[
                        const SizedBox(width: 20),
                        const Icon(Icons.favorite_rounded, size: 16, color: YtColors.red),
                      ],
                    ],
                  ),
                  if (c.replyCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      context.tr('replies_n', {'n': compactNumber(c.replyCount)}),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF3EA6FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
