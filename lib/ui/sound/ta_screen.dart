import 'dart:math' as math;

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'car_view.dart';
import 'carro_theme.dart';
import 'sound_strings.dart';

/// TIME ALIGNMENT: car top view with speakers and the listener, presets, per-speaker
/// distance (2.5 cm steps) and the resulting delays computed like the engine.
class TaScreen extends ConsumerStatefulWidget {
  const TaScreen({super.key});

  @override
  ConsumerState<TaScreen> createState() => _TaScreenState();
}

class _TaScreenState extends ConsumerState<TaScreen> {
  int _selected = 0;
  bool _ms = false;

  static const _standardNames = ['FL', 'FR', 'RL', 'RR', 'SW'];
  static const _networkNames = ['HL', 'HR', 'ML', 'MR', 'SW'];

  String _dist(double cm) => _ms ? '${(cm / 34.3).toStringAsFixed(2)} ms' : '${cm.toStringAsFixed(1)} cm';

  double _sampleRate(bool dspAvailable) {
    if (!dspAvailable) return 48000;
    try {
      final sr = CarroDsp.instance.sampleRate;
      return sr > 0 ? sr : 48000;
    } catch (_) {
      return 48000;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final names = pr.network ? _networkNames : _standardNames;
    final cm = [for (var i = 0; i < 5; i++) i < pr.taCm.length ? pr.taCm[i] : 0.0];
    final maxD = cm.reduce(math.max);
    final sr = _sampleRate(s.dspAvailable);
    final c = watchIllumination(ref);
    final presetIndex = pr.taOn ? taPresetNames.indexOf(pr.taPreset) : 0;

    double delayMs(int i) => pr.taOn ? (maxD - cm[i]) / 34.3 : 0;

    return CarroScaffold(
      title: 'TIME ALIGNMENT',
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          CarroPanel(
            title: 'LISTENING POSITION',
            trailing: Text(pr.taOn ? pr.taPreset : 'OFF', style: lcdStyle(c, size: 12)),
            child: CarroSegmented(
              labels: taPresetNames,
              selected: presetIndex,
              scrollable: true,
              onSelected: (i) => n.applyTaPreset(taPresetNames[i]),
            ),
          ),
          CarroPanel(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 0.82,
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final view = CarView(size);
                      final pos = _speakerPositions(pr.network);
                      var best = -1;
                      var bestD = 30.0;
                      for (var i = 0; i < pos.length; i++) {
                        final dd = (view.px(pos[i]) - d.localPosition).distance;
                        if (dd < bestD) {
                          bestD = dd;
                          best = i;
                        }
                      }
                      if (best >= 0 && best != _selected) {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = best);
                      }
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _TaPainter(
                        cm: cm,
                        names: names,
                        network: pr.network,
                        taOn: pr.taOn,
                        preset: pr.taPreset,
                        selected: _selected,
                        color: c,
                        ms: _ms,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          CarroPanel(
            title: 'UNIT',
            child: CarroSegmented(
              labels: const ['cm', 'ms'],
              selected: _ms ? 1 : 0,
              onSelected: (i) => setState(() => _ms = i == 1),
            ),
          ),
          CarroPanel(
            title: 'SPEAKER ${names[_selected]}',
            glow: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroValueStepper(
                  label: 'DISTANCE',
                  value: _dist(cm[_selected]),
                  valueWidth: 116,
                  onDecrement: cm[_selected] > 0 ? () => n.setTaDistance(_selected, cm[_selected] - 2.5) : null,
                  onIncrement: cm[_selected] < 350 ? () => n.setTaDistance(_selected, cm[_selected] + 2.5) : null,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: Text('DELAY', style: carroCaption)),
                    Text(
                      '${delayMs(_selected).toStringAsFixed(2)} ms  ·  ${(delayMs(_selected) / 1000 * sr).round()} smp',
                      style: lcdStyle(c, size: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'ALL SPEAKERS  ·  ${(sr / 1000).toStringAsFixed(sr % 1000 == 0 ? 0 : 1)} kHz',
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _selected = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      decoration: BoxDecoration(
                        color: i == _selected ? c.withValues(alpha: 0.08) : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              names[i],
                              style: lcdStyle(i == _selected ? c : CarroColors.text, size: 13, glow: i == _selected),
                            ),
                          ),
                          CarroValueStepper(
                            value: _dist(cm[i]),
                            valueWidth: 86,
                            onDecrement: cm[i] > 0 ? () => n.setTaDistance(i, cm[i] - 2.5) : null,
                            onIncrement: cm[i] < 350 ? () => n.setTaDistance(i, cm[i] + 2.5) : null,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${delayMs(i).toStringAsFixed(2)} ms',
                                  style: lcdStyle(c, size: 11.5, glow: false),
                                ),
                                Text(
                                  '${(delayMs(i) / 1000 * sr).round()} smp',
                                  style: carroCaption.copyWith(letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  soundText(context, pr.taOn ? (pr.taPreset == 'CUSTOM' ? 'ta_custom' : 'ta_help') : 'ta_off'),
                  style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Speaker positions in cabin centimetres (see [CarView]).
List<Offset> _speakerPositions(bool network) => network
    ? const [Offset(14, -6), Offset(136, -6), Offset(2, 32), Offset(148, 32), Offset(75, 284)]
    : const [Offset(2, 24), Offset(148, 24), Offset(2, 186), Offset(148, 186), Offset(75, 284)];

/// Listener head for a preset; CUSTOM is estimated from the distances (least squares).
Offset _listener(String preset, List<double> cm, List<Offset> speakers) {
  switch (preset) {
    case 'FRONT-LEFT':
      return const Offset(40, 108);
    case 'FRONT-RIGHT':
      return const Offset(110, 108);
    case 'FRONT':
      return const Offset(75, 108);
    case 'ALL':
      return const Offset(75, 150);
  }
  var best = const Offset(40, 108);
  var bestErr = double.infinity;
  for (var x = 5.0; x <= 145; x += 5) {
    for (var y = 40.0; y <= 235; y += 5) {
      final p = Offset(x, y);
      var err = 0.0;
      for (var i = 0; i < 4; i++) {
        final e = (p - speakers[i]).distance - cm[i];
        err += e * e;
      }
      if (err < bestErr) {
        bestErr = err;
        best = p;
      }
    }
  }
  return best;
}

class _TaPainter extends CustomPainter {
  _TaPainter({
    required this.cm,
    required this.names,
    required this.network,
    required this.taOn,
    required this.preset,
    required this.selected,
    required this.color,
    required this.ms,
  });

  final List<double> cm;
  final List<String> names;
  final bool network, taOn, ms;
  final String preset;
  final int selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final view = CarView(size);
    view.paintBody(canvas, color);
    final speakers = _speakerPositions(network);
    final tp = TextPainter(textDirection: TextDirection.ltr);

    void text(String t, Offset center, {Color? c, double fs = 10, bool box = false}) {
      tp
        ..text = TextSpan(
          text: t,
          style: TextStyle(color: c ?? color, fontSize: fs, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        )
        ..layout();
      final r = Rect.fromCenter(center: center, width: tp.width + 8, height: tp.height + 3);
      if (box) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = const Color(0xE6050608),
        );
      }
      tp.paint(canvas, r.topLeft + const Offset(4, 1.5));
    }

    if (taOn) {
      final l = _listener(preset, cm, speakers);
      final lp = view.px(l);
      canvas.save();
      canvas.clipRect(view.pxRect(CarView.bodyRect));
      // Distance arc of the selected speaker.
      final sp = view.px(speakers[selected]);
      canvas.drawCircle(
        sp,
        cm[selected] * view.scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.35),
      );
      canvas.restore();
      for (var i = 0; i < 5; i++) {
        final p = view.px(speakers[i]);
        final sel = i == selected;
        final paint = Paint()
          ..strokeWidth = sel ? 2 : 1
          ..color = color.withValues(alpha: sel ? 0.9 : 0.35);
        canvas.drawLine(lp, p, paint);
        final mid = Offset.lerp(lp, p, 0.5)!;
        text(
          ms ? (cm[i] / 34.3).toStringAsFixed(2) : cm[i].toStringAsFixed(cm[i] % 1 == 0 ? 0 : 1),
          mid,
          c: sel ? color : CarroColors.textDim,
          fs: 9,
          box: true,
        );
      }
      // Listener head.
      canvas.drawCircle(
        lp,
        18,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(lp, 9, Paint()..color = const Color(0xFF20252C));
      canvas.drawCircle(
        lp,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      // Ears/nose hint showing the facing direction (front = up).
      canvas.drawCircle(lp + const Offset(0, -9), 2, Paint()..color = color);
    } else {
      text('TA OFF', view.px(const Offset(75, 130)), c: CarroColors.textDim, fs: 13, box: true);
    }

    // Speakers.
    for (var i = 0; i < 5; i++) {
      final p = view.px(speakers[i]);
      final sel = i == selected;
      final r = i == 4 ? 13.0 : 10.0;
      if (sel) {
        canvas.drawCircle(
          p,
          r + 8,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawCircle(p, r, Paint()..color = const Color(0xFF0F1216));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 2.2 : 1.4
          ..color = sel ? color : Colors.white.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
        p,
        r * 0.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = (sel ? color : Colors.white).withValues(alpha: 0.45),
      );
      canvas.drawCircle(p, r * 0.18, Paint()..color = sel ? color : Colors.white.withValues(alpha: 0.6));
      final labelOffset = speakers[i].dx < 40
          ? const Offset(-24, 0)
          : (speakers[i].dx > 110 ? const Offset(24, 0) : Offset(0, r + 10));
      text(names[i], p + labelOffset, c: sel ? color : CarroColors.text, fs: 10);
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_TaPainter old) =>
      old.cm.length != cm.length ||
      [for (var i = 0; i < cm.length; i++) old.cm[i] != cm[i]].any((b) => b) ||
      old.network != network ||
      old.taOn != taOn ||
      old.preset != preset ||
      old.selected != selected ||
      old.color != color ||
      old.ms != ms ||
      old.names != names;
}
