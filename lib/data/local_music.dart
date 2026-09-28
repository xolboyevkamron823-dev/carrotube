import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// "My music": audio files on the device (imported from Files / AirDrop / Telegram, or
/// dropped into the app's folder in the Files app). They play through the native player,
/// so the whole Carrozzeria DSP chain applies and playback continues in the background.
abstract final class LocalMusic {
  static const idPrefix = 'local:';
  static const extensions = ['mp3', 'm4a', 'aac', 'flac', 'wav', 'aiff', 'aif', 'caf', 'ogg', 'opus', 'mp4'];

  static String? _dir;

  static bool isLocalId(String id) => id.startsWith(idPrefix);

  static Future<Directory> dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'music'));
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d.path;
    return d;
  }

  /// Absolute path of a local track id (null if the file is gone).
  static String? pathFor(String id) {
    if (!isLocalId(id) || _dir == null) return null;
    final f = File(p.join(_dir!, id.substring(idPrefix.length)));
    return f.existsSync() ? f.path : null;
  }

  static bool _isAudio(String path) => extensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());

  static VideoItem itemFor(File f) {
    final name = p.basename(f.path);
    var title = p.basenameWithoutExtension(name).replaceAll('_', ' ').trim();
    var artist = '';
    // "Artist - Title" file names are common.
    final dash = title.indexOf(' - ');
    if (dash > 0) {
      artist = title.substring(0, dash).trim();
      title = title.substring(dash + 3).trim();
    }
    return VideoItem(
      id: '$idPrefix$name',
      title: title.isEmpty ? name : title,
      channelName: artist,
      uploadDate: f.statSync().modified,
      thumbnail: '',
    );
  }

  /// Lists the music folder. Audio files the user put in the app's Documents root via the
  /// Files app are moved into it first.
  static Future<List<VideoItem>> list() async {
    final d = await dir();
    final root = d.parent;
    for (final e in root.listSync().whereType<File>()) {
      if (!_isAudio(e.path)) continue;
      try {
        await e.rename(p.join(d.path, p.basename(e.path)));
      } catch (_) {}
    }
    final files = d.listSync().whereType<File>().where((f) => _isAudio(f.path)).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files.map(itemFor).toList();
  }

  /// Copies picked files into the music folder. Returns how many were added.
  static Future<int> import(Iterable<String> paths) async {
    final d = await dir();
    var n = 0;
    for (final src in paths) {
      if (!_isAudio(src)) continue;
      var dest = p.join(d.path, p.basename(src));
      var i = 1;
      while (File(dest).existsSync()) {
        dest = p.join(d.path, '${p.basenameWithoutExtension(src)} ($i)${p.extension(src)}');
        i++;
      }
      try {
        await File(src).copy(dest);
        n++;
      } catch (_) {}
    }
    return n;
  }

  static Future<void> delete(String id) async {
    final path = pathFor(id);
    if (path != null) await File(path).delete();
  }
}

final localMusicProvider = FutureProvider<List<VideoItem>>((ref) => LocalMusic.list());
