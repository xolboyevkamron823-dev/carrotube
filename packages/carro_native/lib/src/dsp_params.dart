/// Parameter ids of the C++ engine. Keep in sync with `src/carro_api.h`.
abstract final class P {
  static const bypass = 0;
  static const slaDb = 1;
  static const preampDb = 2;
  static const autoHeadroom = 3;

  static const asrMode = 10;

  static const eqMode = 20;
  static const eqBand = 21; // index = channel * 32 + band

  static const loudness = 30;
  static const bassBoost = 31;

  static const sfEngine = 40;
  static const sfMode = 41;
  static const sfLevel = 42;
  static const sfSize = 43;
  static const sfWidth = 44;
  static const sfDryWet = 45;
  static const sfConvPreDelayMs = 46;
  static const sfLoudnessMatch = 47;
  static const sfIrTrimStartMs = 48;
  static const sfIrTrimEndMs = 49;

  // per-mode table, index = mode 1..7
  static const sftPreDelayMs = 60;
  static const sftRt60 = 61;
  static const sftLowMult = 62;
  static const sftDampHz = 63;
  static const sftErLevelDb = 64;
  static const sftLateLevelDb = 65;
  static const sftDensity = 66;
  static const sftWidth = 67;
  static const sftRoomW = 68;
  static const sftRoomL = 69;
  static const sftRoomH = 70;
  static const sftWetHpfHz = 71;
  static const sftModDepthMs = 72;
  static const sftModRateHz = 73;
  static const sftWetLpfHz = 74;

  // crossover, index = group
  static const xoNetwork = 80;
  static const xoHpfOn = 81;
  static const xoHpfHz = 82;
  static const xoHpfSlope = 83;
  static const xoLpfOn = 84;
  static const xoLpfHz = 85;
  static const xoLpfSlope = 86;
  static const xoType = 87;
  static const chLevelDb = 88;
  static const chPhase = 89;
  static const chMute = 90;
  static const subOn = 91;

  // time alignment, index = speaker slot
  static const taOn = 100;
  static const taDistCm = 101;

  static const scc = 110;
  static const fader = 111;
  static const balance = 112;
  static const outputMode = 113;
  static const crossfeed = 114;

  static const limiterOn = 120;
  static const limiterCeilDb = 121;
}

/// Crossover groups (index for the xo*/ch* parameters).
abstract final class XoGroup {
  static const front = 0;
  static const rear = 1;
  static const sub = 2;
  static const high = 3;
  static const mid = 4;
}

/// Curves for [CarroDsp.response].
abstract final class Curve {
  static const eqL = 0;
  static const eqR = 1;
  static const tone = 2;
  static int group(int g) => 10 + g;
}

/// Sound Field modes in head-unit order.
const soundFieldModes = <String>[
  'OFF',
  'STUDIO',
  'JAZZ CLUB',
  'CONCERT HALL',
  'CATHEDRAL',
  'STADIUM',
  'LIVE',
  'DOME',
];

/// 13-band Carrozzeria GEQ centre frequencies.
const eq13Freqs = <double>[50, 80, 125, 200, 315, 500, 800, 1250, 2000, 3150, 5000, 8000, 12500];

/// 31-band ISO 1/3-octave centre frequencies (Pro mode).
const eq31Freqs = <double>[
  20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, //
  1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
];

/// Carrozzeria crossover frequency steps (25 Hz .. 12.5 kHz, 1/3-octave).
const crossoverFreqs = <double>[
  25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, //
  1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500,
];

const crossoverSlopes = <int>[6, 12, 18, 24, 30, 36];
