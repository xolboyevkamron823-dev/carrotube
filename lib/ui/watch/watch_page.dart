import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/download_manager.dart';
import '../../data/feed.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../queue/queue_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/channel_tile.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/thumbnail.dart';
import '../widgets/video_card.dart';
import 'comments_sheet.dart';
import 'watch_providers.dart';

/// Everything below the player on the watch page: title, actions, channel, description,
/// comments teaser and the Up next list.
class WatchDetails extends ConsumerWidget {
  const WatchDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerProvider.select((s) => s.current));
    if (current == null) return const SizedBox.shrink();
    final details = ref.watch(videoDetailsProvider(current.id)).value;
    final video = details == null
        ? current
        : VideoItem(
            id: current.id,
            title: details.title.isNotEmpty ? details.title : current.title,
            channelName: details.channelName.isNotEmpty ? details.channelName : current.channelName,
            channelId: details.channelId ?? current.channelId,
            duration: details.duration ?? current.duration,
            viewCount: details.viewCount ?? current.viewCount,
            uploadDate: details.uploadDate ?? current.uploadDate,
            uploadDateText: details.uploadDateText ?? current.uploadDateText,
            description: details.description ?? current.description,
            isLive: details.isLive || current.isLive,
            likeCount: details.likeCount ?? current.likeCount,
            thumbnail: current.thumbnail,
          );
    return _WatchScroll(key: ValueKey(current.id), video: video);
  }
}

class _WatchScroll extends ConsumerStatefulWidget {
  const _WatchScroll({super.key, required this.video});
  final VideoItem video;

  @override
  ConsumerState<_WatchScroll> createState() => _WatchScrollState();
}

class _WatchScrollState extends ConsumerState<_WatchScroll> {
  bool _descExpanded = false;

  void _playFromUpNext(VideoItem v) {
    final s = ref.read(playerProvider);
    final ctrl = ref.read(playerProvider.notifier);
    final qi = s.queue.indexWhere((e) => e.id == v.id);
    if (qi >= 0) {
      ctrl.jumpTo(qi);
    } else {
      ctrl.playNext(v);
      ctrl.next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final upNext = ref.watch(upNextListProvider);
    final (loadingItem, pastStart, hasError, autoplay) = ref.watch(
      playerProvider.select((s) => (s.loadingItem, s.position.inSeconds > 20, s.error != null, s.autoplay)),
    );
    final upNextLoading = upNext.isEmpty && !hasError && (loadingItem || !pastStart);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _TitleBlock(
            video: v,
            expanded: _descExpanded,
            onToggle: () => setState(() => _descExpanded = !_descExpanded),
          ),
        ),
        SliverToBoxAdapter(child: _ChannelRow(video: v)),
        SliverToBoxAdapter(child: _ActionsRow(video: v)),
        SliverToBoxAdapter(
          child: _DescriptionCard(
            video: v,
            expanded: _descExpanded,
            onToggle: () => setState(() => _descExpanded = !_descExpanded),
          ),
        ),
        SliverToBoxAdapter(child: _CommentsTeaser(videoId: v.id)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('up_next'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(context.tr('autoplay'), style: Theme.of(context).textTheme.bodySmall),
                Switch(value: autoplay, onChanged: ref.read(playerProvider.notifier).setAutoplay),
              ],
            ),
          ),
        ),
        if (upNextLoading)
          SliverToBoxAdapter(child: SkeletonList.tiles(count: 6))
        else
          SliverList.builder(
            itemCount: upNext.length,
            itemBuilder: (context, i) => VideoTile(video: upNext[i], onTap: () => _playFromUpNext(upNext[i])),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.video, required this.expanded, required this.onToggle});
  final VideoItem video;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = videoMetaLine(context, video, withChannel: false);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: Text(
                video.title,
                maxLines: expanded ? null : 2,
                overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 18, height: 1.3),
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  if (video.isLive) TextSpan(text: '${context.tr('live_badge')}  '),
                  TextSpan(text: meta),
                  TextSpan(
                    text: '  ${context.tr(expanded ? 'show_less' : 'more')}',
                    style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = video.channelId;
    final info = id == null ? null : ref.watch(channelInfoProvider(id)).value;
    final channel = info ?? ChannelItem(id: id ?? '', title: video.channelName);
    return InkWell(
      onTap: id == null ? null : () => openChannel(context, id, title: video.channelName),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            AppAvatar(url: info?.avatarUrl, name: video.channelName, size: 38),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                info?.title ?? video.channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (info?.subscriberCount != null) ...[
              const SizedBox(width: 8),
              Text(
                compactNumber(info!.subscriberCount),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const Spacer(),
            if (id != null) SubscribeButton(channel: channel, dense: true),
          ],
        ),
      ),
    );
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(isLikedProvider(video.id)).value ?? false;
    final download = ref.watch(downloadManagerProvider.select((m) => m[video.id]));
    final audioOnly = ref.watch(playerProvider.select((s) => s.audioOnly));

    final Widget downloadIcon;
    final String downloadLabel;
    switch (download?.status) {
      case DownloadStatus.done:
        downloadIcon = const Icon(Icons.download_done_rounded, size: 20);
        downloadLabel = context.tr('downloaded');
      case DownloadStatus.running || DownloadStatus.queued:
        downloadIcon = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            value: download!.status == DownloadStatus.running && download.progress > 0 ? download.progress : null,
          ),
        );
        downloadLabel = download.status == DownloadStatus.running
            ? '${(download.progress * 100).round()}%'
            : context.tr('queued');
      default:
        downloadIcon = const Icon(Icons.download_outlined, size: 20);
        downloadLabel = context.tr('download');
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _ActionPill(
            icon: Icon(liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined, size: 20),
            label: video.likeCount != null && video.likeCount! > 0
                ? compactNumber(video.likeCount)
                : context.tr(liked ? 'liked' : 'like'),
            onTap: () => ref.read(libraryActionsProvider).setLiked(video, !liked),
          ),
          _ActionPill(
            icon: const Icon(Icons.reply_rounded, size: 20, textDirection: TextDirection.rtl),
            label: context.tr('share'),
            onTap: () => shareVideo(video),
          ),
          _ActionPill(
            icon: const Icon(Icons.bookmark_border_rounded, size: 20),
            label: context.tr('save'),
            onTap: () => showSaveToPlaylistSheet(context, video),
          ),
          _ActionPill(
            icon: downloadIcon,
            label: downloadLabel,
            highlighted: download?.status == DownloadStatus.done,
            onTap: () => showDownloadSheet(context, video),
          ),
          _ActionPill(
            icon: Icon(audioOnly ? Icons.headphones_rounded : Icons.headphones_outlined, size: 20),
            label: context.tr(audioOnly ? 'audio_only' : 'video_mode'),
            highlighted: audioOnly,
            onTap: () => ref.read(playerProvider.notifier).setAudioOnly(!audioOnly),
          ),
          _ActionPill(
            icon: const Icon(Icons.playlist_play_rounded, size: 20),
            label: context.tr('queue'),
            onTap: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label, required this.onTap, this.highlighted = false});
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = highlighted ? scheme.onSurface : scheme.surfaceContainerHighest;
    final fg = highlighted ? scheme.surface : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: icon),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.video, required this.expanded, required this.onToggle});
  final VideoItem video;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final desc = (video.description ?? '').trim();
    final head = <String>[
      if (video.viewCount != null) context.tr('views_n', {'n': compactNumber(video.viewCount)}),
      if (video.uploadDate != null)
        timeAgo(video.uploadDate, lang: lang)
      else if (video.uploadDateText != null)
        video.uploadDateText!,
    ].join('  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (head.isNotEmpty)
                    Text(head, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    expanded
                        ? SelectableText(desc, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))
                        : Text(
                            desc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                          ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    context.tr(expanded ? 'show_less' : 'show_more'),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentsTeaser extends ConsumerWidget {
  const _CommentsTeaser({required this.videoId});
  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(commentsProvider(videoId));
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final first = state.items.isNotEmpty ? state.items.first : null;
    final unavailable = !state.loading && first == null;

    Widget body;
    if (state.loading) {
      body = const Shimmer(
        child: Row(
          children: [
            SkeletonBox(width: 24, height: 24, circle: true),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 12)),
          ],
        ),
      );
    } else if (first != null) {
      body = Row(
        children: [
          AppAvatar(name: first.author.replaceFirst('@', ''), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(first.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ),
        ],
      );
    } else {
      body = Text(context.tr('comments_off'), style: secondary);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: unavailable && state.error == null ? null : () => showCommentsSheet(context, videoId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.tr('comments'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (state.items.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(state.hasMore ? '${state.items.length}+' : '${state.items.length}', style: secondary),
                    ],
                    const Spacer(),
                    if (!unavailable)
                      Icon(Icons.unfold_more_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 8),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
