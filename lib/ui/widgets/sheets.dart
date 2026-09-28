import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/download_manager.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import 'states.dart';
import 'thumbnail.dart';

/// Extra entry for [showVideoMenu] (e.g. "Remove from history").
class VideoMenuAction {
  const VideoMenuAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Shares a video link through the system share sheet.
Future<void> shareVideo(VideoItem v) =>
    SharePlus.instance.share(ShareParams(text: '${v.title}\n${v.url}', subject: v.title));

/// YouTube 3-dot menu of a video.
Future<void> showVideoMenu(
  BuildContext context,
  VideoItem v, {
  List<VideoMenuAction> extra = const [],
  bool showChannel = true,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = AppStrings.of(context);
  void toast(String key) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.get(key)), duration: const Duration(seconds: 2)));
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () {
          Navigator.of(sheetContext).pop();
          onTap();
        },
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetVideoHeader(video: v),
              const Divider(),
              item(Icons.playlist_play_rounded, sheetContext.tr('play_next'), () {
                container.read(playerProvider.notifier).playNext(v);
                toast('added_play_next');
              }),
              item(Icons.queue_music_rounded, sheetContext.tr('add_to_queue'), () {
                container.read(playerProvider.notifier).addToQueue(v);
                toast('added_to_queue');
              }),
              item(Icons.bookmark_border_rounded, sheetContext.tr('save_to_playlist'), () {
                if (context.mounted) showSaveToPlaylistSheet(context, v);
              }),
              item(Icons.download_outlined, sheetContext.tr('download'), () {
                if (context.mounted) showDownloadSheet(context, v);
              }),
              item(Icons.share_outlined, sheetContext.tr('share'), () => shareVideo(v)),
              if (showChannel && v.channelId != null)
                item(Icons.account_box_outlined, sheetContext.tr('go_to_channel'), () {
                  if (context.mounted) openChannel(context, v.channelId!, title: v.channelName);
                }),
              for (final a in extra) item(a.icon, a.label, a.onTap),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetVideoHeader extends StatelessWidget {
  const _SheetVideoHeader({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          SizedBox(width: 96, child: VideoThumbnail(video: video, radius: 6, showBadges: false, cacheWidth: 96)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  video.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text input dialog (new playlist, rename ...). Returns the trimmed text or null.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _TextInputDialog(title: title, initial: initial, hint: hint, confirmLabel: confirmLabel),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.initial, this.hint, required this.confirmLabel});
  final String title;
  final String initial;
  final String? hint;
  final String confirmLabel;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 150,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('cancel'))),
        ValueListenableBuilder(
          valueListenable: _c,
          builder: (context, value, _) =>
              TextButton(onPressed: value.text.trim().isEmpty ? null : _submit, child: Text(widget.confirmLabel)),
        ),
      ],
    );
  }
}

/// Yes/no confirmation dialog.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
}) async {
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('cancel'))),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a name and creates a local playlist. Returns its id.
Future<int?> createPlaylistFlow(BuildContext context, {VideoItem? addVideo}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final name = await showTextInputDialog(
    context,
    title: context.tr('new_playlist'),
    hint: context.tr('playlist_name'),
    confirmLabel: context.tr('create'),
  );
  if (name == null) return null;
  final actions = container.read(libraryActionsProvider);
  final id = await actions.createPlaylist(name);
  if (addVideo != null) await actions.addToPlaylist(id, addVideo);
  return id;
}

/// "Save video to..." sheet: local playlists with checkboxes + New playlist.
Future<void> showSaveToPlaylistSheet(BuildContext context, VideoItem v) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SaveToPlaylistSheet(video: v),
  );
}

class _SaveToPlaylistSheet extends ConsumerWidget {
  const _SaveToPlaylistSheet({required this.video});
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(localPlaylistsProvider);
    final liked = ref.watch(isLikedProvider(video.id)).value ?? false;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('save_video_to'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => createPlaylistFlow(context, addVideo: video),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('new_playlist')),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  CheckboxListTile(
                    value: liked,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(context.tr('liked_videos')),
                    secondary: const Icon(Icons.thumb_up_outlined),
                    onChanged: (on) => ref.read(libraryActionsProvider).setLiked(video, on ?? false),
                  ),
                  ...playlists.when(
                    data: (list) => [for (final p in list) _PlaylistCheckbox(playlist: p, video: video)],
                    loading: () => const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (e, _) => [
                      ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(localPlaylistsProvider)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCheckbox extends ConsumerWidget {
  const _PlaylistCheckbox({required this.playlist, required this.video});
  final LocalPlaylist playlist;
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(localPlaylistVideosProvider(playlist.id)).value;
    final contains = videos?.any((e) => e.id == video.id) ?? false;
    return CheckboxListTile(
      value: contains,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      secondary: const Icon(Icons.lock_outline_rounded, size: 20),
      onChanged: videos == null
          ? null
          : (on) {
              final actions = ref.read(libraryActionsProvider);
              if (on ?? false) {
                actions.addToPlaylist(playlist.id, video);
              } else {
                actions.removeFromPlaylist(playlist.id, video.id);
              }
            },
    );
  }
}

/// Download chooser: audio only / video, with the current state of the download.
Future<void> showDownloadSheet(BuildContext context, VideoItem v) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final started = context.tr('download_started');
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => _DownloadSheet(
      video: v,
      onStarted: () => messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(started), duration: const Duration(seconds: 2))),
    ),
  );
}

class _DownloadSheet extends ConsumerWidget {
  const _DownloadSheet({required this.video, required this.onStarted});
  final VideoItem video;
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = ref.watch(downloadManagerProvider.select((m) => m[video.id]));
    final manager = ref.read(downloadManagerProvider.notifier);
    final active = item != null && (item.status == DownloadStatus.running || item.status == DownloadStatus.queued);
    final done = item?.status == DownloadStatus.done;

    Widget option({required bool audio, required IconData icon, required String title, required String subtitle}) {
      final isThis = item != null && item.audioOnly == audio;
      final trailing = switch (item?.status) {
        DownloadStatus.done when isThis || (audio && done) => const Icon(Icons.check_circle, color: YtColors.red),
        DownloadStatus.running || DownloadStatus.queued when isThis => SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: item.status == DownloadStatus.running && item.progress > 0 ? item.progress : null,
          ),
        ),
        _ => null,
      };
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
        enabled: !active,
        onTap: () {
          manager.enqueue(video, audioOnly: audio);
          Navigator.of(context).pop();
          onStarted();
        },
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              context.tr('download_quality'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          option(
            audio: true,
            icon: Icons.music_note_rounded,
            title: context.tr('download_audio'),
            subtitle: context.tr('download_audio_sub'),
          ),
          option(
            audio: false,
            icon: Icons.movie_outlined,
            title: context.tr('download_video'),
            subtitle: context.tr('download_video_sub'),
          ),
          if (active)
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(context.tr('cancel_download')),
              onTap: () {
                manager.cancel(video.id);
                Navigator.of(context).pop();
              },
            ),
          if (done)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(context.tr('delete_download')),
              onTap: () {
                manager.delete(video.id);
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
