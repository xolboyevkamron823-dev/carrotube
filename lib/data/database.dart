import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Opened once in main() and injected via [appDatabaseProvider] override.
final appDatabaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override in main'));

/// SQLite storage for everything the user owns locally: history, likes, playlists,
/// subscriptions, search history, downloads and key/value settings.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'carrotube.db'),
      version: 1,
      onCreate: (db, v) async {
        final b = db.batch();
        b.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, json TEXT NOT NULL)');
        b.execute('CREATE TABLE history (video_id TEXT PRIMARY KEY, watched_at INTEGER NOT NULL, position_ms INTEGER DEFAULT 0)');
        b.execute('CREATE TABLE liked (video_id TEXT PRIMARY KEY, liked_at INTEGER NOT NULL)');
        b.execute('CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created INTEGER NOT NULL)');
        b.execute('CREATE TABLE playlist_items (playlist_id INTEGER NOT NULL, video_id TEXT NOT NULL, pos INTEGER NOT NULL, '
            'PRIMARY KEY (playlist_id, video_id))');
        b.execute('CREATE TABLE subscriptions (channel_id TEXT PRIMARY KEY, json TEXT NOT NULL, subscribed_at INTEGER NOT NULL)');
        b.execute('CREATE TABLE search_history (query TEXT PRIMARY KEY, at INTEGER NOT NULL)');
        b.execute('CREATE TABLE downloads (video_id TEXT PRIMARY KEY, audio_only INTEGER NOT NULL, status TEXT NOT NULL, '
            'file_path TEXT, video_file_path TEXT, size_bytes INTEGER DEFAULT 0, created INTEGER NOT NULL, error TEXT)');
        b.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        await b.commit(noResult: true);
      },
    );
    return AppDatabase._(db);
  }

  // ---- videos (metadata cache for local lists) ----
  Future<void> putVideo(VideoItem v) =>
      _db.insert('videos', {'id': v.id, 'json': jsonEncode(v.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<VideoItem>> _videosJoin(String sql, [List<Object?> args = const []]) async {
    final rows = await _db.rawQuery(sql, args);
    return rows
        .where((r) => r['json'] != null)
        .map((r) => VideoItem.fromJson((jsonDecode(r['json']! as String) as Map).cast<String, Object?>()))
        .toList();
  }

  // ---- history ----
  Future<void> addHistory(VideoItem v, {Duration position = Duration.zero}) async {
    await putVideo(v);
    await _db.insert(
      'history',
      {'video_id': v.id, 'watched_at': DateTime.now().millisecondsSinceEpoch, 'position_ms': position.inMilliseconds},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> savePosition(String id, Duration position) =>
      _db.update('history', {'position_ms': position.inMilliseconds}, where: 'video_id = ?', whereArgs: [id]);

  Future<Duration> positionOf(String id) async {
    final r = await _db.query('history', columns: ['position_ms'], where: 'video_id = ?', whereArgs: [id]);
    if (r.isEmpty) return Duration.zero;
    return Duration(milliseconds: (r.first['position_ms'] as int?) ?? 0);
  }

  Future<List<VideoItem>> history({int limit = 500}) => _videosJoin(
      'SELECT v.json FROM history h JOIN videos v ON v.id = h.video_id ORDER BY h.watched_at DESC LIMIT ?', [limit]);

  Future<void> removeHistory(String id) => _db.delete('history', where: 'video_id = ?', whereArgs: [id]);
  Future<void> clearHistory() => _db.delete('history');

  // ---- likes ----
  Future<bool> isLiked(String id) async =>
      (await _db.query('liked', where: 'video_id = ?', whereArgs: [id])).isNotEmpty;

  Future<void> setLiked(VideoItem v, bool liked) async {
    if (liked) {
      await putVideo(v);
      await _db.insert('liked', {'video_id': v.id, 'liked_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _db.delete('liked', where: 'video_id = ?', whereArgs: [v.id]);
    }
  }

  Future<List<VideoItem>> liked() =>
      _videosJoin('SELECT v.json FROM liked l JOIN videos v ON v.id = l.video_id ORDER BY l.liked_at DESC');

  // ---- playlists ----
  Future<int> createPlaylist(String name) =>
      _db.insert('playlists', {'name': name, 'created': DateTime.now().millisecondsSinceEpoch});

  Future<void> renamePlaylist(int id, String name) =>
      _db.update('playlists', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deletePlaylist(int id) async {
    await _db.delete('playlist_items', where: 'playlist_id = ?', whereArgs: [id]);
    await _db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LocalPlaylist>> playlists() async {
    final rows = await _db.rawQuery('''
      SELECT p.id, p.name, p.created, COUNT(i.video_id) AS cnt,
             (SELECT video_id FROM playlist_items WHERE playlist_id = p.id ORDER BY pos LIMIT 1) AS cover
      FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
      GROUP BY p.id ORDER BY p.created DESC''');
    return rows
        .map((r) => LocalPlaylist(
              id: r['id']! as int,
              name: r['name']! as String,
              created: DateTime.fromMillisecondsSinceEpoch(r['created']! as int),
              count: (r['cnt'] as int?) ?? 0,
              cover: r['cover'] == null ? null : 'https://i.ytimg.com/vi/${r['cover']}/hqdefault.jpg',
            ))
        .toList();
  }

  Future<void> addToPlaylist(int playlistId, VideoItem v) async {
    await putVideo(v);
    final r = await _db.rawQuery('SELECT COALESCE(MAX(pos), -1) + 1 AS n FROM playlist_items WHERE playlist_id = ?',
        [playlistId]);
    await _db.insert('playlist_items', {'playlist_id': playlistId, 'video_id': v.id, 'pos': r.first['n']},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFromPlaylist(int playlistId, String videoId) =>
      _db.delete('playlist_items', where: 'playlist_id = ? AND video_id = ?', whereArgs: [playlistId, videoId]);

  Future<void> reorderPlaylist(int playlistId, List<String> orderedIds) async {
    final b = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      b.update('playlist_items', {'pos': i},
          where: 'playlist_id = ? AND video_id = ?', whereArgs: [playlistId, orderedIds[i]]);
    }
    await b.commit(noResult: true);
  }

  Future<List<VideoItem>> playlistVideos(int playlistId) => _videosJoin(
      'SELECT v.json FROM playlist_items i JOIN videos v ON v.id = i.video_id WHERE i.playlist_id = ? ORDER BY i.pos',
      [playlistId]);

  // ---- subscriptions ----
  Future<bool> isSubscribed(String channelId) async =>
      (await _db.query('subscriptions', where: 'channel_id = ?', whereArgs: [channelId])).isNotEmpty;

  Future<void> setSubscribed(ChannelItem c, bool on) async {
    if (on) {
      await _db.insert(
        'subscriptions',
        {'channel_id': c.id, 'json': jsonEncode(c.toJson()), 'subscribed_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await _db.delete('subscriptions', where: 'channel_id = ?', whereArgs: [c.id]);
    }
  }

  Future<List<ChannelItem>> subscriptions() async {
    final rows = await _db.query('subscriptions', orderBy: 'subscribed_at DESC');
    return rows
        .map((r) => ChannelItem.fromJson((jsonDecode(r['json']! as String) as Map).cast<String, Object?>()))
        .toList();
  }

  // ---- search history ----
  Future<void> addSearch(String q) => _db.insert('search_history', {'query': q, 'at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<String>> searchHistory({int limit = 30}) async =>
      (await _db.query('search_history', orderBy: 'at DESC', limit: limit)).map((r) => r['query']! as String).toList();

  Future<void> removeSearch(String q) => _db.delete('search_history', where: 'query = ?', whereArgs: [q]);
  Future<void> clearSearchHistory() => _db.delete('search_history');

  // ---- downloads ----
  Future<void> upsertDownload(DownloadItem d) async {
    await putVideo(d.video);
    await _db.insert(
      'downloads',
      {
        'video_id': d.video.id,
        'audio_only': d.audioOnly ? 1 : 0,
        'status': d.status.name,
        'file_path': d.filePath,
        'video_file_path': d.videoFilePath,
        'size_bytes': d.sizeBytes,
        'created': d.createdAt.millisecondsSinceEpoch,
        'error': d.error,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDownload(String id) => _db.delete('downloads', where: 'video_id = ?', whereArgs: [id]);

  Future<List<DownloadItem>> downloads() async {
    final rows = await _db.rawQuery(
        'SELECT d.*, v.json FROM downloads d JOIN videos v ON v.id = d.video_id ORDER BY d.created DESC');
    return rows.map((r) {
      final status = DownloadStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => DownloadStatus.failed);
      return DownloadItem(
        video: VideoItem.fromJson((jsonDecode(r['json']! as String) as Map).cast<String, Object?>()),
        audioOnly: r['audio_only'] == 1,
        // A download that was running when the app died is resumed as queued.
        status: status == DownloadStatus.running ? DownloadStatus.queued : status,
        filePath: r['file_path'] as String?,
        videoFilePath: r['video_file_path'] as String?,
        sizeBytes: (r['size_bytes'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created']! as int),
        error: r['error'] as String?,
      );
    }).toList();
  }

  // ---- key/value ----
  Future<String?> getString(String k) async {
    final r = await _db.query('kv', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  Future<void> setString(String k, String v) =>
      _db.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, String>> allStrings() async {
    final rows = await _db.query('kv');
    return {for (final r in rows) r['k']! as String: r['v']! as String};
  }
}
