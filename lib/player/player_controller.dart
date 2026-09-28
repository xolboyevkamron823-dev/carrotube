import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:carro_native/carro_native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/download_manager.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../data/youtube_service.dart';
import 'embed_player.dart';

enum RepeatMode { off, all, one }

class PlayerUiState {
  const PlayerUiState({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.state = NativePlaybackState.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.audioOnly = false,
    this.textureId,
    this.aspectRatio = 16 / 9,
    this.speed = 1.0,
    this.repeat = RepeatMode.off,
    this.shuffle = false,
    this.autoplay = true,
    this.upNext = const [],
    this.streams,
    this.quality,
    this.error,
    this.pipActive = false,
    this.loadingItem = false,
    this.embed = false,
  });

  final List<VideoItem> queue;
  final int index;
  final bool playing;
  final NativePlaybackState state;
  final Duration position, duration, buffered;
  final bool audioOnly;
  final int? textureId;
  final double aspectRatio;
  final double speed;
  final RepeatMode repeat;
  final bool shuffle;
  final bool autoplay;

  /// Related videos of the current item ("Up next").
  final List<VideoItem> upNext;
  final ResolvedStreams? streams;
  final StreamChoice? quality;
  final String? error;
  final bool pipActive;
  final bool loadingItem;

  /// Playing through YouTube's official embedded player (web view) instead of the native
  /// DSP player.
  final bool embed;

  VideoItem? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length || (autoplay && upNext.isNotEmpty) || repeat == RepeatMode.all;
  bool get hasPrevious => index > 0;
  bool get isActive => current != null;
  bool get buffering =>
      loadingItem || state == NativePlaybackState.loading || state == NativePlaybackState.buffering;

  PlayerUiState copyWith({
    List<VideoItem>? queue,
    int? index,
    bool? playing,
    NativePlaybackState? state,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    bool? audioOnly,
    int? textureId,
    bool clearTexture = false,
    double? aspectRatio,
    double? speed,
    RepeatMode? repeat,
    bool? shuffle,
    bool? autoplay,
    List<VideoItem>? upNext,
    ResolvedStreams? streams,
    StreamChoice? quality,
    bool clearQuality = false,
    String? error,
    bool clearError = false,
    bool? pipActive,
    bool? loadingItem,
    bool? embed,
  }) =>
      PlayerUiState(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        state: state ?? this.state,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        audioOnly: audioOnly ?? this.audioOnly,
        textureId: clearTexture ? null : (textureId ?? this.textureId),
        aspectRatio: aspectRatio ?? this.aspectRatio,
        speed: speed ?? this.speed,
        repeat: repeat ?? this.repeat,
        shuffle: shuffle ?? this.shuffle,
        autoplay: autoplay ?? this.autoplay,
        upNext: upNext ?? this.upNext,
        streams: streams ?? this.streams,
        quality: clearQuality ? null : (quality ?? this.quality),
        error: clearError ? null : (error ?? this.error),
        pipActive: pipActive ?? this.pipActive,
        loadingItem: loadingItem ?? this.loadingItem,
        embed: embed ?? this.embed,
      );
}

final playerProvider = NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);

/// Whether the full watch page is open (the shell hides the mini player then).
final watchPageOpenProvider = NotifierProvider<WatchPageOpen, bool>(WatchPageOpen.new);

class WatchPageOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool open) => state = open;
}

/// Queue + transport logic on top of the native player. Everything audible goes through
/// the native DSP; this class only decides *what* plays.
class PlayerController extends Notifier<PlayerUiState> {
  final _player = NativePlayer.instance;
  StreamSubscription<PlayerEvent>? _sub;
  StreamSubscription<EmbedEvent>? _embedSub;
  Timer? _positionSaver;
  int _loadToken = 0;
  int _refreshAttempts = 0;
  String? _prefetchedFor;
  List<VideoItem> _originalOrder = const [];
  final _rng = Random();

  @override
  PlayerUiState build() {
    final s = ref.read(settingsProvider);
    _sub = _player.events.listen(_onEvent);
    _embedSub = ref.read(embedPlayerProvider).events.listen(_onEmbedEvent);
    _player.init();
    _player.setResumeOnBluetooth(s.resumeOnBluetooth);
    _positionSaver = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
    ref.onDispose(() {
      _sub?.cancel();
      _embedSub?.cancel();
      _positionSaver?.cancel();
    });
    return PlayerUiState(audioOnly: s.audioOnlyDefault, autoplay: s.autoplay, speed: s.playbackSpeed);
  }

  YoutubeService get _yt => ref.read(youtubeServiceProvider);

  // ---------------------------------------------------------------------------------------
  // Queue building
  // ---------------------------------------------------------------------------------------
  /// Plays [video]. With [queue] the whole list becomes the queue (starting at [video]).
  Future<void> playVideo(VideoItem video, {List<VideoItem>? queue, bool? audioOnly}) async {
    var q = queue ?? [video];
    var i = q.indexWhere((v) => v.id == video.id);
    if (i < 0) {
      q = [video, ...q];
      i = 0;
    }
    _originalOrder = List.of(q);
    if (state.shuffle) {
      final rest = [...q]..removeAt(i);
      rest.shuffle(_rng);
      q = [video, ...rest];
      i = 0;
    }
    state = state.copyWith(queue: q, index: i, audioOnly: audioOnly ?? state.audioOnly, upNext: const []);
    await _loadCurrent();
  }

  Future<void> playQueue(List<VideoItem> items, {int start = 0, bool shuffle = false}) async {
    if (items.isEmpty) return;
    if (shuffle) state = state.copyWith(shuffle: true);
    await playVideo(items[start.clamp(0, items.length - 1)], queue: items);
  }

  void playNext(VideoItem v) {
    if (!state.isActive) {
      playVideo(v);
      return;
    }
    final q = [...state.queue]..removeWhere((e) => e.id == v.id && e != state.current);
    final at = q.indexWhere((e) => e.id == state.current!.id) + 1;
    q.insert(at, v);
    state = state.copyWith(queue: q, index: at - 1);
    _updateRemoteControls();
  }

  void addToQueue(VideoItem v) {
    if (!state.isActive) {
      playVideo(v);
      return;
    }
    if (state.queue.any((e) => e.id == v.id)) return;
    state = state.copyWith(queue: [...state.queue, v]);
    _updateRemoteControls();
  }

  void removeAt(int i) {
    if (i < 0 || i >= state.queue.length || i == state.index) return;
    final q = [...state.queue]..removeAt(i);
    state = state.copyWith(queue: q, index: i < state.index ? state.index - 1 : state.index);
    _updateRemoteControls();
  }

  void reorder(int oldIndex, int newIndex) {
    final q = [...state.queue];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = q.removeAt(oldIndex);
    q.insert(newIndex, item);
    final cur = state.current;
    state = state.copyWith(queue: q, index: cur == null ? -1 : q.indexOf(cur));
    _updateRemoteControls();
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= state.queue.length) return;
    state = state.copyWith(index: i);
    await _loadCurrent();
  }

  // ---------------------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------------------
  EmbedPlayer get _embed => ref.read(embedPlayerProvider);

  Future<void> play() => state.embed ? _embed.play() : _player.play();
  Future<void> pause() => state.embed ? _embed.pause() : _player.pause();
  Future<void> togglePlay() => state.playing ? pause() : play();

  Future<void> seek(Duration d) async {
    final max = state.duration > Duration.zero ? state.duration : d;
    final t = d < Duration.zero ? Duration.zero : (d > max ? max : d);
    state = state.copyWith(position: t);
    if (state.embed) {
      await _embed.seek(t);
    } else {
      await _player.seek(t);
    }
  }

  Future<void> seekRelative(int seconds) => seek(state.position + Duration(seconds: seconds));

  Future<void> next({bool auto = false}) async {
    if (state.repeat == RepeatMode.one && auto) {
      await seek(Duration.zero);
      await play();
      return;
    }
    if (state.index + 1 < state.queue.length) {
      state = state.copyWith(index: state.index + 1);
      await _loadCurrent();
      return;
    }
    if (state.repeat == RepeatMode.all && state.queue.isNotEmpty) {
      state = state.copyWith(index: 0);
      await _loadCurrent();
      return;
    }
    if (state.autoplay && state.upNext.isNotEmpty) {
      final played = state.queue.map((e) => e.id).toSet();
      final candidate = state.upNext.firstWhere((v) => !played.contains(v.id), orElse: () => state.upNext.first);
      state = state.copyWith(queue: [...state.queue, candidate], index: state.queue.length);
      await _loadCurrent();
      return;
    }
    if (auto) {
      state = state.copyWith(playing: false);
    }
  }

  Future<void> previous() async {
    if (state.position > const Duration(seconds: 3) || state.index <= 0) {
      await seek(Duration.zero);
      return;
    }
    state = state.copyWith(index: state.index - 1);
    await _loadCurrent();
  }

  Future<void> setSpeed(double r) async {
    state = state.copyWith(speed: r);
    if (state.embed) {
      await _embed.setRate(r);
    } else {
      await _player.setRate(r);
    }
  }

  void setRepeat(RepeatMode m) {
    state = state.copyWith(repeat: m);
    _updateRemoteControls();
  }

  void cycleRepeat() => setRepeat(RepeatMode.values[(state.repeat.index + 1) % RepeatMode.values.length]);

  void toggleShuffle() {
    final on = !state.shuffle;
    final cur = state.current;
    if (cur == null) {
      state = state.copyWith(shuffle: on);
      return;
    }
    List<VideoItem> q;
    if (on) {
      _originalOrder = List.of(state.queue);
      final rest = [...state.queue]..remove(cur);
      rest.shuffle(_rng);
      q = [cur, ...rest];
    } else {
      q = _originalOrder.isNotEmpty ? List.of(_originalOrder) : state.queue;
      for (final v in state.queue) {
        if (!q.contains(v)) q.add(v);
      }
    }
    state = state.copyWith(shuffle: on, queue: q, index: q.indexOf(cur));
    _updateRemoteControls();
  }

  void setAutoplay(bool on) {
    state = state.copyWith(autoplay: on);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(autoplay: on));
    _updateRemoteControls();
  }

  /// Switches between video and audio-only (YouTube Music style) keeping the position.
  Future<void> setAudioOnly(bool audioOnly) async {
    if (audioOnly == state.audioOnly) return;
    state = state.copyWith(audioOnly: audioOnly);
    // The embedded player keeps playing; audio-only just covers the video with artwork.
    if (state.embed) return;
    if (state.isActive) await _loadCurrent(start: state.position, keepPlaying: state.playing);
  }

  Future<void> setQuality(StreamChoice c) async {
    state = state.copyWith(quality: c);
    if (state.isActive && !state.audioOnly) await _loadCurrent(start: state.position, keepPlaying: state.playing);
  }

  Future<void> stop() async {
    await _savePosition();
    await _player.stop();
    if (state.embed) await _embed.stop();
    state = PlayerUiState(
      audioOnly: state.audioOnly,
      autoplay: state.autoplay,
      speed: state.speed,
      repeat: state.repeat,
      shuffle: state.shuffle,
    );
  }

  Future<bool> startPip(Rect rect) async {
    if (state.audioOnly || state.textureId == null) return false;
    return _player.startPip(rect);
  }

  // ---------------------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------------------
  Future<void> _loadCurrent({Duration? start, bool keepPlaying = true}) async {
    final item = state.current;
    if (item == null) return;
    final token = ++_loadToken;
    _refreshAttempts = 0;
    state = state.copyWith(
      loadingItem: true,
      clearError: true,
      position: start ?? Duration.zero,
      duration: item.duration ?? Duration.zero,
      buffered: Duration.zero,
      clearTexture: true,
      clearQuality: start == null,
    );
    _updateRemoteControls();

    // Downloaded files play natively (with the DSP); online YouTube videos play through
    // YouTube's official embedded player.
    final dl = ref.read(downloadManagerProvider)[item.id];
    final offline = dl != null && dl.status == DownloadStatus.done && dl.filePath != null && File(dl.filePath!).existsSync();
    if (!offline) {
      if (!state.embed) await _player.stop();
      state = state.copyWith(embed: true, state: NativePlaybackState.loading);
      await _embed.load(item.id, startSeconds: (start ?? Duration.zero).inMilliseconds / 1000, autoplay: keepPlaying);
      if (token != _loadToken) return;
      state = state.copyWith(loadingItem: false);
      if (state.speed != 1.0) await _embed.setRate(state.speed);
      ref.read(libraryActionsProvider).addHistory(item);
      _loadUpNext(item, token);
      return;
    }
    if (state.embed) {
      await _embed.stop();
      state = state.copyWith(embed: false);
    }
    try {
      final media = await _mediaFor(item);
      if (token != _loadToken) return;
      final withVideo = !state.audioOnly && (media.videoUrl != null || media.muxedUrl != null);
      final texture = await _player.load(
        media,
        withVideo: withVideo,
        start: start ?? Duration.zero,
        playWhenReady: keepPlaying,
      );
      if (token != _loadToken) return;
      state = state.copyWith(textureId: texture, loadingItem: false);
      _player.setAutoPip(withVideo && texture != null).ignore();
      if (state.speed != 1.0) await _player.setRate(state.speed);
      ref.read(libraryActionsProvider).addHistory(item);
      _loadUpNext(item, token);
    } catch (e) {
      if (token != _loadToken) return;
      state = state.copyWith(loadingItem: false, error: e.toString(), playing: false);
    }
  }

  Future<NativeMediaItem> _mediaFor(VideoItem item, {bool refresh = false}) async {
    // Offline copy first.
    final dl = ref.read(downloadManagerProvider)[item.id];
    if (dl != null && dl.status == DownloadStatus.done && dl.filePath != null && File(dl.filePath!).existsSync()) {
      final vf = dl.videoFilePath;
      final hasVideo = vf != null && File(vf).existsSync();
      return NativeMediaItem(
        id: item.id,
        audioUrl: dl.filePath!,
        videoUrl: hasVideo && !vf.endsWith('.muxed.mp4') ? vf : null,
        muxedUrl: hasVideo && vf.endsWith('.muxed.mp4') ? vf : null,
        title: item.title,
        artist: item.channelName,
        artworkUrl: item.thumbnailUrl,
        duration: item.duration,
        isLocalFile: true,
      );
    }
    final streams = await _yt.resolve(item.id, refresh: refresh);
    StreamChoice? choice = state.quality;
    if (choice != null && !streams.videoChoices.any((c) => c.height == choice!.height)) choice = null;
    if (choice == null && streams.videoChoices.isNotEmpty) {
      final pref = ref.read(settingsProvider).preferredQuality;
      final ok = streams.videoChoices.where((c) => c.height <= pref).toList();
      choice = ok.isNotEmpty ? ok.first : streams.videoChoices.last;
    } else if (choice != null) {
      choice = streams.videoChoices.firstWhere((c) => c.height == choice!.height);
    }
    state = state.copyWith(streams: streams, quality: choice);
    return NativeMediaItem(
      id: item.id,
      audioUrl: streams.audioUrl,
      videoUrl: choice != null && !choice.muxed ? choice.url : null,
      muxedUrl: choice != null && choice.muxed ? choice.url : streams.muxedUrl,
      headers: streams.headers,
      title: item.title,
      artist: item.channelName,
      artworkUrl: item.thumbnailUrl,
      duration: item.duration,
    );
  }

  Future<void> _loadUpNext(VideoItem item, int token) async {
    try {
      final page = await _yt.related(item.id);
      if (token != _loadToken) return;
      state = state.copyWith(upNext: page.items.where((v) => !v.isLive).toList());
      _updateRemoteControls();
    } catch (_) {}
  }

  /// Re-resolves an expired stream URL and continues where playback stopped.
  Future<void> _refreshAndResume() async {
    final item = state.current;
    if (item == null) return;
    final token = ++_loadToken;
    final pos = state.position;
    try {
      final media = await _mediaFor(item, refresh: true);
      if (token != _loadToken) return;
      final texture = await _player.load(
        media,
        withVideo: !state.audioOnly && (media.videoUrl != null || media.muxedUrl != null),
        start: pos,
      );
      state = state.copyWith(textureId: texture, clearError: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void _updateRemoteControls() {
    _player.setQueueControls(hasNext: state.hasNext, hasPrevious: state.isActive);
    final browse = [...state.queue, ...state.upNext.where((v) => !state.queue.contains(v))].take(60);
    _player
        .setBrowsable([
          for (final v in browse)
            NativeMediaItem(id: v.id, audioUrl: '', title: v.title, artist: v.channelName, artworkUrl: v.thumbnailUrl),
        ])
        .ignore();
  }

  /// Android Auto / assistant picked an item from the browse list.
  Future<void> _playById(String? id) async {
    if (id == null) return;
    final i = state.queue.indexWhere((v) => v.id == id);
    if (i >= 0) {
      await jumpTo(i);
      return;
    }
    final v = state.upNext.where((v) => v.id == id).firstOrNull;
    if (v != null) {
      await playVideo(v, queue: [...state.queue, v]);
      return;
    }
    try {
      await playVideo(await _yt.video(id));
    } catch (_) {}
  }

  /// The item [next] would pick right now (without changing anything).
  VideoItem? _peekNext() {
    if (state.repeat == RepeatMode.one) return null;
    if (state.index + 1 < state.queue.length) return state.queue[state.index + 1];
    if (state.repeat == RepeatMode.all && state.queue.isNotEmpty) return state.queue.first;
    if (state.autoplay && state.upNext.isNotEmpty) {
      final played = state.queue.map((e) => e.id).toSet();
      return state.upNext.firstWhere((v) => !played.contains(v.id), orElse: () => state.upNext.first);
    }
    return null;
  }

  /// Resolves the next item's stream URLs ~25 s before the current one ends, so the
  /// hand-over is instant. This matters on iOS: an app that stops producing audio in the
  /// background may be suspended before a slow network request finishes.
  void _maybePrefetchNext() {
    final cur = state.current;
    if (cur == null || state.duration <= Duration.zero) return;
    final remaining = state.duration - state.position;
    if (remaining > const Duration(seconds: 25) || _prefetchedFor == cur.id) return;
    _prefetchedFor = cur.id;
    final next = _peekNext();
    if (next == null) return;
    final dl = ref.read(downloadManagerProvider)[next.id];
    if (dl != null && dl.status == DownloadStatus.done) return;
    _yt.resolve(next.id).ignore();
  }

  Future<void> _savePosition() async {
    final cur = state.current;
    if (cur == null || state.position.inSeconds < 5) return;
    await ref.read(appDatabaseProvider).savePosition(cur.id, state.position);
  }

  // ---------------------------------------------------------------------------------------
  // Embedded (YouTube IFrame) player events
  // ---------------------------------------------------------------------------------------
  static NativePlaybackState _embedState(int s) => switch (s) {
        0 => NativePlaybackState.ended,
        1 || 2 => NativePlaybackState.ready,
        3 => NativePlaybackState.buffering,
        5 => NativePlaybackState.ready,
        _ => NativePlaybackState.loading,
      };

  void _onEmbedEvent(EmbedEvent e) {
    if (!state.embed) return;
    switch (e.type) {
      case 'state':
        final s = (e.data['s'] as num?)?.toInt() ?? -1;
        final wasEnded = state.state == NativePlaybackState.ended;
        state = state.copyWith(state: _embedState(s), playing: s == 1 || s == 3, clearError: s == 1);
        if (s == 0 && !wasEnded) next(auto: true);
      case 'time':
        final d = Duration(milliseconds: (((e.data['d'] as num?) ?? 0) * 1000).round());
        final t = Duration(milliseconds: (((e.data['t'] as num?) ?? 0) * 1000).round());
        final b = ((e.data['b'] as num?) ?? 0).toDouble();
        final s = (e.data['s'] as num?)?.toInt() ?? -1;
        state = state.copyWith(
          position: t,
          duration: d > Duration.zero ? d : state.duration,
          buffered: Duration(milliseconds: (d.inMilliseconds * b).round()),
          playing: s == 1 || s == 3,
        );
        if (s == 1) _maybePrefetchNext();
      case 'error':
        final code = (e.data['code'] as num?)?.toInt() ?? 0;
        final cur = state.current;
        if ((code == 152 || code == 153) && cur != null && _embed.tryNextVariant()) {
          // The new page needs a moment to load the IFrame API; carroLoad queues until ready.
          final at = state.position;
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (state.embed && state.current?.id == cur.id) {
              _embed.load(cur.id, startSeconds: at.inMilliseconds / 1000);
            }
          });
          return;
        }
        state = state.copyWith(error: embedErrorText(code), playing: false, loadingItem: false);
      case 'rate':
        break;
    }
  }

  // ---------------------------------------------------------------------------------------
  // Native events
  // ---------------------------------------------------------------------------------------
  void _onEvent(PlayerEvent e) {
    switch (e) {
      case PlayerStateEvent() when state.embed:
        break;
      case PlayerStateEvent():
        final wasEnded = state.state == NativePlaybackState.ended;
        state = state.copyWith(
          state: e.state,
          playing: e.playing,
          position: e.position,
          duration: e.duration > Duration.zero ? e.duration : state.duration,
          buffered: e.buffered,
        );
        if (e.state == NativePlaybackState.ended && !wasEnded) {
          next(auto: true);
        } else if (e.playing) {
          _maybePrefetchNext();
        }
      case PlayerErrorEvent():
        if (e.looksLikeExpiredUrl && _refreshAttempts < 2 && !(state.current == null)) {
          _refreshAttempts++;
          _refreshAndResume();
        } else {
          state = state.copyWith(error: e.message, playing: false, loadingItem: false);
        }
      case RemoteCommandEvent():
        switch (e.command) {
          case 'next':
            next();
          case 'previous':
            previous();
          case 'play':
            play();
          case 'pause':
            pause();
          case 'toggle':
            togglePlay();
          case 'seek':
            seek(e.position);
          case 'stop':
            stop();
          case 'playId':
            _playById(e.id);
        }
      case VideoSizeEvent():
        if (e.width > 0 && e.height > 0) {
          state = state.copyWith(aspectRatio: e.width / e.height, textureId: e.textureId ?? state.textureId);
        }
      case PipEvent():
        state = state.copyWith(pipActive: e.active);
      case InterruptionEvent():
      case RouteChangeEvent():
      case AppBackgroundEvent(:final background) when background && state.embed && state.playing:
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (state.embed) _embed.play();
        });
      case AppBackgroundEvent():
        break;
    }
  }
}

/// Convenience: pretty "Up next" list = rest of the queue followed by related videos.
final upNextListProvider = Provider<List<VideoItem>>((ref) {
  final s = ref.watch(playerProvider);
  final rest = s.index >= 0 && s.index + 1 < s.queue.length ? s.queue.sublist(s.index + 1) : <VideoItem>[];
  final ids = {...rest.map((e) => e.id), if (s.current != null) s.current!.id};
  return [...rest, ...s.upNext.where((v) => !ids.contains(v.id))];
});
