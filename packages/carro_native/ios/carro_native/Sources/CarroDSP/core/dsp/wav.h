// Minimal RIFF/WAVE reader & writer plus an offline windowed-sinc resampler.
// Reader: PCM 16/24/32-bit int, IEEE float 32/64, WAVE_FORMAT_EXTENSIBLE, any channel count.
#pragma once

#include <string>
#include <vector>

namespace carro {

struct WavData {
  int channels = 0;
  int sampleRate = 0;
  int frames = 0;
  std::vector<float> interleaved;
  // Returns channel `c` as its own vector.
  std::vector<float> channel(int c) const;
};

// Returns 0 on success or a CARRO_ERR_* code.
int readWav(const std::string& path, WavData& out);
int writeWavFloat(const std::string& path, const float* interleaved, int frames, int channels, int sampleRate);

// High-quality offline resampling (Kaiser-windowed sinc, 32 zero crossings).
std::vector<float> resample(const std::vector<float>& in, double fromRate, double toRate);

}  // namespace carro
