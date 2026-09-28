// Real-input FFT (power-of-two sizes) built on an iterative radix-2 complex FFT of half size.
// Spectra are stored split (re[], im[]) with n/2+1 bins, which keeps the complex
// multiply-accumulate loops of the convolver auto-vectorisable.
#pragma once

#include <vector>

namespace carro {

class RealFFT {
 public:
  RealFFT() = default;
  explicit RealFFT(int n) { init(n); }
  void init(int n);
  int size() const { return n_; }
  int bins() const { return n_ / 2 + 1; }
  // in[n] -> re/im[n/2+1] (unnormalised forward DFT)
  void forward(const float* in, float* re, float* im);
  // re/im[n/2+1] -> out[n] (exact inverse, includes 1/n)
  void inverse(const float* re, const float* im, float* out);

 private:
  void complexFFT(float* re, float* im) const;  // in-place forward, size h_
  int n_ = 0, h_ = 0, log2h_ = 0;
  std::vector<int> bitrev_;
  std::vector<float> twr_, twi_;    // complex FFT twiddles, size h_/2
  std::vector<float> postr_, posti_;  // real split twiddles e^{-2 pi i k / n}, size h_+1
  std::vector<float> wr_, wi_;      // scratch
};

inline bool isPowerOfTwo(int n) { return n > 0 && (n & (n - 1)) == 0; }
inline int nextPowerOfTwo(int n) {
  int p = 1;
  while (p < n) p <<= 1;
  return p;
}

}  // namespace carro
