import 'dart:math' as math;

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'car_view.dart';
import 'carro_theme.dart';
import 'sound_strings.dart';

String _lr(num v, {String left = 'L', String right = 'R'}) => v == 0 ? '0' : (v < 0 ? '$left${-v}' : '$right$v');

/// AUDIO menu: loudness, bass boost, ASR, SLA, subwoofer, fader/balance, sonic center
/// control, listening position, output mode, limiter, pre-amp and live meters.
class EffectsScreen extends ConsumerWidget {
  const EffectsScreen({super.key});

  static const _positions = ['OFF', 'FRONT-LEFT', 'FRONT-RIGHT', 'FRONT', 'ALL'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final sub = pr.xo[XoGroup.sub];
    final posIndex = !pr.taOn ? 0 : _positions.indexOf(pr.taPreset);

    return CarroScaffold(
      title: 'AUDIO',
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          CarroPanel(
            title: 'LIVE METERS',
            child: s.dspAvailable ? const _LiveMeters() : const CarroNoDspGraph(height: 70),
          ),
          CarroPanel(
            title: 'LOUDNESS',
            child: CarroSegmented(
              labels: loudnessNames,
              selected: pr.loudness,
              onSelected: (i) => n.update((p) => p.copyWith(loudness: i)),
            ),
          ),
          CarroPanel(
            title: 'BASS BOOST / SLA',
            child: Column(
              children: [
                CarroNumStepper(
                  label: 'BASS BOOST',
                  value: pr.bassBoost.toDouble(),
                  min: 0,
                  max: 6,
                  format: (v) => v == 0 ? 'OFF' : '+${v.toInt()}',
                  onChanged: (v) => n.update((p) => p.copyWith(bassBoost: v.toInt())),
                ),
                CarroNumStepper(
                  label: 'SLA',
                  sublabel: soundText(context, 'sla_help'),
                  value: pr.sla.toDouble(),
                  min: -4,
                  max: 4,
                  format: (v) => '${signed(v)} dB',
                  onChanged: (v) => n.update((p) => p.copyWith(sla: v.toInt())),
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'ASR · ADVANCED SOUND RETRIEVER',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(
                  labels: asrNames,
                  selected: pr.asrMode,
                  onSelected: (i) => n.update((p) => p.copyWith(asrMode: i)),
                ),
                const SizedBox(height: 8),
                Text(soundText(context, 'asr_help'), style: carroBody.copyWith(fontSize: 12)),
              ],
            ),
          ),
          CarroPanel(
            title: 'SUBWOOFER',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroToggle(
                  label: 'SUBWOOFER',
                  value: pr.subOn,
                  onChanged: (v) => n.update((p) => p.copyWith(subOn: v)),
                ),
                CarroNumStepper(
                  label: 'LEVEL',
                  enabled: pr.subOn,
                  value: sub.levelDb,
                  min: -24,
                  max: 10,
                  format: (v) => '${signed(v)} dB',
                  onChanged: (v) => n.update((p) => p.withXo(XoGroup.sub, p.xo[XoGroup.sub].copyWith(levelDb: v))),
                ),
                const SizedBox(height: 6),
                CarroSegmented(
                  labels: const ['NORMAL', 'REVERSE'],
                  enabled: pr.subOn,
                  selected: sub.phaseReverse ? 1 : 0,
                  onSelected: (i) =>
                      n.update((p) => p.withXo(XoGroup.sub, p.xo[XoGroup.sub].copyWith(phaseReverse: i == 1))),
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'FADER / BALANCE',
            trailing: Text(
              '${pr.network ? 'F --' : 'F ${_lr(pr.fader, left: 'R', right: 'F')}'}   B ${_lr(pr.balance)}',
              style: lcdStyle(watchIllumination(ref), size: 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FaderBalancePad(
                  fader: pr.fader,
                  balance: pr.balance,
                  faderEnabled: !pr.network,
                  onChanged: (f, b) => n.update((p) => p.copyWith(fader: f, balance: b)),
                ),
                if (pr.network) ...[
                  const SizedBox(height: 6),
                  Text(soundText(context, 'fader_network'), style: carroCaption.copyWith(color: CarroColors.warn)),
                ],
                const SizedBox(height: 6),
                CarroNumStepper(
                  label: 'FADER',
                  enabled: !pr.network,
                  value: pr.fader.toDouble(),
                  min: -15,
                  max: 15,
                  format: (v) => _lr(v.toInt(), left: 'R', right: 'F'),
                  onChanged: (v) => n.update((p) => p.copyWith(fader: v.toInt())),
                ),
                CarroNumStepper(
                  label: 'BALANCE',
                  value: pr.balance.toDouble(),
                  min: -15,
                  max: 15,
                  format: (v) => _lr(v.toInt()),
                  onChanged: (v) => n.update((p) => p.copyWith(balance: v.toInt())),
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'SONIC CENTER CONTROL',
            child: Column(
              children: [
                CarroSlider(
                  value: pr.scc.toDouble(),
                  min: -15,
                  max: 15,
                  step: 1,
                  origin: 0,
                  onChanged: (v) => n.update((p) => p.copyWith(scc: v.toInt())),
                ),
                CarroNumStepper(
                  label: 'POSITION',
                  value: pr.scc.toDouble(),
                  min: -15,
                  max: 15,
                  format: (v) => _lr(v.toInt()),
                  onChanged: (v) => n.update((p) => p.copyWith(scc: v.toInt())),
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'LISTENING POSITION',
            trailing: pr.taOn && pr.taPreset == 'CUSTOM'
                ? Text('CUSTOM', style: carroCaption.copyWith(color: CarroColors.warn))
                : null,
            child: CarroSegmented(
              labels: _positions,
              selected: posIndex,
              scrollable: true,
              onSelected: (i) => n.applyTaPreset(_positions[i]),
            ),
          ),
          CarroPanel(
            title: 'OUTPUT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(
                  labels: const ['CAR SPEAKERS', 'HEADPHONES'],
                  selected: pr.outputMode,
                  onSelected: (i) => n.update((p) => p.copyWith(outputMode: i)),
                ),
                const SizedBox(height: 6),
                Text(
                  soundText(context, 'output_help'),
                  style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3),
                ),
                if (pr.outputMode == 1) ...[
                  const SizedBox(height: 6),
                  CarroSliderRow(
                    label: 'CROSSFEED',
                    valueText: '${(pr.crossfeed * 100).round()}%',
                    value: pr.crossfeed,
                    min: 0,
                    max: 1,
                    step: 0.05,
                    onChanged: (v) => n.update((p) => p.copyWith(crossfeed: v)),
                  ),
                  Text(
                    soundText(context, 'crossfeed_help'),
                    style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3),
                  ),
                ],
              ],
            ),
          ),
          CarroPanel(
            title: 'LIMITER / GAIN',
            child: Column(
              children: [
                CarroToggle(
                  label: 'LIMITER',
                  value: pr.limiterOn,
                  onChanged: (v) => n.update((p) => p.copyWith(limiterOn: v)),
                ),
                CarroNumStepper(
                  label: 'CEILING',
                  enabled: pr.limiterOn,
                  value: pr.limiterCeilDb,
                  min: -6,
                  max: 0,
                  step: 0.1,
                  valueWidth: 108,
                  format: (v) => '${v.toStringAsFixed(1)} dBTP',
                  onChanged: (v) => n.update((p) => p.copyWith(limiterCeilDb: v)),
                ),
                CarroNumStepper(
                  label: 'PRE-AMP',
                  value: pr.preampDb,
                  min: -12,
                  max: 6,
                  step: 0.5,
                  format: (v) => '${signed(v, decimals: 1)} dB',
                  onChanged: (v) => n.update((p) => p.copyWith(preampDb: v)),
                ),
                CarroToggle(
                  label: 'AUTO HEADROOM',
                  subtitle: soundText(context, 'auto_headroom_help'),
                  value: pr.autoHeadroom,
                  onChanged: (v) => n.update((p) => p.copyWith(autoHeadroom: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------------------
// Fader / balance pad
// -----------------------------------------------------------------------------------------

class _FaderBalancePad extends StatefulWidget {
  const _FaderBalancePad({
    required this.fader,
    required this.balance,
    required this.faderEnabled,
    required this.onChanged,
  });

  final int fader, balance;
  final bool faderEnabled;
  final void Function(int fader, int balance) onChanged;

  @override
  State<_FaderBalancePad> createState() => _FaderBalancePadState();
}

class _FaderBalancePadState extends State<_FaderBalancePad> {
  int? _f, _b;

  void _at(Offset local, Size size) {
    final view = CarView(size);
    final cm = view.cm(local);
    const r = CarView.cabinRect;
    final b = (((cm.dx - r.left) / r.width) * 30 - 15).round().clamp(-15, 15);
    final f = widget.faderEnabled ? (15 - ((cm.dy - r.top) / r.height) * 30).round().clamp(-15, 15) : widget.fader;
    if (f == _f && b == _b) return;
    _f = f;
    _b = b;
    if (f == 0 && b == 0) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onChanged(f, b);
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              _f = widget.fader;
              _b = widget.balance;
              _at(d.localPosition, size);
            },
            onPanUpdate: (d) => _at(d.localPosition, size),
            onTapUp: (d) {
              _f = widget.fader;
              _b = widget.balance;
              _at(d.localPosition, size);
            },
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              widget.onChanged(0, 0);
            },
            child: CustomPaint(
              size: size,
              painter: _PadPainter(
                fader: widget.fader,
                balance: widget.balance,
                faderEnabled: widget.faderEnabled,
                color: c,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({required this.fader, required this.balance, required this.faderEnabled, required this.color});

  final int fader, balance;
  final bool faderEnabled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final view = CarView(size);
    view.paintBody(canvas, color);
    const r = CarView.cabinRect;
    final cabin = view.pxRect(r);

    // Grid.
    final grid = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final x = cabin.left + cabin.width * i / 6;
      final y = cabin.top + cabin.height * i / 6;
      canvas.drawLine(Offset(x, cabin.top), Offset(x, cabin.bottom), grid);
      canvas.drawLine(Offset(cabin.left, y), Offset(cabin.right, y), grid);
    }
    final axis = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cabin.center.dx, cabin.top), Offset(cabin.center.dx, cabin.bottom), axis);
    if (faderEnabled) canvas.drawLine(Offset(cabin.left, cabin.center.dy), Offset(cabin.right, cabin.center.dy), axis);

    final pos = view.px(Offset(r.left + (balance + 15) / 30 * r.width, r.top + (15 - fader) / 30 * r.height));
    canvas.drawLine(
      Offset(pos.dx, cabin.top),
      Offset(pos.dx, cabin.bottom),
      Paint()..color = color.withValues(alpha: 0.4),
    );
    canvas.drawLine(
      Offset(cabin.left, pos.dy),
      Offset(cabin.right, pos.dy),
      Paint()..color = color.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      pos,
      22,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(pos, 9, Paint()..color = color);
    canvas.drawCircle(
      pos,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.7),
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset at) {
      tp
        ..text = TextSpan(
          text: t,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        )
        ..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('FRONT', view.px(const Offset(75, -70)));
    label('REAR', view.px(const Offset(75, 312)));
    label('L', view.px(const Offset(-14, 130)));
    label('R', view.px(const Offset(164, 130)));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.fader != fader || old.balance != balance || old.faderEnabled != faderEnabled || old.color != color;
}

// -----------------------------------------------------------------------------------------
// Live meters
// -----------------------------------------------------------------------------------------

class _LiveMeters extends StatefulWidget {
  const _LiveMeters();

  @override
  State<_LiveMeters> createState() => _LiveMetersState();
}

class _LiveMetersState extends State<_LiveMeters> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _signal = _MeterSignal();
  final _numbers = ValueNotifier<DspMeters>(DspMeters.zero);
  Duration _last = Duration.zero;
  Duration _lastText = Duration.zero;

  static const _floorDb = -48.0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dtUs = (elapsed - _last).inMicroseconds;
    if (_last != Duration.zero && dtUs < 31000) return;
    final dt = _last == Duration.zero ? 1 / 30 : math.min(0.2, dtUs / 1e6);
    _last = elapsed;
    DspMeters m;
    try {
      m = CarroDsp.instance.meters();
    } catch (_) {
      _ticker.stop();
      return;
    }
    double db(double lin) => lin <= 1e-6 ? _floorDb : (20 * math.log(lin) / math.ln10).clamp(_floorDb, 6.0);
    final l = db(m.peakL), r = db(m.peakR);
    _signal.update(l, r, m.gainReductionDb.abs(), dt);
    if ((elapsed - _lastText).inMilliseconds >= 250) {
      _lastText = elapsed;
      _numbers.value = m;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _signal.dispose();
    _numbers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(value, style: lcdStyle(color ?? c, size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: carroCaption),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          child: SizedBox(
            height: 64,
            child: CustomPaint(
              painter: _MeterPainter(signal: _signal, color: c, floorDb: _floorDb),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<DspMeters>(
          valueListenable: _numbers,
          builder: (context, m, _) => Row(
            children: [
              stat(
                'CPU',
                '${(m.cpuLoad * 100).toStringAsFixed(1)}%',
                color: m.cpuLoad > 0.8 ? CarroColors.danger : null,
              ),
              stat('LATENCY', '${m.latencyMs.toStringAsFixed(1)} ms'),
              stat(
                'GR',
                '${m.gainReductionDb.abs().toStringAsFixed(1)} dB',
                color: m.gainReductionDb.abs() > 0.1 ? CarroColors.warn : null,
              ),
              stat('UNDERRUNS', '${m.underruns}', color: m.underruns > 0 ? CarroColors.warn : null),
            ],
          ),
        ),
      ],
    );
  }
}

class _MeterSignal extends ChangeNotifier {
  double l = -48, r = -48, gr = 0;
  double peakL = -48, peakR = -48;
  double _holdL = 0, _holdR = 0;

  void update(double nl, double nr, double ngr, double dt) {
    const fall = 26.0; // dB per second
    l = nl > l ? nl : math.max(nl, l - fall * dt);
    r = nr > r ? nr : math.max(nr, r - fall * dt);
    gr = ngr > gr ? ngr : math.max(ngr, gr - 20 * dt);
    if (l >= peakL) {
      peakL = l;
      _holdL = 1.0;
    } else if ((_holdL -= dt) <= 0) {
      peakL = math.max(l, peakL - 12 * dt);
    }
    if (r >= peakR) {
      peakR = r;
      _holdR = 1.0;
    } else if ((_holdR -= dt) <= 0) {
      peakR = math.max(r, peakR - 12 * dt);
    }
    notifyListeners();
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({required this.signal, required this.color, required this.floorDb}) : super(repaint: signal);

  final _MeterSignal signal;
  final Color color;
  final double floorDb;

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 26.0;
    const rowH = 14.0;
    final left = labelW, right = size.width - 4;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void text(String t, Offset at, {Color c = CarroColors.textDim}) {
      tp
        ..text = TextSpan(
          text: t,
          style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1),
        )
        ..layout();
      tp.paint(canvas, at);
    }

    double xOf(double db) => left + (db - floorDb) / (0 - floorDb) * (right - left);

    void bar(double y, double level, double peak, String name) {
      text(name, Offset(0, y + 1));
      const segW = 4.0, gap = 1.5;
      final lit = Paint()..color = color;
      final hot = Paint()..color = CarroColors.warn;
      final clip = Paint()..color = CarroColors.danger;
      final off = Paint()..color = const Color(0xFF171B21);
      for (var x = left; x + segW <= right; x += segW + gap) {
        final db = floorDb + (x - left) / (right - left) * (0 - floorDb);
        final on = db <= level;
        final p = !on ? off : (db > -3 ? clip : (db > -12 ? hot : lit));
        canvas.drawRect(Rect.fromLTWH(x, y, segW, rowH), p);
      }
      final px = xOf(peak.clamp(floorDb, 0));
      canvas.drawRect(
        Rect.fromLTWH(px - 1, y - 1, 2, rowH + 2),
        Paint()..color = peak > -0.5 ? CarroColors.danger : Colors.white,
      );
    }

    bar(0, signal.l, signal.peakL, 'L');
    bar(rowH + 4, signal.r, signal.peakR, 'R');

    // Gain reduction: 0..12 dB growing from the right.
    final y = 2 * (rowH + 4);
    text('GR', Offset(0, y));
    final grW = (signal.gr.clamp(0, 12) / 12) * (right - left);
    canvas.drawRect(Rect.fromLTRB(left, y + 2, right, y + 8), Paint()..color = const Color(0xFF171B21));
    if (grW > 0.5) canvas.drawRect(Rect.fromLTRB(right - grW, y + 2, right, y + 8), Paint()..color = CarroColors.warn);

    // Scale.
    for (final db in const [-48.0, -36.0, -24.0, -12.0, -6.0, -3.0, 0.0]) {
      final x = xOf(db);
      tp
        ..text = TextSpan(
          text: db.toStringAsFixed(0),
          style: const TextStyle(color: CarroColors.textDim, fontSize: 8),
        )
        ..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(left, right - tp.width), y + 10));
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.color != color || old.signal != signal;
}
