import 'dart:math' as math;

import 'package:carro_native/carro_native.dart';

/// Carrozzeria GEQ presets (13-band values, dB). CUSTOM1/CUSTOM2 live in the profile.
/// Pioneer does not publish the factory curves; these are tuned by ear to the character of
/// each preset and can be edited (then saved as CUSTOM).
const eqPresetNames = <String>['SUPER BASS', 'POWERFUL', 'NATURAL', 'VOCAL', 'FLAT', 'CUSTOM1', 'CUSTOM2'];

const eqPresets13 = <String, List<double>>{
  'SUPER BASS': [7, 6, 5, 3, 1, 0, -1, -1, 0, 0, 0, 0, 0],
  'POWERFUL': [5, 4, 3, 1, 0, -1, -1, 0, 1, 2, 3, 4, 4],
  'NATURAL': [2, 2, 1, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2],
  'VOCAL': [-2, -2, -1, 0, 1, 2, 3, 3, 2, 1, 0, -1, -2],
  'FLAT': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
};

const loudnessNames = <String>['OFF', 'LOW', 'MID', 'HIGH'];
const asrNames = <String>['OFF', 'MODE1', 'MODE2'];
const sizeNames = <String>['S', 'M', 'L'];

/// Time-alignment presets (listening position) and their speaker distances in cm for a
/// typical left-hand-drive sedan. Order: FL/HL, FR/HR, RL/ML, RR/MR, SUB.
const taPresetNames = <String>['OFF', 'FRONT-LEFT', 'FRONT-RIGHT', 'FRONT', 'ALL', 'CUSTOM'];
const taPresetDistances = <String, List<double>>{
  'FRONT-LEFT': [75, 130, 150, 185, 200],
  'FRONT-RIGHT': [130, 75, 185, 150, 200],
  'FRONT': [100, 100, 165, 165, 200],
  'ALL': [150, 150, 150, 150, 150],
};

/// Interpolates a curve given at [fromFreqs] onto [toFreqs] (log-frequency, linear dB).
List<double> resampleEq(List<double> values, List<double> fromFreqs, List<double> toFreqs) {
  double at(double f) {
    if (f <= fromFreqs.first) return values.first;
    if (f >= fromFreqs.last) return values.last;
    for (var i = 0; i < fromFreqs.length - 1; i++) {
      if (f >= fromFreqs[i] && f <= fromFreqs[i + 1]) {
        final t = (math.log(f) - math.log(fromFreqs[i])) / (math.log(fromFreqs[i + 1]) - math.log(fromFreqs[i]));
        return values[i] + t * (values[i + 1] - values[i]);
      }
    }
    return 0;
  }

  return [for (final f in toFreqs) (at(f) * 2).roundToDouble() / 2];
}

class XoSettings {
  const XoSettings({
    this.hpfOn = false,
    this.hpfHz = 80,
    this.hpfSlope = 12,
    this.lpfOn = false,
    this.lpfHz = 80,
    this.lpfSlope = 12,
    this.linkwitzRiley = true,
    this.levelDb = 0,
    this.phaseReverse = false,
    this.mute = false,
  });

  final bool hpfOn;
  final double hpfHz;
  final int hpfSlope;
  final bool lpfOn;
  final double lpfHz;
  final int lpfSlope;
  final bool linkwitzRiley;
  final double levelDb;
  final bool phaseReverse;
  final bool mute;

  XoSettings copyWith({
    bool? hpfOn,
    double? hpfHz,
    int? hpfSlope,
    bool? lpfOn,
    double? lpfHz,
    int? lpfSlope,
    bool? linkwitzRiley,
    double? levelDb,
    bool? phaseReverse,
    bool? mute,
  }) =>
      XoSettings(
        hpfOn: hpfOn ?? this.hpfOn,
        hpfHz: hpfHz ?? this.hpfHz,
        hpfSlope: hpfSlope ?? this.hpfSlope,
        lpfOn: lpfOn ?? this.lpfOn,
        lpfHz: lpfHz ?? this.lpfHz,
        lpfSlope: lpfSlope ?? this.lpfSlope,
        linkwitzRiley: linkwitzRiley ?? this.linkwitzRiley,
        levelDb: levelDb ?? this.levelDb,
        phaseReverse: phaseReverse ?? this.phaseReverse,
        mute: mute ?? this.mute,
      );

  Map<String, Object?> toJson() => {
        'hpfOn': hpfOn,
        'hpfHz': hpfHz,
        'hpfSlope': hpfSlope,
        'lpfOn': lpfOn,
        'lpfHz': lpfHz,
        'lpfSlope': lpfSlope,
        'lr': linkwitzRiley,
        'levelDb': levelDb,
        'phaseReverse': phaseReverse,
        'mute': mute,
      };

  factory XoSettings.fromJson(Map<String, Object?> j, XoSettings d) => XoSettings(
        hpfOn: (j['hpfOn'] as bool?) ?? d.hpfOn,
        hpfHz: (j['hpfHz'] as num?)?.toDouble() ?? d.hpfHz,
        hpfSlope: (j['hpfSlope'] as num?)?.toInt() ?? d.hpfSlope,
        lpfOn: (j['lpfOn'] as bool?) ?? d.lpfOn,
        lpfHz: (j['lpfHz'] as num?)?.toDouble() ?? d.lpfHz,
        lpfSlope: (j['lpfSlope'] as num?)?.toInt() ?? d.lpfSlope,
        linkwitzRiley: (j['lr'] as bool?) ?? d.linkwitzRiley,
        levelDb: (j['levelDb'] as num?)?.toDouble() ?? d.levelDb,
        phaseReverse: (j['phaseReverse'] as bool?) ?? d.phaseReverse,
        mute: (j['mute'] as bool?) ?? d.mute,
      );
}

/// Factory crossover defaults per group (FRONT, REAR, SUB, HIGH, MID).
const defaultXo = <XoSettings>[
  XoSettings(hpfOn: false, hpfHz: 80, hpfSlope: 12),
  XoSettings(hpfOn: false, hpfHz: 80, hpfSlope: 12),
  XoSettings(lpfOn: true, lpfHz: 80, lpfSlope: 18, linkwitzRiley: false),
  XoSettings(hpfOn: true, hpfHz: 3150, hpfSlope: 24),
  XoSettings(hpfOn: true, hpfHz: 100, hpfSlope: 24, lpfOn: true, lpfHz: 3150, lpfSlope: 24),
];

/// Per-mode algorithmic Sound Field parameters (from assets/carro/sound_fields.json).
class SfTableEntry {
  const SfTableEntry({
    required this.preDelayMs,
    required this.rt60,
    required this.lowMult,
    required this.dampHz,
    required this.erLevelDb,
    required this.lateLevelDb,
    required this.density,
    required this.width,
    required this.roomW,
    required this.roomL,
    required this.roomH,
    required this.wetHpfHz,
    required this.modDepthMs,
    required this.modRateHz,
    required this.wetLpfHz,
  });

  final double preDelayMs, rt60, lowMult, dampHz, erLevelDb, lateLevelDb, density, width;
  final double roomW, roomL, roomH, wetHpfHz, modDepthMs, modRateHz, wetLpfHz;

  static const fields = <String>[
    'preDelayMs', 'rt60', 'lowMult', 'dampHz', 'erLevelDb', 'lateLevelDb', 'density', 'width', //
    'roomW', 'roomL', 'roomH', 'wetHpfHz', 'modDepthMs', 'modRateHz', 'wetLpfHz',
  ];

  static const paramIds = <int>[
    P.sftPreDelayMs, P.sftRt60, P.sftLowMult, P.sftDampHz, P.sftErLevelDb, P.sftLateLevelDb, //
    P.sftDensity, P.sftWidth, P.sftRoomW, P.sftRoomL, P.sftRoomH, P.sftWetHpfHz, P.sftModDepthMs,
    P.sftModRateHz, P.sftWetLpfHz,
  ];

  List<double> get values => [
        preDelayMs, rt60, lowMult, dampHz, erLevelDb, lateLevelDb, density, width, //
        roomW, roomL, roomH, wetHpfHz, modDepthMs, modRateHz, wetLpfHz,
      ];

  factory SfTableEntry.fromValues(List<double> v) => SfTableEntry(
        preDelayMs: v[0],
        rt60: v[1],
        lowMult: v[2],
        dampHz: v[3],
        erLevelDb: v[4],
        lateLevelDb: v[5],
        density: v[6],
        width: v[7],
        roomW: v[8],
        roomL: v[9],
        roomH: v[10],
        wetHpfHz: v[11],
        modDepthMs: v[12],
        modRateHz: v[13],
        wetLpfHz: v[14],
      );

  SfTableEntry withField(String field, double value) {
    final v = values;
    v[fields.indexOf(field)] = value;
    return SfTableEntry.fromValues(v);
  }

  Map<String, Object?> toJson() => {for (var i = 0; i < fields.length; i++) fields[i]: values[i]};

  factory SfTableEntry.fromJson(Map<String, Object?> j) =>
      SfTableEntry.fromValues([for (final f in fields) (j[f] as num?)?.toDouble() ?? 0]);
}

/// A complete sound setting, exactly what the Carrozzeria "AUDIO" menu holds.
class SoundProfile {
  const SoundProfile({
    this.name = 'Default',
    this.sla = 0,
    this.preampDb = 0,
    this.autoHeadroom = true,
    this.asrMode = 0,
    this.eqPreset = 'FLAT',
    this.eqMode = 0,
    this.eqL = const [],
    this.eqR = const [],
    this.eqLinked = true,
    this.custom1 = const [],
    this.custom2 = const [],
    this.loudness = 0,
    this.bassBoost = 0,
    this.sfEngine = 0,
    this.sfMode = 0,
    this.sfLevel = 5,
    this.sfSize = 1,
    this.sfWidth = 1.0,
    this.convDryWet = 1.0,
    this.convPreDelayMs = 0,
    this.loudnessMatch = true,
    this.irTrimStartMs = 0,
    this.irTrimEndMs = 0,
    this.network = false,
    this.xo = defaultXo,
    this.subOn = false,
    this.taOn = false,
    this.taPreset = 'OFF',
    this.taCm = const [0, 0, 0, 0, 0],
    this.scc = 0,
    this.fader = 0,
    this.balance = 0,
    this.outputMode = 0,
    this.crossfeed = 0.5,
    this.limiterOn = true,
    this.limiterCeilDb = -1.0,
  });

  final String name;
  final int sla;
  final double preampDb;
  final bool autoHeadroom;
  final int asrMode;
  final String eqPreset;

  /// 0 = 13-band, 1 = 31-band Pro.
  final int eqMode;

  /// Band gains for the current [eqMode] (13 or 31 values). R is used only when unlinked.
  final List<double> eqL, eqR;
  final bool eqLinked;
  final List<double> custom1, custom2;
  final int loudness, bassBoost;
  final int sfEngine, sfMode, sfLevel, sfSize;
  final double sfWidth, convDryWet, convPreDelayMs;
  final bool loudnessMatch;
  final double irTrimStartMs, irTrimEndMs;
  final bool network;
  final List<XoSettings> xo;
  final bool subOn;
  final bool taOn;
  final String taPreset;
  final List<double> taCm;
  final int scc, fader, balance, outputMode;
  final double crossfeed;
  final bool limiterOn;
  final double limiterCeilDb;

  int get bandCount => eqMode == 1 ? 31 : 13;
  List<double> get bandFreqs => eqMode == 1 ? eq31Freqs : eq13Freqs;
  List<double> get eqLeft => _fit(eqL);
  List<double> get eqRight => eqLinked ? eqLeft : _fit(eqR);

  List<double> _fit(List<double> v) =>
      v.length == bandCount ? v : [...v.take(bandCount), ...List.filled(math.max(0, bandCount - v.length), 0.0)];

  SoundProfile copyWith({
    String? name,
    int? sla,
    double? preampDb,
    bool? autoHeadroom,
    int? asrMode,
    String? eqPreset,
    int? eqMode,
    List<double>? eqL,
    List<double>? eqR,
    bool? eqLinked,
    List<double>? custom1,
    List<double>? custom2,
    int? loudness,
    int? bassBoost,
    int? sfEngine,
    int? sfMode,
    int? sfLevel,
    int? sfSize,
    double? sfWidth,
    double? convDryWet,
    double? convPreDelayMs,
    bool? loudnessMatch,
    double? irTrimStartMs,
    double? irTrimEndMs,
    bool? network,
    List<XoSettings>? xo,
    bool? subOn,
    bool? taOn,
    String? taPreset,
    List<double>? taCm,
    int? scc,
    int? fader,
    int? balance,
    int? outputMode,
    double? crossfeed,
    bool? limiterOn,
    double? limiterCeilDb,
  }) =>
      SoundProfile(
        name: name ?? this.name,
        sla: sla ?? this.sla,
        preampDb: preampDb ?? this.preampDb,
        autoHeadroom: autoHeadroom ?? this.autoHeadroom,
        asrMode: asrMode ?? this.asrMode,
        eqPreset: eqPreset ?? this.eqPreset,
        eqMode: eqMode ?? this.eqMode,
        eqL: eqL ?? this.eqL,
        eqR: eqR ?? this.eqR,
        eqLinked: eqLinked ?? this.eqLinked,
        custom1: custom1 ?? this.custom1,
        custom2: custom2 ?? this.custom2,
        loudness: loudness ?? this.loudness,
        bassBoost: bassBoost ?? this.bassBoost,
        sfEngine: sfEngine ?? this.sfEngine,
        sfMode: sfMode ?? this.sfMode,
        sfLevel: sfLevel ?? this.sfLevel,
        sfSize: sfSize ?? this.sfSize,
        sfWidth: sfWidth ?? this.sfWidth,
        convDryWet: convDryWet ?? this.convDryWet,
        convPreDelayMs: convPreDelayMs ?? this.convPreDelayMs,
        loudnessMatch: loudnessMatch ?? this.loudnessMatch,
        irTrimStartMs: irTrimStartMs ?? this.irTrimStartMs,
        irTrimEndMs: irTrimEndMs ?? this.irTrimEndMs,
        network: network ?? this.network,
        xo: xo ?? this.xo,
        subOn: subOn ?? this.subOn,
        taOn: taOn ?? this.taOn,
        taPreset: taPreset ?? this.taPreset,
        taCm: taCm ?? this.taCm,
        scc: scc ?? this.scc,
        fader: fader ?? this.fader,
        balance: balance ?? this.balance,
        outputMode: outputMode ?? this.outputMode,
        crossfeed: crossfeed ?? this.crossfeed,
        limiterOn: limiterOn ?? this.limiterOn,
        limiterCeilDb: limiterCeilDb ?? this.limiterCeilDb,
      );

  SoundProfile withXo(int group, XoSettings s) {
    final list = [...xo];
    list[group] = s;
    return copyWith(xo: list);
  }

  /// Pushes every parameter to the engine as one atomic update.
  void applyTo(CarroDsp dsp) {
    dsp.batch(() {
      dsp.set(P.slaDb, sla);
      dsp.set(P.preampDb, preampDb);
      dsp.set(P.autoHeadroom, autoHeadroom ? 1 : 0);
      dsp.set(P.asrMode, asrMode);
      dsp.set(P.eqMode, eqMode);
      final l = eqLeft, r = eqRight;
      for (var b = 0; b < 31; b++) {
        dsp.set(P.eqBand, b < l.length ? l[b] : 0, b);
        dsp.set(P.eqBand, b < r.length ? r[b] : 0, 32 + b);
      }
      dsp.set(P.loudness, loudness);
      dsp.set(P.bassBoost, bassBoost);
      dsp.set(P.sfEngine, sfEngine);
      dsp.set(P.sfMode, sfMode);
      dsp.set(P.sfLevel, sfLevel);
      dsp.set(P.sfSize, sfSize);
      dsp.set(P.sfWidth, sfWidth);
      dsp.set(P.sfDryWet, convDryWet);
      dsp.set(P.sfConvPreDelayMs, convPreDelayMs);
      dsp.set(P.sfLoudnessMatch, loudnessMatch ? 1 : 0);
      dsp.set(P.sfIrTrimStartMs, irTrimStartMs);
      dsp.set(P.sfIrTrimEndMs, irTrimEndMs);
      dsp.set(P.xoNetwork, network ? 1 : 0);
      for (var g = 0; g < 5; g++) {
        final x = g < xo.length ? xo[g] : defaultXo[g];
        dsp.set(P.xoHpfOn, x.hpfOn ? 1 : 0, g);
        dsp.set(P.xoHpfHz, x.hpfHz, g);
        dsp.set(P.xoHpfSlope, x.hpfSlope, g);
        dsp.set(P.xoLpfOn, x.lpfOn ? 1 : 0, g);
        dsp.set(P.xoLpfHz, x.lpfHz, g);
        dsp.set(P.xoLpfSlope, x.lpfSlope, g);
        dsp.set(P.xoType, x.linkwitzRiley ? 1 : 0, g);
        dsp.set(P.chLevelDb, x.levelDb, g);
        dsp.set(P.chPhase, x.phaseReverse ? 1 : 0, g);
        dsp.set(P.chMute, x.mute ? 1 : 0, g);
      }
      dsp.set(P.subOn, subOn ? 1 : 0);
      dsp.set(P.taOn, taOn ? 1 : 0);
      for (var s = 0; s < 5; s++) {
        dsp.set(P.taDistCm, s < taCm.length ? taCm[s] : 0, s);
      }
      dsp.set(P.scc, scc);
      dsp.set(P.fader, network ? 0 : fader);
      dsp.set(P.balance, balance);
      dsp.set(P.outputMode, outputMode);
      dsp.set(P.crossfeed, crossfeed);
      dsp.set(P.limiterOn, limiterOn ? 1 : 0);
      dsp.set(P.limiterCeilDb, limiterCeilDb);
    });
  }

  Map<String, Object?> toJson() => {
        'format': 'carrotube.sound/1',
        'name': name,
        'sla': sla,
        'preampDb': preampDb,
        'autoHeadroom': autoHeadroom,
        'asrMode': asrMode,
        'eqPreset': eqPreset,
        'eqMode': eqMode,
        'eqL': eqL,
        'eqR': eqR,
        'eqLinked': eqLinked,
        'custom1': custom1,
        'custom2': custom2,
        'loudness': loudness,
        'bassBoost': bassBoost,
        'sfEngine': sfEngine,
        'sfMode': sfMode,
        'sfLevel': sfLevel,
        'sfSize': sfSize,
        'sfWidth': sfWidth,
        'convDryWet': convDryWet,
        'convPreDelayMs': convPreDelayMs,
        'loudnessMatch': loudnessMatch,
        'irTrimStartMs': irTrimStartMs,
        'irTrimEndMs': irTrimEndMs,
        'network': network,
        'xo': [for (final x in xo) x.toJson()],
        'subOn': subOn,
        'taOn': taOn,
        'taPreset': taPreset,
        'taCm': taCm,
        'scc': scc,
        'fader': fader,
        'balance': balance,
        'outputMode': outputMode,
        'crossfeed': crossfeed,
        'limiterOn': limiterOn,
        'limiterCeilDb': limiterCeilDb,
      };

  static List<double> _list(Object? v) => v is List ? v.map((e) => (e as num).toDouble()).toList() : <double>[];

  factory SoundProfile.fromJson(Map<String, Object?> j) {
    const d = SoundProfile();
    final xoJson = j['xo'];
    final xo = <XoSettings>[
      for (var g = 0; g < 5; g++)
        xoJson is List && g < xoJson.length && xoJson[g] is Map
            ? XoSettings.fromJson((xoJson[g] as Map).cast<String, Object?>(), defaultXo[g])
            : defaultXo[g],
    ];
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    double f(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool b(String k, bool def) => (j[k] as bool?) ?? def;
    final ta = _list(j['taCm']);
    return SoundProfile(
      name: (j['name'] as String?) ?? d.name,
      sla: i('sla', 0).clamp(-4, 4),
      preampDb: f('preampDb', 0),
      autoHeadroom: b('autoHeadroom', true),
      asrMode: i('asrMode', 0).clamp(0, 2),
      eqPreset: (j['eqPreset'] as String?) ?? 'FLAT',
      eqMode: i('eqMode', 0).clamp(0, 1),
      eqL: _list(j['eqL']),
      eqR: _list(j['eqR']),
      eqLinked: b('eqLinked', true),
      custom1: _list(j['custom1']),
      custom2: _list(j['custom2']),
      loudness: i('loudness', 0).clamp(0, 3),
      bassBoost: i('bassBoost', 0).clamp(0, 6),
      sfEngine: i('sfEngine', 0).clamp(0, 1),
      sfMode: i('sfMode', 0).clamp(0, 7),
      sfLevel: i('sfLevel', 5).clamp(0, 10),
      sfSize: i('sfSize', 1).clamp(0, 2),
      sfWidth: f('sfWidth', 1),
      convDryWet: f('convDryWet', 1),
      convPreDelayMs: f('convPreDelayMs', 0),
      loudnessMatch: b('loudnessMatch', true),
      irTrimStartMs: f('irTrimStartMs', 0),
      irTrimEndMs: f('irTrimEndMs', 0),
      network: b('network', false),
      xo: xo,
      subOn: b('subOn', false),
      taOn: b('taOn', false),
      taPreset: (j['taPreset'] as String?) ?? 'OFF',
      taCm: ta.length == 5 ? ta : const [0, 0, 0, 0, 0],
      scc: i('scc', 0).clamp(-15, 15),
      fader: i('fader', 0).clamp(-15, 15),
      balance: i('balance', 0).clamp(-15, 15),
      outputMode: i('outputMode', 0).clamp(0, 1),
      crossfeed: f('crossfeed', 0.5),
      limiterOn: b('limiterOn', true),
      limiterCeilDb: f('limiterCeilDb', -1),
    );
  }
}
