// SPDX-License-Identifier: GPL-3.0-only
// Helper grouping informed by FineTune AudioProcessMonitor.swift,
// Copyright (C) 2026 Ronit Singh. See THIRD_PARTY_NOTICES.md.
import AppKit
import CoreAudio

struct AudioProcess {
    let object: AudioObjectID
    let pid: pid_t
    let rawBundle: String
    let key: String
    let name: String
    let output: Bool
}
struct AudioApplication {
    let key: String
    let name: String
    var isUserApplication = false
    var processes: [AudioProcess] = []
}
struct CaptureSelection: Codable, Equatable {
    var wholeSystem = true
    var applications: Set<String> = []
    // Each explicit exclusion covers an application and its helpers, never a tab.
    var excludedApplications: Set<String> = []
    static let allBrowsers = "all-browsers"
    static let ownKey = "bundle:org.macam.Macam"

    init() {}
    private enum CodingKeys: String, CodingKey {
        case wholeSystem, applications, excludedApplications, excludedApplication
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wholeSystem = try values.decodeIfPresent(Bool.self, forKey: .wholeSystem) ?? true
        applications = try values.decodeIfPresent(Set<String>.self, forKey: .applications) ?? []
        if let multiple = try values.decodeIfPresent(Set<String>.self, forKey: .excludedApplications) {
            excludedApplications = multiple
        } else if let previous = try values.decodeIfPresent(String.self, forKey: .excludedApplication) {
            excludedApplications = [previous] // Preserve the 0.2 explicit opt-in.
        }
        // 0.1's implicit `receiver` preference is intentionally not decoded.
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(wholeSystem, forKey: .wholeSystem)
        try values.encode(applications.sorted(), forKey: .applications)
        try values.encode(excludedApplications.sorted(), forKey: .excludedApplications)
    }
    func isExcluded(_ key: String) -> Bool {
        key == Self.ownKey || excludedApplications.contains(key) ||
            (excludedApplications.contains(Self.allBrowsers) && ProcessCatalog.isBrowser(key))
    }
}

func selectionFromArguments(_ args: [String]) throws -> CaptureSelection {
    var selection = CaptureSelection()
    for i in args.indices where args[i] == "--source" || args[i] == "--exclude" || args[i] == "--receiver" {
        guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
            throw MacamError(message: "Missing value after \(args[i])")
        }
        let raw = args[i + 1]
        let key = raw.hasPrefix("bundle:") || raw.hasPrefix("executable:") || raw == CaptureSelection.allBrowsers ? raw : "bundle:" + raw
        if args[i] == "--exclude" || args[i] == "--receiver" {
            if raw == "none" { selection.excludedApplications.removeAll() }
            else { selection.excludedApplications.insert(key) }
        } else { selection.wholeSystem = false; selection.applications.insert(key) }
    }
    return selection
}
struct ProcessCatalog {
    let processes: [AudioProcess]
    let applications: [AudioApplication]
    static let browsers = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "com.brave.Browser",
                           "com.microsoft.edgemac", "company.thebrowser.Browser", "org.chromium.Chromium",
                           "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.kagi.kagimacOS"]
    static func isBrowser(_ key: String) -> Bool {
        browsers.contains { key == "bundle:" + $0 || key.hasPrefix("bundle:" + $0 + ".") } || key.hasPrefix("bundle:com.apple.WebKit.")
    }
    static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard macam_process_path(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
    static func outerApp(_ path: String?) -> Bundle? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[..<range.lowerBound]) + ".app")
    }
    static func load() throws -> ProcessCatalog {
        let running = NSWorkspace.shared.runningApplications
        let regular = running.filter { $0.activationPolicy == .regular }
        let appsByPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var apps: [String: AudioApplication] = [:]
        for app in regular {
            guard let bundle = app.bundleIdentifier, bundle != "org.macam.Macam" else { continue }
            let key = "bundle:" + bundle
            apps[key] = AudioApplication(key: key, name: app.localizedName ?? bundle, isUserApplication: true)
        }
        func appFor(_ pid: pid_t) -> NSRunningApplication? {
            let responsible = macam_responsible_pid(pid)
            if responsible > 0, let app = appsByPID[responsible], app.activationPolicy == .regular { return app }
            var current = pid, visited = Set<pid_t>()
            for _ in 0..<64 {
                guard current > 1, visited.insert(current).inserted else { break }
                if let app = appsByPID[current], app.activationPolicy == .regular { return app }
                current = macam_parent_pid(current)
            }
            return nil
        }
        var processes: [AudioProcess] = []
        for object in try HAL.ids(HAL.system, kAudioHardwarePropertyProcessObjectList) {
            guard let pid = try? HAL.value(object, kAudioProcessPropertyPID, pid_t(0)), pid > 0 else { continue }
            let raw = (try? HAL.string(object, kAudioProcessPropertyBundleID)) ?? ""
            let app = appFor(pid)
            let executable = path(pid)
            let outer = outerApp(executable)
            let bundle = app?.bundleIdentifier ?? outer?.bundleIdentifier ?? (raw.isEmpty ? nil : raw)
            let key = pid == getpid() || raw == "org.macam.Macam" ? CaptureSelection.ownKey : bundle.map { "bundle:" + $0 } ?? "executable:" + (executable ?? "pid:\(pid)")
            let name = app?.localizedName ?? (outer?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (outer?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? executable.map { URL(fileURLWithPath: $0).lastPathComponent } ?? raw
            let p = AudioProcess(object: object, pid: pid, rawBundle: raw, key: key, name: name,
                                 output: (try? HAL.value(object, kAudioProcessPropertyIsRunningOutput, UInt32(0))) == 1)
            processes.append(p)
            if key != CaptureSelection.ownKey {
                if apps[key] == nil { apps[key] = AudioApplication(key: key, name: name) }
                apps[key]!.processes.append(p)
            }
        }
        return ProcessCatalog(processes: processes, applications: apps.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }
    func configuration(_ selection: CaptureSelection) -> (objects: [AudioObjectID], bundles: [String]) {
        let matching = processes.filter { p in
            let excluded = selection.isExcluded(p.key) || p.pid == getpid() ||
                (selection.excludedApplications.contains(CaptureSelection.allBrowsers) && Self.isBrowser("bundle:" + p.rawBundle))
            return selection.wholeSystem ? excluded : selection.applications.contains(p.key) && !excluded
        }
        var keys: Set<String>
        if selection.wholeSystem {
            keys = [CaptureSelection.ownKey]
            for excluded in selection.excludedApplications {
                if excluded == CaptureSelection.allBrowsers { keys.formUnion(Self.browsers.map { "bundle:" + $0 }) }
                else { keys.insert(excluded) }
            }
        } else { keys = selection.applications.filter { !selection.isExcluded($0) } }
        var bundles = Set(keys.compactMap { $0.hasPrefix("bundle:") ? String($0.dropFirst(7)) : nil })
        // Shared WebKit XPC bundle IDs identify helpers belonging to several apps.
        // Adding one to a selected Safari tap would also capture Mail/WebKit hosts.
        // Keep those helpers scoped by their resolved process object IDs instead.
        let owners = Dictionary(grouping: processes.filter { !$0.rawBundle.isEmpty }, by: \.rawBundle)
        matching.filter { !$0.rawBundle.isEmpty && !$0.rawBundle.hasPrefix("com.apple.WebKit.") }.forEach {
            if Set((owners[$0.rawBundle] ?? []).map(\.key)).count == 1 { bundles.insert($0.rawBundle) }
        }
        if selection.wholeSystem && selection.excludedApplications.contains(CaptureSelection.allBrowsers) {
            bundles.formUnion(["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent", "com.apple.WebKit.Networking"])
        }
        // Chromium audio utility helpers use a stable app-specific bundle ID.
        for base in Self.browsers where base != "com.apple.Safari" {
            if bundles.contains(base) { bundles.insert(base + ".helper") }
        }
        return (matching.map(\.object).sorted(), bundles.sorted())
    }
}
