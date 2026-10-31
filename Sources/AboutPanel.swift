import AppKit

/// The standard macOS About window, so Tarn has a proper "About Tarn" like any other Mac app.
@MainActor
enum AboutPanel {
    static func show() {
        let body = NSFont.systemFont(ofSize: 11)
        let serif = NSFont(descriptor: NSFont.systemFont(ofSize: 12).fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.italic) ?? NSFont.systemFont(ofSize: 12).fontDescriptor, size: 12) ?? body
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 6

        let credits = NSMutableAttributedString()
        func add(_ text: String, font: NSFont = body, link: String? = nil) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: center]
            if let link, let url = URL(string: link) { attrs[.link] = url }
            credits.append(NSAttributedString(string: text, attributes: attrs))
        }
        add("A tarn is a small, still mountain lake, quiet enough to hold the sky.\n", font: serif)
        add("Free and open source. No account, no tracking.\n")
        add("Source and releases\n", link: "https://github.com/jakeantelis/Tarn")
        add("antelislabs.com\n", link: "https://antelislabs.com")
        add("Also from us: Matcha", link: "https://github.com/jakeantelis/Matcha")

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tarn",
            .credits: credits,
        ])
    }
}
