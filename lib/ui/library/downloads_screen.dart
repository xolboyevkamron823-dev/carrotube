import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/download_manager.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../widgets/chips.dart';
import '../widgets/sheets.dart';
import '../widgets/states.dart';
import '../widgets/thumbnail.dart';

enum _DownloadFilter { all, audio, video }

/// Offline downloads: progress, cancel / retry / delete, filter, play offline.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _DownloadFilter _filter = _DownloadFilter.all;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(downloadManagerProvider).values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = all.where((d) {
      return switch (_filter) {
        _DownloadFilter.all => true,
        _DownloadFilter.audio => d.audioOnly,
        _DownloadFilter.video => !d.audioOnly,
      };
    }).toList();
    final done = items.where((d) => d.status == DownloadStatus.done).toList();
    final totalBytes = done.fold<int>(0, (s, d) => s + d.sizeBytes);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('downloads'))),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              children: [
                for (final f in _DownloadFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: YtChip(
                      label: context.tr(switch (f) {
                        _DownloadFilter.all => 'all',
                        _DownloadFilter.audio => 'download_audio',
                        _DownloadFilter.video => 'download_video',
                      }),
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          if (done.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${context.tr('videos_n', {'n': '${done.length}'})} · ${formatBytes(totalBytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => playList(ref, done.map((d) => d.video).toList()),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(context.tr('play_all')),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? EmptyView(
                    icon: Icons.download_outlined,
                    message: context.tr('downloads_empty'),
                    subtitle: context.tr('downloads_empty_sub'),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => _DownloadRow(
                      item: items[i],
                      onPlay: () {
                        final idx = done.indexWhere((d) => d.video.id == items[i].video.id);
                        playList(ref, done.map((d) => d.video).toList(), start: idx < 0 ? 0 : idx);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.item, required this.onPlay});
  final DownloadItem item;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manager = ref.read(downloadManagerProvider.notifier);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final kind = context.tr(item.audioOnly ? 'download_audio' : 'download_video');
    final id = item.video.id;

    final Widget status;
    final List<Widget> actions;
    switch (item.status) {
      case DownloadStatus.running:
        status = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                minHeight: 3,
                color: YtColors.red,
              ),
            ),
            const SizedBox(height: 4),
            Text('${(item.progress * 100).round()}% · $kind', style: secondary),
          ],
        );
        actions = [
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: () => manager.cancel(id),
            icon: const Icon(Icons.close_rounded),
          ),
        ];
      case DownloadStatus.queued:
        status = Text('${context.tr('queued')} · $kind', style: secondary);
        actions = [
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: () => manager.cancel(id),
            icon: const Icon(Icons.close_rounded),
          ),
        ];
      case DownloadStatus.done:
        status = Row(
          children: [
            const Icon(Icons.download_done_rounded, size: 14),
            const SizedBox(width: 4),
            Flexible(child: Text('${formatBytes(item.sizeBytes)} · $kind', style: secondary)),
          ],
        );
        actions = [];
      case DownloadStatus.failed || DownloadStatus.canceled:
        status = Text(
          '${context.tr(item.status == DownloadStatus.failed ? 'download_failed' : 'download_canceled')} · $kind',
          style: secondary?.copyWith(color: item.status == DownloadStatus.failed ? theme.colorScheme.error : null),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
        actions = [
          IconButton(
            tooltip: context.tr('retry'),
            onPressed: () => manager.retry(id),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ];
    }

    return InkWell(
      onTap: item.status == DownloadStatus.done ? onPlay : null,
      onLongPress: () => showVideoMenu(context, item.video),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: VideoThumbnail(
                video: item.video,
                radius: 8,
                cacheWidth: 140,
                progress: item.status == DownloadStatus.running ? item.progress : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(item.video.channelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                  const SizedBox(height: 2),
                  status,
                ],
              ),
            ),
            ...actions,
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('delete_download'),
                    body: item.video.title,
                    confirmLabel: context.tr('delete'),
                  );
                  if (ok) await manager.delete(id);
                } else if (v == 'play') {
                  onPlay();
                }
              },
              itemBuilder: (context) => [
                if (item.status == DownloadStatus.done)
                  PopupMenuItem(value: 'play', child: Text(context.tr('play_offline'))),
                PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
