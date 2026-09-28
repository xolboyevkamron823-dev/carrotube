#import "CarroDSP.h"

#import <MediaToolbox/MediaToolbox.h>

#include <atomic>
#include <cstdlib>

#include "core/carro_api.h"

// Per-tap context. Allocated when the mix is built, freed in the tap's finalize callback.
struct CarroTapContext {
  double sampleRate = 0;
  UInt32 channels = 0;
  bool isFloat = false;
  bool nonInterleaved = false;
  std::atomic<bool> prepared{false};
};

static void CarroTapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
  *tapStorageOut = clientInfo;
}

static void CarroTapFinalize(MTAudioProcessingTapRef tap) {
  auto *ctx = static_cast<CarroTapContext *>(MTAudioProcessingTapGetStorage(tap));
  delete ctx;
}

static void CarroTapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames,
                            const AudioStreamBasicDescription *format) {
  auto *ctx = static_cast<CarroTapContext *>(MTAudioProcessingTapGetStorage(tap));
  ctx->sampleRate = format->mSampleRate;
  ctx->channels = format->mChannelsPerFrame;
  ctx->isFloat = (format->mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format->mBitsPerChannel == 32;
  ctx->nonInterleaved = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  // Allocation happens here (tap prepare runs outside the render callback).
  carro_prepare(format->mSampleRate, static_cast<int>(maxFrames));
  ctx->prepared.store(true);
}

static void CarroTapUnprepare(MTAudioProcessingTapRef tap) {
  auto *ctx = static_cast<CarroTapContext *>(MTAudioProcessingTapGetStorage(tap));
  ctx->prepared.store(false);
}

static void CarroTapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags,
                            AudioBufferList *bufferList, CMItemCount *numberFramesOut,
                            MTAudioProcessingTapFlags *flagsOut) {
  OSStatus st = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, NULL, numberFramesOut);
  if (st != noErr) return;
  auto *ctx = static_cast<CarroTapContext *>(MTAudioProcessingTapGetStorage(tap));
  if (!ctx->prepared.load(std::memory_order_relaxed) || !ctx->isFloat) return;
  const int frames = static_cast<int>(*numberFramesOut);
  if (frames <= 0) return;

  if (ctx->nonInterleaved) {
    if (bufferList->mNumberBuffers >= 2) {
      float *l = static_cast<float *>(bufferList->mBuffers[0].mData);
      float *r = static_cast<float *>(bufferList->mBuffers[1].mData);
      if (l && r) carro_process_planar(l, r, frames);
    } else if (bufferList->mNumberBuffers == 1) {
      float *m = static_cast<float *>(bufferList->mBuffers[0].mData);
      if (m) carro_process_planar(m, nullptr, frames);
    }
  } else if (bufferList->mNumberBuffers >= 1) {
    float *d = static_cast<float *>(bufferList->mBuffers[0].mData);
    const int ch = static_cast<int>(bufferList->mBuffers[0].mNumberChannels);
    if (d && ch > 0) carro_process_interleaved(d, frames, ch);
  }
}

@implementation CarroAudioBridge

+ (NSString *)engineVersion {
  return [NSString stringWithUTF8String:carro_version()];
}

+ (void)prepareWithSampleRate:(double)sampleRate maxFrames:(int)maxFrames {
  carro_prepare(sampleRate, maxFrames);
}

+ (nullable AVAudioMix *)audioMixForTrack:(AVAssetTrack *)track {
  auto *ctx = new CarroTapContext();
  MTAudioProcessingTapCallbacks callbacks;
  callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
  callbacks.clientInfo = ctx;
  callbacks.init = CarroTapInit;
  callbacks.finalize = CarroTapFinalize;
  callbacks.prepare = CarroTapPrepare;
  callbacks.unprepare = CarroTapUnprepare;
  callbacks.process = CarroTapProcess;

  MTAudioProcessingTapRef tap = NULL;
  OSStatus st = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects,
                                           &tap);
  if (st != noErr || tap == NULL) {
    delete ctx;
    return nil;
  }
  AVMutableAudioMixInputParameters *params = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
  params.audioTapProcessor = tap;
  CFRelease(tap);  // the input parameters keep their own reference
  AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
  mix.inputParameters = @[ params ];
  return mix;
}

+ (NSData *)sweepWithFrames:(int)frames sampleRate:(double)sampleRate f1:(double)f1 f2:(double)f2 amplitude:(float)amplitude {
  NSMutableData *data = [NSMutableData dataWithLength:sizeof(float) * (NSUInteger)MAX(frames, 0)];
  if (frames > 0) carro_sweep_generate(static_cast<float *>(data.mutableBytes), frames, sampleRate, f1, f2, amplitude);
  return data;
}

+ (BOOL)writeWavAtPath:(NSString *)path samples:(NSData *)interleavedFloat32 channels:(int)channels sampleRate:(int)sampleRate {
  if (channels <= 0) return NO;
  const int frames = static_cast<int>(interleavedFloat32.length / sizeof(float) / channels);
  return carro_wav_write(path.fileSystemRepresentation, static_cast<const float *>(interleavedFloat32.bytes), frames,
                         channels, sampleRate) == CARRO_OK;
}

@end
