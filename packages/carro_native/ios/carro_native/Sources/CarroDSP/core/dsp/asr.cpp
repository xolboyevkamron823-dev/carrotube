#include "asr.h"

namespace carro {

namespace {
float coefFor(double ms, double fs) { return static_cast<float>(std::exp(-1.0 / (std::max(0.05, ms) * 0.001 * fs))); }
}  // namespace

void Asr::prepare(double fs) {
  fs_ = fs;
  exciteAmt_.setTime(60.0f, fs);
  transAmt_.setTime(60.0f, fs);
  fastAtt_ = coefFor(0.5, fs);
  fastRel_ = coefFor(25.0, fs);
  slowAtt_ = coefFor(40.0, fs);
  slowRel_ = coefFor(250.0, fs);
  gainCoef_ = coefFor(2.0, fs);
  for (auto& c : ch_) c.env.setCutoff(20.0, fs);
  designSplit();
  exciteAmt_.snap(exciteAmt_.target());
  transAmt_.snap(transAmt_.target());
  reset();
}

void Asr::designSplit() {
  const float corner = mode_ == 2 ? 2500.0f : 3500.0f;
  splitHz_ = corner;
  for (auto& c : ch_) {
    c.split1.c = designFilter(FilterType::HighPass, fs_, corner, 0.7071, 0);
    c.split2.c = c.split1.c;
    c.post.c = designFilter(FilterType::HighPass, fs_, std::min<double>(corner * 1.6, fs_ * 0.45), 0.7071, 0);
  }
}

void Asr::setMode(int mode) {
  mode = clampi(mode, 0, 2);
  if (mode != mode_ && mode != 0) {
    mode_ = mode;
    designSplit();
  } else {
    mode_ = mode;
  }
  // exciter mix (linear) and transient amount
  const float ex = mode == 0 ? 0.0f : (mode == 1 ? 0.10f : 0.20f);
  const float tr = mode == 0 ? 0.0f : (mode == 1 ? 0.35f : 0.65f);
  exciteAmt_.setTarget(ex);
  transAmt_.setTarget(tr);
  maxLift_ = mode == 2 ? dbToGain(4.0f) : dbToGain(2.0f);
}

void Asr::reset() {
  for (auto& c : ch_) {
    c.split1.reset();
    c.split2.reset();
    c.post.reset();
    c.env.reset();
  }
  fastEnv_ = slowEnv_ = 0.0f;
  gainSmooth_ = 1.0f;
}

void Asr::process(float* L, float* R, int n) {
  if (exciteAmt_.settled() && exciteAmt_.current() == 0.0f && transAmt_.settled() &&
      transAmt_.current() == 0.0f) {
    return;  // fully off
  }
  float* io[2] = {L, R};
  for (int i = 0; i < n; ++i) {
    const float ex = exciteAmt_.next();
    const float tr = transAmt_.next();

    // --- transient restore (linked stereo) ---
    const float mid = 0.5f * std::fabs(L[i] + R[i]) + 0.5f * std::fabs(L[i] - R[i]);
    fastEnv_ = mid > fastEnv_ ? mid + fastAtt_ * (fastEnv_ - mid) : mid + fastRel_ * (fastEnv_ - mid);
    slowEnv_ = mid > slowEnv_ ? mid + slowAtt_ * (slowEnv_ - mid) : mid + slowRel_ * (slowEnv_ - mid);
    float target = 1.0f;
    if (slowEnv_ > 1e-5f) {
      const float ratio = fastEnv_ / slowEnv_;
      if (ratio > 1.0f) target = std::min(maxLift_, 1.0f + tr * (ratio - 1.0f));
    }
    gainSmooth_ = target + gainCoef_ * (gainSmooth_ - target);
    const float tg = gainSmooth_;

    for (int c = 0; c < 2; ++c) {
      Channel& ch = ch_[c];
      const float x = io[c][i];
      // --- harmonic exciter ---
      float band = ch.split2.process(ch.split1.process(x));
      const float e = ch.env.process(std::fabs(band)) + 1e-6f;
      // band*|band|/env: 2nd harmonic at the band's own level; cubic term adds 3rd.
      const float nrm = clampf(band / e, -2.0f, 2.0f);
      float h = band * std::fabs(nrm) * 0.5f + band * nrm * nrm * 0.15f;
      h = ch.post.process(h);
      io[c][i] = (x + ex * h) * tg;
    }
  }
}

}  // namespace carro
