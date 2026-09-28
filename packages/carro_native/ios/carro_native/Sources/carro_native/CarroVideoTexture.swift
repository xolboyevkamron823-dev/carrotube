import AVFoundation
import Flutter
import QuartzCore

/// Breaks the CADisplayLink -> target retain cycle.
private final class DisplayLinkProxy: NSObject {
  weak var target: CarroVideoTexture?
  init(_ target: CarroVideoTexture) { self.target = target }
  @objc func tick() { target?.tick() }
}

/// Renders an AVPlayerItem's video frames into a Flutter texture
/// (AVPlayerItemVideoOutput -> CVPixelBuffer -> FlutterTexture).
final class CarroVideoTexture: NSObject, FlutterTexture {
  private weak var registry: FlutterTextureRegistry?
  var textureId: Int64 = 0
  private var output: AVPlayerItemVideoOutput?
  private var latest: CVPixelBuffer?
  private var displayLink: CADisplayLink?
  private let lock = NSLock()

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  func attach(to item: AVPlayerItem) {
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
    item.add(out)
    output = out
    startDisplayLink()
  }

  private func startDisplayLink() {
    displayLink?.invalidate()
    let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  func tick() {
    guard let out = output else { return }
    let time = out.itemTime(forHostTime: CACurrentMediaTime())
    guard out.hasNewPixelBuffer(forItemTime: time),
      let buffer = out.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    else { return }
    lock.lock()
    latest = buffer
    lock.unlock()
    registry?.textureFrameAvailable(textureId)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer = latest else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  /// Stops pulling frames (app in background, audio keeps playing).
  func setPaused(_ paused: Bool) {
    displayLink?.isPaused = paused
  }

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
    output = nil
    lock.lock()
    latest = nil
    lock.unlock()
  }
}
