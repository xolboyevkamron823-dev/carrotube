import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/library.dart';
import '../nav.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// Watch history: swipe or menu to remove, clear all.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Removed optimistically so a swiped-away row leaves the tree immediately.
  final _removed = <String>{};

  void _remove(String id) {
    setState(() => _removed.add(id));
    ref.read(libraryActionsProvider).removeHistory(id);
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final actions = ref.read(libraryActionsProvider);
    final hasItems = history.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('history')),
        actions: [
          if (hasItems)
            IconButton(
              tooltip: context.tr('clear_history'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: context.tr('clear_history'),
                  body: context.tr('clear_history_body'),
                  confirmLabel: context.tr('clear'),
                );
                if (ok) await actions.clearHistory();
              },
            ),
        ],
      ),
      body: history.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => SingleChildScrollView(child: SkeletonList.tiles()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(historyProvider)),
        data: (all) {
          // Forget ids the database has already dropped (they may be re-added later).
          _removed.removeWhere((id) => !all.any((v) => v.id == id));
          final list = all.where((v) => !_removed.contains(v.id)).toList();
          return list.isEmpty
              ? EmptyView(icon: Icons.history_rounded, message: context.tr('history_empty'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final v = list[i];
                    return Dismissible(
                      key: ValueKey('h-${v.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: YtColors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) => _remove(v.id),
                      child: VideoTile(
                        video: v,
                        onTap: () => openVideo(ref, v),
                        menuActions: [
                          VideoMenuAction(
                            icon: Icons.delete_outline_rounded,
                            label: context.tr('remove_from_history'),
                            onTap: () => _remove(v.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
        },
      ),
    );
  }
}
