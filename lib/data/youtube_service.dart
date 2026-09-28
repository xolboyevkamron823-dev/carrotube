import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'models.dart';

/// A page of results plus a way to fetch the next page (infinite scroll).
class Paged<T> {
  Paged(this.items, [this._next]);
  final List<T> items;
  final Future<Paged<T>?> Function()? _next;
  bool get hasMore => _next != null;
  Future<Paged<T>?> next() async => _next == null ? null : _next();

  static Paged<T> empty<T>() => Paged<T>(const []);
}

final youtubeServiceProvider = Provider<YoutubeService>((ref) {
  final s = YoutubeService();
  ref.onDispose(s.close);
  return s;
});

/// Everything YouTube: search, suggestions, metadata, related, comments, channels,
/// playlists and stream resolution. No API key (youtube_explode_dart).
class YoutubeService {
  YoutubeService() : _yt = yt.YoutubeExplode();

  final yt.YoutubeExplode _yt;
  final _videoCache = <String, yt.Video>{};
  final _streamCache = <String, ResolvedStreams>{};
  final _inflight = <String, Future<ResolvedStreams>>{};

  /// User-Agent of the Android client whose stream URLs we play (YouTube checks it).
  static const androidClientUa = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  void close() => _yt.close();

  // ---------------------------------------------------------------------------------------
  // Mapping helpers
  // ---------------------------------------------------------------------------------------
  VideoItem _fromVideo(yt.Video v) => VideoItem(
        id: v.id.value,
        title: v.title,
        channelName: v.author,
        channelId: v.channelId.value,
        duration: v.duration,
        viewCount: v.engagement.viewCount,
        likeCount: v.engagement.likeCount,
        uploadDate: v.uploadDate ?? v.publishDate,
        uploadDateText: v.uploadDateRaw,
        description: v.description,
        isLive: v.isLive,
      );

  static Duration? parseDuration(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    var secs = 0;
    for (final p in parts) {
      secs = secs * 60 + p;
    }
    return Duration(seconds: secs);
  }

  static String? _bestThumb(List<yt.Thumbnail> t) {
    if (t.isEmpty) return null;
    final sorted = [...t]..sort((a, b) => b.width.compareTo(a.width));
    var url = sorted.first.url.toString();
    if (url.startsWith('//')) url = 'https:$url';
    return url;
  }

  VideoItem _fromSearchVideo(yt.SearchVideo v) => VideoItem(
        id: v.id.value,
        title: v.title,
        channelName: v.author,
        channelId: v.channelId,
        duration: parseDuration(v.duration),
        viewCount: v.viewCount,
        uploadDateText: v.uploadDate,
        description: v.description,
        isLive: v.isLive,
      );

  ChannelItem _fromSearchChannel(yt.SearchChannel c) => ChannelItem(
        id: c.id.value,
        title: c.name,
        avatarUrl: _bestThumb(c.thumbnails),
        videoCount: c.videoCount,
        description: c.description,
      );

  PlaylistItem _fromSearchPlaylist(yt.SearchPlaylist p) => PlaylistItem(
        id: p.id.value,
        title: p.title,
        videoCount: p.videoCount,
        thumbnailUrl: _bestThumb(p.thumbnails),
      );

  void _cache(yt.Video v) {
    if (_videoCache.length > 300) _videoCache.remove(_videoCache.keys.first);
    _videoCache[v.id.value] = v;
  }

  // ---------------------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------------------
  Future<List<String>> suggestions(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      return await _yt.search.getQuerySuggestions(query);
    } catch (_) {
      return const [];
    }
  }

  yt.SearchFilter _filterFor(SearchFilters f) {
    // YouTube accepts one "sp" filter; the rest is applied client-side.
    switch (f.uploadDate) {
      case SearchUploadDate.hour:
        return yt.UploadDateFilter.lastHour;
      case SearchUploadDate.today:
        return yt.UploadDateFilter.today;
      case SearchUploadDate.week:
        return yt.UploadDateFilter.lastWeek;
      case SearchUploadDate.month:
        return yt.UploadDateFilter.lastMonth;
      case SearchUploadDate.year:
        return yt.UploadDateFilter.lastYear;
      case SearchUploadDate.any:
        break;
    }
    switch (f.duration) {
      case SearchDuration.short:
        return yt.DurationFilters.short;
      case SearchDuration.long:
        return yt.DurationFilters.long;
      case SearchDuration.any:
        break;
    }
    return switch (f.type) {
      SearchType.videos => yt.TypeFilters.video,
      SearchType.channels => yt.TypeFilters.channel,
      SearchType.playlists => yt.TypeFilters.playlist,
      SearchType.all => const yt.SearchFilter(''),
    };
  }

  List<SearchEntry> _mapSearch(Iterable<yt.SearchResult> list, SearchFilters f) {
    final out = <SearchEntry>[];
    for (final r in list) {
      switch (r) {
        case yt.SearchVideo():
          if (f.type == SearchType.all || f.type == SearchType.videos) {
            final v = _fromSearchVideo(r);
            if (f.duration == SearchDuration.short && (v.duration?.inMinutes ?? 0) >= 4) continue;
            if (f.duration == SearchDuration.long && (v.duration?.inMinutes ?? 0) < 20) continue;
            out.add(SearchVideoEntry(v));
          }
        case yt.SearchChannel():
          if (f.type == SearchType.all || f.type == SearchType.channels) out.add(SearchChannelEntry(_fromSearchChannel(r)));
        case yt.SearchPlaylist():
          if (f.type == SearchType.all || f.type == SearchType.playlists) {
            out.add(SearchPlaylistEntry(_fromSearchPlaylist(r)));
          }
      }
    }
    return out;
  }

  Future<Paged<SearchEntry>> search(String query, [SearchFilters filters = const SearchFilters()]) async {
    final list = await _yt.search.searchContent(query, filter: _filterFor(filters));
    return _searchPage(list, filters);
  }

  Paged<SearchEntry> _searchPage(yt.SearchList list, SearchFilters f) => Paged(
        _mapSearch(list, f),
        () async {
          final next = await list.nextPage();
          return next == null ? null : _searchPage(next, f);
        },
      );

  /// Plain video search used by the home feed / explore shelves.
  Future<Paged<VideoItem>> videoSearch(String query, {yt.SearchFilter? filter}) async {
    final list = await _yt.search.search(query, filter: filter ?? yt.TypeFilters.video);
    return _videoSearchPage(list);
  }

  Paged<VideoItem> _videoSearchPage(yt.VideoSearchList list) {
    list.forEach(_cache);
    return Paged(
      list.map(_fromVideo).toList(),
      () async {
        final next = await list.nextPage();
        return next == null ? null : _videoSearchPage(next);
      },
    );
  }

  // ---------------------------------------------------------------------------------------
  // Videos
  // ---------------------------------------------------------------------------------------
  Future<yt.Video> _video(String id) async {
    final cached = _videoCache[id];
    if (cached != null && cached.description.isNotEmpty) return cached;
    final v = await _yt.videos.get(id);
    _cache(v);
    return v;
  }

  /// Full metadata (description, likes, date).
  Future<VideoItem> video(String id) async => _fromVideo(await _video(id));

  Future<Paged<VideoItem>> related(String id) async {
    final v = await _video(id);
    final list = await _yt.videos.getRelatedVideos(v);
    if (list == null) return Paged.empty();
    return _relatedPage(list);
  }

  Paged<VideoItem> _relatedPage(yt.RelatedVideosList list) {
    list.forEach(_cache);
    return Paged(
      list.map(_fromVideo).toList(),
      () async {
        final next = await list.nextPage();
        return next == null ? null : _relatedPage(next);
      },
    );
  }

  Future<Paged<CommentItem>?> comments(String id) async {
    try {
      final v = await _video(id);
      // The library marks comments as unsupported; it still works for many videos and we
      // fall back to "comments unavailable" when it does not.
      // ignore: deprecated_member_use
      final list = await _yt.videos.commentsClient.getComments(v);
      if (list == null) return null;
      return _commentPage(list);
    } catch (_) {
      return null;
    }
  }

  Paged<CommentItem> _commentPage(yt.CommentsList list) => Paged(
        list
            .map((c) => CommentItem(
                  author: c.author,
                  text: c.text,
                  likeCount: c.likeCount,
                  publishedTime: c.publishedTime,
                  replyCount: c.replyCount,
                  channelId: c.channelId.value,
                  isHearted: c.isHearted,
                ))
            .toList(),
        () async {
          final next = await list.nextPage();
          return next == null ? null : _commentPage(next);
        },
      );

  // ---------------------------------------------------------------------------------------
  // Channels & playlists
  // ---------------------------------------------------------------------------------------
  Future<ChannelItem> channel(String id) async {
    final c = await _yt.channels.get(id);
    return ChannelItem(
      id: c.id.value,
      title: c.title,
      avatarUrl: c.logoUrl.isEmpty ? null : c.logoUrl,
      bannerUrl: c.bannerUrl.isEmpty ? null : c.bannerUrl,
      subscriberCount: c.subscribersCount,
    );
  }

  Future<Paged<VideoItem>> channelUploads(String id, {bool popular = false}) async {
    final list = await _yt.channels.getUploadsFromPage(
      id,
      videoSorting: popular ? yt.VideoSorting.popularity : yt.VideoSorting.newest,
    );
    return _uploadsPage(list);
  }

  Paged<VideoItem> _uploadsPage(yt.ChannelUploadsList list) {
    list.forEach(_cache);
    return Paged(
      list.map(_fromVideo).toList(),
      () async {
        final next = await list.nextPage();
        return next == null ? null : _uploadsPage(next);
      },
    );
  }

  /// YouTube does not expose a channel's playlist tab to this client, so we search for
  /// playlists by the channel name.
  Future<List<PlaylistItem>> channelPlaylists(String channelTitle) async {
    final list = await _yt.search.searchContent(channelTitle, filter: yt.TypeFilters.playlist);
    return list.whereType<yt.SearchPlaylist>().map(_fromSearchPlaylist).toList();
  }

  Future<PlaylistItem> playlist(String id) async {
    final p = await _yt.playlists.get(id);
    return PlaylistItem(
      id: p.id.value,
      title: p.title,
      author: p.author,
      description: p.description,
      videoCount: p.videoCount,
      thumbnailUrl: p.thumbnails.highResUrl,
    );
  }

  Future<List<VideoItem>> playlistVideos(String id, {int limit = 200}) async {
    final out = <VideoItem>[];
    await for (final v in _yt.playlists.getVideos(id).take(limit)) {
      _cache(v);
      out.add(_fromVideo(v));
    }
    return out;
  }

  // ---------------------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------------------
  /// Resolves playable URLs. Cached until they go stale; [refresh] forces a new manifest
  /// (used when the player reports an expired / 403 URL).
  Future<ResolvedStreams> resolve(String id, {bool refresh = false}) {
    if (!refresh) {
      final c = _streamCache[id];
      if (c != null && !c.isStale) return Future.value(c);
      final f = _inflight[id];
      if (f != null) return f;
    }
    final fut = _resolve(id).whenComplete(() => _inflight.remove(id));
    _inflight[id] = fut;
    return fut;
  }

  Future<ResolvedStreams> _resolve(String id) async {
    final manifest = await _yt.videos.streamsClient.getManifest(id);
    final ios = Platform.isIOS;

    // Audio: iOS needs MP4/AAC (AVPlayer has no WebM/Opus); Android takes the best one.
    final audios = manifest.audioOnly.toList();
    yt.AudioOnlyStreamInfo? audio;
    final mp4Audio = audios.where((a) => a.container == yt.StreamContainer.mp4).toList();
    if (ios) {
      if (mp4Audio.isNotEmpty) audio = mp4Audio.withHighestBitrate();
    } else if (audios.isNotEmpty) {
      audio = audios.withHighestBitrate();
    }

    final muxed = manifest.muxed.where((m) => m.container == yt.StreamContainer.mp4).toList()
      ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
    final muxedUrl = muxed.isEmpty ? null : muxed.first.url.toString();

    // Video-only choices: H.264 in MP4 plays everywhere with hardware decoding.
    final byHeight = <int, yt.VideoOnlyStreamInfo>{};
    for (final v in manifest.videoOnly) {
      final avc = v.container == yt.StreamContainer.mp4 && v.codec.toString().contains('avc1');
      if (!avc && ios) continue;
      final h = v.videoResolution.height;
      if (h > 1080 || h <= 0) continue;
      final prev = byHeight[h];
      final prevAvc = prev != null && prev.codec.toString().contains('avc1');
      if (prev == null || (avc && !prevAvc) || (avc == prevAvc && v.bitrate.compareTo(prev.bitrate) > 0)) {
        byHeight[h] = v;
      }
    }
    final choices = byHeight.entries
        .map((e) => StreamChoice(
              label: '${e.key}p',
              height: e.key,
              url: e.value.url.toString(),
              muxed: false,
            ))
        .toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    for (final m in muxed) {
      if (!choices.any((c) => c.height == m.videoResolution.height)) {
        choices.add(StreamChoice(
          label: '${m.videoResolution.height}p',
          height: m.videoResolution.height,
          url: m.url.toString(),
          muxed: true,
        ));
      }
    }
    choices.sort((a, b) => b.height.compareTo(a.height));

    final audioUrl = audio?.url.toString() ?? muxedUrl;
    if (audioUrl == null) {
      throw StateError('No playable stream for $id');
    }
    final r = ResolvedStreams(
      audioUrl: audioUrl,
      headers: const {'User-Agent': androidClientUa},
      videoChoices: choices,
      muxedUrl: muxedUrl,
      resolvedAt: DateTime.now(),
      audioBitrateKbps: audio == null ? null : (audio.bitrate.bitsPerSecond / 1000).round(),
      audioCodec: audio?.audioCodec,
    );
    _streamCache[id] = r;
    return r;
  }

  /// Byte stream of a URL with the headers YouTube expects (for downloads).
  Future<(Stream<List<int>>, int?)> openStream(String url, Map<String, String> headers, {int start = 0}) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    if (start > 0) req.headers.set('Range', 'bytes=$start-');
    final res = await req.close();
    if (res.statusCode >= 400) {
      client.close(force: true);
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final len = res.contentLength >= 0 ? res.contentLength + start : null;
    final controller = StreamController<List<int>>();
    res.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        controller.close();
        client.close();
      },
      cancelOnError: true,
    );
    controller.onCancel = () => client.close(force: true);
    return (controller.stream, len);
  }
}
