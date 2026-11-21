import CoreLocation
import Flutter
import LocalAuthentication
import UIKit

/// The app lock and the cover for the app switcher, for lib/lock/lock.dart, on `upon_thy_head/lock`.
///
/// Methods (Dart → iOS):
///  - `method` → how this phone can unlock: "faceID", "touchID", "opticID", "passcode", or "none"
///    when nothing is set up (no passcode), so the app cannot lock
///  - `authenticate` {reason} → true when the person proved it is them (Face ID, Touch ID, or the
///    passcode as fallback); false when cancelled or failed. Failures and lockouts are the system's.
///  - `cover` {on}: whether the plain sky covers the app whenever it leaves the foreground
///  - `version` → "0.1.0 (1)"
///  - `openSettings`: this app's page in the Settings app
/// Events (iOS → Dart): `active` {away, background}: the app is in front again; `away` is the
/// seconds since it went to the background (0 if it only went inactive). The cover is lifted when
/// Dart answers, so a lock decided there is drawn before anything else shows.
enum LockChannel {
  static var channel: FlutterMethodChannel?

  /// The cover is wanted (the lock is on).
  static var coverOn = false

  /// A system sheet the app raised itself (Face ID, a permission prompt) is up: the app goes
  /// inactive under it, but what is behind it is not private, so it is not covered for that.
  static var systemPrompt = 0

  static var leftAt: Date?
  static var cover: UIImageView?
  static var observers: [NSObjectProtocol] = []

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/lock", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
    observeScenes()
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "method":
      result(method())
    case "authenticate":
      let reason = args["reason"] as? String ?? "Unlock"
      let context = LAContext()
      var error: NSError?
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        NSLog("lock: cannot authenticate: %@", error?.localizedDescription ?? "?")
        return result(false)
      }
      systemPrompt += 1
      context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
        DispatchQueue.main.async {
          systemPrompt = max(0, systemPrompt - 1)
          if let error { NSLog("lock: %@", error.localizedDescription) }
          result(ok)
        }
      }
    case "biometry":
      result(biometry())
    case "askBiometrics":
      // The first run's Face ID question: biometrics only, with no passcode fallback, so "Don't
      // Allow" ends it rather than bringing up the passcode. After the question, iOS runs one scan;
      // whatever the scan does, the answer to the question is what `biometry` reports afterwards.
      let reason = args["reason"] as? String ?? "Unlock"
      let context = LAContext()
      context.localizedFallbackTitle = ""
      var error: NSError?
      guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return result(biometry()) }
      systemPrompt += 1
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { _, error in
        DispatchQueue.main.async {
          systemPrompt = max(0, systemPrompt - 1)
          if let error { NSLog("lock: first run: %@", error.localizedDescription) }
          result(biometry())
        }
      }
    case "cover":
      coverOn = args["on"] as? Bool ?? false
      if !coverOn { lift() }
      result(nil)
    case "version":
      let info = Bundle.main.infoDictionary ?? [:]
      let v = info["CFBundleShortVersionString"] as? String ?? "?"
      let b = info["CFBundleVersion"] as? String ?? "?"
      result("\(v) (\(b))")
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
      result(nil)
    case "openPage":
      // Settings' Privacy and Terms, in Safari: only these two addresses, chosen by name. Safari
      // loads the page; the app itself makes no network call for it.
      let pages = ["privacy": "https://uponthyhead.app/privacy", "terms": "https://uponthyhead.app/terms"]
      if let page = pages[args["name"] as? String ?? ""], let url = URL(string: page) { UIApplication.shared.open(url) }
      result(nil)
    case "debugCovered":
      result(cover != nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// What can unlock this phone. Biometrics if enrolled, else the passcode; "none" without a passcode.
  static func method() -> String {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return "none" }
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "passcode" }
    switch context.biometryType {
    case .faceID: return "faceID"
    case .touchID: return "touchID"
    case .opticID: return "opticID"
    default: return "passcode"
    }
  }

  /// What the first run's lock row shows: the kind of biometrics this phone has ("faceID",
  /// "touchID", "opticID", "none"), whether it can be used now ("ok"), was refused ("denied"), has
  /// nothing enrolled ("notEnrolled") or cannot be used ("unavailable"), and whether a passcode is set.
  static func biometry() -> [String: Any] {
    let context = LAContext()
    var error: NSError?
    let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let type: String
    switch context.biometryType {
    case .faceID: type = "faceID"
    case .touchID: type = "touchID"
    case .opticID: type = "opticID"
    default: type = "none"
    }
    var state = "ok"
    if !ok {
      switch (error as? LAError)?.code {
      case .biometryNotEnrolled: state = "notEnrolled"
      case .biometryNotAvailable: state = type == "none" ? "unavailable" : "denied"
      case .passcodeNotSet: state = "noPasscode"
      default: state = "unavailable"
      }
    }
    let passcode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    return ["type": type, "state": state, "passcode": passcode]
  }

  // ---- the cover ----

  static func observeScenes() {
    let nc = NotificationCenter.default
    observers = [
      nc.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { n in
        if systemPrompt == 0 { place(on: n.object as? UIWindowScene) }
      },
      nc.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { n in
        leftAt = Date()
        // whatever was up, the snapshot the system takes now must show only the sky
        place(on: n.object as? UIWindowScene)
      },
      nc.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
        let away = leftAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let background = leftAt != nil
        leftAt = nil
        guard let channel else { return lift() }
        var lifted = false
        let liftOnce = {
          if lifted { return }
          lifted = true
          lift()
        }
        channel.invokeMethod("active", arguments: ["away": away, "background": background]) { _ in liftOnce() }
        // never leave the app covered if Dart does not answer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { liftOnce() }
      },
    ]
  }

  /// The plain sky (assets/sky/cover.jpg: the locked sky with nothing drawn over it) over everything.
  static func place(on scene: UIWindowScene?) {
    guard coverOn, cover == nil else { return }
    guard let window = (scene ?? activeScene())?.windows.first(where: { $0.isKeyWindow }) ?? activeScene()?.windows.first else { return }
    let view = UIImageView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.contentMode = .scaleAspectFill
    view.clipsToBounds = true
    view.backgroundColor = UIColor(red: 0x0B / 255, green: 0x09 / 255, blue: 0x07 / 255, alpha: 1)
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sky/cover.jpg")
    if let path = Bundle.main.path(forResource: key, ofType: nil) { view.image = UIImage(contentsOfFile: path) }
    view.accessibilityElementsHidden = true
    window.addSubview(view)
    cover = view
  }

  static func lift() {
    cover?.removeFromSuperview()
    cover = nil
  }

  static func activeScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  }
}

/// Where blessings are given, for lib/place/where.dart, on `upon_thy_head/location`.
///
/// Only an approximate place is ever asked for (Info.plist: NSLocationDefaultAccuracyReduced), and
/// Dart keeps it rounded to a tenth of a degree.
///  - `status` → "undetermined", "denied", "restricted" or "granted"
///  - `request` → the status after the person answers the system's question (asked only if undetermined)
///  - `locate` → {lat, lon}, or null when no place came within 15 seconds or it is not allowed
final class LocationChannel: NSObject, CLLocationManagerDelegate {
  static let shared = LocationChannel()
  static var channel: FlutterMethodChannel?

  private let manager = CLLocationManager()
  private var answered: [(String) -> Void] = []
  private var located: [([String: Double]?) -> Void] = []

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/location", binaryMessenger: messenger)
    c.setMethodCallHandler { call, result in shared.handle(call, result) }
    channel = c
  }

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyReduced
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(status())
    case "request":
      guard manager.authorizationStatus == .notDetermined else { return result(status()) }
      answered.append { result($0) }
      LockChannel.systemPrompt += 1
      manager.requestWhenInUseAuthorization()
    case "locate":
      guard status() == "granted" else { return result(nil) }
      located.append { result($0) }
      if located.count == 1 { manager.requestLocation() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.settle(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func status() -> String {
    switch manager.authorizationStatus {
    case .notDetermined: return "undetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    default: return "granted"
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined, !answered.isEmpty else { return }
    LockChannel.systemPrompt = max(0, LockChannel.systemPrompt - 1)
    let s = status()
    let waiting = answered
    answered = []
    waiting.forEach { $0(s) }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let c = locations.last?.coordinate else { return }
    settle(["lat": c.latitude, "lon": c.longitude])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("location: %@", error.localizedDescription)
    settle(nil)
  }

  private func settle(_ place: [String: Double]?) {
    let waiting = located
    located = []
    waiting.forEach { $0(place) }
  }
}
