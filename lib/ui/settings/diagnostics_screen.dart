import 'dart:io';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/database.dart';
import '../../data/youtube_service.dart';

/// Runs every layer the app depends on (network, YouTube search, stream resolution, stream
/// download, related videos, database, DSP engine, native player channel) and shows the exact
/// result of each step, so a problem on a device can be reported with one screenshot.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _Step {
  _Step(this.name);
  final String name;
  bool? ok;
  String detail = '';
  int ms = 0;
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _steps = <_Step>[];
  bool _running = false;

  Future<void> _run(String name, Future<String> Function() body) async {
    final s = _Step(name);
    setState(() => _steps.add(s));
    final sw = Stopwatch()..start();
    try {
      s.detail = await body().timeout(const Duration(seconds: 45));
      s.ok = true;
    } catch (e) {
      s.detail = '$e';
      s.ok = false;
    }
    s.ms = sw.elapsedMilliseconds;
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _steps.clear();
    });
    final yt = ref.read(youtubeServiceProvider);
    String? firstId;
    await _run('Internet (youtube.com)', () async {
      final r = await http.get(Uri.parse('https://www.youtube.com/generate_204'));
      return 'HTTP ${r.statusCode}';
    });
    await _run('Search suggestions', () async => (await yt.suggestions('uzbek music')).take(3).join(', '));
    await _run('Search', () async {
      final p = await yt.videoSearch('uzbek music');
      if (p.items.isEmpty) throw StateError('no results');
      firstId = p.items.first.id;
      return '${p.items.length} videos, first: ${p.items.first.title}';
    });
    if (firstId != null) {
      final id = firstId!;
      await _run('Stream URLs ($id)', () async {
        final r = await yt.resolve(id, refresh: true);
        return 'audio ${r.audioCodec} ${r.audioBitrateKbps ?? '?'} kbps, video ${r.videoChoices.map((c) => c.label).join(' ')}';
      });
      await _run('Stream download test', () async {
        final r = await yt.resolve(id);
        final res = await http.get(Uri.parse(r.audioUrl), headers: {...r.headers, 'Range': 'bytes=0-4095'});
        if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
        return 'HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes';
      });
      await _run('Video details', () async => (await yt.video(id)).title);
      await _run('Up next (related)', () async => '${(await yt.related(id)).items.length} videos');
    }
    await _run('Database', () async => '${(await ref.read(appDatabaseProvider).history(limit: 5)).length} history rows');
    await _run('DSP engine', () async {
      if (!CarroDsp.isAvailable) throw StateError('not loaded: ${CarroDsp.loadError}');
      final d = CarroDsp.instance;
      return '${d.version}, ${d.sampleRate.toStringAsFixed(0)} Hz, cpu ${(d.meters().cpuLoad * 100).toStringAsFixed(1)}%';
    });
    await _run('Native player channel', () async {
      await NativePlayer.instance.init();
      return 'ok (${Platform.operatingSystem} ${Platform.operatingSystemVersion})';
    });
    if (mounted) setState(() => _running = false);
  }

  String get _report => _steps
      .map((s) => '${s.ok == true ? 'OK  ' : s.ok == false ? 'FAIL' : '... '} ${s.name} (${s.ms} ms): ${s.detail}')
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostika'),
        actions: [
          if (_steps.isNotEmpty && !_running)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _report));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_running ? 'Running…' : 'Run diagnostics'),
          ),
          const SizedBox(height: 16),
          for (final s in _steps)
            Card(
              child: ListTile(
                leading: s.ok == null
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(s.ok! ? Icons.check_circle_rounded : Icons.error_rounded,
                        color: s.ok! ? Colors.green : theme.colorScheme.error),
                title: Text('${s.name}  ·  ${s.ms} ms'),
                subtitle: SelectableText(s.detail, maxLines: 6),
              ),
            ),
        ],
      ),
    );
  }
}
