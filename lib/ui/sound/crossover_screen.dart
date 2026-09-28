import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'crossover_graph.dart';
import 'sound_strings.dart';

/// CROSSOVER: Standard (FRONT HPF, REAR HPF, SUBWOOFER LPF) or NETWORK 3-way
/// (HIGH HPF, MID HPF+LPF, SUBWOOFER LPF) with the engine's real filter responses.
class CrossoverScreen extends ConsumerStatefulWidget {
  const CrossoverScreen({super.key});

  @override
  ConsumerState<CrossoverScreen> createState() => _CrossoverScreenState();
}

class _CrossoverScreenState extends ConsumerState<CrossoverScreen> {
  int _sel = 0;

  static final List<double> _freqs = CrossoverGraph.logFreqs(200);

  static const _standard = [XoGroup.front, XoGroup.rear, XoGroup.sub];
  static const _network = [XoGroup.high, XoGroup.mid, XoGroup.sub];

  static String groupName(int g) => switch (g) {
    XoGroup.front => 'FRONT',
    XoGroup.rear => 'REAR',
    XoGroup.sub => 'SUBWOOFER',
    XoGroup.high => 'HIGH',
    XoGroup.mid => 'MID',
    _ => 'CH $g',
  };

  static bool _hasHpf(int g) => g != XoGroup.sub;
  static bool _hasLpf(int g) => g == XoGroup.sub || g == XoGroup.mid;

  bool _lrAllowed(int g, XoSettings x) {
    final slopes = <int>[if (_hasHpf(g) && x.hpfOn) x.hpfSlope, if (_hasLpf(g) && x.lpfOn) x.lpfSlope];
    return slopes.every((s) => s % 12 == 0);
  }

  void _edit(int g, XoSettings Function(XoSettings x) f) {
    ref.read(soundProvider.notifier).update((p) {
      var x = f(p.xo[g]);
      if (x.linkwitzRiley && !_lrAllowed(g, x)) x = x.copyWith(linkwitzRiley: false);
      return p.withXo(g, x);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final groups = pr.network ? _network : _standard;
    final sel = _sel.clamp(0, groups.length - 1);
    final g = groups[sel];
    final x = pr.xo[g];
    final colors = channelColors(watchIllumination(ref));

    final curves = <XoCurve>[];
    if (s.dspAvailable) {
      try {
        final dsp = CarroDsp.instance;
        for (var i = 0; i < groups.length; i++) {
          final gi = groups[i];
          if (gi == XoGroup.sub && !pr.subOn) continue;
          final db = dsp.response(Curve.group(gi), _freqs);
          curves.add(
            XoCurve(label: groupName(gi), color: colors[i], db: db, selected: i == sel, muted: pr.xo[gi].mute),
          );
        }
      } catch (_) {
        curves.clear();
      }
    }

    return CarroScaffold(
      title: 'CROSSOVER',
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          if (!s.dspAvailable) const CarroDspUnavailable(compact: true),
          CarroPanel(
            title: 'SPEAKER MODE',
            child: CarroSegmented(
              labels: const ['STANDARD', 'NETWORK 3-WAY'],
              selected: pr.network ? 1 : 0,
              onSelected: (i) => n.update((p) => p.copyWith(network: i == 1)),
            ),
          ),
          CarroPanel(
            title: 'RESPONSE',
            padding: const EdgeInsets.fromLTRB(6, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.dspAvailable)
                  CrossoverGraph(freqs: _freqs, curves: curves)
                else
                  const CarroNoDspGraph(height: 210),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 3,
                            color: (groups[i] == XoGroup.sub && !pr.subOn) || pr.xo[groups[i]].mute
                                ? colors[i].withValues(alpha: 0.3)
                                : colors[i],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            groupName(groups[i]) + (groups[i] == XoGroup.sub && !pr.subOn ? ' (OFF)' : ''),
                            style: carroCaption.copyWith(color: i == sel ? colors[i] : CarroColors.textDim),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          CarroPanel(
            title: 'CHANNEL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(
                  labels: [for (final gi in groups) groupName(gi)],
                  selected: sel,
                  onSelected: (i) => setState(() => _sel = i),
                ),
                const SizedBox(height: 6),
                Text(
                  soundText(context, 'xo_help'),
                  style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          if (g == XoGroup.sub)
            CarroPanel(
              title: 'SUBWOOFER OUTPUT',
              child: CarroToggle(
                label: 'SUBWOOFER',
                value: pr.subOn,
                onChanged: (v) => n.update((p) => p.copyWith(subOn: v)),
              ),
            ),
          if (_hasHpf(g))
            _FilterPanel(
              title: '${groupName(g)} HPF',
              on: x.hpfOn,
              hz: x.hpfHz,
              slope: x.hpfSlope,
              onToggle: (v) => _edit(g, (x) => x.copyWith(hpfOn: v)),
              onHz: (v) => _edit(g, (x) => x.copyWith(hpfHz: v)),
              onSlope: (v) => _edit(g, (x) => x.copyWith(hpfSlope: v)),
            ),
          if (_hasLpf(g))
            _FilterPanel(
              title: '${groupName(g)} LPF',
              on: x.lpfOn,
              hz: x.lpfHz,
              slope: x.lpfSlope,
              onToggle: (v) => _edit(g, (x) => x.copyWith(lpfOn: v)),
              onHz: (v) => _edit(g, (x) => x.copyWith(lpfHz: v)),
              onSlope: (v) => _edit(g, (x) => x.copyWith(lpfSlope: v)),
            ),
          CarroPanel(
            title: 'FILTER TYPE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(
                  labels: const ['LINKWITZ-RILEY', 'BUTTERWORTH'],
                  selected: x.linkwitzRiley ? 0 : 1,
                  disabled: _lrAllowed(g, x) ? const {} : const {0},
                  onSelected: (i) => _edit(g, (x) => x.copyWith(linkwitzRiley: i == 0)),
                ),
                if (!_lrAllowed(g, x)) ...[
                  const SizedBox(height: 6),
                  Text(
                    soundText(context, 'xo_lr_note'),
                    style: carroCaption.copyWith(
                      color: CarroColors.warn,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CarroPanel(
            title: '${groupName(g)} LEVEL / PHASE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroNumStepper(
                  label: 'LEVEL',
                  value: x.levelDb,
                  min: -24,
                  max: 10,
                  format: (v) => '${signed(v)} dB',
                  onChanged: (v) => _edit(g, (x) => x.copyWith(levelDb: v)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'PHASE',
                        style: TextStyle(
                          color: CarroColors.text,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: CarroSegmented(
                        dense: true,
                        labels: const ['NORMAL', 'REVERSE'],
                        selected: x.phaseReverse ? 1 : 0,
                        onSelected: (i) => _edit(g, (x) => x.copyWith(phaseReverse: i == 1)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                CarroToggle(
                  label: 'MUTE',
                  onText: 'MUTE',
                  offText: 'OFF',
                  value: x.mute,
                  onChanged: (v) => _edit(g, (x) => x.copyWith(mute: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.title,
    required this.on,
    required this.hz,
    required this.slope,
    required this.onToggle,
    required this.onHz,
    required this.onSlope,
  });

  final String title;
  final bool on;
  final double hz;
  final int slope;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onHz;
  final ValueChanged<int> onSlope;

  int get _index {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < crossoverFreqs.length; i++) {
      final d = (crossoverFreqs[i] - hz).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final i = _index;
    return CarroPanel(
      title: title,
      glow: on,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CarroToggle(label: 'FILTER', value: on, onChanged: onToggle),
          CarroValueStepper(
            label: 'FREQUENCY',
            enabled: on,
            value: '${hzText(crossoverFreqs[i])}Hz',
            valueWidth: 100,
            onDecrement: i > 0 ? () => onHz(crossoverFreqs[i - 1]) : null,
            onIncrement: i < crossoverFreqs.length - 1 ? () => onHz(crossoverFreqs[i + 1]) : null,
          ),
          const SizedBox(height: 6),
          Text('SLOPE  dB/oct', style: carroCaption),
          const SizedBox(height: 6),
          CarroSegmented(
            dense: true,
            enabled: on,
            labels: [for (final s in crossoverSlopes) '-$s'],
            selected: crossoverSlopes.indexOf(slope),
            onSelected: (k) => onSlope(crossoverSlopes[k]),
          ),
        ],
      ),
    );
  }
}
