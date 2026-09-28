import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../data/paging.dart';
import '../../data/youtube_service.dart';
import '../widgets/channel_tile.dart';
import '../widgets/chips.dart';
import '../widgets/playlist_tile.dart';
import '../widgets/sheets.dart';
import '../widgets/shimmer.dart';
import '../widgets/states.dart';
import '../widgets/video_card.dart';

/// Search query + filters (records compare by value, so they work as a family key).
typedef SearchKey = (String query, SearchType type, SearchDuration duration, SearchUploadDate uploadDate);

SearchKey searchKeyOf(String q, SearchFilters f) => (q, f.type, f.duration, f.uploadDate);

final searchResultsProvider = NotifierProvider.autoDispose
    .family<SearchResultsNotifier, PagedState<SearchEntry>, SearchKey>(SearchResultsNotifier.new);

class SearchResultsNotifier extends PagedNotifier<SearchEntry> {
  SearchResultsNotifier(this.key);
  final SearchKey key;

  @override
  String? keyOf(SearchEntry item) => switch (item) {
    SearchVideoEntry(:final video) => 'v:${video.id}',
    SearchChannelEntry(:final channel) => 'c:${channel.id}',
    SearchPlaylistEntry(:final playlist) => 'p:${playlist.id}',
  };

  @override
  Future<Paged<SearchEntry>?> fetchFirst() => ref
      .read(youtubeServiceProvider)
      .search(key.$1, SearchFilters(type: key.$2, duration: key.$3, uploadDate: key.$4));
}

/// Search tab: pill search field, live suggestions + history, mixed results with filters.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _suggestToken = 0;
  List<String> _suggestions = const [];
  String? _submitted;
  SearchFilters _filters = const SearchFilters();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _editing => _submitted == null || _focus.hasFocus;

  void _onTextChanged() {
    _debounce?.cancel();
    final q = _controller.text;
    if (q.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final token = ++_suggestToken;
      final list = await ref.read(youtubeServiceProvider).suggestions(q);
      if (!mounted || token != _suggestToken) return;
      setState(() => _suggestions = list);
    });
  }

  void _submit(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    ref.read(libraryActionsProvider).addSearch(query);
    setState(() => _submitted = query);
  }

  void _fill(String q) {
    _controller.value = TextEditingValue(
      text: '$q ',
      selection: TextSelection.collapsed(offset: q.length + 1),
    );
    _focus.requestFocus();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FiltersSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  void _back() {
    if (_focus.hasFocus && _submitted != null) {
      _controller.text = _submitted!;
      _focus.unfocus();
      return;
    }
    setState(() {
      _submitted = null;
      _controller.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showResults = !_editing && _submitted != null;
    return PopScope(
      canPop: _submitted == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: _submitted == null ? 16 : 0,
          leading: _submitted == null ? null : IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
          automaticallyImplyLeading: false,
          title: SizedBox(
            height: 40,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              onTap: () => setState(() {}),
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: context.tr('search_hint'),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _controller.clear();
                            _focus.requestFocus();
                          },
                        ),
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: context.tr('filters'),
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: !_filters.isDefault,
                backgroundColor: YtColors.red,
                smallSize: 8,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: showResults
              ? _Results(
                  key: ValueKey(searchKeyOf(_submitted!, _filters)),
                  searchKey: searchKeyOf(_submitted!, _filters),
                  filters: _filters,
                  onTypeChanged: (t) => setState(() => _filters = _filters.copyWith(type: t)),
                )
              : _Suggestions(
                  key: const ValueKey('suggestions'),
                  text: _controller.text,
                  suggestions: _suggestions,
                  onSearch: _submit,
                  onFill: _fill,
                ),
        ),
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({
    super.key,
    required this.text,
    required this.suggestions,
    required this.onSearch,
    required this.onFill,
  });

  final String text;
  final List<String> suggestions;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const <String>[];
    final q = text.trim().toLowerCase();
    final actions = ref.read(libraryActionsProvider);
    final matchingHistory = q.isEmpty ? history : history.where((h) => h.toLowerCase().contains(q)).take(4).toList();
    final fromApi = suggestions.where((s) => !matchingHistory.contains(s)).toList();

    if (q.isEmpty && history.isEmpty) {
      return EmptyView(icon: Icons.search_rounded, message: context.tr('search_empty'));
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (q.isEmpty)
          SectionHeader(
            context.tr('search_history'),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            trailing: TextButton(
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: context.tr('clear_search_history'),
                  confirmLabel: context.tr('clear'),
                );
                if (ok) actions.clearSearchHistory();
              },
              child: Text(context.tr('clear')),
            ),
          ),
        for (final h in matchingHistory)
          _SuggestionRow(
            text: h,
            history: true,
            onTap: () => onSearch(h),
            onFill: () => onFill(h),
            onRemove: () => actions.removeSearch(h),
          ),
        for (final s in fromApi) _SuggestionRow(text: s, onTap: () => onSearch(s), onFill: () => onFill(s)),
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.text,
    required this.onTap,
    required this.onFill,
    this.history = false,
    this.onRemove,
  });

  final String text;
  final bool history;
  final VoidCallback onTap;
  final VoidCallback onFill;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(history ? Icons.history_rounded : Icons.search_rounded, color: scheme.onSurfaceVariant),
      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      onLongPress: onRemove == null
          ? null
          : () async {
              final ok = await showConfirmDialog(
                context,
                title: text,
                body: context.tr('remove_from_search_history'),
                confirmLabel: context.tr('remove'),
              );
              if (ok) onRemove!();
            },
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
            ),
          IconButton(
            onPressed: onFill,
            icon: Icon(Icons.north_west_rounded, size: 20, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({super.key, required this.searchKey, required this.filters, required this.onTypeChanged});
  final SearchKey searchKey;
  final SearchFilters filters;
  final ValueChanged<SearchType> onTypeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchResultsProvider(searchKey));
    final notifier = ref.read(searchResultsProvider(searchKey).notifier);

    final typeChips = SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        children: [
          for (final t in SearchType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: YtChip(label: context.tr(_typeKey(t)), selected: filters.type == t, onTap: () => onTypeChanged(t)),
            ),
        ],
      ),
    );

    Widget body;
    if (state.loading) {
      body = ListView(physics: const NeverScrollableScrollPhysics(), children: [SkeletonList.cards(count: 3)]);
    } else if (state.error != null) {
      body = ErrorView(error: state.error, onRetry: notifier.retry);
    } else if (state.isEmpty) {
      body = EmptyView(icon: Icons.search_off_rounded, message: context.tr('no_results'));
    } else {
      body = RefreshIndicator(
        onRefresh: notifier.refresh,
        child: InfiniteScroll(
          onLoadMore: notifier.loadMore,
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: state.items.length + 1,
            itemBuilder: (context, i) {
              if (i == state.items.length) {
                return LoadMoreFooter(
                  loading: state.loadingMore || state.hasMore,
                  error: state.moreError,
                  onRetry: () => notifier.loadMore(force: true),
                );
              }
              return switch (state.items[i]) {
                SearchVideoEntry(:final video) => VideoCard(video: video, key: ValueKey('v${video.id}')),
                SearchChannelEntry(:final channel) => ChannelTile(channel: channel),
                SearchPlaylistEntry(:final playlist) => PlaylistTile.remote(context, playlist),
              };
            },
          ),
        ),
      );
    }

    return Column(
      children: [
        typeChips,
        Expanded(
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: body),
        ),
      ],
    );
  }
}

String _typeKey(SearchType t) => switch (t) {
  SearchType.all => 'all',
  SearchType.videos => 'videos',
  SearchType.channels => 'channels',
  SearchType.playlists => 'playlists',
};

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial});
  final SearchFilters initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late SearchFilters _f = widget.initial;

  Widget _group<T>(String title, List<T> values, T selected, String Function(T) label, ValueChanged<T> onSelected) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in values)
                SizedBox(
                  height: 34,
                  child: YtChip(label: label(v), selected: v == selected, onTap: () => setState(() => onSelected(v))),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('filters'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _f = const SearchFilters()),
                    child: Text(context.tr('reset')),
                  ),
                ],
              ),
            ),
            _group<SearchType>(
              context.tr('type'),
              SearchType.values,
              _f.type,
              (t) => context.tr(_typeKey(t)),
              (t) => _f = _f.copyWith(type: t),
            ),
            _group<SearchDuration>(
              context.tr('duration'),
              SearchDuration.values,
              _f.duration,
              (d) => context.tr(switch (d) {
                SearchDuration.any => 'any',
                SearchDuration.short => 'short_4',
                SearchDuration.long => 'long_20',
              }),
              (d) => _f = _f.copyWith(duration: d),
            ),
            _group<SearchUploadDate>(
              context.tr('upload_date'),
              SearchUploadDate.values,
              _f.uploadDate,
              (d) => context.tr(switch (d) {
                SearchUploadDate.any => 'any',
                SearchUploadDate.hour => 'last_hour',
                SearchUploadDate.today => 'today',
                SearchUploadDate.week => 'this_week',
                SearchUploadDate.month => 'this_month',
                SearchUploadDate.year => 'this_year',
              }),
              (d) => _f = _f.copyWith(uploadDate: d),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_f),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(context.tr('apply')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
