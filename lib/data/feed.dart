import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library.dart';
import 'models.dart';
import 'paging.dart';
import 'youtube_service.dart';

export 'paging.dart';

/// Category chips on top of the Home tab. Every chip except [all] is a search query.
enum FeedCategory {
  all('all', null),
  music('music', 'music hits 2026'),
  pop('pop', 'pop music 2026'),
  rap('rap', 'rap 2026 new'),
  uzbek('uzbek', 'uzbek music 2026'),
  russian('russian', 'русская музыка хиты'),
  remix('remix', 'remix 2026'),
  live('live', 'live concert'),
  podcasts('podcasts', 'podcast full episode'),
  gaming('gaming', 'gaming'),
  news('news', 'news today');

  const FeedCategory(this.labelKey, this.query);

  /// l10n key of the chip label.
  final String labelKey;
  final String? query;
}

/// Query mixed into the "All" feed together with history based recommendations.
const trendingQuery = 'trending';

final selectedFeedCategoryProvider = NotifierProvider<SelectedFeedCategory, FeedCategory>(SelectedFeedCategory.new);

class SelectedFeedCategory extends Notifier<FeedCategory> {
  @override
  FeedCategory build() => FeedCategory.all;
  void select(FeedCategory c) => state = c;
}

/// Home feed per category (kept alive so switching chips back is instant).
final homeFeedProvider = NotifierProvider.family<HomeFeedNotifier, PagedState<VideoItem>, FeedCategory>(
  HomeFeedNotifier.new,
);

class HomeFeedNotifier extends PagedNotifier<VideoItem> {
  HomeFeedNotifier(this.category);
  final FeedCategory category;

  YoutubeService get _yt => ref.read(youtubeServiceProvider);

  @override
  String? keyOf(VideoItem item) => item.id;

  @override
  Future<Paged<VideoItem>?> fetchFirst() async {
    final q = category.query;
    if (q != null) return _yt.videoSearch(q);
    return _recommendations();
  }

  /// "All": related videos of the 2-3 most recently watched items interleaved with a
  /// trending search. Every source keeps paging on its own.
  Future<Paged<VideoItem>> _recommendations() async {
    List<VideoItem> history;
    try {
      history = await ref.read(historyProvider.future);
    } catch (_) {
      history = const [];
    }
    final seeds = <VideoItem>[];
    for (final v in history) {
      if (v.isLive || seeds.any((s) => s.id == v.id)) continue;
      seeds.add(v);
      if (seeds.length == 3) break;
    }
    final futures = <Future<Paged<VideoItem>?>>[
      for (final s in seeds) _safe(() => _yt.related(s.id)),
      _safe(() => _yt.videoSearch(trendingQuery)),
    ];
    final pages = (await Future.wait(futures)).whereType<Paged<VideoItem>>().toList();
    if (pages.isEmpty) {
      // Everything failed: surface the error of the plain trending query.
      return _yt.videoSearch(trendingQuery);
    }
    return mergePaged(pages);
  }

  static Future<Paged<VideoItem>?> _safe(Future<Paged<VideoItem>> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }
}

/// Interleaves several paged sources round-robin into one paged source.
Paged<T> mergePaged<T>(List<Paged<T>> sources) {
  final merged = <T>[];
  final maxLen = sources.fold<int>(0, (m, p) => p.items.length > m ? p.items.length : m);
  for (var i = 0; i < maxLen; i++) {
    for (final s in sources) {
      if (i < s.items.length) merged.add(s.items[i]);
    }
  }
  final withMore = sources.where((s) => s.hasMore).toList();
  if (withMore.isEmpty) return Paged<T>(merged);
  return Paged<T>(merged, () async {
    final next = await Future.wait(
      withMore.map((s) async {
        try {
          return await s.next();
        } catch (_) {
          return null;
        }
      }),
    );
    final pages = next.whereType<Paged<T>>().toList();
    if (pages.isEmpty) return null;
    return mergePaged(pages);
  });
}

// -----------------------------------------------------------------------------------------
// Explore / Music
// -----------------------------------------------------------------------------------------

/// Moods & genres of the Music tab: l10n key + search query + accent colour.
class Mood {
  const Mood(this.labelKey, this.query, this.color);
  final String labelKey;
  final String query;
  final int color;
}

const moods = <Mood>[
  Mood('mood_chill', 'chill music', 0xFF4FC3F7),
  Mood('mood_workout', 'workout music', 0xFFFF7043),
  Mood('mood_party', 'party music', 0xFFE040FB),
  Mood('mood_focus', 'focus music', 0xFF26A69A),
  Mood('mood_romance', 'romantic songs', 0xFFF06292),
  Mood('mood_sad', 'sad songs', 0xFF7986CB),
  Mood('mood_sleep', 'sleep music', 0xFF5C6BC0),
  Mood('mood_commute', 'car music bass boosted', 0xFFFFCA28),
  Mood('mood_energy', 'energy boost music', 0xFFFF5252),
  Mood('mood_feel_good', 'feel good music', 0xFF66BB6A),
  Mood('uzbek', 'uzbek music 2026', 0xFF29B6F6),
  Mood('russian', 'русская музыка хиты', 0xFFEF5350),
];

final selectedMoodProvider = NotifierProvider<SelectedMood, Mood?>(SelectedMood.new);

class SelectedMood extends Notifier<Mood?> {
  @override
  Mood? build() => null;
  void select(Mood? m) => state = m;
}

Future<List<VideoItem>> _firstVideos(YoutubeService yt, String query, {int take = 20}) async {
  final page = await yt.videoSearch(query);
  return page.items.where((v) => !v.isLive).take(take).toList();
}

Future<List<PlaylistItem>> _playlists(YoutubeService yt, String query, {int take = 6}) async {
  final page = await yt.search(query, const SearchFilters(type: SearchType.playlists));
  return page.items.whereType<SearchPlaylistEntry>().map((e) => e.playlist).take(take).toList();
}

/// "Trending" shelf / list of the Music tab.
final exploreTrendingProvider = FutureProvider<List<VideoItem>>(
  (ref) => _firstVideos(ref.watch(youtubeServiceProvider), 'trending music 2026', take: 20),
  retry: noRetry,
);

/// "New releases" shelf.
final exploreNewReleasesProvider = FutureProvider<List<VideoItem>>(
  (ref) => _firstVideos(ref.watch(youtubeServiceProvider), 'new songs 2026 official music video', take: 16),
  retry: noRetry,
);

/// "Quick picks": related songs of the last watched item, trending as a fallback.
final exploreQuickPicksProvider = FutureProvider<List<VideoItem>>((ref) async {
  final yt = ref.watch(youtubeServiceProvider);
  List<VideoItem> history;
  try {
    history = await ref.read(historyProvider.future);
  } catch (_) {
    history = const [];
  }
  if (history.isNotEmpty) {
    try {
      final page = await yt.related(history.first.id);
      final items = page.items.where((v) => !v.isLive).take(16).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}
  }
  return _firstVideos(yt, 'top hits 2026', take: 16);
}, retry: noRetry);

/// Chart playlists (Top 100 global / Uzbekistan / Russia ...).
const chartQueries = <(String, int)>[
  ('Top 100 Songs Global', 3),
  ('Top 100 Music Videos Uzbekistan', 3),
  ('Top 100 Songs Russia', 2),
  ('Top 50 Uzbekistan chart', 2),
];

final exploreChartsProvider = FutureProvider<List<PlaylistItem>>((ref) async {
  final yt = ref.watch(youtubeServiceProvider);
  final results = await Future.wait(
    chartQueries.map((q) async {
      try {
        return await _playlists(yt, q.$1, take: q.$2);
      } catch (_) {
        return <PlaylistItem>[];
      }
    }),
  );
  final seen = <String>{};
  final out = [
    for (final list in results)
      for (final p in list)
        if (seen.add(p.id)) p,
  ];
  if (out.isEmpty) throw StateError('charts unavailable');
  return out;
}, retry: noRetry);

/// Shelves shown when a mood chip is selected.
class MoodShelves {
  const MoodShelves(this.playlists, this.videos);
  final List<PlaylistItem> playlists;
  final List<VideoItem> videos;
}

final moodShelvesProvider = FutureProvider.family<MoodShelves, String>((ref, query) async {
  final yt = ref.watch(youtubeServiceProvider);
  final results = await Future.wait<Object>([
    _playlists(yt, '$query playlist', take: 10).catchError((_) => <PlaylistItem>[]),
    _firstVideos(yt, query, take: 24),
  ]);
  return MoodShelves(results[0] as List<PlaylistItem>, results[1] as List<VideoItem>);
}, retry: noRetry);

// -----------------------------------------------------------------------------------------
// Channels
// -----------------------------------------------------------------------------------------

/// Channel details (avatar, banner, subscribers) cached for the app lifetime; used by
/// feed cards for avatars, the watch page channel row and the channel page.
final channelInfoProvider = FutureProvider.family<ChannelItem, String>(
  (ref, id) => ref.watch(youtubeServiceProvider).channel(id),
  retry: noRetry,
);
