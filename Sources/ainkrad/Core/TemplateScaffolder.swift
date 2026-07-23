import AinkradAppKit
import Foundation

/// A validation or filesystem failure while scaffolding a new Ainkrad App.
struct TemplateScaffolderError: Error, CustomStringConvertible {
    let description: String
}

/// Generates a ready-to-build Ainkrad App by copying the embedded
/// `AinkradPluginTemplate` subset and performing the identity find/replace a
/// developer would otherwise do by hand: app id, display name, icon, and the
/// Swift/target/class names derived from `name`.
///
/// `name` and `id` are decoupled: `name` must be a valid Swift type
/// identifier (it becomes the app's `struct`/entry-point class/target name),
/// while `id` may be hyphenated (it is only ever used where an id string is
/// valid, such as `AinkradAppID` and the bundle-id suffix) and is validated
/// with `AinkradAppKit.PluginValidation.isValidAppID`.
struct TemplateScaffolder {
    /// The resource name of the embedded template directory, as registered
    /// in `Package.swift` (`.copy("Resources/Template")`).
    private static let templateResourceName = "Template"

    func scaffold(
        name: String,
        id: String,
        displayName: String,
        icon: String,
        into destination: URL
    ) throws {
        guard PluginValidation.isValidAppID(id) else {
            throw TemplateScaffolderError(
                description: "Invalid app id \"\(id)\": must be non-empty, not \".\" or \"..\", " +
                    "and contain only letters, digits, '.', '_', or '-'."
            )
        }
        guard TemplateScaffolder.isValidSwiftIdentifier(name) else {
            throw TemplateScaffolderError(
                description: "Invalid app name \"\(name)\": must be a valid Swift type " +
                    "identifier (used as the app's struct, entry-point class, and target name)."
            )
        }

        guard let templateURL = Bundle.module.url(
            forResource: TemplateScaffolder.templateResourceName, withExtension: nil
        ) else {
            throw TemplateScaffolderError(
                description: "Embedded template resources not found in the ainkrad bundle."
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let replacements = TemplateScaffolder.substitutions(
            name: name, id: id, displayName: displayName, icon: icon
        )

        try TemplateScaffolder.copyAndSubstitute(
            from: templateURL, to: destination, replacements: replacements, fileManager: fileManager
        )
    }

    /// A valid Swift type identifier: starts with a letter or underscore,
    /// followed by letters, digits, or underscores. (Deliberately stricter
    /// than the full Swift identifier grammar — good enough for a
    /// generated `struct`/`final class` name.)
    private static func isValidSwiftIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        guard CharacterSet.letters.contains(first) || first == "_" else { return false }

        let allowedRest = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        return name.unicodeScalars.dropFirst().allSatisfy { allowedRest.contains($0) }
    }

    /// The full identity substitution table, longest/most-specific token
    /// first so a shorter token is never tried before a longer one that
    /// starts with the same text at a given scan position.
    ///
    /// Substitution happens in a single left-to-right scan (see
    /// `applySubstitutions`), not sequential whole-string
    /// `replacingOccurrences` passes: `name`/`id`/`displayName` are
    /// arbitrary caller input and may themselves contain another token as a
    /// substring (e.g. `name == "MyApp2"` contains the `MyApp` token).
    /// Sequential passes would re-scan and corrupt text a prior pass just
    /// inserted; a single scan that only ever advances past *source* text
    /// cannot.
    private static func substitutions(
        name: String, id: String, displayName: String, icon: String
    ) -> [(token: String, replacement: String)] {
        [
            (
                token: "<key>AinkradAPIVersion</key><integer>1</integer>",
                replacement: "<key>AinkradAPIVersion</key><integer>\(AinkradAppKit.apiVersion)</integer>"
            ),
            (token: "\"apiVersion\": 1,", replacement: "\"apiVersion\": \(AinkradAppKit.apiVersion),"),
            (token: "puzzlepiece.extension", replacement: icon),
            (token: "MyPluginEntryPoint", replacement: "\(name)EntryPoint"),
            (token: "TemplatePlugin", replacement: name),
            (token: "My Plugin", replacement: displayName),
            (token: "myplugin", replacement: id),
            (token: "MyApp", replacement: name),
        ]
    }

    /// Single-pass, boundary-safe substitution: scans `contents` once,
    /// left to right. At each position, tries each token in order; on a
    /// match it emits the replacement and advances past the *matched
    /// source* text (never past the replacement), so replacement text is
    /// never itself re-scanned for further matches.
    private static func applySubstitutions(
        to contents: String, replacements: [(token: String, replacement: String)]
    ) -> String {
        var result = ""
        result.reserveCapacity(contents.count)
        var remaining = Substring(contents)

        while !remaining.isEmpty {
            if let match = replacements.first(where: { remaining.hasPrefix($0.token) }) {
                result += match.replacement
                remaining = remaining.dropFirst(match.token.count)
            } else {
                result.append(remaining.removeFirst())
            }
        }

        return result
    }

    private static func copyAndSubstitute(
        from source: URL, to destination: URL,
        replacements: [(token: String, replacement: String)], fileManager: FileManager
    ) throws {
        let items = try fileManager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey]
        )
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                try copyAndSubstitute(
                    from: item, to: target, replacements: replacements, fileManager: fileManager
                )
            } else {
                try substituteFile(from: item, to: target, replacements: replacements, fileManager: fileManager)
            }
        }
    }

    private static func substituteFile(
        from source: URL, to target: URL,
        replacements: [(token: String, replacement: String)], fileManager: FileManager
    ) throws {
        guard let contents = try? String(contentsOf: source, encoding: .utf8) else {
            // Not UTF-8 text (shouldn't occur in this template, but copy
            // verbatim rather than corrupt it).
            try fileManager.copyItem(at: source, to: target)
            return
        }

        let substituted = applySubstitutions(to: contents, replacements: replacements)
        try substituted.write(to: target, atomically: true, encoding: .utf8)

        // Preserve the source file's permissions (e.g. `scripts/release.sh`
        // must stay executable).
        if let permissions = try fileManager.attributesOfItem(atPath: source.path)[.posixPermissions] {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }
}
