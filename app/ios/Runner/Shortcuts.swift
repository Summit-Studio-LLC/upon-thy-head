import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// The app in Spotlight, Siri and the Shortcuts app: two App Shortcuts (listed under the app from
/// install, with nothing to set up) and one Core Spotlight entry for the app as a whole.
///
/// Privacy: only the fixed words below are ever given to the system. Nothing of any blessing (no
/// name, date, title, words, count or place) is indexed, donated or put in a phrase, and no
/// NSUserActivity is donated for a blessing.
///
/// Each one opens the app and hands Dart a place to go, the way a blessing link is handed over
/// (BlessingInbox in Share.swift): `{shortcut: "record"}` or `{shortcut: "home"}`, waiting there until
/// Dart is ready (a cold start) or sent at once with `incoming` (the app was running). Dart goes
/// there only once the app is unlocked (lib/home/home_screen.dart, "shortcuts").

/// "Record a blessing": the app at its recording start (the screen New blessing opens). The
/// microphone does not start: Begin is still the person's own press.
struct RecordBlessingIntent: AppIntent {
  static let title: LocalizedStringResource = "Record a blessing"
  static let description = IntentDescription("Opens Upon Thy Head ready to record. Nothing is recorded until you press Begin.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    BlessingInbox.receiveShortcut(.record)
    return .result()
  }
}

/// "Open my blessings": the app at its home, the night sky.
struct OpenBlessingsIntent: AppIntent {
  static let title: LocalizedStringResource = "Open my blessings"
  static let description = IntentDescription("Opens Upon Thy Head at the night sky of your blessings.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    BlessingInbox.receiveShortcut(.home)
    return .result()
  }
}

/// The phrases are in AppShortcuts.strings (en.lproj, es.lproj); the titles in Localizable.strings.
struct UponThyHeadShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RecordBlessingIntent(),
      phrases: [
        "Record a blessing in \(.applicationName)",
        "Record a blessing with \(.applicationName)",
        "New blessing in \(.applicationName)",
        "\(.applicationName) record a blessing",
      ],
      shortTitle: "Record a blessing",
      systemImageName: "mic")
    AppShortcut(
      intent: OpenBlessingsIntent(),
      phrases: [
        "Open my blessings in \(.applicationName)",
        "Show my blessings in \(.applicationName)",
      ],
      shortTitle: "Open my blessings",
      systemImageName: "moon.stars")
  }

  static let shortcutTileColor: ShortcutTileColor = .navy
}

/// Where a shortcut leads, as Dart reads it.
enum ShortcutPlace: String {
  case record, home
}

/// One entry for the app as a whole, written at each launch: its name, one line about it, and words
/// people may search for. Tapping it opens the app at home (BlessingInbox's scene listener).
enum SpotlightEntry {
  static let id = "dev.summitstudio.uponThyHead.app"

  static let keywords = [
    "blessing", "blessings", "priesthood", "priesthood blessing", "patriarchal blessing", "father's blessing",
    "setting apart", "ordination", "baby blessing", "confirmation",
    "bendición", "bendiciones", "sacerdocio", "bendición del sacerdocio", "bendición patriarcal", "bendición de padre",
    "apartamiento", "ordenación", "bendición de un bebé", "confirmación",
  ]

  static func write() {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    let a = CSSearchableItemAttributeSet(contentType: .application)
    a.title = "Upon Thy Head"
    a.displayName = "Upon Thy Head"
    a.contentDescription = NSLocalizedString("Record a blessing as it is given, and keep its words on this phone.", comment: "Spotlight")
    a.keywords = keywords
    let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: "app", attributeSet: a)
    item.expirationDate = .distantFuture
    CSSearchableIndex.default().indexSearchableItems([item]) { error in
      if let error { NSLog("spotlight: %@", error.localizedDescription) }
    }
  }

  /// The entry was tapped in Spotlight.
  static func isOurs(_ a: NSUserActivity) -> Bool {
    a.activityType == CSSearchableItemActionType && (a.userInfo?[CSSearchableItemActivityIdentifier] as? String) == id
  }
}
