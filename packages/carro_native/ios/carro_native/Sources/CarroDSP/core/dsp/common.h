// Shared helpers for the Carro DSP core: constants, dB math, denormal protection,
// parameter smoothing and a lock-free triple buffer for control -> audio hand-off.
#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>

#if defined(__SSE__) || defined(_M_X64) || defined(__x86_64__) || defined(_M_IX86)
#include <xmmintrin.h>
#define CARRO_X86 1
#endif

namespace carro {

constexpr double kPi = 3.14159265358979323846;
constexpr float kPiF = 3.14159265358979323846f;
constexpr float kSpeedOfSoundCmPerSec = 34300.0f;
// Internal chunk size. process() splits larger host buffers into chunks of this size.
constexpr int kChunk = 512;

inline float dbToGain(float db) { return std::pow(10.0f, db * 0.05f); }
inline float gainToDb(float g) { return 20.0f * std::log10(std::max(g, 1e-12f)); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

// Enables flush-to-zero / denormals-are-zero for the lifetime of the object. Created at the
// top of every audio callback, so filter and reverb tails never fall into the slow denormal
// range. Feedback loops additionally use kAntiDenormal as a belt-and-braces offset.
struct DenormalGuard {
#if defined(CARRO_X86)
  unsigned int old;
  DenormalGuard() : old(_mm_getcsr()) { _mm_setcsr(old | 0x8040u); }  // FTZ | DAZ
  ~DenormalGuard() { _mm_setcsr(old); }
#elif defined(__aarch64__)
  uint64_t old;
  DenormalGuard() {
    uint64_t v;
    __asm__ __volatile__("mrs %0, fpcr" : "=r"(v));
    old = v;
    v |= (1ull << 24);  // FZ
    __asm__ __volatile__("msr fpcr, %0" : : "r"(v));
  }
  ~DenormalGuard() { __asm__ __volatile__("msr fpcr, %0" : : "r"(old)); }
#elif defined(__arm__) && defined(__ARM_FP)
  uint32_t old;
  DenormalGuard() {
    uint32_t v;
    __asm__ __volatile__("vmrs %0, fpscr" : "=r"(v));
    old = v;
    v |= (1u << 24);  // FZ
    __asm__ __volatile__("vmsr fpscr, %0" : : "r"(v));
  }
  ~DenormalGuard() { __asm__ __volatile__("vmsr fpscr, %0" : : "r"(old)); }
#else
  DenormalGuard() {}
#endif
  DenormalGuard(const DenormalGuard&) = delete;
  DenormalGuard& operator=(const DenormalGuard&) = delete;
};

constexpr float kAntiDenormal = 1e-20f;

// One-pole exponential smoother (per-sample). Time constant ~= `ms`.
class Smoother {
 public:
  void setTime(float ms, double fs) {
    const double n = std::max(1.0, ms * 0.001 * fs);
    coef_ = static_cast<float>(1.0 - std::exp(-1.0 / n));
  }
  void setTarget(float t) { target_ = t; }
  void snap(float v) { cur_ = target_ = v; }
  float target() const { return target_; }
  float current() const { return cur_; }
  bool settled() const { return cur_ == target_; }
  inline float next() {
    cur_ += coef_ * (target_ - cur_);
    if (std::fabs(target_ - cur_) < 1e-6f) cur_ = target_;
    return cur_;
  }
  // Advance by `n` samples at once (used for per-block coefficient smoothing).
  inline float advance(int n) {
    const float k = 1.0f - std::pow(1.0f - coef_, static_cast<float>(n));
    cur_ += k * (target_ - cur_);
    if (std::fabs(target_ - cur_) < 1e-4f * std::max(1.0f, std::fabs(target_))) cur_ = target_;
    return cur_;
  }

 private:
  float cur_ = 0.0f, target_ = 0.0f, coef_ = 0.01f;
};

// Lock-free triple buffer: one writer thread publishes complete snapshots, the audio thread
// picks up the newest one. Neither side ever blocks.
template <typename T>
class TripleBuffer {
 public:
  TripleBuffer() : middle_(1), back_(2), front_(0) {}
  // Writer side.
  T& back() { return buf_[back_]; }
  void publish() { back_ = middle_.exchange(back_ | kDirty, std::memory_order_acq_rel) & kMask; }
  // Reader side. Returns true when a newer snapshot became the front buffer.
  bool update() {
    if ((middle_.load(std::memory_order_acquire) & kDirty) == 0) return false;
    front_ = middle_.exchange(front_, std::memory_order_acq_rel) & kMask;
    return true;
  }
  const T& front() const { return buf_[front_]; }

 private:
  static constexpr int kDirty = 4;
  static constexpr int kMask = 3;
  T buf_[3];
  std::atomic<int> middle_;
  int back_;
  int front_;
};

// Simple float atomic max helper for meters.
inline void atomicMax(std::atomic<float>& a, float v) {
  float prev = a.load(std::memory_order_relaxed);
  while (prev < v && !a.compare_exchange_weak(prev, v, std::memory_order_relaxed)) {
  }
}

}  // namespace carro
