// JNI bridge between the Kotlin side (ExoPlayer AudioProcessor, IR capture) and the shared
// C++ engine. Dart reaches the same engine through dart:ffi (carro_api.h).
#include <jni.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

#include "carro_api.h"

namespace {
constexpr int kChunk = 512;

inline int16_t toI16(float v) {
  float s = v * 32767.0f;
  s = s > 32767.0f ? 32767.0f : (s < -32768.0f ? -32768.0f : s);
  return static_cast<int16_t>(s >= 0 ? s + 0.5f : s - 0.5f);
}
}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL Java_uz_carrotube_carro_1native_CarroDspJni_version(JNIEnv* env, jobject) {
  return env->NewStringUTF(carro_version());
}

JNIEXPORT void JNICALL Java_uz_carrotube_carro_1native_CarroDspJni_prepare(JNIEnv*, jobject, jdouble sampleRate,
                                                                          jint maxFrames) {
  carro_prepare(sampleRate, maxFrames);
}

// Reads `frames` of 1- or 2-channel PCM (int16 or float) from `input` (direct buffer, byte
// offset `inOffset`), runs the DSP chain and writes interleaved stereo int16 to `output`.
// Called on ExoPlayer's playback thread; no allocation.
JNIEXPORT void JNICALL Java_uz_carrotube_carro_1native_CarroDspJni_process(JNIEnv* env, jobject, jobject input,
                                                                          jint inOffset, jboolean inputIsFloat,
                                                                          jint inChannels, jint frames,
                                                                          jobject output, jint outOffset) {
  auto* inBase = static_cast<uint8_t*>(env->GetDirectBufferAddress(input));
  auto* outBase = static_cast<uint8_t*>(env->GetDirectBufferAddress(output));
  if (!inBase || !outBase || frames <= 0 || inChannels < 1 || inChannels > 2) return;
  const int16_t* in16 = reinterpret_cast<const int16_t*>(inBase + inOffset);
  const float* inF = reinterpret_cast<const float*>(inBase + inOffset);
  int16_t* out = reinterpret_cast<int16_t*>(outBase + outOffset);

  float l[kChunk], r[kChunk];
  const float scale = 1.0f / 32768.0f;
  for (int off = 0; off < frames; off += kChunk) {
    const int m = std::min(kChunk, frames - off);
    for (int i = 0; i < m; ++i) {
      const int idx = (off + i) * inChannels;
      if (inputIsFloat) {
        l[i] = inF[idx];
        r[i] = inChannels > 1 ? inF[idx + 1] : l[i];
      } else {
        l[i] = in16[idx] * scale;
        r[i] = inChannels > 1 ? in16[idx + 1] * scale : l[i];
      }
    }
    carro_process_planar(l, r, m);
    for (int i = 0; i < m; ++i) {
      out[(off + i) * 2] = toI16(l[i]);
      out[(off + i) * 2 + 1] = toI16(r[i]);
    }
  }
}

JNIEXPORT jfloatArray JNICALL Java_uz_carrotube_carro_1native_CarroDspJni_sweep(JNIEnv* env, jobject, jint frames,
                                                                               jdouble sampleRate, jdouble f1,
                                                                               jdouble f2, jfloat amplitude) {
  if (frames <= 0) return env->NewFloatArray(0);
  std::vector<float> buf(static_cast<size_t>(frames));
  carro_sweep_generate(buf.data(), frames, sampleRate, f1, f2, amplitude);
  jfloatArray arr = env->NewFloatArray(frames);
  if (arr) env->SetFloatArrayRegion(arr, 0, frames, buf.data());
  return arr;
}

JNIEXPORT jboolean JNICALL Java_uz_carrotube_carro_1native_CarroDspJni_writeWav(JNIEnv* env, jobject, jstring path,
                                                                               jfloatArray interleaved, jint channels,
                                                                               jint sampleRate) {
  if (!path || !interleaved || channels <= 0) return JNI_FALSE;
  const char* p = env->GetStringUTFChars(path, nullptr);
  const jsize n = env->GetArrayLength(interleaved);
  jfloat* data = env->GetFloatArrayElements(interleaved, nullptr);
  const int rc = carro_wav_write(p, data, n / channels, channels, sampleRate);
  env->ReleaseFloatArrayElements(interleaved, data, JNI_ABORT);
  env->ReleaseStringUTFChars(path, p);
  return rc == CARRO_OK ? JNI_TRUE : JNI_FALSE;
}

}  // extern "C"
