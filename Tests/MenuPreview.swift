// SPDX-License-Identifier: GPL-3.0-only
// Render only Macam-owned AppKit components; never capture the user's screen.
import AppKit

@main struct MenuPreview {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        func save(_ view: NSView, name: String) throws {
            view.layoutSubtreeIfNeeded()
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        for (name, running, summary, detail, tone) in [
            ("menu-stopped.png", false, "Stopped", "Stopped", CaptureStatusTone.idle),
            ("menu-running.png", true, "Mirroring", "Mirroring to Macam Audio", .active),
            ("menu-error.png", true, "Needs attention", "Input unavailable. Click the status to view the full error and recovery details.", .error)
        ] {
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 248))
            root.appearance = NSAppearance(named: .aqua)
            root.wantsLayer = true; root.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
            let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = root
            func label(_ title: String, y: CGFloat, secondary: Bool = false) {
                let field = NSTextField(labelWithString: title)
                field.frame = NSRect(x: 16, y: y, width: 288, height: 22)
                field.font = .systemFont(ofSize: 13)
                field.textColor = secondary ? .secondaryLabelColor : .labelColor
                root.addSubview(field)
            }
            label("Macam — Mirror your Mac’s audio.", y: 218, secondary: true)
            let controls = CaptureControlView()
            controls.frame.origin.y = 172
            controls.update(requested: running, summary: summary, detail: detail, tone: tone)
            root.addSubview(controls)
            let meter = MeterView(frame: .zero)
            meter.frame.origin.y = 126
            meter.set(summary == "Mirroring" ? 0.16 : 0); root.addSubview(meter)
            for y: CGFloat in [120, 64] {
                let separator = NSBox(frame: NSRect(x: 16, y: y, width: 288, height: 1))
                separator.boxType = .separator; root.addSubview(separator)
            }
            label("Source: Whole system", y: 94)
            label("Playback exclusions: 2 selected", y: 70)
            label("About Macam…", y: 36)
            label("Quit Macam", y: 10)
            try save(root, name: name)
            withExtendedLifetime(window) {}
        }
        let (alert, tools) = makeAboutAlert(version: "0.3.0", availableBrowsers: ["com.google.Chrome", "com.apple.Safari"])
        alert.accessoryView = nil
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 408, height: 390))
        panel.appearance = NSAppearance(named: .aqua)
        panel.wantsLayer = true; panel.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        let window = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = panel
        let title = NSTextField(labelWithString: alert.messageText)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 24, y: 346, width: 360, height: 24); panel.addSubview(title)
        let description = NSTextField(wrappingLabelWithString: alert.informativeText)
        description.font = .systemFont(ofSize: 12)
        description.frame = NSRect(x: 24, y: 164, width: 360, height: 174); panel.addSubview(description)
        tools.frame.origin = NSPoint(x: 24, y: 20); panel.addSubview(tools)
        try save(panel, name: "about.png")
        withExtendedLifetime(window) {}
        print("Rendered Macam-owned UI components to \(output.path)")
    }
}
