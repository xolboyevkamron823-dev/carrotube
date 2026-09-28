/// Shared look of the Carrozzeria "Sound" tab: near-black panels, LCD style text and
/// controls that glow in the user's ILLUMINATION colour.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:carro_native/carro_native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../dsp/sound_controller.dart';
import 'sound_strings.dart';

// -----------------------------------------------------------------------------------------
// Colours, text styles, formatting
// -----------------------------------------------------------------------------------------

abstract final class CarroColors {
  static const bg = Color(0xFF040506);
  static const panelTop = Color(0xFF15181D);
  static const panelBottom = Color(0xFF0A0C0F);
  static const inset = Color(0xFF07090B);
  static const border = Color(0xFF242930);
  static const text = Color(0xFFE4E8EC);
  static const textDim = Color(0xFF7D858E);
  static const unlit = Color(0xFF1E232A);
  static const warn = Color(0xFFFFB300);
  static const danger = Color(0xFFFF4D4D);
  static const defaultIllumination = Color(0xFF3FA9F5);
}

/// Segmented-LCD like text: monospace, tabular digits, wide tracking and a soft glow.
TextStyle lcdStyle(
  Color color, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
  bool glow = true,
  double spacing = 1.6,
}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['RobotoMono', 'Menlo', 'Consolas', 'Courier New', 'Courier'],
  fontSize: size,
  fontWeight: weight,
  letterSpacing: spacing,
  height: 1.15,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
  shadows: glow
      ? [
          Shadow(color: color.withValues(alpha: 0.75), blurRadius: size * 0.55),
          Shadow(color: color.withValues(alpha: 0.30), blurRadius: size * 1.3),
        ]
      : null,
);

/// Small caption above controls (unit silk-screen style).
const carroCaption = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
  color: CarroColors.textDim,
);

const carroBody = TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFB9C0C8));

/// "+3", "-2", "0" (optionally with decimals).
String signed(num v, {int decimals = 0}) {
  final s = v.abs().toStringAsFixed(decimals);
  if (double.parse(s) == 0) return decimals == 0 ? '0' : (0).toStringAsFixed(decimals);
  return v > 0 ? '+$s' : '-$s';
}

/// Head-unit frequency label: 50, 125, 1.25k, 10k, 12.5k, 20k.
String hzText(double hz) {
  if (hz < 1000) {
    return hz == hz.roundToDouble() ? hz.toStringAsFixed(0) : hz.toStringAsFixed(1);
  }
  final k = hz / 1000;
  var s = k.toStringAsFixed(k >= 10 ? 1 : 2);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return '${s}k';
}

/// Distinct curve / channel colours derived from the illumination colour.
List<Color> channelColors(Color c) {
  final hsv = HSVColor.fromColor(c);
  if (hsv.saturation < 0.2) {
    return const [Color(0xFFFFFFFF), Color(0xFFFFB300), Color(0xFF00E5FF), Color(0xFFFF4D8D), Color(0xFF7CFF6B)];
  }
  Color at(double shift) =>
      hsv.withHue((hsv.hue + shift) % 360).withSaturation(math.max(0.55, hsv.saturation)).toColor();
  return [c, at(120), at(240), at(60), at(300)];
}

// -----------------------------------------------------------------------------------------
// Illumination scope + theme
// -----------------------------------------------------------------------------------------

/// Provides the illumination colour to every Carro widget. It is an [InheritedTheme] so
/// dialogs and bottom sheets opened from a Sound screen keep the colour.
class CarroIllumination extends InheritedTheme {
  const CarroIllumination({super.key, required this.color, required super.child});

  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarroIllumination>()?.color ?? CarroColors.defaultIllumination;

  @override
  Widget wrap(BuildContext context, Widget child) => CarroIllumination(color: color, child: child);

  @override
  bool updateShouldNotify(CarroIllumination oldWidget) => oldWidget.color != color;
}

/// Illumination colour for code that runs above [CarroScope] (a screen's own build method,
/// whose context is outside the scope that [CarroScaffold] creates).
Color watchIllumination(WidgetRef ref) => Color(ref.watch(settingsProvider.select((s) => s.illumination)));

/// Wraps a subtree with the illumination colour from settings and the Carro theme.
class CarroScope extends ConsumerWidget {
  const CarroScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Color(ref.watch(settingsProvider.select((s) => s.illumination)));
    return CarroIllumination(
      color: c,
      child: Theme(data: carroThemeData(c), child: child),
    );
  }
}

ThemeData carroThemeData(Color c) {
  final scheme = ColorScheme.dark(
    primary: c,
    onPrimary: Colors.black,
    secondary: c,
    onSecondary: Colors.black,
    surface: const Color(0xFF0D1013),
    onSurface: CarroColors.text,
    surfaceContainerHighest: const Color(0xFF1A1E23),
    surfaceContainerHigh: const Color(0xFF15181C),
    surfaceContainer: const Color(0xFF111418),
    surfaceContainerLow: const Color(0xFF0D1013),
    onSurfaceVariant: CarroColors.textDim,
    outline: CarroColors.border,
    outlineVariant: const Color(0xFF1B1F25),
    error: CarroColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: CarroColors.bg,
  );
  return base.copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF101317),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.withValues(alpha: 0.35)),
      ),
      titleTextStyle: lcdStyle(c, size: 16),
      contentTextStyle: carroBody,
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF0D1013), showDragHandle: true),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c,
      linearTrackColor: c.withValues(alpha: 0.15),
      circularTrackColor: c.withValues(alpha: 0.12),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c,
      selectionColor: c.withValues(alpha: 0.35),
      selectionHandleColor: c,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CarroColors.inset,
      labelStyle: carroCaption,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CarroColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CarroColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c,
        textStyle: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700),
      ),
    ),
    iconTheme: const IconThemeData(color: CarroColors.text),
    dividerTheme: const DividerThemeData(color: Color(0xFF1B1F25), space: 1),
    listTileTheme: const ListTileThemeData(iconColor: CarroColors.textDim, textColor: CarroColors.text),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF12151A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: CarroColors.border),
      ),
      textStyle: const TextStyle(color: CarroColors.text, letterSpacing: 1.1),
    ),
  );
}

// -----------------------------------------------------------------------------------------
// Scaffold / header / panels
// -----------------------------------------------------------------------------------------

/// Every Sound screen: themed scope, dark background with a faint illumination vignette and
/// the head-unit header.
class CarroScaffold extends StatelessWidget {
  const CarroScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.showAb = true,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final Widget body;
  final bool showBack;
  final bool showAb;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return CarroScope(
      child: Builder(
        builder: (context) {
          final c = CarroIllumination.of(context);
          return Scaffold(
            backgroundColor: CarroColors.bg,
            appBar: CarroHeader(title: title, showBack: showBack, showAb: showAb, actions: actions),
            bottomNavigationBar: bottom,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.2),
                  radius: 1.4,
                  colors: [c.withValues(alpha: 0.07), CarroColors.bg],
                ),
              ),
              child: body,
            ),
          );
        },
      ),
    );
  }
}

/// Screen title + back + A/B, drawn like the top line of the head-unit display.
class CarroHeader extends StatelessWidget implements PreferredSizeWidget {
  const CarroHeader({
    super.key,
    required this.title,
    this.showBack = true,
    this.showAb = true,
    this.actions = const [],
  });

  final String title;
  final bool showBack;
  final bool showAb;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final canPop = showBack && Navigator.of(context).canPop();
    return Material(
      color: CarroColors.bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101318), Color(0xFF07080A)],
            ),
            border: Border(bottom: BorderSide(color: c.withValues(alpha: 0.35))),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icon(Icons.chevron_left, color: c, size: 30),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: lcdStyle(c, size: 17, weight: FontWeight.w700, spacing: 2.4),
                ),
              ),
              ...actions,
              if (showAb) const Padding(padding: EdgeInsets.only(left: 4, right: 10), child: CarroAbButton()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Instant A/B: A = DSP active, B = bypass (original signal).
class CarroAbButton extends ConsumerWidget {
  const CarroAbButton({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bypass = ref.watch(soundProvider.select((s) => s.bypass));
    final c = CarroIllumination.of(context);
    void toggle() {
      HapticFeedback.mediumImpact();
      ref.read(soundProvider.notifier).toggleBypass();
    }

    Widget half(String letter, String caption, bool lit, Color color) => Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(vertical: large ? 12 : 0),
        decoration: BoxDecoration(
          color: lit ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(large ? 10 : 6),
        ),
        alignment: Alignment.center,
        child: large
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    letter,
                    style: lcdStyle(lit ? color : CarroColors.unlit, size: 28, weight: FontWeight.w800, glow: lit),
                  ),
                  const SizedBox(height: 2),
                  Text(caption, style: lcdStyle(lit ? color : CarroColors.textDim, size: 11, glow: lit)),
                ],
              )
            : Text(
                letter,
                style: lcdStyle(lit ? color : CarroColors.textDim, size: 14, weight: FontWeight.w800, glow: lit),
              ),
      ),
    );

    return Semantics(
      button: true,
      label: bypass ? 'B bypass' : 'A DSP',
      child: GestureDetector(
        onTap: toggle,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: large ? null : 64,
          height: large ? null : 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: CarroColors.inset,
            borderRadius: BorderRadius.circular(large ? 13 : 9),
            border: Border.all(color: (bypass ? CarroColors.warn : c).withValues(alpha: 0.6)),
            boxShadow: [BoxShadow(color: (bypass ? CarroColors.warn : c).withValues(alpha: 0.18), blurRadius: 10)],
          ),
          child: Row(
            children: [
              half('A', 'DSP ON', !bypass, c),
              const SizedBox(width: 3),
              half('B', 'BYPASS', bypass, CarroColors.warn),
            ],
          ),
        ),
      ),
    );
  }
}

/// Near-black glass panel with an optional caption row.
class CarroPanel extends StatelessWidget {
  const CarroPanel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 12),
    this.margin = const EdgeInsets.fromLTRB(12, 6, 12, 6),
    this.glow = false,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CarroColors.panelTop, CarroColors.panelBottom],
        ),
        border: Border.all(color: glow ? c.withValues(alpha: 0.55) : CarroColors.border),
        boxShadow: [
          const BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 4)),
          if (glow) BoxShadow(color: c.withValues(alpha: 0.16), blurRadius: 18),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Glass highlight across the top edge.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 28,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: 0.045), Colors.white.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null || trailing != null) ...[
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 12,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(title ?? '', style: carroCaption.copyWith(color: c.withValues(alpha: 0.9))),
                        ),
                        ?trailing,
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain LCD text in the illumination colour.
class CarroLcdText extends StatelessWidget {
  const CarroLcdText(this.text, {super.key, this.size = 14, this.color, this.dim = false, this.textAlign, this.weight});

  final String text;
  final double size;
  final Color? color;
  final bool dim;
  final TextAlign? textAlign;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (dim ? CarroColors.textDim : CarroIllumination.of(context));
    return Text(
      text,
      textAlign: textAlign,
      style: lcdStyle(c, size: size, glow: !dim, weight: weight ?? FontWeight.w600),
    );
  }
}

/// Outlined head-unit button.
class CarroButton extends StatelessWidget {
  const CarroButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = false,
    this.dense = false,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool dense;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? CarroIllumination.of(context);
    final enabled = onPressed != null;
    final fg = enabled ? (filled ? Colors.black : c) : CarroColors.textDim;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                }
              : null,
          child: Ink(
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 7 : 11),
            decoration: BoxDecoration(
              color: filled && enabled ? c : CarroColors.inset,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: enabled ? c.withValues(alpha: 0.7) : CarroColors.border),
              boxShadow: enabled ? [BoxShadow(color: c.withValues(alpha: filled ? 0.35 : 0.12), blurRadius: 10)] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: dense ? 16 : 18, color: fg), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      fontSize: dense ? 11.5 : 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of live graphs / meters when the native engine is missing.
class CarroDspUnavailable extends StatelessWidget {
  const CarroDspUnavailable({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final err = CarroDsp.loadError;
    return CarroPanel(
      glow: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.memory_outlined, color: CarroColors.warn, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  soundText(context, 'dsp_missing_title').toUpperCase(),
                  style: lcdStyle(CarroColors.warn, size: 13, weight: FontWeight.w700),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(soundText(context, 'dsp_missing_body'), style: carroBody),
                  if (err != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$err',
                      style: carroCaption.copyWith(letterSpacing: 0.2, fontWeight: FontWeight.w500),
                      maxLines: 3,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small inline placeholder for a graph area when the DSP is missing.
class CarroNoDspGraph extends StatelessWidget {
  const CarroNoDspGraph({super.key, this.height = 120, this.text = 'DSP ENGINE NOT LOADED'});

  final double height;
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Center(child: Text(text, style: lcdStyle(CarroColors.textDim, size: 12, glow: false))),
  );
}

// -----------------------------------------------------------------------------------------
// Value stepper  ◀ value ▶
// -----------------------------------------------------------------------------------------

/// ◀ value ▶ with press-and-hold auto repeat (accelerating) and a haptic tick per step.
class CarroValueStepper extends StatelessWidget {
  const CarroValueStepper({
    super.key,
    this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.valueWidth = 92,
    this.enabled = true,
    this.sublabel,
  });

  final String? label;
  final String? sublabel;
  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final double valueWidth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RepeatButton(icon: Icons.arrow_left_rounded, onStep: enabled ? onDecrement : null),
        Container(
          width: valueWidth,
          height: 34,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: CarroColors.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CarroColors.border),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(value, style: lcdStyle(enabled ? c : CarroColors.textDim, size: 14, glow: enabled)),
            ),
          ),
        ),
        _RepeatButton(icon: Icons.arrow_right_rounded, onStep: enabled ? onIncrement : null),
      ],
    );
    if (label == null) return controls;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label!,
                  style: TextStyle(
                    color: enabled ? CarroColors.text : CarroColors.textDim,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 12.5,
                  ),
                ),
                if (sublabel != null)
                  Text(sublabel!, style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.4)),
              ],
            ),
          ),
          controls,
        ],
      ),
    );
  }
}

class _RepeatButton extends StatefulWidget {
  const _RepeatButton({required this.icon, required this.onStep});

  final IconData icon;
  final VoidCallback? onStep;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;
  int _ticks = 0;
  bool _down = false;

  void _fire() {
    final f = widget.onStep;
    if (f == null) {
      _stop();
      return;
    }
    HapticFeedback.selectionClick();
    f();
  }

  void _start() {
    if (widget.onStep == null) return;
    setState(() => _down = true);
    _fire();
    _ticks = 0;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 420), _repeat);
  }

  void _repeat() {
    if (!mounted || !_down) return;
    _fire();
    _ticks++;
    final ms = _ticks > 24 ? 35 : (_ticks > 8 ? 60 : 100);
    _timer = Timer(Duration(milliseconds: ms), _repeat);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_down && mounted) setState(() => _down = false);
  }

  @override
  void didUpdateWidget(covariant _RepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onStep == null && _timer != null) _stop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final enabled = widget.onStep != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 38,
        height: 34,
        decoration: BoxDecoration(
          color: _down ? c.withValues(alpha: 0.22) : const Color(0xFF12161B),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: enabled ? c.withValues(alpha: 0.45) : CarroColors.border),
        ),
        child: Icon(widget.icon, size: 30, color: enabled ? c : CarroColors.unlit),
      ),
    );
  }
}

/// Numeric convenience wrapper around [CarroValueStepper].
class CarroNumStepper extends StatelessWidget {
  const CarroNumStepper({
    super.key,
    this.label,
    this.sublabel,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
    this.format,
    this.valueWidth = 92,
    this.enabled = true,
  });

  final String? label;
  final String? sublabel;
  final double value, min, max, step;
  final ValueChanged<double> onChanged;
  final String Function(double v)? format;
  final double valueWidth;
  final bool enabled;

  double _snap(double v) {
    final s = ((v - min) / step).round() * step + min;
    return double.parse(s.clamp(min, max).toStringAsFixed(4));
  }

  @override
  Widget build(BuildContext context) {
    final text = format?.call(value) ?? (step % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1));
    return CarroValueStepper(
      label: label,
      sublabel: sublabel,
      value: text,
      valueWidth: valueWidth,
      enabled: enabled,
      onDecrement: value > min + 1e-9 ? () => onChanged(_snap(value - step)) : null,
      onIncrement: value < max - 1e-9 ? () => onChanged(_snap(value + step)) : null,
    );
  }
}

// -----------------------------------------------------------------------------------------
// Toggle / segmented
// -----------------------------------------------------------------------------------------

/// Head-unit ON/OFF item with an LED.
class CarroToggle extends StatelessWidget {
  const CarroToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onText = 'ON',
    this.offText = 'OFF',
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String onText, offText;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final lit = value && enabled;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onChanged(!value);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled ? CarroColors.text : CarroColors.textDim,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 12.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: carroCaption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 74,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: lit ? c.withValues(alpha: 0.14) : CarroColors.inset,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: lit ? c.withValues(alpha: 0.8) : CarroColors.border),
                boxShadow: lit ? [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 10)] : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: lit ? c : CarroColors.unlit,
                      boxShadow: lit ? [BoxShadow(color: c, blurRadius: 6)] : null,
                    ),
                  ),
                  const Spacer(),
                  Text(value ? onText : offText, style: lcdStyle(lit ? c : CarroColors.textDim, size: 12.5, glow: lit)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose one of N labels. [selected] = -1 highlights nothing.
class CarroSegmented extends StatelessWidget {
  const CarroSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.disabled = const {},
    this.dense = false,
    this.scrollable = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final Set<int> disabled;
  final bool dense;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    Widget seg(int i) {
      final on = i == selected;
      final can = enabled && !disabled.contains(i);
      final color = on && can ? c : (on ? c.withValues(alpha: 0.5) : (can ? CarroColors.text : CarroColors.unlit));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: can && !on
            ? () {
                HapticFeedback.selectionClick();
                onSelected(i);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: dense ? 32 : 38,
          padding: EdgeInsets.symmetric(horizontal: scrollable ? 14 : 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.16) : const Color(0xFF0E1115),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: on ? c.withValues(alpha: can ? 0.85 : 0.4) : CarroColors.border),
            boxShadow: on && can ? [BoxShadow(color: c.withValues(alpha: 0.22), blurRadius: 10)] : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              labels[i],
              maxLines: 1,
              style: on
                  ? lcdStyle(color, size: dense ? 11.5 : 12.5, weight: FontWeight.w700, spacing: 1.1, glow: can)
                  : TextStyle(color: color, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
            ),
          ),
        ),
      );
    }

    if (scrollable) {
      return SizedBox(
        height: dense ? 32 : 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: labels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => seg(i),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[if (i > 0) const SizedBox(width: 6), Expanded(child: seg(i))],
      ],
    );
  }
}

// -----------------------------------------------------------------------------------------
// Horizontal slider
// -----------------------------------------------------------------------------------------

/// Thin glowing horizontal slider. Drag or tap; snaps to [step]; haptic per step when the
/// range has a reasonable number of steps.
class CarroSlider extends StatefulWidget {
  const CarroSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step,
    this.origin,
    this.enabled = true,
    this.height = 34,
  });

  final double value, min, max;
  final double? step;

  /// Where the lit part starts (defaults to [min]); e.g. 0 for a bipolar dB value.
  final double? origin;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final double height;

  @override
  State<CarroSlider> createState() => _CarroSliderState();
}

class _CarroSliderState extends State<CarroSlider> {
  static const _pad = 12.0;
  double? _last;

  double _valueAt(double dx, double width) {
    final w = math.max(1.0, width - 2 * _pad);
    final t = ((dx - _pad) / w).clamp(0.0, 1.0);
    var v = widget.min + t * (widget.max - widget.min);
    final s = widget.step;
    if (s != null && s > 0) {
      v = ((v - widget.min) / s).round() * s + widget.min;
      v = double.parse(v.toStringAsFixed(4));
    }
    return v.clamp(widget.min, widget.max);
  }

  void _emit(double dx, double width) {
    final v = _valueAt(dx, width);
    if (_last != null && (v - _last!).abs() < 1e-9) return;
    _last = v;
    final s = widget.step;
    if (s != null && (widget.max - widget.min) / s <= 120) HapticFeedback.selectionClick();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (d) {
                  _last = widget.value;
                  _emit(d.localPosition.dx, width);
                }
              : null,
          onHorizontalDragStart: widget.enabled
              ? (d) {
                  _last = widget.value;
                  _emit(d.localPosition.dx, width);
                }
              : null,
          onHorizontalDragUpdate: widget.enabled ? (d) => _emit(d.localPosition.dx, width) : null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SliderPainter(
                t: ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0),
                origin: (((widget.origin ?? widget.min) - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0),
                color: widget.enabled ? c : CarroColors.textDim,
                pad: _pad,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.t, required this.origin, required this.color, required this.pad});

  final double t, origin, pad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x0 = pad, x1 = size.width - pad;
    final track = Paint()
      ..color = const Color(0xFF1B2027)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), track);
    final xv = x0 + (x1 - x0) * t;
    final xo = x0 + (x1 - x0) * origin;
    if ((xv - xo).abs() > 0.5) {
      final glow = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawLine(Offset(xo, y), Offset(xv, y), glow);
      canvas.drawLine(
        Offset(xo, y),
        Offset(xv, y),
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    if (origin > 0 && origin < 1) {
      canvas.drawLine(
        Offset(xo, y - 7),
        Offset(xo, y + 7),
        Paint()
          ..color = CarroColors.textDim
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(
      Offset(xv, y),
      11,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(xv, y),
      8.5,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF4A5059), Color(0xFF15181C)],
          center: Alignment(-0.3, -0.4),
        ).createShader(Rect.fromCircle(center: Offset(xv, y), radius: 8.5)),
    );
    canvas.drawCircle(
      Offset(xv, y),
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(Offset(xv, y), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t || old.origin != origin || old.color != color;
}

/// Label + LCD value on one line and a [CarroSlider] under it.
class CarroSliderRow extends StatelessWidget {
  const CarroSliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step,
    this.origin,
    this.enabled = true,
  });

  final String label, valueText;
  final double value, min, max;
  final double? step, origin;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? CarroColors.text : CarroColors.textDim,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(valueText, style: lcdStyle(enabled ? c : CarroColors.textDim, size: 13, glow: enabled)),
            ],
          ),
          CarroSlider(
            value: value,
            min: min,
            max: max,
            step: step,
            origin: origin,
            onChanged: onChanged,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------------------
// Rotary knob
// -----------------------------------------------------------------------------------------

/// Rotary knob: drag up/right to increase, down/left to decrease; mouse wheel steps;
/// double tap resets to [defaultValue]. 270° travel with tick marks and a glowing arc.
class CarroKnob extends StatefulWidget {
  const CarroKnob({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.label,
    this.valueText,
    this.size = 104,
    this.defaultValue,
    this.enabled = true,
    this.bipolar = false,
  });

  final double value, min, max, step;
  final ValueChanged<double> onChanged;
  final String? label;
  final String? valueText;
  final double size;
  final double? defaultValue;
  final bool enabled;
  final bool bipolar;

  @override
  State<CarroKnob> createState() => _CarroKnobState();
}

class _CarroKnobState extends State<CarroKnob> {
  double _accum = 0;
  double _pending = 0;
  bool _dragging = false;

  int get _steps => math.max(1, ((widget.max - widget.min) / widget.step).round());

  double get _pxPerStep => math.max(9.0, 240.0 / _steps);

  void _stepBy(int n) {
    final next = (_pending + n * widget.step).clamp(widget.min, widget.max).toDouble();
    if ((next - _pending).abs() < 1e-9) return;
    _pending = double.parse(next.toStringAsFixed(4));
    HapticFeedback.selectionClick();
    widget.onChanged(_pending);
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final t = ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final knob = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _KnobPainter(
          t: t,
          color: widget.enabled ? c : CarroColors.textDim,
          ticks: _steps <= 40 ? _steps + 1 : 41,
          bipolar: widget.bipolar,
          active: _dragging,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerSignal: widget.enabled
              ? (e) {
                  if (e is PointerScrollEvent) {
                    _pending = widget.value;
                    _stepBy(e.scrollDelta.dy < 0 ? 1 : -1);
                  }
                }
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.enabled
                ? (_) => setState(() {
                    _dragging = true;
                    _accum = 0;
                    _pending = widget.value;
                  })
                : null,
            onPanUpdate: widget.enabled
                ? (d) {
                    _accum += d.delta.dx - d.delta.dy;
                    while (_accum >= _pxPerStep) {
                      _accum -= _pxPerStep;
                      _stepBy(1);
                    }
                    while (_accum <= -_pxPerStep) {
                      _accum += _pxPerStep;
                      _stepBy(-1);
                    }
                  }
                : null,
            onPanEnd: (_) => setState(() => _dragging = false),
            onPanCancel: () => setState(() => _dragging = false),
            onDoubleTap: widget.enabled && widget.defaultValue != null
                ? () {
                    _pending = widget.value;
                    if ((widget.value - widget.defaultValue!).abs() > 1e-9) {
                      HapticFeedback.mediumImpact();
                      widget.onChanged(widget.defaultValue!);
                    }
                  }
                : null,
            child: knob,
          ),
        ),
        if (widget.valueText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.valueText!,
            style: lcdStyle(widget.enabled ? c : CarroColors.textDim, size: 16, weight: FontWeight.w700),
          ),
        ],
        if (widget.label != null) ...[const SizedBox(height: 2), Text(widget.label!, style: carroCaption)],
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({
    required this.t,
    required this.color,
    required this.ticks,
    required this.bipolar,
    required this.active,
  });

  final double t;
  final Color color;
  final int ticks;
  final bool bipolar;
  final bool active;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;

    // Ticks.
    for (var i = 0; i < ticks; i++) {
      final f = ticks == 1 ? 0.0 : i / (ticks - 1);
      final a = _start + _sweep * f;
      final lit = bipolar ? ((f >= 0.5 && f <= t + 1e-6) || (f <= 0.5 && f >= t - 1e-6)) : f <= t + 1e-6;
      final major = i == 0 || i == ticks - 1 || (bipolar && (f - 0.5).abs() < 1e-6);
      final p = Paint()
        ..color = lit ? color : const Color(0xFF2A3038)
        ..strokeWidth = major ? 2.2 : 1.4
        ..strokeCap = StrokeCap.round;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (r * (major ? 0.84 : 0.88)), center + dir * (r * 0.97), p);
    }

    // Value arc with glow.
    final arcRect = Rect.fromCircle(center: center, radius: r * 0.78);
    final from = bipolar ? 0.5 : 0.0;
    final a0 = _start + _sweep * math.min(from, t);
    final sweep = _sweep * (t - from).abs();
    canvas.drawArc(
      arcRect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = const Color(0xFF14181D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    if (sweep > 0.001) {
      canvas.drawArc(
        arcRect,
        a0,
        sweep,
        false,
        Paint()
          ..color = color.withValues(alpha: active ? 0.8 : 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawArc(
        arcRect,
        a0,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Knob body.
    final body = r * 0.66;
    canvas.drawCircle(
      center + const Offset(0, 3),
      body,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      body,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: [Color(0xFF4B525B), Color(0xFF22262C), Color(0xFF0E1013)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: body)),
    );
    // Knurling.
    final knurl = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 48; i++) {
      final a = i * math.pi * 2 / 48;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + d * (body * 0.88), center + d * body, knurl);
    }
    canvas.drawCircle(
      center,
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    // Cap.
    final cap = body * 0.72;
    canvas.drawCircle(
      center,
      cap,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF30353C), Color(0xFF15181C)],
        ).createShader(Rect.fromCircle(center: center, radius: cap)),
    );
    // Pointer.
    final a = _start + _sweep * t;
    final d = Offset(math.cos(a), math.sin(a));
    final p1 = center + d * (cap * 0.25), p2 = center + d * (cap * 0.92);
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.t != t || old.color != color || old.ticks != ticks || old.bipolar != bipolar || old.active != active;
}

// -----------------------------------------------------------------------------------------
// Vertical EQ slider
// -----------------------------------------------------------------------------------------

/// EQ band fader: [min]..[max] dB in 1 dB steps with a detent at 0, value on top and the
/// frequency label at the bottom. Double tap resets to 0.
class CarroVerticalSlider extends StatefulWidget {
  const CarroVerticalSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = -12,
    this.max = 12,
    this.label,
    this.height = 240,
    this.enabled = true,
  });

  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String? label;
  final double height;
  final bool enabled;

  @override
  State<CarroVerticalSlider> createState() => _CarroVerticalSliderState();
}

class _CarroVerticalSliderState extends State<CarroVerticalSlider> {
  static const _pad = 10.0;
  double? _last;
  bool _active = false;

  void _emit(double dy, double trackHeight) {
    final h = math.max(1.0, trackHeight - 2 * _pad);
    final frac = 1 - ((dy - _pad) / h).clamp(0.0, 1.0);
    final raw = widget.min + frac * (widget.max - widget.min);
    // Detent: 0 dB holds a little wider than the other steps.
    final v = raw.abs() < 0.85 ? 0.0 : raw.roundToDouble().clamp(widget.min, widget.max).toDouble();
    if (_last != null && _last == v) return;
    _last = v;
    if (v == 0) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = CarroIllumination.of(context);
    final color = widget.enabled ? c : CarroColors.textDim;
    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                signed(widget.value),
                style: lcdStyle(
                  widget.value == 0 ? CarroColors.textDim : color,
                  size: 12,
                  glow: widget.value != 0,
                  spacing: 0.4,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: widget.enabled
                    ? (d) {
                        setState(() => _active = true);
                        _last = widget.value;
                        _emit(d.localPosition.dy, box.maxHeight);
                      }
                    : null,
                onVerticalDragUpdate: widget.enabled ? (d) => _emit(d.localPosition.dy, box.maxHeight) : null,
                onVerticalDragEnd: (_) => setState(() => _active = false),
                onVerticalDragCancel: () => setState(() => _active = false),
                onDoubleTap: widget.enabled && widget.value != 0
                    ? () {
                        HapticFeedback.mediumImpact();
                        widget.onChanged(0);
                      }
                    : null,
                child: CustomPaint(
                  size: Size(box.maxWidth, box.maxHeight),
                  painter: _VSliderPainter(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    color: color,
                    pad: _pad,
                    active: _active,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(widget.label ?? '', style: carroCaption.copyWith(letterSpacing: 0.3, fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VSliderPainter extends CustomPainter {
  _VSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.pad,
    required this.active,
  });

  final double value, min, max, pad;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = pad, bottom = size.height - pad;
    double yOf(double v) => bottom - (v - min) / (max - min) * (bottom - top);

    // Slot.
    final slot = RRect.fromRectAndRadius(Rect.fromLTRB(cx - 2.5, top, cx + 2.5, bottom), const Radius.circular(3));
    canvas.drawRRect(slot, Paint()..color = const Color(0xFF020304));
    canvas.drawRRect(
      slot,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF1D2229),
    );

    // LED ladder: one segment per dB each side of the slot.
    final steps = (max - min).round();
    final segW = math.min(7.0, math.max(3.0, size.width / 2 - 8));
    final y0 = yOf(0);
    final yv = yOf(value);
    final lit = Paint()..color = color;
    final unlit = Paint()..color = const Color(0xFF181C22);
    for (var i = 0; i <= steps; i++) {
      final v = min + i;
      final y = yOf(v);
      final on = value > 0 ? (v > 0 && v <= value) : (value < 0 ? (v < 0 && v >= value) : false);
      final p = v == 0 ? (Paint()..color = CarroColors.textDim) : (on ? lit : unlit);
      final h = v == 0 ? 1.6 : 1.2;
      canvas.drawRect(Rect.fromLTRB(cx - 5 - segW, y - h, cx - 5, y + h), p);
      canvas.drawRect(Rect.fromLTRB(cx + 5, y - h, cx + 5 + segW, y + h), p);
    }
    if (value != 0) {
      canvas.drawLine(
        Offset(cx, y0),
        Offset(cx, yv),
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawLine(
        Offset(cx, y0),
        Offset(cx, yv),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
    }

    // Thumb.
    final tw = math.min(size.width - 4, 28.0);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, yv), width: tw, height: 13),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      thumb.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      thumb,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A616B), Color(0xFF252A30), Color(0xFF3A4048)],
        ).createShader(thumb.outerRect),
    );
    canvas.drawRRect(
      thumb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: active ? 0.9 : 0.45),
    );
    canvas.drawLine(
      Offset(cx - tw / 2 + 4, yv),
      Offset(cx + tw / 2 - 4, yv),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..maskFilter = active ? const MaskFilter.blur(BlurStyle.normal, 1.5) : null,
    );
  }

  @override
  bool shouldRepaint(_VSliderPainter old) =>
      old.value != value || old.color != color || old.active != active || old.min != min || old.max != max;
}

// -----------------------------------------------------------------------------------------
// Dialogs
// -----------------------------------------------------------------------------------------

Future<bool> showCarroConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'OK',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel.toUpperCase()),
        ),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirm)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> showCarroTextDialog(BuildContext context, {required String title, String initial = '', String? label}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextDialog(title: title, initial: initial, label: label),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, this.label});

  final String title, initial;
  final String? label;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 48,
        style: const TextStyle(color: CarroColors.text, letterSpacing: 1),
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel.toUpperCase()),
        ),
        TextButton(onPressed: _submit, child: Text(MaterialLocalizations.of(context).okButtonLabel.toUpperCase())),
      ],
    );
  }
}

/// Illumination for a context that may sit above [CarroScope] (falls back to settings).
Color _illuminationFor(BuildContext context) {
  final scoped = context.getInheritedWidgetOfExactType<CarroIllumination>();
  if (scoped != null) return scoped.color;
  try {
    return Color(ProviderScope.containerOf(context, listen: false).read(settingsProvider).illumination);
  } catch (_) {
    return CarroColors.defaultIllumination;
  }
}

/// Floating snackbar with the head-unit look.
void showCarroSnack(BuildContext context, String text, {bool error = false, Color? color}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = error ? CarroColors.danger : (color ?? _illuminationFor(context));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF11151A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.withValues(alpha: 0.6)),
        ),
        content: Text(text, style: TextStyle(color: error ? CarroColors.danger : CarroColors.text, letterSpacing: 0.4)),
      ),
    );
}
