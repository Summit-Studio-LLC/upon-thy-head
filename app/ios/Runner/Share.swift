import CoreText
import Flutter
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

/// Sharing a blessing, for lib/share/share.dart, on `upon_thy_head/share`.
///
/// Methods (Dart → iOS):
///  - `text` {text, subject}: the system share sheet with the text; answers when it has closed
///  - `pdf` {fileName, title, date, from, recipient, paragraphs, pageOf}: the PDF is made in
///    tmp/share/, the share sheet opened with it; answers when the sheet has closed and the file is gone
///  - `file` {fileName, bytes}: a `.blessing` file (lib/share/blessing_file.dart) written to
///    tmp/share/ and shared as the app's own document type; answers as `pdf` does
///  - `link` {url, title}: a blessing's link (lib/share/links.dart), handed over as a URL so Messages
///    and Mail show it as a link; never logged (it holds the key)
///  Each answers, when its sheet has closed, whether something was done with it (true) or the sheet
///  was cancelled (false).
///  - `dismiss`: close the sheet now (the app locked) and remove the file
///  - `clean`: remove tmp/share/ (at launch: a file left by an app killed while sharing)
///  - `debugShowing` → whether the sheet is up; `debugPaper` → "letter" or "a4"; `debugItems` → what
///    the sheet was handed (for each item: its kind, file name, type and what the type conforms to)
///  - `receiving`: Dart is ready for files that arrive (BlessingInbox, below); answers with any that
///    came before it was, and sends later ones with `incoming`; an App Shortcut or the Spotlight entry
///    (Shortcuts.swift) comes the same way, as {shortcut: "record" | "home"}
///
/// The app adds nothing of its own to what is shared: no message, no link, no app name.
enum ShareChannel {
  static var channel: FlutterMethodChannel?
  static var sheet: UIActivityViewController?
  static var answer: FlutterResult?
  /// Whether the last sheet's activity was carried out (not cancelled).
  static var completed = false

  /// Everything made for sharing lives here, and only while the sheet is up.
  static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true) }

  static func register(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar? = nil) {
    // blessing files that arrive come through the scene (Flutter's scene delegate passes them on)
    registrar?.addSceneDelegate(BlessingInbox.scenes)
    let c = FlutterMethodChannel(name: "upon_thy_head/share", binaryMessenger: messenger)
    c.setMethodCallHandler(handle)
    channel = c
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "text":
      let text = args["text"] as? String ?? ""
      present(ShareItem(item: text, subject: args["subject"] as? String ?? ""), result)
    case "pdf":
      close()
      clean()
      do {
        let doc = SharedPdf(args)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(doc.fileName)
        try doc.write(to: url)
        present(ShareItem(item: url, subject: doc.title), result)
      } catch {
        NSLog("share: %@", error.localizedDescription)
        clean()
        result(FlutterError(code: "pdf", message: error.localizedDescription, details: nil))
      }
    case "file":
      close()
      clean()
      do {
        let name = (args["fileName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Blessing.blessing"
        guard let bytes = args["bytes"] as? FlutterStandardTypedData else { throw NSError(domain: "share", code: 2) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((name as NSString).lastPathComponent)
        try bytes.data.write(to: url, options: [.atomic, .completeFileProtection])
        present(ShareItem(item: url, subject: args["title"] as? String ?? ""), result)
      } catch {
        NSLog("share: %@", error.localizedDescription)
        clean()
        result(FlutterError(code: "file", message: error.localizedDescription, details: nil))
      }
    case "link":
      guard let s = args["url"] as? String, let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else {
        return result(FlutterError(code: "link", message: "not a link", details: nil))
      }
      present(ShareItem(item: url, subject: args["title"] as? String ?? ""), result)
    case "receiving":
      BlessingInbox.ready(result)
    case "debugItems":
      result(lastItems)
    case "debugReceivedLeft":
      result(BlessingInbox.leftovers())
    case "dismiss":
      if let s = sheet, s.presentingViewController != nil {
        s.dismiss(animated: false) { finish() }
      } else {
        finish()
      }
      result(nil)
    case "clean":
      clean()
      result(nil)
    case "debugShowing":
      result(sheet != nil && sheet?.presentingViewController != nil)
    case "debugPaper":
      result(SharedPdf.usesLetter() ? "letter" : "a4")
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func present(_ item: ShareItem, _ result: @escaping FlutterResult) {
    // one at a time ("text" closes an earlier one here; "pdf" already has, before making its file)
    if sheet != nil { close() }
    guard let top = topController() else {
      clean()
      return result(FlutterError(code: "share", message: "no window", details: nil))
    }
    lastItems = [describe(item.item)]
    let vc = UIActivityViewController(activityItems: [item], applicationActivities: nil)
    // nothing that would keep or file it on the app's behalf
    vc.excludedActivityTypes = [.addToReadingList, .assignToContact, .openInIBooks]
    completed = false
    vc.completionWithItemsHandler = { [weak vc] _, done, _, _ in
      if done { completed = true }
      // an activity that shows its own screen (Messages, Mail) calls this when it is done; the sheet
      // may still be up after a cancelled one, so only finish once it has gone, and only if no newer
      // sheet has taken its place
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        guard let vc, sheet === vc, vc.presentingViewController == nil else { return }
        finish()
      }
    }
    if let pop = vc.popoverPresentationController {
      pop.sourceView = top.view
      pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
      pop.permittedArrowDirections = []
    }
    sheet = vc
    answer = result
    top.present(vc, animated: true)
  }

  /// An earlier sheet goes without a trace and is answered, leaving the share folder alone.
  static func close() {
    let s = sheet
    sheet = nil
    if let s, s.presentingViewController != nil { s.dismiss(animated: false) }
    let a = answer
    answer = nil
    a?(false)
  }

  /// The sheet has closed: remove what was made for it and answer Dart.
  static func finish() {
    clean()
    sheet = nil
    let a = answer
    answer = nil
    a?(completed)
  }

  /// What the last sheet was handed, for the tests.
  static var lastItems: [[String: Any]] = []

  static func describe(_ item: Any) -> [String: Any] {
    guard let url = item as? URL else { return ["kind": "text"] }
    if !url.isFileURL {
      var d: [String: Any] = ["kind": "url", "scheme": url.scheme ?? "", "length": url.absoluteString.count]
      #if DEBUG
      d["url"] = url.absoluteString // tests only: the link holds its key
      #endif
      return d
    }
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    return [
      "kind": "file",
      "name": url.lastPathComponent.precomposedStringWithCanonicalMapping, // file URLs often come back decomposed
      "type": type?.identifier ?? "",
      "json": type?.conforms(to: .json) ?? false,
      "text": type?.conforms(to: .text) ?? false,
      "data": type?.conforms(to: .data) ?? false,
      "bytes": (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1,
      "path": url.path,
    ]
  }

  static func clean() {
    try? FileManager.default.removeItem(at: folder)
  }

  static func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    var top = window?.rootViewController
    while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
    return top
  }
}

/// What the share sheet is given: the text or the file, with the title as the subject (Mail).
final class ShareItem: NSObject, UIActivityItemSource {
  let item: Any
  let subject: String
  init(item: Any, subject: String) {
    self.item = item
    self.subject = subject
  }

  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { item }
  func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { item }
  func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject }

  /// The sheet's header names the blessing by its title, not "Plain Text".
  func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
    let m = LPLinkMetadata()
    m.title = subject
    if let url = item as? URL { m.originalURL = url; m.url = url }
    return m
  }
}

/// The blessing as a printed page: US Letter where the region uses it, A4 elsewhere; an inch of
/// margin; Newsreader (the app's face, from the Flutter assets) in black on white. Real text with the
/// fonts embedded, so it can be selected and searched.
///
/// Page 1: the date small, the title large, "A blessing from …" in italic, "For …", a thin rule, then
/// the words. From page 2 a small footer: the title and "2 of 3". Paragraphs break across pages with
/// no single line left alone at the top or bottom of a page where that can be avoided.
struct SharedPdf {
  let fileName, title, date, from, recipient, pageOf: String
  let paragraphs: [String]

  init(_ a: [String: Any]) {
    fileName = (a["fileName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Blessing.pdf"
    title = a["title"] as? String ?? ""
    date = a["date"] as? String ?? ""
    from = a["from"] as? String ?? ""
    recipient = a["recipient"] as? String ?? ""
    pageOf = a["pageOf"] as? String ?? "{n} / {total}"
    paragraphs = a["paragraphs"] as? [String] ?? []
  }

  /// CLDR's US-Letter territories; everywhere else prints on A4.
  static let letterRegions: Set<String> = ["US", "CA", "MX", "CL", "CO", "CR", "GT", "PA", "PH", "PR", "SV", "VE", "NI", "BZ"]

  static func usesLetter() -> Bool {
    letterRegions.contains(Locale.current.region?.identifier ?? "US")
  }

  // ---- measures, in points ----
  static let margin: CGFloat = 72
  static let bodySize: CGFloat = 12.5, bodyLeading: CGFloat = 20.5, paragraphGap: CGFloat = 10.25
  static let footerSize: CGFloat = 8.5

  // ---- fonts ----
  static func font(italic: Bool, size: CGFloat, figures oldstyle: Bool = false) -> CTFont {
    let asset = italic ? "assets/fonts/Newsreader-Italic.ttf" : "assets/fonts/Newsreader.ttf"
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData,
          let base = CTFontManagerCreateFontDescriptorFromData(data)
    else { return CTFontCreateWithName((italic ? "Georgia-Italic" : "Georgia") as CFString, size, nil) }
    // the app's settings: regular weight, the optical size following the size (theme.dart)
    let tag = { (s: String) -> NSNumber in NSNumber(value: s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
    var attrs: [CFString: Any] = [
      kCTFontVariationAttribute: [tag("wght"): 400, tag("opsz"): min(72, max(6, size))],
    ]
    if oldstyle {
      attrs[kCTFontFeatureSettingsAttribute] = [[kCTFontOpenTypeFeatureTag: "onum", kCTFontOpenTypeFeatureValue: 1]]
    }
    let d = CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary)
    return CTFontCreateWithFontDescriptor(d, size, nil)
  }

  /// A drawn line: where its baseline starts, measured from the page's top-left.
  struct Placed {
    let line: CTLine
    let x, baseline: CGFloat
  }

  static func attributed(_ s: String, _ font: CTFont, gray: CGFloat = 0, tracking: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
      NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ])
  }

  /// [s] broken into lines [width] wide; a hard line break inside it is kept.
  static func lines(_ s: String, _ font: CTFont, width: CGFloat, tracking: CGFloat = 0) -> [CTLine] {
    var out: [CTLine] = []
    for segment in s.components(separatedBy: "\n") {
      let text = attributed(segment.trimmingCharacters(in: .whitespaces), font, tracking: tracking)
      if text.length == 0 {
        out.append(CTLineCreateWithAttributedString(text))
        continue
      }
      let ts = CTTypesetterCreateWithAttributedString(text)
      var start = 0
      while start < text.length {
        let n = CTTypesetterSuggestLineBreak(ts, start, Double(width))
        out.append(CTTypesetterCreateLine(ts, CFRange(location: start, length: n)))
        start += max(1, n)
      }
    }
    return out
  }

  func write(to url: URL) throws {
    let letter = Self.usesLetter()
    let page = letter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    let m = Self.margin, width = page.width - 2 * m
    let top = m, bottom = page.height - m

    // ---- page 1's heading ----
    var pages: [[Placed]] = [[]]
    var y = top
    func put(_ ls: [CTLine], leading: CGFloat, ascent: CGFloat) {
      for l in ls {
        pages[pages.count - 1].append(Placed(line: l, x: m, baseline: y + ascent))
        y += leading
      }
    }
    let dateFont = Self.font(italic: false, size: 9.5, figures: true)
    put(Self.lines(date, dateFont, width: width, tracking: 0.1), leading: 14, ascent: 10)
    y += 10
    let titleFont = Self.font(italic: false, size: 26)
    put(Self.lines(title, titleFont, width: width, tracking: -0.3), leading: 31, ascent: 25)
    if !from.isEmpty {
      y += 5
      put(Self.lines(from, Self.font(italic: true, size: 13.5), width: width), leading: 19, ascent: 14)
    }
    if !recipient.isEmpty {
      y += from.isEmpty ? 6 : 1
      put(Self.lines(recipient, Self.font(italic: false, size: 11), width: width), leading: 16, ascent: 12)
    }
    y += 16
    let ruleY = y
    y += 26

    // ---- the words ----
    let body = Self.font(italic: false, size: Self.bodySize, figures: true)
    let lead = Self.bodyLeading, ascent: CGFloat = 13
    var pageTop = false // y is at the top of a fresh page
    for para in paragraphs {
      let ls = Self.lines(para, body, width: width)
      var i = 0
      if !pageTop && y > top + 1 { y += Self.paragraphGap }
      while i < ls.count {
        // whole lines that still fit above the bottom margin
        let fit = max(0, Int(((bottom - y) / lead + 0.001).rounded(.down)))
        let left = ls.count - i
        var take = min(fit, left)
        if take < left {
          // no single line alone at the foot (the paragraph's first) or the head (its last)
          if left - take == 1 { take = max(0, take - 1) }
          if i == 0 && take == 1 { take = 0 }
          // a page with nothing on it yet takes what fits, whatever is stranded
          if take <= 0 && pageTop { take = max(1, min(fit, left)) }
        }
        for l in ls[i ..< i + max(0, take)] {
          pages[pages.count - 1].append(Placed(line: l, x: m, baseline: y + ascent))
          y += lead
          pageTop = false
        }
        i += max(0, take)
        if i < ls.count {
          pages.append([])
          y = top
          pageTop = true
        }
      }
    }

    // ---- drawing ----
    var box = page
    let info: [CFString: Any] = [kCGPDFContextTitle: title]
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
      throw NSError(domain: "share", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not make the PDF"])
    }
    let footerFont = Self.font(italic: false, size: Self.footerSize, figures: true)
    for (n, placed) in pages.enumerated() {
      ctx.beginPDFPage(nil)
      // Core Graphics draws from the bottom-left; the layout above is from the top-left
      func draw(_ l: CTLine, x: CGFloat, baseline: CGFloat) {
        ctx.textPosition = CGPoint(x: x, y: page.height - baseline)
        CTLineDraw(l, ctx)
      }
      if n == 0 {
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: m, y: page.height - ruleY))
        ctx.addLine(to: CGPoint(x: m + 96, y: page.height - ruleY))
        ctx.strokePath()
      }
      for p in placed { draw(p.line, x: p.x, baseline: p.baseline) }
      if n > 0 {
        let numbers = pageOf.replacingOccurrences(of: "{n}", with: "\(n + 1)").replacingOccurrences(of: "{total}", with: "\(pages.count)")
        let right = CTLineCreateWithAttributedString(Self.attributed(numbers, footerFont, gray: 0.35))
        let rw = CGFloat(CTLineGetTypographicBounds(right, nil, nil, nil))
        let full = CTLineCreateWithAttributedString(Self.attributed(title, footerFont, gray: 0.35))
        let ellipsis = CTLineCreateWithAttributedString(Self.attributed("…", footerFont, gray: 0.35))
        let left = CTLineCreateTruncatedLine(full, Double(width - rw - 24), .end, ellipsis) ?? full
        let base = page.height - m + 34
        draw(left, x: m, baseline: base)
        draw(right, x: m + width - rw, baseline: base)
      }
      ctx.endPDFPage()
    }
    ctx.closePDF()
  }
}

/// Blessing files that arrive: tapped in Files, Mail or Messages, or received by AirDrop. iOS hands
/// the app the file's URL (SceneDelegate); its bytes are read here, up to the limit, and the copy iOS
/// made inside the app's folders (Documents/Inbox) is removed at once. A file opened in place from
/// Files stays where it is, untouched. Dart reads the bytes strictly (lib/share/blessing_file.dart).
///
/// Before Dart is ready (the app was launched by the file) they wait here; Dart asks with
/// `receiving` once the sky is up and is sent each later one with `incoming` {bytes} or {tooLarge}.
enum BlessingInbox {
  static let scenes = SceneListener()

  final class SceneListener: NSObject, FlutterSceneLifeCycleDelegate {
    /// Launched by a file (the app was closed).
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
      let contexts = (connectionOptions?.urlContexts ?? []).map(\.url)
      let urls = contexts.filter(\.isFileURL)
      NSLog("receive: launched with %d file(s)", urls.count)
      urls.forEach(receive)
      // a universal link (the app was closed), or the simulator's stand-in for one
      let links = (connectionOptions?.userActivities ?? []).compactMap(webLink) + contexts.filter(isTestLink)
      links.forEach(receiveLink)
      // one of the app's own Spotlight entries (Shortcuts.swift): its place
      let spotlight = (connectionOptions?.userActivities ?? []).compactMap(SpotlightEntry.place)
      spotlight.forEach(BlessingInbox.receiveShortcut)
      return !urls.isEmpty || !links.isEmpty || !spotlight.isEmpty
    }

    /// While running or in the background.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
      let all = URLContexts.map(\.url)
      let urls = all.filter(\.isFileURL)
      NSLog("receive: opened with %d file(s)", urls.count)
      urls.forEach(receive)
      let links = all.filter(isTestLink)
      links.forEach(receiveLink)
      return !urls.isEmpty || !links.isEmpty
    }

    /// A universal link while running or in the background (`scene(_:continue:)`).
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
      if let place = SpotlightEntry.place(userActivity) {
        BlessingInbox.receiveShortcut(place)
        return true
      }
      guard let url = webLink(userActivity) else { return false }
      receiveLink(url)
      return true
    }

    func webLink(_ a: NSUserActivity) -> URL? {
      guard a.activityType == NSUserActivityTypeBrowsingWeb, let url = a.webpageURL, url.path.hasPrefix("/b/") else { return nil }
      return url
    }

    /// The simulator cannot hand an app a universal link for a site that is not live, so debug builds
    /// also take `uponthyhead-test://b/<id>#<key>` (registered in Info.plist), which lib/share/
    /// link_format.dart reads the same way. Release builds ignore it.
    func isTestLink(_ url: URL) -> Bool {
      #if DEBUG
      return url.scheme == "uponthyhead-test"
      #else
      return false
      #endif
    }
  }

  /// A blessing link: handed to Dart whole, fragment and all. Never logged: it holds the key.
  static func receiveLink(_ url: URL) {
    NSLog("receive: a link (fragment %@)", url.fragment == nil ? "missing" : "present")
    let item: [String: Any] = ["link": url.absoluteString]
    if listening, let c = ShareChannel.channel {
      c.invokeMethod("incoming", arguments: item)
    } else {
      waiting.append(item)
    }
  }

  /// An App Shortcut or one of the app's Spotlight entries (Shortcuts.swift): where the app should open. It
  /// waits, as a link does, until Dart is ready; only the newest one counts there.
  static func receiveShortcut(_ place: ShortcutPlace) {
    NSLog("receive: shortcut %@", place.rawValue)
    let item: [String: Any] = ["shortcut": place.rawValue]
    if listening, let c = ShareChannel.channel {
      c.invokeMethod("incoming", arguments: item)
    } else {
      waiting.append(item)
    }
  }

  /// The same limit as lib/share/blessing_file.dart's blessingFileMaxBytes.
  static let maxBytes = 512 * 1024
  static var waiting: [[String: Any]] = []
  static var listening = false

  static func ready(_ result: FlutterResult) {
    listening = true
    let w = waiting
    waiting = []
    result(w)
    cleanInbox()
  }

  /// A file from iOS (any thread-safe point on the main thread).
  static func receive(_ url: URL) {
    let item = read(url)
    if listening, let c = ShareChannel.channel {
      c.invokeMethod("incoming", arguments: item)
    } else {
      waiting.append(item)
    }
  }

  static func read(_ url: URL) -> [String: Any] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
      removeIfOurs(url)
    }
    var coordinated: [String: Any] = ["unreadable": true]
    var err: NSError?
    // Files may hold it in a provider; coordinate so it is all there before reading
    NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &err) { u in
      guard let h = try? FileHandle(forReadingFrom: u) else { return }
      defer { try? h.close() }
      let data = (try? h.read(upToCount: maxBytes + 1)) ?? Data()
      if data.count > maxBytes {
        coordinated = ["tooLarge": true]
      } else {
        coordinated = ["bytes": FlutterStandardTypedData(bytes: data), "name": u.lastPathComponent]
      }
    }
    if let err { NSLog("receive: %@", err.localizedDescription) }
    return coordinated
  }

  /// The app's own folders, resolved (/private/var and /var are the same place).
  static var home: String { URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path }

  static func removeIfOurs(_ url: URL) {
    let path = url.resolvingSymlinksInPath().path
    guard path.hasPrefix(home + "/") else { return }
    try? FileManager.default.removeItem(atPath: path)
    cleanInbox()
  }

  /// Documents/Inbox, where iOS puts the copies it hands an app; nothing of ours lives there.
  static var inbox: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox", isDirectory: true)
  }

  static func cleanInbox() {
    try? FileManager.default.removeItem(at: inbox)
  }

  /// Tests: any `.blessing` file anywhere in the app's folders.
  static func leftovers() -> [String] {
    var out: [String] = []
    let root = URL(fileURLWithPath: home)
    if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
      for case let u as URL in e where u.pathExtension.lowercased() == "blessing" {
        out.append(String(u.resolvingSymlinksInPath().path.dropFirst(home.count)))
      }
    }
    return out
  }
}
