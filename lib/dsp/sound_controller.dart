import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carro_native/carro_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import 'sound_profile.dart';

/// Sound Field table shipped in assets (loaded in main and overridden here).
final defaultSfTableProvider = Provider<Map<int, SfTableEntry>>((ref) => const {});

/// An impulse response stored on the device.
class IrEntry {
  const IrEntry({required this.path, required this.name, this.channels = 0, this.lengthSeconds = 0, this.source = ''});
  final String path;
  final String name;
  final int channels;
  final double lengthSeconds;

  /// 'capture', 'import' ...
  final String source;

  Map<String, Object?> toJson() =>
      {'path': path, 'name': name, 'channels': channels, 'lengthSeconds': lengthSeconds, 'source': source};

  factory IrEntry.fromJson(Map<String, Object?> j) => IrEntry(
        path: j['path']! as String,
        name: (j['name'] as String?) ?? p.basename(j['path']! as String),
        channels: (j['channels'] as num?)?.toInt() ?? 0,
        lengthSeconds: (j['lengthSeconds'] as num?)?.toDouble() ?? 0,
        source: (j['source'] as String?) ?? '',
      );
}

class SoundState {
  const SoundState({
    required this.profile,
    required this.sfTable,
    this.savedProfiles = const [],
    this.irLibrary = const [],
    this.irAssignments = const {},
    this.loadedIrPath,
    this.bypass = false,
    this.dspAvailable = true,
    this.irLoading = false,
    this.message,
  });

  final SoundProfile profile;
  final Map<int, SfTableEntry> sfTable;
  final List<String> savedProfiles;

  /// All IR files the user has (captured or imported).
  final List<IrEntry> irLibrary;

  /// "mode_size" -> IR path used for that Sound Field slot in convolution mode.
  final Map<String, String> irAssignments;
  final String? loadedIrPath;
  final bool bypass;
  final bool dspAvailable;
  final bool irLoading;
  final String? message;

  static String slotKey(int mode, int size) => '${mode}_$size';

  String? irForSlot(int mode, int size) {
    final exact = irAssignments[slotKey(mode, size)];
    if (exact != null) return exact;
    for (var s = 0; s < 3; s++) {
      final any = irAssignments[slotKey(mode, s)];
      if (any != null) return any;
    }
    return null;
  }

  SoundState copyWith({
    SoundProfile? profile,
    Map<int, SfTableEntry>? sfTable,
    List<String>? savedProfiles,
    List<IrEntry>? irLibrary,
    Map<String, String>? irAssignments,
    String? loadedIrPath,
    bool clearLoadedIr = false,
    bool? bypass,
    bool? dspAvailable,
    bool? irLoading,
    String? message,
    bool clearMessage = false,
  }) =>
      SoundState(
        profile: profile ?? this.profile,
        sfTable: sfTable ?? this.sfTable,
        savedProfiles: savedProfiles ?? this.savedProfiles,
        irLibrary: irLibrary ?? this.irLibrary,
        irAssignments: irAssignments ?? this.irAssignments,
        loadedIrPath: clearLoadedIr ? null : (loadedIrPath ?? this.loadedIrPath),
        bypass: bypass ?? this.bypass,
        dspAvailable: dspAvailable ?? this.dspAvailable,
        irLoading: irLoading ?? this.irLoading,
        message: clearMessage ? null : (message ?? this.message),
      );
}

final soundProvider = NotifierProvider<SoundController, SoundState>(SoundController.new);

/// Owns the current sound profile, keeps the native engine in sync, persists everything
/// and manages named profiles, the Sound Field table and the IR library.
class SoundController extends Notifier<SoundState> {
  static const _kCurrent = 'sound.current';
  static const _kTable = 'sound.sftable';
  static const _kIrLib = 'sound.irlibrary';
  static const _kIrMap = 'sound.irmap';

  Timer? _saveTimer;
  CarroDsp? _dsp;

  @override
  SoundState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    final available = CarroDsp.isAvailable;
    _dsp = available ? CarroDsp.instance : null;
    Future.microtask(_restore);
    return SoundState(
      profile: const SoundProfile(eqL: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      sfTable: ref.read(defaultSfTableProvider),
      dspAvailable: available,
    );
  }

  CarroDsp? get dsp => _dsp;
  AppDatabase get _db => ref.read(appDatabaseProvider);

  static Future<Directory> _dir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, name));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<Directory> irDir() => _dir('ir');
  static Future<Directory> profilesDir() => _dir('profiles');

  /// Loads the shipped Sound Field table (assets/carro/sound_fields.json).
  static Future<Map<int, SfTableEntry>> loadDefaultTable() async {
    try {
      final raw = await rootBundle.loadString('assets/carro/sound_fields.json');
      return parseTable(jsonDecode(raw));
    } catch (_) {
      return const {};
    }
  }

  static Map<int, SfTableEntry> parseTable(Object? json) {
    final out = <int, SfTableEntry>{};
    final modes = json is Map ? json['modes'] : null;
    if (modes is List) {
      for (final m in modes) {
        if (m is! Map) continue;
        final mode = (m['mode'] as num?)?.toInt();
        if (mode == null || mode < 1 || mode > 7) continue;
        out[mode] = SfTableEntry.fromJson(m.cast<String, Object?>());
      }
    }
    return out;
  }

  Future<void> _restore() async {
    var profile = state.profile;
    final saved = await _db.getString(_kCurrent);
    if (saved != null) {
      try {
        profile = SoundProfile.fromJson((jsonDecode(saved) as Map).cast<String, Object?>());
      } catch (_) {}
    }
    var table = {...state.sfTable};
    final t = await _db.getString(_kTable);
    if (t != null) {
      try {
        table = {...table, ...parseTable(jsonDecode(t))};
      } catch (_) {}
    }
    var lib = <IrEntry>[];
    final l = await _db.getString(_kIrLib);
    if (l != null) {
      try {
        lib = (jsonDecode(l) as List)
            .map((e) => IrEntry.fromJson((e as Map).cast<String, Object?>()))
            .where((e) => File(e.path).existsSync())
            .toList();
      } catch (_) {}
    }
    var map = <String, String>{};
    final m = await _db.getString(_kIrMap);
    if (m != null) {
      try {
        map = (jsonDecode(m) as Map).map((k, v) => MapEntry(k as String, v as String));
        map.removeWhere((k, v) => !File(v).existsSync());
      } catch (_) {}
    }
    state = state.copyWith(
      profile: profile,
      sfTable: table,
      irLibrary: lib,
      irAssignments: map,
      savedProfiles: await _listProfiles(),
    );
    _pushTable();
    _apply();
    await _syncIr();
  }

  // ---------------------------------------------------------------------------------------
  // Engine sync
  // ---------------------------------------------------------------------------------------
  void _pushTable() {
    final d = _dsp;
    if (d == null) return;
    d.batch(() {
      state.sfTable.forEach((mode, e) {
        final v = e.values;
        for (var i = 0; i < v.length; i++) {
          d.set(SfTableEntry.paramIds[i], v[i], mode);
        }
      });
    });
  }

  void _apply() {
    final d = _dsp;
    if (d == null) return;
    state.profile.applyTo(d);
    d.set(P.bypass, state.bypass ? 1 : 0);
  }

  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      _db.setString(_kCurrent, jsonEncode(state.profile.toJson()));
    });
  }

  /// Generic profile edit. Every screen funnels its changes through here.
  void update(SoundProfile Function(SoundProfile p) f) {
    final before = state.profile;
    final after = f(before);
    state = state.copyWith(profile: after);
    _apply();
    _persistSoon();
    if (before.sfEngine != after.sfEngine || before.sfMode != after.sfMode || before.sfSize != after.sfSize) {
      _syncIr();
    }
  }

  void setBypass(bool on) {
    state = state.copyWith(bypass: on);
    _dsp?.set(P.bypass, on ? 1 : 0);
  }

  void toggleBypass() => setBypass(!state.bypass);

  // ---------------------------------------------------------------------------------------
  // EQ helpers
  // ---------------------------------------------------------------------------------------
  /// [channel]: 0 = left (or both when linked), 1 = right.
  void setEqBand(int band, double db, {int channel = 0}) {
    update((pr) {
      final n = pr.bandCount;
      final l = [...pr.eqLeft], r = [...pr.eqRight];
      if (band < 0 || band >= n) return pr;
      final v = db.clamp(-12.0, 12.0).roundToDouble();
      if (pr.eqLinked || channel == 0) l[band] = v;
      if (pr.eqLinked) {
        r[band] = v;
      } else if (channel == 1) {
        r[band] = v;
      }
      // Editing a factory preset turns it into CUSTOM1 (like the head unit).
      final preset = pr.eqPreset.startsWith('CUSTOM') ? pr.eqPreset : 'CUSTOM1';
      final c13 = pr.eqMode == 0 ? l : resampleEq(l, eq31Freqs, eq13Freqs);
      return pr.copyWith(
        eqL: l,
        eqR: r,
        eqPreset: preset,
        custom1: preset == 'CUSTOM1' ? c13 : null,
        custom2: preset == 'CUSTOM2' ? c13 : null,
      );
    });
  }

  void applyEqPreset(String name) {
    update((pr) {
      List<double> v13;
      if (name == 'CUSTOM1') {
        v13 = pr.custom1.length == 13 ? pr.custom1 : List.filled(13, 0.0);
      } else if (name == 'CUSTOM2') {
        v13 = pr.custom2.length == 13 ? pr.custom2 : List.filled(13, 0.0);
      } else {
        v13 = eqPresets13[name] ?? List.filled(13, 0.0);
      }
      final v = pr.eqMode == 1 ? resampleEq(v13, eq13Freqs, eq31Freqs) : List<double>.of(v13);
      return pr.copyWith(eqPreset: name, eqL: v, eqR: v);
    });
  }

  void setEqMode(int mode) {
    update((pr) {
      if (pr.eqMode == mode) return pr;
      final from = pr.bandFreqs, to = mode == 1 ? eq31Freqs : eq13Freqs;
      return pr.copyWith(
        eqMode: mode,
        eqL: resampleEq(pr.eqLeft, from, to),
        eqR: resampleEq(pr.eqRight, from, to),
      );
    });
  }

  void setEqLinked(bool linked) => update((pr) => pr.copyWith(eqLinked: linked, eqR: linked ? pr.eqLeft : pr.eqRight));

  void resetEq() => applyEqPreset('FLAT');

  // ---------------------------------------------------------------------------------------
  // Time alignment
  // ---------------------------------------------------------------------------------------
  void applyTaPreset(String name) {
    update((pr) {
      if (name == 'OFF') return pr.copyWith(taOn: false, taPreset: 'OFF');
      if (name == 'CUSTOM') return pr.copyWith(taOn: true, taPreset: 'CUSTOM');
      return pr.copyWith(taOn: true, taPreset: name, taCm: List.of(taPresetDistances[name]!));
    });
  }

  void setTaDistance(int speaker, double cm) {
    update((pr) {
      final list = [...pr.taCm];
      list[speaker] = ((cm.clamp(0, 350) / 2.5).round() * 2.5).toDouble();
      return pr.copyWith(taCm: list, taOn: true, taPreset: 'CUSTOM');
    });
  }

  // ---------------------------------------------------------------------------------------
  // Sound Field table
  // ---------------------------------------------------------------------------------------
  void setSfTable(int mode, SfTableEntry e) {
    state = state.copyWith(sfTable: {...state.sfTable, mode: e});
    final d = _dsp;
    if (d != null) {
      final v = e.values;
      d.batch(() {
        for (var i = 0; i < v.length; i++) {
          d.set(SfTableEntry.paramIds[i], v[i], mode);
        }
      });
    }
    _db.setString(_kTable, jsonEncode(tableJson()));
  }

  Future<void> resetSfTable() async {
    final def = await loadDefaultTable();
    state = state.copyWith(sfTable: def);
    _pushTable();
    await _db.setString(_kTable, jsonEncode(tableJson()));
  }

  Map<String, Object?> tableJson() => {
        'format': 'carrotube.soundfields/1',
        'modes': [
          for (final e in state.sfTable.entries) {'mode': e.key, 'name': soundFieldModes[e.key], ...e.value.toJson()},
        ],
      };

  Future<String> exportSfTable() async {
    final dir = await profilesDir();
    final f = File(p.join(dir.path, 'sound_fields.json'));
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(tableJson()));
    return f.path;
  }

  Future<bool> importSfTable(String path) async {
    try {
      final t = parseTable(jsonDecode(await File(path).readAsString()));
      if (t.isEmpty) return false;
      state = state.copyWith(sfTable: {...state.sfTable, ...t});
      _pushTable();
      await _db.setString(_kTable, jsonEncode(tableJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------------------
  // Named profiles
  // ---------------------------------------------------------------------------------------
  Future<List<String>> _listProfiles() async {
    final dir = await profilesDir();
    final names = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.carro.json'))
        .map((f) => p.basename(f.path).replaceAll('.carro.json', ''))
        .toList()
      ..sort();
    return names;
  }

  static String _safe(String name) => name.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();

  Future<void> saveProfile(String name) async {
    final dir = await profilesDir();
    final prof = state.profile.copyWith(name: name);
    await File(p.join(dir.path, '${_safe(name)}.carro.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(prof.toJson()));
    state = state.copyWith(profile: prof, savedProfiles: await _listProfiles(), message: 'saved');
    _persistSoon();
  }

  Future<void> loadProfile(String name) async {
    final dir = await profilesDir();
    final f = File(p.join(dir.path, '${_safe(name)}.carro.json'));
    if (!f.existsSync()) return;
    final prof = SoundProfile.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>());
    update((_) => prof);
    await _syncIr();
  }

  Future<void> deleteProfile(String name) async {
    final dir = await profilesDir();
    final f = File(p.join(dir.path, '${_safe(name)}.carro.json'));
    if (f.existsSync()) await f.delete();
    state = state.copyWith(savedProfiles: await _listProfiles());
  }

  /// Writes a profile to a shareable file and returns its path.
  Future<String> exportProfile([String? name]) async {
    final dir = await profilesDir();
    final prof = name == null ? state.profile : state.profile.copyWith(name: name);
    final f = File(p.join(dir.path, '${_safe(prof.name)}.carro.json'));
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(prof.toJson()));
    return f.path;
  }

  Future<bool> importProfile(String path) async {
    try {
      final j = (jsonDecode(await File(path).readAsString()) as Map).cast<String, Object?>();
      final prof = SoundProfile.fromJson(j);
      final dir = await profilesDir();
      await File(p.join(dir.path, '${_safe(prof.name)}.carro.json'))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(prof.toJson()));
      state = state.copyWith(savedProfiles: await _listProfiles());
      update((_) => prof);
      return true;
    } catch (_) {
      return false;
    }
  }

  void resetAll() => update((_) => const SoundProfile(eqL: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));

  // ---------------------------------------------------------------------------------------
  // IR library (convolution Sound Field)
  // ---------------------------------------------------------------------------------------
  /// Copies a WAV into the app's IR folder and adds it to the library.
  Future<IrEntry> addIr(String sourcePath, {required String name, String source = 'import'}) async {
    final dir = await irDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(dir.path, '${_safe(name)}_$stamp.wav');
    if (p.normalize(sourcePath) != p.normalize(dest)) await File(sourcePath).copy(dest);
    final entry = IrEntry(path: dest, name: name, source: source);
    state = state.copyWith(irLibrary: [...state.irLibrary, entry]);
    await _db.setString(_kIrLib, jsonEncode([for (final e in state.irLibrary) e.toJson()]));
    return entry;
  }

  Future<void> removeIr(IrEntry e) async {
    final lib = [...state.irLibrary]..removeWhere((x) => x.path == e.path);
    final map = {...state.irAssignments}..removeWhere((k, v) => v == e.path);
    state = state.copyWith(irLibrary: lib, irAssignments: map);
    try {
      await File(e.path).delete();
    } catch (_) {}
    await _db.setString(_kIrLib, jsonEncode([for (final x in lib) x.toJson()]));
    await _db.setString(_kIrMap, jsonEncode(map));
    await _syncIr();
  }

  /// Uses [irPath] (or null to clear) for Sound Field [mode] at [size].
  Future<void> assignIr(int mode, int size, String? irPath) async {
    final map = {...state.irAssignments};
    final k = SoundState.slotKey(mode, size);
    if (irPath == null) {
      map.remove(k);
    } else {
      map[k] = irPath;
    }
    state = state.copyWith(irAssignments: map);
    await _db.setString(_kIrMap, jsonEncode(map));
    await _syncIr();
  }

  /// Loads the IR that belongs to the current mode/size into the convolver (or clears it
  /// so the algorithmic engine takes over).
  Future<void> _syncIr() async {
    final d = _dsp;
    if (d == null) return;
    final pr = state.profile;
    final want = pr.sfEngine == 1 && pr.sfMode > 0 ? state.irForSlot(pr.sfMode, pr.sfSize) : null;
    if (want == state.loadedIrPath) return;
    if (want == null) {
      d.clearIr();
      state = state.copyWith(clearLoadedIr: true);
      return;
    }
    state = state.copyWith(irLoading: true);
    final rc = await d.loadIr(want);
    if (rc == CarroError.ok) {
      final info = d.irInfo();
      final lib = [
        for (final e in state.irLibrary)
          e.path == want
              ? IrEntry(
                  path: e.path,
                  name: e.name,
                  channels: info.channels,
                  lengthSeconds: info.lengthSeconds,
                  source: e.source,
                )
              : e,
      ];
      state = state.copyWith(loadedIrPath: want, irLoading: false, irLibrary: lib);
    } else {
      d.clearIr();
      state = state.copyWith(clearLoadedIr: true, irLoading: false, message: CarroError.describe(rc));
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);
}
