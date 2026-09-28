import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/explore/explore_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/library/library_screen.dart';
import '../ui/search/search_screen.dart';
import '../ui/shell/app_shell.dart';
import '../ui/sound/sound_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Navigator keys of the five tab branches (used by `ui/nav.dart` to push detail pages
/// into the current tab from places that live outside the tab navigators, e.g. the
/// watch page overlay).
final shellBranchKeys = List<GlobalKey<NavigatorState>>.generate(
  5,
  (i) => GlobalKey<NavigatorState>(debugLabel: 'branch$i'),
);

/// Five tabs like YouTube (+ the Carrozzeria "Sound" tab). Each tab keeps its own
/// navigation stack; detail pages (channel, playlist, settings, sound sub-screens) are
/// pushed imperatively inside the tab so the bottom bar and mini player stay visible.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(navigatorKey: shellBranchKeys[0], routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(navigatorKey: shellBranchKeys[1], routes: [GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen())]),
        StatefulShellBranch(navigatorKey: shellBranchKeys[2], routes: [GoRoute(path: '/search', builder: (_, _) => const SearchScreen())]),
        StatefulShellBranch(navigatorKey: shellBranchKeys[3], routes: [GoRoute(path: '/library', builder: (_, _) => const LibraryScreen())]),
        StatefulShellBranch(navigatorKey: shellBranchKeys[4], routes: [GoRoute(path: '/sound', builder: (_, _) => const SoundScreen())]),
      ],
    ),
  ],
);
