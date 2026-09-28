// Analysis helpers: lock-free output tap for the spectrum analyzer, log-band spectrum,
// Schroeder energy-decay curve and RT60 measurement, IR capture (ESS sweep + deconvolution).
#pragma once

#include <atomic>
#include <string>
#include <vector>

#include "fft.h"

namespace carro {

// Single-producer ring of the (mono) output. The reader copies the newest window; a torn
// read only affects one analyzer frame, which is harmless for display.
class SpectrumTap {
 public:
  static constexpr int kSize = 8192;
  void push(const float* L, const float* R, int n) {
    uint32_t w = write_.load(std::memory_order_relaxed);
    for (int i = 0; i < n; ++i) ring_[(w + i) & (kSize - 1)] = 0.5f * (L[i] + R[i]);
    write_.store(w + static_cast<uint32_t>(n), std::memory_order_release);
  }
  void snapshot(float* out, int n) const {
    const uint32_t w = write_.load(std::memory_order_acquire);
    for (int i = 0; i < n; ++i) out[i] = ring_[(w - n + i) & (kSize - 1)];
  }

 private:
  float ring_[kSize] = {};
  std::atomic<uint32_t> write_{0};
};

// Log-spaced band magnitudes (dBFS, sine-calibrated) from `n` (power of two) samples.
void spectrumBands(const float* samples, int n, double fs, float* outDb, int bands, RealFFT& fft);

// Schroeder backward-integrated energy decay (dB, 0 at start) resampled to `points`.
void energyDecayCurve(const std::vector<float>& a, const std::vector<float>& b, float* outDb, int points);
// RT60 from T20 (-5..-25 dB), falling back to T10 when the dynamic range is too small.
float measureRt60(const float* ir, int n, double fs);
float measureRt60Stereo(const std::vector<float>& a, const std::vector<float>& b, double fs);
// ISO 3382 style "mid" RT60: mean of the 500 Hz and 1 kHz octave-band decays.
float measureRt60Mid(const std::vector<float>& a, const std::vector<float>& b, double fs);

void generateSweep(float* out, int frames, double fs, double f1, double f2, float amplitude);
int buildIrFromCaptures(const std::string& recLeft, const std::string& recRight, const std::string& outWav,
                        double sweepRate, double f1, double f2, double sweepSeconds, double maxIrSeconds);

}  // namespace carro
