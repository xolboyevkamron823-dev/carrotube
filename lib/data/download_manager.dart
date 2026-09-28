import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'models.dart';
import 'settings.dart';
import 'youtube_service.dart';

final downloadManagerProvider =
    NotifierProvider<DownloadManager, Map<String, DownloadItem>>(DownloadManager.new);

/// Offline downloads with a sequential queue, progress, resume (HTTP Range) and automatic
/// URL refresh when YouTube rejects an expired link.
///
/// Audio is always stored as its own file; video downloads add a video-only (or muxed) file.
/// The native player plays the pair through the DSP exactly like a stream.
class DownloadManager extends Notifier<Map<String, DownloadItem>> {
  final _cancel = <String>{};
  bool _running = false;

  @override
  Map<String, DownloadItem> build() {
    Future.microtask(_restore);
    return const {};
  }

  AppDatabase get _db => ref.read(appDatabaseProvider);
  YoutubeService get _yt => ref.read(youtubeServiceProvider);

  Future<void> _restore() async {
    final list = await _db.downloads();
    state = {for (final d in list) d.video.id: d};
    _pump();
  }

  static Future<Directory> downloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  bool isDownloaded(String id) => state[id]?.status == DownloadStatus.done;

  Future<void> enqueue(VideoItem v, {required bool audioOnly}) async {
    final existing = state[v.id];
    if (existing != null && existing.status == DownloadStatus.done && (existing.audioOnly || !audioOnly)) return;
    final item = DownloadItem(
      video: v,
      audioOnly: audioOnly,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );
    _set(item);
    await _db.upsertDownload(item);
    _pump();
  }

  void cancel(String id) {
    _cancel.add(id);
    final d = state[id];
    if (d != null && d.status == DownloadStatus.queued) {
      _set(d.copyWith(status: DownloadStatus.canceled));
      _db.upsertDownload(state[id]!);
    }
  }

  Future<void> retry(String id) async {
    final d = state[id];
    if (d == null) return;
    _cancel.remove(id);
    _set(d.copyWith(status: DownloadStatus.queued, progress: 0));
    await _db.upsertDownload(state[id]!);
    _pump();
  }

  Future<void> delete(String id) async {
    _cancel.add(id);
    final d = state[id];
    if (d != null) {
      for (final f in [d.filePath, d.videoFilePath]) {
        if (f != null) {
          try {
            await File(f).delete();
          } catch (_) {}
        }
      }
    }
    await _db.deleteDownload(id);
    final next = {...state}..remove(id);
    state = next;
  }

  void _set(DownloadItem d) => state = {...state, d.video.id: d};

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = state.values.where((d) => d.status == DownloadStatus.queued).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (next.isEmpty) break;
        await _run(next.first);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadItem item) async {
    final id = item.video.id;
    _cancel.remove(id);
    _set(item.copyWith(status: DownloadStatus.running, progress: 0));
    try {
      final dir = await downloadsDir();
      var streams = await _yt.resolve(id);
      final audioExt = streams.audioUrl.contains('mime=audio%2Fwebm') ? 'webm' : 'm4a';
      final audioPath = p.join(dir.path, '$id.$audioExt');
      String? videoPath;
      StreamChoice? videoChoice;
      if (!item.audioOnly) {
        final pref = ref.read(settingsProvider).preferredQuality;
        final candidates = streams.videoChoices.where((c) => c.height <= pref).toList();
        videoChoice = candidates.isNotEmpty
            ? candidates.first
            : (streams.videoChoices.isNotEmpty ? streams.videoChoices.last : null);
        if (videoChoice != null) videoPath = p.join(dir.path, '$id.${videoChoice.muxed ? 'muxed' : 'video'}.mp4');
      }

      final jobs = <(String Function(ResolvedStreams), String)>[
        ((s) => s.audioUrl, audioPath),
        if (videoChoice != null && videoPath != null)
          (
            (s) =>
                s.videoChoices.firstWhere((c) => c.height == videoChoice!.height, orElse: () => videoChoice!).url,
            videoPath,
          ),
      ];
      final totals = List<int>.filled(jobs.length, 0);
      final done = List<int>.filled(jobs.length, 0);

      for (var j = 0; j < jobs.length; j++) {
        final (urlOf, path) = jobs[j];
        final part = File('$path.part');
        var attempts = 0;
        while (true) {
          if (_cancel.contains(id)) throw const _Canceled();
          final start = part.existsSync() ? part.lengthSync() : 0;
          try {
            final (stream, total) = await _yt.openStream(urlOf(streams), streams.headers, start: start);
            totals[j] = total ?? 0;
            done[j] = start;
            final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
            var lastTick = DateTime.now();
            try {
              await for (final chunk in stream) {
                if (_cancel.contains(id)) throw const _Canceled();
                sink.add(chunk);
                done[j] += chunk.length;
                final now = DateTime.now();
                if (now.difference(lastTick).inMilliseconds > 250) {
                  lastTick = now;
                  final t = totals.fold<int>(0, (a, b) => a + b);
                  final d = done.fold<int>(0, (a, b) => a + b);
                  final prog = t > 0 ? d / t : 0.0;
                  _set(state[id]!.copyWith(progress: (j + prog.clamp(0, 1)) / jobs.length * 1.0));
                }
              }
            } finally {
              await sink.flush();
              await sink.close();
            }
            if (totals[j] > 0 && part.lengthSync() < totals[j]) throw const HttpException('Incomplete download');
            break;
          } on _Canceled {
            rethrow;
          } catch (e) {
            attempts++;
            if (attempts > 4) rethrow;
            // Expired / rejected URL: fetch a fresh manifest and resume.
            if (e.toString().contains('403') || e.toString().contains('410')) {
              streams = await _yt.resolve(id, refresh: true);
            }
            await Future<void>.delayed(Duration(milliseconds: 600 * attempts));
          }
        }
        await part.rename(path);
      }

      var size = File(audioPath).lengthSync();
      if (videoPath != null && File(videoPath).existsSync()) size += File(videoPath).lengthSync();
      final finished = state[id]!.copyWith(
        status: DownloadStatus.done,
        progress: 1,
        filePath: audioPath,
        videoFilePath: videoPath,
        sizeBytes: size,
      );
      _set(finished);
      await _db.upsertDownload(finished);
    } on _Canceled {
      final c = state[id];
      if (c != null) {
        final canceled = c.copyWith(status: DownloadStatus.canceled);
        _set(canceled);
        await _db.upsertDownload(canceled);
      }
    } catch (e) {
      final c = state[id];
      if (c != null) {
        final failed = c.copyWith(status: DownloadStatus.failed, error: e.toString());
        _set(failed);
        await _db.upsertDownload(failed);
      }
    }
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
