import 'dart:async';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'sound_field_screen.dart';
import 'sound_files.dart';
import 'sound_strings.dart';

/// IR CAPTURE: guided wizard that measures the real head unit's Sound Field with sine
/// sweeps and turns it into a convolution IR, plus the IR library (import / assign / delete).
class IrCaptureScreen extends StatefulWidget {
  const IrCaptureScreen({super.key, this.initialMode, this.initialSize, this.initialTab = 0});

  final int? initialMode;
  final int? initialSize;

  /// 0 = capture wizard, 1 = IR library.
  final int initialTab;

  @override
  State<IrCaptureScreen> createState() => _IrCaptureScreenState();
}

class _IrCaptureScreenState extends State<IrCaptureScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CarroScaffold(
      title: 'IR CAPTURE',
      body: Builder(
        builder: (context) {
          final c = CarroIllumination.of(context);
          return Column(
            children: [
              TabBar(
                controller: _tabs,
                indicatorColor: c,
                labelColor: c,
                unselectedLabelColor: CarroColors.textDim,
                dividerColor: CarroColors.border,
                labelStyle: lcdStyle(c, size: 13, weight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.4),
                tabs: const [
                  Tab(text: 'CAPTURE WIZARD'),
                  Tab(text: 'IR LIBRARY'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _CaptureWizard(initialMode: widget.initialMode, initialSize: widget.initialSize),
                    const _IrLibraryTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------------------
// Wizard
// -----------------------------------------------------------------------------------------

class _CaptureWizard extends ConsumerStatefulWidget {
  const _CaptureWizard({this.initialMode, this.initialSize});

  final int? initialMode;
  final int? initialSize;

  @override
  ConsumerState<_CaptureWizard> createState() => _CaptureWizardState();
}

class _CaptureWizardState extends ConsumerState<_CaptureWizard> with AutomaticKeepAliveClientMixin {
  static const _sweepSeconds = 10.0;
  static const _tailSeconds = 4.0;
  static const _titles = ['wiz_1_title', 'wiz_2_title', 'wiz_3_title', 'wiz_4_title', 'wiz_5_title', 'wiz_6_title'];

  int _step = 0;
  late int _mode;
  late int _size;
  int _method = 0;

  Map<String, Object?>? _route;
  String? _routeError;
  bool? _mic;
  bool _checkingRoute = false;

  final Map<int, Map<String, Object?>> _captures = {};
  int? _capturing;
  double _elapsed = 0;
  Timer? _timer;
  String? _captureError;

  bool _processing = false;
  String? _irPath;
  int? _irFrames;
  double _irRate = 48000;
  String? _processError;

  bool _saving = false;
  late final TextEditingController _name = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final pr = ref.read(soundProvider).profile;
    _mode = (widget.initialMode ?? (pr.sfMode > 0 ? pr.sfMode : 3)).clamp(1, 7);
    _size = (widget.initialSize ?? pr.sfSize).clamp(0, 2);
    _name.text = _defaultName();
  }

  String _defaultName() => '${soundFieldModes[_mode]} ${sizeNames[_size]} capture';

  @override
  void dispose() {
    _timer?.cancel();
    if (_capturing != null) {
      IrCaptureApi.cancel().catchError((Object _) {});
    }
    _name.dispose();
    super.dispose();
  }

  String _t(String key) => soundText(context, key);

  String _err(Object e) => e is PlatformException
      ? (e.message ?? e.code)
      : (e is MissingPluginException ? 'not supported on this platform' : '$e');

  bool get _canNext => switch (_step) {
    3 => _captures.containsKey(0) && _captures.containsKey(1) && _capturing == null,
    4 => _irPath != null && !_processing,
    5 => false,
    _ => true,
  };

  void _goTo(int step) {
    if (step < 0 || step > 5) return;
    HapticFeedback.selectionClick();
    setState(() => _step = step);
    if (step == 2 && _route == null && !_checkingRoute) _checkRoute();
    if (step == 4 && _irPath == null && !_processing) _process();
  }

  Future<void> _checkRoute() async {
    setState(() {
      _checkingRoute = true;
      _routeError = null;
    });
    try {
      final r = await IrCaptureApi.route();
      if (!mounted) return;
      setState(() => _route = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _routeError = _err(e));
    } finally {
      if (mounted) setState(() => _checkingRoute = false);
    }
  }

  Future<void> _requestMic() async {
    try {
      final ok = await IrCaptureApi.requestMicrophone();
      if (!mounted) return;
      setState(() => _mic = ok);
      if (ok) await _checkRoute();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mic = false;
        _routeError = _err(e);
      });
    }
  }

  Future<void> _capture(int channel) async {
    if (_capturing != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _capturing = channel;
      _elapsed = 0;
      _captureError = null;
    });
    final sw = Stopwatch()..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _elapsed = sw.elapsedMilliseconds / 1000);
    });
    try {
      final r = await IrCaptureApi.capture(channel: channel, sweepSeconds: _sweepSeconds, tailSeconds: _tailSeconds);
      final path = r['path'];
      if (path is! String || path.isEmpty) throw StateError('no recording returned');
      _captures[channel] = r;
      // A new capture invalidates a previously built IR.
      _irPath = null;
      _irFrames = null;
      _processError = null;
    } catch (e) {
      _captureError = _t('wiz_capture_failed').replaceAll('{error}', _err(e));
    } finally {
      _timer?.cancel();
      _timer = null;
      sw.stop();
      if (mounted) setState(() => _capturing = null);
    }
  }

  Future<void> _cancelCapture() async {
    try {
      await IrCaptureApi.cancel();
    } catch (_) {
      // The capture future reports the outcome.
    }
  }

  Future<void> _process() async {
    final l = _captures[0], r = _captures[1];
    if (l == null || r == null) return;
    if (!ref.read(soundProvider).dspAvailable) {
      setState(() => _processError = _t('dsp_missing_title'));
      return;
    }
    setState(() {
      _processing = true;
      _processError = null;
    });
    try {
      final tmp = await getTemporaryDirectory();
      final out = p.join(tmp.path, 'ir_capture.wav');
      final rate = (l['sampleRate'] as num?)?.toDouble() ?? 48000;
      final rc = await CarroDsp.buildIrFromCaptures(
        recLeft: l['path']! as String,
        recRight: r['path']! as String,
        outWav: out,
        sweepSampleRate: rate,
        sweepSeconds: _sweepSeconds,
        maxIrSeconds: 6,
      );
      if (!mounted) return;
      setState(() {
        if (rc > 0) {
          _irPath = out;
          _irFrames = rc;
          _irRate = rate;
        } else {
          _processError = CarroError.describe(rc);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _processError = _err(e));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    final path = _irPath;
    if (path == null || _saving) return;
    final n = ref.read(soundProvider.notifier);
    final name = _name.text.trim().isEmpty ? _defaultName() : _name.text.trim();
    setState(() => _saving = true);
    try {
      final entry = await n.addIr(path, name: name, source: 'capture');
      await n.assignIr(_mode, _size, entry.path);
      n.update((p) => p.copyWith(sfEngine: 1, sfMode: _mode, sfSize: _size));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showCarroSnack(context, _t('ir_saved').replaceAll('{slot}', slotName(_mode, _size)));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showCarroSnack(context, _t('error_generic').replaceAll('{error}', _err(e)), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final busy = _capturing != null || _processing || _saving;
    return Column(
      children: [
        _StepHeader(step: _step, count: 6, title: _t(_titles[_step]), onTap: busy ? null : _goTo),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            children: [
              switch (_step) {
                0 => _prepare(),
                1 => _connections(),
                2 => _routeStep(),
                3 => _captureStep(),
                4 => _processStep(),
                _ => _saveStep(),
              },
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: CarroButton(
                    label: 'BACK',
                    icon: Icons.chevron_left,
                    onPressed: _step > 0 && !busy ? () => _goTo(_step - 1) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _step == 5
                      ? CarroButton(
                          label: 'SAVE & ASSIGN',
                          icon: Icons.save,
                          filled: true,
                          onPressed: _irPath != null && !busy ? _save : null,
                        )
                      : CarroButton(
                          label: 'NEXT',
                          icon: Icons.chevron_right,
                          filled: true,
                          onPressed: _canNext && !busy ? () => _goTo(_step + 1) : null,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- step 1 -----------------------------------------------------------------------------
  Widget _prepare() {
    return Column(
      children: [
        CarroPanel(
          title: 'HEAD UNIT SETUP',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_t('wiz_1_body'), style: carroBody),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag('EQ FLAT'),
                  _Tag('LOUDNESS OFF'),
                  _Tag('BASS BOOST 0'),
                  _Tag('ASR OFF'),
                  _Tag('SLA 0'),
                  _Tag('TA OFF'),
                  _Tag('HPF/LPF OFF'),
                  _Tag('F/B CENTER'),
                ],
              ),
              const SizedBox(height: 10),
              Text(_t('wiz_1_level'), style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3)),
            ],
          ),
        ),
        CarroPanel(
          title: 'TARGET SLOT',
          glow: true,
          child: _SlotPicker(
            mode: _mode,
            size: _size,
            onChanged: (m, s) {
              final wasDefault = _name.text == _defaultName();
              setState(() {
                _mode = m;
                _size = s;
                if (wasDefault) _name.text = _defaultName();
              });
            },
          ),
        ),
      ],
    );
  }

  // ---- step 2 -----------------------------------------------------------------------------
  Widget _connections() {
    final chains = <List<String>>[
      [
        'PHONE',
        'USB',
        'AUDIO INTERFACE',
        'OUT L/R  →  AUX IN',
        'HEAD UNIT',
        'RCA PRE-OUT  →  IN L/R',
        'AUDIO INTERFACE',
        'USB',
        'PHONE (RECORD)', //
      ],
      [
        'PHONE',
        'BLUETOOTH / USB',
        'HEAD UNIT',
        'RCA PRE-OUT  →  IN L/R',
        'AUDIO INTERFACE',
        'USB',
        'PHONE (RECORD)', //
      ],
      [
        'PHONE',
        'BLUETOOTH / USB / AUX',
        'HEAD UNIT',
        'SPEAKERS',
        'CAR CABIN',
        'MIC AT DRIVER\'S HEAD',
        'PHONE (RECORD)', //
      ],
    ];
    final texts = ['wiz_2_usb', 'wiz_2_bt', 'wiz_2_mic'];
    return Column(
      children: [
        CarroPanel(
          title: 'METHOD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarroSegmented(
                labels: const ['USB INTERFACE', 'BT/USB + IN', 'PHONE MIC'],
                selected: _method,
                onSelected: (i) => setState(() => _method = i),
              ),
              const SizedBox(height: 10),
              Text(_t(texts[_method]), style: carroBody),
            ],
          ),
        ),
        CarroPanel(
          title: _method == 0 ? 'RECOMMENDED WIRING' : 'WIRING',
          child: _Chain(items: chains[_method]),
        ),
      ],
    );
  }

  // ---- step 3 -----------------------------------------------------------------------------
  Widget _routeStep() {
    final c = CarroIllumination.of(context);
    String v(String k) {
      final x = _route?[k];
      if (x == null) return '—';
      if (x is num && k == 'sampleRate') return '${x.round()} Hz';
      return '$x';
    }

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: carroCaption)),
          Expanded(child: Text(value, style: lcdStyle(c, size: 13))),
        ],
      ),
    );

    return Column(
      children: [
        CarroPanel(
          title: 'AUDIO ROUTE',
          trailing: _checkingRoute
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_t('wiz_3_body'), style: carroBody),
              const SizedBox(height: 10),
              row('INPUT', v('input')),
              row('INPUT TYPE', v('inputType')),
              row('OUTPUT', v('output')),
              row('SAMPLE RATE', v('sampleRate')),
              if (_routeError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _routeError!,
                  style: carroCaption.copyWith(color: CarroColors.danger, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 10),
              CarroButton(
                label: 'REFRESH ROUTE',
                icon: Icons.refresh,
                dense: true,
                onPressed: _checkingRoute ? null : _checkRoute,
              ),
            ],
          ),
        ),
        CarroPanel(
          title: 'MICROPHONE / INPUT PERMISSION',
          glow: _mic == true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mic != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _t(_mic! ? 'wiz_3_granted' : 'wiz_3_denied'),
                    style: carroBody.copyWith(color: _mic! ? c : CarroColors.danger),
                  ),
                ),
              CarroButton(label: 'ALLOW MICROPHONE', icon: Icons.mic, filled: _mic != true, onPressed: _requestMic),
            ],
          ),
        ),
      ],
    );
  }

  // ---- step 4 -----------------------------------------------------------------------------
  Widget _captureStep() {
    const total = _sweepSeconds + _tailSeconds;
    Widget captureCard(int ch, String label) {
      final r = _captures[ch];
      final running = _capturing == ch;
      final peak = (r?['peakDb'] as num?)?.toDouble();
      final (String levelKey, Color levelColor) = peak == null
          ? ('', CarroColors.textDim)
          : (peak < -40
                ? ('wiz_4_level_low', CarroColors.warn)
                : (peak > -1
                      ? ('wiz_4_level_clip', CarroColors.danger)
                      : ('wiz_4_level_ok', CarroIllumination.of(context))));
      return CarroPanel(
        title: '$label SWEEP',
        glow: running || r != null,
        trailing: r != null && !running ? const Icon(Icons.check_circle, size: 16, color: CarroColors.text) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (running) ...[
              LinearProgressIndicator(value: (_elapsed / total).clamp(0.0, 1.0), minHeight: 6),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _elapsed < _sweepSeconds ? 'SWEEP 20 Hz → 20 kHz' : 'RECORDING TAIL',
                      style: carroCaption,
                    ),
                  ),
                  CarroLcdText('${(total - _elapsed).clamp(0, total).ceil()} s', size: 18, weight: FontWeight.w800),
                ],
              ),
              const SizedBox(height: 8),
              CarroButton(
                label: 'CANCEL',
                icon: Icons.stop,
                dense: true,
                color: CarroColors.danger,
                onPressed: _cancelCapture,
              ),
            ] else ...[
              if (r != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (r['sampleRate'] is num) '${(r['sampleRate']! as num).round()} Hz',
                          if (r['channels'] is num) '${(r['channels']! as num).toInt()} CH',
                        ].join(' · '),
                        style: carroCaption,
                      ),
                    ),
                    if (peak != null) CarroLcdText('PEAK ${peak.toStringAsFixed(1)} dBFS', size: 12, color: levelColor),
                  ],
                ),
                if (levelKey.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _t(levelKey),
                    style: carroCaption.copyWith(color: levelColor, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              CarroButton(
                label: r == null ? 'CAPTURE $label' : 'RECAPTURE $label',
                icon: Icons.fiber_manual_record,
                filled: r == null,
                onPressed: _capturing == null && (ch == 0 || _captures.containsKey(0)) ? () => _capture(ch) : null,
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        CarroPanel(
          title: 'LEVEL CHECK',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_t('wiz_4_body'), style: carroBody),
              if (_method == 2) ...[
                const SizedBox(height: 6),
                Text(_t('wiz_2_mic'), style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3)),
              ],
            ],
          ),
        ),
        captureCard(0, 'LEFT'),
        captureCard(1, 'RIGHT'),
        if (_captureError != null)
          CarroPanel(
            child: Text(_captureError!, style: carroBody.copyWith(color: CarroColors.danger)),
          ),
        if (!(_captures.containsKey(0) && _captures.containsKey(1)))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              _t('wiz_need_both'),
              style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3),
            ),
          ),
      ],
    );
  }

  // ---- step 5 -----------------------------------------------------------------------------
  Widget _processStep() {
    final dspOk = ref.watch(soundProvider.select((s) => s.dspAvailable));
    if (!dspOk) return const CarroDspUnavailable();
    final c = CarroIllumination.of(context);
    return CarroPanel(
      title: 'DECONVOLUTION',
      glow: _irPath != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('wiz_5_body'), style: carroBody),
          const SizedBox(height: 12),
          if (_processing) ...[
            const LinearProgressIndicator(minHeight: 6),
            const SizedBox(height: 8),
            Text('PROCESSING…', style: lcdStyle(c, size: 13)),
          ] else if (_processError != null) ...[
            Text(_processError!, style: carroBody.copyWith(color: CarroColors.danger)),
            const SizedBox(height: 10),
            CarroButton(label: 'RETRY', icon: Icons.refresh, onPressed: _process),
          ] else if (_irPath != null) ...[
            Row(
              children: [
                Icon(Icons.check_circle, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_t('wiz_5_done'), style: carroBody.copyWith(color: c)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_irFrames ?? 0} FRAMES · ${((_irFrames ?? 0) / _irRate).toStringAsFixed(2)} s · ${_irRate.round()} Hz',
              style: lcdStyle(c, size: 12),
            ),
            const SizedBox(height: 10),
            CarroButton(label: 'BUILD AGAIN', icon: Icons.refresh, dense: true, onPressed: _process),
          ] else
            CarroButton(label: 'BUILD IR', icon: Icons.auto_fix_high, filled: true, onPressed: _process),
        ],
      ),
    );
  }

  // ---- step 6 -----------------------------------------------------------------------------
  Widget _saveStep() {
    return Column(
      children: [
        CarroPanel(
          title: 'NAME',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_t('wiz_6_body'), style: carroBody),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: 48,
                style: const TextStyle(color: CarroColors.text, letterSpacing: 1),
                decoration: InputDecoration(labelText: _t('ir_name')),
              ),
            ],
          ),
        ),
        CarroPanel(
          title: 'SLOT',
          glow: true,
          child: _SlotPicker(
            mode: _mode,
            size: _size,
            onChanged: (m, s) => setState(() {
              _mode = m;
              _size = s;
            }),
          ),
        ),
        if (_saving)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: LinearProgressIndicator(minHeight: 3)),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.count, required this.title, required this.onTap});

  final int step, count;
  final String title;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(height: 2, color: i <= step ? c.withValues(alpha: 0.7) : CarroColors.border),
                  ),
                GestureDetector(
                  onTap: onTap != null && i < step ? () => onTap!(i) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < step ? c : (i == step ? c.withValues(alpha: 0.18) : CarroColors.inset),
                      border: Border.all(color: i <= step ? c : CarroColors.border, width: 1.5),
                      boxShadow: i == step ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)] : null,
                    ),
                    child: i < step
                        ? const Icon(Icons.check, size: 15, color: Colors.black)
                        : Text(
                            '${i + 1}',
                            style: lcdStyle(i == step ? c : CarroColors.textDim, size: 12, glow: i == step),
                          ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text('STEP ${step + 1}/$count', style: carroCaption.copyWith(color: c.withValues(alpha: 0.8))),
          const SizedBox(height: 2),
          Text(title.toUpperCase(), style: lcdStyle(c, size: 15, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: lcdStyle(c, size: 10.5, glow: false, spacing: 1)),
    );
  }
}

/// Vertical signal chain: node, link, node, link, node ...
class _Chain extends StatelessWidget {
  const _Chain({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          if (i.isEven)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              decoration: BoxDecoration(
                color: CarroColors.inset,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.withValues(alpha: 0.5)),
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 8)],
              ),
              child: Text(
                items[i],
                textAlign: TextAlign.center,
                style: lcdStyle(c, size: 12.5, weight: FontWeight.w700),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                children: [
                  Icon(Icons.arrow_downward, size: 16, color: c.withValues(alpha: 0.7)),
                  Text(items[i], style: carroCaption.copyWith(letterSpacing: 0.8)),
                ],
              ),
            ),
      ],
    );
  }
}

/// Sound Field mode (1..7) + size (S/M/L) selector.
class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.mode, required this.size, required this.onChanged});

  final int mode, size;
  final void Function(int mode, int size) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SOUND FIELD MODE', style: carroCaption),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 2 * 6) / 3;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var m = 1; m < soundFieldModes.length; m++)
                  SizedBox(
                    width: w,
                    child: CarroSegmented(
                      dense: true,
                      labels: [soundFieldModes[m]],
                      selected: m == mode ? 0 : -1,
                      onSelected: (_) => onChanged(m, size),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text('SIZE', style: carroCaption),
        const SizedBox(height: 6),
        CarroSegmented(labels: sizeNames, selected: size, onSelected: (s) => onChanged(mode, s)),
      ],
    );
  }
}

/// Dialog: choose the Sound Field slot for an IR.
Future<(int, int)?> _pickSlot(BuildContext context, {required int mode, required int size}) {
  return showDialog<(int, int)>(
    context: context,
    builder: (_) => _SlotDialog(mode: mode, size: size),
  );
}

class _SlotDialog extends StatefulWidget {
  const _SlotDialog({required this.mode, required this.size});

  final int mode, size;

  @override
  State<_SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends State<_SlotDialog> {
  late int _mode = widget.mode.clamp(1, 7);
  late int _size = widget.size.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ASSIGN IR'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: _SlotPicker(
            mode: _mode,
            size: _size,
            onChanged: (m, s) => setState(() {
              _mode = m;
              _size = s;
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel.toUpperCase()),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop((_mode, _size)), child: const Text('ASSIGN')),
      ],
    );
  }
}

class _ImportResult {
  const _ImportResult(this.name, this.slot);

  final String name;
  final (int, int)? slot;
}

// -----------------------------------------------------------------------------------------
// IR library
// -----------------------------------------------------------------------------------------

class _IrLibraryTab extends ConsumerStatefulWidget {
  const _IrLibraryTab();

  @override
  ConsumerState<_IrLibraryTab> createState() => _IrLibraryTabState();
}

class _IrLibraryTabState extends ConsumerState<_IrLibraryTab> with AutomaticKeepAliveClientMixin {
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _import() async {
    if (_busy) return;
    final n = ref.read(soundProvider.notifier);
    final pr = ref.read(soundProvider).profile;
    setState(() => _busy = true);
    try {
      final path = await pickLocalFile(const ['wav']);
      if (path == null || !mounted) return;
      final initialName = p.basenameWithoutExtension(path).replaceAll(RegExp(r'^import_\d+_'), '');
      final res = await showDialog<_ImportResult>(
        context: context,
        builder: (_) => _ImportDialog(initialName: initialName, mode: pr.sfMode > 0 ? pr.sfMode : 3, size: pr.sfSize),
      );
      if (res == null) return;
      final entry = await n.addIr(path, name: res.name, source: 'import');
      final slot = res.slot;
      if (slot != null) await n.assignIr(slot.$1, slot.$2, entry.path);
      if (!mounted) return;
      showCarroSnack(
        context,
        slot == null ? res.name : soundText(context, 'ir_assigned').replaceAll('{slot}', slotName(slot.$1, slot.$2)),
      );
    } catch (e) {
      if (mounted) {
        showCarroSnack(context, soundText(context, 'error_generic').replaceAll('{error}', '$e'), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(IrEntry e) async {
    final n = ref.read(soundProvider.notifier);
    final pr = ref.read(soundProvider).profile;
    final slot = await _pickSlot(context, mode: pr.sfMode > 0 ? pr.sfMode : 3, size: pr.sfSize);
    if (slot == null) return;
    await n.assignIr(slot.$1, slot.$2, e.path);
    if (!mounted) return;
    showCarroSnack(context, soundText(context, 'ir_assigned').replaceAll('{slot}', slotName(slot.$1, slot.$2)));
  }

  Future<void> _delete(IrEntry e) async {
    final n = ref.read(soundProvider.notifier);
    final ok = await showCarroConfirm(
      context,
      title: 'DELETE IR',
      message: soundText(context, 'confirm_delete').replaceAll('{name}', e.name),
      confirm: 'DELETE',
    );
    if (ok) await n.removeIr(e);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = ref.watch(soundProvider);
    final c = CarroIllumination.of(context);
    List<String> slotsOf(IrEntry e) {
      final out = <String>[];
      for (final kv in s.irAssignments.entries) {
        if (kv.value != e.path) continue;
        final parts = kv.key.split('_');
        final m = int.tryParse(parts.first), z = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (m != null && z != null) out.add(slotName(m, z));
      }
      return out..sort();
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        CarroPanel(
          title: 'IMPORT IR WAV (REW)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(soundText(context, 'ir_import_help'), style: carroBody),
              const SizedBox(height: 10),
              CarroButton(label: 'IMPORT WAV', icon: Icons.file_open, filled: true, onPressed: _busy ? null : _import),
              if (_busy) ...[const SizedBox(height: 8), const LinearProgressIndicator(minHeight: 3)],
            ],
          ),
        ),
        CarroPanel(
          title: 'IR LIBRARY',
          trailing: Text('${s.irLibrary.length}', style: lcdStyle(c, size: 12)),
          child: s.irLibrary.isEmpty
              ? Text(soundText(context, 'ir_library_empty'), style: carroBody)
              : Column(
                  children: [
                    for (final e in s.irLibrary) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CarroColors.inset,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: s.loadedIrPath == e.path ? c.withValues(alpha: 0.7) : CarroColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(e.source == 'capture' ? Icons.mic : Icons.graphic_eq, size: 18, color: c),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(e.name, style: lcdStyle(c, size: 13), overflow: TextOverflow.ellipsis),
                                ),
                                if (s.loadedIrPath == e.path) Text('LOADED', style: carroCaption.copyWith(color: c)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(irDescription(e), style: carroCaption),
                            if (slotsOf(e).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in slotsOf(e)) _Tag(t)]),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: CarroButton(
                                    label: 'ASSIGN',
                                    icon: Icons.link,
                                    dense: true,
                                    onPressed: () => _assign(e),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: CarroButton(
                                    label: 'DELETE',
                                    icon: Icons.delete_outline,
                                    dense: true,
                                    color: CarroColors.danger,
                                    onPressed: () => _delete(e),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initialName, required this.mode, required this.size});

  final String initialName;
  final int mode, size;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late int _mode = widget.mode.clamp(1, 7);
  late int _size = widget.size.clamp(0, 2);
  bool _assign = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('IMPORT IR'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                maxLength: 48,
                style: const TextStyle(color: CarroColors.text, letterSpacing: 1),
                decoration: InputDecoration(labelText: soundText(context, 'ir_name')),
              ),
              CarroToggle(
                label: soundText(context, 'ir_assign_slot').toUpperCase(),
                subtitle: _assign ? null : soundText(context, 'ir_no_assign'),
                value: _assign,
                onChanged: (v) => setState(() => _assign = v),
              ),
              if (_assign) ...[
                const SizedBox(height: 8),
                _SlotPicker(
                  mode: _mode,
                  size: _size,
                  onChanged: (m, s) => setState(() {
                    _mode = m;
                    _size = s;
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel.toUpperCase()),
        ),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(_ImportResult(name, _assign ? (_mode, _size) : null));
          },
          child: const Text('IMPORT'),
        ),
      ],
    );
  }
}
