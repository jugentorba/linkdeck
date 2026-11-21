import AppKit
import Foundation
import os

/// Turns a saved link into a real `.app` in `~/Applications/LinkDeck`.
///
/// The bundle is duplicated from the running LinkDeck bundle so it always
/// carries the current web-view + blocker code, then customised in place.
@MainActor
final class PinnedAppBuilder {
    private let favicon: FaviconService
    private let logger = Logger(subsystem: "dev.linkdeck.mac", category: "pin")

    init(favicon: FaviconService? = nil) {
        self.favicon = favicon ?? FaviconService.shared
    }

    static var defaultDestinationRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/LinkDeck", isDirectory: true)
    }

    func pin(name: String, url: String, destinationRoot: URL? = nil) async throws -> URL {
        guard let normalized = LinkInput.normalizedURL(from: url) else {
            throw PinError.invalidURL
        }

        let source = Bundle.main.bundleURL.standardizedFileURL
        guard source.pathExtension == "app",
              FileManager.default.fileExists(atPath: source.path) else {
            throw PinError.bundleUnavailable
        }

        let root = destinationRoot ?? Self.defaultDestinationRoot
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let baseName = LinkInput.sanitizedName(name)
        let destination = uniqueDestination(root: root, baseName: baseName)

        do {
            try manager.copyItem(at: source, to: destination)
        } catch {
            throw PinError.copyFailed(error.localizedDescription)
        }

        do {
            try writeInfoPlist(in: destination, displayName: baseName)
            try writePinnedLink(in: destination, name: baseName, url: normalized.absoluteString)
            try await installIcon(in: destination, name: baseName, host: normalized.host ?? baseName)
            try run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", destination.path])
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }

        logger.info("Pinned \(baseName, privacy: .public) to \(destination.path, privacy: .public)")
        return destination
    }

    // MARK: - Bundle customisation

    private func uniqueDestination(root: URL, baseName: String) -> URL {
        var candidate = root.appendingPathComponent("\(baseName).app", isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(baseName) \(counter).app", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    private func writeInfoPlist(in app: URL, displayName: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PinError.invalidBundle
        }

        let slug = displayName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let bundleID = "dev.linkdeck.pinned.\(slug.isEmpty ? "link" : String(slug.prefix(24))).\(suffix)"

        plist["CFBundleIdentifier"] = bundleID
        plist["CFBundleName"] = displayName
        plist["CFBundleDisplayName"] = displayName
        plist["CFBundleIconFile"] = "AppIcon"

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: plistURL, options: .atomic)
    }

    private func writePinnedLink(in app: URL, name: String, url: String) throws {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let marker = resources.appendingPathComponent(PinnedLink.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(PinnedLink(name: name, url: url))
        try data.write(to: marker, options: .atomic)
    }

    private func installIcon(in app: URL, name: String, host: String) async throws {
        let faviconData = await favicon.faviconData(for: host)
        let letter = name.first(where: { $0.isLetter || $0.isNumber }).map(String.init) ?? "L"
        guard let png = PinnedIconRenderer.pngData(favicon: faviconData, host: host, letter: letter) else {
            logger.error("Could not render an icon; keeping the default LinkDeck icon")
            return
        }

        do {
            let icns = try makeICNS(from: png)
            let destination = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: icns, to: destination)
        } catch {
            logger.error("Icon generation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeICNS(from png: Data) throws -> URL {
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("LinkDeckIcon-\(UUID().uuidString)", isDirectory: true)
        let iconset = work.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        let master = work.appendingPathComponent("master.png")
        let output = work.appendingPathComponent("AppIcon.icns")
        try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
        try png.write(to: master, options: .atomic)

        struct Entry {
            let pixels: Int
            let name: String
        }
        let entries = [
            Entry(pixels: 16, name: "icon_16x16.png"),
            Entry(pixels: 32, name: "icon_16x16@2x.png"),
            Entry(pixels: 32, name: "icon_32x32.png"),
            Entry(pixels: 64, name: "icon_32x32@2x.png"),
            Entry(pixels: 128, name: "icon_128x128.png"),
            Entry(pixels: 256, name: "icon_128x128@2x.png"),
            Entry(pixels: 256, name: "icon_256x256.png"),
            Entry(pixels: 512, name: "icon_256x256@2x.png"),
            Entry(pixels: 512, name: "icon_512x512.png"),
            Entry(pixels: 1024, name: "icon_512x512@2x.png")
        ]

        for entry in entries {
            let target = iconset.appendingPathComponent(entry.name)
            try run("/usr/bin/sips", ["-z", "\(entry.pixels)", "\(entry.pixels)", master.path, "--out", target.path])
        }

        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path])
        guard manager.fileExists(atPath: output.path) else {
            throw PinError.iconFailed
        }
        return output
    }

    // MARK: - Processes

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PinError.toolFailed(executable, message)
        }
    }

    enum PinError: LocalizedError {
        case invalidURL
        case bundleUnavailable
        case invalidBundle
        case copyFailed(String)
        case iconFailed
        case toolFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "That web address is not valid."
            case .bundleUnavailable:
                return "LinkDeck is not running from an app bundle, so it cannot be copied."
            case .invalidBundle:
                return "The generated app has an unreadable Info.plist."
            case .copyFailed(let message):
                return "Could not copy the LinkDeck app: \(message)"
            case .iconFailed:
                return "Could not build the app icon."
            case .toolFailed(let tool, let message):
                let name = URL(fileURLWithPath: tool).lastPathComponent
                return message.isEmpty ? "\(name) failed." : "\(name) failed: \(message)"
            }
        }
    }
}
