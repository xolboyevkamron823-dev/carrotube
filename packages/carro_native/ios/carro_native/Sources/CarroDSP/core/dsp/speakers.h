// Virtual speaker matrix: Carrozzeria crossover (Standard / Network 3-way), per-channel
// level and phase, time alignment, Sonic Center Control, fader/balance and the fold-down
// of the virtual car speakers to the phone's stereo output (with optional headphone
// crossfeed).
//
//   Standard : FRONT L/R (HPF) + REAR L/R (HPF) + SUB mono (LPF)
//   Network  : HIGH L/R (HPF)  + MID L/R (HPF+LPF) + SUB mono (LPF)
//
// Each virtual speaker has its own delay (TA distance model: delay = (dmax - d) / c), so on a
// phone/headphones the TA and SCC settings become inter-channel delays exactly like the
// head unit applies them to its RCA outputs.
#pragma once

#include <vector>

#include "biquad.h"
#include "params.h"

namespace carro {

class SpeakerMatrix {
 public:
  void prepare(double fs, int maxBlock);
  // Structural settings (network mode, filter on/off, slope, type). Engine output is faded
  // out while this runs. Resets filter memories.
  void applyStructure(const EngineParams& p);
  // Smoothly-changing settings (frequencies, levels, phase, delays, fader, balance).
  void setTargets(const EngineParams& p);
  void snap();
  void reset();
  void process(float* L, float* R, int n);

  static bool structureDiffers(const EngineParams& a, const EngineParams& b);
  // Static helpers shared with the response/graph API.
  static void computeSpeakerDelaysSamples(const EngineParams& p, double fs, float out[kNumSpeakers]);

 private:
  struct GroupDsp {
    bool active = false;
    bool hpfOn = false, lpfOn = false;
    int hpfSlope = 12, lpfSlope = 12;
    bool lr = true;
    Smoother hpfLogHz, lpfLogHz, gain;  // gain is signed (phase) linear
    float designedHpf = -1, designedLpf = -1;
    FilterCascade hpf, lpf;
    // per-channel states (index 0 = L, 1 = R; mono sub uses 0)
    Biquad hpfState[2][FilterCascade::kMaxSections];
    Biquad lpfState[2][FilterCascade::kMaxSections];
    void redesign(double fs, bool force);
    void resetStates();
  };
  struct DelayLine {
    std::vector<float> buf;
    int mask = 0;
    int w = 0;
    Smoother delay;  // samples (fractional)
    void init(int maxDelay);
    void clear();
  };

  double fs_ = 48000.0;
  int network_ = 0;
  bool subOn_ = false;
  int outputMode_ = 0;
  GroupDsp g_[kNumGroups];
  DelayLine del_[kNumSpeakers];
  Smoother gFront_, gRear_, gBalL_, gBalR_, crossfeed_;
  // crossfeed state
  OnePole xfLpL_, xfLpR_;
  std::vector<float> xfBufL_, xfBufR_;
  int xfPos_ = 0, xfDelay_ = 1;
  // scratch
  std::vector<float> a_[2], b_[2], sub_;
};

}  // namespace carro
