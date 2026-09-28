import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Opens the native DSP library.
/// - Android: `libcarro_dsp.so` built by the plugin's CMake project.
/// - iOS: the C++ core is linked into the app (Swift Package or CocoaPods framework),
///   so its symbols are visible process-wide.
DynamicLibrary openCarroLibrary() {
  if (Platform.isAndroid) return DynamicLibrary.open('libcarro_dsp.so');
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isWindows) return DynamicLibrary.open('carro_dsp.dll');
  return DynamicLibrary.open('libcarro_dsp.so');
}

typedef _VoidC = Void Function();
typedef _VoidD = void Function();
typedef _SetC = Void Function(Int32, Int32, Float);
typedef _SetD = void Function(int, int, double);
typedef _GetC = Float Function(Int32, Int32);
typedef _GetD = double Function(int, int);
typedef _PathC = Int32 Function(Pointer<Utf8>);
typedef _PathD = int Function(Pointer<Utf8>);
typedef _FloatsC = Void Function(Pointer<Float>);
typedef _FloatsD = void Function(Pointer<Float>);
typedef _SpecC = Int32 Function(Pointer<Float>, Int32);
typedef _SpecD = int Function(Pointer<Float>, int);
typedef _DecayC = Int32 Function(Pointer<Float>, Int32, Pointer<Float>);
typedef _DecayD = int Function(Pointer<Float>, int, Pointer<Float>);
typedef _RespC = Int32 Function(Int32, Pointer<Float>, Pointer<Float>, Int32);
typedef _RespD = int Function(int, Pointer<Float>, Pointer<Float>, int);
typedef _RateC = Double Function();
typedef _RateD = double Function();
typedef _VersionC = Pointer<Utf8> Function();
typedef _BuildC = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Double, Double, Double, Double, Double);
typedef _BuildD = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, double, double, double, double, double);
typedef _Rt60C = Int32 Function(Pointer<Float>, Int32, Double, Pointer<Float>);
typedef _Rt60D = int Function(Pointer<Float>, int, double, Pointer<Float>);

/// Live meters of the engine.
class DspMeters {
  const DspMeters(this.peakL, this.peakR, this.gainReductionDb, this.cpuLoad, this.latencyMs, this.underruns);
  final double peakL, peakR, gainReductionDb, cpuLoad, latencyMs;
  final int underruns;
  static const zero = DspMeters(0, 0, 0, 0, 0, 0);
}

class DecayCurve {
  const DecayCurve(this.db, this.durationSeconds, this.rt60);
  final Float32List db;
  final double durationSeconds;
  final double rt60;
}

class IrInfo {
  const IrInfo(this.loaded, this.channels, this.sampleRate, this.lengthSeconds);
  final bool loaded;
  final int channels;
  final int sampleRate;
  final double lengthSeconds;
}

/// Dart face of the C++ engine (dart:ffi). All calls are cheap and thread-safe on the
/// native side; heavy ones (IR load, IR build) run in a background isolate.
class CarroDsp {
  CarroDsp._(DynamicLibrary lib)
      : _setParam = lib.lookupFunction<_SetC, _SetD>('carro_set_param', isLeaf: true),
        _getParam = lib.lookupFunction<_GetC, _GetD>('carro_get_param', isLeaf: true),
        _begin = lib.lookupFunction<_VoidC, _VoidD>('carro_begin_batch', isLeaf: true),
        _end = lib.lookupFunction<_VoidC, _VoidD>('carro_end_batch'),
        _reset = lib.lookupFunction<_VoidC, _VoidD>('carro_reset', isLeaf: true),
        _clearIr = lib.lookupFunction<_VoidC, _VoidD>('carro_clear_ir'),
        _irInfo = lib.lookupFunction<_FloatsC, _FloatsD>('carro_ir_info', isLeaf: true),
        _spectrum = lib.lookupFunction<_SpecC, _SpecD>('carro_get_spectrum', isLeaf: true),
        _meters = lib.lookupFunction<_FloatsC, _FloatsD>('carro_get_meters', isLeaf: true),
        _decay = lib.lookupFunction<_DecayC, _DecayD>('carro_get_decay_curve', isLeaf: true),
        _response = lib.lookupFunction<_RespC, _RespD>('carro_get_response', isLeaf: true),
        _rate = lib.lookupFunction<_RateC, _RateD>('carro_sample_rate', isLeaf: true),
        _version = lib.lookupFunction<_VersionC, _VersionC>('carro_version');

  static CarroDsp? _instance;
  static Object? _loadError;

  /// The process-wide engine. Throws if the native library is missing.
  static CarroDsp get instance {
    if (_instance != null) return _instance!;
    try {
      return _instance = CarroDsp._(openCarroLibrary());
    } catch (e) {
      _loadError = e;
      rethrow;
    }
  }

  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Object? get loadError => _loadError;

  final _SetD _setParam;
  final _GetD _getParam;
  final _VoidD _begin, _end, _reset, _clearIr;
  final _FloatsD _irInfo, _meters;
  final _SpecD _spectrum;
  final _DecayD _decay;
  final _RespD _response;
  final _RateD _rate;
  final _VersionC _version;

  // Persistent native scratch buffers (never freed; the engine lives for the app lifetime).
  final Pointer<Float> _buf = malloc<Float>(1024);
  final Pointer<Float> _buf2 = malloc<Float>(1024);
  final Pointer<Float> _small = malloc<Float>(8);

  String get version => _version().toDartString();
  double get sampleRate => _rate();

  void set(int id, num value, [int index = 0]) => _setParam(id, index, value.toDouble());
  double get(int id, [int index = 0]) => _getParam(id, index);
  void beginBatch() => _begin();
  void endBatch() => _end();

  /// Runs [body] as one atomic parameter update.
  void batch(void Function() body) {
    _begin();
    try {
      body();
    } finally {
      _end();
    }
  }

  void reset() => _reset();
  void clearIr() => _clearIr();

  /// Loads an impulse response WAV (off the UI thread).
  Future<int> loadIr(String path) => Isolate.run(() {
        final lib = openCarroLibrary();
        final fn = lib.lookupFunction<_PathC, _PathD>('carro_load_ir_file');
        final p = path.toNativeUtf8();
        try {
          return fn(p);
        } finally {
          malloc.free(p);
        }
      });

  IrInfo irInfo() {
    _irInfo(_small);
    return IrInfo(_small[0] > 0.5, _small[1].round(), _small[2].round(), _small[3]);
  }

  /// Output spectrum in [bands] log-spaced bands (dBFS).
  Float32List spectrum(int bands) {
    final n = _spectrum(_buf, bands.clamp(1, 1024));
    return Float32List.fromList(_buf.asTypedList(n));
  }

  DspMeters meters() {
    _meters(_small);
    return DspMeters(_small[0], _small[1], _small[2], _small[3], _small[4], _small[5].round());
  }

  DecayCurve? decayCurve(int points) {
    final n = _decay(_buf, points.clamp(2, 1024), _small);
    if (n <= 0) return null;
    return DecayCurve(Float32List.fromList(_buf.asTypedList(n)), _small[0], _small[1]);
  }

  /// Magnitude response (dB) of a curve (see [Curve]) at [freqs].
  Float32List response(int curve, List<double> freqs) {
    final n = freqs.length.clamp(0, 1024);
    for (var i = 0; i < n; i++) {
      _buf[i] = freqs[i];
    }
    final got = _response(curve, _buf, _buf2, n);
    return Float32List.fromList(_buf2.asTypedList(got));
  }

  /// Deconvolves recorded sweeps into an IR WAV. Returns IR frames (>0) or an error code.
  static Future<int> buildIrFromCaptures({
    required String recLeft,
    String? recRight,
    required String outWav,
    required double sweepSampleRate,
    double f1 = 20,
    double f2 = 20000,
    required double sweepSeconds,
    double maxIrSeconds = 6,
  }) =>
      Isolate.run(() {
        final lib = openCarroLibrary();
        final fn = lib.lookupFunction<_BuildC, _BuildD>('carro_ir_build_from_captures');
        final a = recLeft.toNativeUtf8();
        final b = (recRight ?? '').toNativeUtf8();
        final o = outWav.toNativeUtf8();
        try {
          return fn(a, b, o, sweepSampleRate, f1, f2, sweepSeconds, maxIrSeconds);
        } finally {
          malloc.free(a);
          malloc.free(b);
          malloc.free(o);
        }
      });

  /// RT60 (T20) of a mono impulse response.
  static double measureRt60(Float32List ir, double sampleRate) {
    final lib = openCarroLibrary();
    final fn = lib.lookupFunction<_Rt60C, _Rt60D>('carro_measure_rt60');
    final p = malloc<Float>(ir.length);
    final out = malloc<Float>(1);
    try {
      p.asTypedList(ir.length).setAll(0, ir);
      fn(p, ir.length, sampleRate, out);
      return out.value;
    } finally {
      malloc.free(p);
      malloc.free(out);
    }
  }
}

/// Error codes returned by the native side.
abstract final class CarroError {
  static const ok = 0;
  static const io = -1;
  static const format = -2;
  static const args = -3;
  static const signal = -4;

  static String describe(int code) => switch (code) {
        io => 'I/O error',
        format => 'Unsupported WAV format',
        args => 'Invalid arguments',
        signal => 'No usable signal in the recording',
        _ => 'Error $code',
      };
}
