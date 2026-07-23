import ArgumentParser
import Foundation

/// `ainkrad new` — scaffolds a ready-to-build Ainkrad App from the embedded
/// `AinkradPluginTemplate`, performing the identity find/replace a developer
/// does by hand today (id, display name, icon, and the derived Swift/target
/// names) and stamping the CLI's target SDK generation.
///
/// Kept thin: all scaffolding logic lives in `TemplateScaffolder`.
struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Scaffold a new Ainkrad App from the embedded template."
    )

    @Argument(help: "The app's name — a valid Swift identifier, e.g. MyWidget.")
    var name: String

    @Option(help: "The app id (letters, digits, '.', '_', '-'). Defaults to the name.")
    var id: String?

    @Option(name: .customLong("display-name"), help: "The display name shown in the UI. Defaults to the name.")
    var displayName: String?

    @Option(help: "The SF Symbol used as the app's icon.")
    var icon: String = "puzzlepiece.extension"

    @Option(help: "Directory to scaffold into. Defaults to './<name>'.")
    var into: String?

    func run() throws {
        let resolvedID = id ?? name
        let resolvedDisplayName = displayName ?? name
        let destination = URL(fileURLWithPath: into ?? name)

        try TemplateScaffolder().scaffold(
            name: name,
            id: resolvedID,
            displayName: resolvedDisplayName,
            icon: icon,
            into: destination
        )

        print("Scaffolded \(resolvedDisplayName) (\(resolvedID)) into \(destination.path)")
    }
}
