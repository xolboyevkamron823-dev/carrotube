import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/settings.dart';
import 'dsp/sound_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final db = await AppDatabase.open();
  final settings = await SettingsNotifier.load(db);
  final sfTable = await SoundController.loadDefaultTable();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
        defaultSfTableProvider.overrideWithValue(sfTable),
      ],
      child: const CarroTubeApp(),
    ),
  );
}
