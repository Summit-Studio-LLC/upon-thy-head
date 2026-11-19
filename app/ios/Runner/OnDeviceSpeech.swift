import AVFoundation
import Foundation
import Speech

/// Turns a recorded file into words on this device, and never anywhere else.
///
/// Two engines, chosen at run time:
///  - Apple's new engine (SpeechAnalyzer with SpeechTranscriber, iOS 26 / macOS 26) where the
///    device reports it available and supports the language;
///  - otherwise Apple's older recogniser (SFSpeechRecognizer) with `requiresOnDeviceRecognition`,
///    only where it says it can recognise that language on the device.
/// When neither can, `transcribe` throws `.unavailable` and nothing is sent anywhere.
///
/// No Flutter in this file: tool/speech_harness compiles it on a Mac as it is.
enum OnDeviceSpeech {
  enum Engine: String {
    case analyzer, recognizer
  }

  struct Words {
    var text: String
    var engine: Engine
    var locale: String
  }

  enum Failure: Error, CustomStringConvertible {
    /// No engine on this device can write this language without a server.
    case unavailable(String)
    /// The recogniser ran and failed.
    case failed(String)

    var description: String {
      switch self {
      case .unavailable(let s): return "unavailable: \(s)"
      case .failed(let s): return "failed: \(s)"
      }
    }
  }

  /// The locales tried, best first, for each language the app offers.
  static let candidates: [String: [String]] = [
    "en": ["en-US"],
    "es": ["es-US", "es-MX", "es-ES"],
  ]

  /// A silence at least this long between words starts a new paragraph.
  static let paragraphGap: Double = 2.0

  private static let traceLock = NSLock()
  nonisolated(unsafe) private static var _verbose = false
  nonisolated(unsafe) private static var _trace: [String] = []

  /// Log every step (debug builds and the harness only; release builds never log spoken words).
  static var verbose: Bool {
    get {
      #if DEBUG
      traceLock.lock()
      defer { traceLock.unlock() }
      return _verbose
      #else
      return false
      #endif
    }
    set {
      #if DEBUG
      traceLock.lock()
      _verbose = newValue
      traceLock.unlock()
      #endif
    }
  }

  /// What happened during the last transcription, when [verbose].
  static var trace: [String] {
    get {
      #if DEBUG
      traceLock.lock()
      defer { traceLock.unlock() }
      return _trace
      #else
      return []
      #endif
    }
    set {
      #if DEBUG
      traceLock.lock()
      _trace = newValue
      traceLock.unlock()
      #endif
    }
  }

  static func log(_ s: @autoclosure () -> String) {
    #if DEBUG
    traceLock.lock()
    let on = _verbose
    traceLock.unlock()
    guard on else { return }
    let line = s()
    traceLock.lock()
    _trace.append(line)
    traceLock.unlock()
    print("[speech] \(line)")
    #endif
  }

  static func bcp47(_ id: String) -> String { id.replacingOccurrences(of: "_", with: "-") }

  static func bcp47(_ l: Locale) -> String { bcp47(l.identifier) }

  /// What the device reports, for the report and for debugging.
  static func describe() async -> [String: Any] {
    var out: [String: Any] = [:]
    var analyzer: Any = "needs iOS 26 / macOS 26"
    if #available(iOS 26, macOS 26, *) {
      let supported = await SpeechTranscriber.supportedLocales.map { bcp47($0) }
      let installed = await SpeechTranscriber.installedLocales.map { bcp47($0) }
      let wanted = candidates.values.flatMap { $0 }
      analyzer = [
        "isAvailable": SpeechTranscriber.isAvailable,
        "supported": wanted.filter { supported.contains($0) },
        "installed": wanted.filter { installed.contains($0) },
      ]
    }
    out["analyzer"] = analyzer
    var recognizer: [String: Any] = [:]
    for id in candidates.values.flatMap({ $0 }) {
      let r = SFSpeechRecognizer(locale: Locale(identifier: id))
      recognizer[id] = r == nil ? "none" : (r!.supportsOnDeviceRecognition ? "on-device" : "server only")
    }
    out["recognizer"] = recognizer
    return out
  }

  /// The engine and locale that would write [language] here, without a server; nil when none can.
  /// [force] limits the choice to one engine (the harness uses it).
  static func choose(_ language: String, force: Engine? = nil) async -> (Engine, String)? {
    let ids = candidates[language] ?? []
    if force != .recognizer, #available(iOS 26, macOS 26, *), SpeechTranscriber.isAvailable {
      let supported = await SpeechTranscriber.supportedLocales.map { bcp47($0) }
      if let id = ids.first(where: { supported.contains(bcp47($0)) }) { return (.analyzer, id) }
    }
    if force != .analyzer {
      for id in ids {
        if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.supportsOnDeviceRecognition {
          return (.recognizer, id)
        }
      }
    }
    return nil
  }

  /// Make sure the new engine's model for [language] is on the device (Apple downloads the
  /// language model; no audio is involved). Quietly does nothing where the new engine is absent.
  static func prepare(_ language: String) async {
    guard #available(iOS 26, macOS 26, *), let (engine, id) = await choose(language), engine == .analyzer else { return }
    let module = SpeechTranscriber(locale: Locale(identifier: id), preset: .transcription)
    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        log("downloading the \(id) model")
        try await request.downloadAndInstall()
      }
    } catch {
      log("model for \(id) not installed: \(error)")
    }
  }

  /// The words in the file at [url], in [language] ("en" or "es"). With [download] false the new
  /// engine never fetches its language model first (the phone check reports that instead).
  static func transcribe(_ url: URL, language: String, force: Engine? = nil, download: Bool = true) async throws -> Words {
    guard let (engine, id) = await choose(language, force: force) else {
      throw Failure.unavailable("no on-device engine for \(language)")
    }
    log("engine \(engine.rawValue), locale \(id)")
    if engine == .analyzer, #available(iOS 26, macOS 26, *) {
      do {
        return Words(text: try await analyze(url, locale: Locale(identifier: id), download: download), engine: .analyzer, locale: id)
      } catch {
        // e.g. the model could not be downloaded: try the older recogniser, still on the device
        log("new engine failed (\(error)); trying the older recogniser")
        guard force == nil, let (_, rid) = await choose(language, force: .recognizer) else { throw error }
        return Words(text: try await recognize(url, locale: Locale(identifier: rid)), engine: .recognizer, locale: rid)
      }
    }
    return Words(text: try await recognize(url, locale: Locale(identifier: id)), engine: .recognizer, locale: id)
  }

  // ---- the new engine ----

  @available(iOS 26, macOS 26, *)
  static func analyze(_ url: URL, locale: Locale, download: Bool = true) async throws -> String {
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      guard download else { throw Failure.unavailable("the \(bcp47(locale)) model is not downloaded yet") }
      log("downloading the \(locale.identifier) model before transcribing")
      try await request.downloadAndInstall()
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let file = try AVAudioFile(forReading: url)
    let collect = Task { () throws -> [(Double, Double, String)] in
      var parts: [(Double, Double, String)] = []
      for try await r in transcriber.results where r.isFinal {
        let s = String(r.text.characters)
        log(String(format: "result %.2f-%.2f %@", r.range.start.seconds, r.range.end.seconds, s))
        parts.append((r.range.start.seconds, r.range.end.seconds, s))
      }
      return parts
    }
    defer { collect.cancel() }
    if let end = try await analyzer.analyzeSequence(from: file) {
      try await analyzer.finalizeAndFinish(through: end)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    return join(try await collect.value)
  }

  /// Results in time order, a blank line wherever the speaker paused for [paragraphGap].
  static func join(_ parts: [(start: Double, end: Double, text: String)]) -> String {
    var out = ""
    var lastEnd: Double?
    for p in parts {
      let t = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { continue }
      if let e = lastEnd { out += p.start - e >= paragraphGap ? "\n\n" : " " }
      out += t
      lastEnd = p.end
    }
    return out
  }

  // ---- the older recogniser, on the device only ----

  static func recognize(_ url: URL, locale: Locale) async throws -> String {
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
      throw Failure.unavailable("the older recogniser cannot write \(locale.identifier) on this device")
    }
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true // never a server
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    request.taskHint = .dictation
    let gather = RecognizerGather()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
      var finished = false
      let task = recognizer.recognitionTask(with: request) { result, error in
        if finished { return }
        if let result {
          gather.add(result.bestTranscription, final: result.isFinal)
          if result.isFinal {
            finished = true
            cont.resume(returning: gather.text)
          }
        } else if let error {
          finished = true
          // "No speech detected" ends a file of silence: no words, not a failure
          let ns = error as NSError
          if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 203) {
            cont.resume(returning: gather.text)
          } else {
            cont.resume(throwing: Failure.failed("\(ns.domain) \(ns.code): \(ns.localizedDescription)"))
          }
        }
      }
      gather.task = task
    }
  }
}

/// Keeps the older recogniser's words across its restarts.
///
/// Measured on the iOS 26.3 simulator with a file that has three-second pauses: after each pause
/// the on-device recogniser silently starts a new transcription (the next partial result has one
/// word) and never sends a final result for the words before it; only the last stretch ends in a
/// final result. So the last partial of each stretch is kept here, and each restart, which follows
/// a pause, starts a new paragraph.
final class RecognizerGather: @unchecked Sendable {
  var task: SFSpeechRecognitionTask?
  private var kept: [String] = []
  private var current = ""
  private var currentWords = 0

  func add(_ t: SFTranscription, final: Bool) {
    let words = t.segments.count
    OnDeviceSpeech.log("\(final ? "final" : "partial") \(words) words: \(t.formattedString)")
    // a restart: far fewer words than a moment ago
    if currentWords >= 2 && words <= currentWords / 2 {
      OnDeviceSpeech.log("restart; keeping \(currentWords) words")
      kept.append(current)
    }
    // within a stretch, words can come and go by one as the recogniser changes its mind
    current = final ? OnDeviceSpeech.paragraphs(of: t).map { $0.2 }.joined(separator: "\n\n") : t.formattedString
    currentWords = words
  }

  /// The stretches as paragraphs. The recogniser sometimes sends a shorter partial of the
  /// same stretch (measured through a real microphone), which looks like a restart; the stretch
  /// that follows then repeats it, so a stretch the next one begins with is dropped.
  var text: String {
    let chunks = (kept + [current]).map { OnDeviceSpeech.sentence($0) }.filter { !$0.isEmpty }
    var out: [String] = []
    for (i, c) in chunks.enumerated() {
      if i + 1 < chunks.count, (Self.key(chunks[i + 1]) + " ").hasPrefix(Self.key(c) + " ") { continue }
      out.append(c)
    }
    return out.joined(separator: "\n\n")
  }

  /// Words only, lower case, for comparing stretches.
  static func key(_ s: String) -> String {
    s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
  }
}

extension OnDeviceSpeech {
  /// A stretch of words as a paragraph: trimmed, its first letter a capital. Nothing else is
  /// changed; the words stay exactly as the recogniser heard them.
  static func sentence(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = t.first else { return "" }
    return first.uppercased() + t.dropFirst()
  }

  /// Splits a transcription where its words are [paragraphGap] apart, as (start, end, text).
  static func paragraphs(of t: SFTranscription) -> [(Double, Double, String)] {
    let s = t.formattedString as NSString
    let segs = t.segments
    guard !segs.isEmpty, segs.last!.timestamp > 0 else {
      return segs.isEmpty ? [] : [(0, 0, t.formattedString)] // partial results carry no times
    }
    var out: [(Double, Double, String)] = []
    var from = 0, startTime = segs[0].timestamp
    for i in 1..<segs.count {
      let prevEnd = segs[i - 1].timestamp + segs[i - 1].duration
      if segs[i].timestamp - prevEnd >= paragraphGap {
        let cut = segs[i].substringRange.location
        guard cut >= from, cut <= s.length else { continue }
        out.append((startTime, prevEnd, s.substring(with: NSRange(location: from, length: cut - from))))
        from = cut
        startTime = segs[i].timestamp
      }
    }
    let last = segs[segs.count - 1]
    if from <= s.length {
      out.append((startTime, last.timestamp + last.duration, s.substring(from: from)))
    }
    return out
  }
}
