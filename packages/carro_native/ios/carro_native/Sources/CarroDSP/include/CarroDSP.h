// Objective-C face of the Carro C++ DSP for the Swift side of the plugin.
// The C++ engine itself is compiled from ../../../../src via carro_dsp_all.cpp.
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CarroAudioBridge : NSObject

/// Engine version string (also forces the C++ object file to be linked).
+ (NSString *)engineVersion;

/// Prepares the engine outside of playback (e.g. before the first track).
+ (void)prepareWithSampleRate:(double)sampleRate maxFrames:(int)maxFrames;

/// Builds an audio mix whose MTAudioProcessingTap runs every sample of `track` through the
/// Carrozzeria DSP chain (works for progressive / file / composition items, not HLS).
+ (nullable AVAudioMix *)audioMixForTrack:(AVAssetTrack *)track;

/// Exponential sine sweep (float32 mono) for IR capture.
+ (NSData *)sweepWithFrames:(int)frames
                 sampleRate:(double)sampleRate
                         f1:(double)f1
                         f2:(double)f2
                  amplitude:(float)amplitude;

/// Writes interleaved float32 samples as a 32-bit float WAV.
+ (BOOL)writeWavAtPath:(NSString *)path
                samples:(NSData *)interleavedFloat32
               channels:(int)channels
             sampleRate:(int)sampleRate;

@end

NS_ASSUME_NONNULL_END
