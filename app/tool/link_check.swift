// Opens a blessing link (lib/share/link.dart) with Apple's own frameworks only, as an App Clip
// would: CryptoKit's ChaChaPoly and the Compression framework's raw DEFLATE (COMPRESSION_ZLIB).
// Prints the record's JSON, or why it would not open.
//
//   swiftc -O -o /tmp/link_check tool/link_check.swift && /tmp/link_check '<link or fragment>'
import CryptoKit
import Compression
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : (readLine() ?? "")
var f = arg.split(separator: "#", maxSplits: 1).last.map(String.init) ?? ""
guard f.first == "1" else { fail("not a version 1 link") }
f.removeFirst()
var b64 = f.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
while b64.count % 4 != 0 { b64 += "=" }
guard let all = Data(base64Encoded: b64), all.count > 48 else { fail("not base64url") }
let key = SymmetricKey(data: all.prefix(32))
let sealed = all.dropFirst(32)
do {
  let box = try ChaChaPoly.SealedBox(combined: Data(count: 12) + sealed)
  let packed = try ChaChaPoly.open(box, using: key)
  let cap = 512 * 1024
  var out = Data(count: cap)
  let n = out.withUnsafeMutableBytes { dst in
    packed.withUnsafeBytes { src in
      compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap, src.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
    }
  }
  guard n > 0, n < cap else { fail("does not unpack") }
  print(String(decoding: out.prefix(n), as: UTF8.self))
} catch {
  fail("does not open: \(error)")
}
