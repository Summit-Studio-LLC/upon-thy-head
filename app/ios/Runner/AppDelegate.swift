import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // the app's two Spotlight entries (Shortcuts.swift): fixed words only, nothing of any blessing
    SpotlightEntry.write()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeepAwake") {
      KeepAwake.register(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Speech") {
      SpeechChannel.register(messenger: registrar.messenger())
      Playback.register(messenger: registrar.messenger())
      LockChannel.register(messenger: registrar.messenger())
      LocationChannel.register(messenger: registrar.messenger())
      ShareChannel.register(messenger: registrar.messenger(), registrar: registrar)
      LinkChannel.register(messenger: registrar.messenger())
      ProofChannel.register(messenger: registrar.messenger())
      PhoneModelChannel.register(messenger: registrar.messenger())
      // only in builds made with --dart-define=PHONE_CHECK=true (it needs the bundled recordings)
      PhoneCheck.register(messenger: registrar.messenger())
      registrar.register(LanguageMenuFactory(messenger: registrar.messenger()), withId: "upon_thy_head/language_menu")
    }
  }
}

/// Keeps the screen from dimming and locking while a recording listens
/// (lib/record/keep_awake.dart). `set` takes a bool; `get` answers the current value.
enum KeepAwake {
  static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/keep_awake", binaryMessenger: messenger)
    c.setMethodCallHandler { call, result in
      if call.method == "get" {
        result(UIApplication.shared.isIdleTimerDisabled)
        return
      }
      guard call.method == "set", let on = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = on
        result(nil)
      }
    }
    channel = c
  }
}
