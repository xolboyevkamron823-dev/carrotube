import AVFoundation
import AVKit
import Flutter
import MediaPlayer
import UIKit

#if canImport(CarroDSP)
  import CarroDSP
#endif

/// AVPlayer based player. Every audio sample passes through the Carro DSP via an
/// MTAudioProcessingTap attached to the item's audio mix. Video (when requested) is either a
/// muxed MP4 or an AVMutableComposition of YouTube's separate video-only + audio-only
/// streams, rendered into a Flutter texture; picture-in-picture uses an AVPlayerLayer.
///
/// Background playback: AVAudioSession .playback + UIBackgroundModes=audio. When the app
/// goes to the background the video tracks are disabled (unless PiP is active) so audio
/// keeps playing seamlessly and no GPU work is done.
final class CarroPlayer: NSObject, AVPictureInPictureControllerDelegate {
  var emit: (([String: Any]) -> Void)?

  private let textures: FlutterTextureRegistry
  private let player = AVPlayer()
  private var videoTexture: CarroVideoTexture?
  private var textureId: Int64?
  private var timeObserver: Any?
  private var playerObservations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var notificationTokens: [NSObjectProtocol] = []
  private var loadTask: Task<Void, Never>?
  private var loadGeneration = 0
  private var loading = false
  private var ended = false
  private var withVideo = false
  private var isLocal = false
  private var hasNext = false
  private var resumeOnBluetooth = true
  private var pausedByRouteLoss = false
  private var wasPlayingBeforeInterruption = false
  private var inBackground = false
  private var sessionConfigured = false
  private var remoteConfigured = false
  private var nowPlaying: [String: Any] = [:]
  private var artworkTask: URLSessionDataTask?
  private var lastVideoSize = CGSize.zero
  private var desiredRate: Float = 1
  private var pendingStartMs: Double?
  private var pendingPlay = false

  // Picture-in-picture
  private var playerLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var pipPossibleObservation: NSKeyValueObservation?
  private var pendingPipStart = false

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
    super.init()
    // Keep audio inside the app process so the DSP tap is never bypassed (AirPlay audio
    // routes still work; AirPlay *video* hand-off would skip the tap).
    player.allowsExternalPlayback = false
    player.automaticallyWaitsToMinimizeStalling = true
    player.actionAtItemEnd = .pause

    playerObservations.append(
      player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
        DispatchQueue.main.async {
          self?.sendState()
          self?.updateNowPlayingPlayback()
        }
      })
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
    ) { [weak self] _ in
      self?.sendState()
    }
    installNotifications()
  }

  deinit {
    shutdown()
  }

  func shutdown() {
    if let t = timeObserver {
      player.removeTimeObserver(t)
      timeObserver = nil
    }
    notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    notificationTokens.removeAll()
    releaseTexture()
    player.replaceCurrentItem(with: nil)
  }

  // MARK: - Method channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "init":
      configureSession()
      configureRemoteCommands()
      result(nil)
    case "load":
      configureSession()
      configureRemoteCommands()
      let id = load(args)
      result(id.map { NSNumber(value: $0) })
    case "play":
      startPlayback()
      result(nil)
    case "pause":
      player.pause()
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "seek":
      let ms = (args["ms"] as? NSNumber)?.doubleValue ?? 0
      seek(toMs: ms)
      result(nil)
    case "setRate":
      desiredRate = max(0.25, min(2.0, (args["rate"] as? NSNumber)?.floatValue ?? 1))
      player.currentItem?.audioTimePitchAlgorithm = .timeDomain
      if player.timeControlStatus != .paused {
        player.rate = desiredRate
      }
      updateNowPlayingPlayback()
      result(nil)
    case "setQueueControls":
      hasNext = args["hasNext"] as? Bool ?? false
      MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
      MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = args["hasPrevious"] as? Bool ?? true
      result(nil)
    case "setResumeOnBluetooth":
      resumeOnBluetooth = args["enabled"] as? Bool ?? true
      result(nil)
    case "isPipSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "startPip":
      let rect = CGRect(
        x: (args["x"] as? NSNumber)?.doubleValue ?? 0,
        y: (args["y"] as? NSNumber)?.doubleValue ?? 0,
        width: (args["w"] as? NSNumber)?.doubleValue ?? 320,
        height: (args["h"] as? NSNumber)?.doubleValue ?? 180)
      result(startPip(rect: rect))
    case "stopPip":
      pipController?.stopPictureInPicture()
      result(nil)
    case "setAutoPip", "setBrowsable":
      // Android-only features (auto PiP on leave, Android Auto browse tree).
      result(nil)
    case "setVideoEnabled":
      setVideoTracks(enabled: args["enabled"] as? Bool ?? true)
      result(nil)
    case "dispose":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Audio session

  private func configureSession() {
    guard !sessionConfigured else { return }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
      sessionConfigured = true
    } catch {
      emit?(["type": "error", "code": "session", "message": error.localizedDescription])
    }
  }

  private func activateSession() {
    let session = AVAudioSession.sharedInstance()
    if session.category != .playback {
      try? session.setCategory(.playback, mode: .default, options: [])
    }
    try? session.setActive(true)
  }

  /// Starts playback at the user's speed (AVPlayer.defaultRate needs iOS 16, so set rate).
  private func startPlayback() {
    guard player.currentItem != nil else { return }
    activateSession()
    if desiredRate == 1 {
      player.play()
    } else {
      player.rate = desiredRate
    }
  }

  /// Called by the IR capture before it switches the session to play-and-record.
  func pauseForCapture() {
    player.pause()
  }

  /// Called by the IR capture when it hands the session back.
  func restoreSessionAfterCapture() {
    sessionConfigured = false
    configureSession()
  }

  // MARK: - Loading

  private func makeAsset(_ string: String, headers: [String: String]) -> AVURLAsset {
    let url: URL
    if isLocal || string.hasPrefix("/") {
      url = URL(fileURLWithPath: string)
    } else {
      url = URL(string: string) ?? URL(fileURLWithPath: string)
    }
    var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: false]
    if !url.isFileURL && !headers.isEmpty {
      // Widely used key for per-asset HTTP headers (YouTube checks the client User-Agent).
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    return AVURLAsset(url: url, options: options)
  }

  /// YouTube serves HD video and audio as separate streams: mux them on the fly.
  private func composition(video: AVURLAsset, audio: AVURLAsset) async throws -> AVAsset {
    async let vTracks = video.loadTracks(withMediaType: .video)
    async let aTracks = audio.loadTracks(withMediaType: .audio)
    async let vDuration = video.load(.duration)
    async let aDuration = audio.load(.duration)
    let (vt, at, vd, ad) = try await (vTracks, aTracks, vDuration, aDuration)
    guard let v = vt.first, let a = at.first else {
      throw NSError(domain: "CarroPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stream has no tracks"])
    }
    let duration = CMTimeMinimum(vd, ad)
    let range = CMTimeRange(start: .zero, duration: duration)
    let comp = AVMutableComposition()
    if let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try cv.insertTimeRange(range, of: v, at: .zero)
      cv.preferredTransform = try await v.load(.preferredTransform)
    }
    if let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try ca.insertTimeRange(range, of: a, at: .zero)
    }
    return comp
  }

  private func load(_ args: [String: Any]) -> Int64? {
    loadGeneration += 1
    let generation = loadGeneration
    loadTask?.cancel()

    let audioUrl = args["audioUrl"] as? String ?? ""
    let videoUrl = args["videoUrl"] as? String
    let muxedUrl = args["muxedUrl"] as? String
    let headers = args["headers"] as? [String: String] ?? [:]
    isLocal = args["isLocalFile"] as? Bool ?? false
    let wantVideo = (args["video"] as? Bool ?? false) && (videoUrl != nil || muxedUrl != nil)
    let startMs = (args["startMs"] as? NSNumber)?.doubleValue ?? 0
    let playWhenReady = args["playWhenReady"] as? Bool ?? true

    withVideo = wantVideo
    ended = false
    loading = true
    lastVideoSize = .zero
    updateNowPlayingMetadata(args)

    // Stop the previous item right away (like YouTube) and reset the texture.
    player.pause()
    clearItemObservations()
    player.replaceCurrentItem(with: nil)
    releaseTexture()
    var newTextureId: Int64?
    if wantVideo {
      let texture = CarroVideoTexture(registry: textures)
      let id = textures.register(texture)
      texture.textureId = id
      videoTexture = texture
      textureId = id
      newTextureId = id
    }
    sendState()

    loadTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let asset: AVAsset
        if wantVideo, let v = videoUrl {
          asset = try await self.composition(
            video: self.makeAsset(v, headers: headers), audio: self.makeAsset(audioUrl, headers: headers))
        } else if wantVideo, let m = muxedUrl {
          asset = self.makeAsset(m, headers: headers)
        } else {
          asset = self.makeAsset(audioUrl, headers: headers)
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard generation == self.loadGeneration, !Task.isCancelled else { return }

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        if let track = audioTracks.first, let mix = CarroAudioBridge.audioMix(for: track) {
          item.audioMix = mix
        }
        if wantVideo, let texture = self.videoTexture {
          texture.attach(to: item)
        }
        // Start position and auto-play are applied once the item is ready (seeking an
        // item that is not ready yet is not reliable).
        self.pendingStartMs = startMs > 0 ? startMs : nil
        self.pendingPlay = playWhenReady
        self.observe(item: item)
        self.player.replaceCurrentItem(with: item)
        self.loading = false
        self.applyBackgroundVideoState()
        self.sendState()
      } catch {
        guard generation == self.loadGeneration else { return }
        self.loading = false
        self.emitError(error)
      }
    }
    return newTextureId
  }

  private func observe(item: AVPlayerItem) {
    clearItemObservations()
    itemObservations.append(
      item.observe(\.status, options: [.new]) { [weak self] item, _ in
        DispatchQueue.main.async {
          guard let self else { return }
          if item.status == .failed {
            self.emitError(item.error)
          } else if item.status == .readyToPlay {
            self.applyBackgroundVideoState()
            self.startPendingPlayback()
          }
          self.sendState()
          self.updateNowPlayingPlayback()
        }
      })
    itemObservations.append(
      item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
        DispatchQueue.main.async {
          guard let self else { return }
          let size = item.presentationSize
          guard size.width > 0, size.height > 0, size != self.lastVideoSize else { return }
          self.lastVideoSize = size
          var event: [String: Any] = ["type": "video", "width": Int(size.width), "height": Int(size.height)]
          if let id = self.textureId { event["textureId"] = NSNumber(value: id) }
          self.emit?(event)
        }
      })
  }

  private func startPendingPlayback() {
    let play = pendingPlay
    pendingPlay = false
    if let ms = pendingStartMs {
      pendingStartMs = nil
      let time = CMTime(seconds: ms / 1000.0, preferredTimescale: 1000)
      player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        DispatchQueue.main.async {
          if play { self?.startPlayback() }
          self?.sendState()
          self?.updateNowPlayingPlayback()
        }
      }
    } else if play {
      startPlayback()
    }
  }

  private func clearItemObservations() {
    itemObservations.forEach { $0.invalidate() }
    itemObservations.removeAll()
  }

  private func releaseTexture() {
    if let texture = videoTexture {
      texture.dispose()
    }
    if let id = textureId {
      textures.unregisterTexture(id)
    }
    videoTexture = nil
    textureId = nil
  }

  private func stop() {
    loadGeneration += 1
    loadTask?.cancel()
    loading = false
    player.pause()
    clearItemObservations()
    player.replaceCurrentItem(with: nil)
    releaseTexture()
    ended = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    nowPlaying = [:]
    pendingStartMs = nil
    pendingPlay = false
    sendState()
  }

  private func seek(toMs ms: Double) {
    ended = false
    let time = CMTime(seconds: max(0, ms) / 1000.0, preferredTimescale: 1000)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      DispatchQueue.main.async {
        self?.sendState()
        self?.updateNowPlayingPlayback()
      }
    }
  }

  // MARK: - State events

  func sendState() {
    var state = "idle"
    if let item = player.currentItem {
      switch item.status {
      case .failed:
        state = "error"
      case .unknown:
        state = "loading"
      case .readyToPlay:
        state = player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "buffering" : "ready"
      @unknown default:
        state = "loading"
      }
      if ended { state = "ended" }
    } else if loading {
      state = "loading"
    }
    let position = finiteMs(player.currentTime())
    var duration = 0.0
    var buffered = 0.0
    if let item = player.currentItem {
      duration = finiteMs(item.duration)
      if let range = item.loadedTimeRanges.last?.timeRangeValue {
        buffered = finiteMs(CMTimeAdd(range.start, range.duration))
      }
    }
    emit?([
      "type": "state",
      "state": state,
      "playing": player.timeControlStatus != .paused,
      "positionMs": Int(position),
      "durationMs": Int(duration),
      "bufferedMs": Int(buffered),
      "rate": Double(player.rate == 0 ? desiredRate : player.rate),
    ])
  }

  private func finiteMs(_ t: CMTime) -> Double {
    let s = t.seconds
    return s.isFinite && s >= 0 ? s * 1000.0 : 0
  }

  private func emitError(_ error: Error?) {
    let ns = error as NSError?
    var status = 0
    if let log = player.currentItem?.errorLog()?.events.last {
      status = log.errorStatusCode
    }
    emit?([
      "type": "error",
      "code": isLocal ? "file" : "source",
      "message": ns?.localizedDescription ?? "Playback failed",
      "httpStatus": status,
    ])
    sendState()
  }

  // MARK: - Notifications (end, errors, interruptions, routes, background)

  private func installNotifications() {
    let nc = NotificationCenter.default
    notificationTokens.append(
      nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
        guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
        self.ended = true
        self.sendState()
        self.updateNowPlayingPlayback()
      })
    notificationTokens.append(
      nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
        guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
        self.emitError(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
      })
    notificationTokens.append(
      nc.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: nil, queue: .main) { [weak self] note in
        guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem,
          let event = item.errorLog()?.events.last
        else { return }
        // An expired YouTube URL answers 403/410: let Dart re-resolve it.
        if event.errorStatusCode == 403 || event.errorStatusCode == 410 {
          self.emit?([
            "type": "error", "code": "http", "message": "HTTP \(event.errorStatusCode)",
            "httpStatus": event.errorStatusCode,
          ])
        }
      })
    notificationTokens.append(
      nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
        [weak self] note in
        self?.handleInterruption(note)
      })
    notificationTokens.append(
      nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
        self?.handleRouteChange(note)
      })
    notificationTokens.append(
      nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.sessionConfigured = false
        self?.configureSession()
      })
    notificationTokens.append(
      nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.inBackground = true
        self?.applyBackgroundVideoState()
        self?.emit?(["type": "background", "background": true])
      })
    notificationTokens.append(
      nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.inBackground = false
        self?.applyBackgroundVideoState()
        self?.emit?(["type": "background", "background": false])
      })
  }

  private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    switch type {
    case .began:
      wasPlayingBeforeInterruption = player.timeControlStatus != .paused
      emit?(["type": "interruption", "began": true, "shouldResume": false])
    case .ended:
      var shouldResume = false
      if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
        shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
      }
      if shouldResume && wasPlayingBeforeInterruption {
        startPlayback()
      }
      emit?(["type": "interruption", "began": false, "shouldResume": shouldResume])
    @unknown default:
      break
    }
    sendState()
  }

  private func handleRouteChange(_ note: Notification) {
    guard let info = note.userInfo,
      let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
    else { return }
    switch reason {
    case .oldDeviceUnavailable:
      // Headphones unplugged / Bluetooth or car disconnected -> pause (iOS convention).
      if player.timeControlStatus != .paused {
        pausedByRouteLoss = true
      }
      player.pause()
      emit?(["type": "route", "reason": "unplugged"])
    case .newDeviceAvailable:
      let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType }
      let carOrBt = outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio].contains($0) }
      if resumeOnBluetooth && pausedByRouteLoss && carOrBt && player.currentItem != nil {
        pausedByRouteLoss = false
        startPlayback()
      }
      emit?(["type": "route", "reason": "connected"])
    default:
      break
    }
    sendState()
  }

  // MARK: - Background video handling

  private func setVideoTracks(enabled: Bool) {
    guard let item = player.currentItem else { return }
    for track in item.tracks where track.assetTrack?.mediaType == .video {
      track.isEnabled = enabled
    }
    videoTexture?.setPaused(!enabled)
  }

  private func applyBackgroundVideoState() {
    guard withVideo else { return }
    let pipActive = pipController?.isPictureInPictureActive ?? false
    setVideoTracks(enabled: !inBackground || pipActive)
  }

  // MARK: - Picture in picture

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func startPip(rect: CGRect) -> Bool {
    guard withVideo, AVPictureInPictureController.isPictureInPictureSupported(),
      let host = keyWindow()?.rootViewController?.view
    else { return false }
    let layer = playerLayer ?? AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    layer.frame = rect
    if layer.superlayer == nil {
      host.layer.addSublayer(layer)
    }
    playerLayer = layer
    if pipController == nil {
      guard let controller = AVPictureInPictureController(playerLayer: layer) else { return false }
      controller.delegate = self
      controller.canStartPictureInPictureAutomaticallyFromInline = true
      pipController = controller
    }
    guard let controller = pipController else { return false }
    if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    } else {
      pendingPipStart = true
      pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
        [weak self] c, _ in
        DispatchQueue.main.async {
          guard let self, self.pendingPipStart, c.isPictureInPicturePossible else { return }
          self.pendingPipStart = false
          c.startPictureInPicture()
        }
      }
    }
    return true
  }

  private func tearDownPip() {
    pipPossibleObservation?.invalidate()
    pipPossibleObservation = nil
    pendingPipStart = false
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    pipController = nil
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    playerLayer?.opacity = 0
    emit?(["type": "pip", "active": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    tearDownPip()
    applyBackgroundVideoState()
    emit?(["type": "pip", "active": false])
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error
  ) {
    tearDownPip()
    emit?(["type": "pip", "active": false])
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }

  // MARK: - Lock screen / Control Center / CarPlay now-playing, steering-wheel buttons

  private func configureRemoteCommands() {
    guard !remoteConfigured else { return }
    remoteConfigured = true
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let c = MPRemoteCommandCenter.shared()
    c.playCommand.addTarget { [weak self] _ in
      guard let self, self.player.currentItem != nil else { return .noActionableNowPlayingItem }
      self.startPlayback()
      return .success
    }
    c.pauseCommand.addTarget { [weak self] _ in
      self?.player.pause()
      return .success
    }
    c.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      if self.player.timeControlStatus == .paused {
        self.startPlayback()
      } else {
        self.player.pause()
      }
      return .success
    }
    c.stopCommand.addTarget { [weak self] _ in
      self?.player.pause()
      return .success
    }
    c.nextTrackCommand.addTarget { [weak self] _ in
      self?.emit?(["type": "remote", "command": "next"])
      return .success
    }
    c.previousTrackCommand.addTarget { [weak self] _ in
      self?.emit?(["type": "remote", "command": "previous"])
      return .success
    }
    c.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self.seek(toMs: e.positionTime * 1000)
      self.emit?(["type": "remote", "command": "seek", "positionMs": Int(e.positionTime * 1000)])
      return .success
    }
    // Show previous/next (not +-15 s) on the lock screen and car displays.
    c.skipForwardCommand.isEnabled = false
    c.skipBackwardCommand.isEnabled = false
    c.nextTrackCommand.isEnabled = false
    c.previousTrackCommand.isEnabled = true
    c.changePlaybackPositionCommand.isEnabled = true
  }

  private func updateNowPlayingMetadata(_ args: [String: Any]) {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: args["title"] as? String ?? "",
      MPMediaItemPropertyArtist: args["artist"] as? String ?? "",
      MPNowPlayingInfoPropertyMediaType: NSNumber(
        value: (args["video"] as? Bool ?? false) ? MPNowPlayingInfoMediaType.video.rawValue
          : MPNowPlayingInfoMediaType.audio.rawValue),
      MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: 0),
      MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 0),
    ]
    if let ms = (args["durationMs"] as? NSNumber)?.doubleValue, ms > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: ms / 1000.0)
    }
    nowPlaying = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    artworkTask?.cancel()
    guard let s = args["artworkUrl"] as? String, let url = URL(string: s) else { return }
    let expectedTitle = info[MPMediaItemPropertyTitle] as? String
    artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, (self.nowPlaying[MPMediaItemPropertyTitle] as? String) == expectedTitle else { return }
        self.nowPlaying[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlaying
      }
    }
    artworkTask?.resume()
  }

  private func updateNowPlayingPlayback() {
    guard !nowPlaying.isEmpty else { return }
    nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: finiteMs(player.currentTime()) / 1000.0)
    nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: player.rate)
    if let item = player.currentItem {
      let d = finiteMs(item.duration)
      if d > 0 { nowPlaying[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: d / 1000.0) }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
  }
}
