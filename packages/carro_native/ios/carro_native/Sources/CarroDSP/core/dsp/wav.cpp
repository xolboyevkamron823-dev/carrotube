#include "wav.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "../carro_api.h"
#include "common.h"

namespace carro {

namespace {

uint32_t rd32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<uint32_t>(p[3]) << 24); }
uint16_t rd16(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
void wr32(std::FILE* f, uint32_t v) {
  const uint8_t b[4] = {uint8_t(v), uint8_t(v >> 8), uint8_t(v >> 16), uint8_t(v >> 24)};
  std::fwrite(b, 1, 4, f);
}
void wr16(std::FILE* f, uint16_t v) {
  const uint8_t b[2] = {uint8_t(v), uint8_t(v >> 8)};
  std::fwrite(b, 1, 2, f);
}

double besselI0(double x) {
  double sum = 1.0, term = 1.0;
  for (int k = 1; k < 40; ++k) {
    term *= (x / (2.0 * k)) * (x / (2.0 * k));
    sum += term;
    if (term < 1e-12 * sum) break;
  }
  return sum;
}

}  // namespace

std::vector<float> WavData::channel(int c) const {
  std::vector<float> out(frames);
  for (int i = 0; i < frames; ++i) out[i] = interleaved[static_cast<size_t>(i) * channels + c];
  return out;
}

int readWav(const std::string& path, WavData& out) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return CARRO_ERR_IO;
  std::vector<uint8_t> bytes;
  {
    std::fseek(f, 0, SEEK_END);
    const long size = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    if (size <= 44) {
      std::fclose(f);
      return CARRO_ERR_FORMAT;
    }
    bytes.resize(static_cast<size_t>(size));
    const size_t got = std::fread(bytes.data(), 1, bytes.size(), f);
    std::fclose(f);
    if (got != bytes.size()) return CARRO_ERR_IO;
  }
  const uint8_t* p = bytes.data();
  if (std::memcmp(p, "RIFF", 4) != 0 || std::memcmp(p + 8, "WAVE", 4) != 0) return CARRO_ERR_FORMAT;
  size_t pos = 12;
  int format = 0, channels = 0, rate = 0, bits = 0;
  const uint8_t* data = nullptr;
  size_t dataSize = 0;
  while (pos + 8 <= bytes.size()) {
    const uint32_t id = rd32(p + pos);
    const uint32_t sz = rd32(p + pos + 4);
    const size_t body = pos + 8;
    const size_t avail = bytes.size() - body;
    if (std::memcmp(p + pos, "fmt ", 4) == 0 && sz >= 16 && avail >= 16) {
      format = rd16(p + body);
      channels = rd16(p + body + 2);
      rate = static_cast<int>(rd32(p + body + 4));
      bits = rd16(p + body + 14);
      if (format == 0xFFFE && sz >= 40 && avail >= 26) format = rd16(p + body + 24);  // sub-format GUID
    } else if (std::memcmp(p + pos, "data", 4) == 0) {
      data = p + body;
      dataSize = std::min<size_t>(sz, avail);
    }
    (void)id;
    pos = body + sz + (sz & 1);
  }
  if (!data || channels <= 0 || rate <= 0) return CARRO_ERR_FORMAT;
  const int bytesPer = bits / 8;
  if (bytesPer <= 0) return CARRO_ERR_FORMAT;
  const size_t frames = dataSize / (static_cast<size_t>(bytesPer) * channels);
  out.channels = channels;
  out.sampleRate = rate;
  out.frames = static_cast<int>(frames);
  out.interleaved.resize(frames * channels);
  const size_t total = frames * channels;
  for (size_t i = 0; i < total; ++i) {
    const uint8_t* s = data + i * bytesPer;
    float v = 0.0f;
    if (format == 1) {
      if (bits == 16) v = static_cast<int16_t>(rd16(s)) / 32768.0f;
      else if (bits == 24) {
        int32_t x = (s[0] << 8) | (s[1] << 16) | (static_cast<int32_t>(s[2]) << 24);
        v = static_cast<float>((x >> 8) / 8388608.0);
      } else if (bits == 32) v = static_cast<float>(static_cast<int32_t>(rd32(s)) / 2147483648.0);
      else if (bits == 8) v = (s[0] - 128) / 128.0f;
      else return CARRO_ERR_FORMAT;
    } else if (format == 3) {
      if (bits == 32) {
        uint32_t u = rd32(s);
        std::memcpy(&v, &u, 4);
      } else if (bits == 64) {
        uint64_t u = 0;
        for (int k = 7; k >= 0; --k) u = (u << 8) | s[k];
        double d;
        std::memcpy(&d, &u, 8);
        v = static_cast<float>(d);
      } else return CARRO_ERR_FORMAT;
    } else {
      return CARRO_ERR_FORMAT;
    }
    if (!std::isfinite(v)) v = 0.0f;
    out.interleaved[i] = v;
  }
  return CARRO_OK;
}

int writeWavFloat(const std::string& path, const float* interleaved, int frames, int channels, int sampleRate) {
  if (!interleaved || frames <= 0 || channels <= 0 || sampleRate <= 0) return CARRO_ERR_ARGS;
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) return CARRO_ERR_IO;
  const uint32_t dataBytes = static_cast<uint32_t>(frames) * channels * 4u;
  std::fwrite("RIFF", 1, 4, f);
  wr32(f, 36 + dataBytes);
  std::fwrite("WAVE", 1, 4, f);
  std::fwrite("fmt ", 1, 4, f);
  wr32(f, 16);
  wr16(f, 3);  // IEEE float
  wr16(f, static_cast<uint16_t>(channels));
  wr32(f, static_cast<uint32_t>(sampleRate));
  wr32(f, static_cast<uint32_t>(sampleRate) * channels * 4u);
  wr16(f, static_cast<uint16_t>(channels * 4));
  wr16(f, 32);
  std::fwrite("data", 1, 4, f);
  wr32(f, dataBytes);
  const size_t n = static_cast<size_t>(frames) * channels;
  const size_t written = std::fwrite(interleaved, sizeof(float), n, f);  // little-endian hosts
  std::fclose(f);
  return written == n ? CARRO_OK : CARRO_ERR_IO;
}

std::vector<float> resample(const std::vector<float>& in, double fromRate, double toRate) {
  if (in.empty() || fromRate <= 0 || toRate <= 0 || std::fabs(fromRate - toRate) < 0.5) return in;
  const double ratio = toRate / fromRate;
  const size_t outLen = static_cast<size_t>(std::ceil(in.size() * ratio));
  std::vector<float> out(outLen, 0.0f);
  const double cutoff = std::min(1.0, ratio) * 0.97;  // normalised to input Nyquist
  const int zeros = 32;
  const double halfWidth = zeros / cutoff;  // in input samples
  const double beta = 9.0;
  const double i0b = besselI0(beta);
  // Tabulated kernel (|offset| in input samples, 512 points per sample, linear interpolation).
  const int res = 512;
  const int tableLen = static_cast<int>(halfWidth * res) + 2;
  std::vector<float> table(tableLen + 1, 0.0f);
  for (int i = 0; i <= tableLen; ++i) {
    const double off = static_cast<double>(i) / res;
    const double x = off * cutoff;
    const double sinc = x < 1e-12 ? 1.0 : std::sin(kPi * x) / (kPi * x);
    const double r = off / halfWidth;
    const double w = r >= 1.0 ? 0.0 : besselI0(beta * std::sqrt(1.0 - r * r)) / i0b;
    table[i] = static_cast<float>(sinc * w * cutoff);
  }
  const long inLen = static_cast<long>(in.size());
  for (size_t n = 0; n < outLen; ++n) {
    const double t = n / ratio;  // position in input samples
    const long first = std::max(0L, static_cast<long>(std::ceil(t - halfWidth)));
    const long last = std::min(inLen - 1, static_cast<long>(std::floor(t + halfWidth)));
    double acc = 0.0;
    for (long k = first; k <= last; ++k) {
      const double pos = std::fabs(k - t) * res;
      const int idx = static_cast<int>(pos);
      if (idx >= tableLen) continue;
      const float fr = static_cast<float>(pos - idx);
      acc += in[k] * (table[idx] + fr * (table[idx + 1] - table[idx]));
    }
    out[n] = static_cast<float>(acc);
  }
  return out;
}

}  // namespace carro
