import Flutter
import UIKit

/// The language choice on the recording screen: a clear UIButton laid over the words Flutter
/// draws ("English ⌃⌄"), which opens the system pull-down menu (UIMenu) with English and Español.
/// lib/record/language_menu.dart places it. Each view talks on `upon_thy_head/language_menu/<id>`:
///  - Dart → iOS `select` {code}: tick the current language
///  - iOS → Dart `picked` {code}: the person chose one
///  - Dart → iOS `debugOpen`, `debugClose`: open and close the menu as a tap would (tests)
final class LanguageMenuFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let a = args as? [String: Any] ?? [:]
    // Settings passes its own three ("Same as this iPhone", English, Español); Begin uses the two
    let given = (a["choices"] as? [[String]])?.compactMap { $0.count == 2 ? (code: $0[0], title: $0[1]) : nil }
    return LanguageMenu(
      frame: frame, id: viewId, selected: a["code"] as? String ?? "en", label: a["label"] as? String ?? "",
      choices: given?.isEmpty == false ? given! : LanguageMenu.choices, messenger: messenger)
  }
}

final class LanguageMenu: NSObject, FlutterPlatformView {
  static let choices: [(code: String, title: String)] = [("en", "English"), ("es", "Español")]

  private let button = BelowMenuButton(type: .custom)
  private let channel: FlutterMethodChannel
  private var selected: String
  private let options: [(code: String, title: String)]

  init(frame: CGRect, id: Int64, selected: String, label: String, choices: [(code: String, title: String)], messenger: FlutterBinaryMessenger) {
    self.selected = selected
    options = choices
    channel = FlutterMethodChannel(name: "upon_thy_head/language_menu/\(id)", binaryMessenger: messenger)
    super.init()
    button.frame = frame
    button.backgroundColor = .clear
    button.accessibilityLabel = label
    button.accessibilityTraits = .button
    // the app is drawn dark; so is its menu
    button.overrideUserInterfaceStyle = .dark
    // English, then Español, wherever the menu opens
    button.preferredMenuElementOrder = .fixed
    button.showsMenuAsPrimaryAction = true
    button.menu = menu()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "select":
        self.selected = (call.arguments as? [String: Any])?["code"] as? String ?? self.selected
        self.button.menu = self.menu()
        result(nil)
      case "debugOpen":
        // UIKit aborts if a menu is presented from a view that is in no window
        if #available(iOS 17.4, *), self.button.window != nil { self.button.performPrimaryAction() }
        result(nil)
      case "debugClose":
        self.button.contextMenuInteraction?.dismissMenu()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { button }

  private func menu() -> UIMenu {
    UIMenu(children: options.map { c in
      UIAction(title: c.title, state: c.code == selected ? .on : .off) { [weak self] _ in self?.pick(c.code) }
    })
  }

  private func pick(_ code: String) {
    selected = code
    button.menu = menu()
    channel.invokeMethod("picked", arguments: ["code": code])
  }
}

/// A button whose menu hangs below it. Left to itself, iOS centres the menu on the button, so it
/// covered the bottom of the Begin ring above.
final class BelowMenuButton: UIButton {
  override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
    CGPoint(x: bounds.midX, y: bounds.maxY + 4)
  }
}
