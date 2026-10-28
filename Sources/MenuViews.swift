// SPDX-License-Identifier: GPL-3.0-only
import AppKit

enum CaptureStatusTone {
    case idle, active, attention, error

    var color: NSColor {
        switch self {
        case .idle: return .secondaryLabelColor
        case .active: return .systemGreen
        case .attention: return .systemOrange
        case .error: return .systemRed
        }
    }
}

/// A real button and an adjacent, accessible status/details action.
final class CaptureControlView: NSView {
    static let width: CGFloat = 320
    let toggleButton = NSButton(title: "Start", target: nil, action: nil)
    let statusButton = NSButton(title: "Stopped", target: nil, action: nil)
    private let indicator = NSImageView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 44))
        toggleButton.bezelStyle = .rounded
        toggleButton.font = .systemFont(ofSize: 13, weight: .medium)
        toggleButton.setAccessibilityLabel("Start or stop audio mirroring")
        statusButton.isBordered = false
        statusButton.alignment = .left
        statusButton.font = .systemFont(ofSize: 12)
        statusButton.contentTintColor = .secondaryLabelColor
        statusButton.lineBreakMode = .byTruncatingTail
        statusButton.setAccessibilityLabel("Capture status; show details")
        indicator.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        indicator.imageScaling = .scaleProportionallyDown
        indicator.setAccessibilityElement(false)
        for view in [toggleButton, indicator, statusButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 88),
            indicator.leadingAnchor.constraint(equalTo: toggleButton.trailingAnchor, constant: 14),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 7),
            indicator.heightAnchor.constraint(equalToConstant: 7),
            statusButton.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 6),
            statusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(requested: false, summary: "Stopped", detail: "Stopped", tone: .idle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(requested: Bool, summary: String, detail: String, tone: CaptureStatusTone) {
        toggleButton.title = requested ? "Stop" : "Start"
        statusButton.title = summary
        statusButton.toolTip = detail + "\nClick for details."
        statusButton.setAccessibilityValue(detail)
        indicator.contentTintColor = tone.color
        toolTip = detail
    }
}

final class AboutToolsView: NSView {
    let browser = NSPopUpButton()
    let receiverButton = NSButton(title: "Open receiver", target: nil, action: nil)
    let toneButton = NSButton(title: "Open test tone", target: nil, action: nil)
    let permissionsButton = NSButton(title: "Audio recording permissions…", target: nil, action: nil)

    init(availableBrowsers: Set<String>) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 126))
        browser.menu?.autoenablesItems = false
        for (identifier, name) in [("default", "Default Browser"), ("com.google.Chrome", "Google Chrome"), ("com.apple.Safari", "Safari")] {
            browser.addItem(withTitle: name)
            browser.lastItem?.representedObject = identifier
            browser.lastItem?.isEnabled = identifier == "default" || availableBrowsers.contains(identifier)
        }
        browser.setAccessibilityLabel("Browser for offline diagnostic pages")
        let heading = NSTextField(labelWithString: "Diagnostics")
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        let browserRow = NSStackView(views: [NSTextField(labelWithString: "Open in"), browser])
        browserRow.spacing = 8
        let buttons = NSStackView(views: [receiverButton, toneButton])
        buttons.spacing = 8
        for button in [receiverButton, toneButton, permissionsButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        let note = NSTextField(labelWithString: "Offline pages. The test tone starts only when you click Play.")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, browserRow, buttons, note, permissionsButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var selectedBrowser: String { browser.selectedItem?.representedObject as? String ?? "default" }
}

func makeAboutAlert(version: String, availableBrowsers: Set<String>) -> (alert: NSAlert, tools: AboutToolsView) {
    let alert = NSAlert()
    alert.messageText = "Macam — Mac Audio Mirror"
    alert.informativeText = "Mirror your Mac’s audio.\nVersion \(version) · Local-only · GPL-3.0\n\nProject code is 100% LLM-generated under human direction, including attributed adaptations. No warranty.\n\nHelper discovery adapts FineTune, © 2026 Ronit Singh. Upstream copyright and license notices are preserved."
    let tools = AboutToolsView(availableBrowsers: availableBrowsers)
    alert.accessoryView = tools
    alert.addButton(withTitle: "Done")
    alert.addButton(withTitle: "License")
    return (alert, tools)
}

final class MeterView: NSView {
    let level = NSLevelIndicator(frame: NSRect(x: 16, y: 8, width: CaptureControlView.width - 32, height: 12))
    let label = NSTextField(labelWithString: "No signal")
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: CaptureControlView.width, height: 48))
        label.frame = NSRect(x: 16, y: 25, width: CaptureControlView.width - 32, height: 18)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        level.levelIndicatorStyle = .continuousCapacity
        level.minValue = -60; level.maxValue = 0; level.warningValue = -6; level.criticalValue = -1
        level.isEditable = false
        addSubview(level); addSubview(label)
        set(0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func set(_ peak: Float) {
        let db = peak > 0 ? max(-60, 20 * log10(Double(peak))) : -60
        level.doubleValue = db
        label.stringValue = peak > 0.000001 ? String(format: "Input peak: %.1f dBFS", db) : "Input: no signal"
        setAccessibilityLabel("Macam Audio input meter")
        setAccessibilityValue(label.stringValue)
    }
}

