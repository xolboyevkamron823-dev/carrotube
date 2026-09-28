import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'youtube_service.dart';

/// Immutable state of an infinitely scrolling list.
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.moreError,
    this.unavailable = false,
  });

  final List<T> items;

  /// First page is loading (show skeletons).
  final bool loading;

  /// A following page is loading (show a footer spinner).
  final bool loadingMore;
  final bool hasMore;

  /// Error of the first page (show a full error view).
  final Object? error;

  /// Error of a following page (show a small retry footer).
  final Object? moreError;

  /// The source reported that this content does not exist (e.g. disabled comments).
  final bool unavailable;

  bool get isEmpty => !loading && error == null && items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
    Object? moreError,
    bool clearMoreError = false,
    bool? unavailable,
  }) => PagedState<T>(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    moreError: clearMoreError ? null : (moreError ?? this.moreError),
    unavailable: unavailable ?? this.unavailable,
  );
}

/// Base class for [Paged]-backed lists: loads the first page on build, [loadMore] appends
/// the next one, [refresh] reloads while keeping the current items visible
/// (pull-to-refresh). Items are de-duplicated with [keyOf].
abstract class PagedNotifier<T> extends Notifier<PagedState<T>> {
  Paged<T>? _page;
  int _generation = 0;
  final _seen = <String>{};

  /// Fetches the first page. Returning null marks the content as unavailable.
  Future<Paged<T>?> fetchFirst();

  /// Stable key used to drop duplicates across pages; null disables de-duplication.
  String? keyOf(T item) => null;

  /// Minimum number of items the first load tries to reach before stopping.
  int get minInitialItems => 8;

  @override
  PagedState<T> build() {
    _page = null;
    _seen.clear();
    final gen = ++_generation;
    Future.microtask(() => _loadFirst(gen, keepItems: false));
    return PagedState<T>();
  }

  List<T> _dedupe(Iterable<T> items) {
    final out = <T>[];
    for (final i in items) {
      final k = keyOf(i);
      if (k == null || _seen.add(k)) out.add(i);
    }
    return out;
  }

  bool _alive(int gen) => ref.mounted && gen == _generation;

  Future<void> _loadFirst(int gen, {required bool keepItems}) async {
    try {
      final page = await fetchFirst();
      if (!_alive(gen)) return;
      if (page == null) {
        state = PagedState<T>(loading: false, unavailable: true);
        return;
      }
      _page = page;
      _seen.clear();
      final items = _dedupe(page.items);
      state = PagedState<T>(items: items, loading: false, hasMore: page.hasMore);
      if (items.length < minInitialItems && page.hasMore) await loadMore();
    } catch (e) {
      if (!_alive(gen)) return;
      if (keepItems && state.items.isNotEmpty) {
        state = state.copyWith(loading: false, moreError: e);
      } else {
        state = PagedState<T>(loading: false, error: e);
      }
    }
  }

  /// Pull-to-refresh: reloads the first page, keeping the old items until it arrives.
  Future<void> refresh() async {
    final gen = ++_generation;
    if (state.items.isEmpty) state = PagedState<T>();
    await _loadFirst(gen, keepItems: true);
  }

  /// Full reload that shows skeletons again (used by Retry buttons).
  Future<void> retry() async {
    final gen = ++_generation;
    _page = null;
    _seen.clear();
    state = PagedState<T>();
    await _loadFirst(gen, keepItems: false);
  }

  /// Appends the next page (infinite scroll). Safe to call repeatedly.
  /// After a failed page, automatic calls (scrolling) stop until [force] is used by the
  /// Retry footer, so a broken connection does not fire a request per scroll event.
  Future<void> loadMore({bool force = false}) async {
    final page = _page;
    if (page == null || !page.hasMore || state.loadingMore || state.loading) return;
    if (state.moreError != null && !force) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true, clearMoreError: true);
    try {
      var next = await page.next();
      var added = next == null ? <T>[] : _dedupe(next.items);
      // A page made only of duplicates: keep going a couple of times.
      var guard = 0;
      while (added.isEmpty && next != null && next.hasMore && guard < 3) {
        if (!_alive(gen)) return;
        next = await next.next();
        added = next == null ? <T>[] : _dedupe(next.items);
        guard++;
      }
      if (!_alive(gen)) return;
      _page = next;
      state = state.copyWith(items: [...state.items, ...added], loadingMore: false, hasMore: next?.hasMore ?? false);
    } catch (e) {
      if (!_alive(gen)) return;
      state = state.copyWith(loadingMore: false, moreError: e);
    }
  }
}

/// Riverpod retry policy for providers whose errors are shown to the user with a Retry
/// button instead of silently retrying in the background.
Duration? noRetry(int retryCount, Object error) => null;
