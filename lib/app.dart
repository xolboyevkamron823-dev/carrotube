import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/settings.dart';
import 'dsp/sound_controller.dart';
import 'player/player_controller.dart';

class CarroTubeApp extends ConsumerWidget {
  const CarroTubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Keep the long-lived controllers alive for the whole app lifetime.
    ref.watch(playerProvider.select((s) => s.index));
    ref.watch(soundProvider.select((s) => s.dspAvailable));
    return MaterialApp.router(
      title: 'CarroTube',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: settings.localeCode == null ? null : Locale(settings.localeCode!),
      supportedLocales: AppStrings.supported,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return const Locale('en');
        return supported.firstWhere((l) => l.languageCode == locale.languageCode, orElse: () => const Locale('en'));
      },
      routerConfig: appRouter,
    );
  }
}
