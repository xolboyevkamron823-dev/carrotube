// ignore_for_file: avoid_print
// Live-network smoke test of the app's own data layer (run manually, not in CI):
//   flutter test test/network_smoke_test.dart
@Tags(['network'])
library;

import 'dart:io';

import 'package:carrotube/data/innertube.dart';
import 'package:carrotube/data/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  setUpAll(() => HttpOverrides.global = null); // allow real network in tests

  test('resolve music videos (bot-check workaround) + playable URLs', () async {
    final yt = YoutubeService();
    print('searching');
    final list = await yt.videoSearch('uzbek music 2026');
    print('search done ${list.items.length}');
    var ok = 0;
    for (final v in list.items.take(6)) {
      final sw = Stopwatch()..start();
      try {
        final r = await yt.resolve(v.id).timeout(const Duration(seconds: 30));
        print('resolved ${v.id} in ${sw.elapsedMilliseconds}ms');
        final res = await http.get(Uri.parse(r.audioUrl), headers: {...r.headers, 'Range': 'bytes=0-1023'}).timeout(const Duration(seconds: 20));
        print('OK   ${v.id} ${sw.elapsedMilliseconds}ms audio=${res.statusCode} ${r.audioCodec} '
            'qualities=${r.videoChoices.map((c) => c.label).join(',')}');
        if (res.statusCode == 206 || res.statusCode == 200) ok++;
      } catch (e) {
        print('FAIL ${v.id} ${sw.elapsedMilliseconds}ms $e');
      }
    }
    // iOS client path (what the iPhone build uses first)
    final it = InnertubePlayer();
    final p = await it.player(list.items.first.id, 'IOS');
    final a = p.adaptive.where((f) => f.isAudio && f.isMp4).first;
    final res = await http.get(Uri.parse(a.url!), headers: {'User-Agent': p.userAgent, 'Range': 'bytes=0-1023'});
    print('IOS client: audio ${a.mimeType} -> ${res.statusCode}, avc video heights '
        '${p.adaptive.where((f) => f.isVideo && f.isAvc).map((f) => f.height).toSet()}');
    it.close();
    yt.close();
    expect(ok, greaterThanOrEqualTo(5));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('metadata and related', () async {
    final yt = YoutubeService();
    final list = await yt.videoSearch('uzbek music 2026');
    final id = list.items.first.id;
    try {
      final v = await yt.video(id);
      print('video(): ${v.title} views=${v.viewCount}');
    } catch (e) {
      print('video() FAIL: $e');
    }
    try {
      final r = await yt.related(id);
      print('related(): ${r.items.length}');
    } catch (e) {
      print('related() FAIL: $e');
    }
    yt.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
