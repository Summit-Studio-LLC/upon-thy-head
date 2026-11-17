import CryptoKit
import Flutter
import Foundation
import Security

/// Locking and opening a blessing for a link, and keeping each link's stop token, for
/// lib/share/link_crypto.dart, on `upon_thy_head/link`. The cipher is CryptoKit's AES-256-GCM,
/// exactly as website/PROTOCOL.md §3 says; nothing here implements a cipher. Nothing here logs a
/// key, a plaintext, or a token.
///
///  - `random` {count} → bytes from SecRandomCopyBytes
///  - `seal` {plain, key, nonce} → 0x01 ‖ nonce ‖ ciphertext ‖ tag, additional data the byte 0x01
///  - `open` {locked, key} → the plaintext, or the error `locked` (it does not authenticate)
///  - `secretPut` {name, value}, `secretGet` {name}, `secretDelete` {name}, `secretNames`: the
///    Keychain, as generic passwords of this app, readable after the first unlock and on this device
///    only (so never restored from a backup onto another phone)
enum LinkChannel {
  static let version: UInt8 = 1
  static let service = "dev.summitstudio.uponThyHead.links"

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "upon_thy_head/link", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
  }

  static func data(_ v: Any?) -> Data? { (v as? FlutterStandardTypedData)?.data }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "random":
      let n = a["count"] as? Int ?? 0
      guard n > 0, n <= 64 else { return result(FlutterError(code: "random", message: "count", details: nil)) }
      var bytes = [UInt8](repeating: 0, count: n)
      guard SecRandomCopyBytes(kSecRandomDefault, n, &bytes) == errSecSuccess else {
        return result(FlutterError(code: "random", message: "no randomness", details: nil))
      }
      result(FlutterStandardTypedData(bytes: Data(bytes)))
    case "seal":
      guard let plain = data(a["plain"]), let key = data(a["key"]), let nonce = data(a["nonce"]), key.count == 32, nonce.count == 12 else {
        return result(FlutterError(code: "seal", message: "bad arguments", details: nil))
      }
      do {
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: Data([version]))
        result(FlutterStandardTypedData(bytes: Data([version]) + nonce + box.ciphertext + box.tag))
      } catch {
        result(FlutterError(code: "seal", message: "could not lock", details: nil))
      }
    case "open":
      guard let locked = data(a["locked"]), let key = data(a["key"]), key.count == 32 else {
        return result(FlutterError(code: "open", message: "bad arguments", details: nil))
      }
      // the frame is checked in Dart first (size, version); a copy too short for a nonce and a tag
      // cannot authenticate
      guard locked.count >= 1 + 12 + 16 else { return result(FlutterError(code: "locked", message: nil, details: nil)) }
      let bytes = [UInt8](locked)
      do {
        let box = try AES.GCM.SealedBox(
          nonce: AES.GCM.Nonce(data: Data(bytes[1..<13])),
          ciphertext: Data(bytes[13..<(bytes.count - 16)]),
          tag: Data(bytes[(bytes.count - 16)...]))
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data([bytes[0]]))
        result(FlutterStandardTypedData(bytes: plain))
      } catch {
        result(FlutterError(code: "locked", message: nil, details: nil))
      }
    case "secretPut":
      guard let name = a["name"] as? String, let value = a["value"] as? String else { return result(FlutterError(code: "secret", message: "bad arguments", details: nil)) }
      let status = Secrets.put(name, Data(value.utf8))
      status == errSecSuccess ? result(nil) : result(FlutterError(code: "secret", message: "keychain \(status)", details: nil))
    case "secretGet":
      guard let name = a["name"] as? String else { return result(nil) }
      result(Secrets.get(name).flatMap { String(data: $0, encoding: .utf8) })
    case "secretDelete":
      if let name = a["name"] as? String { Secrets.delete(name) }
      result(nil)
    case "secretNames":
      result(Secrets.names())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The Keychain items of the links: generic passwords under one service name.
enum Secrets {
  static func base(_ name: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: LinkChannel.service, kSecAttrAccount as String: name]
  }

  static func put(_ name: String, _ value: Data) -> OSStatus {
    SecItemDelete(base(name) as CFDictionary)
    var add = base(name)
    add[kSecValueData as String] = value
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    add[kSecAttrSynchronizable as String] = false
    return SecItemAdd(add as CFDictionary, nil)
  }

  static func get(_ name: String) -> Data? {
    var q = base(name)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
    return out as? Data
  }

  static func delete(_ name: String) {
    SecItemDelete(base(name) as CFDictionary)
  }

  static func names() -> [String] {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: LinkChannel.service,
      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
    return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
  }
}
