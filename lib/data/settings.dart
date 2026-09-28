import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Head-unit style illumination colours (like the Carrozzeria "ILLUMINATION" menu).
const illuminationPresets = <Color>[
  Color(0xFF3FA9F5), // blue (default)
  Color(0xFF00E5FF), // sky
  Color(0xFF00E676), // green
  Color(0xFFFFC400), // amber
  Color(0xFFFF6D00), // orange
  Color(0xFFFF1744), // red
  Color(0xFFD500F9), // purple
  Color(0xFFFFFFFF), // white
];

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.localeCode,
    this.autoplay = true,
    this.audioOnlyDefault = false,
    this.preferredQuality = 720,
    this.resumeOnBluetooth = true,
    this.illumination = 0xFF3FA9F5,
    this.playbackSpeed = 1.0,
    this.restoreQueue = true,
  });

  final ThemeMode themeMode;

  /// 'uz', 'ru', 'en' or null = system.
  final String? localeCode;
  final bool autoplay;
  final bool audioOnlyDefault;
  final int preferredQuality;
  final bool resumeOnBluetooth;
  final int illumination;
  final double playbackSpeed;
  final bool restoreQueue;

  Color get illuminationColor => Color(illumination);

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    bool clearLocale = false,
    bool? autoplay,
    bool? audioOnlyDefault,
    int? preferredQuality,
    bool? resumeOnBluetooth,
    int? illumination,
    double? playbackSpeed,
    bool? restoreQueue,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
        autoplay: autoplay ?? this.autoplay,
        audioOnlyDefault: audioOnlyDefault ?? this.audioOnlyDefault,
        preferredQuality: preferredQuality ?? this.preferredQuality,
        resumeOnBluetooth: resumeOnBluetooth ?? this.resumeOnBluetooth,
        illumination: illumination ?? this.illumination,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        restoreQueue: restoreQueue ?? this.restoreQueue,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'localeCode': localeCode,
        'autoplay': autoplay,
        'audioOnlyDefault': audioOnlyDefault,
        'preferredQuality': preferredQuality,
        'resumeOnBluetooth': resumeOnBluetooth,
        'illumination': illumination,
        'playbackSpeed': playbackSpeed,
        'restoreQueue': restoreQueue,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.dark),
        localeCode: j['localeCode'] as String?,
        autoplay: (j['autoplay'] as bool?) ?? true,
        audioOnlyDefault: (j['audioOnlyDefault'] as bool?) ?? false,
        preferredQuality: (j['preferredQuality'] as num?)?.toInt() ?? 720,
        resumeOnBluetooth: (j['resumeOnBluetooth'] as bool?) ?? true,
        illumination: (j['illumination'] as num?)?.toInt() ?? 0xFF3FA9F5,
        playbackSpeed: (j['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
        restoreQueue: (j['restoreQueue'] as bool?) ?? true,
      );
}

/// Settings loaded before runApp (overridden in main).
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const key = 'app.settings';

  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  static Future<AppSettings> load(AppDatabase db) async {
    final s = await db.getString(key);
    if (s == null) return const AppSettings();
    try {
      return AppSettings.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
    } catch (_) {
      return const AppSettings();
    }
  }

  void update(AppSettings Function(AppSettings s) f) {
    state = f(state);
    ref.read(appDatabaseProvider).setString(key, jsonEncode(state.toJson()));
  }
}
