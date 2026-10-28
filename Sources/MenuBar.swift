// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreAudio

final class HALObservation {
    private var address: AudioObjectPropertyAddress
    private let object: AudioObjectID
    private let block: AudioObjectPropertyListenerBlock
    init(_ selector: AudioObjectPropertySelector, action: @escaping () -> Void) {
        object = HAL.system
        address = HAL.address(selector)
        block = { _, _ in action() }
        AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
    }
    deinit { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) }
}

final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let startStopShortcut = NSMenuItem(title: "Start", action: #selector(toggle), keyEquivalent: "s")
    private let controls = CaptureControlView()
    private var statusDetail = "Stopped"
    private weak var aboutTools: AboutToolsView?
    private let sourceItem = NSMenuItem(title: "Source: Whole system", action: nil, keyEquivalent: "")
    private let exclusionItem = NSMenuItem(title: "Playback exclusions: Off", action: nil, keyEquivalent: "")
    private let meterView = MeterView(frame: .zero)
    private let engine = MirrorEngine()
    private var selection = CaptureSelection()
    private var catalog = ProcessCatalog(processes: [], applications: [])
    private var timer: Timer?
    private var observations: [HALObservation] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var signals: ShutdownSignals?
    private var wanted = false, sleeping = false
    private var lastRefresh = Date.distantPast, lastAdvance = Date(), lastFrames: UInt64 = 0
    private var startedAt = Date(), retryAt = Date.distantPast, retries = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let data = UserDefaults.standard.data(forKey: "captureSelection"),
           let saved = try? JSONDecoder().decode(CaptureSelection.self, from: data) { selection = saved }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Macam — Mirror your Mac’s audio.")
        statusItem.button?.toolTip = "Macam — Mirror your Mac’s audio."
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Macam — Mirror your Mac’s audio.", action: nil, keyEquivalent: "")
        title.toolTip = "Mac Audio Mirror"
        title.isEnabled = false; menu.addItem(title)
        controls.toggleButton.target = self; controls.toggleButton.action = #selector(toggle)
        controls.statusButton.target = self; controls.statusButton.action = #selector(showStatusDetails)
        let controlItem = NSMenuItem(); controlItem.view = controls; menu.addItem(controlItem)
        startStopShortcut.target = self; startStopShortcut.isHidden = true
        startStopShortcut.allowsKeyEquivalentWhenHidden = true; menu.addItem(startStopShortcut)
        let meterItem = NSMenuItem(); meterItem.view = meterView; menu.addItem(meterItem)
        menu.addItem(.separator())
        menu.addItem(sourceItem); menu.addItem(exclusionItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Macam…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Macam", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        do { let owner = try AudioOwnership(); try owner.recover() }
        catch { setStatus(error.localizedDescription, summary: "Needs attention", tone: .error) }
        refreshCatalog()
        rebuildChoices()
        observations = [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices,
                        kAudioHardwarePropertyDefaultOutputDevice].map { selector in
            HALObservation(selector) { [weak self] in self?.refreshCatalog() }
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = true; self.engine.stop(); self.meterView.set(0)
            if self.wanted { self.setStatus("Paused for sleep", summary: "Paused", tone: .attention) }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false; self.retryAt = Date(timeIntervalSinceNow: 1); self.retries = 0
            if self.wanted { self.setStatus("Resuming after wake…", summary: "Resuming…", tone: .attention) }
        })
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        signals = ShutdownSignals { NSApp.terminate(nil) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); observations = []
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        engine.stop()
        engine.cleanupErrors.forEach { fputs("Macam cleanup: \($0)\n", stderr) }
    }
    private func setStatus(_ text: String, summary: String, tone: CaptureStatusTone) {
        statusDetail = text
        controls.update(requested: wanted, summary: summary, detail: text, tone: tone)
        statusItem?.button?.toolTip = "Macam — \(text)"
    }
    private func save() {
        if let data = try? JSONEncoder().encode(selection) { UserDefaults.standard.set(data, forKey: "captureSelection") }
    }
    private func refreshCatalog() {
        do {
            catalog = try ProcessCatalog.load()
            if engine.device != 0 && wanted && !sleeping { try engine.update(selection: selection, catalog: catalog) }
        } catch {
            if wanted { fail(error) }
        }
        lastRefresh = Date()
    }
    private func fail(_ error: Error) {
        engine.stop(); meterView.set(0)
        retries += 1
        retryAt = Date(timeIntervalSinceNow: min(30, pow(2, Double(retries))))
        setStatus("\(error.localizedDescription)\(retries < 4 ? " — retrying" : " — press Stop/Start to retry")",
                  summary: retries < 4 ? "Retrying…" : "Needs attention", tone: .error)
    }
    private func start() {
        do {
            refreshCatalog()
            try engine.start(selection: selection, catalog: catalog)
            startedAt = Date(); lastAdvance = Date(); lastFrames = 0
            setStatus("Select Macam Audio as the input in your receiving application.", summary: "Listening", tone: .active)
            statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Macam running")
        } catch { fail(error) }
    }
    private func tick() {
        if Date().timeIntervalSince(lastRefresh) >= 1 { refreshCatalog() }
        guard wanted && !sleeping else { return }
        if engine.device == 0 {
            if retries < 4 && Date() >= retryAt { start() }
            return
        }
        guard let meter = engine.meter else { return }
        let reading = meter.reading
        meterView.set(reading.peak)
        if reading.frames != lastFrames { lastAdvance = Date(); lastFrames = reading.frames }
        if Date().timeIntervalSince(lastAdvance) > 5 {
            fail(MacamError(message: "Input stopped delivering audio after a device change")); return
        }
        if Date().timeIntervalSince(startedAt) > 10 { retries = 0 }
        if Date().timeIntervalSince(startedAt) > 5 && reading.nonzero == 0 {
            setStatus("No signal — play source audio; check recording permission", summary: "No signal", tone: .attention)
        } else if reading.nonzero > 0 {
            setStatus("Mirroring to Macam Audio", summary: "Mirroring", tone: .active)
        }
        // Tap streams can change format/rate after a device change. The meter is
        // format agnostic within Float32 stereo. Rebuild if that contract changes.
        if Date().timeIntervalSince(lastRefresh) < 0.2,
           let formats = try? HAL.formats(engine.device),
           formats.reduce(0, { $0 + $1.mChannelsPerFrame }) != 2 || formats.contains(where: {
               $0.mFormatID != kAudioFormatLinearPCM || $0.mBitsPerChannel != 32 || $0.mFormatFlags & kAudioFormatFlagIsFloat == 0
           }) {
            fail(MacamError(message: "Input format changed; recreating Macam Audio"))
        }
    }
    @objc private func toggle() {
        menu.cancelTracking()
        wanted.toggle(); retries = 0
        startStopShortcut.title = wanted ? "Stop" : "Start"
        if wanted { start() }
        else {
            engine.stop(); meterView.set(0)
            setStatus(engine.cleanupErrors.isEmpty ? "Stopped" : engine.cleanupErrors.joined(separator: "; "),
                      summary: engine.cleanupErrors.isEmpty ? "Stopped" : "Cleanup needed",
                      tone: engine.cleanupErrors.isEmpty ? .idle : .error)
            statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Macam stopped")
        }
    }
    func menuWillOpen(_ menu: NSMenu) { refreshCatalog(); rebuildChoices() }
    private func label(_ key: String) -> String {
        if key == CaptureSelection.allBrowsers { return "All browsers" }
        if key == "bundle:com.google.Chrome" { return "Google Chrome" }
        if key == "bundle:com.apple.Safari" { return "Safari" }
        return catalog.applications.first { $0.key == key }?.name ?? key.replacingOccurrences(of: "bundle:", with: "")
    }
    private func rebuildChoices() {
        sourceItem.title = selection.wholeSystem ? "Source: Whole system" : "Source: \(selection.applications.count) selected app(s)"
        let excluded = selection.excludedApplications
        let exclusionSummary = excluded.isEmpty ? "Off" : excluded.count == 1 ? label(excluded.first!) : "\(excluded.count) selected"
        exclusionItem.title = "Playback exclusions: \(exclusionSummary)"
        let sources = NSMenu(), exclusions = NSMenu()
        sources.autoenablesItems = false; exclusions.autoenablesItems = false
        let whole = NSMenuItem(title: "Whole system", action: #selector(selectSource(_:)), keyEquivalent: "")
        whole.target = self; whole.representedObject = "whole-system"; whole.state = selection.wholeSystem ? .on : .off
        sources.addItem(whole); sources.addItem(.separator())
        let instruction = NSMenuItem(title: "Toggle apps to capture their audio", action: nil, keyEquivalent: "")
        instruction.isEnabled = false; sources.addItem(instruction)
        var choices = catalog.applications.filter {
            $0.isUserApplication || $0.processes.contains(where: \.output) || selection.applications.contains($0.key)
        }
        for key in selection.applications where !choices.contains(where: { $0.key == key }) {
            choices.append(AudioApplication(key: key, name: label(key) + " (not running)"))
        }
        for app in choices {
            let item = NSMenuItem(title: app.name + (app.processes.contains(where: \.output) ? " •" : ""), action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = app.key
            item.state = !selection.wholeSystem && selection.applications.contains(app.key) ? .on : .off
            item.isEnabled = !selection.isExcluded(app.key)
            if !item.isEnabled { item.title += " (playback excluded)" }
            sources.addItem(item)
        }
        let off = NSMenuItem(title: "Clear all (Off)", action: #selector(selectExclusion(_:)), keyEquivalent: "")
        off.target = self; off.representedObject = "no-exclusion"
        off.state = excluded.isEmpty ? .on : .off
        exclusions.addItem(off); exclusions.addItem(.separator())
        var exclusionChoices = [AudioApplication(key: CaptureSelection.allBrowsers, name: "All browsers")]
        exclusionChoices += catalog.applications.filter { $0.isUserApplication }
        for key in excluded.sorted() where !exclusionChoices.contains(where: { $0.key == key }) {
            exclusionChoices.insert(AudioApplication(key: key, name: label(key)), at: 1)
        }
        for app in exclusionChoices {
            let item = NSMenuItem(title: app.name, action: #selector(selectExclusion(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = app.key
            item.state = excluded.contains(app.key) ? .on : .off; exclusions.addItem(item)
        }
        sourceItem.submenu = sources; exclusionItem.submenu = exclusions
    }
    private func selectionChanged() {
        save()
        do {
            if wanted && engine.device != 0 { try engine.update(selection: selection, catalog: catalog) }
        } catch { fail(error) }
        rebuildChoices()
    }
    @objc private func selectSource(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String else { return }
        if key == "whole-system" { selection.wholeSystem = true }
        else {
            if selection.wholeSystem { selection.applications = []; selection.wholeSystem = false }
            if selection.applications.contains(key) { selection.applications.remove(key) }
            else { selection.applications.insert(key) }
        }
        selectionChanged()
    }
    @objc private func selectExclusion(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String else { return }
        if key == "no-exclusion" { selection.excludedApplications.removeAll() }
        else if selection.excludedApplications.contains(key) { selection.excludedApplications.remove(key) }
        else { selection.excludedApplications.insert(key) }
        selection.applications = selection.applications.filter { !selection.isExcluded($0) }
        selectionChanged()
    }
    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func showAbout() {
        menu.cancelTracking()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let available = Set(["com.google.Chrome", "com.apple.Safari"].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        })
        let (alert, tools) = makeAboutAlert(version: version, availableBrowsers: available)
        tools.receiverButton.target = self; tools.receiverButton.action = #selector(openReceiverTest)
        tools.toneButton.target = self; tools.toneButton.action = #selector(openToneTest)
        tools.permissionsButton.target = self; tools.permissionsButton.action = #selector(openPermissions)
        aboutTools = tools
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let license = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(license) }
        aboutTools = nil
    }
    @objc private func openReceiverTest() { openBrowserTest(file: "ReceiverTest") }
    @objc private func openToneTest() { openBrowserTest(file: "ToneSource") }
    private func openBrowserTest(file: String) {
        guard let url = Bundle.main.url(forResource: file, withExtension: "html") else { return }
        let browser = aboutTools?.selectedBrowser ?? "default"
        if browser != "default", let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
        } else { NSWorkspace.shared.open(url) }
    }
    @objc private func showStatusDetails() {
        menu.cancelTracking()
        let alert = NSAlert()
        alert.messageText = "Macam capture status"
        alert.informativeText = statusDetail
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
