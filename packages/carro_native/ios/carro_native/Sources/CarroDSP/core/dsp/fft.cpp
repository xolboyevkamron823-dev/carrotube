#include "fft.h"

#include <cmath>

#include "common.h"

namespace carro {

void RealFFT::init(int n) {
  n_ = std::max(4, nextPowerOfTwo(n));
  h_ = n_ / 2;
  log2h_ = 0;
  while ((1 << log2h_) < h_) ++log2h_;
  bitrev_.assign(h_, 0);
  for (int i = 0; i < h_; ++i) {
    int r = 0;
    for (int b = 0; b < log2h_; ++b)
      if (i & (1 << b)) r |= 1 << (log2h_ - 1 - b);
    bitrev_[i] = r;
  }
  twr_.resize(std::max(1, h_ / 2));
  twi_.resize(std::max(1, h_ / 2));
  for (int k = 0; k < h_ / 2; ++k) {
    const double a = -2.0 * kPi * k / h_;
    twr_[k] = static_cast<float>(std::cos(a));
    twi_[k] = static_cast<float>(std::sin(a));
  }
  postr_.resize(h_ + 1);
  posti_.resize(h_ + 1);
  for (int k = 0; k <= h_; ++k) {
    const double a = -2.0 * kPi * k / n_;
    postr_[k] = static_cast<float>(std::cos(a));
    posti_[k] = static_cast<float>(std::sin(a));
  }
  wr_.resize(h_);
  wi_.resize(h_);
}

void RealFFT::complexFFT(float* re, float* im) const {
  for (int i = 0; i < h_; ++i) {
    const int j = bitrev_[i];
    if (j > i) {
      std::swap(re[i], re[j]);
      std::swap(im[i], im[j]);
    }
  }
  for (int len = 2; len <= h_; len <<= 1) {
    const int half = len >> 1;
    const int step = h_ / len;
    for (int start = 0; start < h_; start += len) {
      for (int k = 0; k < half; ++k) {
        const float wr = twr_[k * step], wi = twi_[k * step];
        const int a = start + k, b = a + half;
        const float xr = re[b] * wr - im[b] * wi;
        const float xi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
      }
    }
  }
}

void RealFFT::forward(const float* in, float* re, float* im) {
  float* zr = wr_.data();
  float* zi = wi_.data();
  for (int k = 0; k < h_; ++k) {
    zr[k] = in[2 * k];
    zi[k] = in[2 * k + 1];
  }
  complexFFT(zr, zi);
  // X[k] = Ze + W^k * Zo, Ze = (Z[k] + conj(Z[h-k]))/2, Zo = -i (Z[k] - conj(Z[h-k]))/2
  for (int k = 0; k <= h_; ++k) {
    const int a = (k == h_) ? 0 : k;
    const int b = (k == 0) ? 0 : h_ - k;
    const float ar = zr[a], ai = zi[a];
    const float br = zr[b], bi = -zi[b];  // conj(Z[h-k])
    const float er = 0.5f * (ar + br), ei = 0.5f * (ai + bi);
    const float dr = 0.5f * (ar - br), di = 0.5f * (ai - bi);
    // Zo = -i * d = (di, -dr)
    const float or_ = di, oi = -dr;
    const float wr = postr_[k], wi = posti_[k];
    re[k] = er + (or_ * wr - oi * wi);
    im[k] = ei + (or_ * wi + oi * wr);
  }
}

void RealFFT::inverse(const float* re, const float* im, float* out) {
  float* zr = wr_.data();
  float* zi = wi_.data();
  // Z[k] = Ze + i Zo; Ze = (X[k] + conj(X[h-k]))/2, Zo = (X[k] - conj(X[h-k]))/2 * W^-k
  for (int k = 0; k < h_; ++k) {
    const float ar = re[k], ai = im[k];
    const float br = re[h_ - k], bi = -im[h_ - k];
    const float er = 0.5f * (ar + br), ei = 0.5f * (ai + bi);
    const float dr = 0.5f * (ar - br), di = 0.5f * (ai - bi);
    const float wr = postr_[k], wi = -posti_[k];  // W^-k
    const float or_ = dr * wr - di * wi, oi = dr * wi + di * wr;
    // + i*Zo = (-oi, or_); store conjugated for the inverse-via-forward trick
    zr[k] = er - oi;
    zi[k] = -(ei + or_);
  }
  complexFFT(zr, zi);
  const float scale = 1.0f / static_cast<float>(h_);
  for (int k = 0; k < h_; ++k) {
    out[2 * k] = zr[k] * scale;
    out[2 * k + 1] = -zi[k] * scale;
  }
}

}  // namespace carro
