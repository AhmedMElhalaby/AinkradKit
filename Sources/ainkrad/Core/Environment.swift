import AinkradAppKit
import Foundation

/// Probes the local toolchain the `ainkrad` CLI depends on: an
/// Xcode-beta developer directory, and external tools such as `xcodegen`
/// and `gh` on `PATH`.
///
/// The real machine probes (`Environment()`) shell out to `xcode-select`
/// and `which`. For deterministic tests, use the injecting initializer to
/// stub tool lookup and Xcode-beta detection without touching the real
/// machine.
struct Environment {
    private let findTool: (String) -> URL?

    /// Whether the selected Xcode developer directory is Xcode-beta.
    let xcodeBetaPresent: Bool

    /// The API generation `ainkrad` targets — mirrors `AinkradAppKit.apiVersion`.
    let targetGeneration: Int

    /// Injectable initializer for tests: stub `find` and `xcodeBetaPresent`
    /// to report an environment deterministically, without touching the
    /// real filesystem or `PATH`.
    init(
        find: @escaping (String) -> URL?,
        xcodeBetaPresent: Bool,
        targetGeneration: Int = AinkradAppKit.apiVersion
    ) {
        self.findTool = find
        self.xcodeBetaPresent = xcodeBetaPresent
        self.targetGeneration = targetGeneration
    }

    /// The real environment: probes `DEVELOPER_DIR` / `xcode-select -p`
    /// for the selected Xcode, and `which` for external tools on `PATH`.
    init() {
        self.init(
            find: Environment.locate,
            xcodeBetaPresent: Environment.detectXcodeBetaPresent()
        )
    }

    /// Locates `tool` on `PATH`, or `nil` if it isn't found.
    func find(_ tool: String) -> URL? {
        findTool(tool)
    }

    private static func locate(_ tool: String) -> URL? {
        guard let path = run("/usr/bin/which", arguments: [tool]) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func detectXcodeBetaPresent() -> Bool {
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            return developerDir.contains("Xcode-beta")
        }
        guard let selectedPath = run("/usr/bin/xcode-select", arguments: ["-p"]) else {
            return false
        }
        return selectedPath.contains("Xcode-beta")
    }

    /// Runs `executable` with `arguments`, returning trimmed stdout on
    /// success (exit code 0) or `nil` on failure/launch error.
    private static func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
                return nil
            }
            return output
        } catch {
            return nil
        }
    }
}
