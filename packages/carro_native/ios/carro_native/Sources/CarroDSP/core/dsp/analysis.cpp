#include "analysis.h"

#include <algorithm>
#include <cmath>

#include "../carro_api.h"
#include "biquad.h"
#include "common.h"
#include "wav.h"

namespace carro {

void spectrumBands(const float* samples, int n, double fs, float* outDb, int bands, RealFFT& fft) {
  if (fft.size() != n) fft.init(n);
  std::vector<float> buf(n), re(n / 2 + 1), im(n / 2 + 1);
  double wsum = 0.0;
  for (int i = 0; i < n; ++i) {
    const double w = 0.5 - 0.5 * std::cos(2.0 * kPi * i / (n - 1));
    buf[i] = static_cast<float>(samples[i] * w);
    wsum += w;
  }
  fft.forward(buf.data(), re.data(), im.data());
  const double fLo = 20.0, fHi = std::min(20000.0, fs * 0.5);
  const double binHz = fs / n;
  // amplitude of a full-scale sine = 1 -> 0 dBFS
  const double scale = 2.0 / wsum;
  for (int b = 0; b < bands; ++b) {
    const double f0 = fLo * std::pow(fHi / fLo, static_cast<double>(b) / bands);
    const double f1 = fLo * std::pow(fHi / fLo, static_cast<double>(b + 1) / bands);
    int k0 = static_cast<int>(std::floor(f0 / binHz));
    int k1 = static_cast<int>(std::ceil(f1 / binHz));
    k0 = std::max(1, std::min(k0, n / 2));
    k1 = std::max(k0 + 1, std::min(k1, n / 2 + 1));
    double peak = 0.0;
    for (int k = k0; k < k1; ++k) peak = std::max(peak, std::sqrt(double(re[k]) * re[k] + double(im[k]) * im[k]));
    outDb[b] = static_cast<float>(20.0 * std::log10(std::max(peak * scale, 1e-9)));
  }
}

namespace {
std::vector<double> schroeder(const std::vector<float>& a, const std::vector<float>& b) {
  const size_t n = std::max(a.size(), b.size());
  std::vector<double> e(n, 0.0);
  double acc = 0.0;
  for (size_t i = n; i-- > 0;) {
    const double x = i < a.size() ? a[i] : 0.0;
    const double y = i < b.size() ? b[i] : 0.0;
    acc += x * x + y * y;
    e[i] = acc;
  }
  return e;
}

float rt60FromEdc(const std::vector<double>& e, double fs) {
  if (e.empty() || e[0] <= 0.0) return 0.0f;
  const double e0 = e[0];
  auto dbAt = [&](size_t i) { return 10.0 * std::log10(std::max(e[i] / e0, 1e-30)); };
  // Choose evaluation range.
  double hi = -5.0, lo = -25.0;
  if (dbAt(e.size() - 1) > -27.0) lo = -15.0;
  if (dbAt(e.size() - 1) > -17.0) return 0.0f;
  // Least-squares line over the samples within [lo, hi].
  double sx = 0, sy = 0, sxx = 0, sxy = 0;
  size_t cnt = 0;
  const size_t step = std::max<size_t>(1, e.size() / 20000);
  for (size_t i = 0; i < e.size(); i += step) {
    const double d = dbAt(i);
    if (d > hi) continue;
    if (d < lo) break;
    const double t = i / fs;
    sx += t; sy += d; sxx += t * t; sxy += t * d;
    ++cnt;
  }
  if (cnt < 4) return 0.0f;
  const double slope = (cnt * sxy - sx * sy) / (cnt * sxx - sx * sx);  // dB per second
  if (slope >= 0.0) return 0.0f;
  return static_cast<float>(-60.0 / slope);
}
}  // namespace

void energyDecayCurve(const std::vector<float>& a, const std::vector<float>& b, float* outDb, int points) {
  const std::vector<double> e = schroeder(a, b);
  if (e.empty() || e[0] <= 0.0 || points <= 0) {
    for (int i = 0; i < points; ++i) outDb[i] = -100.0f;
    return;
  }
  for (int p = 0; p < points; ++p) {
    const size_t idx = std::min(e.size() - 1, static_cast<size_t>(static_cast<double>(p) / points * e.size()));
    outDb[p] = static_cast<float>(std::max(-100.0, 10.0 * std::log10(std::max(e[idx] / e[0], 1e-30))));
  }
}

float measureRt60(const float* ir, int n, double fs) {
  std::vector<float> a(ir, ir + n), b;
  return rt60FromEdc(schroeder(a, b), fs);
}

float measureRt60Stereo(const std::vector<float>& a, const std::vector<float>& b, double fs) {
  return rt60FromEdc(schroeder(a, b), fs);
}

float measureRt60Mid(const std::vector<float>& a, const std::vector<float>& b, double fs) {
  float sum = 0.0f;
  int cnt = 0;
  for (double fc : {500.0, 1000.0}) {
    // Two cascaded constant-peak band-passes (~1 octave).
    const BiquadCoeffs c = designFilter(FilterType::BandPass, fs, fc, 1.414, 0);
    auto band = [&](const std::vector<float>& x) {
      std::vector<float> y(x);
      Biquad f1, f2;
      f1.c = c;
      f2.c = c;
      f1.processBlock(y.data(), static_cast<int>(y.size()));
      f2.processBlock(y.data(), static_cast<int>(y.size()));
      return y;
    };
    const float rt = rt60FromEdc(schroeder(band(a), band(b)), fs);
    if (rt > 0.0f) {
      sum += rt;
      ++cnt;
    }
  }
  return cnt ? sum / cnt : measureRt60Stereo(a, b, fs);
}

// ---------------------------------------------------------------------------------------------
void generateSweep(float* out, int frames, double fs, double f1, double f2, float amplitude) {
  if (frames <= 0) return;
  const double T = frames / fs;
  const double L = T / std::log(f2 / f1);
  const int fadeIn = std::min(frames / 4, static_cast<int>(0.05 * fs));
  const int fadeOut = std::min(frames / 4, static_cast<int>(0.02 * fs));
  for (int i = 0; i < frames; ++i) {
    const double t = i / fs;
    double v = std::sin(2.0 * kPi * f1 * L * (std::exp(t / L) - 1.0));
    if (i < fadeIn) v *= 0.5 - 0.5 * std::cos(kPi * i / fadeIn);
    if (i >= frames - fadeOut) v *= 0.5 - 0.5 * std::cos(kPi * (frames - 1 - i) / fadeOut);
    out[i] = static_cast<float>(v * amplitude);
  }
}

namespace {

// Regularised spectral division: h = IFFT( Y X* / (|X|^2 + eps(f)) ).
std::vector<float> deconvolve(const std::vector<float>& rec, const std::vector<float>& sweep, double fs, double f1,
                              double f2) {
  const int N = nextPowerOfTwo(static_cast<int>(rec.size() + sweep.size()));
  RealFFT fft(N);
  const int bins = N / 2 + 1;
  std::vector<float> buf(N, 0.0f), yr(bins), yi(bins), xr(bins), xi(bins);
  std::copy(rec.begin(), rec.end(), buf.begin());
  fft.forward(buf.data(), yr.data(), yi.data());
  std::fill(buf.begin(), buf.end(), 0.0f);
  std::copy(sweep.begin(), sweep.end(), buf.begin());
  fft.forward(buf.data(), xr.data(), xi.data());
  const double binHz = fs / N;
  const double bandLo = f1 * 1.05, bandHi = std::min(f2 * 0.95, fs * 0.47);
  double mean = 0.0;
  int cnt = 0;
  for (int k = 0; k < bins; ++k) {
    const double f = k * binHz;
    if (f >= bandLo && f <= bandHi) {
      mean += double(xr[k]) * xr[k] + double(xi[k]) * xi[k];
      ++cnt;
    }
  }
  mean = cnt ? mean / cnt : 1.0;
  const double epsIn = 1e-4 * mean, epsOut = 10.0 * mean;
  for (int k = 0; k < bins; ++k) {
    const double f = std::max(k * binHz, 1e-3);
    double oct = 0.0;
    if (f < bandLo) oct = std::log2(bandLo / f);
    else if (f > bandHi) oct = std::log2(f / bandHi);
    const double w = std::min(1.0, oct / 0.5);
    const double eps = std::exp(std::log(epsIn) * (1.0 - w) + std::log(epsOut) * w);
    const double den = double(xr[k]) * xr[k] + double(xi[k]) * xi[k] + eps;
    // Y * conj(X)
    const double re = double(yr[k]) * xr[k] + double(yi[k]) * xi[k];
    const double im = double(yi[k]) * xr[k] - double(yr[k]) * xi[k];
    yr[k] = static_cast<float>(re / den);
    yi[k] = static_cast<float>(im / den);
  }
  fft.inverse(yr.data(), yi.data(), buf.data());
  return buf;
}

}  // namespace

int buildIrFromCaptures(const std::string& recLeft, const std::string& recRight, const std::string& outWav,
                        double sweepRate, double f1, double f2, double sweepSeconds, double maxIrSeconds) {
  if (sweepRate <= 0 || f1 <= 0 || f2 <= f1 || sweepSeconds <= 0.5) return CARRO_ERR_ARGS;
  WavData wl, wr;
  int err = readWav(recLeft, wl);
  if (err != CARRO_OK) return err;
  const bool haveRight = !recRight.empty();
  if (haveRight) {
    err = readWav(recRight, wr);
    if (err != CARRO_OK) return err;
    if (wr.channels != wl.channels) return CARRO_ERR_FORMAT;
  }
  const double fs = sweepRate;
  const int sweepFrames = static_cast<int>(sweepSeconds * fs);
  std::vector<float> sweep(sweepFrames);
  generateSweep(sweep.data(), sweepFrames, fs, f1, f2, 1.0f);

  // Deconvolve every recorded channel of every capture.
  std::vector<std::vector<float>> irs;  // capture-major, then recorded channel
  auto addCapture = [&](const WavData& w) {
    for (int c = 0; c < std::min(w.channels, 2); ++c) {
      std::vector<float> ch = w.channel(c);
      if (std::fabs(w.sampleRate - fs) > 0.5) ch = resample(ch, w.sampleRate, fs);
      irs.push_back(deconvolve(ch, sweep, fs, f1, f2));
    }
  };
  addCapture(wl);
  if (haveRight) addCapture(wr);
  if (irs.empty()) return CARRO_ERR_FORMAT;
  const int recCh = std::min(wl.channels, 2);

  // Channel layout of the result.
  //   L+R captures, stereo rec : LL = capL.ch0, LR = capL.ch1, RL = capR.ch0, RR = capR.ch1
  //   L+R captures, mono rec   : L = capL.ch0, R = capR.ch0
  //   single capture           : its recorded channels
  std::vector<std::vector<float>*> order;
  for (auto& v : irs) order.push_back(&v);
  (void)recCh;

  // Global latency alignment (keeps inter-channel timing).
  size_t peakMin = SIZE_MAX;
  double globalPeak = 0.0;
  for (auto* v : order) {
    const size_t half = v->size() / 2;  // negative-time (harmonic) products live in the upper half
    size_t best = 0;
    float bv = 0.0f;
    for (size_t i = 0; i < half; ++i)
      if (std::fabs((*v)[i]) > bv) { bv = std::fabs((*v)[i]); best = i; }
    peakMin = std::min(peakMin, best);
    globalPeak = std::max(globalPeak, static_cast<double>(bv));
  }
  if (globalPeak <= 1e-9) return CARRO_ERR_SIGNAL;
  const size_t preroll = static_cast<size_t>(0.001 * fs);
  const size_t offset = peakMin > preroll ? peakMin - preroll : 0;
  const size_t maxLen = static_cast<size_t>(std::min(6.0, std::max(0.2, maxIrSeconds)) * fs);

  // Noise-floor based truncation on the summed energy.
  const size_t win = static_cast<size_t>(0.01 * fs);
  const size_t avail = order[0]->size() / 2 > offset ? order[0]->size() / 2 - offset : 0;
  const size_t span = std::min(avail, maxLen + static_cast<size_t>(1.0 * fs));
  std::vector<double> env;
  for (size_t s = 0; s + win <= span; s += win) {
    double e = 0.0;
    for (auto* v : order)
      for (size_t i = s; i < s + win; ++i) e += double((*v)[offset + i]) * (*v)[offset + i];
    env.push_back(10.0 * std::log10(e / (win * order.size()) + 1e-30));
  }
  size_t length = std::min(maxLen, span);
  if (env.size() > 20) {
    const size_t floorStart = std::min(env.size() - 5, std::max<size_t>(env.size() * 8 / 10, maxLen / win));
    std::vector<double> tailEnv(env.begin() + std::min(floorStart, env.size() - 1), env.end());
    std::sort(tailEnv.begin(), tailEnv.end());
    const double noise = tailEnv[tailEnv.size() / 2];
    size_t lastAbove = 0;
    for (size_t k = 0; k < env.size(); ++k)
      if (env[k] > noise + 6.0) lastAbove = k;
    length = std::min(length, (lastAbove + 1) * win + static_cast<size_t>(0.05 * fs));
    length = std::max(length, static_cast<size_t>(0.2 * fs));
  }
  length = std::min(length, avail);
  if (length < 64) return CARRO_ERR_SIGNAL;

  // Assemble, fade, normalise.
  const int outCh = static_cast<int>(order.size());
  std::vector<float> inter(length * outCh);
  const size_t fadeIn = std::max<size_t>(1, preroll);
  const size_t fadeOut = std::min(length / 10, static_cast<size_t>(0.05 * fs));
  float peak = 0.0f;
  for (int c = 0; c < outCh; ++c) {
    const std::vector<float>& v = *order[c];
    for (size_t i = 0; i < length; ++i) {
      double g = 1.0;
      if (i < fadeIn) g *= 0.5 - 0.5 * std::cos(kPi * i / fadeIn);
      if (fadeOut > 0 && i >= length - fadeOut) g *= 0.5 + 0.5 * std::cos(kPi * (i - (length - fadeOut)) / fadeOut);
      const float s = static_cast<float>(v[offset + i] * g);
      inter[i * outCh + c] = s;
      peak = std::max(peak, std::fabs(s));
    }
  }
  if (peak > 0.0f)
    for (float& s : inter) s *= 0.5f / peak;
  err = writeWavFloat(outWav, inter.data(), static_cast<int>(length), outCh, static_cast<int>(std::lround(fs)));
  if (err != CARRO_OK) return err;
  return static_cast<int>(length);
}

}  // namespace carro
