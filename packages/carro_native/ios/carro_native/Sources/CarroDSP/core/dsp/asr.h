// Advanced Sound Retriever (ASR). Restores what lossy codecs remove:
//   1) level-independent 2nd/3rd-harmonic exciter on the top octaves (re-creates the
//      "air" cut away by the codec's low-pass), and
//   2) transient restore: a fast/slow envelope ratio lifts attacks that psycho-acoustic
//      coding smears.
// MODE1 is gentle, MODE2 is stronger (lower corner, more harmonics, more transient lift),
// matching the behaviour of the Pioneer function.
#pragma once

#include "biquad.h"

namespace carro {

class Asr {
 public:
  void prepare(double fs);
  void setMode(int mode);  // 0 OFF, 1 MODE1, 2 MODE2 (smoothly cross-faded)
  void reset();
  void process(float* L, float* R, int n);

 private:
  struct Channel {
    Biquad split1, split2;  // HPF 2x (Linkwitz-Riley 4) -> band to excite
    Biquad post;            // HPF after the waveshaper removes low intermod products
    OnePole env;            // band envelope for level-independent harmonics
  };
  double fs_ = 48000.0;
  int mode_ = 0;
  float splitHz_ = 3500.0f;
  Channel ch_[2];
  Smoother exciteAmt_, transAmt_;
  // Transient detector on mid signal.
  float fastEnv_ = 0.0f, slowEnv_ = 0.0f;
  float fastAtt_ = 0, fastRel_ = 0, slowAtt_ = 0, slowRel_ = 0;
  float gainSmooth_ = 1.0f, gainCoef_ = 0.0f;
  float maxLift_ = 1.0f;
  void designSplit();
};

}  // namespace carro
