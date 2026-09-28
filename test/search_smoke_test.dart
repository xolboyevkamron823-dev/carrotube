// ignore_for_file: avoid_print
// Live-network test of search (run manually): flutter test test/search_smoke_test.dart
@Tags(['network'])
library;

import 'dart:io';

import 'package:carrotube/data/feed.dart';
import 'package:carrotube/data/models.dart';
import 'package:carrotube/data/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('every home feed category + trending + paging', () async {
    final yt = YoutubeService();
    final queries = [
      'trending',
      for (final c in FeedCategory.values)
        if (c.query != null) c.query!,
    ];
    var failures = 0;
    for (final q in queries) {
      try {
        final p = await yt.videoSearch(q);
        final next = await p.next();
        print('OK   "$q" ${p.items.length} videos, page2 ${next?.items.length ?? 0}, '
            'first: ${p.items.first.title} | ${p.items.first.channelName} | ${p.items.first.duration} | ${p.items.first.viewCount}');
      } catch (e) {
        failures++;
        print('FAIL "$q" $e');
      }
    }
    yt.close();
    expect(failures, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('mixed search + filters', () async {
    final yt = YoutubeService();
    for (final f in const [
      SearchFilters(),
      SearchFilters(type: SearchType.channels),
      SearchFilters(type: SearchType.playlists),
      SearchFilters(uploadDate: SearchUploadDate.week),
      SearchFilters(duration: SearchDuration.long),
    ]) {
      final p = await yt.search('munisa rizayeva', f);
      final kinds = p.items.map((e) => e.runtimeType.toString().replaceAll('Search', '').replaceAll('Entry', '')).toSet();
      final first = p.items.isEmpty ? '-' : switch (p.items.first) {
        SearchVideoEntry(:final video) => video.title,
        SearchChannelEntry(:final channel) => '${channel.title} subs=${channel.subscriberCount} avatar=${channel.avatarUrl != null}',
        SearchPlaylistEntry(:final playlist) => '${playlist.title} n=${playlist.videoCount} thumb=${playlist.thumbnailUrl != null}',
      };
      print('${f.type.name}/${f.uploadDate.name}/${f.duration.name}: ${p.items.length} $kinds first: $first');
      expect(p.items, isNotEmpty);
    }
    yt.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
