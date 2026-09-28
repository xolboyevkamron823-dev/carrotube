// Carro DSP unit tests. Self-contained (no framework):
//   g++ -std=c++17 -O2 -pthread -I../src ../src/carro_api.cpp ../src/dsp/*.cpp dsp_tests.cpp -o dsp_tests
// or via tests/CMakeLists.txt. Exit code 0 = all passed.
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "carro_api.h"
#include "dsp/analysis.h"
#include "dsp/biquad.h"
#include "dsp/convolver.h"
#include "dsp/engine.h"
#include "dsp/eq.h"
#include "dsp/fft.h"
#include "dsp/limiter.h"
#include "dsp/reverb_algo.h"
#include "dsp/wav.h"

using namespace carro;

static int g_failed = 0, g_passed = 0;

#define CHECK(cond, ...)                                  \
  do {                                                    \
    if (!(cond)) {                                        \
      std::printf("    FAIL %s:%d: ", __FILE__, __LINE__); \
      std::printf(__VA_ARGS__);                           \
      std::printf("\n");                                  \
      ++g_failed;                                         \
    } else {                                              \
      ++g_passed;                                         \
    }                                                     \
  } while (0)

static void run(const char* name, const std::function<void()>& fn) {
  std::printf("[ RUN  ] %s\n", name);
  const int before = g_failed;
  const auto t0 = std::chrono::steady_clock::now();
  fn();
  const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  std::printf("[ %s ] %s (%.0f ms)\n", g_failed == before ? " OK " : "FAIL", name, ms);
}

static constexpr double kFs = 48000.0;

// Magnitude (dB) of a real signal's DFT at frequency f (Goertzel-free direct evaluation).
static double responseDbAt(const std::vector<float>& h, double f, double fs) {
  double re = 0, im = 0;
  for (size_t n = 0; n < h.size(); ++n) {
    const double a = -2.0 * kPi * f * n / fs;
    re += h[n] * std::cos(a);
    im += h[n] * std::sin(a);
  }
  return 20.0 * std::log10(std::max(std::sqrt(re * re + im * im), 1e-12));
}

static void resetEngineDefaults() {
  carro_begin_batch();
  EngineParams d;  // factory defaults
  carro_set_param(CARRO_P_BYPASS, 0, 0);
  carro_set_param(CARRO_P_SLA_DB, 0, 0);
  carro_set_param(CARRO_P_PREAMP_DB, 0, 0);
  carro_set_param(CARRO_P_AUTO_HEADROOM, 0, 0);
  carro_set_param(CARRO_P_ASR_MODE, 0, 0);
  carro_set_param(CARRO_P_EQ_MODE, 0, 0);
  for (int c = 0; c < 2; ++c)
    for (int b = 0; b < 31; ++b) carro_set_param(CARRO_P_EQ_BAND, c * 32 + b, 0);
  carro_set_param(CARRO_P_LOUDNESS, 0, 0);
  carro_set_param(CARRO_P_BASS_BOOST, 0, 0);
  carro_set_param(CARRO_P_SF_MODE, 0, 0);
  carro_set_param(CARRO_P_SF_ENGINE, 0, 0);
  carro_set_param(CARRO_P_XO_NETWORK, 0, 0);
  carro_set_param(CARRO_P_SUB_ON, 0, 0);
  for (int g = 0; g < 5; ++g) {
    carro_set_param(CARRO_P_XO_HPF_ON, g, static_cast<float>(d.xo[g].hpfOn));
    carro_set_param(CARRO_P_XO_LPF_ON, g, static_cast<float>(d.xo[g].lpfOn));
    carro_set_param(CARRO_P_CH_LEVEL_DB, g, 0);
    carro_set_param(CARRO_P_CH_PHASE, g, 0);
    carro_set_param(CARRO_P_CH_MUTE, g, 0);
  }
  carro_set_param(CARRO_P_TA_ON, 0, 0);
  carro_set_param(CARRO_P_SCC, 0, 0);
  carro_set_param(CARRO_P_FADER, 0, 0);
  carro_set_param(CARRO_P_BALANCE, 0, 0);
  carro_set_param(CARRO_P_OUTPUT_MODE, 0, 0);
  carro_set_param(CARRO_P_LIMITER_ON, 0, 1);
  carro_set_param(CARRO_P_LIMITER_CEIL_DB, 0, -1);
  carro_end_batch();
}

// Runs the engine long enough for smoothers/fades to settle.
static void settleEngine() {
  std::vector<float> l(4800, 0.0f), r(4800, 0.0f);
  for (int i = 0; i < 20; ++i) carro_process_planar(l.data(), r.data(), 4800);
}

static void renderEngine(std::vector<float>& L, std::vector<float>& R, int block = 256) {
  for (size_t off = 0; off < L.size(); off += block) {
    const int m = static_cast<int>(std::min<size_t>(block, L.size() - off));
    carro_process_planar(L.data() + off, R.data() + off, m);
  }
}

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::printf("Carro DSP tests - %s\n\n", carro_version());

  run("fft: matches naive DFT and round-trips", [] {
    const int n = 256;
    RealFFT fft(n);
    std::mt19937 rng(1);
    std::uniform_real_distribution<float> u(-1, 1);
    std::vector<float> x(n), re(n / 2 + 1), im(n / 2 + 1), y(n);
    for (auto& v : x) v = u(rng);
    fft.forward(x.data(), re.data(), im.data());
    double maxErr = 0;
    for (int k = 0; k <= n / 2; ++k) {
      double r = 0, i = 0;
      for (int t = 0; t < n; ++t) {
        r += x[t] * std::cos(-2 * kPi * k * t / n);
        i += x[t] * std::sin(-2 * kPi * k * t / n);
      }
      maxErr = std::max(maxErr, std::fabs(r - re[k]) + std::fabs(i - im[k]));
    }
    CHECK(maxErr < 1e-3, "forward error %g", maxErr);
    fft.inverse(re.data(), im.data(), y.data());
    double rt = 0;
    for (int t = 0; t < n; ++t) rt = std::max(rt, static_cast<double>(std::fabs(y[t] - x[t])));
    CHECK(rt < 1e-5, "round-trip error %g", rt);
  });

  run("biquad: RBJ peaking/shelf gains at their corner", [] {
    const auto pk = designFilter(FilterType::Peak, kFs, 1000, 2.15, 12.0);
    CHECK(std::fabs(magnitudeDb(pk, 1000, kFs) - 12.0) < 0.01, "peak %f", magnitudeDb(pk, 1000, kFs));
    CHECK(std::fabs(magnitudeDb(pk, 100, kFs)) < 0.3, "peak skirt %f", magnitudeDb(pk, 100, kFs));
    const auto ls = designFilter(FilterType::LowShelf, kFs, 100, 0.707, 6.0);
    CHECK(std::fabs(magnitudeDb(ls, 20, kFs) - 6.0) < 0.5, "low shelf DC %f", magnitudeDb(ls, 20, kFs));
    CHECK(std::fabs(magnitudeDb(ls, 100, kFs) - 3.0) < 0.2, "low shelf corner %f", magnitudeDb(ls, 100, kFs));
    const auto hs = designFilter(FilterType::HighShelf, kFs, 10000, 0.707, 5.0);
    CHECK(std::fabs(magnitudeDb(hs, 20000, kFs) - 5.0) < 0.6, "high shelf %f", magnitudeDb(hs, 20000, kFs));
  });

  run("crossover: slopes, Butterworth -3 dB, Linkwitz-Riley -6 dB and flat LR sum", [] {
    for (int slope = 6; slope <= 36; slope += 6) {
      const auto lp = designCrossover(false, slope, false, 250, kFs);
      const double at = cascadeMagnitudeDb(lp, 250, kFs);
      CHECK(std::fabs(at + 3.01) < 0.1, "BW%d fc %f", slope, at);
      // asymptotic slope measured over one octave far in the stop band
      const double a1 = cascadeMagnitudeDb(lp, 1000, kFs), a2 = cascadeMagnitudeDb(lp, 2000, kFs);
      CHECK(std::fabs((a1 - a2) - slope) < 1.5, "BW slope %d measured %f", slope, a1 - a2);
    }
    for (int slope : {12, 24, 36}) {
      const auto lp = designCrossover(false, slope, true, 2000, kFs);
      const auto hp = designCrossover(true, slope, true, 2000, kFs);
      CHECK(std::fabs(cascadeMagnitudeDb(lp, 2000, kFs) + 6.02) < 0.1, "LR%d LP fc", slope);
      CHECK(std::fabs(cascadeMagnitudeDb(hp, 2000, kFs) + 6.02) < 0.1, "LR%d HP fc", slope);
      // Complex sum of LR LP + HP (LR4 is in phase; LR2/LR6 need one leg inverted).
      const bool invert = slope != 24;
      double worst = 0;
      for (double f = 50; f < 20000; f *= 1.1) {
        auto H = [&](const FilterCascade& c) {
          std::complex<double> h = 1.0;
          for (int s = 0; s < c.count; ++s) {
            const double w = 2 * kPi * f / kFs;
            const auto z1 = std::polar(1.0, -w), z2 = std::polar(1.0, -2 * w);
            const auto& q = c.sec[s];
            h *= (double(q.b0) + double(q.b1) * z1 + double(q.b2) * z2) / (1.0 + double(q.a1) * z1 + double(q.a2) * z2);
          }
          return h;
        };
        const auto sum = H(lp) + (invert ? -H(hp) : H(hp));
        worst = std::max(worst, std::fabs(20 * std::log10(std::abs(sum))));
      }
      CHECK(worst < 0.1, "LR%d sum deviates %f dB", slope, worst);
    }
  });

  run("geq: impulse response matches band settings (13 and 31 band)", [] {
    for (int mode = 0; mode < 2; ++mode) {
      GraphicEq eq;
      eq.prepare(kFs);
      eq.setMode(mode);
      float g[2][kEqMaxBands] = {};
      int count;
      float q;
      const float* f = GraphicEq::freqsForMode(mode, count, q);
      const int band = mode == 0 ? 5 : 14;  // 500 Hz in both layouts
      g[0][band] = 12.0f;
      g[1][band] = -12.0f;
      eq.setTargets(g);
      eq.snap();
      std::vector<float> L(8192, 0.0f), R(8192, 0.0f);
      L[0] = R[0] = 1.0f;
      eq.process(L.data(), R.data(), 8192);
      const double dl = responseDbAt(L, f[band], kFs), dr = responseDbAt(R, f[band], kFs);
      CHECK(std::fabs(dl - 12.0) < 0.3, "mode %d L %f", mode, dl);
      CHECK(std::fabs(dr + 12.0) < 0.3, "mode %d R %f", mode, dr);
      const double far = responseDbAt(L, 8000, kFs);
      CHECK(std::fabs(far) < 0.5, "mode %d far band %f", mode, far);
    }
  });

  run("engine: flat chain is a pure delay (impulse test)", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    settleEngine();
    const int lat = Engine::instance().latencySamples();
    std::vector<float> L(8192, 0.0f), R(8192, 0.0f);
    L[100] = 0.5f;
    R[100] = -0.25f;
    renderEngine(L, R, 173);  // odd block size on purpose
    double err = 0;
    for (int i = 0; i < 8192; ++i) {
      const float el = i == 100 + lat ? 0.5f : 0.0f;
      const float er = i == 100 + lat ? -0.25f : 0.0f;
      err = std::max(err, static_cast<double>(std::fabs(L[i] - el) + std::fabs(R[i] - er)));
    }
    CHECK(err < 1e-4, "latency %d, max deviation %g", lat, err);
  });

  run("engine: bypass A/B is latency matched and click free", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    carro_set_param(CARRO_P_EQ_BAND, 3, 6.0f);
    carro_set_param(CARRO_P_EQ_BAND, 32 + 3, 6.0f);
    settleEngine();
    const int n = 48000;
    std::vector<float> L(n), R(n);
    for (int i = 0; i < n; ++i) L[i] = R[i] = 0.25f * std::sin(2 * kPi * 440 * i / kFs);
    double maxStep = 0;
    for (int off = 0; off < n; off += 256) {
      if (off == 24064) carro_set_param(CARRO_P_BYPASS, 0, 1);
      carro_process_planar(L.data() + off, R.data() + off, std::min(256, n - off));
    }
    for (int i = 1; i < n; ++i) maxStep = std::max(maxStep, static_cast<double>(std::fabs(L[i] - L[i - 1])));
    const double sineStep = 0.25 * 2 * kPi * 440 / kFs * 2.0;  // generous: 6 dB boost region
    CHECK(maxStep < sineStep * 1.5, "max sample step %f", maxStep);
    carro_set_param(CARRO_P_BYPASS, 0, 0);
  });

  run("engine: structural changes (network mode / EQ mode) are click free", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    settleEngine();
    const int n = 96000;
    std::vector<float> L(n), R(n);
    for (int i = 0; i < n; ++i) L[i] = R[i] = 0.25f * std::sin(2 * kPi * 1000 * i / kFs);
    for (int off = 0; off < n; off += 480) {
      if (off == 24000) carro_set_param(CARRO_P_XO_NETWORK, 0, 1);
      if (off == 48000) carro_set_param(CARRO_P_EQ_MODE, 0, 1);
      if (off == 72000) carro_set_param(CARRO_P_XO_NETWORK, 0, 0);
      carro_process_planar(L.data() + off, R.data() + off, 480);
    }
    double maxStep = 0;
    for (int i = 1; i < n; ++i) maxStep = std::max(maxStep, static_cast<double>(std::fabs(L[i] - L[i - 1])));
    const double sineStep = 0.25 * 2 * kPi * 1000 / kFs;
    CHECK(maxStep < sineStep * 1.3, "max sample step %f (sine %f)", maxStep, sineStep);
  });

  run("reverb: CONCERT HALL (size M) RT60 in 1.8..2.2 s", [] {
    EngineParams p;
    for (int size = 0; size < 3; ++size) {
      ReverbDesign d;
      designReverb(p.sfTable[3], size, 1.0f, kFs, d);
      std::vector<float> l, r;
      AlgoReverb::renderImpulse(d, kFs, static_cast<int>(4.0 * kFs), l, r);
      const float rt = measureRt60Mid(l, r, kFs);
      std::printf("    size %c: RT60 = %.2f s\n", "SML"[size], rt);
      if (size == 1) CHECK(rt > 1.8f && rt < 2.2f, "RT60 %f", rt);
      else CHECK(rt > 1.2f && rt < 3.0f, "RT60 size %d %f", size, rt);
    }
    for (int mode = 1; mode < kNumSfModes; ++mode) {
      ReverbDesign d;
      designReverb(p.sfTable[mode], 1, 1.0f, kFs, d);
      std::vector<float> l, r;
      AlgoReverb::renderImpulse(d, kFs, static_cast<int>(std::max(1.5f, p.sfTable[mode].rt60 * 1.6f) * kFs), l, r);
      const float rt = measureRt60Mid(l, r, kFs);
      const float target = p.sfTable[mode].rt60;
      std::printf("    mode %d: target %.2f s measured %.2f s\n", mode, target, rt);
      CHECK(std::fabs(rt - target) < 0.25f * target + 0.1f, "mode %d rt %f target %f", mode, rt, target);
    }
  });

  run("reverb: wet is decorrelated stereo and stable (bounded energy)", [] {
    EngineParams p;
    ReverbDesign d;
    designReverb(p.sfTable[4], 2, 1.0f, kFs, d);
    std::vector<float> l, r;
    AlgoReverb::renderImpulse(d, kFs, static_cast<int>(8 * kFs), l, r);
    double e1 = 0, e2 = 0, lr = 0, ll = 0, rr = 0;
    const size_t half = l.size() / 2;
    for (size_t i = 0; i < l.size(); ++i) {
      (i < half ? e1 : e2) += l[i] * l[i];
      lr += l[i] * r[i];
      ll += l[i] * l[i];
      rr += r[i] * r[i];
    }
    CHECK(e2 < e1 * 0.01, "late energy not decaying: %g vs %g", e2, e1);
    const double corr = lr / std::sqrt(ll * rr);
    CHECK(std::fabs(corr) < 0.5, "L/R correlation %f", corr);
  });

  run("convolution: equals direct convolution (true stereo, head + tail)", [] {
    std::mt19937 rng(7);
    std::uniform_real_distribution<float> u(-1, 1);
    const int irLen = 30000;
    IrSet ir;
    for (int p = 0; p < 4; ++p) {
      ir.paths[p].resize(irLen);
      for (int i = 0; i < irLen; ++i) ir.paths[p][i] = u(rng) * std::exp(-i / 6000.0f) * (p == 1 || p == 2 ? 0.3f : 1.0f);
    }
    const int n = 50000;
    std::vector<float> xl(n), xr(n);
    for (int i = 0; i < n; ++i) {
      xl[i] = u(rng) * 0.5f;
      xr[i] = u(rng) * 0.5f;
    }
    auto direct = [&](int t, int out) {
      double acc = 0;
      const auto& ha = ir.paths[out == 0 ? 0 : 1];  // from L
      const auto& hb = ir.paths[out == 0 ? 2 : 3];  // from R
      for (int k = 0; k <= t && k < irLen; ++k) acc += xl[t - k] * ha[k] + xr[t - k] * hb[k];
      return acc;
    };
    for (int threaded = 0; threaded < 2; ++threaded) {
      Convolver conv(ir, kFs, threaded == 1);
      std::vector<float> yl(n), yr(n);
      std::mt19937 bs(3);
      for (int off = 0; off < n;) {
        const int m = std::min<int>(n - off, 64 + bs() % 700);  // ragged host blocks
        conv.process(xl.data() + off, xr.data() + off, yl.data() + off, yr.data() + off, m);
        off += m;
        if (threaded) std::this_thread::sleep_for(std::chrono::microseconds(1000 * m / 48));  // real time
      }
      const int lat = conv.latency();
      double maxErr = 0, maxRef = 0;
      for (int t = 0; t < n - lat; t += 37) {  // sampled check (direct conv is O(N^2))
        const double rl = direct(t, 0), rr = direct(t, 1);
        maxErr = std::max(maxErr, std::max(std::fabs(rl - yl[t + lat]), std::fabs(rr - yr[t + lat])));
        maxRef = std::max(maxRef, std::max(std::fabs(rl), std::fabs(rr)));
      }
      std::printf("    %s: max error %.2e (ref peak %.1f), underruns %u\n", threaded ? "threaded" : "inline", maxErr,
                  maxRef, conv.underruns());
      CHECK(maxErr < 2e-3 * maxRef, "%s conv error %g", threaded ? "threaded" : "inline", maxErr);
      CHECK(conv.underruns() == 0, "underruns %u", conv.underruns());
    }
  });

  run("no denormals: long silence after an impulse stays normal and fast", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    carro_begin_batch();
    carro_set_param(CARRO_P_SF_MODE, 0, 4);  // CATHEDRAL
    carro_set_param(CARRO_P_SF_LEVEL, 0, 10);
    carro_set_param(CARRO_P_SF_SIZE, 0, 2);
    carro_set_param(CARRO_P_EQ_BAND, 0, 12);
    carro_set_param(CARRO_P_ASR_MODE, 0, 2);
    carro_set_param(CARRO_P_XO_NETWORK, 0, 1);
    carro_set_param(CARRO_P_SUB_ON, 0, 1);
    carro_set_param(CARRO_P_TA_ON, 0, 1);
    carro_set_param(CARRO_P_TA_DIST_CM, 0, 100);
    carro_end_batch();
    settleEngine();
    const int block = 512;
    std::vector<float> L(block, 0.0f), R(block, 0.0f);
    L[0] = R[0] = 1.0f;
    int subnormals = 0;
    double firstMs = 0, lastMs = 0;
    const int blocks = static_cast<int>(30 * kFs / block);
    for (int b = 0; b < blocks; ++b) {
      if (b > 0) {
        std::fill(L.begin(), L.end(), 0.0f);
        std::fill(R.begin(), R.end(), 0.0f);
      }
      const auto t0 = std::chrono::steady_clock::now();
      carro_process_planar(L.data(), R.data(), block);
      const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
      if (b >= 10 && b < 200) firstMs += ms;
      if (b >= blocks - 190) lastMs += ms;
      for (int i = 0; i < block; ++i)
        if (std::fpclassify(L[i]) == FP_SUBNORMAL || std::fpclassify(R[i]) == FP_SUBNORMAL) ++subnormals;
    }
    std::printf("    early %.2f ms / 190 blocks, after 30 s silence %.2f ms\n", firstMs, lastMs);
    CHECK(subnormals == 0, "%d subnormal output samples", subnormals);
    CHECK(lastMs < firstMs * 3.0 + 5.0, "processing slowed down in silence (%f vs %f)", lastMs, firstMs);
  });

  run("no clipping: +12 dB EQ, bass boost, loudness HIGH, hot input stay under ceiling", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    carro_begin_batch();
    for (int b = 0; b < 13; ++b) {
      carro_set_param(CARRO_P_EQ_BAND, b, 12);
      carro_set_param(CARRO_P_EQ_BAND, 32 + b, 12);
    }
    carro_set_param(CARRO_P_BASS_BOOST, 0, 6);
    carro_set_param(CARRO_P_LOUDNESS, 0, 3);
    carro_set_param(CARRO_P_SLA_DB, 0, 4);
    carro_set_param(CARRO_P_SF_MODE, 0, 3);
    carro_set_param(CARRO_P_SF_LEVEL, 0, 10);
    carro_end_batch();
    settleEngine();
    const int n = static_cast<int>(3 * kFs);
    std::vector<float> L(n), R(n);
    std::mt19937 rng(5);
    std::uniform_real_distribution<float> u(-1, 1);
    for (int i = 0; i < n; ++i) {
      const float sq = std::sin(2 * kPi * 60 * i / kFs) > 0 ? 1.0f : -1.0f;  // full-scale square
      L[i] = i < n / 2 ? sq : u(rng);
      R[i] = i < n / 2 ? 0.99f * std::sin(2 * kPi * 11025.0 * i / kFs + 0.7) : u(rng);  // ISP-prone tone
    }
    renderEngine(L, R, 480);
    const float ceil = dbToGain(-1.0f);
    float peak = 0;
    for (int i = 0; i < n; ++i) peak = std::max(peak, std::max(std::fabs(L[i]), std::fabs(R[i])));
    CHECK(peak <= ceil + 1e-4f, "sample peak %f > ceiling %f", peak, ceil);
    // True peak via 8x windowed-sinc oversampling of a segment.
    std::vector<float> seg(R.begin() + n / 4, R.begin() + n / 4 + 4800);
    std::vector<float> up = resample(seg, kFs, kFs * 8);
    float tp = 0;
    for (size_t i = 400; i + 400 < up.size(); ++i) tp = std::max(tp, std::fabs(up[i]));
    std::printf("    sample peak %.4f, true peak %.4f (ceiling %.4f)\n", peak, tp, ceil);
    CHECK(tp <= ceil * 1.035f, "true peak %f", tp);
  });

  run("ir capture: sweep -> simulated head unit -> deconvolved IR matches", [] {
    const double fs = kFs;
    const double secs = 4.0;
    const int sweepN = static_cast<int>(secs * fs);
    std::vector<float> sweep(sweepN);
    carro_sweep_generate(sweep.data(), sweepN, fs, 20, 20000, 0.5f);
    // "head unit": 37 ms latency, direct + two reflections + decaying diffuse tail
    const int irLen = 12000;
    std::vector<float> h(irLen, 0.0f);
    std::mt19937 rng(11);
    std::normal_distribution<float> nd(0, 1);
    for (int i = 200; i < irLen; ++i) h[i] = 0.05f * nd(rng) * std::exp(-(i - 200) / 1500.0f);
    h[0] = 1.0f;
    h[480] += 0.5f;
    h[1100] -= 0.3f;
    const int latency = static_cast<int>(0.037 * fs);
    const int recN = sweepN + static_cast<int>(1.5 * fs);
    std::vector<float> rec(recN * 2, 0.0f);
    RealFFT dummy;
    for (int t = 0; t < recN; ++t) {
      double acc = 0;
      const int t0 = t - latency;
      if (t0 >= 0)
        for (int k = 0; k < irLen && k <= t0; k += 1) {
          if (t0 - k >= sweepN) continue;
          if (h[k] != 0.0f) acc += h[k] * sweep[t0 - k];
        }
      rec[t * 2] = static_cast<float>(acc + 1e-5 * nd(rng));
      rec[t * 2 + 1] = static_cast<float>(0.5 * acc + 1e-5 * nd(rng));
    }
    const std::string recPath = "test_rec.wav", outPath = "test_ir.wav";
    CHECK(carro_wav_write(recPath.c_str(), rec.data(), recN, 2, static_cast<int>(fs)) == 0, "write rec");
    const int len = carro_ir_build_from_captures(recPath.c_str(), nullptr, outPath.c_str(), fs, 20, 20000, secs, 1.0);
    CHECK(len > 0, "build returned %d", len);
    WavData w;
    CHECK(readWav(outPath, w) == 0 && w.channels == 2, "read ir");
    if (w.frames > 0) {
      std::vector<float> got = w.channel(0);
      // The sweep only excites 20 Hz..20 kHz: compare both IRs band-limited to 40 Hz..15 kHz.
      auto bandLimit = [](std::vector<float>& x) {
        Biquad a, b, c;
        a.c = designFilter(FilterType::LowPass, kFs, 15000, 0.7071, 0);
        b.c = designFilter(FilterType::LowPass, kFs, 15000, 0.7071, 0);
        c.c = designFilter(FilterType::HighPass, kFs, 40, 0.7071, 0);
        a.processBlock(x.data(), static_cast<int>(x.size()));
        b.processBlock(x.data(), static_cast<int>(x.size()));
        c.processBlock(x.data(), static_cast<int>(x.size()));
      };
      std::vector<float> ref(h);
      ref.resize(20000, 0.0f);
      bandLimit(ref);
      std::vector<float> gotBl(got);
      bandLimit(gotBl);
      // find the direct peak and correlate against the reference IR
      size_t pk = 0;
      for (size_t i = 0; i < got.size(); ++i)
        if (std::fabs(got[i]) > std::fabs(got[pk])) pk = i;
      double num = 0, da = 0, db = 0;
      for (int k = 0; k < 8000 && pk + k < gotBl.size(); ++k) {
        const double a = gotBl[pk + k], b = ref[k];
        num += a * b;
        da += a * a;
        db += b * b;
      }
      const double corr = num / std::sqrt(da * db);
      std::printf("    IR frames %d, direct peak at %zu (pre-roll), correlation %.4f\n", w.frames, pk, corr);
      CHECK(pk < static_cast<size_t>(0.002 * fs), "latency not removed: peak at %zu", pk);
      CHECK(corr > 0.98, "correlation %f", corr);
      const std::vector<float> right = w.channel(1);
      CHECK(std::fabs(right[pk] / got[pk] - 0.5) < 0.02, "channel ratio %f", right[pk] / got[pk]);
    }
    std::remove(recPath.c_str());
    std::remove(outPath.c_str());
  });

  run("wav: 24-bit/float read-write round trip and IR load into the engine", [] {
    std::vector<float> ir(4 * 20000);
    std::mt19937 rng(9);
    std::uniform_real_distribution<float> u(-1, 1);
    for (int i = 0; i < 20000; ++i)
      for (int c = 0; c < 4; ++c) ir[i * 4 + c] = u(rng) * std::exp(-i / 4000.0f) * (c == 0 || c == 3 ? 1.0f : 0.2f);
    const std::string path = "test_ts_ir.wav";
    CHECK(carro_wav_write(path.c_str(), ir.data(), 20000, 4, 44100) == 0, "write");
    WavData w;
    CHECK(readWav(path, w) == 0 && w.channels == 4 && w.frames == 20000 && w.sampleRate == 44100, "read back");
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    Engine::instance().setSynchronousConvolver(true);
    CHECK(carro_load_ir_file(path.c_str()) == 0, "load ir");
    float info[4];
    carro_ir_info(info);
    CHECK(info[0] == 1.0f && info[1] == 4.0f, "ir info %f %f", info[0], info[1]);
    carro_begin_batch();
    carro_set_param(CARRO_P_SF_ENGINE, 0, 1);
    carro_set_param(CARRO_P_SF_MODE, 0, 3);
    carro_set_param(CARRO_P_SF_LEVEL, 0, 10);
    carro_set_param(CARRO_P_SF_DRYWET, 0, 1);
    carro_end_batch();
    settleEngine();
    // Loudness match: noise in == noise out (within 2 dB) with 100 % wet convolution.
    const int n = static_cast<int>(2 * kFs);
    std::vector<float> L(n), R(n);
    double ein = 0, eout = 0;
    for (int i = 0; i < n; ++i) {
      L[i] = 0.1f * u(rng);
      R[i] = 0.1f * u(rng);
      ein += L[i] * L[i] + R[i] * R[i];
    }
    renderEngine(L, R, 512);
    for (int i = n / 2; i < n; ++i) eout += L[i] * L[i] + R[i] * R[i];
    const double diff = 10 * std::log10(eout / (ein * 0.5));
    std::printf("    loudness difference wet vs dry: %.2f dB\n", diff);
    CHECK(std::fabs(diff) < 2.0, "loudness mismatch %f dB", diff);
    float curve[64], cinfo[2];
    CHECK(carro_get_decay_curve(curve, 64, cinfo) == 64, "decay curve");
    carro_clear_ir();
    Engine::instance().setSynchronousConvolver(false);
    std::remove(path.c_str());
  });

  run("performance: full chain real-time factor", [] {
    carro_prepare(kFs, 512);
    resetEngineDefaults();
    carro_begin_batch();
    for (int b = 0; b < 13; ++b) carro_set_param(CARRO_P_EQ_BAND, b, (b % 3) - 1.0f);
    carro_set_param(CARRO_P_ASR_MODE, 0, 1);
    carro_set_param(CARRO_P_LOUDNESS, 0, 2);
    carro_set_param(CARRO_P_SF_MODE, 0, 3);
    carro_set_param(CARRO_P_SF_LEVEL, 0, 6);
    carro_set_param(CARRO_P_XO_NETWORK, 0, 1);
    carro_set_param(CARRO_P_SUB_ON, 0, 1);
    carro_set_param(CARRO_P_TA_ON, 0, 1);
    carro_end_batch();
    settleEngine();
    const int n = static_cast<int>(10 * kFs);
    std::vector<float> L(n), R(n);
    std::mt19937 rng(2);
    std::uniform_real_distribution<float> u(-0.3f, 0.3f);
    for (int i = 0; i < n; ++i) L[i] = R[i] = u(rng);
    const auto t0 = std::chrono::steady_clock::now();
    renderEngine(L, R, 512);
    const double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::printf("    10 s of audio in %.3f s -> %.1f%% of one core (desktop)\n", s, 100.0 * s / 10.0);
    CHECK(s < 1.0, "too slow: %f s", s);
  });

  std::printf("\n%d checks passed, %d failed\n", g_passed, g_failed);
  return g_failed == 0 ? 0 : 1;
}
