import 'dart:async';

import 'package:flutter/services.dart';

/// Playback state reported by the native player.
enum NativePlaybackState { idle, loading, ready, buffering, ended, error }

/// Events coming from the native side (EventChannel `carro/player/events`).
sealed class PlayerEvent {
  const PlayerEvent();

  static PlayerEvent? fromMap(Map<Object?, Object?> m) {
    switch (m['type']) {
      case 'state':
        return PlayerStateEvent(
          state: NativePlaybackState.values.firstWhere(
            (s) => s.name == m['state'],
            orElse: () => NativePlaybackState.idle,
          ),
          playing: m['playing'] == true,
          position: Duration(milliseconds: _int(m['positionMs'])),
          duration: Duration(milliseconds: _int(m['durationMs'])),
          buffered: Duration(milliseconds: _int(m['bufferedMs'])),
          rate: _double(m['rate'], 1.0),
        );
      case 'error':
        return PlayerErrorEvent(
          message: (m['message'] as String?) ?? 'Playback error',
          code: (m['code'] as String?) ?? 'unknown',
          httpStatus: _int(m['httpStatus']),
        );
      case 'remote':
        return RemoteCommandEvent(
          command: (m['command'] as String?) ?? '',
          position: Duration(milliseconds: _int(m['positionMs'])),
          id: m['id'] as String?,
        );
      case 'video':
        return VideoSizeEvent(
          width: _int(m['width']),
          height: _int(m['height']),
          textureId: m['textureId'] == null ? null : _int(m['textureId']),
        );
      case 'pip':
        return PipEvent(active: m['active'] == true);
      case 'interruption':
        return InterruptionEvent(began: m['began'] == true, shouldResume: m['shouldResume'] == true);
      case 'route':
        return RouteChangeEvent(reason: (m['reason'] as String?) ?? '');
      case 'background':
        return AppBackgroundEvent(background: m['background'] == true);
    }
    return null;
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static double _double(Object? v, double d) => v is num ? v.toDouble() : d;
}

class PlayerStateEvent extends PlayerEvent {
  const PlayerStateEvent({
    required this.state,
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.rate,
  });
  final NativePlaybackState state;
  final bool playing;
  final Duration position, duration, buffered;
  final double rate;
}

class PlayerErrorEvent extends PlayerEvent {
  const PlayerErrorEvent({required this.message, required this.code, this.httpStatus = 0});
  final String message;
  final String code;
  final int httpStatus;

  /// Stream URLs expire after a few hours / may be rejected with 403 -> re-resolve.
  bool get looksLikeExpiredUrl =>
      httpStatus == 403 || httpStatus == 410 || code == 'http' || code == 'source' || code == 'expired';
}

class RemoteCommandEvent extends PlayerEvent {
  const RemoteCommandEvent({required this.command, required this.position, this.id});

  /// play, pause, toggle, next, previous, seek, stop, playId
  final String command;
  final Duration position;

  /// Media id for `playId` (Android Auto / assistant selection).
  final String? id;
}

class VideoSizeEvent extends PlayerEvent {
  const VideoSizeEvent({required this.width, required this.height, this.textureId});
  final int width, height;
  final int? textureId;
}

class PipEvent extends PlayerEvent {
  const PipEvent({required this.active});
  final bool active;
}

class InterruptionEvent extends PlayerEvent {
  const InterruptionEvent({required this.began, required this.shouldResume});
  final bool began, shouldResume;
}

class RouteChangeEvent extends PlayerEvent {
  const RouteChangeEvent({required this.reason});

  /// `unplugged` (headphones / BT lost -> native already paused), `connected`
  final String reason;
}

class AppBackgroundEvent extends PlayerEvent {
  const AppBackgroundEvent({required this.background});
  final bool background;
}

/// Media item handed to the native player.
class NativeMediaItem {
  const NativeMediaItem({
    required this.id,
    required this.audioUrl,
    this.videoUrl,
    this.muxedUrl,
    this.headers = const {},
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.duration,
    this.isLocalFile = false,
  });

  final String id;

  /// Audio-only stream (m4a/AAC on iOS, any on Android) or local file path.
  final String audioUrl;

  /// Video-only stream (mp4/avc1). When set the native side muxes it with [audioUrl].
  final String? videoUrl;

  /// Muxed (audio+video) stream, used when [videoUrl] is null and video is wanted.
  final String? muxedUrl;
  final Map<String, String> headers;
  final String title, artist;
  final String? artworkUrl;
  final Duration? duration;
  final bool isLocalFile;

  Map<String, Object?> toMap() => {
        'id': id,
        'audioUrl': audioUrl,
        'videoUrl': videoUrl,
        'muxedUrl': muxedUrl,
        'headers': headers,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': duration?.inMilliseconds,
        'isLocalFile': isLocalFile,
      };
}

/// Method-channel API of the native player (ExoPlayer on Android, AVPlayer on iOS).
/// Every sample the player renders goes through the Carro DSP engine.
class NativePlayer {
  NativePlayer._();
  static final NativePlayer instance = NativePlayer._();

  static const _method = MethodChannel('carro/player');
  static const _events = EventChannel('carro/player/events');

  Stream<PlayerEvent>? _stream;

  Stream<PlayerEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => e is Map ? PlayerEvent.fromMap(e.cast<Object?, Object?>()) : null)
      .where((e) => e != null)
      .cast<PlayerEvent>()
      .asBroadcastStream();

  Future<void> init() => _method.invokeMethod('init');

  /// Loads and (optionally) starts an item. Returns the Flutter texture id when
  /// [withVideo] is true and the platform renders video into a texture.
  Future<int?> load(
    NativeMediaItem item, {
    required bool withVideo,
    Duration start = Duration.zero,
    bool playWhenReady = true,
  }) async {
    final r = await _method.invokeMethod<Object?>('load', {
      ...item.toMap(),
      'video': withVideo,
      'startMs': start.inMilliseconds,
      'playWhenReady': playWhenReady,
    });
    return r is num ? r.toInt() : null;
  }

  Future<void> play() => _method.invokeMethod('play');
  Future<void> pause() => _method.invokeMethod('pause');
  Future<void> stop() => _method.invokeMethod('stop');
  Future<void> seek(Duration position) => _method.invokeMethod('seek', {'ms': position.inMilliseconds});
  Future<void> setRate(double rate) => _method.invokeMethod('setRate', {'rate': rate});

  /// Tells the lock screen / notification which transport buttons to enable.
  Future<void> setQueueControls({required bool hasNext, required bool hasPrevious}) =>
      _method.invokeMethod('setQueueControls', {'hasNext': hasNext, 'hasPrevious': hasPrevious});

  Future<void> setResumeOnBluetooth(bool enabled) =>
      _method.invokeMethod('setResumeOnBluetooth', {'enabled': enabled});

  /// Starts picture-in-picture. [rect] is the video widget in logical pixels (global).
  Future<bool> startPip(Rect rect) async =>
      (await _method.invokeMethod<bool>('startPip', {
        'x': rect.left,
        'y': rect.top,
        'w': rect.width,
        'h': rect.height,
      })) ??
      false;

  Future<void> stopPip() => _method.invokeMethod('stopPip');
  Future<bool> isPipSupported() async => (await _method.invokeMethod<bool>('isPipSupported')) ?? false;

  /// Android: automatically enter picture-in-picture when the user leaves the app while a
  /// video plays (YouTube behaviour). iOS: no-op (PiP is started explicitly).
  Future<void> setAutoPip(bool enabled) => _method.invokeMethod('setAutoPip', {'enabled': enabled});

  /// Items shown in Android Auto's browse list (current queue + up next).
  Future<void> setBrowsable(List<NativeMediaItem> items) => _method.invokeMethod('setBrowsable', {
        'items': [
          for (final i in items) {'id': i.id, 'title': i.title, 'artist': i.artist, 'artworkUrl': i.artworkUrl},
        ],
      });

  /// Detaches/attaches video decoding without reloading (background audio).
  Future<void> setVideoEnabled(bool enabled) => _method.invokeMethod('setVideoEnabled', {'enabled': enabled});

  Future<void> dispose() => _method.invokeMethod('dispose');
}

/// Platform helpers (battery optimisation on Android, device info).
class CarroSystem {
  static const _ch = MethodChannel('carro/system');

  static Future<Map<String, Object?>> deviceInfo() async =>
      (await _ch.invokeMapMethod<String, Object?>('deviceInfo')) ?? const {};

  /// Android: true if the app is exempt from battery optimisation. iOS: always true.
  static Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? true;

  static Future<void> requestIgnoreBatteryOptimizations() =>
      _ch.invokeMethod('requestIgnoreBatteryOptimizations');

  /// Opens vendor specific autostart / background screens (Xiaomi, Samsung, Huawei...).
  static Future<bool> openVendorBackgroundSettings(String vendor) async =>
      (await _ch.invokeMethod<bool>('openVendorBackgroundSettings', {'vendor': vendor})) ?? false;
}

/// Recording side of the IR capture wizard (sweep playback + input recording).
class IrCaptureApi {
  static const _ch = MethodChannel('carro/ircapture');

  static Future<bool> requestMicrophone() async => (await _ch.invokeMethod<bool>('requestMicrophone')) ?? false;

  /// Current audio route: {'input': name, 'inputType': ..., 'output': name, 'sampleRate': 48000.0}
  static Future<Map<String, Object?>> route() async =>
      (await _ch.invokeMapMethod<String, Object?>('route')) ?? const {};

  /// Plays an exponential sweep on [channel] (0 = left, 1 = right, 2 = both) and records the
  /// input for the sweep plus [tailSeconds]. Returns {'path', 'sampleRate', 'channels', 'peakDb'}.
  static Future<Map<String, Object?>> capture({
    required int channel,
    double sweepSeconds = 10,
    double f1 = 20,
    double f2 = 20000,
    double amplitudeDb = -6,
    double tailSeconds = 4,
  }) async =>
      (await _ch.invokeMapMethod<String, Object?>('capture', {
        'channel': channel,
        'sweepSeconds': sweepSeconds,
        'f1': f1,
        'f2': f2,
        'amplitudeDb': amplitudeDb,
        'tailSeconds': tailSeconds,
      })) ??
      const {};

  static Future<void> cancel() => _ch.invokeMethod('cancel');
}
