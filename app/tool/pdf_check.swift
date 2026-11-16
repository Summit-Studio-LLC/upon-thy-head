// Checks a shared blessing PDF on the Mac, with nothing to install (PDFKit and Core Graphics):
//
//   swift tool/pdf_check.swift <file.pdf> <expected.json> <out dir for page images>
//
// expected.json: {"fileName", "title", "paper": "letter"|"a4", "paragraphs": [...], "footer": "{n} of {total}"}
// Prints one line per check, "ok …" or "FAIL …", and ends with "PDF CHECK PASSED" or "PDF CHECK FAILED".
// Each page is rendered at 2× (144 dpi) on white as <out>/<name>-page-<n>.png.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 4 else {
  print("usage: pdf_check.swift <file.pdf> <expected.json> <out dir>")
  exit(2)
}
let url = URL(fileURLWithPath: args[1])
let expected = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
let outDir = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var failed = false
func check(_ ok: Bool, _ what: String) {
  print((ok ? "ok   " : "FAIL ") + what)
  if !ok { failed = true }
}

guard let doc = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else {
  print("FAIL cannot open \(url.path)")
  print("PDF CHECK FAILED")
  exit(1)
}

// ---- name, title, paper ----
check(url.lastPathComponent == expected["fileName"] as? String, "file name: \(url.lastPathComponent)")
let attrs = doc.documentAttributes ?? [:]
let title = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""
check(title == expected["title"] as? String, "document title: \(title)")
let creator = attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
let producer = attrs[PDFDocumentAttribute.producerAttribute] as? String ?? ""
let author = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
print("info creator=\"\(creator)\" producer=\"\(producer)\" author=\"\(author)\"")
check(!"\(creator) \(author)".localizedCaseInsensitiveContains("upon thy head"), "no app name in the document's information")
let paper = expected["paper"] as? String ?? "letter"
let size = paper == "letter" ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
var sizesOk = true
for i in 0 ..< doc.pageCount {
  let b = doc.page(at: i)!.bounds(for: .mediaBox)
  if abs(b.width - size.width) > 0.6 || abs(b.height - size.height) > 0.6 { sizesOk = false }
}
let first = doc.page(at: 0)!.bounds(for: .mediaBox)
check(sizesOk, "page size \(paper): \(first.width) × \(first.height) pt on all \(doc.pageCount) pages")
print("pages \(doc.pageCount)")
if let want = expected["pages"] as? Int { check(doc.pageCount == want, "page count \(doc.pageCount), expected \(want)") }
if let atLeast = expected["minPages"] as? Int { check(doc.pageCount >= atLeast, "page count \(doc.pageCount) ≥ \(atLeast)") }

// ---- fonts ----
var fonts: [String: String] = [:] // name → how it is embedded
for n in 1 ... cg.numberOfPages {
  guard let page = cg.page(at: n), let dict = page.dictionary else { continue }
  var res: CGPDFDictionaryRef?, fd: CGPDFDictionaryRef?
  guard CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res, CGPDFDictionaryGetDictionary(res, "Font", &fd), let fd else { continue }
  CGPDFDictionaryApplyBlock(fd, { _, obj, _ in
    var f: CGPDFDictionaryRef?
    guard CGPDFObjectGetValue(obj, .dictionary, &f), let f else { return true }
    func name(_ d: CGPDFDictionaryRef, _ k: String) -> String {
      var p: UnsafePointer<CChar>?
      return CGPDFDictionaryGetName(d, k, &p) ? String(cString: p!) : ""
    }
    var base = name(f, "BaseFont")
    let subtype = name(f, "Subtype")
    var desc: CGPDFDictionaryRef?
    var d = f
    if subtype == "Type0" {
      var arr: CGPDFArrayRef?, inner: CGPDFDictionaryRef?
      if CGPDFDictionaryGetArray(f, "DescendantFonts", &arr), let arr, CGPDFArrayGetDictionary(arr, 0, &inner), let inner { d = inner }
    }
    var how = "not embedded"
    if CGPDFDictionaryGetDictionary(d, "FontDescriptor", &desc), let desc {
      var s: CGPDFStreamRef?
      for k in ["FontFile2", "FontFile3", "FontFile"] where CGPDFDictionaryGetStream(desc, k, &s) { how = "embedded (\(k))"; break }
      if base.isEmpty { base = name(desc, "FontName") }
    } else if subtype == "Type3" {
      how = "embedded (Type3 glyphs)"
    }
    var tu: CGPDFStreamRef?
    let unicode = CGPDFDictionaryGetStream(f, "ToUnicode", &tu)
    let encoding = name(f, "Encoding")
    // text maps to Unicode through a ToUnicode table, or a standard encoding every reader knows
    let mapped = unicode ? "text: ToUnicode" : ["MacRomanEncoding", "WinAnsiEncoding", "StandardEncoding"].contains(encoding) ? "text: \(encoding)" : "text: UNMAPPED \(encoding)"
    fonts["\(base) [\(subtype)]"] = how + ", " + mapped
    return true
  }, nil)
}
for (k, v) in fonts.sorted(by: { $0.key < $1.key }) { print("font \(k): \(v)") }
check(!fonts.isEmpty && fonts.keys.allSatisfy { $0.localizedCaseInsensitiveContains("Newsreader") }, "every font is Newsreader")
check(fonts.values.allSatisfy { $0.hasPrefix("embedded") && !$0.contains("UNMAPPED") }, "every font embedded, its text mapped to Unicode")

// ---- the text ----
func words(_ s: String) -> [String] {
  s.replacingOccurrences(of: "\u{00AD}", with: "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
}
let paragraphs = expected["paragraphs"] as? [String] ?? []
let footer = expected["footer"] as? String ?? "{n} of {total}"
let titleWords = words(expected["title"] as? String ?? "")
var bodyText: [String] = []
var all = ""
struct Line { let text: String; let rect: CGRect }
var pagesLines: [[Line]] = []
var edgesOk = true, footersOk = true
for i in 0 ..< doc.pageCount {
  let page = doc.page(at: i)!
  let b = page.bounds(for: .mediaBox)
  all += (page.string ?? "") + "\n"
  let lines = (page.selection(for: b)?.selectionsByLine() ?? []).compactMap { sel -> Line? in
    let t = (sel.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Line(text: t, rect: sel.bounds(for: page))
  }
  // nothing past the inch of margin but the footer
  for l in lines {
    if l.rect.minX < 71 || l.rect.maxX > b.width - 71 { edgesOk = false; print("     edge x: page \(i + 1) \"\(l.text.prefix(30))\" \(l.rect)") }
    if l.rect.maxY > b.height - 66 { edgesOk = false; print("     edge top: page \(i + 1) \"\(l.text.prefix(30))\" \(l.rect)") }
  }
  var body = lines.filter { $0.rect.minY > 60 }
  let foot = lines.filter { $0.rect.minY <= 60 }
  if i == 0 {
    check(foot.isEmpty, "no footer on page 1")
  } else {
    let numbers = footer.replacingOccurrences(of: "{n}", with: "\(i + 1)").replacingOccurrences(of: "{total}", with: "\(doc.pageCount)")
    let f = foot.map(\.text).joined(separator: " ")
    let titleStart = titleWords.prefix(2).joined(separator: " ")
    if !(f.hasSuffix(numbers) && f.hasPrefix(titleStart)) { footersOk = false; print("     footer page \(i + 1): \"\(f)\", expected \"\(titleStart)… \(numbers)\"") }
    if foot.contains(where: { $0.rect.minY < 20 }) { edgesOk = false }
  }
  if i == 0 {
    // the heading: everything above the rule's gap; body lines are the ones at the body size
    if let firstWords = paragraphs.first.map(words), let startAt = body.firstIndex(where: { Array(words($0.text).prefix(3)) == Array(firstWords.prefix(3)) }) {
      body = Array(body[startAt...])
    }
  }
  pagesLines.append(body)
  bodyText.append(contentsOf: body.map(\.text))
}
if doc.pageCount > 1 { check(footersOk, "footers from page 2: title and \"\(footer)\"") }
check(edgesOk, "nothing cut off or past the margins")
let got = words(bodyText.joined(separator: " ")), want = words(paragraphs.joined(separator: " "))
if got != want {
  let n = zip(got, want).prefix(while: { $0 == $1 }).count
  print("     first difference at word \(n): got \(got.dropFirst(n).prefix(6)) want \(want.dropFirst(n).prefix(6)) (\(got.count) vs \(want.count))")
}
check(got == want, "the words extract in order and equal the blessing's (\(want.count) words)")
let docWords = words(all)
let head = words([expected["date"] as? String, expected["from"] as? String, expected["recipient"] as? String].compactMap { $0 }.joined(separator: " "))
check(head.allSatisfy { docWords.contains($0) }, "the heading's date and names are in the text")
// searchable: PDFKit finds a phrase from the middle of the last paragraph
if let last = paragraphs.last {
  let w = words(last), mid = w.count / 2
  let phrase = w[max(0, mid - 1) ..< min(w.count, mid + 2)].joined(separator: " ")
  check(!doc.findString(phrase, withOptions: .caseInsensitive).isEmpty, "searchable: \"\(phrase)\" is found")
}

// ---- stranded lines: a paragraph's first line alone at a page's foot, or its last alone at the head ----
func starts(_ t: String) -> Bool { paragraphs.contains { words($0).prefix(3) == words(t).prefix(3) } }
func ends(_ t: String) -> Bool { paragraphs.contains { words($0).suffix(3) == words(t).suffix(3) } }
var stranded = 0
for (i, lines) in pagesLines.enumerated() where !lines.isEmpty {
  // runs of lines, split where the gap is a paragraph's
  var runs: [[Line]] = [[lines[0]]]
  for k in 1 ..< max(1, lines.count) where lines.count > 1 {
    let gap = lines[k - 1].rect.minY - lines[k].rect.maxY
    if gap > 8 { runs.append([lines[k]]) } else { runs[runs.count - 1].append(lines[k]) }
  }
  let runSizes = runs.map(\.count)
  print("page \(i + 1): \(lines.count) lines in runs \(runSizes)")
  if i > 0, let r = runs.first, r.count == 1, !starts(r[0].text) { stranded += 1; print("     widow at the top of page \(i + 1): \"\(r[0].text.prefix(40))\"") }
  if i < pagesLines.count - 1, let r = runs.last, r.count == 1, !ends(r[0].text) { stranded += 1; print("     orphan at the foot of page \(i + 1): \"\(r[0].text.prefix(40))\"") }
}
check(stranded == 0, "no single line stranded at a page's top or foot")

// ---- page images ----
let stem = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ",", with: "")
for n in 1 ... cg.numberOfPages {
  let page = cg.page(at: n)!
  let box = page.getBoxRect(.mediaBox)
  let scale: CGFloat = 2
  let w = Int(box.width * scale), h = Int(box.height * scale)
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.setFillColor(gray: 1, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.scaleBy(x: scale, y: scale)
  ctx.drawPDFPage(page)
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  let file = outDir.appendingPathComponent("\(stem)-page-\(n).png")
  try! rep.representation(using: .png, properties: [:])!.write(to: file)
  print("image \(file.path)")
}
print(failed ? "PDF CHECK FAILED" : "PDF CHECK PASSED")
exit(failed ? 1 : 0)
