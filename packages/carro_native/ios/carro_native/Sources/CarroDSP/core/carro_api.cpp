// C ABI wrappers around carro::Engine (see carro_api.h for the threading contract).
#include "carro_api.h"

#include <cstring>
#include <string>

#include "dsp/analysis.h"
#include "dsp/engine.h"
#include "dsp/wav.h"

using carro::Engine;

namespace {
constexpr int kScratch = 512;
}

CARRO_API const char* carro_version(void) { return "CarroDSP 1.0.0"; }

CARRO_API void carro_prepare(double sampleRate, int maxBlockFrames) {
  Engine::instance().prepare(sampleRate, maxBlockFrames);
}

CARRO_API double carro_sample_rate(void) { return Engine::instance().sampleRate(); }

CARRO_API void carro_process_planar(float* left, float* right, int frames) {
  if (!left || frames <= 0) return;
  if (!right) {  // mono: process as dual mono, sum back
    float l[kScratch], r[kScratch];
    for (int off = 0; off < frames; off += kScratch) {
      const int m = frames - off < kScratch ? frames - off : kScratch;
      std::memcpy(l, left + off, sizeof(float) * m);
      std::memcpy(r, left + off, sizeof(float) * m);
      Engine::instance().process(l, r, m);
      for (int i = 0; i < m; ++i) left[off + i] = 0.5f * (l[i] + r[i]);
    }
    return;
  }
  Engine::instance().process(left, right, frames);
}

CARRO_API void carro_process_interleaved(float* data, int frames, int channels) {
  if (!data || frames <= 0 || channels <= 0) return;
  float l[kScratch], r[kScratch];
  for (int off = 0; off < frames; off += kScratch) {
    const int m = frames - off < kScratch ? frames - off : kScratch;
    float* base = data + static_cast<size_t>(off) * channels;
    for (int i = 0; i < m; ++i) {
      l[i] = base[i * channels];
      r[i] = channels > 1 ? base[i * channels + 1] : l[i];
    }
    Engine::instance().process(l, r, m);
    for (int i = 0; i < m; ++i) {
      if (channels > 1) {
        base[i * channels] = l[i];
        base[i * channels + 1] = r[i];
      } else {
        base[i] = 0.5f * (l[i] + r[i]);
      }
    }
  }
}

CARRO_API void carro_process_int16(int16_t* data, int frames, int channels) {
  if (!data || frames <= 0 || channels <= 0) return;
  float l[kScratch], r[kScratch];
  const float in = 1.0f / 32768.0f;
  for (int off = 0; off < frames; off += kScratch) {
    const int m = frames - off < kScratch ? frames - off : kScratch;
    int16_t* base = data + static_cast<size_t>(off) * channels;
    for (int i = 0; i < m; ++i) {
      l[i] = base[i * channels] * in;
      r[i] = channels > 1 ? base[i * channels + 1] * in : l[i];
    }
    Engine::instance().process(l, r, m);
    auto toI16 = [](float v) {
      float s = v * 32767.0f;
      s = s > 32767.0f ? 32767.0f : (s < -32768.0f ? -32768.0f : s);
      return static_cast<int16_t>(s >= 0 ? s + 0.5f : s - 0.5f);
    };
    for (int i = 0; i < m; ++i) {
      if (channels > 1) {
        base[i * channels] = toI16(l[i]);
        base[i * channels + 1] = toI16(r[i]);
      } else {
        base[i] = toI16(0.5f * (l[i] + r[i]));
      }
    }
  }
}

CARRO_API void carro_reset(void) { Engine::instance().requestReset(); }

CARRO_API void carro_set_param(int id, int index, float value) { Engine::instance().setParam(id, index, value); }
CARRO_API float carro_get_param(int id, int index) { return Engine::instance().getParam(id, index); }
CARRO_API void carro_begin_batch(void) { Engine::instance().beginBatch(); }
CARRO_API void carro_end_batch(void) { Engine::instance().endBatch(); }

CARRO_API int carro_load_ir_file(const char* path) {
  if (!path || !*path) return CARRO_ERR_ARGS;
  return Engine::instance().loadIrFile(path);
}
CARRO_API void carro_clear_ir(void) { Engine::instance().clearIr(); }
CARRO_API void carro_ir_info(float* out4) {
  if (out4) Engine::instance().irInfo(out4);
}

CARRO_API int carro_get_spectrum(float* outDb, int bands) { return Engine::instance().getSpectrum(outDb, bands); }
CARRO_API void carro_get_meters(float* out6) {
  if (out6) Engine::instance().getMeters(out6);
}
CARRO_API int carro_get_decay_curve(float* outDb, int points, float* outInfo2) {
  if (!outDb) return 0;
  return Engine::instance().getDecayCurve(outDb, points, outInfo2);
}
CARRO_API int carro_get_response(int curve, const float* freqsHz, float* outDb, int n) {
  return Engine::instance().getResponse(curve, freqsHz, outDb, n);
}

CARRO_API int carro_sweep_generate(float* out, int frames, double sampleRate, double f1, double f2, float amplitude) {
  if (!out || frames <= 0 || sampleRate <= 0 || f1 <= 0 || f2 <= f1) return CARRO_ERR_ARGS;
  carro::generateSweep(out, frames, sampleRate, f1, f2, amplitude);
  return frames;
}

CARRO_API int carro_ir_build_from_captures(const char* recLeftWav, const char* recRightWav, const char* outWav,
                                           double sweepSampleRate, double f1, double f2, double sweepSeconds,
                                           double maxIrSeconds) {
  if (!recLeftWav || !outWav) return CARRO_ERR_ARGS;
  return carro::buildIrFromCaptures(recLeftWav, recRightWav ? recRightWav : "", outWav, sweepSampleRate, f1, f2,
                                    sweepSeconds, maxIrSeconds);
}

CARRO_API int carro_wav_write(const char* path, const float* interleaved, int frames, int channels, int sampleRate) {
  if (!path) return CARRO_ERR_ARGS;
  return carro::writeWavFloat(path, interleaved, frames, channels, sampleRate);
}

CARRO_API int carro_measure_rt60(const float* ir, int frames, double sampleRate, float* outRt60) {
  if (!ir || frames <= 0 || !outRt60) return CARRO_ERR_ARGS;
  *outRt60 = carro::measureRt60(ir, frames, sampleRate);
  return CARRO_OK;
}
