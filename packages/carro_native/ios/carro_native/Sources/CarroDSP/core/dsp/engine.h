// The Carro engine: fixed Carrozzeria signal chain
//
//   Input -> SLA -> ASR -> GEQ -> Loudness/Bass Boost -> SOUND FIELD -> Crossover ->
//   Level/Phase -> Time Alignment -> Fader/Balance -> Limiter -> Output
//
// Control side (any thread, serialised by a mutex that the audio thread never touches)
// edits a master EngineParams and publishes snapshots through a lock-free triple buffer.
// Heavy objects (convolvers) are built on the control thread and handed over with atomic
// pointer exchange; the audio thread never allocates, frees or locks.
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "analysis.h"
#include "asr.h"
#include "convolver.h"
#include "eq.h"
#include "limiter.h"
#include "params.h"
#include "reverb_algo.h"
#include "speakers.h"
#include "wav.h"

namespace carro {

class Engine {
 public:
  static Engine& instance();
  Engine();
  ~Engine();

  // ---- audio side ----
  void prepare(double sampleRate, int maxBlock);
  double sampleRate() const { return fsAtomic_.load(std::memory_order_acquire); }
  void process(float* L, float* R, int n);

  // ---- control side ----
  void setParam(int id, int index, float value);
  float getParam(int id, int index);
  void beginBatch();
  void endBatch();
  void requestReset();
  int loadIrFile(const std::string& path);
  void clearIr();
  void irInfo(float* out4);
  int getSpectrum(float* outDb, int bands);
  void getMeters(float* out6);
  int getDecayCurve(float* outDb, int points, float* info2);
  int getResponse(int curve, const float* freqs, float* outDb, int n);

  // Test hook: build convolvers without a worker thread (deterministic offline rendering).
  void setSynchronousConvolver(bool sync) { syncConv_ = sync; }
  int latencySamples() const { return latency_; }

 private:
  // ---------------- control ----------------
  void commitLocked();
  void recalibrateAlgoLocked();
  void rebuildConvolverLocked();
  void collectRetiredLocked();
  double controlRate() const;
  bool setParamLocked(int id, int index, float value, bool& sfDirty, bool& irDirty);

  std::mutex ctrl_;
  EngineParams master_;
  TripleBuffer<EngineParams> params_;
  int batchDepth_ = 0;
  bool pendingSf_ = false, pendingIr_ = false;

  struct IrSource {
    bool loaded = false;
    std::string path;
    WavData wav;
  } irSrc_;
  float irLengthSec_ = 0.0f;
  std::vector<float> algoCurve_, convCurve_;
  float algoCurveSec_ = 0.0f, algoRt60_ = 0.0f, convCurveSec_ = 0.0f, convRt60_ = 0.0f;
  RealFFT analyzerFft_;
  std::vector<float> analyzerBuf_;
  bool syncConv_ = false;

  // Convolver hand-off.
  std::atomic<Convolver*> pendingConv_{nullptr};
  std::atomic<uint32_t> convGen_{0};
  std::atomic<Convolver*> retiredConv_{nullptr};

  // ---------------- audio ----------------
  void applySmooth(const EngineParams& p);
  void applyStructural(const EngineParams& p);
  void resetStates();
  void processChunk(float* L, float* R, int n);
  void processSoundField(float* L, float* R, int n);
  static bool structural(const EngineParams& a, const EngineParams& b);
  void updateSoundFieldTargets(const EngineParams& p);

  std::atomic<bool> prepared_{false};
  std::atomic<double> fsAtomic_{0.0};
  double fs_ = 48000.0;
  EngineParams active_, pending_;
  bool hasPending_ = false;
  bool firstParams_ = true;

  // stages
  Smoother inGain_;
  Asr asr_;
  GraphicEq geq_;
  ToneStage tone_;
  AlgoReverb algo_;
  Convolver* conv_ = nullptr;
  uint32_t convGenSeen_ = 0;
  SpeakerMatrix speakers_;
  TruePeakLimiter limiter_;
  SpectrumTap tap_;

  // sound field
  ReverbDesign sfDesign_;
  bool sfDesignValid_ = false;
  int sfKeyMode_ = -1, sfKeySize_ = -1, sfKeyEngine_ = -1;
  float sfKeyWidth_ = -1.0f;
  SfModeParams sfKeyTable_{};
  enum class WetFade { Idle, Out, In } wetFade_ = WetFade::Idle;
  float wetFadeGain_ = 1.0f, wetFadeStep_ = 0.001f;
  bool wetChangePending_ = false;
  Smoother sfDry_, sfWetAlgo_, sfWetConv_;
  std::vector<float> dryDelayL_, dryDelayR_;
  int dryPos_ = 0;
  std::vector<float> dlyL_, dlyR_, wetL_, wetR_, wet2L_, wet2R_;
  std::atomic<uint32_t> convUnderruns_{0};
  std::mutex anaMu_;

  // structural fade & bypass
  enum class Fade { None, Out, In } fade_ = Fade::None;
  float fadeGain_ = 1.0f, fadeStep_ = 0.001f;
  Smoother bypassMix_;
  std::vector<float> byDelayL_, byDelayR_;
  int byPos_ = 0;
  int latency_ = 0;
  std::vector<float> dryInL_, dryInR_;

  // meters
  std::atomic<float> peakL_{0.0f}, peakR_{0.0f}, grDb_{0.0f}, cpu_{0.0f};
  float cpuSmooth_ = 0.0f;
};

}  // namespace carro
