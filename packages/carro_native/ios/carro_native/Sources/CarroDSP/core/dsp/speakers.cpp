#include "speakers.h"

namespace carro {

namespace {
constexpr float kSccStepCm = 2.5f;
constexpr float kMaxTaCm = 350.0f;

int slopeClamp(int s) {
  s = clampi(s, 6, 36);
  return (s / 6) * 6;
}
}  // namespace

// ---------------------------------------------------------------------------------------------
void SpeakerMatrix::GroupDsp::redesign(double fs, bool force) {
  const float hz = std::exp(hpfLogHz.current());
  const float lz = std::exp(lpfLogHz.current());
  if (hpfOn && (force || std::fabs(hz - designedHpf) > 0.01f)) {
    hpf = designCrossover(true, hpfSlope, lr, hz, fs);
    designedHpf = hz;
    for (int c = 0; c < 2; ++c)
      for (int s = 0; s < hpf.count; ++s) hpfState[c][s].c = hpf.sec[s];
  }
  if (lpfOn && (force || std::fabs(lz - designedLpf) > 0.01f)) {
    lpf = designCrossover(false, lpfSlope, lr, lz, fs);
    designedLpf = lz;
    for (int c = 0; c < 2; ++c)
      for (int s = 0; s < lpf.count; ++s) lpfState[c][s].c = lpf.sec[s];
  }
}

void SpeakerMatrix::GroupDsp::resetStates() {
  for (int c = 0; c < 2; ++c)
    for (int s = 0; s < FilterCascade::kMaxSections; ++s) {
      hpfState[c][s].reset();
      lpfState[c][s].reset();
    }
}

void SpeakerMatrix::DelayLine::init(int maxDelay) {
  int s = 1;
  while (s < maxDelay + 4) s <<= 1;
  buf.assign(s, 0.0f);
  mask = s - 1;
  w = 0;
}

void SpeakerMatrix::DelayLine::clear() { std::fill(buf.begin(), buf.end(), 0.0f); }

// ---------------------------------------------------------------------------------------------
void SpeakerMatrix::prepare(double fs, int /*maxBlock*/) {
  fs_ = fs;
  const int maxDelay = static_cast<int>((kMaxTaCm + 15 * kSccStepCm) / kSpeedOfSoundCmPerSec * fs) + 2;
  for (auto& d : del_) {
    d.init(maxDelay);
    d.delay.setTime(80.0f, fs);
  }
  for (auto& g : g_) {
    g.hpfLogHz.setTime(60.0f, fs);
    g.lpfLogHz.setTime(60.0f, fs);
    g.gain.setTime(30.0f, fs);
  }
  gFront_.setTime(40.0f, fs);
  gRear_.setTime(40.0f, fs);
  gBalL_.setTime(40.0f, fs);
  gBalR_.setTime(40.0f, fs);
  crossfeed_.setTime(60.0f, fs);
  xfLpL_.setCutoff(700.0, fs);
  xfLpR_.setCutoff(700.0, fs);
  xfDelay_ = std::max(1, static_cast<int>(0.00025 * fs));
  xfBufL_.assign(xfDelay_, 0.0f);
  xfBufR_.assign(xfDelay_, 0.0f);
  xfPos_ = 0;
  for (int c = 0; c < 2; ++c) {
    a_[c].assign(kChunk, 0.0f);
    b_[c].assign(kChunk, 0.0f);
  }
  sub_.assign(kChunk, 0.0f);
}

bool SpeakerMatrix::structureDiffers(const EngineParams& a, const EngineParams& b) {
  if (a.network != b.network || a.subOn != b.subOn) return true;
  for (int g = 0; g < kNumGroups; ++g) {
    const XoverGroup& x = a.xo[g];
    const XoverGroup& y = b.xo[g];
    if (x.hpfOn != y.hpfOn || x.lpfOn != y.lpfOn || slopeClamp(x.hpfSlope) != slopeClamp(y.hpfSlope) ||
        slopeClamp(x.lpfSlope) != slopeClamp(y.lpfSlope) || x.type != y.type)
      return true;
  }
  return false;
}

void SpeakerMatrix::applyStructure(const EngineParams& p) {
  network_ = p.network ? 1 : 0;
  subOn_ = p.subOn != 0;
  for (int gi = 0; gi < kNumGroups; ++gi) {
    GroupDsp& g = g_[gi];
    const XoverGroup& x = p.xo[gi];
    if (network_) g.active = gi == kHigh || gi == kMid || (gi == kSub && subOn_);
    else g.active = gi == kFront || gi == kRear || (gi == kSub && subOn_);
    // Which filters exist on which output (mirrors the head unit menus).
    const bool allowHpf = gi == kFront || gi == kRear || gi == kHigh || gi == kMid;
    const bool allowLpf = gi == kSub || gi == kMid;
    g.hpfOn = allowHpf && x.hpfOn;
    g.lpfOn = allowLpf && x.lpfOn;
    g.hpfSlope = slopeClamp(x.hpfSlope);
    g.lpfSlope = slopeClamp(x.lpfSlope);
    g.lr = x.type == 1;
    g.hpfLogHz.snap(std::log(clampf(x.hpfHz, 20.0f, 20000.0f)));
    g.lpfLogHz.snap(std::log(clampf(x.lpfHz, 20.0f, 20000.0f)));
    g.redesign(fs_, true);
    g.resetStates();
  }
  setTargets(p);
}

void SpeakerMatrix::computeSpeakerDelaysSamples(const EngineParams& p, double fs, float out[kNumSpeakers]) {
  float cm[kNumSpeakers] = {0, 0, 0, 0, 0};
  if (p.taOn) {
    float dmax = 0.0f;
    for (int s = 0; s < kNumSpeakers; ++s) {
      if (s == 4 && !p.subOn) continue;
      dmax = std::max(dmax, clampf(p.taDistCm[s], 0.0f, kMaxTaCm));
    }
    for (int s = 0; s < kNumSpeakers; ++s) {
      if (s == 4 && !p.subOn) continue;
      cm[s] = dmax - clampf(p.taDistCm[s], 0.0f, kMaxTaCm);
    }
  }
  // Sonic Center Control: move the image toward the side that stays early.
  const int scc = clampi(p.scc, -15, 15);
  if (scc > 0) {
    cm[0] += scc * kSccStepCm;
    cm[2] += scc * kSccStepCm;
  } else if (scc < 0) {
    cm[1] += -scc * kSccStepCm;
    cm[3] += -scc * kSccStepCm;
  }
  for (int s = 0; s < kNumSpeakers; ++s) out[s] = cm[s] / kSpeedOfSoundCmPerSec * static_cast<float>(fs);
}

void SpeakerMatrix::setTargets(const EngineParams& p) {
  outputMode_ = p.outputMode;
  for (int gi = 0; gi < kNumGroups; ++gi) {
    GroupDsp& g = g_[gi];
    const XoverGroup& x = p.xo[gi];
    g.hpfLogHz.setTarget(std::log(clampf(x.hpfHz, 20.0f, 20000.0f)));
    g.lpfLogHz.setTarget(std::log(clampf(x.lpfHz, 20.0f, 20000.0f)));
    float gain = x.mute ? 0.0f : dbToGain(clampf(x.levelDb, -24.0f, 10.0f));
    if (x.phaseInvert) gain = -gain;
    g.gain.setTarget(gain);
  }
  float delays[kNumSpeakers];
  computeSpeakerDelaysSamples(p, fs_, delays);
  for (int s = 0; s < kNumSpeakers; ++s) del_[s].delay.setTarget(delays[s]);

  const int f = clampi(p.fader, -15, 15);
  if (p.network) {
    gFront_.setTarget(1.0f);
    gRear_.setTarget(1.0f);
  } else {
    gFront_.setTarget(f < 0 ? (15.0f + f) / 15.0f : 1.0f);
    gRear_.setTarget(f > 0 ? (15.0f - f) / 15.0f : 1.0f);
  }
  const int b = clampi(p.balance, -15, 15);
  gBalL_.setTarget(b > 0 ? (15.0f - b) / 15.0f : 1.0f);
  gBalR_.setTarget(b < 0 ? (15.0f + b) / 15.0f : 1.0f);
  crossfeed_.setTarget(p.outputMode == 1 ? clampf(p.crossfeed, 0.0f, 1.0f) * 0.45f : 0.0f);
}

void SpeakerMatrix::snap() {
  for (auto& g : g_) {
    g.hpfLogHz.snap(g.hpfLogHz.target());
    g.lpfLogHz.snap(g.lpfLogHz.target());
    g.gain.snap(g.gain.target());
    g.redesign(fs_, true);
  }
  for (auto& d : del_) d.delay.snap(d.delay.target());
  gFront_.snap(gFront_.target());
  gRear_.snap(gRear_.target());
  gBalL_.snap(gBalL_.target());
  gBalR_.snap(gBalR_.target());
  crossfeed_.snap(crossfeed_.target());
}

void SpeakerMatrix::reset() {
  for (auto& g : g_) g.resetStates();
  for (auto& d : del_) d.clear();
  std::fill(xfBufL_.begin(), xfBufL_.end(), 0.0f);
  std::fill(xfBufR_.begin(), xfBufR_.end(), 0.0f);
  xfLpL_.reset();
  xfLpR_.reset();
}

void SpeakerMatrix::process(float* L, float* R, int n) {
  if (n > kChunk) {  // engine never does this, but stay safe
    for (int off = 0; off < n; off += kChunk) process(L + off, R + off, std::min(kChunk, n - off));
    return;
  }
  // Smooth crossover frequencies once per block.
  for (auto& g : g_) {
    if (!g.active) continue;
    bool moved = false;
    if (!g.hpfLogHz.settled()) { g.hpfLogHz.advance(n); moved = true; }
    if (!g.lpfLogHz.settled()) { g.lpfLogHz.advance(n); moved = true; }
    if (moved) g.redesign(fs_, false);
  }

  float* outL = a_[0].data();
  float* outR = a_[1].data();
  std::fill(outL, outL + n, 0.0f);
  std::fill(outR, outR + n, 0.0f);
  float* tL = b_[0].data();
  float* tR = b_[1].data();

  const int grpA = network_ ? kHigh : kFront;
  const int grpB = network_ ? kMid : kRear;

  // Per-sample smoothed fader weights are captured once for the normalisation below.
  for (int pass = 0; pass < 2; ++pass) {
    const int gi = pass == 0 ? grpA : grpB;
    GroupDsp& g = g_[gi];
    const int slotL = pass == 0 ? 0 : 2, slotR = pass == 0 ? 1 : 3;
    Smoother& fad = pass == 0 ? gFront_ : gRear_;
    if (!g.active) continue;
    std::copy(L, L + n, tL);
    std::copy(R, R + n, tR);
    if (g.hpfOn)
      for (int s = 0; s < g.hpf.count; ++s) {
        g.hpfState[0][s].processBlock(tL, n);
        g.hpfState[1][s].processBlock(tR, n);
      }
    if (g.lpfOn)
      for (int s = 0; s < g.lpf.count; ++s) {
        g.lpfState[0][s].processBlock(tL, n);
        g.lpfState[1][s].processBlock(tR, n);
      }
    DelayLine& dl = del_[slotL];
    DelayLine& dr = del_[slotR];
    for (int i = 0; i < n; ++i) {
      const float gain = g.gain.next() * fad.next();
      // TA delay (fractional, smoothed)
      dl.buf[dl.w & dl.mask] = tL[i] * gain;
      dr.buf[dr.w & dr.mask] = tR[i] * gain;
      const float dls = dl.delay.next(), drs = dr.delay.next();
      const int il = static_cast<int>(dls), ir = static_cast<int>(drs);
      const float fl = dls - il, fr = drs - ir;
      const float l0 = dl.buf[(dl.w - il) & dl.mask], l1 = dl.buf[(dl.w - il - 1) & dl.mask];
      const float r0 = dr.buf[(dr.w - ir) & dr.mask], r1 = dr.buf[(dr.w - ir - 1) & dr.mask];
      dl.w = (dl.w + 1) & 0x3fffffff;
      dr.w = (dr.w + 1) & 0x3fffffff;
      outL[i] += l0 + fl * (l1 - l0);
      outR[i] += r0 + fr * (r1 - r0);
    }
  }

  // Standard mode: normalise so fader centre = unity (front + rear carry the same program).
  if (!network_) {
    // Fader smoothers were advanced inside the loops; use their current value.
    const bool a = g_[grpA].active, b = g_[grpB].active;
    const float wa = a ? gFront_.current() : 0.0f;
    const float wb = b ? gRear_.current() : 0.0f;
    const float norm = 1.0f / std::max(wa + wb, 1e-3f);
    for (int i = 0; i < n; ++i) {
      outL[i] *= norm;
      outR[i] *= norm;
    }
  }

  // Balance on the L/R speakers.
  for (int i = 0; i < n; ++i) {
    outL[i] *= gBalL_.next();
    outR[i] *= gBalR_.next();
  }

  // Subwoofer: mono sum, LPF, level/phase, its own TA delay, into both sides.
  GroupDsp& sg = g_[kSub];
  if (sg.active) {
    float* s = sub_.data();
    for (int i = 0; i < n; ++i) s[i] = 0.5f * (L[i] + R[i]);
    if (sg.lpfOn)
      for (int k = 0; k < sg.lpf.count; ++k) sg.lpfState[0][k].processBlock(s, n);
    DelayLine& d = del_[4];
    for (int i = 0; i < n; ++i) {
      d.buf[d.w & d.mask] = s[i] * sg.gain.next();
      const float ds = d.delay.next();
      const int id = static_cast<int>(ds);
      const float fd = ds - id;
      const float v0 = d.buf[(d.w - id) & d.mask], v1 = d.buf[(d.w - id - 1) & d.mask];
      d.w = (d.w + 1) & 0x3fffffff;
      const float v = v0 + fd * (v1 - v0);
      outL[i] += v;
      outR[i] += v;
    }
  }

  // Headphone crossfeed (Bauer-style: delayed, low-passed opposite channel).
  if (!(crossfeed_.settled() && crossfeed_.current() == 0.0f)) {
    for (int i = 0; i < n; ++i) {
      const float c = crossfeed_.next();
      const float dl = xfBufL_[xfPos_], dr = xfBufR_[xfPos_];
      xfBufL_[xfPos_] = outL[i];
      xfBufR_[xfPos_] = outR[i];
      xfPos_ = (xfPos_ + 1) % xfDelay_;
      const float norm = 1.0f / (1.0f + c);
      const float l = (outL[i] + c * xfLpR_.process(dr)) * norm;
      const float r = (outR[i] + c * xfLpL_.process(dl)) * norm;
      outL[i] = l;
      outR[i] = r;
    }
  }

  std::copy(outL, outL + n, L);
  std::copy(outR, outR + n, R);
}

}  // namespace carro
