#include "reverb_algo.h"

#include <algorithm>

namespace carro {

namespace {

bool isPrime(int n) {
  if (n < 2) return false;
  if (n % 2 == 0) return n == 2;
  for (int d = 3; d * d <= n; d += 2)
    if (n % d == 0) return false;
  return true;
}

int nearestPrime(int n) {
  for (int k = 0; k < 1000; ++k) {
    if (isPrime(n + k)) return n + k;
    if (n - k > 2 && isPrime(n - k)) return n - k;
  }
  return n;
}

int pow2Mask(int minSize) {
  int s = 1;
  while (s < minSize) s <<= 1;
  return s - 1;
}

// Line-length spread (relative to the mean free path) - roughly geometric, mutually prime
// after rounding to primes.
constexpr float kLineFactors[kFdnLines] = {0.61f, 0.72f, 0.83f, 0.95f, 1.07f, 1.21f, 1.37f, 1.55f};
constexpr float kApMsL[kDiffusers] = {4.771f, 3.595f, 12.73f, 9.307f};
constexpr float kApMsR[kDiffusers] = {4.531f, 3.813f, 11.91f, 9.929f};
constexpr float kOutSignL[kFdnLines] = {1, -1, 1, -1, 1, -1, 1, -1};
constexpr float kOutSignR[kFdnLines] = {1, 1, -1, -1, 1, 1, -1, -1};
constexpr float kInSign[4] = {1, -1, 1, -1};

constexpr double kMaxInputSec = 0.45;   // pre-delay + ER span
constexpr double kMaxLineSec = 0.26;    // longest FDN line
constexpr double kMaxErSec = 0.15;      // reflections later than this are left to the FDN
constexpr float kMaxDiffuserMs = 20.0f;

inline void hadamard8(float* v) {
  for (int len = 1; len < 8; len <<= 1) {
    for (int i = 0; i < 8; i += len << 1) {
      for (int j = i; j < i + len; ++j) {
        const float a = v[j], b = v[j + len];
        v[j] = a + b;
        v[j + len] = a - b;
      }
    }
  }
  const float s = 0.35355339059327373f;  // 1/sqrt(8)
  for (int i = 0; i < 8; ++i) v[i] *= s;
}

}  // namespace

void designReverb(const SfModeParams& p, int size, float widthMul, double fs, ReverbDesign& d) {
  d = ReverbDesign();
  float dimS, rtS, preS;
  sizeScale(size, dimS, rtS, preS);
  const double W = std::max(2.0f, p.roomW * dimS), Lr = std::max(2.0f, p.roomL * dimS),
               H = std::max(2.0f, p.roomH * dimS);
  const double c = kSpeedOfSoundCmPerSec / 100.0;  // m/s
  const double rt60 = std::max(0.1f, p.rt60 * rtS);

  d.active = true;
  d.preDelay = static_cast<int>(std::min(0.12, p.preDelayMs * preS * 0.001) * fs);

  // Mean free path 4V/S drives the FDN line lengths.
  const double V = W * Lr * H;
  const double S = 2.0 * (W * Lr + W * H + Lr * H);
  const double mfp = 4.0 * V / S;
  const double meanLineSec = std::min(kMaxLineSec / 1.6, std::max(0.006, mfp / c));
  d.lateOnset = static_cast<int>(std::min(0.04, std::max(0.002, 0.5 * mfp / c)) * fs);
  for (int i = 0; i < kFdnLines; ++i) {
    int len = static_cast<int>(meanLineSec * kLineFactors[i] * fs);
    len = std::min(nearestPrime(std::max(len, 37)), static_cast<int>(kMaxLineSec * fs) - 8);
    d.lineLen[i] = len;
    d.gMid[i] = static_cast<float>(std::pow(10.0, -3.0 * len / (rt60 * fs)));
    d.gLow[i] = static_cast<float>(std::pow(10.0, -3.0 * len / (rt60 * std::max(0.3f, p.lowMult) * fs)));
  }

  // Input diffusion scales mildly with room size; density sets the allpass gain.
  const float apScale = static_cast<float>(0.7 + 0.3 * std::min(1.5, dimS * std::cbrt(V) / 20.0));
  for (int k = 0; k < kDiffusers; ++k) {
    d.apLen[0][k] = std::max(1, static_cast<int>(std::min(kMaxDiffuserMs, kApMsL[k] * apScale) * 0.001f * fs));
    d.apLen[1][k] = std::max(1, static_cast<int>(std::min(kMaxDiffuserMs, kApMsR[k] * apScale) * 0.001f * fs));
  }
  d.apGain = 0.45f + 0.3f * clampf(p.density, 0.0f, 1.0f);

  // ---- image-source early reflections (orders 1 and 2 => 24 images per source) ----
  const double lx = 0.5 * W, ly = 0.62 * Lr, lz = std::min(1.2, H * 0.5);
  const double spread = std::min(W * 0.18, 4.0);
  const double sy = 0.12 * Lr, sz = std::min(1.6, H * 0.5);
  const double srcX[2] = {0.5 * W - spread, 0.5 * W + spread};
  const double beta = 0.62 + 0.25 * clampf(p.density, 0.0f, 1.0f);  // wall reflection coefficient
  int nt = 0;
  for (int src = 0; src < 2; ++src) {
    const double sx = srcX[src];
    const double d0 = std::sqrt((sx - lx) * (sx - lx) + (sy - ly) * (sy - ly) + (sz - lz) * (sz - lz));
    for (int nx = -2; nx <= 2; ++nx)
      for (int ny = -2; ny <= 2; ++ny)
        for (int nz = -2; nz <= 2; ++nz) {
          const int order = std::abs(nx) + std::abs(ny) + std::abs(nz);
          if (order < 1 || order > 2) continue;
          auto img = [](int n, double dim, double s) { return n * dim + ((n % 2 == 0) ? s : dim - s); };
          const double ix = img(nx, W, sx), iy = img(ny, Lr, sy), iz = img(nz, H, sz);
          const double vx = ix - lx, vy = iy - ly, vz = iz - lz;
          const double dist = std::sqrt(vx * vx + vy * vy + vz * vz);
          const double delaySec = (dist - d0) / c;
          if (delaySec <= 0.0005 || delaySec > kMaxErSec || nt >= kMaxErTaps) continue;
          const double gain = (d0 / dist) * std::pow(beta, order);
          const double lateral = clampf(static_cast<float>(vx / dist), -1.0f, 1.0f);
          ErTap& t = d.taps[nt++];
          t.delay = static_cast<int>(delaySec * fs);
          t.gL = static_cast<float>(gain * std::sqrt(0.5 * (1.0 - lateral)));
          t.gR = static_cast<float>(gain * std::sqrt(0.5 * (1.0 + lateral)));
          t.src = src;
        }
  }
  d.numTaps = nt;

  d.erGain = dbToGain(p.erLevelDb);
  d.lateGain = dbToGain(p.lateLevelDb);
  d.width = clampf(p.width * widthMul, 0.0f, 2.0f);
  d.dampHz = clampf(p.dampHz, 1000.0f, static_cast<float>(fs * 0.45));
  // Length-dependent HF damping: each line's one-pole low-pass is solved so that its gain at
  // dampHz equals the mid-band loop gain again, i.e. RT60(dampHz) = RT60(mid) / 2 for every
  // line regardless of its length (Jot absorptive filter).
  {
    const double cw = std::cos(2.0 * kPi * d.dampHz / fs);
    for (int i = 0; i < kFdnLines; ++i) {
      const double g = d.gMid[i];
      const double g2 = g * g;
      double a = 0.0;
      if (g2 < 1.0) {
        const double b = 1.0 - g2 * cw;
        const double q = 1.0 - g2;
        a = (b - std::sqrt(std::max(0.0, b * b - q * q))) / q;
      }
      d.dampA[i] = static_cast<float>(clampf(static_cast<float>(a), 0.0f, 0.95f));
    }
  }
  d.modDepth = clampf(p.modDepthMs, 0.0f, 2.0f) * 0.001f * static_cast<float>(fs);
  d.modRateHz = clampf(p.modRateHz, 0.05f, 3.0f);
  d.hpfHz = clampf(p.wetHpfHz, 20.0f, 1000.0f);
  d.lpfHz = clampf(p.wetLpfHz, 2000.0f, static_cast<float>(fs * 0.45));
}

void AlgoReverb::prepare(double fs) {
  fs_ = fs;
  inMask_ = pow2Mask(static_cast<int>(kMaxInputSec * fs) + 8);
  for (auto& b : in_) b.assign(inMask_ + 1, 0.0f);
  for (auto& l : lines_) {
    l.mask = pow2Mask(static_cast<int>((kMaxLineSec + 0.004) * fs) + 8);
    l.buf.assign(l.mask + 1, 0.0f);
  }
  for (auto& ch : ap_)
    for (auto& a : ch) {
      a.mask = pow2Mask(static_cast<int>(kMaxDiffuserMs * 0.001 * fs) + 4);
      a.buf.assign(a.mask + 1, 0.0f);
    }
  w_ = 0;
}

void AlgoReverb::apply(const ReverbDesign& d) {
  d_ = d;
  for (int i = 0; i < kFdnLines; ++i) {
    Line& l = lines_[i];
    l.low.setCutoff(d.lowXoverHz, fs_);
    l.damp.a = d.dampA[i];
    // Spread LFO rates +-35 % so lines never modulate in lockstep.
    const double rate = d.modRateHz * (0.65 + 0.7 * i / (kFdnLines - 1.0));
    l.oscK = static_cast<float>(2.0 * std::sin(kPi * rate / fs_));
    const double ph = 2.0 * kPi * i / kFdnLines;
    l.oscS = static_cast<float>(std::sin(ph));
    l.oscC = static_cast<float>(std::cos(ph));
  }
  for (int c = 0; c < 2; ++c)
    for (int k = 0; k < kDiffusers; ++k) ap_[c][k].len = std::min(d.apLen[c][k], ap_[c][k].mask);
  hpf_.c = designFilter(FilterType::HighPass, fs_, d.hpfHz, 0.7071, 0);
  lpf_.c = designFilter(FilterType::LowPass, fs_, d.lpfHz, 0.7071, 0);
  reset();
}

void AlgoReverb::reset() {
  for (auto& b : in_) std::fill(b.begin(), b.end(), 0.0f);
  for (auto& l : lines_) {
    std::fill(l.buf.begin(), l.buf.end(), 0.0f);
    l.low.reset();
    l.damp.reset();
  }
  for (auto& ch : ap_)
    for (auto& a : ch) std::fill(a.buf.begin(), a.buf.end(), 0.0f);
  hpf_.reset();
  lpf_.reset();
}

void AlgoReverb::process(const float* inL, const float* inR, float* outL, float* outR, int n) {
  if (!d_.active) {
    std::fill(outL, outL + n, 0.0f);
    std::fill(outR, outR + n, 0.0f);
    return;
  }
  const int pre = d_.preDelay;
  const int onset = pre + d_.lateOnset;
  const float g = d_.apGain;
  float y[kFdnLines], v[kFdnLines];
  unsigned w = static_cast<unsigned>(w_);
  for (int i = 0; i < n; ++i) {
    const float xl = inL[i], xr = inR[i];
    in_[0][w & inMask_] = xl;
    in_[1][w & inMask_] = xr;

    // ---- early reflections ----
    float erL = 0.0f, erR = 0.0f;
    for (int t = 0; t < d_.numTaps; ++t) {
      const ErTap& tap = d_.taps[t];
      const float s = in_[tap.src][(w - static_cast<unsigned>(pre + tap.delay)) & inMask_];
      erL += s * tap.gL;
      erR += s * tap.gR;
    }

    // ---- late input + diffusion ----
    float dl = in_[0][(w - static_cast<unsigned>(onset)) & inMask_];
    float dr = in_[1][(w - static_cast<unsigned>(onset)) & inMask_];
    for (int k = 0; k < kDiffusers; ++k) {
      Diffuser& a = ap_[0][k];
      const float dd = a.buf[(w - static_cast<unsigned>(a.len)) & a.mask];
      const float vv = dl + g * dd;
      a.buf[w & a.mask] = vv;
      dl = dd - g * vv;
      Diffuser& b = ap_[1][k];
      const float de = b.buf[(w - static_cast<unsigned>(b.len)) & b.mask];
      const float vr = dr + g * de;
      b.buf[w & b.mask] = vr;
      dr = de - g * vr;
    }

    // ---- FDN ----
    for (int k = 0; k < kFdnLines; ++k) {
      Line& l = lines_[k];
      // magic-circle quadrature LFO
      l.oscS += l.oscK * l.oscC;
      l.oscC -= l.oscK * l.oscS;
      const float delay = static_cast<float>(d_.lineLen[k]) - d_.modDepth * 0.5f * (1.0f + l.oscS);
      const int di = static_cast<int>(delay);
      const float fr = delay - static_cast<float>(di);
      const float a0 = l.buf[(w - static_cast<unsigned>(di)) & l.mask];
      const float a1 = l.buf[(w - static_cast<unsigned>(di + 1)) & l.mask];
      const float out = a0 + fr * (a1 - a0);
      y[k] = out;
      const float lo = l.low.process(out);
      const float t = d_.gLow[k] * lo + d_.gMid[k] * (out - lo);
      v[k] = l.damp.process(t);
    }
    hadamard8(v);
    for (int k = 0; k < 4; ++k) {
      v[k] += dl * kInSign[k];
      v[k + 4] += dr * kInSign[k];
    }
    for (int k = 0; k < kFdnLines; ++k) lines_[k].buf[w & lines_[k].mask] = v[k] + kAntiDenormal;

    float lateL = 0.0f, lateR = 0.0f;
    for (int k = 0; k < kFdnLines; ++k) {
      lateL += kOutSignL[k] * y[k];
      lateR += kOutSignR[k] * y[k];
    }
    lateL *= 0.35f;
    lateR *= 0.35f;

    float wl = d_.erGain * erL + d_.lateGain * lateL;
    float wr = d_.erGain * erR + d_.lateGain * lateR;
    const float m = 0.5f * (wl + wr), s = 0.5f * (wl - wr) * d_.width;
    outL[i] = m + s;
    outR[i] = m - s;
    ++w;
  }
  w_ = static_cast<int>(w & 0x3fffffff);  // keep positive; all masks are < 2^30
  hpf_.processBlock(outL, outR, n);
  lpf_.processBlock(outL, outR, n);
}

void AlgoReverb::renderImpulse(const ReverbDesign& d, double fs, int frames, std::vector<float>& outL,
                               std::vector<float>& outR) {
  AlgoReverb r;
  r.prepare(fs);
  r.apply(d);
  outL.assign(frames, 0.0f);
  outR.assign(frames, 0.0f);
  std::vector<float> inL(frames, 0.0f), inR(frames, 0.0f);
  if (frames > 0) inL[0] = inR[0] = 1.0f;
  const int block = 1024;
  for (int off = 0; off < frames; off += block) {
    const int m = std::min(block, frames - off);
    r.process(inL.data() + off, inR.data() + off, outL.data() + off, outR.data() + off, m);
  }
}

}  // namespace carro
