// Checks website/protocol-vectors.json with Apple's own CryptoKit, the same calls the app makes in
// ios/Runner/Link.swift (AES-256-GCM, additional data 0x01): each vector seals to exactly its locked
// copy and opens to its plaintext, and each refusal fails for its own reason in the contract's order
// (key, damaged, newer, locked; "record" refusals open, and the app's record reader refuses them).
// Or, given a link and its locked copy, opens it and prints the record.
//
//   swiftc -O -o /tmp/link_check tool/link_check.swift
//   /tmp/link_check ../website/protocol-vectors.json
//   /tmp/link_check 'https://uponthyhead.app/b/<id>#<key>' locked.bin
import CryptoKit
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

func hex(_ s: String) -> Data {
  var d = Data(); var i = s.startIndex
  while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
  return d
}

/// The key in a fragment: 43 base64url characters, the last one canonical; nil otherwise.
func key(_ f: String) -> Data? {
  guard f.count == 43, f.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
        "AEIMQUYcgkosw048".contains(f.last!) else { return nil }
  let b = f.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="
  return Data(base64Encoded: b).flatMap { $0.count == 32 ? $0 : nil }
}

func seal(_ plain: Data, _ key: Data, _ nonce: Data) throws -> Data {
  let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: Data([1]))
  return Data([1]) + nonce + box.ciphertext + box.tag
}

/// The contract's steps 2–4: the error name, or the plaintext.
func open(_ locked: Data, _ key: Data) -> (String?, Data?) {
  let b = [UInt8](locked)
  if b.count < 31 || b.count > 65536 || b[0] == 0 { return ("damaged", nil) }
  if b[0] > 1 { return ("newer", nil) }
  do {
    let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(b[1..<13])), ciphertext: Data(b[13..<(b.count - 16)]), tag: Data(b[(b.count - 16)...]))
    return (nil, try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data([b[0]])))
  } catch {
    return ("locked", nil)
  }
}

let args = CommandLine.arguments
if args.count == 3 {
  guard let hash = args[1].firstIndex(of: "#"), let k = key(String(args[1][args[1].index(after: hash)...])) else { fail("key") }
  guard let locked = FileManager.default.contents(atPath: args[2]) else { fail("no locked copy at \(args[2])") }
  let (e, plain) = open(locked, k)
  if let e { fail(e) }
  print(String(decoding: plain!, as: UTF8.self))
  exit(0)
}
guard args.count == 2, let data = FileManager.default.contents(atPath: args[1]),
      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { fail("usage: link_check <protocol-vectors.json> | <link> <locked copy>") }

var passed = 0, failed = 0
func check(_ ok: Bool, _ what: String) {
  if ok { passed += 1; print("ok   \(what)") } else { failed += 1; print("FAIL \(what)") }
}

for v in j["vectors"] as! [[String: Any]] {
  let name = v["name"] as! String
  let k = hex((v["key"] as! [String: Any])["hex"] as! String)
  let nonce = hex((v["nonce"] as! [String: Any])["hex"] as! String)
  let plain = ((v["plaintext"] as! [String: Any])["utf8"] as! String).data(using: .utf8)!
  let locked = Data(base64Encoded: (v["locked"] as! [String: Any])["base64"] as! String)!
  check(key((v["key"] as! [String: Any])["base64url"] as! String) == k, "\(name): the key from its fragment")
  check((try? seal(plain, k, nonce)) == locked, "\(name): sealed to exactly its locked copy")
  let (e, out) = open(locked, k)
  check(e == nil && out == plain, "\(name): opened to its plaintext")
}
for r in j["refusals"] as! [[String: Any]] {
  let want = r["error"] as! String
  let (e, _) = open(Data(base64Encoded: r["locked"] as! String)!, key(r["key"] as! String)!)
  check(e == want, "\(r["name"]!): \(want)")
}
// these open; what is inside is refused by the app's record reader (test/link_format_test.dart)
for r in j["records"] as! [[String: Any]] {
  let (e, plain) = open(Data(base64Encoded: r["locked"] as! String)!, key(r["key"] as! String)!)
  check(e == nil && plain != nil, "\(r["name"]!): opens, for the reader to refuse (\(r["error"]!))")
}
for f in j["fragments"] as! [[String: Any]] {
  check(key(f["fragment"] as! String) == nil, "fragment \"\(f["fragment"]!)\": key")
}
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
