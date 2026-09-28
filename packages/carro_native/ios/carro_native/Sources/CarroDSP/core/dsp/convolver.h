// True-stereo, non-uniformly partitioned FFT convolution.
//
//   head : uniform partitions of B = 256 samples covering IR[0, 2P)   (audio thread)
//   tail : uniform partitions of P = 4096 samples covering IR[2P, end) (worker thread)
//
// The tail starts at 2P so every tail segment has P samples (~85 ms) of slack between the
// moment its input is complete and the moment its first output sample is due. The worker
// therefore never has to meet a per-callback deadline and the audio thread's cost stays flat
// (no FFT spikes). Latency of the whole convolver is B samples (input FIFO). IRs up to 6 s.
//
// Paths: hLL (L->L), hLR (L->R), hRL (R->L), hRR (R->R). Empty paths are skipped.
#pragma once

#include <atomic>
#include <memory>
#include <thread>
#include <vector>

#include "fft.h"

namespace carro {

struct IrSet {
  // paths[0]=LL, [1]=LR, [2]=RL, [3]=RR ; empty vector = silent path
  std::vector<float> paths[4];
  int length() const {
    size_t m = 0;
    for (const auto& p : paths) m = std::max(m, p.size());
    return static_cast<int>(m);
  }
};

class Convolver {
 public:
  static constexpr int kHeadBlock = 256;
  static constexpr int kTailBlock = 4096;

  // Control thread. `threaded=false` computes the tail inline (offline rendering / tests).
  Convolver(const IrSet& ir, double sampleRate, bool threaded = true);
  ~Convolver();
  Convolver(const Convolver&) = delete;
  Convolver& operator=(const Convolver&) = delete;

  double sampleRate() const { return fs_; }
  int latency() const { return kHeadBlock; }
  int irLength() const { return irLen_; }
  uint32_t underruns() const { return underruns_.load(std::memory_order_relaxed); }

  // Audio thread. Arbitrary n; in/out may alias.
  void process(const float* inL, const float* inR, float* outL, float* outR, int n);

 private:
  struct Stage {
    int P = 0;           // partition size
    int parts = 0;       // number of partitions
    int bins = 0;        // P + 1
    RealFFT fft;         // size 2P
    // filter spectra [path][part][bin]
    std::vector<float> hRe[4], hIm[4];
    bool pathOn[4] = {false, false, false, false};
    // frequency-domain delay line per input channel [slot][bin]
    std::vector<float> xRe[2], xIm[2];
    int fdlPos = 0;
    std::vector<float> accRe[2], accIm[2];
    std::vector<float> timeBuf, outBuf;  // 2P scratch
    std::vector<float> prevIn[2];        // last P input samples per channel (overlap-save)
    void init(const IrSet& ir, int offset, int length, int P);
    // Consumes one P-sample input segment per channel, produces P output samples per channel.
    void processSegment(const float* inL, const float* inR, float* outL, float* outR);
  };

  void processHeadBlock();
  void computeTailSegments(bool fromWorker);
  void workerLoop();

  double fs_;
  int irLen_ = 0;
  bool threaded_;
  bool hasTail_ = false;

  Stage head_, tail_;
  // FIFO for arbitrary host block sizes.
  std::vector<float> fifoIn_[2], fifoOut_[2];
  int fifoPos_ = 0;
  std::vector<float> headOut_[2];

  // Tail rings (size 4P). Written by the audio thread (input) and the worker (output).
  std::vector<float> tailIn_[2], tailOut_[2];
  int ringMask_ = 0;
  std::atomic<uint64_t> inputCount_{0};   // samples written to tailIn_
  std::atomic<uint64_t> tailReady_{0};    // tail segments completed
  uint64_t tailNext_ = 0;                 // next segment to compute (worker)
  uint64_t outputIndex_ = 0;              // audio thread output sample index
  std::vector<float> segInL_, segInR_, segOutL_, segOutR_;
  std::atomic<uint32_t> underruns_{0};

  std::atomic<bool> quit_{false};
  std::thread worker_;
};

}  // namespace carro
