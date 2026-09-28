#include "limiter.h"

namespace carro {

void TruePeakLimiter::prepare(double fs) {
  fs_ = fs;
  look_ = std::max(8, static_cast<int>(0.0015 * fs));  // 1.5 ms look-ahead
  latency_ = kTaps / 2 + look_ - 1;
  relCoef_ = static_cast<float>(std::exp(-1.0 / (0.080 * fs)));  // 80 ms release

  // 4x interpolation FIR: Blackman-windowed sinc, half-width kTaps/2.
  for (int ph = 0; ph < kPhases; ++ph) {
    double sum = 0.0;
    for (int k = 0; k < kTaps; ++k) {
      const double t = k - (kTaps / 2 - 1) - ph / static_cast<double>(kPhases);
      const double sinc = std::fabs(t) < 1e-9 ? 1.0 : std::sin(kPi * t) / (kPi * t);
      const double x = (t + kTaps / 2.0) / kTaps;  // 0..1 across the window
      const double w = (x <= 0.0 || x >= 1.0) ? 0.0
                                              : 0.42 - 0.5 * std::cos(2 * kPi * x) + 0.08 * std::cos(4 * kPi * x);
      fir_[ph][k] = static_cast<float>(sinc * w);
      sum += sinc * w;
    }
    for (int k = 0; k < kTaps; ++k) fir_[ph][k] = static_cast<float>(fir_[ph][k] / sum);
  }
  histL_.assign(2 * kTaps, 0.0f);
  histR_.assign(2 * kTaps, 0.0f);
  dqCap_ = look_ + 2;
  dqVal_.assign(dqCap_, 1.0f);
  dqIdx_.assign(dqCap_, 0);
  box_.assign(look_, 1.0f);
  delL_.assign(latency_, 0.0f);
  delR_.assign(latency_, 0.0f);
  reset();
}

void TruePeakLimiter::reset() {
  std::fill(histL_.begin(), histL_.end(), 0.0f);
  std::fill(histR_.begin(), histR_.end(), 0.0f);
  histPos_ = 0;
  prevInterval_ = 0.0f;
  dqHead_ = dqTail_ = 0;
  sampleIdx_ = 0;
  released_ = 1.0f;
  std::fill(box_.begin(), box_.end(), 1.0f);
  boxPos_ = 0;
  boxSum_ = static_cast<double>(look_);
  std::fill(delL_.begin(), delL_.end(), 0.0f);
  std::fill(delR_.begin(), delR_.end(), 0.0f);
  delPos_ = 0;
}

// Largest |interpolated| value strictly between hist[kTaps/2-1] and hist[kTaps/2].
float TruePeakLimiter::interpPeak(const float* h) const {
  float m = 0.0f;
  for (int ph = 1; ph < kPhases; ++ph) {
    float acc = 0.0f;
    for (int k = 0; k < kTaps; ++k) acc += fir_[ph][k] * h[k];
    m = std::max(m, std::fabs(acc));
  }
  return m;
}

void TruePeakLimiter::process(float* L, float* R, int n) {
  float minG = 1.0f;
  const int latLen = latency_;
  const float relStep = 1.0f - relCoef_;
  for (int i = 0; i < n; ++i) {
    // --- detector (mirrored ring so the last kTaps samples are contiguous) ---
    histL_[histPos_] = histL_[histPos_ + kTaps] = L[i];
    histR_[histPos_] = histR_[histPos_ + kTaps] = R[i];
    histPos_ = (histPos_ + 1) % kTaps;
    const float* hl = &histL_[histPos_];  // oldest .. newest
    const float* hr = &histR_[histPos_];
    const int c = kTaps / 2 - 1;  // sample under test = n - 8
    const float interval = std::max(interpPeak(hl), interpPeak(hr));
    const float peak = std::max(std::max(std::fabs(hl[c]), std::fabs(hr[c])), std::max(interval, prevInterval_));
    prevInterval_ = interval;
    const float d = (enabled_ && peak > ceiling_) ? ceiling_ / peak : 1.0f;

    // --- sliding minimum over the look-ahead window ---
    const uint32_t j = sampleIdx_++;
    while (dqTail_ != dqHead_) {
      const int back = (dqTail_ - 1 + dqCap_) % dqCap_;
      if (dqVal_[back] >= d) dqTail_ = back; else break;
    }
    dqVal_[dqTail_] = d;
    dqIdx_[dqTail_] = j;
    dqTail_ = (dqTail_ + 1) % dqCap_;
    while (static_cast<int32_t>(j - dqIdx_[dqHead_]) >= look_) dqHead_ = (dqHead_ + 1) % dqCap_;
    const float m = dqVal_[dqHead_];

    // --- release, then box-car ---
    float r = released_ + (1.0f - released_) * relStep;
    if (m < r) r = m;
    released_ = r;
    boxSum_ += static_cast<double>(r) - box_[boxPos_];
    box_[boxPos_] = r;
    if (++boxPos_ == look_) {
      boxPos_ = 0;
      double s = 0.0;  // periodic exact re-sum kills floating-point drift
      for (float v : box_) s += v;
      boxSum_ = s;
    }
    const float g = static_cast<float>(boxSum_ / look_);
    minG = std::min(minG, g);

    // --- delayed audio ---
    const float dl = delL_[delPos_], dr = delR_[delPos_];
    delL_[delPos_] = L[i];
    delR_[delPos_] = R[i];
    delPos_ = (delPos_ + 1) % latLen;
    float ol = dl * g, orr = dr * g;
    // Final safety net (never engages in normal operation).
    ol = clampf(ol, -1.0f, 1.0f);
    orr = clampf(orr, -1.0f, 1.0f);
    L[i] = ol;
    R[i] = orr;
  }
  minGainBlock_ = minG;
}

}  // namespace carro
