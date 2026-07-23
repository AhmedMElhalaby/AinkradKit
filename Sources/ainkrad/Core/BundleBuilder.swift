import Foundation

/// A shell-out or discovery failure while building an Ainkrad App.
/// `description` includes the failing child process's stderr verbatim so
/// the real compiler/toolchain message reaches the developer.
struct BundleBuilderError: Error, CustomStringConvertible {
    let description: String
}

/// The ONE blessed build path for an Ainkrad App: wraps `xcodegen generate`
/// and `xcodebuild build` with the fixed environment every `ainkrad`
/// developer should use, so nobody has to guess which Xcode or which
/// xcodebuild flags to invoke by hand.
///
/// `xcodegen`/`xcodebuild` are resolved via `PATH` (through `Environment`,
/// not hardcoded paths); the toolchain itself is pinned by setting
/// `DEVELOPER_DIR` to Xcode-beta in the child process environment.
struct BundleBuilder {
    /// The one true toolchain every `ainkrad build` invocation targets.
    private static let developerDirectoryPath = "/Applications/Xcode-beta.app/Contents/Developer"

    private let environment: Environment

    /// Injectable for tests that only need to stub tool lookup; the
    /// integration test in `BundleBuilderTests` uses the real
    /// `Environment()` and the real toolchain.
    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    /// Generates the Xcode project for `projectDir` with XcodeGen, builds
    /// its scheme with xcodebuild against Xcode-beta, and returns the path
    /// to the produced `.bundle`.
    func build(projectDir: URL) throws -> URL {
        guard let xcodegen = environment.find("xcodegen") else {
            throw BundleBuilderError(description: "xcodegen not found on PATH.")
        }
        guard let xcodebuild = environment.find("xcodebuild") else {
            throw BundleBuilderError(description: "xcodebuild not found on PATH.")
        }

        try BundleBuilder.run(xcodegen, arguments: ["generate"], currentDirectory: projectDir)

        // Derive the scheme from the project XcodeGen just generated, rather
        // than assuming it matches any particular field of project.yml.
        let scheme = try BundleBuilder.scheme(in: projectDir, xcodebuild: xcodebuild)

        // Build into a derived data directory scoped to this run so the
        // produced .bundle is easy to locate deterministically, independent
        // of the caller's (or CI's) global DerivedData location.
        let derivedDataPath = projectDir.appendingPathComponent(".ainkrad-build", isDirectory: true)
        try BundleBuilder.run(
            xcodebuild,
            arguments: ["-scheme", scheme, "-derivedDataPath", derivedDataPath.path, "build"],
            currentDirectory: projectDir
        )

        return try BundleBuilder.locateBundle(under: derivedDataPath, scheme: scheme)
    }

    /// Asks xcodebuild for the generated project's schemes and returns the
    /// first one. This queries the project XcodeGen just produced (rather
    /// than re-parsing `project.yml`'s YAML by hand), so it stays correct
    /// even if the scaffold's scheme-naming convention changes.
    private static func scheme(in projectDir: URL, xcodebuild: URL) throws -> String {
        let output = try BundleBuilder.run(xcodebuild, arguments: ["-list", "-json"], currentDirectory: projectDir)

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let project = json["project"] as? [String: Any],
            let schemes = project["schemes"] as? [String],
            let scheme = schemes.first
        else {
            throw BundleBuilderError(
                description: "Could not determine a scheme from `xcodebuild -list -json` in " +
                    "\(projectDir.path). Output was:\n\(output)"
            )
        }
        return scheme
    }

    /// Recursively finds the built `.bundle`, preferring one whose name
    /// matches `scheme` (the scaffold's convention) but falling back to any
    /// `.bundle` under the build products directory.
    private static func locateBundle(under derivedDataPath: URL, scheme: String) throws -> URL {
        let productsDir = derivedDataPath.appendingPathComponent("Build/Products")
        guard let enumerator = FileManager.default.enumerator(
            at: productsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            throw BundleBuilderError(
                description: "xcodebuild reported success but no build products directory was found at " +
                    "\(productsDir.path)."
            )
        }

        var bundles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "bundle" {
            bundles.append(url)
        }

        if let match = bundles.first(where: { $0.deletingPathExtension().lastPathComponent == scheme }) {
            return match
        }
        guard let first = bundles.first else {
            throw BundleBuilderError(
                description: "xcodebuild reported success but no .bundle was found under \(productsDir.path)."
            )
        }
        return first
    }

    /// Runs `executable` with `arguments` in `currentDirectory`, with
    /// `DEVELOPER_DIR` pinned to Xcode-beta in the child environment.
    /// Returns trimmed stdout on success (exit code 0); on failure, throws
    /// with the child's stderr included verbatim so the real
    /// xcodegen/xcodebuild failure reaches the developer.
    ///
    /// stdout/stderr are captured via temp files rather than `Pipe`:
    /// xcodebuild output can be large, and reading two pipes sequentially
    /// (rather than concurrently) risks a classic deadlock if the child
    /// fills one pipe's buffer while we're still draining the other.
    @discardableResult
    private static func run(_ executable: URL, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        var childEnvironment = ProcessInfo.processInfo.environment
        childEnvironment["DEVELOPER_DIR"] = BundleBuilder.developerDirectoryPath
        process.environment = childEnvironment

        let fileManager = FileManager.default
        let stdoutURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stderrURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw BundleBuilderError(
                description: "Failed to launch \(executable.path) \(arguments.joined(separator: " ")): \(error)"
            )
        }
        process.waitUntilExit()
        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            throw BundleBuilderError(
                description: "\(executable.lastPathComponent) \(arguments.joined(separator: " ")) " +
                    "failed (exit \(process.terminationStatus)) in \(currentDirectory.path):\n\(stderr)"
            )
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
