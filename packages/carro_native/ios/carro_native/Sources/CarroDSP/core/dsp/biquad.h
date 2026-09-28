// RBJ "Audio EQ Cookbook" biquads, first-order sections, Butterworth / Linkwitz-Riley
// cascade design and analytic magnitude response. Coefficients are designed in double and
// run in float (Transposed Direct Form II).
#pragma once

#include <complex>

#include "common.h"

namespace carro {

struct BiquadCoeffs {
  float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;
  bool isIdentity() const { return b0 == 1.0f && b1 == 0.0f && b2 == 0.0f && a1 == 0.0f && a2 == 0.0f; }
};

enum class FilterType { Peak, LowShelf, HighShelf, LowPass, HighPass, LowPass1, HighPass1, BandPass };

inline BiquadCoeffs designFilter(FilterType type, double fs, double f0, double q, double gainDb) {
  BiquadCoeffs c;
  f0 = std::min(std::max(f0, 1.0), fs * 0.49);
  q = std::max(q, 0.05);
  const double w0 = 2.0 * kPi * f0 / fs;
  const double cw = std::cos(w0), sw = std::sin(w0);
  const double A = std::pow(10.0, gainDb / 40.0);
  const double alpha = sw / (2.0 * q);
  double b0 = 1, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;
  switch (type) {
    case FilterType::Peak:
      b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A;
      a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A;
      break;
    case FilterType::LowShelf: {
      const double sa = 2 * std::sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cw + sa);
      b1 = 2 * A * ((A - 1) - (A + 1) * cw);
      b2 = A * ((A + 1) - (A - 1) * cw - sa);
      a0 = (A + 1) + (A - 1) * cw + sa;
      a1 = -2 * ((A - 1) + (A + 1) * cw);
      a2 = (A + 1) + (A - 1) * cw - sa;
      break;
    }
    case FilterType::HighShelf: {
      const double sa = 2 * std::sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cw + sa);
      b1 = -2 * A * ((A - 1) + (A + 1) * cw);
      b2 = A * ((A + 1) + (A - 1) * cw - sa);
      a0 = (A + 1) - (A - 1) * cw + sa;
      a1 = 2 * ((A - 1) - (A + 1) * cw);
      a2 = (A + 1) - (A - 1) * cw - sa;
      break;
    }
    case FilterType::LowPass:
      b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2;
      a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
    case FilterType::HighPass:
      b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2;
      a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
    case FilterType::BandPass:  // constant 0 dB peak gain
      b0 = alpha; b1 = 0; b2 = -alpha;
      a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
    case FilterType::LowPass1: {  // bilinear first order
      const double k = std::tan(w0 / 2);
      b0 = k; b1 = k; b2 = 0;
      a0 = 1 + k; a1 = k - 1; a2 = 0;
      break;
    }
    case FilterType::HighPass1: {
      const double k = std::tan(w0 / 2);
      b0 = 1; b1 = -1; b2 = 0;
      a0 = 1 + k; a1 = k - 1; a2 = 0;
      break;
    }
  }
  c.b0 = static_cast<float>(b0 / a0);
  c.b1 = static_cast<float>(b1 / a0);
  c.b2 = static_cast<float>(b2 / a0);
  c.a1 = static_cast<float>(a1 / a0);
  c.a2 = static_cast<float>(a2 / a0);
  return c;
}

// |H(e^jw)| in dB.
inline double magnitudeDb(const BiquadCoeffs& c, double freq, double fs) {
  const double w = 2.0 * kPi * freq / fs;
  const std::complex<double> z1 = std::polar(1.0, -w), z2 = std::polar(1.0, -2.0 * w);
  const std::complex<double> num = double(c.b0) + double(c.b1) * z1 + double(c.b2) * z2;
  const std::complex<double> den = 1.0 + double(c.a1) * z1 + double(c.a2) * z2;
  return 20.0 * std::log10(std::max(std::abs(num / den), 1e-12));
}

// Mono TDF-II biquad state.
struct Biquad {
  BiquadCoeffs c;
  float z1 = 0.0f, z2 = 0.0f;
  inline float process(float x) {
    const float y = c.b0 * x + z1;
    z1 = c.b1 * x - c.a1 * y + z2;
    z2 = c.b2 * x - c.a2 * y;
    return y;
  }
  void reset() { z1 = z2 = 0.0f; }
  void processBlock(float* x, int n) {
    const float b0 = c.b0, b1 = c.b1, b2 = c.b2, a1 = c.a1, a2 = c.a2;
    float s1 = z1, s2 = z2;
    for (int i = 0; i < n; ++i) {
      const float in = x[i];
      const float y = b0 * in + s1;
      s1 = b1 * in - a1 * y + s2;
      s2 = b2 * in - a2 * y;
      x[i] = y;
    }
    z1 = s1;
    z2 = s2;
  }
};

// Stereo biquad sharing one coefficient set; L and R are processed in the same loop so the
// compiler can keep both states in registers.
struct StereoBiquad {
  BiquadCoeffs c;
  float l1 = 0, l2 = 0, r1 = 0, r2 = 0;
  void reset() { l1 = l2 = r1 = r2 = 0; }
  void processBlock(float* L, float* R, int n) {
    const float b0 = c.b0, b1 = c.b1, b2 = c.b2, a1 = c.a1, a2 = c.a2;
    float sl1 = l1, sl2 = l2, sr1 = r1, sr2 = r2;
    for (int i = 0; i < n; ++i) {
      const float xl = L[i], xr = R[i];
      const float yl = b0 * xl + sl1;
      const float yr = b0 * xr + sr1;
      sl1 = b1 * xl - a1 * yl + sl2;
      sr1 = b1 * xr - a1 * yr + sr2;
      sl2 = b2 * xl - a2 * yl;
      sr2 = b2 * xr - a2 * yr;
      L[i] = yl;
      R[i] = yr;
    }
    l1 = sl1; l2 = sl2; r1 = sr1; r2 = sr2;
  }
};

// Crossover filter cascade (max 4 sections = up to -48 dB/oct; we use up to -36 dB/oct).
struct FilterCascade {
  static constexpr int kMaxSections = 4;
  BiquadCoeffs sec[kMaxSections];
  int count = 0;
};

// Butterworth order N = slope/6. Linkwitz-Riley (even orders only) = BW(N/2) squared.
inline FilterCascade designCrossover(bool highpass, int slopeDbPerOct, bool linkwitzRiley, double fc,
                                     double fs) {
  FilterCascade out;
  const int order = clampi(slopeDbPerOct / 6, 1, 6);
  auto addBw = [&](int n) {
    // Butterworth pole-pair Qs: Q_k = 1 / (2 sin((2k-1) pi / 2n)), k = 1..n/2
    // (n odd adds one real pole = first-order section).
    for (int k = 1; k <= n / 2; ++k) {
      const double theta = (2.0 * k - 1.0) * kPi / (2.0 * n);
      const double q = 1.0 / (2.0 * std::sin(theta));
      if (out.count < FilterCascade::kMaxSections)
        out.sec[out.count++] = designFilter(highpass ? FilterType::HighPass : FilterType::LowPass, fs, fc, q, 0);
    }
    if (n % 2 == 1 && out.count < FilterCascade::kMaxSections)
      out.sec[out.count++] = designFilter(highpass ? FilterType::HighPass1 : FilterType::LowPass1, fs, fc, 0.707, 0);
  };
  if (linkwitzRiley && order % 2 == 0) {
    addBw(order / 2);
    addBw(order / 2);
  } else {
    addBw(order);
  }
  return out;
}

inline double cascadeMagnitudeDb(const FilterCascade& f, double freq, double fs) {
  double db = 0;
  for (int i = 0; i < f.count; ++i) db += magnitudeDb(f.sec[i], freq, fs);
  return db;
}

// First-order one-pole lowpass used inside reverbs and envelope followers.
struct OnePole {
  float a = 0.0f;  // feedback coefficient
  float z = 0.0f;
  void setCutoff(double hz, double fs) { a = static_cast<float>(std::exp(-2.0 * kPi * hz / fs)); }
  inline float process(float x) {
    z = x + a * (z - x);
    return z;
  }
  void reset() { z = 0.0f; }
};

}  // namespace carro
