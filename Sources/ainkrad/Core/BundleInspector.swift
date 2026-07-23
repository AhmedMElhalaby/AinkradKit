import AinkradAppKit
import Foundation

/// A failure reading or parsing a `.bundle`'s `Contents/Info.plist`.
/// `description` is precise enough to print directly to the developer.
struct BundleInspectorError: Error, CustomStringConvertible {
    let description: String
}

/// Reads a plugin bundle's `Contents/Info.plist` and parses it through the
/// SAME shared `PluginBundleMetadata.parse` the real host runs, so a bundle
/// that inspects clean here cannot fail differently at install time.
struct BundleInspector {
    /// Reads `<bundleURL>/Contents/Info.plist` and parses it via
    /// `PluginBundleMetadata.parse`. Returns the parsed metadata together
    /// with the raw dictionary so callers (e.g. `PluginValidation.validate`)
    /// can re-inspect fields the strict parse doesn't itself carry forward
    /// (like `CFBundleExecutable`).
    func metadata(at bundleURL: URL) throws -> (PluginBundleMetadata, [String: Any]) {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        guard let data = FileManager.default.contents(atPath: infoPlistURL.path) else {
            throw BundleInspectorError(description: "No Info.plist found at \(infoPlistURL.path).")
        }

        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw BundleInspectorError(description: "Could not parse \(infoPlistURL.path) as a property list: \(error)")
        }

        guard let dictionary = plistObject as? [String: Any] else {
            throw BundleInspectorError(description: "\(infoPlistURL.path) is not a dictionary.")
        }

        switch PluginBundleMetadata.parse(infoDictionary: dictionary) {
        case .success(let metadata):
            return (metadata, dictionary)
        case .failure(.missingKey(let key)):
            throw BundleInspectorError(description: "Info.plist is missing required key '\(key)'.")
        case .failure(.invalidAPIVersion):
            throw BundleInspectorError(
                description: "Info.plist's '\(PluginInfoKey.apiVersion)' is missing or not an integer."
            )
        @unknown default:
            throw BundleInspectorError(description: "Could not parse \(infoPlistURL.path).")
        }
    }
}
