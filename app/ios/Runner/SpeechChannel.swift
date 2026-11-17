import AVFoundation
import Flutter
import Speech
import UIKit

/// The recording and its words, for lib/record/speech.dart, on the channel `upon_thy_head/speech`.
///
/// Methods (Dart → iOS):
///  - `permissions` → {"microphone": s, "speech": s}, each "granted", "denied" or "undetermined"
///  - `requestPermissions` → the same, after asking for whatever is undetermined
///  - `openSettings`
///  - `engine` {language} → {"engine", "locale"} or null; also starts any model download
///  - `describe` → what the device reports about each engine (for the report)
///  - `start` {path} : listen to the microphone into the file at path (.m4a)
///  - `stop` → the path of the finished file (the parts joined)
///  - `cancel` : stop and delete everything recorded
///  - `recover` {path} → {"path", "seconds"} or null: at launch, join the parts of a recording the
///    app was closed during into the file at path (see `SegmentRecorder.recover`)
///  - `seconds` {path} → the length of the audio in a file
///  - `transcribe` {path, language} → {"text", "engine", "locale"}; error "unavailable" when no
///    engine on this phone can write the language
///  - `debugInterrupt` {began} : behave as if the system interrupted the audio (tests only)
///  - `debugFeed` {path} : at `stop`, the finished file is replaced by a copy of this one, so a
///    test hears the same words every time (tests only)
/// Events (iOS → Dart): `paused` {bool}, while the system has the microphone (a call, Siri).
enum SpeechChannel {
  static var channel: FlutterMethodChannel?
  static let recorder = SegmentRecorder()

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/speech", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
    recorder.onPaused = { paused in channel?.invokeMethod("paused", arguments: paused) }
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "permissions":
      result(permissions())
    case "requestPermissions":
      requestPermissions { result(permissions()) }
    case "requestMicrophone":
      // the first run asks each on its own, so its row can light while the question is up
      guard AVAudioApplication.shared.recordPermission == .undetermined else { return result(permissions()) }
      LockChannel.systemPrompt += 1
      AVAudioApplication.requestRecordPermission { _ in
        DispatchQueue.main.async {
          LockChannel.systemPrompt = max(0, LockChannel.systemPrompt - 1)
          result(permissions())
        }
      }
    case "requestSpeech":
      guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return result(permissions()) }
      LockChannel.systemPrompt += 1
      SFSpeechRecognizer.requestAuthorization { _ in
        DispatchQueue.main.async {
          LockChannel.systemPrompt = max(0, LockChannel.systemPrompt - 1)
          result(permissions())
        }
      }
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
      result(nil)
    case "engine":
      let language = args["language"] as? String ?? "en"
      Task {
        let chosen = await OnDeviceSpeech.choose(language)
        await MainActor.run {
          result(chosen.map { ["engine": $0.0.rawValue, "locale": $0.1] })
        }
        await OnDeviceSpeech.prepare(language)
      }
    case "describe":
      Task {
        let d = await OnDeviceSpeech.describe()
        await MainActor.run { result(d) }
      }
    case "start":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      do {
        try recorder.start(URL(fileURLWithPath: path))
        result(nil)
      } catch {
        result(FlutterError(code: "record", message: "\(error)", details: nil))
      }
    case "stop":
      recorder.stop { r in
        switch r {
        case .success(let url): result(url.path)
        case .failure(let e): result(FlutterError(code: "record", message: "\(e)", details: nil))
        }
      }
    case "cancel":
      recorder.cancel()
      result(nil)
    case "recover":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      SegmentRecorder.recover(URL(fileURLWithPath: path)) { r in
        DispatchQueue.main.async {
          switch r {
          case .success(let got): result(got.map { ["path": $0.0.path, "seconds": $0.1] })
          case .failure(let e): result(FlutterError(code: "record", message: "\(e)", details: nil))
          }
        }
      }
    case "seconds":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      result(SegmentRecorder.seconds(URL(fileURLWithPath: path)))
    case "transcribe":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      let language = args["language"] as? String ?? "en"
      OnDeviceSpeech.verbose = args["trace"] as? Bool ?? false
      OnDeviceSpeech.trace = []
      Task {
        let t0 = Date()
        do {
          let w = try await OnDeviceSpeech.transcribe(URL(fileURLWithPath: path), language: language)
          let ms = Int(Date().timeIntervalSince(t0) * 1000)
          NSLog("speech: %@ %@ in %d ms", w.engine.rawValue, w.locale, ms)
          await MainActor.run { result(["text": w.text, "engine": w.engine.rawValue, "locale": w.locale, "ms": ms, "trace": OnDeviceSpeech.trace]) }
        } catch OnDeviceSpeech.Failure.unavailable(let why) {
          await MainActor.run { result(FlutterError(code: "unavailable", message: why, details: nil)) }
        } catch {
          await MainActor.run { result(FlutterError(code: "failed", message: "\(error)", details: nil)) }
        }
      }
    case "debugInterrupt":
      recorder.interrupted(began: args["began"] as? Bool ?? true, shouldResume: true)
      result(nil)
    case "debugFeed":
      recorder.feed = (args["path"] as? String).map { URL(fileURLWithPath: $0) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func permissions() -> [String: String] {
    let mic: String
    switch AVAudioApplication.shared.recordPermission {
    case .granted: mic = "granted"
    case .denied: mic = "denied"
    default: mic = "undetermined"
    }
    let speech: String
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: speech = "granted"
    case .denied, .restricted: speech = "denied"
    default: speech = "undetermined"
    }
    return ["microphone": mic, "speech": speech]
  }

  /// The microphone first, then speech, each only if not yet asked.
  static func requestPermissions(_ finished: @escaping () -> Void) {
    // the system's questions are not private: the app is not covered under them (Privacy.swift)
    LockChannel.systemPrompt += 1
    let done = {
      LockChannel.systemPrompt = max(0, LockChannel.systemPrompt - 1)
      finished()
    }
    let speech = {
      if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
        SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async(execute: done) }
      } else {
        DispatchQueue.main.async(execute: done)
      }
    }
    if AVAudioApplication.shared.recordPermission == .undetermined {
      AVAudioApplication.requestRecordPermission { _ in DispatchQueue.main.async(execute: speech) }
    } else {
      speech()
    }
  }
}

/// Records the microphone to a compact file (AAC, 32 kHz, mono, see `settings`).
///
/// Each part is written as ADTS AAC (`<id>.partN.aac`): a stream of self-contained frames with no
/// index at the end, so a part that is never closed (the app killed, the battery gone) can still be
/// read up to its last whole frame. An .m4a cannot: its index is written only when it is closed, and
/// without it the file does not open at all (measured on the simulator, 2026-11-15).
///
/// A recording is kept in parts. Whenever the system takes the microphone (a phone call, Siri, an
/// alarm), the part so far is closed so it is complete on disk whatever happens next, and a new
/// part starts when the microphone is given back. `stop` joins the parts into the one file.
/// The app keeps recording in the background (UIBackgroundModes audio), so locking the phone or
/// leaving the app does not stop it.
final class SegmentRecorder: NSObject, AVAudioRecorderDelegate {
  /// AAC at 32 kHz mono, 24 kbit/s: about 11 MB an hour. Both recognisers read it.
  ///
  /// The recorder writes to disk every 64 AAC frames of 1024 samples (measured on the simulator), so
  /// the sample rate sets how much a kill can lose: 4.2 s at 16 kHz, 2.4 s at 32 kHz, 1.4 s at
  /// 48 kHz. 32 kHz keeps the loss to about two seconds at the same bit rate, so the same file size.
  static let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 32_000,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 24_000,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
  ]

  var onPaused: ((Bool) -> Void)?
  var feed: URL?

  private var target: URL?
  private var parts: [URL] = []
  private var recorder: AVAudioRecorder?
  private(set) var paused = false
  private var observing = false

  func start(_ url: URL) throws {
    cancel()
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // the audio never leaves the phone: not even in an iCloud or computer backup
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var d = dir
    try? d.setResourceValues(values)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .default, options: [])
    try session.setActive(true)
    target = url
    parts = []
    paused = false
    if !observing {
      observing = true
      NotificationCenter.default.addObserver(self, selector: #selector(onInterruption), name: AVAudioSession.interruptionNotification, object: session)
      NotificationCenter.default.addObserver(self, selector: #selector(onActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    try startPart()
  }

  private func startPart() throws {
    guard let target else { return }
    let part = Self.partURL(target, parts.count + 1)
    try? FileManager.default.removeItem(at: part)
    let r = try AVAudioRecorder(url: part, settings: Self.settings)
    r.delegate = self
    guard r.record() else { throw NSError(domain: "record", code: 1, userInfo: [NSLocalizedDescriptionKey: "the recorder would not start"]) }
    recorder = r
    parts.append(part)
  }

  static func partURL(_ target: URL, _ n: Int) -> URL {
    target.deletingPathExtension().appendingPathExtension("part\(n).aac")
  }

  /// The parts of the recording that would end at [target], in order: `<id>.part1.aac`, ….
  static func partsOnDisk(_ target: URL) -> [URL] {
    let dir = target.deletingLastPathComponent()
    let id = target.deletingPathExtension().lastPathComponent
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    let numbered: [(Int, URL)] = names.compactMap { n in
      guard n.hasPrefix("\(id).part"), n.hasSuffix(".aac") else { return nil }
      let mid = n.dropFirst(id.count + 5).dropLast(4)
      guard let i = Int(mid) else { return nil }
      return (i, dir.appendingPathComponent(n))
    }
    return numbered.sorted { $0.0 < $1.0 }.map { $0.1 }
  }

  /// Close the part being written, so it is complete on disk.
  private func closePart() {
    recorder?.stop()
    recorder = nil
  }

  @objc private func onInterruption(_ n: Notification) {
    guard let info = n.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
    interrupted(began: type == .began, shouldResume: options.contains(.shouldResume))
  }

  func interrupted(began: Bool, shouldResume: Bool) {
    guard target != nil else { return }
    if began {
      if paused { return }
      closePart()
      paused = true
      NSLog("speech: interrupted; %d part(s) kept", parts.count)
      onPaused?(true)
    } else if paused, shouldResume || UIApplication.shared.applicationState == .active {
      resume()
    }
  }

  /// Back in the app after an interruption that did not hand the microphone back.
  @objc private func onActive() {
    if target != nil && paused { resume() }
  }

  private func resume() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      try startPart()
      paused = false
      NSLog("speech: listening again, part %d", parts.count)
      onPaused?(false)
    } catch {
      NSLog("speech: could not listen again yet: %@", "\(error)")
    }
  }

  func stop(_ done: @escaping (Result<URL, Error>) -> Void) {
    guard let target else { return done(.failure(NSError(domain: "record", code: 2, userInfo: [NSLocalizedDescriptionKey: "not recording"]))) }
    closePart()
    let parts = self.parts.filter { FileManager.default.fileExists(atPath: $0.path) }
    self.target = nil
    self.parts = []
    paused = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    let finish: (Result<URL, Error>) -> Void = { r in
      // tests: the words they expect, in place of the room's
      if case .success(let url) = r, let feed = self.feed {
        try? FileManager.default.removeItem(at: url)
        do { try FileManager.default.copyItem(at: feed, to: url) } catch { return DispatchQueue.main.async { done(.failure(error)) } }
      }
      DispatchQueue.main.async { done(r) }
    }
    try? FileManager.default.removeItem(at: target)
    Self.join(parts, into: target) { r in
      if case .success = r { parts.forEach { try? FileManager.default.removeItem(at: $0) } }
      finish(r)
    }
  }

  /// At launch: the recording that would have ended at [target] when the app was closed before Amen.
  /// Its parts on disk are joined into [target] and removed. A part that was never closed is read up
  /// to its last whole frame. If there are no parts but [target] is there and plays (the app closed
  /// after the parts were joined), that is the recording. Done with the file and its length in
  /// seconds; nil when nothing was recorded (every file empty), after removing the empty parts. On a
  /// failure everything is left on disk for the next launch.
  static func recover(_ target: URL, _ done: @escaping (Result<(URL, Double)?, Error>) -> Void) {
    let fm = FileManager.default
    let parts = partsOnDisk(target)
    let heard = parts.filter { seconds($0) > 0 }
    if heard.isEmpty {
      parts.forEach { try? fm.removeItem(at: $0) }
      let s = fm.fileExists(atPath: target.path) ? seconds(target) : 0
      if s > 0 { return done(.success((target, s))) }
      try? fm.removeItem(at: target)
      return done(.success(nil))
    }
    // a joined file from a join that was cut short is replaced by joining again
    try? fm.removeItem(at: target)
    join(heard, into: target) { r in
      switch r {
      case .success(let url):
        parts.forEach { try? fm.removeItem(at: $0) }
        done(.success((url, seconds(url))))
      case .failure(let e):
        done(.failure(e))
      }
    }
  }

  /// The length of the audio in the file, read to the end (an ADTS file has no index to ask).
  static func seconds(_ url: URL) -> Double {
    guard let a = try? AVAudioFile(forReading: url) else { return 0 }
    let n = Double(a.length) / a.processingFormat.sampleRate
    return n.isFinite ? n : 0
  }

  func cancel() {
    closePart()
    for p in parts { try? FileManager.default.removeItem(at: p) }
    if let target { try? FileManager.default.removeItem(at: target) }
    parts = []
    target = nil
    paused = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  /// The parts one after another in a single .m4a. The AAC frames are copied as they are, not
  /// encoded again, so this is quick and loses nothing. On failure the parts are left on disk.
  static func join(_ parts: [URL], into out: URL, _ done: @escaping (Result<URL, Error>) -> Void) {
    export(parts, into: out, preset: AVAssetExportPresetPassthrough) { r in
      if case .failure(let e) = r {
        NSLog("speech: copying the parts failed (%@); encoding them instead", "\(e)")
        try? FileManager.default.removeItem(at: out)
        return export(parts, into: out, preset: AVAssetExportPresetAppleM4A, done)
      }
      done(r)
    }
  }

  private static func export(_ parts: [URL], into out: URL, preset: String, _ done: @escaping (Result<URL, Error>) -> Void) {
    Task {
      let comp = AVMutableComposition()
      guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        return done(.failure(NSError(domain: "record", code: 3, userInfo: [NSLocalizedDescriptionKey: "no audio track"])))
      }
      var at = CMTime.zero
      do {
        for p in parts {
          let asset = AVURLAsset(url: p, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
          guard let src = try await asset.loadTracks(withMediaType: .audio).first else { continue }
          let duration = try await asset.load(.duration)
          try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: src, at: at)
          at = at + duration
        }
      } catch {
        return done(.failure(error))
      }
      // Nothing to join (the recorder never started, or every part is empty): say so. Handing
      // AVAssetExportSession an empty composition crashes inside it, seen on the simulator.
      guard at.seconds > 0 else {
        return done(.failure(NSError(domain: "record", code: 6, userInfo: [NSLocalizedDescriptionKey: "nothing was recorded"])))
      }
      exportComposition(comp, into: out, preset: preset, done)
    }
  }

  private static func exportComposition(_ comp: AVMutableComposition, into out: URL, preset: String, _ done: @escaping (Result<URL, Error>) -> Void) {
    guard let export = AVAssetExportSession(asset: comp, presetName: preset) else {
      return done(.failure(NSError(domain: "record", code: 4, userInfo: [NSLocalizedDescriptionKey: "no exporter"])))
    }
    export.outputURL = out
    export.outputFileType = .m4a
    export.exportAsynchronously {
      if export.status == .completed {
        done(.success(out))
      } else {
        done(.failure(export.error ?? NSError(domain: "record", code: 5, userInfo: [NSLocalizedDescriptionKey: "export \(export.status.rawValue)"])))
      }
    }
  }
}
