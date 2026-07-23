import SwiftUI
import AinkradAppKit

/// Your app. Rename `MyApp`, the id, name, and icon. Read theme via
/// `host.theme.tokens` and persist via `host.documents` — never host internals.
struct MyApp: AinkradApp {
    static let id = "myplugin"
    static let displayName = "My Plugin"
    static let icon = "puzzlepiece.extension"

    static func makeRootView(host: HostServices) -> AnyView {
        AnyView(
            Text("Hello from My Plugin 👋")
                .foregroundStyle(host.theme.tokens.accentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(host.theme.tokens.background)
        )
    }

    static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(Text("My Plugin settings"))
    }
}
