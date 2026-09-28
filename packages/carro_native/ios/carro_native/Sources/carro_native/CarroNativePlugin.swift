import AVFoundation
import Flutter
import UIKit

#if canImport(CarroDSP)
  import CarroDSP
#endif

/// Flutter entry point of the native layer.
///
/// Channels
///   carro/player          (method)  transport, loading, PiP, remote-control options
///   carro/player/events   (event)   state / error / remote / video / pip / interruption / route
///   carro/system          (method)  device info, battery optimisation stubs (Android only)
///   carro/ircapture       (method)  sweep playback + input recording for the IR wizard
///
/// The DSP itself is driven from Dart through dart:ffi; the player's MTAudioProcessingTap
/// feeds every rendered sample through the same engine instance.
public final class CarroNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let player: CarroPlayer
  private let capture = CarroIRCapture()
  private var eventSink: FlutterEventSink?

  init(registrar: FlutterPluginRegistrar) {
    player = CarroPlayer(textures: registrar.textures())
    super.init()
    player.emit = { [weak self] event in
      if Thread.isMainThread {
        self?.eventSink?(event)
      } else {
        DispatchQueue.main.async { self?.eventSink?(event) }
      }
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Touch the C++ object code so the linker keeps it (its C symbols are looked up by
    // dart:ffi at runtime) and give the engine a sane default rate until a track plays.
    _ = CarroAudioBridge.engineVersion()
    CarroAudioBridge.prepare(withSampleRate: 48000, maxFrames: 4096)

    let instance = CarroNativePlugin(registrar: registrar)
    let messenger = registrar.messenger()

    let playerChannel = FlutterMethodChannel(name: "carro/player", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: playerChannel)

    let events = FlutterEventChannel(name: "carro/player/events", binaryMessenger: messenger)
    events.setStreamHandler(instance)

    let system = FlutterMethodChannel(name: "carro/system", binaryMessenger: messenger)
    system.setMethodCallHandler { call, result in
      instance.handleSystem(call, result: result)
    }

    let ir = FlutterMethodChannel(name: "carro/ircapture", binaryMessenger: messenger)
    ir.setMethodCallHandler { call, result in
      instance.capture.handle(call, result: result, player: instance.player)
    }
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    player.handle(call, result: result)
  }

  // MARK: FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    player.sendState()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: carro/system

  private func handleSystem(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "deviceInfo":
      let d = UIDevice.current
      result([
        "manufacturer": "Apple",
        "model": d.model,
        "os": "iOS",
        "osVersion": d.systemVersion,
        "name": d.name,
      ])
    case "isIgnoringBatteryOptimizations":
      result(true)  // iOS keeps audio apps alive via UIBackgroundModes=audio
    case "requestIgnoreBatteryOptimizations":
      result(nil)
    case "openVendorBackgroundSettings":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

extension CarroNativePlugin {
  public func applicationWillTerminate(_ application: UIApplication) {
    player.shutdown()
  }
}
