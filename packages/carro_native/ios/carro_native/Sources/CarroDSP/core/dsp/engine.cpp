#include "engine.h"

#include <chrono>
#include <cstring>

#include "../carro_api.h"

namespace carro {

namespace {

// Describes where a parameter lives in EngineParams plus its legal range and step.
struct ParamRef {
  float* f = nullptr;
  int* i = nullptr;
  float lo = 0, hi = 1, step = 0;
  bool sf = false;  // affects the algorithmic calibration
  bool ir = false;  // requires a convolver rebuild
};

ParamRef refFor(EngineParams& m, int id, int index) {
  ParamRef r;
  auto I = [&](int* p, float lo, float hi) { r.i = p; r.lo = lo; r.hi = hi; r.step = 1; };
  auto F = [&](float* p, float lo, float hi, float step) { r.f = p; r.lo = lo; r.hi = hi; r.step = step; };
  const bool modeOk = index >= 1 && index < kNumSfModes;
  const bool grpOk = index >= 0 && index < kNumGroups;
  switch (id) {
    case CARRO_P_BYPASS: I(&m.bypass, 0, 1); break;
    case CARRO_P_SLA_DB: F(&m.slaDb, -4, 4, 1); break;
    case CARRO_P_PREAMP_DB: F(&m.preampDb, -12, 6, 0); break;
    case CARRO_P_AUTO_HEADROOM: I(&m.autoHeadroom, 0, 1); break;
    case CARRO_P_ASR_MODE: I(&m.asrMode, 0, 2); break;
    case CARRO_P_EQ_MODE: I(&m.eqMode, 0, 1); break;
    case CARRO_P_EQ_BAND: {
      const int ch = index / 32, band = index % 32;
      if (index >= 0 && ch < 2 && band < kEqMaxBands) F(&m.eq[ch][band], -12, 12, 0);
      break;
    }
    case CARRO_P_LOUDNESS: I(&m.loudness, 0, 3); break;
    case CARRO_P_BASS_BOOST: I(&m.bassBoost, 0, 6); break;
    case CARRO_P_SF_ENGINE: I(&m.sfEngine, 0, 1); break;
    case CARRO_P_SF_MODE: I(&m.sfMode, 0, kNumSfModes - 1); r.sf = true; break;
    case CARRO_P_SF_LEVEL: I(&m.sfLevel, 0, 10); break;
    case CARRO_P_SF_SIZE: I(&m.sfSize, 0, 2); r.sf = true; break;
    case CARRO_P_SF_WIDTH: F(&m.sfWidth, 0, 2, 0); r.sf = true; break;
    case CARRO_P_SF_DRYWET: F(&m.convDryWet, 0, 1, 0); break;
    case CARRO_P_SF_CONV_PREDELAY_MS: F(&m.convPreDelayMs, 0, 100, 0); r.ir = true; break;
    case CARRO_P_SF_LOUDNESS_MATCH: I(&m.loudnessMatch, 0, 1); r.ir = true; r.sf = true; break;
    case CARRO_P_SF_IR_TRIM_START_MS: F(&m.irTrimStartMs, 0, 500, 0); r.ir = true; break;
    case CARRO_P_SF_IR_TRIM_END_MS: F(&m.irTrimEndMs, 0, 6000, 0); r.ir = true; break;
    case CARRO_P_SFT_PREDELAY_MS: if (modeOk) F(&m.sfTable[index].preDelayMs, 0, 100, 0); r.sf = true; break;
    case CARRO_P_SFT_RT60: if (modeOk) F(&m.sfTable[index].rt60, 0.1f, 8, 0); r.sf = true; break;
    case CARRO_P_SFT_LOW_MULT: if (modeOk) F(&m.sfTable[index].lowMult, 0.3f, 3, 0); r.sf = true; break;
    case CARRO_P_SFT_DAMP_HZ: if (modeOk) F(&m.sfTable[index].dampHz, 1000, 20000, 0); r.sf = true; break;
    case CARRO_P_SFT_ER_LEVEL_DB: if (modeOk) F(&m.sfTable[index].erLevelDb, -60, 6, 0); r.sf = true; break;
    case CARRO_P_SFT_LATE_LEVEL_DB: if (modeOk) F(&m.sfTable[index].lateLevelDb, -60, 6, 0); r.sf = true; break;
    case CARRO_P_SFT_DENSITY: if (modeOk) F(&m.sfTable[index].density, 0, 1, 0); r.sf = true; break;
    case CARRO_P_SFT_WIDTH: if (modeOk) F(&m.sfTable[index].width, 0, 1.5f, 0); r.sf = true; break;
    case CARRO_P_SFT_ROOM_W: if (modeOk) F(&m.sfTable[index].roomW, 2, 200, 0); r.sf = true; break;
    case CARRO_P_SFT_ROOM_L: if (modeOk) F(&m.sfTable[index].roomL, 2, 200, 0); r.sf = true; break;
    case CARRO_P_SFT_ROOM_H: if (modeOk) F(&m.sfTable[index].roomH, 2, 60, 0); r.sf = true; break;
    case CARRO_P_SFT_WET_HPF_HZ: if (modeOk) F(&m.sfTable[index].wetHpfHz, 20, 1000, 0); r.sf = true; break;
    case CARRO_P_SFT_MOD_DEPTH_MS: if (modeOk) F(&m.sfTable[index].modDepthMs, 0, 2, 0); r.sf = true; break;
    case CARRO_P_SFT_MOD_RATE_HZ: if (modeOk) F(&m.sfTable[index].modRateHz, 0.05f, 3, 0); r.sf = true; break;
    case CARRO_P_SFT_WET_LPF_HZ: if (modeOk) F(&m.sfTable[index].wetLpfHz, 2000, 20000, 0); r.sf = true; break;
    case CARRO_P_XO_NETWORK: I(&m.network, 0, 1); break;
    case CARRO_P_XO_HPF_ON: if (grpOk) I(&m.xo[index].hpfOn, 0, 1); break;
    case CARRO_P_XO_HPF_HZ: if (grpOk) F(&m.xo[index].hpfHz, 20, 20000, 0); break;
    case CARRO_P_XO_HPF_SLOPE: if (grpOk) I(&m.xo[index].hpfSlope, 6, 36); break;
    case CARRO_P_XO_LPF_ON: if (grpOk) I(&m.xo[index].lpfOn, 0, 1); break;
    case CARRO_P_XO_LPF_HZ: if (grpOk) F(&m.xo[index].lpfHz, 20, 20000, 0); break;
    case CARRO_P_XO_LPF_SLOPE: if (grpOk) I(&m.xo[index].lpfSlope, 6, 36); break;
    case CARRO_P_XO_TYPE: if (grpOk) I(&m.xo[index].type, 0, 1); break;
    case CARRO_P_CH_LEVEL_DB: if (grpOk) F(&m.xo[index].levelDb, -24, 10, 0); break;
    case CARRO_P_CH_PHASE: if (grpOk) I(&m.xo[index].phaseInvert, 0, 1); break;
    case CARRO_P_CH_MUTE: if (grpOk) I(&m.xo[index].mute, 0, 1); break;
    case CARRO_P_SUB_ON: I(&m.subOn, 0, 1); break;
    case CARRO_P_TA_ON: I(&m.taOn, 0, 1); break;
    case CARRO_P_TA_DIST_CM: if (index >= 0 && index < kNumSpeakers) F(&m.taDistCm[index], 0, 350, 2.5f); break;
    case CARRO_P_SCC: I(&m.scc, -15, 15); break;
    case CARRO_P_FADER: I(&m.fader, -15, 15); break;
    case CARRO_P_BALANCE: I(&m.balance, -15, 15); break;
    case CARRO_P_OUTPUT_MODE: I(&m.outputMode, 0, 1); break;
    case CARRO_P_CROSSFEED: F(&m.crossfeed, 0, 1, 0); break;
    case CARRO_P_LIMITER_ON: I(&m.limiterOn, 0, 1); break;
    case CARRO_P_LIMITER_CEIL_DB: F(&m.limiterCeilDb, -6, 0, 0); break;
    default: break;
  }
  if (!r.f && !r.i) r.sf = r.ir = false;
  return r;
}

float energy(const std::vector<float>& v) {
  double e = 0.0;
  for (float x : v) e += double(x) * x;
  return static_cast<float>(e);
}

void resampleCurve(const std::vector<float>& src, float* out, int points) {
  for (int p = 0; p < points; ++p) {
    if (src.empty()) {
      out[p] = -100.0f;
      continue;
    }
    const double pos = points > 1 ? static_cast<double>(p) * (src.size() - 1) / (points - 1) : 0.0;
    const size_t i = static_cast<size_t>(pos);
    const double fr = pos - i;
    const float a = src[i], b = src[std::min(i + 1, src.size() - 1)];
    out[p] = static_cast<float>(a + fr * (b - a));
  }
}

constexpr int kCurvePoints = 512;

}  // namespace

// =============================================================================================
Engine& Engine::instance() {
  static Engine e;
  return e;
}

Engine::Engine() {
  params_.back() = master_;
  params_.publish();
}

Engine::~Engine() {
  delete conv_;
  delete pendingConv_.exchange(nullptr);
  delete retiredConv_.exchange(nullptr);
}

double Engine::controlRate() const { return fs_ > 0 ? fs_ : 48000.0; }

// ---------------------------------------------------------------------------------------------
// Control side
// ---------------------------------------------------------------------------------------------
void Engine::setParam(int id, int index, float value) {
  if (!std::isfinite(value)) return;
  std::lock_guard<std::mutex> lk(ctrl_);
  bool sf = false, ir = false;
  if (!setParamLocked(id, index, value, sf, ir)) return;
  pendingSf_ |= sf;
  pendingIr_ |= ir;
  if (batchDepth_ == 0) commitLocked();
}

bool Engine::setParamLocked(int id, int index, float value, bool& sfDirty, bool& irDirty) {
  ParamRef r = refFor(master_, id, index);
  if (!r.f && !r.i) return false;
  float v = clampf(value, r.lo, r.hi);
  if (r.step > 0) v = std::round(v / r.step) * r.step;
  if (r.i) {
    const int iv = static_cast<int>(std::lround(v));
    if (*r.i == iv) return false;
    *r.i = iv;
  } else {
    if (*r.f == v) return false;
    *r.f = v;
  }
  // Table edits of a mode that is not active only matter once it becomes active.
  if (id >= CARRO_P_SFT_PREDELAY_MS && id <= CARRO_P_SFT_WET_LPF_HZ && index != master_.sfMode) r.sf = false;
  sfDirty = r.sf;
  irDirty = r.ir && irSrc_.loaded;
  return true;
}

float Engine::getParam(int id, int index) {
  std::lock_guard<std::mutex> lk(ctrl_);
  ParamRef r = refFor(master_, id, index);
  if (r.i) return static_cast<float>(*r.i);
  if (r.f) return *r.f;
  return 0.0f;
}

void Engine::beginBatch() {
  std::lock_guard<std::mutex> lk(ctrl_);
  ++batchDepth_;
}

void Engine::endBatch() {
  std::lock_guard<std::mutex> lk(ctrl_);
  if (batchDepth_ > 0) --batchDepth_;
  if (batchDepth_ == 0) commitLocked();
}

void Engine::requestReset() {
  std::lock_guard<std::mutex> lk(ctrl_);
  ++master_.resetCounter;
  if (batchDepth_ == 0) commitLocked();
}

void Engine::commitLocked() {
  if (pendingSf_) {
    recalibrateAlgoLocked();
    pendingSf_ = false;
  }
  if (pendingIr_) {
    rebuildConvolverLocked();
    pendingIr_ = false;
  }
  collectRetiredLocked();
  params_.back() = master_;
  params_.publish();
}

void Engine::collectRetiredLocked() { delete retiredConv_.exchange(nullptr, std::memory_order_acq_rel); }

void Engine::recalibrateAlgoLocked() {
  const int mode = master_.sfMode;
  if (mode <= 0) {
    master_.algoWetNorm = 1.0f;
    algoCurve_.clear();
    algoRt60_ = 0.0f;
    algoCurveSec_ = 0.0f;
    return;
  }
  const double fs = controlRate();
  ReverbDesign d;
  designReverb(master_.sfTable[mode], master_.sfSize, master_.sfWidth, fs, d);
  float dimS, rtS, preS;
  sizeScale(master_.sfSize, dimS, rtS, preS);
  const SfModeParams& t = master_.sfTable[mode];
  const double rtEff = t.rt60 * rtS * std::max(1.0f, t.lowMult);
  const double seconds = std::min(3.0, std::max(0.4, 0.6 * rtEff + 0.15 + t.preDelayMs * 0.001));
  const int frames = static_cast<int>(seconds * fs);
  std::vector<float> l, r;
  AlgoReverb::renderImpulse(d, fs, frames, l, r);
  const double e = 0.5 * (static_cast<double>(energy(l)) + energy(r));
  master_.algoWetNorm = e > 1e-12 ? static_cast<float>(1.0 / std::sqrt(e)) : 1.0f;
  algoCurve_.resize(kCurvePoints);
  energyDecayCurve(l, r, algoCurve_.data(), kCurvePoints);
  algoCurveSec_ = static_cast<float>(seconds);
  algoRt60_ = measureRt60Mid(l, r, fs);
}

void Engine::rebuildConvolverLocked() {
  if (!irSrc_.loaded) return;
  const double fs = controlRate();
  const WavData& w = irSrc_.wav;
  auto get = [&](int c) { return resample(w.channel(c), w.sampleRate, fs); };
  IrSet set;
  if (w.channels == 1) {
    set.paths[0] = get(0);
    set.paths[3] = set.paths[0];
  } else if (w.channels >= 4) {
    for (int p = 0; p < 4; ++p) set.paths[p] = get(p);
  } else {
    set.paths[0] = get(0);
    set.paths[3] = get(1);
  }
  // Trim, fade, cap at 6 s, pre-delay.
  const size_t start = static_cast<size_t>(master_.irTrimStartMs * 0.001 * fs);
  size_t end = master_.irTrimEndMs > 0 ? static_cast<size_t>(master_.irTrimEndMs * 0.001 * fs) : SIZE_MAX;
  end = std::min(end, start + static_cast<size_t>(6.0 * fs));
  const size_t pre = static_cast<size_t>(master_.convPreDelayMs * 0.001 * fs);
  for (auto& v : set.paths) {
    if (v.empty()) continue;
    const size_t e = std::min(end, v.size());
    std::vector<float> t;
    if (e > start) t.assign(v.begin() + start, v.begin() + e);
    const size_t fade = std::min<size_t>(t.size() / 10, static_cast<size_t>(0.01 * fs));
    for (size_t i = 0; i < fade; ++i) t[t.size() - 1 - i] *= static_cast<float>(i) / fade;
    std::vector<float> out(pre, 0.0f);
    out.insert(out.end(), t.begin(), t.end());
    v.swap(out);
  }
  if (master_.loudnessMatch) {
    const double eL = energy(set.paths[0]) + energy(set.paths[2]);
    const double eR = energy(set.paths[1]) + energy(set.paths[3]);
    const double e = 0.5 * (eL + eR);
    if (e > 1e-12) {
      const float g = static_cast<float>(1.0 / std::sqrt(e));
      for (auto& v : set.paths)
        for (float& x : v) x *= g;
    }
  }
  const int len = set.length();
  irLengthSec_ = static_cast<float>(len / fs);
  // Decay curve of the output for an impulse on both inputs.
  std::vector<float> yl(len, 0.0f), yr(len, 0.0f);
  auto acc = [&](std::vector<float>& y, const std::vector<float>& h) {
    for (size_t i = 0; i < h.size(); ++i) y[i] += h[i];
  };
  acc(yl, set.paths[0]);
  acc(yl, set.paths[2]);
  acc(yr, set.paths[1]);
  acc(yr, set.paths[3]);
  convCurve_.resize(kCurvePoints);
  energyDecayCurve(yl, yr, convCurve_.data(), kCurvePoints);
  convCurveSec_ = irLengthSec_;
  convRt60_ = measureRt60Mid(yl, yr, fs);

  Convolver* c = new Convolver(set, fs, !syncConv_);
  delete pendingConv_.exchange(c, std::memory_order_acq_rel);  // never taken -> safe to free
  convGen_.fetch_add(1, std::memory_order_acq_rel);
  ++master_.irGeneration;
}

int Engine::loadIrFile(const std::string& path) {
  WavData w;
  const int err = readWav(path, w);
  if (err != CARRO_OK) return err;
  if (w.frames < 16 || w.channels < 1) return CARRO_ERR_FORMAT;
  std::lock_guard<std::mutex> lk(ctrl_);
  irSrc_.loaded = true;
  irSrc_.path = path;
  irSrc_.wav = std::move(w);
  rebuildConvolverLocked();
  pendingIr_ = false;
  if (batchDepth_ == 0) commitLocked();
  return CARRO_OK;
}

void Engine::clearIr() {
  std::lock_guard<std::mutex> lk(ctrl_);
  if (!irSrc_.loaded && !pendingConv_.load()) return;
  irSrc_ = IrSource();
  convCurve_.clear();
  convRt60_ = 0.0f;
  irLengthSec_ = 0.0f;
  delete pendingConv_.exchange(nullptr, std::memory_order_acq_rel);
  convGen_.fetch_add(1, std::memory_order_acq_rel);
  ++master_.irGeneration;
  if (batchDepth_ == 0) commitLocked();
}

void Engine::irInfo(float* out4) {
  std::lock_guard<std::mutex> lk(ctrl_);
  out4[0] = irSrc_.loaded ? 1.0f : 0.0f;
  out4[1] = static_cast<float>(irSrc_.wav.channels);
  out4[2] = static_cast<float>(irSrc_.wav.sampleRate);
  out4[3] = irLengthSec_;
}

int Engine::getSpectrum(float* outDb, int bands) {
  if (!outDb || bands <= 0) return 0;
  std::lock_guard<std::mutex> lk(anaMu_);
  const int n = 4096;
  analyzerBuf_.resize(n);
  tap_.snapshot(analyzerBuf_.data(), n);
  const double fs = sampleRate() > 0 ? sampleRate() : 48000.0;
  spectrumBands(analyzerBuf_.data(), n, fs, outDb, bands, analyzerFft_);
  return bands;
}

void Engine::getMeters(float* out6) {
  out6[0] = peakL_.exchange(0.0f, std::memory_order_relaxed);
  out6[1] = peakR_.exchange(0.0f, std::memory_order_relaxed);
  out6[2] = grDb_.load(std::memory_order_relaxed);
  out6[3] = cpu_.load(std::memory_order_relaxed);
  const double fs = sampleRate();
  out6[4] = fs > 0 ? static_cast<float>(1000.0 * latency_ / fs) : 0.0f;
  out6[5] = static_cast<float>(convUnderruns_.load(std::memory_order_relaxed));
  // Opportunistic cleanup of a convolver the audio thread has finished with.
  delete retiredConv_.exchange(nullptr, std::memory_order_acq_rel);
}

int Engine::getDecayCurve(float* outDb, int points, float* info2) {
  std::lock_guard<std::mutex> lk(ctrl_);
  const bool conv = master_.sfEngine == 1 && irSrc_.loaded && !convCurve_.empty();
  const std::vector<float>* src = conv ? &convCurve_ : (master_.sfMode > 0 ? &algoCurve_ : nullptr);
  if (!src || src->empty() || points <= 0) {
    if (info2) info2[0] = info2[1] = 0.0f;
    return 0;
  }
  resampleCurve(*src, outDb, points);
  if (info2) {
    info2[0] = conv ? convCurveSec_ : algoCurveSec_;
    info2[1] = conv ? convRt60_ : algoRt60_;
  }
  return points;
}

int Engine::getResponse(int curve, const float* freqs, float* outDb, int n) {
  if (!freqs || !outDb || n <= 0) return 0;
  std::lock_guard<std::mutex> lk(ctrl_);
  const double fs = controlRate();
  const EngineParams& m = master_;
  std::vector<BiquadCoeffs> secs;
  float offsetDb = 0.0f;
  bool muted = false;
  if (curve == CARRO_CURVE_EQ_L || curve == CARRO_CURVE_EQ_R) {
    int count;
    float q;
    const float* f = GraphicEq::freqsForMode(m.eqMode, count, q);
    const int ch = curve == CARRO_CURVE_EQ_R ? 1 : 0;
    for (int i = 0; i < count; ++i)
      if (m.eq[ch][i] != 0.0f) secs.push_back(designFilter(FilterType::Peak, fs, f[i], q, m.eq[ch][i]));
  } else if (curve == CARRO_CURVE_TONE) {
    float lo, hi;
    ToneStage::loudnessGains(m.loudness, lo, hi);
    secs.push_back(designFilter(FilterType::LowShelf, fs, ToneStage::kLoudLowHz, 0.707, lo));
    secs.push_back(designFilter(FilterType::HighShelf, fs, ToneStage::kLoudHighHz, 0.707, hi));
    secs.push_back(designFilter(FilterType::Peak, fs, ToneStage::kBassHz, ToneStage::kBassQ,
                                ToneStage::bassBoostDb(m.bassBoost)));
  } else if (curve >= CARRO_CURVE_GROUP_BASE && curve < CARRO_CURVE_GROUP_BASE + kNumGroups) {
    const int gi = curve - CARRO_CURVE_GROUP_BASE;
    const XoverGroup& x = m.xo[gi];
    const bool allowHpf = gi == kFront || gi == kRear || gi == kHigh || gi == kMid;
    const bool allowLpf = gi == kSub || gi == kMid;
    if (allowHpf && x.hpfOn) {
      const FilterCascade c = designCrossover(true, (clampi(x.hpfSlope, 6, 36) / 6) * 6, x.type == 1, x.hpfHz, fs);
      for (int s = 0; s < c.count; ++s) secs.push_back(c.sec[s]);
    }
    if (allowLpf && x.lpfOn) {
      const FilterCascade c = designCrossover(false, (clampi(x.lpfSlope, 6, 36) / 6) * 6, x.type == 1, x.lpfHz, fs);
      for (int s = 0; s < c.count; ++s) secs.push_back(c.sec[s]);
    }
    offsetDb = x.levelDb;
    muted = x.mute != 0 || (gi == kSub && !m.subOn);
  } else {
    return 0;
  }
  for (int i = 0; i < n; ++i) {
    double db = offsetDb;
    for (const auto& s : secs) db += magnitudeDb(s, freqs[i], fs);
    outDb[i] = muted ? -120.0f : static_cast<float>(std::max(-120.0, db));
  }
  return n;
}

// ---------------------------------------------------------------------------------------------
// Audio side
// ---------------------------------------------------------------------------------------------
void Engine::prepare(double sampleRate, int maxBlock) {
  if (sampleRate < 8000.0 || sampleRate > 384000.0) return;
  std::lock_guard<std::mutex> lk(ctrl_);
  prepared_.store(false, std::memory_order_release);
  const bool rateChanged = std::fabs(sampleRate - fs_) > 0.5 || fsAtomic_.load() == 0.0;
  fs_ = sampleRate;
  fsAtomic_.store(sampleRate, std::memory_order_release);

  inGain_.setTime(30.0f, fs_);
  asr_.prepare(fs_);
  geq_.prepare(fs_);
  tone_.prepare(fs_);
  algo_.prepare(fs_);
  speakers_.prepare(fs_, maxBlock);
  limiter_.prepare(fs_);
  sfDry_.setTime(30.0f, fs_);
  sfWetAlgo_.setTime(30.0f, fs_);
  sfWetConv_.setTime(30.0f, fs_);
  bypassMix_.setTime(15.0f, fs_);
  wetFadeStep_ = static_cast<float>(1.0 / (0.03 * fs_));
  fadeStep_ = static_cast<float>(1.0 / (0.012 * fs_));

  dryDelayL_.assign(Convolver::kHeadBlock, 0.0f);
  dryDelayR_.assign(Convolver::kHeadBlock, 0.0f);
  dryPos_ = 0;
  latency_ = Convolver::kHeadBlock + limiter_.latency();
  byDelayL_.assign(latency_, 0.0f);
  byDelayR_.assign(latency_, 0.0f);
  byPos_ = 0;
  for (auto* v : {&dlyL_, &dlyR_, &wetL_, &wetR_, &wet2L_, &wet2R_, &dryInL_, &dryInR_}) v->assign(kChunk, 0.0f);

  // Sample-rate dependent control data.
  if (rateChanged) {
    recalibrateAlgoLocked();
    rebuildConvolverLocked();
    pendingSf_ = pendingIr_ = false;
  }
  // Audio thread is idle: adopt any pending convolver directly.
  if (convGen_.load() != convGenSeen_) {
    Convolver* c = pendingConv_.exchange(nullptr, std::memory_order_acq_rel);
    delete conv_;
    conv_ = c;
    convGenSeen_ = convGen_.load();
  }
  if (conv_ && std::fabs(conv_->sampleRate() - fs_) > 0.5) {
    delete conv_;
    conv_ = nullptr;
  }
  collectRetiredLocked();

  params_.update();  // drop any stale snapshot
  params_.back() = master_;
  params_.publish();
  params_.update();
  active_ = master_;
  hasPending_ = false;
  applyStructural(active_);
  applySmooth(active_);
  inGain_.snap(inGain_.target());
  geq_.snap();
  tone_.snap();
  speakers_.snap();
  sfDry_.snap(sfDry_.target());
  sfWetAlgo_.snap(sfWetAlgo_.target());
  sfWetConv_.snap(sfWetConv_.target());
  bypassMix_.snap(bypassMix_.target());
  resetStates();
  sfDesignValid_ = false;
  wetFade_ = WetFade::Idle;
  wetFadeGain_ = 1.0f;
  fade_ = Fade::None;
  fadeGain_ = 1.0f;
  prepared_.store(true, std::memory_order_release);
}

bool Engine::structural(const EngineParams& a, const EngineParams& b) {
  return a.eqMode != b.eqMode || a.resetCounter != b.resetCounter || SpeakerMatrix::structureDiffers(a, b);
}

void Engine::applyStructural(const EngineParams& p) {
  geq_.setMode(p.eqMode);
  speakers_.applyStructure(p);
}

void Engine::applySmooth(const EngineParams& p) {
  float headroom = 0.0f;
  if (p.autoHeadroom) {
    int count;
    float q;
    GraphicEq::freqsForMode(p.eqMode, count, q);
    float maxEq = 0.0f;
    for (int c = 0; c < 2; ++c)
      for (int i = 0; i < count; ++i) maxEq = std::max(maxEq, p.eq[c][i]);
    float lo, hi;
    ToneStage::loudnessGains(p.loudness, lo, hi);
    headroom = -0.5f * (maxEq + std::max(lo, hi) + ToneStage::bassBoostDb(p.bassBoost));
    headroom = std::max(headroom, -12.0f);
  }
  inGain_.setTarget(dbToGain(p.slaDb + p.preampDb + headroom));
  asr_.setMode(p.asrMode);
  geq_.setTargets(p.eq);
  tone_.setTargets(p.loudness, p.bassBoost);
  updateSoundFieldTargets(p);
  speakers_.setTargets(p);
  limiter_.setEnabled(p.limiterOn != 0);
  limiter_.setCeilingDb(p.limiterCeilDb);
  bypassMix_.setTarget(p.bypass ? 1.0f : 0.0f);
}

void Engine::updateSoundFieldTargets(const EngineParams& p) {
  const bool on = p.sfMode > 0 && p.sfLevel > 0;
  float dry = 1.0f, wa = 0.0f, wc = 0.0f;
  if (on) {
    const bool useConv = p.sfEngine == 1 && conv_ != nullptr;
    if (useConv) {
      const float m = clampf(p.convDryWet, 0.0f, 1.0f) * static_cast<float>(p.sfLevel) / 10.0f;
      if (p.loudnessMatch) {
        dry = std::cos(m * kPiF * 0.5f);
        wc = std::sin(m * kPiF * 0.5f);
      } else {
        dry = 1.0f - m;
        wc = m;
      }
    } else {
      // LEVEL 1..10 -> wet -20..-4 dB relative to the dry signal (unit-energy wet).
      const float b = dbToGain(-20.0f + (p.sfLevel - 1) * (16.0f / 9.0f));
      if (p.loudnessMatch) {
        const float g = 1.0f / std::sqrt(1.0f + b * b);
        dry = g;
        wa = g * b * p.algoWetNorm;
      } else {
        wa = b * p.algoWetNorm;
      }
    }
  }
  sfDry_.setTarget(dry);
  sfWetAlgo_.setTarget(wa);
  sfWetConv_.setTarget(wc);
}

void Engine::resetStates() {
  asr_.reset();
  geq_.reset();
  tone_.reset();
  algo_.reset();
  speakers_.reset();
  limiter_.reset();
  std::fill(dryDelayL_.begin(), dryDelayL_.end(), 0.0f);
  std::fill(dryDelayR_.begin(), dryDelayR_.end(), 0.0f);
}

void Engine::process(float* L, float* R, int n) {
  if (!L || !R || n <= 0 || !prepared_.load(std::memory_order_acquire)) return;
  DenormalGuard guard;
  const auto t0 = std::chrono::steady_clock::now();

  if (params_.update()) {
    pending_ = params_.front();
    hasPending_ = true;
  }
  if (hasPending_ && fade_ == Fade::None) {
    if (structural(active_, pending_)) {
      fade_ = Fade::Out;
    } else {
      active_ = pending_;
      applySmooth(active_);
      hasPending_ = false;
    }
  }

  for (int off = 0; off < n; off += kChunk) processChunk(L + off, R + off, std::min(kChunk, n - off));

  const double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  const double budget = n / fs_;
  cpuSmooth_ += 0.05f * (static_cast<float>(dt / budget) - cpuSmooth_);
  cpu_.store(cpuSmooth_, std::memory_order_relaxed);
  if (conv_) convUnderruns_.store(conv_->underruns(), std::memory_order_relaxed);
}

void Engine::processSoundField(float* L, float* R, int n) {
  const EngineParams& p = active_;
  const bool keyChanged = p.sfMode != sfKeyMode_ || p.sfSize != sfKeySize_ || p.sfWidth != sfKeyWidth_ ||
                          p.sfEngine != sfKeyEngine_ ||
                          std::memcmp(&p.sfTable[p.sfMode], &sfKeyTable_, sizeof(SfModeParams)) != 0;
  auto applyDesign = [&]() {
    designReverb(p.sfTable[p.sfMode], p.sfSize, p.sfWidth, fs_, sfDesign_);
    if (p.sfMode == 0) sfDesign_.active = false;
    algo_.apply(sfDesign_);
    sfKeyMode_ = p.sfMode;
    sfKeySize_ = p.sfSize;
    sfKeyWidth_ = p.sfWidth;
    sfKeyEngine_ = p.sfEngine;
    sfKeyTable_ = p.sfTable[p.sfMode];
  };
  if (!sfDesignValid_) {
    applyDesign();
    sfDesignValid_ = true;
  }
  const bool convChange = convGen_.load(std::memory_order_acquire) != convGenSeen_;
  if ((keyChanged || convChange) && wetFade_ == WetFade::Idle) wetFade_ = WetFade::Out;

  // Dry path delayed by the convolver latency so dry, algorithmic and convolved paths align.
  for (int i = 0; i < n; ++i) {
    dlyL_[i] = dryDelayL_[dryPos_];
    dlyR_[i] = dryDelayR_[dryPos_];
    dryDelayL_[dryPos_] = L[i];
    dryDelayR_[dryPos_] = R[i];
    if (++dryPos_ == Convolver::kHeadBlock) dryPos_ = 0;
  }
  const bool algoOn = !(sfWetAlgo_.settled() && sfWetAlgo_.current() == 0.0f);
  const bool convOn = conv_ && !(sfWetConv_.settled() && sfWetConv_.current() == 0.0f);
  if (algoOn) algo_.process(dlyL_.data(), dlyR_.data(), wetL_.data(), wetR_.data(), n);
  if (convOn) conv_->process(L, R, wet2L_.data(), wet2R_.data(), n);

  for (int i = 0; i < n; ++i) {
    const float d = sfDry_.next();
    const float wa = sfWetAlgo_.next();
    const float wc = sfWetConv_.next();
    if (wetFade_ == WetFade::Out) wetFadeGain_ = std::max(0.0f, wetFadeGain_ - wetFadeStep_);
    else if (wetFade_ == WetFade::In) wetFadeGain_ = std::min(1.0f, wetFadeGain_ + wetFadeStep_);
    float wl = 0.0f, wr = 0.0f;
    if (algoOn) { wl += wa * wetL_[i]; wr += wa * wetR_[i]; }
    if (convOn) { wl += wc * wet2L_[i]; wr += wc * wet2R_[i]; }
    L[i] = d * dlyL_[i] + wetFadeGain_ * wl;
    R[i] = d * dlyR_[i] + wetFadeGain_ * wr;
  }

  if (wetFade_ == WetFade::Out && wetFadeGain_ <= 0.0f) {
    bool ready = true;
    if (convGen_.load(std::memory_order_acquire) != convGenSeen_) {
      if (retiredConv_.load(std::memory_order_acquire) == nullptr) {
        const uint32_t gen = convGen_.load(std::memory_order_acquire);
        Convolver* c = pendingConv_.exchange(nullptr, std::memory_order_acq_rel);
        if (c && std::fabs(c->sampleRate() - fs_) > 0.5) {
          retiredConv_.store(c, std::memory_order_release);  // wrong rate: hand straight back
        } else {
          if (conv_) retiredConv_.store(conv_, std::memory_order_release);
          conv_ = c;
        }
        convGenSeen_ = gen;
      } else {
        ready = false;  // wait until the control side collected the previous one
      }
    }
    if (ready) {
      applyDesign();
      updateSoundFieldTargets(active_);
      wetFade_ = WetFade::In;
    }
  } else if (wetFade_ == WetFade::In && wetFadeGain_ >= 1.0f) {
    wetFade_ = WetFade::Idle;
  }
}

void Engine::processChunk(float* L, float* R, int n) {
  std::memcpy(dryInL_.data(), L, sizeof(float) * n);
  std::memcpy(dryInR_.data(), R, sizeof(float) * n);

  // SLA / pre-amp / auto headroom
  for (int i = 0; i < n; ++i) {
    const float g = inGain_.next();
    L[i] *= g;
    R[i] *= g;
  }
  asr_.process(L, R, n);
  geq_.process(L, R, n);
  tone_.process(L, R, n);
  processSoundField(L, R, n);
  speakers_.process(L, R, n);
  limiter_.process(L, R, n);
  grDb_.store(-gainToDb(limiter_.lastMinGain()), std::memory_order_relaxed);

  // Structural fade (EQ mode, crossover topology, reset).
  if (fade_ != Fade::None) {
    for (int i = 0; i < n; ++i) {
      if (fade_ == Fade::Out) fadeGain_ = std::max(0.0f, fadeGain_ - fadeStep_);
      else fadeGain_ = std::min(1.0f, fadeGain_ + fadeStep_);
      L[i] *= fadeGain_;
      R[i] *= fadeGain_;
    }
    if (fade_ == Fade::Out && fadeGain_ <= 0.0f) {
      active_ = pending_;
      hasPending_ = false;
      applyStructural(active_);
      applySmooth(active_);
      geq_.snap();
      speakers_.snap();
      resetStates();
      fade_ = Fade::In;
    } else if (fade_ == Fade::In && fadeGain_ >= 1.0f) {
      fade_ = Fade::None;
    }
  }

  // Bypass (A/B) against the latency-matched dry signal.
  float sum = 0.0f, pl = 0.0f, pr = 0.0f;
  for (int i = 0; i < n; ++i) {
    const float dl = byDelayL_[byPos_], dr = byDelayR_[byPos_];
    byDelayL_[byPos_] = dryInL_[i];
    byDelayR_[byPos_] = dryInR_[i];
    if (++byPos_ == latency_) byPos_ = 0;
    const float m = bypassMix_.next();
    if (m > 0.0f) {
      L[i] = L[i] + m * (clampf(dl, -1.0f, 1.0f) - L[i]);
      R[i] = R[i] + m * (clampf(dr, -1.0f, 1.0f) - R[i]);
    }
    sum += L[i] + R[i];
    pl = std::max(pl, std::fabs(L[i]));
    pr = std::max(pr, std::fabs(R[i]));
  }
  // NaN/Inf guard: never let a blown-up state reach the DAC.
  if (!std::isfinite(sum)) {
    std::memset(L, 0, sizeof(float) * n);
    std::memset(R, 0, sizeof(float) * n);
    resetStates();
    pl = pr = 0.0f;
  }
  atomicMax(peakL_, pl);
  atomicMax(peakR_, pr);
  tap_.push(L, R, n);
}

}  // namespace carro
