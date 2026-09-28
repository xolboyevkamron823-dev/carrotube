import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/paging.dart';
import '../../data/youtube_service.dart';

/// Full metadata of a video (description, likes, exact date). The UI falls back to the
/// [VideoItem] it already has while this loads or when it fails.
final videoDetailsProvider = FutureProvider.autoDispose.family<VideoItem, String>(
  (ref, id) => ref.watch(youtubeServiceProvider).video(id),
  retry: noRetry,
);

/// Paged comments of a video; `unavailable` when YouTube returns none / disabled.
final commentsProvider = NotifierProvider.autoDispose.family<CommentsNotifier, PagedState<CommentItem>, String>(
  CommentsNotifier.new,
);

class CommentsNotifier extends PagedNotifier<CommentItem> {
  CommentsNotifier(this.videoId);
  final String videoId;

  @override
  int get minInitialItems => 0;

  @override
  Future<Paged<CommentItem>?> fetchFirst() => ref.read(youtubeServiceProvider).comments(videoId);
}

/// Whether the user asked for full screen with the button (landscape also means full
/// screen while the watch page is open).
final playerFullscreenProvider = NotifierProvider<PlayerFullscreen, bool>(PlayerFullscreen.new);

class PlayerFullscreen extends Notifier<bool> {
  bool _locked = false;

  @override
  bool build() => false;

  Future<void> enter() async {
    state = true;
    _locked = true;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Leaves full screen and keeps the watch page in portrait until it is collapsed.
  Future<void> exit() async {
    state = false;
    _locked = true;
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  /// Gives rotation back to the sensor (called when the watch page collapses).
  Future<void> release() async {
    state = false;
    if (!_locked) return;
    _locked = false;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
