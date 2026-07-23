import ArgumentParser
import Foundation

/// `ainkrad publish` — packages a built `.bundle` into the catalog format
/// the real host's `GitHubReleasesCatalogSource` consumes
/// (`<appID>.bundle.zip` + `ainkrad-plugin.json`) and creates the GitHub
/// Release carrying them.
///
/// Refuses to package or release a bundle that fails the SAME base
/// validation `ainkrad validate` runs (`Validate.check`), so nothing that
/// would fail at install time ever reaches a release.
///
/// NOT registered as a root subcommand yet (Task 9's job).
struct Publish: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Package a built .bundle and create its GitHub Release."
    )

    @Argument(help: "Path to the built .bundle to publish.")
    var bundlePath: String

    @Argument(help: "The release tag (e.g. v1.0.0).")
    var tag: String

    @Flag(help: "Package the release assets but skip creating the GitHub Release (no network).")
    var dryRun = false

    func run() throws {
        let bundleURL = URL(fileURLWithPath: bundlePath)

        do {
            try Validate.check(bundleURL: bundleURL, inspector: BundleInspector())
        } catch {
            print("Refusing to publish: \(Validate.message(for: error))")
            throw ExitCode(1)
        }

        let publisher = ReleasePublisher()
        let (zip, manifest) = try publisher.package(bundle: bundleURL)

        if dryRun {
            print("Dry run: packaged \(zip.lastPathComponent) and \(manifest.lastPathComponent). Skipping gh release create.")
            return
        }

        try publisher.release(tag: tag, assets: [manifest, zip])
        print("Released \(tag): \(zip.lastPathComponent), \(manifest.lastPathComponent)")
    }
}
