import AVFoundation
import CoreLocation
import Flutter
import Speech
import UIKit

/// The phone check's native half (lib/check/), on `upon_thy_head/check`.
///
/// Registered only when the app bundle holds the `phone_check` folder, which the build copies in
/// only for `--dart-define=PHONE_CHECK=true` (the "Phone check audio" build phase). A normal build
/// has no folder, so this channel never answers there.
///
/// Methods (Dart → iOS):
///  - `audio` → {"en": path, "es": path} of the prepared recordings in the bundle
///  - `arguments` → the launch arguments (`--open-phone-check` opens the page at launch)
///  - `device` → model identifier, iOS version, refresh rate, storage
///  - `engines` → what each engine reports for each locale (see `engines()`)
///  - `transcribe` {path, language, engine} → {text, locale, ms, seconds}; error "unavailable" or "failed"
///  - `download` {locale}: start the new engine's model download; `progress` {locale} → {fraction, done, error}
///  - `preciseLocation` → whether the person turned Precise Location on for the app
///  - `speechAuth` → "granted", "denied", "restricted" or "undetermined"
///  - `askMicrophone` → "granted" or "denied" (asks only for the microphone)
///  - `inspect` {path} → format, sample rate, channels, seconds, bytes, peak (dBFS)
///  - `partSeconds` {path} → seconds readable in part 1 of the recording that would end at path
///  - `backupExcluded` {path} → true, false, or null when the folder does not exist
///  - `log` {lines}: print the lines to the app's standard output (the console `tool/phone.sh --log` reads)
enum PhoneCheck {
  static var channel: FlutterMethodChannel?
  nonisolated(unsafe) static var downloads: [String: Any] = [:]
  nonisolated(unsafe) static var downloadErrors: [String: String] = [:]

  static var bundled: URL? { Bundle.main.url(forResource: "phone_check", withExtension: nil) }

  static func register(messenger: FlutterBinaryMessenger) {
    guard bundled != nil else { return }
    let c = FlutterMethodChannel(name: "upon_thy_head/check", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
    NSLog("phone check: present")
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let path = args["path"] as? String
    switch call.method {
    case "audio":
      guard let dir = bundled else { return result(nil) }
      result(["en": dir.appendingPathComponent("en.m4a").path, "es": dir.appendingPathComponent("es.m4a").path])
    case "device":
      result(device())
    case "arguments":
      result(ProcessInfo.processInfo.arguments)
    case "engines":
      Task {
        let e = await engines()
        await MainActor.run { result(e) }
      }
    case "transcribe":
      guard let path else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      let language = args["language"] as? String ?? "en"
      let engine = OnDeviceSpeech.Engine(rawValue: args["engine"] as? String ?? "") ?? .recognizer
      let url = URL(fileURLWithPath: path)
      Task {
        let t0 = Date()
        do {
          let w = try await OnDeviceSpeech.transcribe(url, language: language, force: engine, download: false)
          let ms = Int(Date().timeIntervalSince(t0) * 1000)
          let s = SegmentRecorder.seconds(url)
          await MainActor.run { result(["text": w.text, "locale": w.locale, "engine": w.engine.rawValue, "ms": ms, "seconds": s]) }
        } catch OnDeviceSpeech.Failure.unavailable(let why) {
          await MainActor.run { result(FlutterError(code: "unavailable", message: why, details: nil)) }
        } catch {
          await MainActor.run { result(FlutterError(code: "failed", message: "\(error)", details: nil)) }
        }
      }
    case "download":
      guard let locale = args["locale"] as? String else { return result(nil) }
      startDownload(locale)
      result(nil)
    case "progress":
      guard let locale = args["locale"] as? String else { return result(nil) }
      result(progress(locale))
    case "speechAuth":
      result(speechAuth())
    case "preciseLocation":
      result(CLLocationManager().accuracyAuthorization == .fullAccuracy)
    case "askMicrophone":
      let app = AVAudioApplication.shared
      if app.recordPermission == .undetermined {
        LockChannel.systemPrompt += 1
        AVAudioApplication.requestRecordPermission { ok in
          DispatchQueue.main.async {
            LockChannel.systemPrompt = max(0, LockChannel.systemPrompt - 1)
            result(ok ? "granted" : "denied")
          }
        }
      } else {
        result(app.recordPermission == .granted ? "granted" : "denied")
      }
    case "inspect":
      guard let path else { return result(nil) }
      DispatchQueue.global().async {
        let r = inspect(URL(fileURLWithPath: path))
        DispatchQueue.main.async { result(r) }
      }
    case "partSeconds":
      guard let path else { return result(nil) }
      let part = SegmentRecorder.partURL(URL(fileURLWithPath: path), 1)
      let bytes = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? Int) ?? 0
      result(["seconds": SegmentRecorder.seconds(part), "bytes": bytes, "exists": FileManager.default.fileExists(atPath: part.path)])
    case "backupExcluded":
      guard let path else { return result(nil) }
      let url = URL(fileURLWithPath: path, isDirectory: true)
      guard FileManager.default.fileExists(atPath: url.path) else { return result(nil) }
      result((try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false)
    case "log":
      for line in args["lines"] as? [String] ?? [] { print(line) }
      fflush(stdout)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func speechAuth() -> String {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    default: return "undetermined"
    }
  }

  static func device() -> [String: Any] {
    var info = utsname()
    uname(&info)
    let machine = withUnsafeBytes(of: &info.machine) { raw in
      String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
    let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    return [
      "machine": machine,
      // the simulator reports the Mac's machine; it says which phone it pretends to be here
      "simulated": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "",
      "simulatorName": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "",
      "name": UIDevice.current.model,
      "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
      "fps": screen?.maximumFramesPerSecond ?? 0,
      "free": values?.volumeAvailableCapacityForImportantUsage ?? -1,
      "total": values?.volumeTotalCapacity ?? -1,
      "memory": ProcessInfo.processInfo.physicalMemory,
    ]
  }

  /// For each locale the app might use: the new engine's state ("installed", "supported" = needs a
  /// download, "downloading", "unsupported"), and the older recogniser's ("on-device", "server only",
  /// "none"); then which engine and locale `OnDeviceSpeech.choose` picks for each language.
  static func engines() async -> [String: Any] {
    var out: [String: Any] = [:]
    let ids = OnDeviceSpeech.candidates.values.flatMap { $0 }
    var analyzer: [String: Any] = ["present": false]
    if #available(iOS 26, *) {
      analyzer["present"] = true
      analyzer["isAvailable"] = SpeechTranscriber.isAvailable
      var locales: [String: String] = [:]
      if SpeechTranscriber.isAvailable {
        let supported = await SpeechTranscriber.supportedLocales.map { OnDeviceSpeech.bcp47($0) }
        for id in ids {
          if !supported.contains(id) { locales[id] = "unsupported"; continue }
          let module = SpeechTranscriber(locale: Locale(identifier: id), preset: .transcription)
          switch await AssetInventory.status(forModules: [module]) {
          case .installed: locales[id] = "installed"
          case .downloading: locales[id] = "downloading"
          case .supported: locales[id] = "supported"
          default: locales[id] = "unsupported"
          }
        }
      }
      analyzer["locales"] = locales
    }
    out["analyzer"] = analyzer
    var recognizer: [String: String] = [:]
    for id in ids {
      guard let r = SFSpeechRecognizer(locale: Locale(identifier: id)) else { recognizer[id] = "none"; continue }
      recognizer[id] = r.supportsOnDeviceRecognition ? "on-device" : "server only"
    }
    out["recognizer"] = recognizer
    var chosen: [String: Any] = [:]
    for language in OnDeviceSpeech.candidates.keys {
      if let (engine, id) = await OnDeviceSpeech.choose(language) {
        chosen[language] = ["engine": engine.rawValue, "locale": id]
      }
    }
    out["chosen"] = chosen
    return out
  }

  static func startDownload(_ locale: String) {
    guard #available(iOS 26, *) else { return }
    downloadErrors[locale] = nil
    Task {
      let module = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
      do {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
          await MainActor.run { downloads[locale] = request }
          try await request.downloadAndInstall()
        }
        await MainActor.run { downloads[locale] = "done" }
      } catch {
        await MainActor.run {
          downloads[locale] = nil
          downloadErrors[locale] = "\(error)"
        }
      }
    }
  }

  static func progress(_ locale: String) -> [String: Any] {
    if let e = downloadErrors[locale] { return ["error": e, "done": false, "fraction": 0.0] }
    if let s = downloads[locale] as? String, s == "done" { return ["done": true, "fraction": 1.0] }
    if #available(iOS 26, *), let r = downloads[locale] as? AssetInstallationRequest {
      return ["done": false, "fraction": r.progress.fractionCompleted]
    }
    return ["done": false, "fraction": 0.0]
  }

  /// What is in an audio file: its format as stored, and the loudest sample in it.
  static func inspect(_ url: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    out["bytes"] = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    guard let f = try? AVAudioFile(forReading: url) else {
      out["error"] = "the file would not open"
      return out
    }
    let fmt = f.fileFormat
    let id = (fmt.settings[AVFormatIDKey] as? UInt32) ?? 0
    out["format"] = id == kAudioFormatMPEG4AAC ? "AAC" : id == kAudioFormatLinearPCM ? "PCM" : String(format: "%08x", id)
    out["sampleRate"] = fmt.sampleRate
    out["channels"] = fmt.channelCount
    out["seconds"] = Double(f.length) / f.processingFormat.sampleRate
    var peak: Float = 0
    let chunk: AVAudioFrameCount = 8192
    if let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: chunk) {
      while f.framePosition < f.length {
        do { try f.read(into: buf, frameCount: chunk) } catch { break }
        if buf.frameLength == 0 { break }
        guard let data = buf.floatChannelData else { break }
        for c in 0..<Int(buf.format.channelCount) {
          for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(data[c][i])) }
        }
      }
    }
    out["peak"] = peak > 0 ? Double(20 * log10(peak)) : -160.0
    return out
  }
}
