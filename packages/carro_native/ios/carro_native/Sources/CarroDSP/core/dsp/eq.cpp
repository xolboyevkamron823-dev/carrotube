#include "eq.h"

namespace carro {

// ---------------------------------------------------------------------------------------------
void SmoothedPeq::configure(FilterType type, float freq, float q, double fs) {
  type_ = type;
  freq_ = freq;
  q_ = q;
  fs_ = fs;
  gl_.setTime(40.0f, fs);
  gr_.setTime(40.0f, fs);
  designedL_ = designedR_ = 1e9f;
  redesign(0, gl_.current());
  redesign(1, gr_.current());
}

void SmoothedPeq::snap() {
  gl_.snap(gl_.target());
  gr_.snap(gr_.target());
  redesign(0, gl_.current());
  redesign(1, gr_.current());
}

void SmoothedPeq::redesign(int ch, float db) {
  float& designed = ch == 0 ? designedL_ : designedR_;
  if (std::fabs(designed - db) < 1e-4f) return;
  designed = db;
  const BiquadCoeffs c = designFilter(type_, fs_, freq_, q_, db);
  (ch == 0 ? l_ : r_).c = c;
}

void SmoothedPeq::process(float* L, float* R, int n) {
  int off = 0;
  while (off < n) {
    const int m = std::min(kSub, n - off);
    if (!gl_.settled()) redesign(0, gl_.advance(m));
    if (!gr_.settled()) redesign(1, gr_.advance(m));
    // A settled 0 dB band is an identity filter: skip it once its memory has decayed.
    const bool skipL = gl_.settled() && gl_.current() == 0.0f && std::fabs(l_.z1) + std::fabs(l_.z2) < 1e-9f;
    const bool skipR = gr_.settled() && gr_.current() == 0.0f && std::fabs(r_.z1) + std::fabs(r_.z2) < 1e-9f;
    if (!skipL) l_.processBlock(L + off, m); else l_.reset();
    if (!skipR) r_.processBlock(R + off, m); else r_.reset();
    off += m;
  }
}

// ---------------------------------------------------------------------------------------------
const float* GraphicEq::freqsForMode(int mode, int& count, float& q) {
  if (mode == 1) {
    count = 31;
    q = kEq31Q;
    return kEq31Freqs;
  }
  count = 13;
  q = kEq13Q;
  return kEq13Freqs;
}

void GraphicEq::prepare(double fs) {
  fs_ = fs;
  setMode(mode_);
}

void GraphicEq::setMode(int mode) {
  mode_ = mode == 1 ? 1 : 0;
  float q;
  const float* f = freqsForMode(mode_, count_, q);
  for (int i = 0; i < count_; ++i) {
    bands_[i].configure(FilterType::Peak, f[i], q, fs_);
    bands_[i].reset();
  }
}

void GraphicEq::setTargets(const float gains[2][kEqMaxBands]) {
  for (int i = 0; i < count_; ++i)
    bands_[i].setTarget(clampf(gains[0][i], -12.0f, 12.0f), clampf(gains[1][i], -12.0f, 12.0f));
}

void GraphicEq::snap() {
  for (int i = 0; i < count_; ++i) bands_[i].snap();
}

void GraphicEq::reset() {
  for (int i = 0; i < count_; ++i) bands_[i].reset();
}

void GraphicEq::process(float* L, float* R, int n) {
  for (int i = 0; i < count_; ++i) bands_[i].process(L, R, n);
}

// ---------------------------------------------------------------------------------------------
void ToneStage::loudnessGains(int loudness, float& lowDb, float& highDb) {
  switch (loudness) {
    case 1: lowDb = 3.5f; highDb = 2.0f; break;   // LOW
    case 2: lowDb = 6.5f; highDb = 3.5f; break;   // MID
    case 3: lowDb = 9.5f; highDb = 5.0f; break;   // HIGH
    default: lowDb = 0.0f; highDb = 0.0f; break;
  }
}

void ToneStage::prepare(double fs) {
  lowShelf_.configure(FilterType::LowShelf, kLoudLowHz, 0.707f, fs);
  highShelf_.configure(FilterType::HighShelf, kLoudHighHz, 0.707f, fs);
  bass_.configure(FilterType::Peak, kBassHz, kBassQ, fs);
}

void ToneStage::setTargets(int loudness, int bassBoost) {
  float lo, hi;
  loudnessGains(loudness, lo, hi);
  lowShelf_.setTarget(lo, lo);
  highShelf_.setTarget(hi, hi);
  const float bb = bassBoostDb(bassBoost);
  bass_.setTarget(bb, bb);
}

void ToneStage::snap() {
  lowShelf_.snap();
  highShelf_.snap();
  bass_.snap();
}

void ToneStage::reset() {
  lowShelf_.reset();
  highShelf_.reset();
  bass_.reset();
}

void ToneStage::process(float* L, float* R, int n) {
  lowShelf_.process(L, R, n);
  highShelf_.process(L, R, n);
  bass_.process(L, R, n);
}

}  // namespace carro
