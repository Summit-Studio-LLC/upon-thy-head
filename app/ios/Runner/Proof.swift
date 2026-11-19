import CryptoKit
import DeviceCheck
import Flutter
import Foundation
import Security

/// Proof that a request to make a link comes from this app, for lib/share/proof.dart, on
/// `upon_thy_head/proof` (website/PROTOCOL.md §4, "Proof of the app"). Apple's App Attest: a new
/// key, attested by Apple against the service's challenge. The key is made fresh for each proof and
/// never used again; the service answers with a pass, which is kept here in the Keychain.
/// Nothing here logs a challenge, key id, attestation or pass.
///
///  - `prove` {challenge} → {platform: "ios", keyId, attestation (base64)}, or nil where App Attest
///    is not supported (the simulator) or fails
///  - `passGet` → the kept pass or nil; `passPut` {value} keeps it (nil forgets it)
enum ProofChannel {
  static let service = "dev.summitstudio.uponThyHead.proof"

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/proof", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "prove":
      guard let challenge = a["challenge"] as? String else { return result(nil) }
      prove(challenge) { answer in DispatchQueue.main.async { result(answer) } }
    case "passGet":
      result(passGet())
    case "passPut":
      passPut(a["value"] as? String)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func prove(_ challenge: String, done: @escaping ([String: String]?) -> Void) {
    let attest = DCAppAttestService.shared
    guard attest.isSupported else { return done(nil) }
    attest.generateKey { keyId, error in
      guard let keyId, error == nil else { return done(nil) }
      let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
      attest.attestKey(keyId, clientDataHash: hash) { attestation, error in
        guard let attestation, error == nil else { return done(nil) }
        done(["platform": "ios", "keyId": keyId, "attestation": attestation.base64EncodedString()])
      }
    }
  }

  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pass"]
  }

  static func passGet() -> String? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func passPut(_ value: String?) {
    SecItemDelete(query as CFDictionary)
    guard let value else { return }
    var q = query
    q[kSecValueData as String] = Data(value.utf8)
    // on this device only, so never restored from a backup onto another phone
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(q as CFDictionary, nil)
  }
}
