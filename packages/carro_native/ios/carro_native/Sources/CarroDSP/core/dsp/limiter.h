// Stereo-linked true-peak brickwall limiter.
//   detector : 4x polyphase interpolation estimates inter-sample peaks
//   gain     : sliding minimum over the look-ahead window, exponential release, then a
//              box-car smoother of the same length. Because every box-car input already
//              includes the peak's own requirement, the applied gain is guaranteed <= the
//              required gain at the peak -> no overs, no clicks.
#pragma once

#include <vector>

#include "common.h"

namespace carro {

class TruePeakLimiter {
 public:
  void prepare(double fs);
  void setCeilingDb(float db) { ceiling_ = dbToGain(clampf(db, -12.0f, 0.0f)); }
  void setEnabled(bool on) { enabled_ = on; }
  void reset();
  void process(float* L, float* R, int n);
  int latency() const { return latency_; }
  float lastMinGain() const { return minGainBlock_; }

 private:
  static constexpr int kTaps = 16;     // per polyphase branch
  static constexpr int kPhases = 4;
  float interpPeak(const float* hist) const;

  double fs_ = 48000.0;
  bool enabled_ = true;
  float ceiling_ = 0.891f;
  int look_ = 72;    // look-ahead L
  int latency_ = 0;  // detector delay + L - 1
  float relCoef_ = 0.999f;

  float fir_[kPhases][kTaps] = {};
  // detector history (per channel, mirrored ring for contiguous reads)
  std::vector<float> histL_, histR_;
  int histPos_ = 0;
  float prevInterval_ = 0.0f;  // inter-sample peak of the previous interval

  // sliding minimum (monotonic deque in a ring)
  std::vector<float> dqVal_;
  std::vector<uint32_t> dqIdx_;
  int dqHead_ = 0, dqTail_ = 0, dqCap_ = 0;
  uint32_t sampleIdx_ = 0;
  float released_ = 1.0f;

  // box-car smoother
  std::vector<float> box_;
  int boxPos_ = 0;
  double boxSum_ = 0.0;

  // audio delay line
  std::vector<float> delL_, delR_;
  int delPos_ = 0;
  float minGainBlock_ = 1.0f;
};

}  // namespace carro
