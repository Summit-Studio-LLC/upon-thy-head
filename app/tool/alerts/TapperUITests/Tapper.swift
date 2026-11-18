import XCTest

/// Answers the system's own dialogs on the simulator for the acceptance scripts (tool/lock_acceptance.sh):
/// permission questions, the Face ID permission, and the app switcher, by the labels a person sees.
///
/// Runs for up to RUN_SECONDS (default 1800), reading one command at a time from `$DIR/cmd`
/// (written whole by the script) and answering in `$DIR/out`:
///  - `tap <label>`: wait up to 12 s for a button with that label in a system alert and tap it;
///    answers `ok <alert title> | <alert text>` or `missing <what is on screen>`
///  - `alert`: the title and text of the alert on screen, or `none`
///  - `home`: press Home
///  - `switcher`: swipe up from the bottom edge and hold, as a person opens the app switcher
///  - `open <bundle id>`: bring that app to the front
///  - `apptap <label>[|<label>…]`: wait up to 12 s for a button or row with one of those labels inside
///    the app under test (the system share sheet it presents) and tap it; `ok <label>` or `missing …`
///  - `apphold <seconds> <label>[|<label>…]`: as `apptap`, but pressed and held, as a person holds
///    Amen; `ok <label>` or `missing …`
///  - `appswipeup`: drag the app's page up, to scroll it
///  - `appdismiss`: swipe the app's presented sheet down
///  - `appenabled <label>`: whether the app's button with that label is enabled now: `yes`, `no` or
///    `missing`
///  - `applabels`: the labels of the buttons and rows the app shows now (for writing scripts)
///  - `files <name>`: open the Files app, go to On My iPhone, and tap the file whose name starts with
///    <name>, as a person opens a file they were sent; `ok <label>` or `missing …`
///  - `fileslabels`: what the Files app shows now (for writing scripts)
///  - `sbhold [x y]`, `sbtap <label>`, `sblabels`: hold, tap or read the home screen (the icon style)
///  - `spotlight <words>`: Home, Spotlight opened by a swipe down, the words typed; answers every
///    label it then shows. `spotlighttap <label>`: tap the first result whose label starts so;
///    `spotlightscroll`: drag the results up; `spotlightlabels`: the labels of its result rows; `spotlighttree`: everything it shows
///  - `quit`: stop
final class Tapper: XCTestCase {
  let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  func testAnswer() throws {
    continueAfterFailure = true
    let env = ProcessInfo.processInfo.environment
    let dir = URL(fileURLWithPath: env["TAPPER_DIR"] ?? "/tmp/uth_tapper")
    let seconds = Double(env["RUN_SECONDS"] ?? "1800") ?? 1800
    let cmd = dir.appendingPathComponent("cmd"), out = dir.appendingPathComponent("out")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? "ready".write(to: dir.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
      guard let line = try? String(contentsOf: cmd, encoding: .utf8) else {
        Thread.sleep(forTimeInterval: 0.2)
        continue
      }
      try? FileManager.default.removeItem(at: cmd)
      let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
      let verb = parts.first ?? "", arg = parts.count > 1 ? parts[1] : ""
      var answer = "ok"
      switch verb {
      case "tap": answer = tap(arg)
      case "alert": answer = describe()
      case "tree": answer = hosts.map { $0.debugDescription }.joined(separator: "\n----\n")
      case "home": XCUIDevice.shared.press(.home)
      case "switcher":
        let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        let to = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1.2)
      case "open": XCUIApplication(bundleIdentifier: arg).activate()
      case "apptap": answer = appTap(arg.components(separatedBy: "|"))
      case "apphold":
        let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
        answer = appTap(parts.count > 1 ? parts[1].components(separatedBy: "|") : [], hold: Double(parts.first ?? "") ?? 1.5)
      case "appdismiss":
        // the iOS 26 share sheet has no Close button. `appdismiss <n>`: 0 taps outside it, 1 drags it
        // down by its top edge, 2 swipes down on the sheet itself
        let app = XCUIApplication(bundleIdentifier: appBundle)
        switch Int(arg) ?? 0 {
        case 0: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        case 1:
          let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.578))
          from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        default:
          let sheet = app.collectionViews.firstMatch
          if sheet.exists { sheet.swipeDown(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
        }
      case "appenabled":
        let e = XCUIApplication(bundleIdentifier: appBundle).buttons.matching(NSPredicate(format: "label == %@", arg)).firstMatch
        answer = e.exists ? (e.isEnabled ? "yes" : "no") : "missing"
      case "applabels":
        let app = XCUIApplication(bundleIdentifier: appBundle)
        guard app.state != .notRunning else { answer = "notrunning"; break }
        answer = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex).map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      case "appall":
        // every labelled element, the rows and lines too (applabels is buttons and cells only)
        let app = XCUIApplication(bundleIdentifier: appBundle)
        guard app.state != .notRunning else { answer = "notrunning"; break }
        answer = app.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      case "appswipeup":
        // drag the app's page up by two thirds of the screen, slowly, so it scrolls without a fling
        let app = XCUIApplication(bundleIdentifier: appBundle)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
          .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        answer = "ok"
      case "sbhold":
        // press and hold the home screen at a normalized point (default an empty spot low down)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let xy = arg.split(separator: " ").compactMap { Double($0) }
        sb.coordinate(withNormalizedOffset: CGVector(dx: xy.count == 2 ? xy[0] : 0.5, dy: xy.count == 2 ? xy[1] : 0.78)).press(forDuration: 1.6)
        answer = "ok"
      case "sbtap":
        // tap the first home-screen element (any kind) with that label, waiting up to 6 s
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let e = sb.descendants(matching: .any).matching(NSPredicate(format: "label == %@", arg)).firstMatch
        if e.waitForExistence(timeout: 6) { e.tap(); answer = "ok \(arg)" } else { answer = "missing \(arg)" }
      case "sblabels":
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        answer = sb.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      case "spotlight":
        // the home screen, Spotlight opened by a swipe down, the words typed; answers what it lists
        answer = spotlight(arg)
      case "spotlighttap":
        // tap the first Spotlight result with that label (waiting up to 12 s)
        answer = spotlightTap(arg)
      case "spotlightscroll":
        // the keyboard away, then the results dragged up by half a screen
        let sp = spotlightApp
        // only while Spotlight is up (a drag on an app not in front cannot be placed, and stops the test)
        guard sp.state == .runningForeground, sp.frame.width > 0 else { answer = "nospotlight"; break }
        sp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
          .press(forDuration: 0.1, thenDragTo: sp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
      case "spotlightlabels":
        answer = spotlightApp.cells.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      case "spotlighttree":
        answer = spotlightApp.debugDescription
      case "orient":
        XCUIDevice.shared.orientation = arg == "landscape" ? .landscapeLeft : .portrait
      case "files": answer = openInFiles(arg)
      case "fileslabels":
        let f = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        answer = (f.buttons.allElementsBoundByIndex + f.cells.allElementsBoundByIndex + f.staticTexts.allElementsBoundByIndex).map(\.label).filter { !$0.isEmpty }.prefix(80).joined(separator: " | ")
      case "quit":
        try? "bye".write(to: out, atomically: true, encoding: .utf8)
        return
      default: answer = "unknown \(verb)"
      }
      try? answer.write(to: out, atomically: true, encoding: .utf8)
    }
  }

  /// Spotlight as a person opens it: Home, a swipe down on the home screen, the words typed. Answers
  /// the labels of everything it then shows (the results), or `nofield` if no search field came up.
  func spotlight(_ words: String) -> String {
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 1)
    let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
    from.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
    // iOS 26 draws Spotlight in its own process
    let end = Date().addingTimeInterval(8)
    while spotlightApp.state != .runningForeground && Date() < end { Thread.sleep(forTimeInterval: 0.3) }
    guard spotlightApp.state == .runningForeground else { return "nofield" }
    Thread.sleep(forTimeInterval: 1)
    // Spotlight may open on the last search: cleared first
    let clear = spotlightApp.buttons["Clear text"]
    if clear.exists { clear.tap(); Thread.sleep(forTimeInterval: 0.5) }
    // the field has the keyboard as Spotlight opens
    spotlightApp.typeText(words)
    Thread.sleep(forTimeInterval: 4)
    return spotlightApp.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
  }

  let spotlightApp = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")

  /// The result row with that label, tapped once it is on screen: the results are dragged down, then
  /// up, a third of a screen at a time, until it is (its place in the list changes with use).
  func spotlightTap(_ label: String) -> String {
    let sp = spotlightApp
    guard sp.state == .runningForeground else { return "nospotlight" }
    // an App Shortcut's row is labelled with its title alone; a Core Spotlight entry's with its title,
    // a comma and its description
    let row = sp.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ",")).firstMatch
    let moves: [CGFloat] = [0, 0.33, 0.33, 0.33, -0.33, -0.33, -0.33, -0.33, -0.33, -0.33]
    for m in moves {
      if m != 0 {
        let from = sp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.1, thenDragTo: sp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45 + m)))
        Thread.sleep(forTimeInterval: 0.6)
      }
      if row.exists && row.isHittable && row.frame.minY > 60 && row.frame.maxY < sp.frame.height * 0.85 {
        row.tap()
        return "ok \(label)"
      }
    }
    return "missing \(label)"
  }

  /// Where the system's own questions are drawn: permission alerts by SpringBoard, the Face ID
  /// sheet and its "Face Not Recognized" by CoreAuthUI.
  lazy var all = [springboard, XCUIApplication(bundleIdentifier: "com.apple.CoreAuthUI")]
  var hosts: [XCUIApplication] { all.filter { $0.state != .notRunning && $0.state != .unknown } }

  /// The title and text of what the system shows, or none.
  func describe() -> String {
    for h in hosts {
      let a = h.alerts.firstMatch
      if a.exists {
        return a.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      }
    }
    for h in hosts where h != springboard {
      let texts = h.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
      if !texts.isEmpty { return texts.joined(separator: " | ") }
    }
    return "none"
  }

  let appBundle = ProcessInfo.processInfo.environment["APP_BUNDLE"] ?? "dev.summitstudio.uponThyHead"

  /// A button or a row of the share sheet the app presents, by its label.
  func appTap(_ labels: [String], hold: Double = 0) -> String {
    let app = XCUIApplication(bundleIdentifier: appBundle)
    guard app.state != .notRunning else { return "notrunning" }
    let end = Date().addingTimeInterval(12)
    while Date() < end {
      for l in labels {
        for q in [app.buttons, app.cells, app.staticTexts] {
          let e = q.matching(NSPredicate(format: "label == %@", l)).firstMatch
          if e.exists && e.isHittable {
            if hold > 0 { e.press(forDuration: hold) } else { e.tap() }
            return "ok \(l)"
          }
        }
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    let seen = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex).prefix(40).map(\.label).filter { !$0.isEmpty }
    return "missing \(labels.joined(separator: "|")) among: " + seen.joined(separator: " | ")
  }

  /// Files: Browse, On My iPhone, then the file. The file's cell is found by the start of its name
  /// (Files may hide the extension).
  func openInFiles(_ name: String) -> String {
    let f = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    f.activate()
    let end = Date().addingTimeInterval(40)
    var steps: [String] = []
    while Date() < end {
      let match = NSPredicate(format: "label BEGINSWITH %@", name)
      for q in [f.cells] { // the file itself, never a bare label that opens nothing
        let e = q.matching(match).firstMatch
        if e.exists && e.isHittable {
          // read before the tap: the app it opens takes Files off the screen, and a query then fails
          let label = e.label
          e.tap()
          return "ok \(label) after \(steps.joined(separator: ", "))"
        }
      }
      // get to On My iPhone: the Browse tab, then the location (back out of any folder first)
      let onPhone = f.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPhone' AND (elementType == %d OR elementType == %d OR elementType == %d)", XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.staticText.rawValue)).firstMatch
      if onPhone.exists && onPhone.isHittable {
        onPhone.tap()
        steps.append("On My iPhone")
        Thread.sleep(forTimeInterval: 1.5)
        continue
      }
      let browse = f.buttons.matching(NSPredicate(format: "label == 'Browse'")).firstMatch
      if browse.exists && browse.isHittable {
        browse.tap()
        steps.append("Browse")
        Thread.sleep(forTimeInterval: 1.0)
        // a second tap on Browse goes to its top level
        if !onPhone.exists { browse.tap() }
        continue
      }
      // "Continue" on a first-run sheet, and the like
      for l in ["Continue", "Not Now", "Done"] {
        let b = f.buttons[l]
        if b.exists && b.isHittable { b.tap(); steps.append(l) }
      }
      Thread.sleep(forTimeInterval: 0.5)
    }
    let seen = (f.buttons.allElementsBoundByIndex + f.cells.allElementsBoundByIndex).prefix(40).map(\.label).filter { !$0.isEmpty }
    return "missing \(name) after \(steps.joined(separator: ", ")) among: " + seen.joined(separator: " | ")
  }

  func tap(_ label: String) -> String {
    let end = Date().addingTimeInterval(12)
    // the system writes "Don’t Allow" with a typographer's apostrophe
    let labels = [label, label.replacingOccurrences(of: "'", with: "\u{2019}")]
    while Date() < end {
      for h in hosts {
        for l in labels {
          // the Face ID alert nests each button in another of the same label: take the first
          let b = (h.alerts.count > 0 ? h.alerts.firstMatch.buttons[l] : h.buttons[l]).firstMatch
          if b.exists {
            let what = describe()
            b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return "ok \(what)"
          }
        }
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return "missing " + describe()
  }
}
