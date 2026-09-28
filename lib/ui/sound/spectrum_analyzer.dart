import 'dart:math' as math;
import 'dart:typed_data';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import 'carro_theme.dart';

/// Real-time output spectrum of the DSP engine (~30 fps) with peak-hold caps, drawn in the
/// illumination colour. Only the painter repaints on each frame; the widget itself does not
/// rebuild.
class SpectrumAnalyzer extends ConsumerStatefulWidget {
  const SpectrumAnalyzer({
    super.key,
    this.bands = 31,
    this.height = 120,
    this.minDb = -72,
    this.maxDb = 0,
    this.showScale = true,
    this.segmented = true,
    this.ghost = true,
  });

  /// Compact variant for status strips.
  const SpectrumAnalyzer.mini({super.key, this.bands = 16, this.height = 28})
    : minDb = -66,
      maxDb = -6,
      showScale = false,
      segmented = false,
      ghost = true;

  final int bands;
  final double height;
  final double minDb, maxDb;
  final bool showScale;
  final bool segmented;
  final bool ghost;

  @override
  ConsumerState<SpectrumAnalyzer> createState() => _SpectrumAnalyzerState();
}

class _SpectrumAnalyzerState extends ConsumerState<SpectrumAnalyzer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _repaint = _RepaintSignal();
  late Float64List _level;
  late Float64List _peak;
  late Float64List _hold;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _alloc();
  }

  void _alloc() {
    _level = Float64List(widget.bands);
    _peak = Float64List(widget.bands);
    _hold = Float64List(widget.bands);
  }

  @override
  void didUpdateWidget(covariant SpectrumAnalyzer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bands != widget.bands) _alloc();
  }

  void _setRunning(bool run) {
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dtUs = (elapsed - _last).inMicroseconds;
    if (_last != Duration.zero && dtUs < 31000) return; // ~30 fps
    final dt = _last == Duration.zero ? 1 / 30 : math.min(0.2, dtUs / 1e6);
    _last = elapsed;
    Float32List data;
    try {
      data = CarroDsp.instance.spectrum(widget.bands);
    } catch (_) {
      _ticker.stop();
      return;
    }
    final n = math.min(data.length, _level.length);
    final range = widget.maxDb - widget.minDb;
    for (var i = 0; i < n; i++) {
      final raw = data[i];
      final v = raw.isFinite ? ((raw - widget.minDb) / range).clamp(0.0, 1.0) : 0.0;
      // Fast attack, smooth fall.
      _level[i] = v > _level[i] ? v : math.max(v, _level[i] - 1.4 * dt);
      if (_level[i] >= _peak[i]) {
        _peak[i] = _level[i];
        _hold[i] = 0.7;
      } else if (_hold[i] > 0) {
        _hold[i] -= dt;
      } else {
        _peak[i] = math.max(_level[i], _peak[i] - 0.45 * dt);
      }
    }
    for (var i = n; i < _level.length; i++) {
      _level[i] = math.max(0, _level[i] - 1.4 * dt);
      _peak[i] = math.max(_level[i], _peak[i] - 0.45 * dt);
    }
    _repaint.ping();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(soundProvider.select((s) => s.dspAvailable));
    _setRunning(available);
    final c = CarroIllumination.of(context);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _SpectrumPainter(
                repaint: _repaint,
                level: _level,
                peak: _peak,
                color: c,
                segmented: widget.segmented,
                showScale: widget.showScale,
                ghost: widget.ghost,
                minDb: widget.minDb,
                maxDb: widget.maxDb,
              ),
            ),
            if (!available && widget.showScale)
              Center(child: Text('DSP ENGINE NOT LOADED', style: lcdStyle(CarroColors.textDim, size: 11, glow: false))),
          ],
        ),
      ),
    );
  }
}

class _RepaintSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required Listenable repaint,
    required this.level,
    required this.peak,
    required this.color,
    required this.segmented,
    required this.showScale,
    required this.ghost,
    required this.minDb,
    required this.maxDb,
  }) : super(repaint: repaint);

  final Float64List level, peak;
  final Color color;
  final bool segmented, showScale, ghost;
  final double minDb, maxDb;

  static const _freqLabels = <double>[31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  @override
  void paint(Canvas canvas, Size size) {
    final left = showScale ? 26.0 : 0.0;
    final bottomPad = showScale ? 14.0 : 0.0;
    final plot = Rect.fromLTRB(left, showScale ? 4 : 0, size.width, size.height - bottomPad);
    if (plot.width <= 0 || plot.height <= 0) return;
    final n = level.length;
    if (n == 0) return;

    if (showScale) {
      final grid = Paint()
        ..color = const Color(0xFF1A1F26)
        ..strokeWidth = 1;
      final tp = TextPainter(textDirection: TextDirection.ltr);
      for (var db = 0.0; db >= minDb; db -= 12) {
        if (db > maxDb) continue;
        final y = plot.bottom - (db - minDb) / (maxDb - minDb) * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        tp
          ..text = TextSpan(
            text: db.toStringAsFixed(0),
            style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
          )
          ..layout();
        tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
      }
      for (final f in _freqLabels) {
        final x = plot.left + math.log(f / 20) / math.log(1000) * plot.width;
        tp
          ..text = TextSpan(
            text: hzText(f),
            style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
          )
          ..layout();
        tp.paint(canvas, Offset((x - tp.width / 2).clamp(plot.left, plot.right - tp.width), plot.bottom + 2));
      }
      tp.dispose();
    }

    final slot = plot.width / n;
    final gap = math.min(3.0, math.max(1.0, slot * 0.22));
    final barW = math.max(1.0, slot - gap);

    if (ghost) {
      final gp = Paint()..color = Colors.white.withValues(alpha: 0.035);
      for (var i = 0; i < n; i++) {
        final x = plot.left + i * slot + gap / 2;
        canvas.drawRect(Rect.fromLTWH(x, plot.top, barW, plot.height), gp);
      }
    }

    final shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [color.withValues(alpha: 0.55), color, Color.lerp(color, Colors.white, 0.45)!],
      stops: const [0, 0.6, 1],
    ).createShader(plot);
    final barPaint = Paint()..shader = shader;
    final path = Path();
    const segH = 3.0, segGap = 1.5;
    for (var i = 0; i < n; i++) {
      final h = level[i] * plot.height;
      if (h < 0.5) continue;
      final x = plot.left + i * slot + gap / 2;
      if (segmented) {
        var y = plot.bottom;
        final topY = plot.bottom - h;
        while (y - segH >= topY - 0.01) {
          path.addRect(Rect.fromLTWH(x, y - segH, barW, segH));
          y -= segH + segGap;
        }
      } else {
        path.addRect(Rect.fromLTWH(x, plot.bottom - h, barW, h));
      }
    }
    canvas.drawPath(path, barPaint);

    // Peak caps.
    final capPaint = Paint()..color = Color.lerp(color, Colors.white, 0.35)!;
    final capGlow = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final caps = Path();
    for (var i = 0; i < n; i++) {
      if (peak[i] <= 0.01) continue;
      final x = plot.left + i * slot + gap / 2;
      final y = plot.bottom - peak[i] * plot.height;
      caps.addRect(Rect.fromLTWH(x, y - 2, barW, 2));
    }
    canvas.drawPath(caps, capGlow);
    canvas.drawPath(caps, capPaint);
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.color != color ||
      old.level != level ||
      old.segmented != segmented ||
      old.showScale != showScale ||
      old.ghost != ghost ||
      old.minDb != minDb ||
      old.maxDb != maxDb;
}
