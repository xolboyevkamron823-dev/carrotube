part of 'innertube.dart';

// Search through the WEB /search JSON API. youtube_explode's HTML scraper breaks on new
// layouts ("Streamed" dates, missing text fields) and trips Google's abuse redirect; the JSON
// API with a visitor id is stable and much lighter.

sealed class ItResult {
  const ItResult();
}

class ItVideo extends ItResult {
  const ItVideo(this.entry, {this.isLive = false});
  final RelatedEntry entry;
  final bool isLive;
}

class ItChannel extends ItResult {
  const ItChannel({required this.id, required this.title, this.avatarUrl, this.subscribers, this.handle});
  final String id, title;
  final String? avatarUrl;
  final int? subscribers;
  final String? handle;
}

class ItPlaylist extends ItResult {
  const ItPlaylist({required this.id, required this.title, this.author, this.thumbnailUrl, this.videoCount});
  final String id, title;
  final String? author, thumbnailUrl;
  final int? videoCount;
}

class ItSearchPage {
  const ItSearchPage(this.results, this.continuation);
  final List<ItResult> results;
  final String? continuation;
}

String? _itText(Object? t) {
  if (t is! Map) return null;
  if (t['simpleText'] is String) return t['simpleText'] as String;
  if (t['content'] is String) return t['content'] as String;
  final runs = t['runs'];
  if (runs is List) return runs.map((e) => (e as Map)['text'] ?? '').join();
  return null;
}

String? _https(String? u) => u == null ? null : (u.startsWith('//') ? 'https:$u' : u);

extension InnertubeSearch on InnertubePlayer {
  Future<ItSearchPage> search(String query, {String? params, String? continuation}) async {
    final vd = await visitorData();
    final r = await _http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
          headers: {
            'content-type': 'application/json',
            'user-agent': InnertubePlayer._webUa,
            'x-goog-visitor-id': ?vd,
          },
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': InnertubeNext._webVersion, 'hl': 'en', 'visitorData': ?vd},
            },
            if (continuation != null) 'continuation': continuation else 'query': query,
            if (continuation == null && params != null && params.isNotEmpty) 'params': params,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw http.ClientException('Search HTTP ${r.statusCode}');
    final results = <ItResult>[];
    final seen = <String>{};
    String? token;

    void visit(Object? n) {
      if (n is List) {
        for (final x in n) {
          visit(x);
        }
        return;
      }
      if (n is! Map) return;
      if (n['reelShelfRenderer'] != null || n['shortsLockupViewModel'] != null) return; // Shorts
      final v = n['videoRenderer'];
      if (v is Map) {
        _addVideo(v, results, seen);
        return;
      }
      final c = n['channelRenderer'];
      if (c is Map) {
        _addChannel(c, results, seen);
        return;
      }
      final l = n['lockupViewModel'];
      if (l is Map) {
        _addLockup(l, results, seen);
        return;
      }
      final cc = n['continuationCommand'];
      if (cc is Map && cc['token'] is String) token ??= cc['token'] as String;
      for (final x in n.values) {
        visit(x);
      }
    }

    visit(jsonDecode(r.body));
    return ItSearchPage(results, token);
  }

  static void _addVideo(Map v, List<ItResult> out, Set<String> seen) {
    final id = v['videoId'] as String?;
    if (id == null || !seen.add(id)) return;
    final owner = (v['ownerText'] as Map?)?['runs'] as List?;
    final ownerRun = owner != null && owner.isNotEmpty ? owner.first as Map : null;
    final badges = jsonEncode(v['badges'] ?? const []);
    out.add(ItVideo(
      RelatedEntry(
        id: id,
        title: _itText(v['title']) ?? '',
        channel: (ownerRun?['text'] as String?) ?? '',
        channelId: ((ownerRun?['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?,
        duration: InnertubeNext._parseDuration(_itText(v['lengthText'])),
        viewCount: InnertubeNext._parseCompact(_itText(v['viewCountText'])),
        published: _itText(v['publishedTimeText']),
      ),
      isLive: badges.contains('LIVE') && v['lengthText'] == null,
    ));
  }

  static void _addChannel(Map c, List<ItResult> out, Set<String> seen) {
    final id = c['channelId'] as String?;
    if (id == null || !seen.add(id)) return;
    final thumbs = ((c['thumbnail'] as Map?)?['thumbnails'] as List?) ?? const [];
    // New layout: subscriber count sits in videoCountText, the @handle in subscriberCountText.
    final texts = [_itText(c['videoCountText']), _itText(c['subscriberCountText'])].whereType<String>();
    final subs = texts.where((s) => s.contains('subscriber'));
    final handle = texts.where((s) => s.startsWith('@'));
    out.add(ItChannel(
      id: id,
      title: _itText(c['title']) ?? '',
      avatarUrl: thumbs.isEmpty ? null : _https((thumbs.last as Map)['url'] as String?),
      subscribers: subs.isEmpty ? null : InnertubeNext._parseCompact(subs.first),
      handle: handle.isEmpty ? null : handle.first,
    ));
  }

  static void _addLockup(Map l, List<ItResult> out, Set<String> seen) {
    final id = l['contentId'] as String?;
    if (id == null || !seen.add(id)) return;
    final meta = (l['metadata'] as Map?)?['lockupMetadataViewModel'] as Map?;
    final title = _itText(meta?['title']) ?? '';
    final rows = (((meta?['metadata'] as Map?)?['contentMetadataViewModel'] as Map?)?['metadataRows'] as List?) ?? const [];
    String? part(int row, int i) {
      if (row >= rows.length) return null;
      final parts = ((rows[row] as Map)['metadataParts'] as List?) ?? const [];
      return i < parts.length ? _itText((parts[i] as Map)['text']) : null;
    }

    final badge = InnertubeNext._find(l['contentImage'], 'thumbnailBadgeViewModel')
        .map((b) => b['text'])
        .whereType<String>()
        .toList();
    if (l['contentType'] == 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
      final sources = InnertubeNext._find(l['contentImage'], 'image')
          .map((i) => i['sources'])
          .whereType<List>()
          .where((s) => s.isNotEmpty)
          .toList();
      out.add(ItPlaylist(
        id: id,
        title: title,
        author: part(0, 0),
        thumbnailUrl: sources.isEmpty ? null : _https((sources.first.last as Map)['url'] as String?),
        videoCount: badge.isEmpty ? null : InnertubeNext._parseCompact(badge.first),
      ));
    } else if (l['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
      out.add(ItVideo(RelatedEntry(
        id: id,
        title: title,
        channel: part(0, 0) ?? '',
        duration: badge.isEmpty ? null : InnertubeNext._parseDuration(badge.first),
        viewCount: InnertubeNext._parseCompact(part(1, 0)),
        published: part(1, 1),
      )));
    }
  }
}
