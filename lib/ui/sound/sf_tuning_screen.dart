import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'sound_field_screen.dart';
import 'sound_files.dart';
import 'sound_strings.dart';

/// Editable range of one [SfTableEntry] field.
class _FieldSpec {
  const _FieldSpec(this.field, this.label, this.min, this.max, this.step, this.format);

  final String field, label;
  final double min, max, step;
  final String Function(double v) format;
}

String _ms(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)} ms';
String _hz(double v) => '${hzText(v)}Hz';
String _db(double v) => '${signed(v, decimals: 1)} dB';
String _x(double v) => '×${v.toStringAsFixed(2)}';
String _m(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)} m';

const _specs = <_FieldSpec>[
  _FieldSpec('preDelayMs', 'PRE-DELAY', 0, 100, 1, _ms),
  _FieldSpec('rt60', 'RT60 (SIZE M)', 0.1, 8, 0.05, _rt),
  _FieldSpec('lowMult', 'LOW RT MULTIPLIER', 0.5, 2, 0.05, _x),
  _FieldSpec('dampHz', 'HF DAMPING', 1000, 20000, 100, _hz),
  _FieldSpec('erLevelDb', 'EARLY REFLECTIONS', -24, 6, 0.5, _db),
  _FieldSpec('lateLevelDb', 'LATE REVERB', -24, 6, 0.5, _db),
  _FieldSpec('density', 'DENSITY', 0, 1, 0.01, _pct),
  _FieldSpec('width', 'WIDTH', 0, 1.5, 0.01, _pct),
  _FieldSpec('roomW', 'ROOM WIDTH', 2, 200, 1, _m),
  _FieldSpec('roomL', 'ROOM LENGTH', 2, 200, 1, _m),
  _FieldSpec('roomH', 'ROOM HEIGHT', 2, 60, 0.5, _m),
  _FieldSpec('wetHpfHz', 'WET HPF', 20, 1000, 5, _hz),
  _FieldSpec('modDepthMs', 'MOD DEPTH', 0, 2, 0.01, _msFine),
  _FieldSpec('modRateHz', 'MOD RATE', 0, 3, 0.01, _rate),
  _FieldSpec('wetLpfHz', 'WET LPF', 2000, 20000, 100, _hz),
];

String _rt(double v) => '${v.toStringAsFixed(2)} s';
String _pct(double v) => '${(v * 100).round()}%';
String _msFine(double v) => '${v.toStringAsFixed(2)} ms';
String _rate(double v) => '${v.toStringAsFixed(2)} Hz';

/// TUNE: edits the per-mode algorithmic Sound Field table, with JSON import / export.
class SfTuningScreen extends ConsumerStatefulWidget {
  const SfTuningScreen({super.key});

  @override
  ConsumerState<SfTuningScreen> createState() => _SfTuningScreenState();
}

class _SfTuningScreenState extends ConsumerState<SfTuningScreen> {
  int? _mode;

  Future<void> _export() async {
    final n = ref.read(soundProvider.notifier);
    try {
      final path = await n.exportSfTable();
      if (!mounted) return;
      await shareLocalFile(context, path, subject: 'CarroTube Sound Field table');
    } catch (e) {
      if (!mounted) return;
      showCarroSnack(context, soundText(context, 'error_generic').replaceAll('{error}', '$e'), error: true);
    }
  }

  Future<void> _import() async {
    final n = ref.read(soundProvider.notifier);
    try {
      final path = await pickLocalFile(const ['json']);
      if (path == null) return;
      final ok = await n.importSfTable(path);
      if (!mounted) return;
      showCarroSnack(context, soundText(context, ok ? 'sf_import_ok' : 'sf_import_fail'), error: !ok);
    } catch (e) {
      if (!mounted) return;
      showCarroSnack(context, soundText(context, 'error_generic').replaceAll('{error}', '$e'), error: true);
    }
  }

  Future<void> _reset() async {
    final n = ref.read(soundProvider.notifier);
    final ok = await showCarroConfirm(
      context,
      title: 'RESET',
      message: soundText(context, 'sf_reset_confirm'),
      confirm: 'RESET',
    );
    if (ok) await n.resetSfTable();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;
    final n = ref.read(soundProvider.notifier);
    final mode = (_mode ?? (pr.sfMode > 0 ? pr.sfMode : 1)).clamp(1, 7);
    final entry = s.sfTable[mode];
    final auditioning = pr.sfEngine == 0 && pr.sfMode == mode;

    return CarroScaffold(
      title: 'SOUND FIELD TUNE',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => switch (v) {
            'export' => _export(),
            'import' => _import(),
            _ => _reset(),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('EXPORT JSON')),
            PopupMenuItem(value: 'import', child: Text('IMPORT JSON')),
            PopupMenuItem(value: 'reset', child: Text('RESET TO DEFAULTS')),
          ],
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          CarroPanel(
            title: 'MODE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarroSegmented(
                  labels: soundFieldModes.sublist(1),
                  selected: mode - 1,
                  scrollable: true,
                  onSelected: (i) => setState(() => _mode = i + 1),
                ),
                const SizedBox(height: 8),
                Text(
                  soundText(context, 'sf_tune_help'),
                  style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3, height: 1.35),
                ),
                const SizedBox(height: 8),
                CarroButton(
                  label: auditioning ? 'AUDITIONING ${soundFieldModes[mode]}' : 'AUDITION ${soundFieldModes[mode]}',
                  icon: Icons.hearing,
                  filled: auditioning,
                  onPressed: auditioning ? null : () => n.update((p) => p.copyWith(sfEngine: 0, sfMode: mode)),
                ),
              ],
            ),
          ),
          if (auditioning)
            CarroPanel(
              title: 'DECAY',
              child: s.dspAvailable
                  ? LiveDecayGraph(height: 120, emptyText: soundText(context, 'decay_none'))
                  : const CarroNoDspGraph(),
            ),
          if (entry == null)
            CarroPanel(child: Text(soundText(context, 'sf_import_fail'), style: carroBody))
          else
            CarroPanel(
              title: soundFieldModes[mode],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final spec in _specs)
                    Builder(
                      builder: (context) {
                        final v = entry.values[SfTableEntry.fields.indexOf(spec.field)];
                        return CarroSliderRow(
                          label: spec.label,
                          valueText: spec.format(v),
                          value: v.clamp(spec.min, spec.max),
                          min: spec.min,
                          max: spec.max,
                          step: spec.step,
                          onChanged: (nv) => n.setSfTable(mode, entry.withField(spec.field, nv)),
                        );
                      },
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: CarroButton(label: 'EXPORT', icon: Icons.ios_share, onPressed: _export),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CarroButton(label: 'IMPORT', icon: Icons.file_open, onPressed: _import),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CarroButton(label: 'RESET', icon: Icons.restart_alt, onPressed: _reset),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
