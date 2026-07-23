import AinkradAppKit
import Foundation
import Testing
@testable import ainkrad

/// The parity guarantee under test: sub-project D promises "passes
/// `ainkrad validate --store` locally ⟺ passes the host installer's review."
/// Both call the SAME `AinkradAppKit.StorePolicy.check`, but construct its
/// `StoreManifestInput` from different sources — the CLI from the bundle's
/// own `Info.plist` (Path A, `Validate.storeIssues`), the host from the
/// downstream `CatalogEntry` derived by `ainkrad publish` (Path B, here
/// reconstructed from the REAL `ainkrad-plugin.json` that
/// `ReleasePublisher.package` produces from that same bundle). If `publish`
/// ever drops a field the installer needs, Path B's reconstruction changes
/// and this test fails — proving parity end-to-end without importing the
/// host (a different repo).
///
/// The host installer's legacy `author == nil` grandfather path is
/// intentionally OUT of this table: `ainkrad publish` always emits an
/// `author` field (nil or a string) on its own decodable, but more
/// importantly a CLI-produced submission always goes through `publish`, so
/// the grandfather clause (for catalog entries published before `author`
/// existed) never applies here.

/// The exact JSON shape the host's `GitHubReleasesCatalogSource` decodes the
/// published `ainkrad-plugin.json` asset into (mirrors `PublishTests`'
/// private `PluginManifest`, copied from
/// `Ainkrad/Sources/Ainkrad/Core/AppStore/CatalogModel.swift`).
private struct PluginManifest: Codable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let apiVersion: Int
    let sha256: String
    let author: String?
}

/// A golden `.bundle` fixture: a real directory on disk with a
/// `Contents/Info.plist`, written with `PropertyListSerialization` so no
/// actual Xcode build is needed to exercise validation or packaging.
private func makeGoldenBundle(infoDictionary: [String: Any]) throws -> URL {
    let bundleURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ainkrad-store-parity-tests-\(UUID().uuidString).bundle")
    let contentsURL = bundleURL.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let data = try PropertyListSerialization.data(
        fromPropertyList: infoDictionary, format: .xml, options: 0
    )
    try data.write(to: contentsURL.appendingPathComponent("Info.plist"))

    return bundleURL
}

/// A complete, valid Info.plist dictionary built against the CLI's own
/// target generation (`AinkradAppKit.apiVersion`), with every key overridable
/// so individual golden rows can knock one out.
private func validInfoDictionary(overrides: [String: Any] = [:], removing: Set<String> = []) -> [String: Any] {
    var dict: [String: Any] = [
        PluginInfoKey.appID: "com.example.widget",
        PluginInfoKey.displayName: "Example Widget",
        PluginInfoKey.iconSymbol: "star.fill",
        PluginInfoKey.apiVersion: AinkradAppKit.apiVersion,
        PluginInfoKey.principalClass: "WidgetApp",
        "CFBundleExecutable": "ExampleWidget",
    ]
    for (key, value) in overrides { dict[key] = value }
    for key in removing { dict.removeValue(forKey: key) }
    return dict
}

/// One golden bundle and the store-issue codes both paths must agree on.
private struct GoldenRow {
    let name: String
    let overrides: [String: Any]
    let removing: Set<String>
    let expectedCodes: Set<String>
}

private func goldenRows() -> [GoldenRow] { [
    GoldenRow(
        name: "complete",
        overrides: [
            PluginInfoKey.author: "Jane Developer",
            PluginInfoKey.description: "A short description of what this app does.",
        ],
        removing: [],
        expectedCodes: []
    ),
    GoldenRow(
        name: "missing author",
        overrides: [
            PluginInfoKey.description: "A short description of what this app does.",
        ],
        removing: [],
        expectedCodes: ["missing-author"]
    ),
    GoldenRow(
        name: "missing description",
        overrides: [
            PluginInfoKey.author: "Jane Developer",
        ],
        removing: [],
        expectedCodes: ["missing-description"]
    ),
    GoldenRow(
        name: "unresolvable icon",
        overrides: [
            PluginInfoKey.author: "Jane Developer",
            PluginInfoKey.description: "A short description of what this app does.",
            PluginInfoKey.iconSymbol: "definitely-not-a-symbol-xyz",
        ],
        removing: [],
        expectedCodes: ["missing-icon"]
    ),
] }

private func assertParity(for row: GoldenRow) throws {
    let bundleURL = try makeGoldenBundle(
        infoDictionary: validInfoDictionary(overrides: row.overrides, removing: row.removing)
    )
    defer { try? FileManager.default.removeItem(at: bundleURL) }

    // Path A: the CLI's own `validate --store` seam, reading the bundle's
    // Info.plist directly.
    let codesA = Set(try Validate.storeIssues(bundleURL: bundleURL, inspector: BundleInspector())
        .map(\.code))

    // Path B: publish the SAME bundle to produce the real
    // `ainkrad-plugin.json`, decode it as the host would, and reconstruct
    // the installer's `StoreManifestInput` from that published manifest —
    // not from the bundle directly — so a field `publish` drops would show
    // up here as a divergence from Path A.
    let (zip, manifest) = try ReleasePublisher().package(bundle: bundleURL)
    defer { try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }

    let manifestData = try Data(contentsOf: manifest)
    let decoded = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

    let (metadata, infoDictionary) = try BundleInspector().metadata(at: bundleURL)
    let input = StoreManifestInput(
        metadata: metadata,
        infoDictionary: infoDictionary,
        author: decoded.author,
        description: decoded.description,
        iconSymbol: decoded.icon,
        declaredSHA256: decoded.sha256,
        computedSHA256: decoded.sha256
    )
    let codesB = Set(StorePolicy.check(
        manifest: input,
        minSupported: AinkradAppKit.apiVersion,
        current: AinkradAppKit.apiVersion
    ).map(\.code))

    #expect(codesA == row.expectedCodes, "Path A (CLI validate) diverged from the expected codes for '\(row.name)'.")
    #expect(codesB == row.expectedCodes, "Path B (publish → installer) diverged from the expected codes for '\(row.name)'.")
    #expect(codesA == codesB, "CLI validate and the host installer diverged on '\(row.name)': A=\(codesA) B=\(codesB).")
}

@Test func cliValidateAndInstallerAgreeOnACompleteBundle() throws {
    try assertParity(for: goldenRows()[0])
}

@Test func cliValidateAndInstallerAgreeOnABundleMissingAuthor() throws {
    try assertParity(for: goldenRows()[1])
}

@Test func cliValidateAndInstallerAgreeOnABundleMissingDescription() throws {
    try assertParity(for: goldenRows()[2])
}

@Test func cliValidateAndInstallerAgreeOnABundleWithAnUnresolvableIcon() throws {
    try assertParity(for: goldenRows()[3])
}
