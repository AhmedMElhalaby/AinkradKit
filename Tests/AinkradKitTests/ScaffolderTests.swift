import Foundation
import Testing
import AinkradAppKit
@testable import ainkrad

/// Forbidden placeholder tokens from `AinkradPluginTemplate` — none of these
/// may remain anywhere in a scaffolded output tree.
private let forbiddenTokens = [
    "myplugin",
    "MyApp",
    "TemplatePlugin",
    "MyPluginEntryPoint",
    "My Plugin",
    "puzzlepiece.extension",
]

/// Recursively collects every file under `root`.
private func allFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }

    var files: [URL] = []
    for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true {
            files.append(url)
        }
    }
    return files
}

/// Asserts none of `forbiddenTokens` appear in any text file under `root`.
private func assertNoPlaceholderTokensRemain(under root: URL) {
    for file in allFiles(under: root) {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for token in forbiddenTokens {
            #expect(
                !contents.contains(token),
                "found leftover placeholder token \"\(token)\" in \(file.lastPathComponent)"
            )
        }
    }
}

private func readInfoPlist(at root: URL) -> [String: Any] {
    let plistURL = root.appendingPathComponent("Sources/Plugin/Info.plist")
    let data = try! Data(contentsOf: plistURL)
    let plist = try! PropertyListSerialization.propertyList(from: data, format: nil)
    return plist as! [String: Any]
}

private func makeTempDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ainkrad-scaffolder-tests-\(UUID().uuidString)")
    return dir
}

@Test func scaffoldsAppWithSubstitutedIdentityAndStampedAPIVersion() throws {
    let destination = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    try TemplateScaffolder().scaffold(
        name: "MyWidget",
        id: "myapp",
        displayName: "My Widget",
        icon: "star.fill",
        into: destination
    )

    let plist = readInfoPlist(at: destination)
    #expect(plist["AinkradAppID"] as? String == "myapp")
    #expect(plist["AinkradDisplayName"] as? String == "My Widget")
    #expect(plist["AinkradIconSymbol"] as? String == "star.fill")
    #expect(plist["AinkradAPIVersion"] as? Int == AinkradAppKit.apiVersion)
    #expect(AinkradAppKit.apiVersion == 7)
    #expect(plist["NSPrincipalClass"] as? String == "MyWidgetEntryPoint")
    #expect(plist["CFBundleName"] as? String == "MyWidget")
    #expect(plist["CFBundleExecutable"] as? String == "MyWidget")

    assertNoPlaceholderTokensRemain(under: destination)
}

@Test func scaffoldedSwiftSourcesUseSubstitutedNames() throws {
    let destination = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    try TemplateScaffolder().scaffold(
        name: "MyWidget",
        id: "myapp",
        displayName: "My Widget",
        icon: "star.fill",
        into: destination
    )

    let appSwift = try String(
        contentsOf: destination.appendingPathComponent("Sources/Plugin/PluginApp.swift"),
        encoding: .utf8
    )
    #expect(appSwift.contains("struct MyWidget: AinkradApp"))
    #expect(appSwift.contains("static let id = \"myapp\""))
    #expect(appSwift.contains("static let displayName = \"My Widget\""))
    #expect(appSwift.contains("static let icon = \"star.fill\""))

    let entryPointSwift = try String(
        contentsOf: destination.appendingPathComponent("Sources/Plugin/PluginEntryPoint.swift"),
        encoding: .utf8
    )
    #expect(entryPointSwift.contains("@objc(MyWidgetEntryPoint)"))
    #expect(entryPointSwift.contains("final class MyWidgetEntryPoint"))
    #expect(entryPointSwift.contains("MyWidget.self"))

    let projectYML = try String(
        contentsOf: destination.appendingPathComponent("project.yml"),
        encoding: .utf8
    )
    #expect(projectYML.contains("MyWidget:"))
    #expect(projectYML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.example.plugin.myapp"))

    assertNoPlaceholderTokensRemain(under: destination)
}

/// Regression: `name` is arbitrary caller input and may itself contain a
/// substitution token as a substring (here, "MyApp" inside "MyAppTwo").
/// Sequential whole-string replacement passes would re-scan and mangle the
/// text a prior pass just inserted (producing e.g. "MyAppTwoTwo"); the
/// scaffolder must substitute in a single left-to-right pass so this can't
/// happen.
@Test func nameContainingAnotherTokenAsSubstringIsNotDoubleSubstituted() throws {
    let destination = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    try TemplateScaffolder().scaffold(
        name: "MyAppTwo",
        id: "myapptwo",
        displayName: "My App Two",
        icon: "star.fill",
        into: destination
    )

    let appSwift = try String(
        contentsOf: destination.appendingPathComponent("Sources/Plugin/PluginApp.swift"),
        encoding: .utf8
    )
    #expect(appSwift.contains("struct MyAppTwo: AinkradApp"))
    #expect(!appSwift.contains("MyAppTwoTwo"))

    let plist = readInfoPlist(at: destination)
    #expect(plist["CFBundleName"] as? String == "MyAppTwo")
    #expect(plist["NSPrincipalClass"] as? String == "MyAppTwoEntryPoint")
}

@Test func rejectsInvalidAppID() {
    let destination = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    #expect(throws: (any Error).self) {
        try TemplateScaffolder().scaffold(
            name: "MyWidget",
            id: "my app", // space is not in PluginValidation's allowed charset
            displayName: "My Widget",
            icon: "star.fill",
            into: destination
        )
    }
}

/// Edge case: a hyphenated id is a legal `AinkradAppID` even though it is
/// not a legal Swift identifier — `name` and `id` are decoupled.
@Test func scaffoldsWithHyphenatedIDAndUnicodeDisplayName() throws {
    let destination = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    try TemplateScaffolder().scaffold(
        name: "CoffeeApp",
        id: "my-app",
        displayName: "咖啡 Café ☕️",
        icon: "cup.and.saucer.fill",
        into: destination
    )

    let plist = readInfoPlist(at: destination)
    #expect(plist["AinkradAppID"] as? String == "my-app")
    #expect(plist["AinkradDisplayName"] as? String == "咖啡 Café ☕️")
    #expect(plist["AinkradAPIVersion"] as? Int == AinkradAppKit.apiVersion)

    let projectYML = try String(
        contentsOf: destination.appendingPathComponent("project.yml"),
        encoding: .utf8
    )
    #expect(projectYML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.example.plugin.my-app"))

    assertNoPlaceholderTokensRemain(under: destination)
}
