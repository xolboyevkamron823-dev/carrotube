import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'models.dart';
import 'youtube_service.dart';

// Read-side providers. Mutations go through [LibraryActions], which invalidates them.
final historyProvider = FutureProvider<List<VideoItem>>((ref) => ref.watch(appDatabaseProvider).history());
final likedProvider = FutureProvider<List<VideoItem>>((ref) => ref.watch(appDatabaseProvider).liked());
final localPlaylistsProvider =
    FutureProvider<List<LocalPlaylist>>((ref) => ref.watch(appDatabaseProvider).playlists());
final localPlaylistVideosProvider = FutureProvider.family<List<VideoItem>, int>(
    (ref, id) => ref.watch(appDatabaseProvider).playlistVideos(id));
final subscriptionsProvider =
    FutureProvider<List<ChannelItem>>((ref) => ref.watch(appDatabaseProvider).subscriptions());
final searchHistoryProvider = FutureProvider<List<String>>((ref) => ref.watch(appDatabaseProvider).searchHistory());
final isLikedProvider = FutureProvider.family<bool, String>((ref, id) => ref.watch(appDatabaseProvider).isLiked(id));
final isSubscribedProvider =
    FutureProvider.family<bool, String>((ref, id) => ref.watch(appDatabaseProvider).isSubscribed(id));

/// Latest uploads of all subscribed channels, newest first (Subscriptions feed).
final subscriptionFeedProvider = FutureProvider<List<VideoItem>>((ref) async {
  final subs = await ref.watch(subscriptionsProvider.future);
  final yt = ref.watch(youtubeServiceProvider);
  final results = await Future.wait(subs.take(25).map((c) async {
    try {
      final page = await yt.channelUploads(c.id);
      return page.items.take(8).toList();
    } catch (_) {
      return <VideoItem>[];
    }
  }));
  final all = results.expand((e) => e).toList();
  all.sort((a, b) {
    final da = a.uploadDate, db = b.uploadDate;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return all;
});

final libraryActionsProvider = Provider<LibraryActions>((ref) => LibraryActions(ref));

class LibraryActions {
  LibraryActions(this._ref);
  final Ref _ref;
  AppDatabase get _db => _ref.read(appDatabaseProvider);

  Future<void> addHistory(VideoItem v) async {
    await _db.addHistory(v);
    _ref.invalidate(historyProvider);
  }

  Future<void> removeHistory(String id) async {
    await _db.removeHistory(id);
    _ref.invalidate(historyProvider);
  }

  Future<void> clearHistory() async {
    await _db.clearHistory();
    _ref.invalidate(historyProvider);
  }

  Future<void> setLiked(VideoItem v, bool liked) async {
    await _db.setLiked(v, liked);
    _ref.invalidate(likedProvider);
    _ref.invalidate(isLikedProvider(v.id));
  }

  Future<int> createPlaylist(String name) async {
    final id = await _db.createPlaylist(name);
    _ref.invalidate(localPlaylistsProvider);
    return id;
  }

  Future<void> renamePlaylist(int id, String name) async {
    await _db.renamePlaylist(id, name);
    _ref.invalidate(localPlaylistsProvider);
  }

  Future<void> deletePlaylist(int id) async {
    await _db.deletePlaylist(id);
    _ref.invalidate(localPlaylistsProvider);
  }

  Future<void> addToPlaylist(int id, VideoItem v) async {
    await _db.addToPlaylist(id, v);
    _ref.invalidate(localPlaylistsProvider);
    _ref.invalidate(localPlaylistVideosProvider(id));
  }

  Future<void> removeFromPlaylist(int id, String videoId) async {
    await _db.removeFromPlaylist(id, videoId);
    _ref.invalidate(localPlaylistsProvider);
    _ref.invalidate(localPlaylistVideosProvider(id));
  }

  Future<void> reorderPlaylist(int id, List<String> ids) async {
    await _db.reorderPlaylist(id, ids);
    _ref.invalidate(localPlaylistVideosProvider(id));
  }

  Future<void> setSubscribed(ChannelItem c, bool on) async {
    await _db.setSubscribed(c, on);
    _ref.invalidate(subscriptionsProvider);
    _ref.invalidate(isSubscribedProvider(c.id));
    _ref.invalidate(subscriptionFeedProvider);
  }

  Future<void> addSearch(String q) async {
    if (q.trim().isEmpty) return;
    await _db.addSearch(q.trim());
    _ref.invalidate(searchHistoryProvider);
  }

  Future<void> removeSearch(String q) async {
    await _db.removeSearch(q);
    _ref.invalidate(searchHistoryProvider);
  }

  Future<void> clearSearchHistory() async {
    await _db.clearSearchHistory();
    _ref.invalidate(searchHistoryProvider);
  }
}
