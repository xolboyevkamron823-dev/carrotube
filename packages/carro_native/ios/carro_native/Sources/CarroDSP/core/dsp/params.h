// Complete engine parameter snapshot. Plain-old-data so it can be copied through the
// lock-free triple buffer. Written only by the control side, read by the audio thread.
#pragma once

#include <cstdint>
#include <cstring>

namespace carro {

constexpr int kNumSfModes = 8;  // OFF + 7 fields
constexpr int kNumGroups = 5;   // FRONT, REAR, SUB, HIGH, MID
constexpr int kNumSpeakers = 5; // FL/HL, FR/HR, RL/ML, RR/MR, SUB
constexpr int kEqMaxBands = 31;

enum Group { kFront = 0, kRear = 1, kSub = 2, kHigh = 3, kMid = 4 };

// 13-band Carrozzeria GEQ centres and the 31-band ISO 1/3-octave centres.
constexpr float kEq13Freqs[13] = {50, 80, 125, 200, 315, 500, 800, 1250, 2000, 3150, 5000, 8000, 12500};
constexpr float kEq31Freqs[31] = {20,   25,   31.5f, 40,   50,   63,   80,   100,  125,  160,  200,
                                  250,  315,  400,   500,  630,  800,  1000, 1250, 1600, 2000, 2500,
                                  3150, 4000, 5000,  6300, 8000, 10000, 12500, 16000, 20000};
// Q for 2/3-octave (13-band) and 1/3-octave (31-band) constant-Q peaking bands.
constexpr float kEq13Q = 2.15f;
constexpr float kEq31Q = 4.32f;

struct XoverGroup {
  int hpfOn = 0;
  float hpfHz = 80.0f;
  int hpfSlope = 12;
  int lpfOn = 0;
  float lpfHz = 80.0f;
  int lpfSlope = 12;
  int type = 1;  // 0 BW, 1 LR
  float levelDb = 0.0f;
  int phaseInvert = 0;
  int mute = 0;
};

struct SfModeParams {
  float preDelayMs = 25.0f;
  float rt60 = 2.0f;
  float lowMult = 1.2f;
  float dampHz = 6000.0f;
  float erLevelDb = -3.0f;
  float lateLevelDb = 0.0f;
  float density = 0.7f;
  float width = 1.0f;
  float roomW = 20.0f, roomL = 30.0f, roomH = 12.0f;
  float wetHpfHz = 150.0f;
  float modDepthMs = 0.35f;
  float modRateHz = 0.5f;
  float wetLpfHz = 12000.0f;
};

struct EngineParams {
  int bypass = 0;
  float slaDb = 0.0f;
  float preampDb = 0.0f;
  int autoHeadroom = 1;

  int asrMode = 0;

  int eqMode = 0;
  float eq[2][kEqMaxBands] = {};

  int loudness = 0;
  int bassBoost = 0;

  int sfEngine = 0;
  int sfMode = 0;
  int sfLevel = 5;
  int sfSize = 1;
  float sfWidth = 1.0f;
  float convDryWet = 1.0f;
  float convPreDelayMs = 0.0f;
  int loudnessMatch = 1;
  float irTrimStartMs = 0.0f;
  float irTrimEndMs = 0.0f;
  SfModeParams sfTable[kNumSfModes];
  // Derived by the control side: wet normalisation for the current algorithmic mode/size.
  float algoWetNorm = 1.0f;
  // Bumped whenever the convolver object changes (so the audio thread can fade).
  uint32_t irGeneration = 0;

  int network = 0;
  XoverGroup xo[kNumGroups];
  int subOn = 0;

  int taOn = 0;
  float taDistCm[kNumSpeakers] = {0, 0, 0, 0, 0};

  int scc = 0;
  int fader = 0;
  int balance = 0;
  int outputMode = 0;
  float crossfeed = 0.5f;

  int limiterOn = 1;
  float limiterCeilDb = -1.0f;

  // Bumped by carro_reset().
  uint32_t resetCounter = 0;

  EngineParams();
};

// Factory defaults close to a freshly reset Carrozzeria unit.
inline EngineParams::EngineParams() {
  xo[kFront].hpfOn = 0; xo[kFront].hpfHz = 80; xo[kFront].hpfSlope = 12;
  xo[kRear].hpfOn = 0;  xo[kRear].hpfHz = 80;  xo[kRear].hpfSlope = 12;
  xo[kSub].lpfOn = 1;   xo[kSub].lpfHz = 80;   xo[kSub].lpfSlope = 18; xo[kSub].type = 0;
  xo[kHigh].hpfOn = 1;  xo[kHigh].hpfHz = 3150; xo[kHigh].hpfSlope = 24;
  xo[kMid].hpfOn = 1;   xo[kMid].hpfHz = 100;  xo[kMid].hpfSlope = 24;
  xo[kMid].lpfOn = 1;   xo[kMid].lpfHz = 3150; xo[kMid].lpfSlope = 24;
  // Default hall table (overridden by assets/carro/sound_fields.json at startup).
  const float t[kNumSfModes][15] = {
      // pre  rt60 lowM damp  er    late dens width W    L    H    hpf  modD  modR lpf
      {0,    0.1f, 1.0f, 8000, -60, -60, 0.0f, 1.0f, 5,   5,   3,   150, 0.0f, 0.5f, 12000},  // OFF
      {8,    0.45f,1.0f, 9000, -2,  -6,  0.60f,0.8f, 6,   8,   3.5f,150, 0.20f, 0.7f, 14000}, // STUDIO
      {14,   0.85f,1.1f, 6000, -3,  -4,  0.65f,0.9f, 10,  14,  4,   150, 0.30f, 0.6f, 11000}, // JAZZ CLUB
      {26,   2.0f, 1.25f,5500, -4,  -1,  0.75f,1.1f, 24,  38,  15,  150, 0.35f, 0.45f,12000}, // CONCERT HALL
      {35,   3.6f, 1.35f,4200, -6,  0,   0.85f,1.2f, 30,  60,  25,  150, 0.40f, 0.35f,10000}, // CATHEDRAL
      {45,   2.6f, 1.1f, 3500, -9,  -2,  0.55f,1.4f, 120, 160, 30,  160, 0.45f, 0.30f, 9000}, // STADIUM
      {18,   1.2f, 1.15f,5000, -2,  -3,  0.70f,1.0f, 16,  24,  7,   150, 0.30f, 0.55f,11000}, // LIVE
      {30,   2.9f, 1.2f, 4800, -5,  -1,  0.80f,1.3f, 40,  40,  30,  150, 0.40f, 0.40f,10500}, // DOME
  };
  for (int m = 0; m < kNumSfModes; ++m) {
    SfModeParams& s = sfTable[m];
    s.preDelayMs = t[m][0]; s.rt60 = t[m][1]; s.lowMult = t[m][2]; s.dampHz = t[m][3];
    s.erLevelDb = t[m][4]; s.lateLevelDb = t[m][5]; s.density = t[m][6]; s.width = t[m][7];
    s.roomW = t[m][8]; s.roomL = t[m][9]; s.roomH = t[m][10]; s.wetHpfHz = t[m][11];
    s.modDepthMs = t[m][12]; s.modRateHz = t[m][13]; s.wetLpfHz = t[m][14];
  }
}

// Size S/M/L scale factors: (dimensions, RT60, pre-delay).
inline void sizeScale(int size, float& dim, float& rt, float& pre) {
  switch (size) {
    case 0: dim = 0.8f; rt = 0.82f; pre = 0.75f; break;
    case 2: dim = 1.25f; rt = 1.22f; pre = 1.25f; break;
    default: dim = 1.0f; rt = 1.0f; pre = 1.0f; break;
  }
}

}  // namespace carro
