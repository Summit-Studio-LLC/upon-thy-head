import SwiftUI

/// An empty app: only the host for the UI test that answers the system's questions
/// (TapperUITests). Never installed for anything else.
@main
struct TapperApp: App {
  var body: some Scene { WindowGroup { Text("Tapper") } }
}
