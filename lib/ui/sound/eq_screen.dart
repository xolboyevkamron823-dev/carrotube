import 'dart:math' as math;
import 'dart:typed_data';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'spectrum_analyzer.dart';

/// Graphic EQ: 13 bands (50 Hz..12.5 kHz) or 31 bands in Pro mode, presets, independent
/// L/R in Network mode, the engine's real EQ curve over the live analyzer.
class EqScreen extends ConsumerStatefulWidget {
  const EqScreen({super.key});

  @override
  ConsumerState<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends ConsumerState<EqScreen> {
  int _channel = 0;

  static final List<double> _curveFreqs = List<double>.generate(
    160,
    (i) => 20 * math.pow(1000, i / 159).toDouble(),
    growable: false,
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final showLink = pr.network || !pr.eqLinked;
    final independent = showLink && !pr.eqLinked;
    final channel = independent ? _channel : 0;
    final values = channel == 1 ? pr.eqRight : pr.eqLeft;
    final freqs = pr.bandFreqs;
    final illum = watchIllumination(ref);

    Float32List? curveSel, curveOther;
    if (s.dspAvailable) {
      try {
        final dsp = CarroDsp.instance;
        curveSel = dsp.response(channel == 1 ? Curve.eqR : Curve.eqL, _curveFreqs);
        if (independent) curveOther = dsp.response(channel == 1 ? Curve.eqL : Curve.eqR, _curveFreqs);
      } catch (_) {
        curveSel = null;
      }
    }

    return CarroScaffold(
      title: 'EQ',
      actions: [
        IconButton(
          tooltip: 'RESET',
          icon: const Icon(Icons.restart_alt),
          onPressed: () {
            HapticFeedback.mediumImpact();
            n.resetEq();
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          if (!s.dspAvailable) const CarroDspUnavailable(compact: true),
          CarroPanel(
            title: 'PRESET',
            trailing: Text(pr.eqPreset, style: lcdStyle(illum, size: 12)),
            child: CarroSegmented(
              labels: eqPresetNames,
              selected: eqPresetNames.indexOf(pr.eqPreset),
              scrollable: true,
              onSelected: (i) => n.applyEqPreset(eqPresetNames[i]),
            ),
          ),
          CarroPanel(
            title: 'RESPONSE',
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: SizedBox(
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const SpectrumAnalyzer(bands: 48, height: 170, minDb: -78, maxDb: -6, showScale: false),
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _EqCurvePainter(
                          freqs: _curveFreqs,
                          curve: curveSel,
                          other: curveOther,
                          bandFreqs: freqs,
                          bandValues: values,
                          color: illum,
                          otherColor: channelColors(illum)[1],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          CarroPanel(
            title: 'MODE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(labels: const ['13-BAND', '31-BAND PRO'], selected: pr.eqMode, onSelected: n.setEqMode),
                if (showLink) ...[
                  const SizedBox(height: 8),
                  CarroToggle(
                    label: 'L/R LINK',
                    subtitle: pr.eqLinked ? 'LEFT = RIGHT' : 'INDEPENDENT LEFT / RIGHT EQ',
                    value: pr.eqLinked,
                    onChanged: (v) {
                      n.setEqLinked(v);
                      if (v) setState(() => _channel = 0);
                    },
                  ),
                  if (independent) ...[
                    const SizedBox(height: 6),
                    CarroSegmented(
                      labels: const ['LEFT', 'RIGHT'],
                      selected: _channel,
                      onSelected: (i) => setState(() => _channel = i),
                    ),
                  ],
                ],
              ],
            ),
          ),
          CarroPanel(
            title: independent ? 'GRAPHIC EQ · ${channel == 1 ? 'RIGHT' : 'LEFT'}' : 'GRAPHIC EQ',
            trailing: Text('${pr.bandCount} BAND', style: carroCaption),
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: SizedBox(
              height: 270,
              child: pr.eqMode == 1
                  ? ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemExtent: 38,
                      itemCount: freqs.length,
                      itemBuilder: (_, i) => CarroVerticalSlider(
                        value: i < values.length ? values[i] : 0,
                        label: hzText(freqs[i]),
                        height: 270,
                        onChanged: (v) => n.setEqBand(i, v, channel: channel),
                      ),
                    )
                  : Row(
                      children: [
                        for (var i = 0; i < freqs.length; i++)
                          Expanded(
                            child: CarroVerticalSlider(
                              value: i < values.length ? values[i] : 0,
                              label: hzText(freqs[i]),
                              height: 270,
                              onChanged: (v) => n.setEqBand(i, v, channel: channel),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: CarroButton(label: 'FLAT', icon: Icons.horizontal_rule, onPressed: n.resetEq),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CarroButton(
                    label: 'SAVE AS CUSTOM2',
                    icon: Icons.save_alt,
                    onPressed: () => n.update((p) {
                      final v13 = p.eqMode == 0
                          ? List<double>.of(p.eqLeft)
                          : resampleEq(p.eqLeft, eq31Freqs, eq13Freqs);
                      return p.copyWith(custom2: v13, eqPreset: 'CUSTOM2');
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({
    required this.freqs,
    required this.curve,
    required this.other,
    required this.bandFreqs,
    required this.bandValues,
    required this.color,
    required this.otherColor,
  });

  final List<double> freqs;
  final Float32List? curve, other;
  final List<double> bandFreqs, bandValues;
  final Color color, otherColor;

  static const _range = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(0, 6, size.width - 22, size.height - 12);
    double xOf(double f) => plot.left + math.log(f / 20) / math.log(1000) * plot.width;
    double yOf(double db) => plot.center.dy - (db.clamp(-_range, _range) / _range) * plot.height / 2;

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final db in const [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = yOf(db);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        db == 0 ? (Paint()..color = Colors.white.withValues(alpha: 0.18)) : grid,
      );
      tp
        ..text = TextSpan(
          text: signed(db),
          style: const TextStyle(color: CarroColors.textDim, fontSize: 8.5),
        )
        ..layout();
      tp.paint(canvas, Offset(plot.right + 3, y - tp.height / 2));
    }
    tp.dispose();

    Path? pathFrom(Float32List? c) {
      if (c == null || c.isEmpty) return null;
      final p = Path();
      final n = math.min(c.length, freqs.length);
      for (var i = 0; i < n; i++) {
        final o = Offset(xOf(freqs[i]), yOf(c[i].isFinite ? c[i] : 0));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p;
    }

    var main = pathFrom(curve);
    if (main == null) {
      // No engine: draw straight segments through the band values.
      main = Path();
      for (var i = 0; i < bandFreqs.length && i < bandValues.length; i++) {
        final o = Offset(xOf(bandFreqs[i]), yOf(bandValues[i]));
        if (i == 0) {
          main.moveTo(plot.left, o.dy);
          main.lineTo(o.dx, o.dy);
        } else {
          main.lineTo(o.dx, o.dy);
        }
      }
      if (bandValues.isNotEmpty) main.lineTo(plot.right, yOf(bandValues.last));
    }

    final second = pathFrom(other);
    if (second != null) {
      canvas.drawPath(
        second,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = otherColor.withValues(alpha: 0.55),
      );
    }

    // Fill between the curve and 0 dB.
    final bounds = main.getBounds();
    final fillPath = Path.from(main)
      ..lineTo(bounds.right, yOf(0))
      ..lineTo(bounds.left, yOf(0))
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02), color.withValues(alpha: 0.22)],
        ).createShader(plot),
    );
    canvas.drawPath(
      main,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      main,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(color, Colors.white, 0.25)!,
    );

    // Band markers.
    final dot = Paint()..color = color;
    for (var i = 0; i < bandFreqs.length && i < bandValues.length; i++) {
      canvas.drawCircle(Offset(xOf(bandFreqs[i]), yOf(bandValues[i])), 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      old.curve != curve ||
      old.other != other ||
      old.color != color ||
      old.otherColor != otherColor ||
      !identical(old.bandValues, bandValues) ||
      !identical(old.bandFreqs, bandFreqs);
}
