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
///  - `appdismiss`: swipe the app's presented sheet down
///  - `applabels`: the labels of the buttons and rows the app shows now (for writing scripts)
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
      case "applabels":
        let app = XCUIApplication(bundleIdentifier: appBundle)
        answer = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex).map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
      case "quit":
        try? "bye".write(to: out, atomically: true, encoding: .utf8)
        return
      default: answer = "unknown \(verb)"
      }
      try? answer.write(to: out, atomically: true, encoding: .utf8)
    }
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
  func appTap(_ labels: [String]) -> String {
    let app = XCUIApplication(bundleIdentifier: appBundle)
    let end = Date().addingTimeInterval(12)
    while Date() < end {
      for l in labels {
        for q in [app.buttons, app.cells, app.staticTexts] {
          let e = q.matching(NSPredicate(format: "label == %@", l)).firstMatch
          if e.exists && e.isHittable {
            e.tap()
            return "ok \(l)"
          }
        }
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    let seen = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex).prefix(40).map(\.label).filter { !$0.isEmpty }
    return "missing \(labels.joined(separator: "|")) among: " + seen.joined(separator: " | ")
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
