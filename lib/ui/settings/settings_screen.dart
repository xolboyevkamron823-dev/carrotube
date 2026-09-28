import 'dart:io';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/settings.dart';
import '../../player/player_controller.dart';
import '../widgets/logo.dart';

/// App settings: theme, language, playback, and (Android) background playback help.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _qualities = [144, 240, 360, 480, 720, 1080];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);

    String themeLabel(ThemeMode m) => context.tr(switch (m) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });

    String langLabel(String? code) => switch (code) {
      'uz' => 'O‘zbekcha',
      'ru' => 'Русский',
      'en' => 'English',
      _ => context.tr('system'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        children: [
          _Header(context.tr('general')),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(context.tr('theme')),
            subtitle: Text(themeLabel(s.themeMode), style: secondary),
            onTap: () => _choose<ThemeMode>(
              context,
              title: context.tr('theme'),
              values: const [ThemeMode.dark, ThemeMode.light, ThemeMode.system],
              selected: s.themeMode,
              label: themeLabel,
              onSelected: (m) => notifier.update((x) => x.copyWith(themeMode: m)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(context.tr('language')),
            subtitle: Text(langLabel(s.localeCode), style: secondary),
            onTap: () => _choose<String?>(
              context,
              title: context.tr('language'),
              values: const ['uz', 'ru', 'en', null],
              selected: s.localeCode,
              label: langLabel,
              onSelected: (code) =>
                  notifier.update((x) => code == null ? x.copyWith(clearLocale: true) : x.copyWith(localeCode: code)),
            ),
          ),
          const Divider(),
          _Header(context.tr('playback')),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: Text(context.tr('preferred_quality')),
            subtitle: Text('${s.preferredQuality}p', style: secondary),
            onTap: () => _choose<int>(
              context,
              title: context.tr('preferred_quality'),
              values: _qualities,
              selected: s.preferredQuality,
              label: (q) => '${q}p',
              onSelected: (q) => notifier.update((x) => x.copyWith(preferredQuality: q)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: Text(context.tr('autoplay')),
            subtitle: Text(context.tr('autoplay_sub'), style: secondary),
            value: s.autoplay,
            onChanged: (v) => ref.read(playerProvider.notifier).setAutoplay(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones_outlined),
            title: Text(context.tr('audio_only_default')),
            subtitle: Text(context.tr('audio_only_sub'), style: secondary),
            value: s.audioOnlyDefault,
            onChanged: (v) => notifier.update((x) => x.copyWith(audioOnlyDefault: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bluetooth_audio_rounded),
            title: Text(context.tr('resume_bt')),
            subtitle: Text(context.tr('resume_bt_sub'), style: secondary),
            value: s.resumeOnBluetooth,
            onChanged: (v) {
              notifier.update((x) => x.copyWith(resumeOnBluetooth: v));
              NativePlayer.instance.setResumeOnBluetooth(v);
            },
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            _Header(context.tr('background_play')),
            const _BackgroundPlaybackSection(),
          ],
          const Divider(),
          _Header(context.tr('about')),
          ListTile(
            leading: const Padding(padding: EdgeInsets.only(top: 4), child: CarroTubeLogo(height: 16)),
            title: const SizedBox.shrink(),
            subtitle: Text('${context.tr('version')} 1.0.0', style: secondary),
          ),
          SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  static void _choose<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            for (final v in values)
              ListTile(
                leading: v == selected ? const Icon(Icons.check_rounded) : const SizedBox(width: 24),
                title: Text(label(v)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSelected(v);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

/// Android vendors with aggressive background killers and how to whitelist the app.
class _Vendor {
  const _Vendor(this.id, this.name, this.stepsKey, this.matches);
  final String id;
  final String name;
  final String stepsKey;
  final List<String> matches;
}

const _vendors = <_Vendor>[
  _Vendor('xiaomi', 'Xiaomi / MIUI / HyperOS', 'vendor_xiaomi', ['xiaomi', 'redmi', 'poco']),
  _Vendor('samsung', 'Samsung (One UI)', 'vendor_samsung', ['samsung']),
  _Vendor('huawei', 'Huawei / Honor', 'vendor_huawei', ['huawei', 'honor']),
  _Vendor('oppo', 'Oppo / Realme / OnePlus', 'vendor_oppo', ['oppo', 'realme', 'oneplus']),
  _Vendor('vivo', 'Vivo / iQOO', 'vendor_vivo', ['vivo', 'iqoo']),
];

class _BackgroundPlaybackSection extends StatefulWidget {
  const _BackgroundPlaybackSection();

  @override
  State<_BackgroundPlaybackSection> createState() => _BackgroundPlaybackSectionState();
}

class _BackgroundPlaybackSectionState extends State<_BackgroundPlaybackSection> with WidgetsBindingObserver {
  bool? _ignoring;
  String? _manufacturer;
  String? _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user comes back from the system settings screen: re-check.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    bool? ignoring;
    Map<String, Object?> info = const {};
    try {
      ignoring = await CarroSystem.isIgnoringBatteryOptimizations();
    } catch (_) {
      ignoring = null;
    }
    try {
      info = await CarroSystem.deviceInfo();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _ignoring = ignoring;
      _manufacturer = (info['manufacturer'] as String?)?.toLowerCase();
      _model = info['model'] as String?;
    });
  }

  _Vendor? get _detected {
    final m = _manufacturer;
    if (m == null) return null;
    for (final v in _vendors) {
      if (v.matches.any(m.contains)) return v;
    }
    return null;
  }

  Future<void> _openVendor(_Vendor v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final fallback = context.tr('vendor_open_failed');
    bool ok;
    try {
      ok = await CarroSystem.openVendorBackgroundSettings(v.id);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(fallback)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = _ignoring == true;
    final detected = _detected;
    final ordered = [?detected, ..._vendors.where((v) => v != detected)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _ignoring == null
                            ? Icons.battery_unknown_rounded
                            : (ok ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded),
                        color: _ignoring == null
                            ? scheme.onSurfaceVariant
                            : (ok ? Colors.green : Colors.amber.shade700),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('battery_title'),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ok ? context.tr('battery_ok') : context.tr('battery_body'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (!ok) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await CarroSystem.requestIgnoreBatteryOptimizations();
                        } catch (_) {}
                        await _load();
                      },
                      icon: const Icon(Icons.battery_saver_outlined),
                      label: Text(context.tr('battery_allow')),
                      style: FilledButton.styleFrom(backgroundColor: scheme.onSurface, foregroundColor: scheme.surface),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_manufacturer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '${context.tr('your_device')}: ${_manufacturer!.isEmpty ? '' : _manufacturer![0].toUpperCase()}${_manufacturer!.length > 1 ? _manufacturer!.substring(1) : ''} ${_model ?? ''}'
                  .trim(),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        for (final v in ordered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: v == detected ? scheme.onSurface.withValues(alpha: 0.5) : scheme.outlineVariant,
                ),
              ),
              child: ExpansionTile(
                initiallyExpanded: v == detected,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.phone_android_rounded),
                title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: v == detected ? Text(context.tr('your_device')) : null,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr(v.stepsKey), style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openVendor(v),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(context.tr('battery_open')),
                    style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurface, shape: const StadiumBorder()),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
