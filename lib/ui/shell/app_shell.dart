import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/router.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../player/mini_player.dart';
import '../watch/player_view.dart';
import '../watch/watch_providers.dart';
import 'player_panel.dart';

/// Root of the five tabs: tab content, YouTube bottom bar, the persistent mini player
/// and the draggable watch page overlay.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ShellTabs.currentIndex = navigationShell.currentIndex;
    return _ShellBody(navigationShell: navigationShell);
  }
}

enum _DragMode { panel, dismiss }

class _ShellBody extends ConsumerStatefulWidget {
  const _ShellBody({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends ConsumerState<_ShellBody> with TickerProviderStateMixin {
  static const _navBarHeight = 56.0;
  static const _animDuration = Duration(milliseconds: 320);

  late final AnimationController _panel = AnimationController(vsync: this, duration: _animDuration);

  /// Swipe-down-to-close of the mini player (0..1 of the dismiss distance).
  late final AnimationController _dismiss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  double _travel = 1;
  _DragMode? _dragMode;
  bool? _immersive;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(watchPageOpenProvider) && ref.read(playerProvider).isActive) _panel.value = 1;
  }

  @override
  void dispose() {
    _panel.dispose();
    _dismiss.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------------------
  // Panel state
  // -------------------------------------------------------------------------------------
  void _animateTo(bool open) {
    _panel.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic, duration: _animDuration);
  }

  void _setOpen(bool open) {
    if (ref.read(watchPageOpenProvider) != open) {
      ref.read(watchPageOpenProvider.notifier).set(open);
    } else {
      _animateTo(open);
    }
  }

  void _toggleFullscreen() {
    final fs = ref.read(playerFullscreenProvider.notifier);
    if (_fullscreen) {
      fs.exit();
    } else {
      fs.enter();
    }
  }

  Future<void> _close() async {
    await ref.read(playerProvider.notifier).stop();
  }

  void _onDragStart(DragStartDetails d) {
    _dragMode = null;
    _panel.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final dy = d.primaryDelta ?? d.delta.dy;
    _dragMode ??= (_panel.value <= 0.001 && dy > 0) ? _DragMode.dismiss : _DragMode.panel;
    if (_dragMode == _DragMode.dismiss) {
      _dismiss.value = (_dismiss.value + dy / (kMiniPlayerHeight * 1.4)).clamp(0.0, 1.0);
    } else {
      _panel.value = (_panel.value - dy / _travel).clamp(0.0, 1.0);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragMode == _DragMode.dismiss) {
      if (_dismiss.value > 0.5 || v > 700) {
        _dismiss.animateTo(1).then((_) async {
          await _close();
          if (mounted) _dismiss.value = 0;
        });
      } else {
        _dismiss.animateBack(0);
      }
    } else {
      final open = v.abs() > 350 ? v < 0 : _panel.value > 0.5;
      _setOpen(open);
    }
    _dragMode = null;
  }

  // -------------------------------------------------------------------------------------
  // Back button & system UI
  // -------------------------------------------------------------------------------------
  Future<bool> _onBack() async {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false; // a sheet/dialog is on top
    if (_fullscreen) {
      await ref.read(playerFullscreenProvider.notifier).exit();
      return true;
    }
    if (ref.read(watchPageOpenProvider) && ref.read(playerProvider).isActive) {
      _setOpen(false);
      return true;
    }
    return false;
  }

  void _syncSystemUi(bool fullscreen) {
    if (_immersive == fullscreen) return;
    _immersive = fullscreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    });
  }

  void _onTabSelected(int i) {
    final shell = widget.navigationShell;
    if (i == shell.currentIndex) {
      shellBranchKeys[i].currentState?.popUntil((r) => r.isFirst);
    }
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(watchPageOpenProvider, (prev, open) {
      _animateTo(open && ref.read(playerProvider).isActive);
      if (open) {
        FocusManager.instance.primaryFocus?.unfocus();
      } else {
        ref.read(playerFullscreenProvider.notifier).release();
      }
    });
    ref.listen<bool>(playerProvider.select((s) => s.isActive), (prev, active) {
      if (active) return;
      _panel.value = 0;
      if (ref.read(watchPageOpenProvider)) ref.read(watchPageOpenProvider.notifier).set(false);
    });

    final active = ref.watch(playerProvider.select((s) => s.isActive));
    final pip = ref.watch(playerProvider.select((s) => s.pipActive));
    final watchOpen = ref.watch(watchPageOpenProvider);
    final fsRequested = ref.watch(playerFullscreenProvider);

    final mq = MediaQuery.of(context);
    final landscape = mq.orientation == Orientation.landscape;
    _fullscreen = active && watchOpen && (fsRequested || landscape);
    _syncSystemUi(_fullscreen || (pip && active));

    final navTotal = _navBarHeight + mq.padding.bottom;
    final contentBottom = navTotal + (active ? kMiniPlayerHeight : 0);

    final content = Positioned(
      left: 0,
      top: 0,
      right: 0,
      bottom: contentBottom,
      child: MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: 0),
          viewPadding: mq.viewPadding.copyWith(bottom: 0),
          viewInsets: mq.viewInsets.copyWith(bottom: math.max(0, mq.viewInsets.bottom - contentBottom)),
        ),
        child: widget.navigationShell,
      ),
    );

    // PopScope makes the framework claim the back gesture (predictive back on Android 14+)
    // while the watch page is open; BackButtonListener then handles it before the tab
    // navigators do.
    return PopScope(
      canPop: !(active && (watchOpen || _fullscreen)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: BackButtonListener(
        onBackButtonPressed: _onBack,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final collapsedTop = size.height - navTotal - kMiniPlayerHeight;
              _travel = math.max(1, collapsedTop);
              return Stack(
                children: [
                  content,
                  AnimatedBuilder(
                    animation: Listenable.merge([_panel, _dismiss]),
                    builder: (context, _) {
                      final t = active ? _panel.value : 0.0;
                      final panelTop = _fullscreen ? 0.0 : collapsedTop * (1 - t);
                      final panelHeight = _fullscreen ? size.height : size.height - panelTop - navTotal * (1 - t);
                      final dismissOffset = _dismiss.value * kMiniPlayerHeight * 1.4;
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: -navTotal * (_fullscreen ? 1 : t),
                            height: navTotal,
                            child: _BottomBar(
                              currentIndex: widget.navigationShell.currentIndex,
                              onSelected: _onTabSelected,
                            ),
                          ),
                          if (active)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: panelTop + dismissOffset,
                              height: panelHeight,
                              child: Opacity(
                                opacity: (1 - _dismiss.value).clamp(0.0, 1.0),
                                child: Material(
                                  elevation: t < 0.05 ? 8 : 0,
                                  shadowColor: Colors.black54,
                                  child: PlayerPanel(
                                    t: _fullscreen ? 1 : t,
                                    screenSize: size,
                                    topInset: mq.padding.top,
                                    fullscreen: _fullscreen,
                                    onExpand: () => _setOpen(true),
                                    onCollapse: () => _setOpen(false),
                                    onClose: _close,
                                    onToggleFullscreen: _toggleFullscreen,
                                    onDragStart: _onDragStart,
                                    onDragUpdate: _onDragUpdate,
                                    onDragEnd: _onDragEnd,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  // Picture-in-picture: the whole (tiny) window is the video. The tabs stay
                  // mounted underneath so nothing is lost when PiP ends.
                  if (pip && active) const Positioned.fill(child: PlayerView(pipMode: true)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentIndex, required this.onSelected});
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: context.tr('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.play_circle_outline_rounded),
            selectedIcon: const Icon(Icons.play_circle_rounded),
            label: context.tr('music'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_rounded),
            selectedIcon: const Icon(Icons.search_rounded, weight: 700),
            label: context.tr('search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.video_library_outlined),
            selectedIcon: const Icon(Icons.video_library_rounded),
            label: context.tr('library'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.graphic_eq_rounded),
            selectedIcon: const Icon(Icons.equalizer_rounded),
            label: context.tr('sound'),
          ),
        ],
      ),
    );
  }
}
