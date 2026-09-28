import 'dart:convert';

import 'package:http/http.dart' as http;

part 'innertube_search.dart';

/// Direct InnerTube `/player` client used to resolve stream URLs.
///
/// Since 2026 YouTube answers anonymous player requests without a visitor id with
/// "Sign in to confirm you're not a bot" (LOGIN_REQUIRED) for most music videos. Sending the
/// `visitorData` a browser gets from youtube.com (context + X-Goog-Visitor-Id header) makes
/// the ANDROID / ANDROID_VR / IOS clients return direct, unciphered stream URLs again.
class InnertubePlayer {
  InnertubePlayer([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;
  String? _visitorData;
  DateTime? _visitorAt;

  static const _webUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36';

  static const clients = <String, Map<String, Object>>{
    'IOS': {
      'clientName': 'IOS',
      'clientVersion': '20.10.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
      'hl': 'en',
      'userAgent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    },
    'ANDROID_VR': {
      'clientName': 'ANDROID_VR',
      'clientVersion': '1.65.10',
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'osName': 'Android',
      'osVersion': '12L',
      'hl': 'en',
      'userAgent':
          'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    },
    'ANDROID': {
      'clientName': 'ANDROID',
      'clientVersion': '20.10.38',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
      'osName': 'Android',
      'osVersion': '11',
      'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    },
  };

  void close() => _http.close();

  /// Visitor id of an anonymous browser session (cached for 6 hours).
  Future<String?> visitorData({bool refresh = false}) async {
    if (!refresh && _visitorData != null && DateTime.now().difference(_visitorAt!) < const Duration(hours: 6)) {
      return _visitorData;
    }
    try {
      final r = await _http
          .get(Uri.parse('https://www.youtube.com/sw.js_data'), headers: {'user-agent': _webUa})
          .timeout(const Duration(seconds: 15));
      var body = r.body;
      if (body.startsWith(")]}'")) body = body.substring(4);
      String? v;
      try {
        final j = jsonDecode(body);
        final candidate = j[0][2][0][0][13];
        if (candidate is String && candidate.isNotEmpty) v = candidate;
      } catch (_) {}
      v ??= RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(body)?.group(1);
      if (v == null) {
        final page = await _http
            .get(Uri.parse('https://www.youtube.com/?hl=en'), headers: {'user-agent': _webUa})
            .timeout(const Duration(seconds: 15));
        v = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(page.body)?.group(1);
      }
      if (v != null) {
        _visitorData = v;
        _visitorAt = DateTime.now();
      }
      return v;
    } catch (_) {
      return _visitorData;
    }
  }

  /// Calls `/player` with [clientName]. Returns the decoded response when playable.
  Future<PlayerResponse> player(String videoId, String clientName) async {
    final client = clients[clientName]!;
    final ua = client['userAgent']! as String;
    for (var attempt = 0; attempt < 2; attempt++) {
      final vd = await visitorData(refresh: attempt > 0);
      final r = await _http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
            headers: {
              'content-type': 'application/json',
              'user-agent': ua,
              'x-goog-visitor-id': ?vd,
            },
            body: jsonEncode({
              'context': {
                'client': {...client, 'visitorData': ?vd},
              },
              'videoId': videoId,
              'contentCheckOk': true,
              'racyCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final ps = (j['playabilityStatus'] as Map?)?.cast<String, dynamic>() ?? const {};
      final status = ps['status'] as String? ?? 'ERROR';
      if (status == 'OK') return PlayerResponse(j, ua, clientName);
      // A stale visitor id also yields LOGIN_REQUIRED: refresh it once.
      if (status == 'LOGIN_REQUIRED' && attempt == 0) continue;
      throw PlayabilityException(status, ps['reason'] as String? ?? status);
    }
    throw const PlayabilityException('LOGIN_REQUIRED', 'Sign in to confirm you are not a bot');
  }
}

class PlayabilityException implements Exception {
  const PlayabilityException(this.status, this.reason);
  final String status;
  final String reason;
  @override
  String toString() => 'YouTube: $reason ($status)';
}

/// One entry of `streamingData.formats` / `adaptiveFormats`.
class InnertubeFormat {
  InnertubeFormat(Map<String, dynamic> j)
      : itag = (j['itag'] as num?)?.toInt() ?? 0,
        url = j['url'] as String?,
        mimeType = j['mimeType'] as String? ?? '',
        bitrate = (j['bitrate'] as num?)?.toInt() ?? 0,
        width = (j['width'] as num?)?.toInt() ?? 0,
        height = (j['height'] as num?)?.toInt() ?? 0,
        contentLength = int.tryParse('${j['contentLength'] ?? ''}');

  final int itag;
  final String? url;
  final String mimeType;
  final int bitrate;
  final int width, height;
  final int? contentLength;

  bool get isAudio => mimeType.startsWith('audio/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isMp4 => mimeType.contains('/mp4');
  bool get isAvc => mimeType.contains('avc1');
  String get codec => RegExp(r'codecs="([^"]+)"').firstMatch(mimeType)?.group(1) ?? '';
}

class PlayerResponse {
  PlayerResponse(this.json, this.userAgent, this.client);
  final Map<String, dynamic> json;
  final String userAgent;
  final String client;

  Map<String, dynamic> get _streaming => (json['streamingData'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<InnertubeFormat> get adaptive => ((_streaming['adaptiveFormats'] as List?) ?? const [])
      .map((e) => InnertubeFormat((e as Map).cast<String, dynamic>()))
      .where((f) => f.url != null)
      .toList();

  List<InnertubeFormat> get muxed => ((_streaming['formats'] as List?) ?? const [])
      .map((e) => InnertubeFormat((e as Map).cast<String, dynamic>()))
      .where((f) => f.url != null)
      .toList();

  String? get hlsUrl => _streaming['hlsManifestUrl'] as String?;
}

/// A related video parsed from the WEB `/next` response.
class RelatedEntry {
  const RelatedEntry({
    required this.id,
    required this.title,
    required this.channel,
    this.channelId,
    this.duration,
    this.viewCount,
    this.published,
  });
  final String id, title, channel;
  final String? channelId;
  final Duration? duration;
  final int? viewCount;
  final String? published;
}

extension InnertubeNext on InnertubePlayer {
  static const _webVersion = '2.20250925.01.00';

  /// "Up next" videos from the WEB `/next` endpoint (the watch-page scraper of
  /// youtube_explode hits the bot wall; `/next` with a visitor id does not).
  Future<List<RelatedEntry>> related(String videoId) async {
    final vd = await visitorData();
    final r = await _http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
          headers: {
            'content-type': 'application/json',
            'user-agent': InnertubePlayer._webUa,
            'x-goog-visitor-id': ?vd,
          },
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': _webVersion, 'hl': 'en', 'visitorData': ?vd},
            },
            'videoId': videoId,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final j = jsonDecode(r.body);
    final out = <RelatedEntry>[];
    final seen = <String>{videoId};
    for (final l in _find(j, 'lockupViewModel')) {
      if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') continue;
      final id = l['contentId'] as String?;
      if (id == null || !seen.add(id)) continue;
      final meta = (l['metadata'] as Map?)?['lockupMetadataViewModel'] as Map?;
      final title = ((meta?['title'] as Map?)?['content'] as String?) ?? '';
      final rows = (((meta?['metadata'] as Map?)?['contentMetadataViewModel'] as Map?)?['metadataRows'] as List?) ?? const [];
      String? part(int row, int i) {
        if (row >= rows.length) return null;
        final parts = ((rows[row] as Map)['metadataParts'] as List?) ?? const [];
        if (i >= parts.length) return null;
        return ((parts[i] as Map)['text'] as Map?)?['content'] as String?;
      }

      final badge = _find(l['contentImage'], 'thumbnailBadgeViewModel').map((b) => b['text']).whereType<String>();
      final browse = _find(meta, 'browseEndpoint').map((b) => b['browseId']).whereType<String>();
      out.add(RelatedEntry(
        id: id,
        title: title,
        channel: part(0, 0) ?? '',
        channelId: browse.isEmpty ? null : browse.first,
        duration: badge.isEmpty ? null : _parseDuration(badge.first),
        viewCount: _parseCompact(part(1, 0)),
        published: part(1, 1),
      ));
    }
    // Older layout.
    for (final c in _find(j, 'compactVideoRenderer')) {
      final id = c['videoId'] as String?;
      if (id == null || !seen.add(id)) continue;
      String? text(Object? t) => t is Map ? (t['simpleText'] as String? ?? ((t['runs'] as List?)?.map((e) => (e as Map)['text']).join())) : null;
      out.add(RelatedEntry(
        id: id,
        title: text(c['title']) ?? '',
        channel: text(c['longBylineText']) ?? '',
        duration: _parseDuration(text(c['lengthText'])),
        viewCount: _parseCompact(text(c['shortViewCountText'])),
        published: text(c['publishedTimeText']),
      ));
    }
    return out;
  }

  static Iterable<Map<String, dynamic>> _find(Object? n, String key) sync* {
    if (n is Map) {
      final v = n[key];
      if (v is Map) yield v.cast<String, dynamic>();
      for (final x in n.values) {
        yield* _find(x, key);
      }
    } else if (n is List) {
      for (final x in n) {
        yield* _find(x, key);
      }
    }
  }

  static Duration? _parseDuration(String? s) {
    if (s == null || !RegExp(r'^\d+(:\d+){1,2}$').hasMatch(s.trim())) return null;
    var secs = 0;
    for (final p in s.trim().split(':')) {
      secs = secs * 60 + int.parse(p);
    }
    return Duration(seconds: secs);
  }

  /// "37M" / "1.2K views" / "845 views" -> number.
  static int? _parseCompact(String? s) {
    if (s == null) return null;
    final m = RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false).firstMatch(s);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (n == null) return null;
    final mult = switch (m.group(2)?.toUpperCase()) { 'K' => 1e3, 'M' => 1e6, 'B' => 1e9, _ => 1.0 };
    return (n * mult).round();
  }
}
