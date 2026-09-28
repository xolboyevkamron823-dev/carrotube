// Graphic EQ (13-band Carrozzeria / 31-band Pro) and the Loudness + Bass Boost tone stage.
// All gain changes are smoothed and coefficients are re-designed every 32 samples while a
// band is moving, which avoids zipper noise and clicks.
#pragma once

#include "biquad.h"
#include "params.h"

namespace carro {

// One stereo filter with independent smoothed gains for L and R.
class SmoothedPeq {
 public:
  static constexpr int kSub = 32;
  void configure(FilterType type, float freq, float q, double fs);
  void setTarget(float dbL, float dbR) {
    gl_.setTarget(dbL);
    gr_.setTarget(dbR);
  }
  void snap();
  void reset() {
    l_.reset();
    r_.reset();
  }
  void process(float* L, float* R, int n);
  float freq() const { return freq_; }
  float q() const { return q_; }
  FilterType type() const { return type_; }
  float currentDb(int ch) const { return ch == 0 ? gl_.current() : gr_.current(); }

 private:
  void redesign(int ch, float db);
  FilterType type_ = FilterType::Peak;
  float freq_ = 1000.0f, q_ = 1.0f;
  double fs_ = 48000.0;
  Biquad l_, r_;
  Smoother gl_, gr_;
  float designedL_ = 1e9f, designedR_ = 1e9f;
};

class GraphicEq {
 public:
  void prepare(double fs);
  // Structural change: only called while the engine output is faded out.
  void setMode(int mode);
  int mode() const { return mode_; }
  void setTargets(const float gains[2][kEqMaxBands]);
  void snap();
  void reset();
  void process(float* L, float* R, int n);
  int bandCount() const { return count_; }
  static const float* freqsForMode(int mode, int& count, float& q);

 private:
  double fs_ = 48000.0;
  int mode_ = 0;
  int count_ = 13;
  SmoothedPeq bands_[kEqMaxBands];
};

// Loudness (OFF/LOW/MID/HIGH low+high shelves) and Bass Boost (0..6, 60 Hz peak).
class ToneStage {
 public:
  void prepare(double fs);
  void setTargets(int loudness, int bassBoost);
  void snap();
  void reset();
  void process(float* L, float* R, int n);
  // Static design helpers used by the response API.
  static void loudnessGains(int loudness, float& lowDb, float& highDb);
  static float bassBoostDb(int bassBoost) { return 1.5f * static_cast<float>(clampi(bassBoost, 0, 6)); }
  static constexpr float kLoudLowHz = 100.0f, kLoudHighHz = 10000.0f, kBassHz = 60.0f, kBassQ = 0.8f;

 private:
  SmoothedPeq lowShelf_, highShelf_, bass_;
};

}  // namespace carro
