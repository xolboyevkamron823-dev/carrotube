import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../dsp/sound_controller.dart';
import '../../dsp/sound_profile.dart';
import 'carro_theme.dart';
import 'crossover_screen.dart';
import 'effects_screen.dart';
import 'eq_screen.dart';
import 'ir_capture_screen.dart';
import 'profiles_screen.dart';
import 'sound_field_screen.dart';
import 'sound_strings.dart';
import 'spectrum_analyzer.dart';
import 'ta_screen.dart';

/// The Carrozzeria "AUDIO" main menu of the Sound tab.
class SoundScreen extends ConsumerWidget {
  const SoundScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundProvider);
    final pr = s.profile;

    ref.listen(soundProvider.select((st) => st.message), (prev, msg) {
      if (msg == null) return;
      final text = msg == 'saved' ? soundText(context, 'profile_saved') : msg;
      showCarroSnack(context, text, error: msg != 'saved', color: Color(ref.read(settingsProvider).illumination));
      Future.microtask(() {
        if (context.mounted) ref.read(soundProvider.notifier).clearMessage();
      });
    });

    final sfText = pr.sfMode == 0
        ? 'OFF'
        : '${soundFieldModes[pr.sfMode]} ${sizeNames[pr.sfSize.clamp(0, 2)]}${pr.sfEngine == 1 ? ' · CONV' : ''}';
    final taText = pr.taOn ? pr.taPreset : 'OFF';
    final effects = <String>[
      if (pr.loudness > 0) 'LOUD ${loudnessNames[pr.loudness]}',
      if (pr.bassBoost > 0) 'BASS +${pr.bassBoost}',
      if (pr.asrMode > 0) 'ASR ${asrNames[pr.asrMode]}',
      if (pr.sla != 0) 'SLA ${signed(pr.sla)}',
    ];

    final tiles = <_MenuItem>[
      _MenuItem('EQ', Icons.equalizer, '${pr.eqPreset} · ${pr.bandCount} BAND', () => _open(context, const EqScreen())),
      _MenuItem('SOUND FIELD', Icons.surround_sound, sfText, () => _open(context, const SoundFieldScreen())),
      _MenuItem('TIME ALIGNMENT', Icons.timer_outlined, taText, () => _open(context, const TaScreen())),
      _MenuItem(
        'CROSSOVER',
        Icons.call_split,
        pr.network ? 'NETWORK 3-WAY' : 'STANDARD',
        () => _open(context, const CrossoverScreen()),
      ),
      _MenuItem(
        'AUDIO',
        Icons.tune,
        effects.isEmpty ? 'FADER/BALANCE · SUB · LIMITER' : effects.join(' · '),
        () => _open(context, const EffectsScreen()),
      ),
      _MenuItem(
        'PROFILES',
        Icons.folder_special_outlined,
        pr.name.toUpperCase(),
        () => _open(context, const ProfilesScreen()),
      ),
      _MenuItem(
        'IR CAPTURE',
        Icons.mic_external_on,
        '${s.irLibrary.length} IR IN LIBRARY',
        () => _open(context, const IrCaptureScreen()),
      ),
    ];

    return CarroScaffold(
      title: 'AUDIO',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          _StatusStrip(sf: sfText, eq: pr.eqPreset, ta: taText, bypass: s.bypass, network: pr.network),
          if (!s.dspAvailable) const CarroDspUnavailable(),
          Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 2), child: const CarroAbButton(large: true)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              soundText(context, s.bypass ? 'bypass_on' : 'bypass_off'),
              textAlign: TextAlign.center,
              style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 720 ? 4 : (box.maxWidth >= 480 ? 3 : 2);
                const gap = 10.0;
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in tiles)
                      SizedBox(
                        width: w,
                        child: _MenuTile(item: t),
                      ),
                  ],
                );
              },
            ),
          ),
          const _IlluminationPanel(),
          if (s.dspAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(child: Text('CARRO DSP ${_version()}', style: carroCaption)),
            ),
        ],
      ),
    );
  }

  static String _version() {
    try {
      return CarroDsp.instance.version;
    } catch (_) {
      return '';
    }
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.sf,
    required this.eq,
    required this.ta,
    required this.bypass,
    required this.network,
  });

  final String sf, eq, ta;
  final bool bypass, network;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    Widget item(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(label, style: carroCaption.copyWith(color: c.withValues(alpha: 0.65), fontSize: 9.5)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: lcdStyle(bypass ? CarroColors.textDim : c, size: 12.5, glow: !bypass),
            ),
          ),
        ],
      ),
    );
    return CarroPanel(
      glow: !bypass,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [item('SF', sf), item('EQ', eq), item('TA', ta), item('XO', network ? 'NETWORK' : 'STANDARD')],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  bypass ? 'BYPASS' : 'DSP',
                  style: lcdStyle(bypass ? CarroColors.warn : c, size: 11, weight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: CarroColors.inset,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: CarroColors.border),
                  ),
                  child: const SpectrumAnalyzer.mini(height: 36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.title, this.icon, this.value, this.onTap);

  final String title;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        splashColor: c.withValues(alpha: 0.15),
        highlightColor: c.withValues(alpha: 0.08),
        onTap: item.onTap,
        child: Ink(
          height: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CarroColors.panelTop, CarroColors.panelBottom],
            ),
            border: Border.all(color: c.withValues(alpha: 0.28)),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    item.icon,
                    color: c,
                    size: 22,
                    shadows: [Shadow(color: c.withValues(alpha: 0.8), blurRadius: 8)],
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: c.withValues(alpha: 0.6), size: 18),
                ],
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CarroColors.text,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: lcdStyle(c, size: 10.5, glow: false, spacing: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ILLUMINATION: preset colours plus a free hue slider; tints the whole Sound UI.
class _IlluminationPanel extends ConsumerWidget {
  const _IlluminationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(settingsProvider.select((s) => s.illumination));
    final current = Color(value);
    void set(Color color) {
      if (color.toARGB32() == value) return;
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(illumination: color.toARGB32()));
    }

    final hsv = HSVColor.fromColor(current);
    return CarroPanel(
      title: 'ILLUMINATION',
      trailing: Container(
        width: 36,
        height: 14,
        decoration: BoxDecoration(
          color: current,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [BoxShadow(color: current.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in illuminationPresets)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    set(p);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p,
                      border: Border.all(
                        color: p.toARGB32() == value ? Colors.white : Colors.black,
                        width: p.toARGB32() == value ? 2.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.withValues(alpha: p.toARGB32() == value ? 0.9 : 0.35),
                          blurRadius: p.toARGB32() == value ? 14 : 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('HUE', style: carroCaption),
          const SizedBox(height: 6),
          _HueSlider(
            hue: hsv.saturation < 0.05 ? 0 : hsv.hue,
            onChanged: (h) => set(HSVColor.fromAHSV(1, h, 0.85, 1).toColor()),
          ),
        ],
      ),
    );
  }
}

class _HueSlider extends StatefulWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  State<_HueSlider> createState() => _HueSliderState();
}

class _HueSliderState extends State<_HueSlider> {
  static const _pad = 12.0;
  int _lastTick = -1;

  void _at(double dx, double width) {
    final t = ((dx - _pad) / (width - 2 * _pad)).clamp(0.0, 1.0);
    final hue = (t * 360).roundToDouble().clamp(0.0, 359.0);
    final tick = hue ~/ 10;
    if (tick != _lastTick) {
      _lastTick = tick;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(hue);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _at(d.localPosition.dx, w),
          onHorizontalDragStart: (d) => _at(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _at(d.localPosition.dx, w),
          child: SizedBox(
            height: 36,
            width: double.infinity,
            child: CustomPaint(
              painter: _HuePainter(hue: widget.hue, pad: _pad),
            ),
          ),
        );
      },
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter({required this.hue, required this.pad});

  final double hue, pad;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTRB(pad, size.height / 2 - 6, size.width - pad, size.height / 2 + 6),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h % 360, 0.85, 1).toColor()],
        ).createShader(track.outerRect),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: 0.6),
    );
    final x = pad + (size.width - 2 * pad) * (hue / 360);
    final color = HSVColor.fromAHSV(1, hue, 0.85, 1).toColor();
    final center = Offset(x, size.height / 2);
    canvas.drawCircle(
      center,
      15,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(center, 11, Paint()..color = color);
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
