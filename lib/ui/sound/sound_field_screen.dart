import 'dart:async';
import 'dart:math' as math;

import 'package:carro_native/carro_native.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'ir_capture_screen.dart';
import 'sf_tuning_screen.dart';
import 'sound_files.dart';
import 'sound_strings.dart';

/// SOUND FIELD: mode, level, size, algorithmic / convolution engine, IR assignment and the
/// live reverb decay curve of the engine.
class SoundFieldScreen extends ConsumerStatefulWidget {
  const SoundFieldScreen({super.key});

  @override
  ConsumerState<SoundFieldScreen> createState() => _SoundFieldScreenState();
}

class _SoundFieldScreenState extends ConsumerState<SoundFieldScreen> {
  Future<void> _importWav(int mode, int size) async {
    final n = ref.read(soundProvider.notifier);
    try {
      final path = await pickLocalFile(const ['wav']);
      if (path == null || !mounted) return;
      final name = await showCarroTextDialog(
        context,
        title: 'IMPORT IR',
        initial: p.basenameWithoutExtension(path).replaceAll(RegExp(r'^import_\d+_'), ''),
        label: soundText(context, 'ir_name'),
      );
      if (name == null) return;
      final entry = await n.addIr(path, name: name, source: 'import');
      await n.assignIr(mode, size, entry.path);
      if (!mounted) return;
      showCarroSnack(context, soundText(context, 'ir_assigned').replaceAll('{slot}', slotName(mode, size)));
    } catch (e) {
      if (!mounted) return;
      showCarroSnack(context, soundText(context, 'error_generic').replaceAll('{error}', '$e'), error: true);
    }
  }

  Future<void> _chooseFromLibrary(int mode, int size) async {
    final s = ref.read(soundProvider);
    final n = ref.read(soundProvider.notifier);
    final current = s.irAssignments[SoundState.slotKey(mode, size)];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'ASSIGN IR · ${slotName(mode, size)}',
                  style: lcdStyle(CarroIllumination.of(ctx), size: 14),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('NONE (ALGORITHMIC FALLBACK)'),
                selected: current == null,
                onTap: () => Navigator.of(ctx).pop(''),
              ),
              if (s.irLibrary.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(soundText(ctx, 'ir_library_empty'), style: carroBody),
                ),
              for (final e in s.irLibrary)
                ListTile(
                  leading: Icon(e.source == 'capture' ? Icons.mic : Icons.graphic_eq),
                  title: Text(e.name),
                  subtitle: Text(irDescription(e)),
                  selected: current == e.path,
                  onTap: () => Navigator.of(ctx).pop(e.path),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await n.assignIr(mode, size, picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final mode = pr.sfMode;
    final off = mode == 0;

    return CarroScaffold(
      title: 'SOUND FIELD',
      actions: [
        IconButton(
          tooltip: 'TUNE',
          icon: const Icon(Icons.tune),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SfTuningScreen())),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          if (!s.dspAvailable) const CarroDspUnavailable(compact: true),
          _ModeCarousel(
            mode: mode,
            onChanged: (m) => n.update((p) => p.copyWith(sfMode: m)),
          ),
          CarroPanel(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CarroKnob(
                  label: 'LEVEL',
                  value: pr.sfLevel.toDouble(),
                  min: 0,
                  max: 10,
                  defaultValue: 5,
                  enabled: !off,
                  valueText: '${pr.sfLevel}',
                  onChanged: (v) => n.update((p) => p.copyWith(sfLevel: v.round())),
                ),
                CarroKnob(
                  label: 'SIZE',
                  value: pr.sfSize.toDouble(),
                  min: 0,
                  max: 2,
                  defaultValue: 1,
                  enabled: !off,
                  valueText: sizeNames[pr.sfSize.clamp(0, 2)],
                  onChanged: (v) => n.update((p) => p.copyWith(sfSize: v.round())),
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'REVERB DECAY',
            child: !s.dspAvailable
                ? const CarroNoDspGraph(height: 140)
                : LiveDecayGraph(emptyText: soundText(context, off ? 'sf_off_note' : 'decay_none')),
          ),
          CarroPanel(
            title: 'STEREO WIDTH',
            child: CarroSliderRow(
              label: 'WIDTH',
              valueText: '${(pr.sfWidth * 100).round()}%',
              value: pr.sfWidth,
              min: 0,
              max: 2,
              step: 0.05,
              origin: 1,
              enabled: !off,
              onChanged: (v) => n.update((p) => p.copyWith(sfWidth: v)),
            ),
          ),
          CarroPanel(
            title: 'ENGINE',
            child: CarroSegmented(
              labels: const ['ALGORITHMIC', 'CONVOLUTION'],
              selected: pr.sfEngine,
              onSelected: (i) => n.update((p) => p.copyWith(sfEngine: i)),
            ),
          ),
          if (pr.sfEngine == 1) _convolutionPanel(context, s, n, mode, pr.sfSize),
          if (pr.sfEngine == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: CarroButton(
                label: 'TUNE ${off ? 'MODES' : soundFieldModes[mode]}',
                icon: Icons.tune,
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SfTuningScreen())),
              ),
            ),
        ],
      ),
    );
  }

  Widget _convolutionPanel(BuildContext context, SoundState s, SoundController n, int mode, int size) {
    final pr = s.profile;
    final c = watchIllumination(ref);
    final off = mode == 0;
    final exact = off ? null : s.irAssignments[SoundState.slotKey(mode, size)];
    final assigned = off ? null : s.irForSlot(mode, size);
    final entry = assigned == null ? null : s.irLibrary.firstWhereOrNull((e) => e.path == assigned);
    IrInfo? info;
    if (s.dspAvailable && assigned != null && s.loadedIrPath == assigned) {
      try {
        info = CarroDsp.instance.irInfo();
      } catch (_) {
        info = null;
      }
    }
    final channelsText = switch (info?.channels ?? entry?.channels ?? 0) {
      1 => 'MONO',
      2 => 'STEREO',
      4 => 'TRUE STEREO',
      0 => '',
      final ch => '$ch CH',
    };

    return CarroPanel(
      title: off ? 'CONVOLUTION' : 'CONVOLUTION · ${slotName(mode, size)}',
      glow: assigned != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (off)
            Text(soundText(context, 'sf_off_note'), style: carroBody)
          else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarroColors.inset,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CarroColors.border),
              ),
              child: assigned == null
                  ? Text(soundText(context, 'conv_no_ir'), style: carroBody.copyWith(fontSize: 12))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(entry?.source == 'capture' ? Icons.mic : Icons.graphic_eq, color: c, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry?.name ?? p.basename(assigned),
                                style: lcdStyle(c, size: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (s.irLoading)
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (channelsText.isNotEmpty) channelsText,
                            if (info != null && info.sampleRate > 0) '${info.sampleRate} Hz',
                            if ((info?.lengthSeconds ?? entry?.lengthSeconds ?? 0) > 0)
                              '${(info?.lengthSeconds ?? entry!.lengthSeconds).toStringAsFixed(2)} s',
                            if (s.loadedIrPath == assigned) 'LOADED' else if (!s.irLoading) 'NOT LOADED',
                          ].join('  ·  '),
                          style: carroCaption,
                        ),
                        if (exact == null) ...[
                          const SizedBox(height: 4),
                          Text(
                            soundText(context, 'conv_fallback'),
                            style: carroCaption.copyWith(color: CarroColors.warn, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CarroButton(
                  label: 'ASSIGN',
                  icon: Icons.library_music,
                  dense: true,
                  onPressed: () => _chooseFromLibrary(mode, size),
                ),
                CarroButton(
                  label: 'IMPORT WAV',
                  icon: Icons.file_open,
                  dense: true,
                  onPressed: () => _importWav(mode, size),
                ),
                CarroButton(
                  label: 'CAPTURE',
                  icon: Icons.mic,
                  dense: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IrCaptureScreen(initialMode: mode, initialSize: size),
                    ),
                  ),
                ),
                if (exact != null)
                  CarroButton(
                    label: 'CLEAR',
                    icon: Icons.link_off,
                    dense: true,
                    onPressed: () => n.assignIr(mode, size, null),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          CarroSliderRow(
            label: 'DRY / WET',
            valueText: '${(pr.convDryWet * 100).round()}% WET',
            value: pr.convDryWet,
            min: 0,
            max: 1,
            step: 0.05,
            onChanged: (v) => n.update((p) => p.copyWith(convDryWet: v)),
          ),
          CarroSliderRow(
            label: 'PRE-DELAY',
            valueText: '${pr.convPreDelayMs.round()} ms',
            value: pr.convPreDelayMs,
            min: 0,
            max: 100,
            step: 1,
            onChanged: (v) => n.update((p) => p.copyWith(convPreDelayMs: v)),
          ),
          CarroSliderRow(
            label: 'IR TRIM START',
            valueText: '${pr.irTrimStartMs.round()} ms',
            value: pr.irTrimStartMs,
            min: 0,
            max: 500,
            step: 5,
            onChanged: (v) => n.update((p) => p.copyWith(irTrimStartMs: v)),
          ),
          CarroSliderRow(
            label: 'IR TRIM END',
            valueText: pr.irTrimEndMs <= 0 ? 'FULL' : '${(pr.irTrimEndMs / 1000).toStringAsFixed(2)} s',
            value: pr.irTrimEndMs,
            min: 0,
            max: 6000,
            step: 50,
            onChanged: (v) => n.update((p) => p.copyWith(irTrimEndMs: v)),
          ),
          CarroToggle(
            label: 'LOUDNESS MATCH',
            value: pr.loudnessMatch,
            onChanged: (v) => n.update((p) => p.copyWith(loudnessMatch: v)),
          ),
        ],
      ),
    );
  }
}

/// "CONCERT HALL M".
String slotName(int mode, int size) =>
    '${soundFieldModes[mode.clamp(0, soundFieldModes.length - 1)]} ${sizeNames[size.clamp(0, 2)]}';

String irDescription(IrEntry e) => [
  e.source.toUpperCase(),
  if (e.channels > 0) e.channels == 4 ? 'TRUE STEREO' : '${e.channels} CH',
  if (e.lengthSeconds > 0) '${e.lengthSeconds.toStringAsFixed(2)} s',
].where((x) => x.isNotEmpty).join(' · ');

/// Big head-unit mode display with arrows / swipe and a grid of all modes.
class _ModeCarousel extends StatelessWidget {
  const _ModeCarousel({required this.mode, required this.onChanged});

  final int mode;
  final ValueChanged<int> onChanged;

  void _step(int d) {
    final next = (mode + d) % soundFieldModes.length;
    HapticFeedback.selectionClick();
    onChanged(next < 0 ? next + soundFieldModes.length : next);
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return CarroPanel(
      glow: mode != 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 150) _step(v < 0 ? 1 : -1);
            },
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: CarroColors.inset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _step(-1),
                    icon: Icon(Icons.arrow_left_rounded, color: c, size: 40),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('SOUND FIELD', style: carroCaption.copyWith(color: c.withValues(alpha: 0.7))),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                          child: FittedBox(
                            key: ValueKey(mode),
                            fit: BoxFit.scaleDown,
                            child: Text(
                              soundFieldModes[mode],
                              style: lcdStyle(
                                mode == 0 ? CarroColors.textDim : c,
                                size: 26,
                                weight: FontWeight.w800,
                                glow: mode != 0,
                                spacing: 3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _step(1),
                    icon: Icon(Icons.arrow_right_rounded, color: c, size: 40),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - 3 * 6) / 4;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < soundFieldModes.length; i++)
                    SizedBox(
                      width: w,
                      child: CarroSegmented(
                        dense: true,
                        labels: [soundFieldModes[i]],
                        selected: i == mode ? 0 : -1,
                        onSelected: (_) => onChanged(i),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Queries the engine's decay curve of the active Sound Field whenever a parameter that
/// shapes it changes (debounced while a control is being dragged, and only while the route
/// is visible: the engine renders the curve synchronously).
class LiveDecayGraph extends ConsumerStatefulWidget {
  const LiveDecayGraph({super.key, this.height = 140, this.emptyText = ''});

  final double height;
  final String emptyText;

  @override
  ConsumerState<LiveDecayGraph> createState() => _LiveDecayGraphState();
}

class _LiveDecayGraphState extends ConsumerState<LiveDecayGraph> {
  Object? _key;
  DecayCurve? _curve;
  bool _computed = false;
  Timer? _debounce;

  static Object _keyOf(SoundState s) {
    final pr = s.profile;
    return (
      pr.sfEngine,
      pr.sfMode,
      pr.sfSize,
      pr.sfLevel,
      pr.sfWidth,
      pr.convDryWet,
      pr.convPreDelayMs,
      pr.irTrimStartMs,
      pr.irTrimEndMs,
      pr.loudnessMatch,
      s.sfTable[pr.sfMode],
      s.loadedIrPath,
      s.irLoading,
    );
  }

  void _compute() {
    final s = ref.read(soundProvider);
    _computed = true;
    if (!s.dspAvailable || s.profile.sfMode == 0) {
      _curve = null;
      return;
    }
    try {
      _curve = CarroDsp.instance.decayCurve(256);
    } catch (_) {
      _curve = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    final key = _keyOf(s);
    if (visible && key != _key) {
      _key = key;
      if (!_computed) {
        _compute();
      } else {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 90), () {
          if (mounted) setState(_compute);
        });
      }
    }
    return DecayGraph(curve: _curve, height: widget.height, emptyText: widget.emptyText);
  }
}

/// Energy decay curve (dB over time) with the RT60 marker.
class DecayGraph extends StatelessWidget {
  const DecayGraph({super.key, required this.curve, this.height = 140, this.emptyText = ''});

  final DecayCurve? curve;
  final double height;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    if (curve == null || curve!.db.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyText.toUpperCase(),
            textAlign: TextAlign.center,
            style: lcdStyle(CarroColors.textDim, size: 11, glow: false),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _DecayPainter(curve: curve!, color: c),
        ),
      ),
    );
  }
}

class _DecayPainter extends CustomPainter {
  _DecayPainter({required this.curve, required this.color});

  final DecayCurve curve;
  final Color color;

  static const _floor = -70.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(30, 6, size.width - 6, size.height - 16);
    if (plot.width <= 0 || plot.height <= 0) return;
    final dur = curve.durationSeconds > 0 ? curve.durationSeconds : 1.0;
    double xOf(double t) => plot.left + t / dur * plot.width;
    double yOf(double db) => plot.top + (db.clamp(_floor, 0) / _floor) * plot.height;

    canvas.drawRect(plot, Paint()..color = const Color(0xFF06080A));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var db = 0.0; db >= _floor; db -= 10) {
      final y = yOf(db);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      if (db % 20 == 0) {
        tp
          ..text = TextSpan(
            text: db.toStringAsFixed(0),
            style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
          )
          ..layout();
        tp.paint(canvas, Offset(plot.left - tp.width - 4, y - tp.height / 2));
      }
    }
    final rawStep = dur / 6;
    final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final step = [1.0, 2.0, 5.0, 10.0].map((m) => m * mag).firstWhere((s) => s >= rawStep, orElse: () => 10 * mag);
    for (var t = 0.0; t <= dur + 1e-9; t += step) {
      final x = xOf(t);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      tp
        ..text = TextSpan(
          text: t < 1 && step < 1 ? '${(t * 1000).round()}ms' : '${t.toStringAsFixed(step < 1 ? 1 : 0)}s',
          style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
        )
        ..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(plot.left, plot.right - tp.width), plot.bottom + 3));
    }

    // -60 dB reference and RT60 marker.
    final ref = Paint()
      ..color = CarroColors.warn.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final y60 = yOf(-60);
    for (var x = plot.left; x < plot.right; x += 8) {
      canvas.drawLine(Offset(x, y60), Offset(math.min(x + 4, plot.right), y60), ref);
    }
    if (curve.rt60 > 0 && curve.rt60 <= dur) {
      final x = xOf(curve.rt60);
      for (var y = plot.top; y < plot.bottom; y += 8) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, plot.bottom)), ref);
      }
    }
    if (curve.rt60 > 0) {
      tp
        ..text = TextSpan(
          text: 'RT60 ${curve.rt60.toStringAsFixed(2)} s',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
            shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 6)],
          ),
        )
        ..layout();
      tp.paint(canvas, Offset(plot.right - tp.width - 6, plot.top + 4));
    }
    tp.dispose();

    final n = curve.db.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1) * dur;
      final v = curve.db[i].isFinite ? curve.db[i] : _floor;
      final o = Offset(xOf(t), yOf(v));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.save();
    canvas.clipRect(plot);
    final fill = Path.from(path)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.02)],
        ).createShader(plot),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DecayPainter old) => old.curve != curve || old.color != color;
}
