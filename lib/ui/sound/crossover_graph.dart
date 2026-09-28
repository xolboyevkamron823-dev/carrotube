import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'carro_theme.dart';

/// One channel's magnitude response for [CrossoverGraph].
class XoCurve {
  const XoCurve({
    required this.label,
    required this.color,
    required this.db,
    this.selected = false,
    this.muted = false,
  });

  final String label;
  final Color color;
  final Float32List db;
  final bool selected;
  final bool muted;
}

/// Log-frequency (20 Hz..20 kHz) / dB (-40..+12) plot of the crossover filters.
class CrossoverGraph extends StatelessWidget {
  const CrossoverGraph({super.key, required this.freqs, required this.curves, this.height = 210});

  final List<double> freqs;
  final List<XoCurve> curves;
  final double height;

  static const minDb = -40.0;
  static const maxDb = 12.0;

  /// [n] log-spaced frequencies from 20 Hz to 20 kHz.
  static List<double> logFreqs(int n) =>
      List<double>.generate(n, (i) => 20 * math.pow(1000, i / (n - 1)).toDouble(), growable: false);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _XoPainter(freqs: freqs, curves: curves, accent: CarroIllumination.of(context)),
        ),
      ),
    );
  }
}

class _XoPainter extends CustomPainter {
  _XoPainter({required this.freqs, required this.curves, required this.accent});

  final List<double> freqs;
  final List<XoCurve> curves;
  final Color accent;

  static const _labelFreqs = <double>[20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

  @override
  void paint(Canvas canvas, Size size) {
    const minDb = CrossoverGraph.minDb, maxDb = CrossoverGraph.maxDb;
    final plot = Rect.fromLTRB(30, 6, size.width - 6, size.height - 16);
    if (plot.width <= 0 || plot.height <= 0) return;
    double xOf(double f) => plot.left + math.log(f / 20) / math.log(1000) * plot.width;
    double yOf(double db) => plot.top + (maxDb - db.clamp(minDb - 6, maxDb + 6)) / (maxDb - minDb) * plot.height;

    canvas.drawRect(plot, Paint()..color = const Color(0xFF06080A));
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;

    // Vertical grid: every 1..9 × decade.
    for (var decade = 10.0; decade <= 10000; decade *= 10) {
      for (var k = 1; k <= 9; k++) {
        final f = decade * k;
        if (f < 20 || f > 20000) continue;
        final x = xOf(f);
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), k == 1 ? major : minor);
      }
    }
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final f in _labelFreqs) {
      final x = xOf(f);
      tp
        ..text = TextSpan(
          text: hzText(f),
          style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
        )
        ..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(plot.left, plot.right - tp.width), plot.bottom + 3));
    }
    // Horizontal grid every 6 dB, labels every 12 dB.
    for (var db = maxDb; db >= minDb; db -= 6) {
      final y = yOf(db);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        db == 0 ? (Paint()..color = Colors.white.withValues(alpha: 0.22)) : (db % 12 == 0 ? major : minor),
      );
      if (db % 12 == 0) {
        tp
          ..text = TextSpan(
            text: signed(db),
            style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
          )
          ..layout();
        tp.paint(canvas, Offset(plot.left - tp.width - 4, y - tp.height / 2));
      }
    }
    tp.dispose();

    canvas.save();
    canvas.clipRect(plot);
    Path build(Float32List db) {
      final p = Path();
      final n = math.min(db.length, freqs.length);
      for (var i = 0; i < n; i++) {
        final v = db[i].isFinite ? db[i] : minDb - 6;
        final o = Offset(xOf(freqs[i]), yOf(v));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p;
    }

    // Unselected first, the selected channel on top.
    final ordered = [...curves.where((c) => !c.selected), ...curves.where((c) => c.selected)];
    for (final c in ordered) {
      if (c.db.isEmpty) continue;
      final path = build(c.db);
      final alpha = c.muted ? 0.25 : (c.selected ? 1.0 : 0.55);
      if (c.selected && !c.muted) {
        final fill = Path.from(path)
          ..lineTo(xOf(freqs[math.min(c.db.length, freqs.length) - 1]), plot.bottom)
          ..lineTo(xOf(freqs.first), plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.color.withValues(alpha: 0.28), c.color.withValues(alpha: 0.0)],
            ).createShader(plot),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = c.color.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c.selected ? 2.4 : 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = c.color.withValues(alpha: alpha),
      );
    }
    canvas.restore();
    canvas.drawRect(
      plot,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_XoPainter old) => old.curves != curves || old.accent != accent || old.freqs != freqs;
}
