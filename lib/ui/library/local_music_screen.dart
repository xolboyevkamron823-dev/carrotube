import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/local_music.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/states.dart';

/// "My music": local audio files played through the native player with the full
/// Carrozzeria DSP chain and background playback.
class LocalMusicScreen extends ConsumerWidget {
  const LocalMusicScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.audio);
    } on PlatformException {
      files = await FilePicker.pickFiles();
    }
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    final n = await LocalMusic.import(paths);
    ref.invalidate(localMusicProvider);
    if (context.mounted) showToast(context, context.tr('imported_n', {'n': '$n'}));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(localMusicProvider);
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('my_music')),
        actions: [
          IconButton(
            tooltip: context.tr('import_music'),
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.library_add_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(localMusicProvider);
          await ref.read(localMusicProvider.future).catchError((_) => <VideoItem>[]);
        },
        child: tracks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(localMusicProvider)),
          data: (list) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(context.tr('my_music_hint'), style: secondary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: list.isEmpty ? null : () => _playAll(ref, list, shuffle: false),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(context.tr('play_all')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: list.isEmpty ? null : () => _playAll(ref, list, shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(context.tr('shuffle')),
                      ),
                    ),
                  ],
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.library_music_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(context.tr('nothing_here'), style: secondary),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _import(context, ref),
                        icon: const Icon(Icons.library_add_rounded),
                        label: Text(context.tr('import_music')),
                      ),
                    ],
                  ),
                ),
              for (final t in list)
                Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: theme.colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await LocalMusic.delete(t.id);
                    ref.invalidate(localMusicProvider);
                  },
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.music_note_rounded),
                    ),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: t.channelName.isEmpty ? null : Text(t.channelName, maxLines: 1),
                    onTap: () => openVideo(ref, t, queue: list),
                  ),
                ),
              SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }

  void _playAll(WidgetRef ref, List<VideoItem> list, {required bool shuffle}) {
    ref.read(playerProvider.notifier).playQueue(list, shuffle: shuffle);
    ref.read(watchPageOpenProvider.notifier).set(true);
  }
}
