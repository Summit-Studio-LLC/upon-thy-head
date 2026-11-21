import Flutter
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The phone's own language model for polish (lib/polish/model.dart), on `upon_thy_head/model`.
///
/// Apple's on-device model only (Foundation Models, iOS 26, with Apple Intelligence on). It runs on
/// the phone; nothing is sent anywhere. The framework's Private Cloud Compute model, which needs the
/// network, is a separate type this file never names. No tools are given to the model.
///
/// The app checks every answer against the spoken words (lib/polish/model_check.dart); this file
/// only asks. Nothing of a blessing is logged, not even in an error.
///
/// Methods (Dart → iOS):
///  - `status` {language} → {available, reason}: reason "system" (before iOS 26),
///    "deviceNotEligible", "appleIntelligenceNotEnabled", "modelNotReady", "language", "unknown"
///  - `polish` {id, text, language, instructions} → the model's text; errors "unavailable",
///    "refused", "guardrail", "tooLong", "language", "busy", "cancelled", "failed"
///  - `cancel` {id}: stop that call
enum PhoneModelChannel {
  static var channel: FlutterMethodChannel?
  /// The calls running, by id. Touched on the main thread only.
  nonisolated(unsafe) static var running: [String: Task<Void, Never>] = [:]

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/model", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status":
      result(status(args["language"] as? String))
    case "polish":
      guard let id = args["id"] as? String, let text = args["text"] as? String,
            let instructions = args["instructions"] as? String else {
        return result(FlutterError(code: "args", message: nil, details: nil))
      }
      let language = args["language"] as? String ?? "en"
      #if canImport(FoundationModels)
      guard #available(iOS 26, *) else { return result(FlutterError(code: "unavailable", message: nil, details: nil)) }
      running[id] = Task {
        let answer: Any
        do {
          answer = try await AppleModel.polish(text, language: language, instructions: instructions)
        } catch is CancellationError {
          answer = FlutterError(code: "cancelled", message: nil, details: nil)
        } catch {
          answer = FlutterError(code: AppleModel.code(error), message: nil, details: nil)
        }
        await MainActor.run {
          running[id] = nil
          result(answer)
        }
      }
      #else
      result(FlutterError(code: "unavailable", message: nil, details: nil))
      #endif
    case "cancel":
      if let id = args["id"] as? String {
        running[id]?.cancel()
        running[id] = nil
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Whether the model can be used now, and why not. With a [language], also whether the model
  /// takes it.
  static func status(_ language: String?) -> [String: Any] {
    #if canImport(FoundationModels)
    if #available(iOS 26, *) { return AppleModel.status(language) }
    #endif
    return ["available": false, "reason": "system"]
  }

  /// For the phone check (PhoneCheck.swift): the model's state and the languages it takes.
  static func report() -> [String: Any] {
    var out = status(nil)
    out["en"] = status("en")["available"] as? Bool ?? false
    out["es"] = status("es")["available"] as? Bool ?? false
    #if canImport(FoundationModels)
    if #available(iOS 26, *) {
      out["languages"] = SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier }.sorted()
    }
    #endif
    return out
  }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
enum AppleModel {
  /// The on-device model, with the guardrails Apple gives for working on text the person supplies
  /// (a blessing speaks of illness, death and the body; the default guardrails can stop on those).
  /// With these, a request for plain text does not throw for a guardrail; the model may still answer
  /// with a refusal in words, which the app's check throws away.
  static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

  static func status(_ language: String?) -> [String: Any] {
    switch SystemLanguageModel.default.availability {
    case .available:
      if let language, !supports(language) { return ["available": false, "reason": "language"] }
      return ["available": true]
    case .unavailable(let why):
      let reason: String
      switch why {
      case .deviceNotEligible: reason = "deviceNotEligible"
      case .appleIntelligenceNotEnabled: reason = "appleIntelligenceNotEnabled"
      case .modelNotReady: reason = "modelNotReady"
      @unknown default: reason = "unknown"
      }
      return ["available": false, "reason": reason]
    }
  }

  /// Apple's advice is `supportsLocale`; a bare language ("es") is tried with the regions the app
  /// records in too, and against the list of languages, so a supported Spanish is never missed.
  static func supports(_ language: String) -> Bool {
    let m = SystemLanguageModel.default
    let regions = language == "es" ? ["es", "es-US", "es-MX", "es-ES"] : ["en", "en-US", "en-GB"]
    if regions.contains(where: { m.supportsLocale(Locale(identifier: $0)) }) { return true }
    return m.supportedLanguages.contains { $0.languageCode?.identifier == language }
  }

  /// One piece, in a session of its own, so no call sees another's words. Greedy, so the same
  /// words give the same answer; the answer may be a little longer than the piece, never much.
  static func polish(_ text: String, language: String, instructions: String) async throws -> String {
    guard case .available = model.availability, supports(language) else { throw Unavailable() }
    let session = LanguageModelSession(model: model, instructions: instructions)
    let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: min(2000, text.count / 2 + 120))
    let response = try await session.respond(to: text, options: options)
    try Task.checkCancellation()
    return response.content
  }

  struct Unavailable: Error {}

  /// The error's kind, without its description (which could hold the words).
  static func code(_ error: Error) -> String {
    if error is Unavailable { return "unavailable" }
    guard let e = error as? LanguageModelSession.GenerationError else { return "failed" }
    switch e {
    case .refusal: return "refused"
    case .guardrailViolation: return "guardrail"
    case .exceededContextWindowSize: return "tooLong"
    case .unsupportedLanguageOrLocale: return "language"
    case .assetsUnavailable: return "unavailable"
    case .rateLimited, .concurrentRequests: return "busy"
    default: return "failed"
    }
  }
}
#endif
