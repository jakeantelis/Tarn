import Foundation
import AppKit

/// Puts tarnctl on the user's PATH with one click. It links into ~/.local/bin, so no password is needed.
enum CommandLineTool {
    private static var source: URL? { Bundle.main.resourceURL?.appendingPathComponent("tarnctl") }
    private static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin") }
    private static var link: URL { folder.appendingPathComponent("tarnctl") }

    static var isInstalled: Bool {
        guard let source, let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return dest == source.path
    }

    /// Whether a shell start up file already adds ~/.local/bin to the PATH.
    static var onPath: Bool {
        ["~/.zshrc", "~/.zprofile", "~/.zshenv", "~/.bash_profile", "~/.profile"].contains { path in
            let text = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
            return text?.contains(".local/bin") ?? false
        }
    }

    static let pathLine = "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc"

    @discardableResult
    static func install() -> Bool {
        guard let source, FileManager.default.isExecutableFile(atPath: source.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            return true
        } catch { return false }
    }

    static func remove() {
        if isInstalled { try? FileManager.default.removeItem(at: link) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
