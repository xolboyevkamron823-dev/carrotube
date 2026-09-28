import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router.dart';
import '../data/models.dart';
import '../player/player_controller.dart';
import 'channel/channel_screen.dart';
import 'library/local_playlist_screen.dart';
import 'playlist/playlist_screen.dart';
import 'settings/settings_screen.dart';

/// Index of the tab that is currently shown (kept up to date by the app shell).
abstract final class ShellTabs {
  static int currentIndex = 0;
  static const search = 2;
}

/// Plays [v] (optionally with a whole [queue]) and opens the watch page.
void openVideo(WidgetRef ref, VideoItem v, {List<VideoItem>? queue}) {
  final player = ref.read(playerProvider);
  if (player.current?.id != v.id || player.error != null) {
    ref.read(playerProvider.notifier).playVideo(v, queue: queue);
  }
  ref.read(watchPageOpenProvider.notifier).set(true);
}

/// The navigator of the current tab. Pages pushed from inside a tab stay in that tab;
/// pages opened from the watch page overlay or a root sheet go to the visible tab.
NavigatorState _tabNavigator(BuildContext context) {
  final nav = Navigator.maybeOf(context);
  if (nav != null && shellBranchKeys.any((k) => k.currentState == nav)) return nav;
  return shellBranchKeys[ShellTabs.currentIndex].currentState ?? Navigator.of(context);
}

/// Pushes [page] inside the current tab (bottom bar and mini player stay visible) and
/// collapses the watch page if it is open.
Future<T?> pushInTab<T>(BuildContext context, Widget page) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(watchPageOpenProvider)) {
    container.read(watchPageOpenProvider.notifier).set(false);
  }
  final nav = _tabNavigator(context);
  return nav.push<T>(MaterialPageRoute<T>(builder: (_) => page));
}

void openChannel(BuildContext context, String channelId, {String? title}) =>
    pushInTab<void>(context, ChannelScreen(channelId: channelId, title: title));

void openPlaylist(BuildContext context, String playlistId) =>
    pushInTab<void>(context, PlaylistScreen(playlistId: playlistId));

void openLocalPlaylist(BuildContext context, LocalPlaylist playlist) =>
    pushInTab<void>(context, LocalPlaylistScreen(playlist: playlist));

void openSettings(BuildContext context) => pushInTab<void>(context, const SettingsScreen());

/// Switches to the Search tab.
void openSearchTab(BuildContext context) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null) {
    shell.goBranch(ShellTabs.search);
  } else {
    GoRouter.of(context).go('/search');
  }
}

/// Plays a whole list (Play all / Shuffle buttons) and opens the watch page.
void playList(WidgetRef ref, List<VideoItem> list, {bool shuffle = false, int start = 0}) {
  if (list.isEmpty) return;
  final player = ref.read(playerProvider.notifier);
  if (!shuffle && ref.read(playerProvider).shuffle) player.toggleShuffle();
  final first = shuffle ? DateTime.now().microsecondsSinceEpoch % list.length : start.clamp(0, list.length - 1);
  player.playQueue(list, start: first, shuffle: shuffle);
  ref.read(watchPageOpenProvider.notifier).set(true);
}
