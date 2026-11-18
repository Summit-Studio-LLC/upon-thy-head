import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// The app in Spotlight, Siri and the Shortcuts app: two App Shortcuts (listed under the app from
/// install, with nothing to set up) and two Core Spotlight entries that carry the same two places.
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

/// Two Core Spotlight entries, written at each launch, that answer plain words: "Record a blessing"
/// (the recording start, as the action) and "My priesthood blessings" (home; the title carries
/// "priesthood" because only title words are matched). Spotlight on iOS 26 matched the
/// old single entry ("Upon Thy Head", content type .application) only by its title, and the same
/// holds for these (tested 2026-11-18 on the simulator): words only in `keywords`, `textContent` or
/// `alternateNames` ("priesthood", "patriarchal") bring nothing up, while a title word or its prefix
/// ("bless") does. So the words a person types are in the titles; the description and keywords
/// stay, in the phone's language, in case a later iOS uses them. Tapping one goes through
/// BlessingInbox.receiveShortcut, so the lock and the "never leave work in progress" rules are those
/// of the App Shortcuts.
enum SpotlightEntry {
  /// The old single entry (build 2), removed from the index.
  static let oldId = "dev.summitstudio.uponThyHead.app"
  static let recordId = "dev.summitstudio.uponThyHead.record"
  static let homeId = "dev.summitstudio.uponThyHead.home"

  static let keywordsEn = [
    "blessing", "blessings", "bless", "priesthood", "priesthood blessing", "patriarchal blessing",
    "father's blessing", "setting apart", "ordination", "baby blessing", "confirmation", "record",
  ]
  static let keywordsEs = [
    "bendición", "bendiciones", "bendecir", "sacerdocio", "bendición del sacerdocio", "bendición patriarcal",
    "bendición de padre", "apartamiento", "ordenación", "bendición de un bebé", "confirmación", "grabar",
  ]

  static func write() {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    let spanish = Bundle.main.preferredLocalizations.first == "es"
    func item(_ id: String, _ title: String, _ about: String) -> CSSearchableItem {
      let a = CSSearchableItemAttributeSet(contentType: .text)
      a.title = NSLocalizedString(title, comment: "Spotlight")
      a.displayName = a.title
      a.contentDescription = NSLocalizedString(about, comment: "Spotlight")
      a.keywords = spanish ? keywordsEs : keywordsEn
      let i = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: "shortcuts", attributeSet: a)
      i.expirationDate = .distantFuture
      return i
    }
    let items = [
      item(recordId, "Record a blessing", "Opens Upon Thy Head ready to record. Nothing is recorded until you press Begin."),
      item(homeId, "My priesthood blessings", "Opens Upon Thy Head at the night sky of your blessings."),
    ]
    let index = CSSearchableIndex.default()
    index.deleteSearchableItems(withIdentifiers: [oldId]) { _ in
      index.indexSearchableItems(items) { error in
        NSLog("spotlight: %@", error.map { "indexing failed: \($0.localizedDescription)" } ?? "indexed 2 entries")
      }
    }
  }

  /// Where a tapped Spotlight entry of the app leads, or nil if the activity is not one.
  static func place(_ a: NSUserActivity) -> ShortcutPlace? {
    guard a.activityType == CSSearchableItemActionType,
          let id = a.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
    switch id {
    case recordId: return .record
    case homeId, oldId: return .home
    default: return nil
    }
  }
}
