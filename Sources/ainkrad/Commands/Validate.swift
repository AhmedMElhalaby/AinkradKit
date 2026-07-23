import AinkradAppKit
import ArgumentParser
import Foundation

/// `ainkrad validate` — runs the EXACT same metadata checks the real host
/// runs against a built `.bundle`, by calling straight into the shared
/// `AinkradAppKit.PluginValidation` module. This is parity by construction:
/// "passes `ainkrad validate`" and "passes install" cannot diverge, because
/// both paths call the same code.
struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a built .bundle against the host's plugin metadata checks."
    )

    @Argument(help: "Path to the built .bundle to validate.")
    var bundlePath: String

    @Flag(help: "Also run App Store submission checks (pending sub-project D).")
    var store = false

    func run() throws {
        let bundleURL = URL(fileURLWithPath: bundlePath)

        do {
            try Validate.check(bundleURL: bundleURL, inspector: BundleInspector())
        } catch {
            print(Validate.message(for: error))
            throw ExitCode(1)
        }

        if store {
            // Sub-project D (StorePolicy) has not landed yet: run the same
            // base checks above and say so explicitly, rather than inventing
            // store-only checks here.
            print("Base checks passed. Store checks pending sub-project D.")
        } else {
            print("\(bundlePath) is valid.")
        }
    }

    /// The validation-decision seam: reads the bundle's metadata and runs
    /// the shared `PluginValidation.validate` against the CLI's own single
    /// target generation. Kept separate from `run()` so tests can assert on
    /// the thrown error directly, without going through process spawning.
    ///
    /// The CLI validates against its own single target generation — there is
    /// no "min supported" concept for it distinct from `AinkradAppKit.apiVersion`.
    static func check(bundleURL: URL, inspector: BundleInspector) throws {
        let (metadata, infoDictionary) = try inspector.metadata(at: bundleURL)
        switch PluginValidation.validate(
            metadata: metadata,
            infoDictionary: infoDictionary,
            minSupported: AinkradAppKit.apiVersion,
            current: AinkradAppKit.apiVersion
        ) {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    /// Renders a thrown validation-path error to the exact message a
    /// developer should see: the raw failure reason, with no CLI-added
    /// wrapping that could obscure it.
    static func message(for error: Error) -> String {
        switch error {
        case let error as PluginValidationError:
            return error.reason
        case let error as BundleInspectorError:
            return error.description
        default:
            return "\(error)"
        }
    }
}
