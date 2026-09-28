// Algorithmic Sound Field reverb, tuned to the Carrozzeria character:
//   pre-delay -> image-source early reflections (24 taps per source, orders 1..2)
//             -> 4-stage allpass input diffusion -> 8x8 Hadamard feedback delay network
//   FDN lines are slowly modulated (no metallic ringing) and each line has a two-band
//   decay filter (low shelf multiplier + mid gain) followed by HF damping.
//   The wet signal is width-controlled (M/S), high-passed at ~150 Hz (keeps car bass tight)
//   and gently low-passed.
#pragma once

#include <vector>

#include "biquad.h"
#include "params.h"

namespace carro {

constexpr int kFdnLines = 8;
constexpr int kMaxErTaps = 48;
constexpr int kDiffusers = 4;

struct ErTap {
  int delay = 0;  // samples after the pre-delay
  float gL = 0, gR = 0;
  int src = 0;  // 0 = left input, 1 = right input
};

// Everything the audio thread needs for one mode/size, computed without allocation.
struct ReverbDesign {
  bool active = false;
  int preDelay = 0;
  int lateOnset = 0;
  int lineLen[kFdnLines] = {};
  float gMid[kFdnLines] = {}, gLow[kFdnLines] = {};
  int apLen[2][kDiffusers] = {};
  float apGain = 0.6f;
  ErTap taps[kMaxErTaps];
  int numTaps = 0;
  float erGain = 0.5f, lateGain = 1.0f, width = 1.0f;
  float lowXoverHz = 250.0f, dampHz = 6000.0f;
  float dampA[kFdnLines] = {};  // per-line one-pole HF damping (RT60 halves at dampHz)
  float modDepth = 0.0f;  // samples
  float modRateHz = 0.5f;
  float hpfHz = 150.0f, lpfHz = 12000.0f;
};

void designReverb(const SfModeParams& p, int size, float widthMul, double fs, ReverbDesign& out);

class AlgoReverb {
 public:
  // Allocates all buffers for the largest possible room at this sample rate.
  void prepare(double fs);
  // Applies a new design. No allocation. Clears the reverb memory.
  void apply(const ReverbDesign& d);
  void reset();
  // Writes the 100% wet signal. Input and output may alias.
  void process(const float* inL, const float* inR, float* outL, float* outR, int n);
  const ReverbDesign& design() const { return d_; }
  // Renders the stereo impulse response of a design (control thread, allocates).
  static void renderImpulse(const ReverbDesign& d, double fs, int frames, std::vector<float>& outL,
                            std::vector<float>& outR);

 private:
  struct Line {
    std::vector<float> buf;
    int mask = 0;
    OnePole low;   // low band split
    OnePole damp;  // HF damping
    float oscS = 0, oscC = 1, oscK = 0;
  };
  struct Diffuser {
    std::vector<float> buf;
    int mask = 0;
    int len = 1;
  };
  double fs_ = 48000.0;
  ReverbDesign d_;
  std::vector<float> in_[2];
  int inMask_ = 0;
  int w_ = 0;
  Line lines_[kFdnLines];
  Diffuser ap_[2][kDiffusers];
  StereoBiquad hpf_, lpf_;
};

}  // namespace carro
