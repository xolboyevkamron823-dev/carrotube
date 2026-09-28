#include "convolver.h"

#include <algorithm>
#include <chrono>
#include <cstring>

namespace carro {

// ---------------------------------------------------------------------------------------------
void Convolver::Stage::init(const IrSet& ir, int offset, int length, int partSize) {
  P = partSize;
  bins = P + 1;
  parts = std::max(1, (length + P - 1) / P);
  fft.init(2 * P);
  timeBuf.assign(2 * P, 0.0f);
  outBuf.assign(2 * P, 0.0f);
  for (int p = 0; p < 4; ++p) {
    const auto& h = ir.paths[p];
    pathOn[p] = static_cast<int>(h.size()) > offset;
    if (!pathOn[p]) {
      hRe[p].clear();
      hIm[p].clear();
      continue;
    }
    hRe[p].assign(static_cast<size_t>(parts) * bins, 0.0f);
    hIm[p].assign(static_cast<size_t>(parts) * bins, 0.0f);
    for (int k = 0; k < parts; ++k) {
      std::fill(timeBuf.begin(), timeBuf.end(), 0.0f);
      const int start = offset + k * P;
      const int end = std::min<int>(static_cast<int>(h.size()), std::min(offset + length, start + P));
      for (int i = start; i < end; ++i) timeBuf[i - start] = h[i];
      fft.forward(timeBuf.data(), &hRe[p][static_cast<size_t>(k) * bins], &hIm[p][static_cast<size_t>(k) * bins]);
    }
  }
  for (int c = 0; c < 2; ++c) {
    xRe[c].assign(static_cast<size_t>(parts) * bins, 0.0f);
    xIm[c].assign(static_cast<size_t>(parts) * bins, 0.0f);
    accRe[c].assign(bins, 0.0f);
    accIm[c].assign(bins, 0.0f);
    prevIn[c].assign(P, 0.0f);
  }
  fdlPos = 0;
}

void Convolver::Stage::processSegment(const float* inL, const float* inR, float* outL, float* outR) {
  const float* in[2] = {inL, inR};
  const bool needIn[2] = {pathOn[0] || pathOn[1], pathOn[2] || pathOn[3]};
  // 1) forward FFT of [previous P | current P] into the FDL slot.
  for (int c = 0; c < 2; ++c) {
    if (!needIn[c]) continue;
    std::memcpy(timeBuf.data(), prevIn[c].data(), sizeof(float) * P);
    std::memcpy(timeBuf.data() + P, in[c], sizeof(float) * P);
    std::memcpy(prevIn[c].data(), in[c], sizeof(float) * P);
    fft.forward(timeBuf.data(), &xRe[c][static_cast<size_t>(fdlPos) * bins], &xIm[c][static_cast<size_t>(fdlPos) * bins]);
  }
  // 2) complex multiply-accumulate over all partitions.
  // output L = X_L * H_LL + X_R * H_RL ; output R = X_L * H_LR + X_R * H_RR
  static constexpr int kSrc[4] = {0, 0, 1, 1};
  static constexpr int kDst[4] = {0, 1, 0, 1};
  for (int o = 0; o < 2; ++o) {
    std::fill(accRe[o].begin(), accRe[o].end(), 0.0f);
    std::fill(accIm[o].begin(), accIm[o].end(), 0.0f);
  }
  for (int path = 0; path < 4; ++path) {
    if (!pathOn[path]) continue;
    const int src = kSrc[path];
    float* __restrict aR = accRe[kDst[path]].data();
    float* __restrict aI = accIm[kDst[path]].data();
    for (int k = 0; k < parts; ++k) {
      int slot = fdlPos - k;
      if (slot < 0) slot += parts;
      const float* __restrict xr = &xRe[src][static_cast<size_t>(slot) * bins];
      const float* __restrict xi = &xIm[src][static_cast<size_t>(slot) * bins];
      const float* __restrict hr = &hRe[path][static_cast<size_t>(k) * bins];
      const float* __restrict hi = &hIm[path][static_cast<size_t>(k) * bins];
      for (int b = 0; b < bins; ++b) {
        aR[b] += xr[b] * hr[b] - xi[b] * hi[b];
        aI[b] += xr[b] * hi[b] + xi[b] * hr[b];
      }
    }
  }
  fdlPos = (fdlPos + 1) % parts;
  // 3) inverse FFT, keep the last P samples (overlap-save).
  float* out[2] = {outL, outR};
  for (int o = 0; o < 2; ++o) {
    const bool any = (o == 0) ? (pathOn[0] || pathOn[2]) : (pathOn[1] || pathOn[3]);
    if (!any) {
      std::fill(out[o], out[o] + P, 0.0f);
      continue;
    }
    fft.inverse(accRe[o].data(), accIm[o].data(), outBuf.data());
    std::memcpy(out[o], outBuf.data() + P, sizeof(float) * P);
  }
}

// ---------------------------------------------------------------------------------------------
Convolver::Convolver(const IrSet& ir, double sampleRate, bool threaded) : fs_(sampleRate), threaded_(threaded) {
  irLen_ = std::max(1, ir.length());
  const int headLen = std::min(irLen_, 2 * kTailBlock);
  head_.init(ir, 0, headLen, kHeadBlock);
  hasTail_ = irLen_ > 2 * kTailBlock;
  if (hasTail_) {
    tail_.init(ir, 2 * kTailBlock, irLen_ - 2 * kTailBlock, kTailBlock);
    ringMask_ = 4 * kTailBlock - 1;
    for (int c = 0; c < 2; ++c) {
      tailIn_[c].assign(4 * kTailBlock, 0.0f);
      tailOut_[c].assign(4 * kTailBlock, 0.0f);
    }
    segInL_.assign(kTailBlock, 0.0f);
    segInR_.assign(kTailBlock, 0.0f);
    segOutL_.assign(kTailBlock, 0.0f);
    segOutR_.assign(kTailBlock, 0.0f);
  }
  for (int c = 0; c < 2; ++c) {
    fifoIn_[c].assign(kHeadBlock, 0.0f);
    fifoOut_[c].assign(kHeadBlock, 0.0f);
    headOut_[c].assign(kHeadBlock, 0.0f);
  }
  if (hasTail_ && threaded_) worker_ = std::thread([this] { workerLoop(); });
}

Convolver::~Convolver() {
  quit_.store(true);
  if (worker_.joinable()) worker_.join();
}

void Convolver::workerLoop() {
  const auto sleep = std::chrono::milliseconds(
      std::max(1, static_cast<int>(1000.0 * kTailBlock / fs_ / 8.0)));
  while (!quit_.load(std::memory_order_acquire)) {
    computeTailSegments(true);
    std::this_thread::sleep_for(sleep);
  }
}

void Convolver::computeTailSegments(bool /*fromWorker*/) {
  const uint64_t avail = inputCount_.load(std::memory_order_acquire);
  const int P = kTailBlock;
  while ((tailNext_ + 1) * static_cast<uint64_t>(P) <= avail) {
    const uint64_t start = tailNext_ * P;
    for (int i = 0; i < P; ++i) {
      const size_t idx = static_cast<size_t>((start + i) & ringMask_);
      segInL_[i] = tailIn_[0][idx];
      segInR_[i] = tailIn_[1][idx];
    }
    tail_.processSegment(segInL_.data(), segInR_.data(), segOutL_.data(), segOutR_.data());
    for (int i = 0; i < P; ++i) {
      const size_t idx = static_cast<size_t>((start + i) & ringMask_);
      tailOut_[0][idx] = segOutL_[i];
      tailOut_[1][idx] = segOutR_[i];
    }
    ++tailNext_;
    tailReady_.store(tailNext_, std::memory_order_release);
    if (quit_.load(std::memory_order_relaxed)) break;
  }
}

void Convolver::processHeadBlock() {
  const int B = kHeadBlock;
  head_.processSegment(fifoIn_[0].data(), fifoIn_[1].data(), headOut_[0].data(), headOut_[1].data());
  if (hasTail_) {
    const uint64_t base = inputCount_.load(std::memory_order_relaxed);
    for (int i = 0; i < B; ++i) {
      const size_t idx = static_cast<size_t>((base + i) & ringMask_);
      tailIn_[0][idx] = fifoIn_[0][i];
      tailIn_[1][idx] = fifoIn_[1][i];
    }
    inputCount_.store(base + B, std::memory_order_release);
    if (!threaded_) computeTailSegments(false);

    // Tail contribution for output samples [outputIndex_, outputIndex_ + B).
    const uint64_t S = 2 * kTailBlock;
    if (outputIndex_ >= S) {
      const uint64_t u = outputIndex_ - S;
      const uint64_t seg = u / kTailBlock;
      if (tailReady_.load(std::memory_order_acquire) > seg) {
        for (int i = 0; i < B; ++i) {
          const size_t idx = static_cast<size_t>((u + i) & ringMask_);
          headOut_[0][i] += tailOut_[0][idx];
          headOut_[1][i] += tailOut_[1][idx];
        }
      } else {
        underruns_.fetch_add(1, std::memory_order_relaxed);
      }
    }
  }
  outputIndex_ += B;
  std::memcpy(fifoOut_[0].data(), headOut_[0].data(), sizeof(float) * B);
  std::memcpy(fifoOut_[1].data(), headOut_[1].data(), sizeof(float) * B);
}

void Convolver::process(const float* inL, const float* inR, float* outL, float* outR, int n) {
  int i = 0;
  while (i < n) {
    const int m = std::min(n - i, kHeadBlock - fifoPos_);
    for (int k = 0; k < m; ++k) {
      const float l = inL[i + k], r = inR[i + k];
      outL[i + k] = fifoOut_[0][fifoPos_ + k];
      outR[i + k] = fifoOut_[1][fifoPos_ + k];
      fifoIn_[0][fifoPos_ + k] = l;
      fifoIn_[1][fifoPos_ + k] = r;
    }
    fifoPos_ += m;
    i += m;
    if (fifoPos_ == kHeadBlock) {
      processHeadBlock();
      fifoPos_ = 0;
    }
  }
}

}  // namespace carro
