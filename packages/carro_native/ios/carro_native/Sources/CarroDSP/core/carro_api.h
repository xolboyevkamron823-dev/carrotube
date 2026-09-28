/*
 * CarroTube DSP - public C ABI.
 *
 * One process-wide engine instance shared by:
 *   - the native player (iOS MTAudioProcessingTap / Android ExoPlayer AudioProcessor),
 *     which calls carro_prepare() + carro_process_*() on its audio thread;
 *   - Dart (dart:ffi), which calls the carro_set_param()/carro_get_*() control functions.
 *
 * Threading contract
 *   - carro_process_*          : real-time audio thread only. Never locks, never allocates.
 *   - carro_prepare            : must not run concurrently with carro_process_* (the players
 *                                call it from their own pipeline before processing starts).
 *   - everything else          : any non-audio thread. Control calls are serialised internally.
 */
#ifndef CARRO_API_H
#define CARRO_API_H

#include <stdint.h>

#if defined(_WIN32)
#define CARRO_EXPORT __declspec(dllexport)
#else
/* "used" keeps the symbol from being dead-stripped so dart:ffi can always find it. */
#define CARRO_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
#define CARRO_API extern "C" CARRO_EXPORT
#else
#define CARRO_API CARRO_EXPORT
#endif

/* ------------------------------------------------------------------------------------------ */
/* Parameter ids. `index` meaning is given per id; unused index = 0.                           */
/* Keep in sync with lib/src/dsp_params.dart.                                                   */
/* ------------------------------------------------------------------------------------------ */
enum CarroParamId {
  /* global */
  CARRO_P_BYPASS = 0,          /* 0/1  instant A/B (crossfaded)                                  */
  CARRO_P_SLA_DB = 1,          /* -4..+4 dB, 1 dB step (Source Level Adjuster)                   */
  CARRO_P_PREAMP_DB = 2,       /* -12..+6 dB extra trim before the limiter                       */
  CARRO_P_AUTO_HEADROOM = 3,   /* 0/1  subtract half of the largest boost at the input          */

  /* Advanced Sound Retriever */
  CARRO_P_ASR_MODE = 10,       /* 0 OFF, 1 MODE1, 2 MODE2                                        */

  /* Graphic EQ */
  CARRO_P_EQ_MODE = 20,        /* 0 = 13-band, 1 = 31-band 1/3-octave (Pro)                      */
  CARRO_P_EQ_BAND = 21,        /* index = channel*32 + band (channel 0 = L, 1 = R), -12..+12 dB  */

  /* Loudness / Bass Boost */
  CARRO_P_LOUDNESS = 30,       /* 0 OFF, 1 LOW, 2 MID, 3 HIGH                                    */
  CARRO_P_BASS_BOOST = 31,     /* 0..6                                                           */

  /* Sound Field */
  CARRO_P_SF_ENGINE = 40,      /* 0 algorithmic, 1 convolution                                   */
  CARRO_P_SF_MODE = 41,        /* 0 OFF,1 STUDIO,2 JAZZ CLUB,3 CONCERT HALL,4 CATHEDRAL,
                                  5 STADIUM,6 LIVE,7 DOME                                        */
  CARRO_P_SF_LEVEL = 42,       /* 0..10                                                          */
  CARRO_P_SF_SIZE = 43,        /* 0 S, 1 M, 2 L                                                  */
  CARRO_P_SF_WIDTH = 44,       /* 0..2 global wet stereo width multiplier (1 = table value)      */
  CARRO_P_SF_DRYWET = 45,      /* 0..1 convolution dry/wet                                       */
  CARRO_P_SF_CONV_PREDELAY_MS = 46, /* 0..100 ms extra pre-delay for the IR                      */
  CARRO_P_SF_LOUDNESS_MATCH = 47,   /* 0/1                                                       */
  CARRO_P_SF_IR_TRIM_START_MS = 48, /* 0..500 ms cut from the IR start                           */
  CARRO_P_SF_IR_TRIM_END_MS = 49,   /* 0..6000 ms, 0 = keep full length                          */

  /* Sound Field per-mode table, index = mode (1..7). Values from sound_fields.json. */
  CARRO_P_SFT_PREDELAY_MS = 60,
  CARRO_P_SFT_RT60 = 61,       /* seconds, mid band                                              */
  CARRO_P_SFT_LOW_MULT = 62,   /* RT60 multiplier below ~250 Hz                                  */
  CARRO_P_SFT_DAMP_HZ = 63,    /* HF damping corner                                              */
  CARRO_P_SFT_ER_LEVEL_DB = 64,
  CARRO_P_SFT_LATE_LEVEL_DB = 65,
  CARRO_P_SFT_DENSITY = 66,    /* 0..1 diffusion                                                 */
  CARRO_P_SFT_WIDTH = 67,      /* 0..1.5                                                         */
  CARRO_P_SFT_ROOM_W = 68,     /* metres                                                         */
  CARRO_P_SFT_ROOM_L = 69,
  CARRO_P_SFT_ROOM_H = 70,
  CARRO_P_SFT_WET_HPF_HZ = 71,
  CARRO_P_SFT_MOD_DEPTH_MS = 72,
  CARRO_P_SFT_MOD_RATE_HZ = 73,
  CARRO_P_SFT_WET_LPF_HZ = 74,

  /* Crossover / channel, index = group: 0 FRONT, 1 REAR, 2 SUB, 3 HIGH, 4 MID */
  CARRO_P_XO_NETWORK = 80,     /* 0 Standard, 1 Network 3-way                                    */
  CARRO_P_XO_HPF_ON = 81,
  CARRO_P_XO_HPF_HZ = 82,
  CARRO_P_XO_HPF_SLOPE = 83,   /* 6,12,18,24,30,36 dB/oct                                        */
  CARRO_P_XO_LPF_ON = 84,
  CARRO_P_XO_LPF_HZ = 85,
  CARRO_P_XO_LPF_SLOPE = 86,
  CARRO_P_XO_TYPE = 87,        /* 0 Butterworth, 1 Linkwitz-Riley (even slopes only)             */
  CARRO_P_CH_LEVEL_DB = 88,    /* -24..+10                                                       */
  CARRO_P_CH_PHASE = 89,       /* 0 normal, 1 reverse                                            */
  CARRO_P_CH_MUTE = 90,
  CARRO_P_SUB_ON = 91,

  /* Time alignment, index = speaker slot: 0 FL/HL, 1 FR/HR, 2 RL/ML, 3 RR/MR, 4 SUB */
  CARRO_P_TA_ON = 100,
  CARRO_P_TA_DIST_CM = 101,    /* 0..350 cm, 2.5 cm step                                         */

  /* Position / balance / output */
  CARRO_P_SCC = 110,           /* Sonic Center Control -15 (L) .. +15 (R)                        */
  CARRO_P_FADER = 111,         /* -15 rear .. +15 front                                          */
  CARRO_P_BALANCE = 112,       /* -15 left .. +15 right                                          */
  CARRO_P_OUTPUT_MODE = 113,   /* 0 car speakers (virtual downmix), 1 headphones (crossfeed)     */
  CARRO_P_CROSSFEED = 114,     /* 0..1                                                           */

  /* Limiter */
  CARRO_P_LIMITER_ON = 120,
  CARRO_P_LIMITER_CEIL_DB = 121 /* -6..0 dBTP                                                    */
};

/* Curves for carro_get_response(). */
enum CarroCurve {
  CARRO_CURVE_EQ_L = 0,
  CARRO_CURVE_EQ_R = 1,
  CARRO_CURVE_TONE = 2,         /* loudness + bass boost                                         */
  CARRO_CURVE_GROUP_BASE = 10   /* + group (0..4): crossover filter incl. level                  */
};

/* Error codes. */
#define CARRO_OK 0
#define CARRO_ERR_IO -1
#define CARRO_ERR_FORMAT -2
#define CARRO_ERR_ARGS -3
#define CARRO_ERR_SIGNAL -4

/* ---- lifecycle / audio thread -------------------------------------------------------------- */
CARRO_API const char* carro_version(void);
CARRO_API void carro_prepare(double sampleRate, int maxBlockFrames);
CARRO_API double carro_sample_rate(void);
CARRO_API void carro_process_planar(float* left, float* right, int frames);
/* Interleaved float, 1 or 2 channels (mono is processed as dual-mono and summed back). */
CARRO_API void carro_process_interleaved(float* data, int frames, int channels);
CARRO_API void carro_process_int16(int16_t* data, int frames, int channels);
/* Clears filter/reverb memories on the next audio block (e.g. after a seek). */
CARRO_API void carro_reset(void);

/* ---- parameters ----------------------------------------------------------------------------- */
CARRO_API void carro_set_param(int id, int index, float value);
CARRO_API float carro_get_param(int id, int index);
/* Group many set_param calls into one atomic update (profile load). Nestable. */
CARRO_API void carro_begin_batch(void);
CARRO_API void carro_end_batch(void);

/* ---- convolution IR ------------------------------------------------------------------------- */
/* WAV 16/24/32-bit int or 32/64-bit float, 1 ch (mono), 2 ch (L/R) or 4 ch (LL, LR, RL, RR). */
CARRO_API int carro_load_ir_file(const char* path);
CARRO_API void carro_clear_ir(void);
/* out[4] = { loaded(0/1), channels, sampleRate, lengthSeconds } */
CARRO_API void carro_ir_info(float* out4);

/* ---- analysis for the UI -------------------------------------------------------------------- */
/* Log-spaced 20 Hz..20 kHz bands of the output, dBFS. Returns number of bands written. */
CARRO_API int carro_get_spectrum(float* outDb, int bands);
/* out[6] = { peakL, peakR (linear, since last call), gainReductionDb, cpuLoad (0..1),
              latencyMs, convolver underruns } */
CARRO_API void carro_get_meters(float* out6);
/* Energy-decay curve of the active Sound Field (dB, 0 at t=0) sampled at `points`.
   info[2] = { durationSeconds, measuredRt60Seconds }. Returns points written (0 = no field). */
CARRO_API int carro_get_decay_curve(float* outDb, int points, float* outInfo2);
/* Magnitude response (dB) of a curve (CarroCurve) at the given frequencies. */
CARRO_API int carro_get_response(int curve, const float* freqsHz, float* outDb, int n);

/* ---- IR capture / utilities ----------------------------------------------------------------- */
/* Exponential sine sweep with 50 ms fade-in and 20 ms fade-out. */
CARRO_API int carro_sweep_generate(float* out, int frames, double sampleRate, double f1, double f2,
                                   float amplitude);
/* Deconvolves one or two recordings of the sweep into an IR WAV (32-bit float).
   recLeftWav : recording while the sweep played on the LEFT channel (or both channels).
   recRightWav: recording while the sweep played on the RIGHT channel, or NULL/"" if single.
   Output channels: stereo recordings of L and R sweeps -> 4 (LL, LR, RL, RR);
                    mono recordings of L and R sweeps   -> 2 (L, R);
                    single recording                    -> its channel count.
   Returns IR length in frames (>0) or an error code. */
CARRO_API int carro_ir_build_from_captures(const char* recLeftWav, const char* recRightWav,
                                           const char* outWav, double sweepSampleRate, double f1,
                                           double f2, double sweepSeconds, double maxIrSeconds);
CARRO_API int carro_wav_write(const char* path, const float* interleaved, int frames, int channels,
                              int sampleRate);
/* Schroeder-integration RT60 (T20 extrapolated) of a mono impulse response. */
CARRO_API int carro_measure_rt60(const float* ir, int frames, double sampleRate, float* outRt60);

#endif /* CARRO_API_H */
