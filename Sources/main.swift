// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreAudio

final class ShutdownSignals {
    private var sources: [DispatchSourceSignal] = []
    init(action: @escaping () -> Void) {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: action); source.resume(); sources.append(source)
        }
    }
    deinit { sources.forEach { $0.cancel() } }
}
func duration(_ args: [String], after option: String) throws -> Double {
    guard let index = args.firstIndex(of: option), index + 1 < args.count,
          let seconds = Double(args[index + 1]), seconds.isFinite, seconds > 0, seconds <= 3600 else {
        throw MacamError(message: "\(option) requires a duration greater than 0 and at most 3600 seconds")
    }
    return seconds
}
func diagnostics() throws {
    let args = CommandLine.arguments
    if args.contains("--help") {
        print("""
        Macam — Mac Audio Mirror
        Mirror your Mac’s audio.

        Launch without arguments for the menu-bar app (starts stopped).
        --inspect                 Read devices and default/volume/mute settings
        --processes               List Core Audio processes and resolved app identities
        --probe SECONDS           Publish Macam Audio, meter, then remove it
        --read SECONDS            Independently open Macam Audio and meter its input
        --source BUNDLE_ID        Capture only this app; repeat for multiple sources
        --exclude BUNDLE_ID       Add a playback exclusion; repeat for multiple apps; none clears all
        --receiver BUNDLE_ID      Legacy alias for --exclude
        --allow-silence           Permit silent diagnostic results
        --cleanup                 Reclaim only resources in Macam's ownership journal
        --exercise-updates        Test source updates in place (use --source with active audio)

        Diagnostics measure audio and never record to a file. Grant System Audio
        Recording permission if prompted. --read may also require microphone access.
        """)
    } else if args.contains("--inspect") {
        printJSON(["settings": try HAL.snapshot(), "devices": try HAL.devices().map(HAL.describe)])
    } else if args.contains("--processes") {
        _ = try HAL.snapshot()
        let catalog = try ProcessCatalog.load()
        printJSON(["processes": catalog.processes.map {
            ["object": $0.object, "pid": $0.pid, "bundle": $0.rawBundle, "appKey": $0.key,
             "name": $0.name, "playing": $0.output] as [String: Any]
        }])
    } else if args.contains("--cleanup") {
        let owner = try AudioOwnership(); try owner.recover(); printJSON(["cleanup": "complete"])
    } else if args.contains("--exercise-updates") {
        let selected = try selectionFromArguments(args)
        guard !selected.wholeSystem else { throw MacamError(message: "--exercise-updates requires --source") }
        var empty = selected; empty.applications = ["bundle:org.macam.nonexistent-test-source"]
        let before = try HAL.snapshot(), engine = MirrorEngine()
        defer { engine.stop() }
        try engine.start(selection: empty)
        let device = engine.device
        func wait(_ seconds: Double, _ selection: CaptureSelection) throws {
            let end = Date(timeIntervalSinceNow: seconds)
            while Date() < end {
                RunLoop.current.run(until: min(end, Date(timeIntervalSinceNow: 0.1)))
                try engine.update(selection: selection, catalog: ProcessCatalog.load())
            }
        }
        try wait(1, empty)
        let silentBefore = engine.meter!.reading.nonzero
        try engine.update(selection: selected, catalog: ProcessCatalog.load())
        printJSON(["phase": "selected", "device": device])
        try wait(4, selected)
        let signal = engine.meter!.reading.nonzero - silentBefore
        try engine.update(selection: empty, catalog: ProcessCatalog.load())
        try wait(0.5, empty)
        let settled = engine.meter!.reading.nonzero
        try wait(2, empty)
        let leakage = engine.meter!.reading.nonzero - settled
        let stable = engine.device == device
        engine.stop()
        let equal = try NSDictionary(dictionary: before).isEqual(to: HAL.snapshot())
        printJSON(["inPlaceUpdates": ["initialNonzero": silentBefore, "selectedNonzero": signal,
                    "unselectedNonzeroAfterSettling": leakage, "deviceIDStable": stable, "settingsUnchanged": equal]])
        guard silentBefore == 0, signal > 0, leakage == 0, stable, equal else {
            throw MacamError(message: "Source update isolation test failed; play the selected source and inspect counters")
        }
    } else if args.contains("--read") {
        let seconds = try duration(args, after: "--read")
        guard let device = try HAL.devices().first(where: { (try? HAL.uid($0)) == MirrorEngine.deviceUID }) else {
            throw MacamError(message: "Macam Audio is not enumerated in this independent process")
        }
        let meter = try InputMeter(device: device)
        printJSON(["receiverDevice": HAL.describe(device)])
        var interrupted = false
        let signals = ShutdownSignals { interrupted = true }
        let end = Date(timeIntervalSinceNow: seconds), start = Date()
        while Date() < end && !interrupted { RunLoop.current.run(until: min(end, Date(timeIntervalSinceNow: 0.1))) }
        withExtendedLifetime(signals) {}
        let r = meter.reading
        var result = readingJSON(r)
        result["elapsedSeconds"] = Date().timeIntervalSince(start)
        result["interrupted"] = interrupted
        printJSON(["independentReceiver": result])
        if r.nonzero == 0 && !args.contains("--allow-silence") { throw MacamError(message: "Receiver got no non-silent samples") }
    } else if args.contains("--probe") {
        let seconds = try duration(args, after: "--probe"), selection = try selectionFromArguments(args)
        let before = try HAL.snapshot(), engine = MirrorEngine()
        defer { engine.stop() }
        try engine.start(selection: selection)
        printJSON(["started": HAL.describe(engine.device), "before": before])
        var interrupted = false
        let signals = ShutdownSignals { interrupted = true }
        let end = Date(timeIntervalSinceNow: seconds), start = Date()
        var refresh = Date.distantPast
        while Date() < end && !interrupted {
            RunLoop.current.run(until: min(end, Date(timeIntervalSinceNow: 0.1)))
            if Date().timeIntervalSince(refresh) >= 0.5 {
                try engine.update(selection: selection, catalog: ProcessCatalog.load()); refresh = Date()
            }
        }
        withExtendedLifetime(signals) {}
        let r = engine.meter!.reading
        var reading = readingJSON(r)
        reading["elapsedSeconds"] = Date().timeIntervalSince(start)
        reading["interrupted"] = interrupted
        let during = try HAL.snapshot()
        engine.stop()
        let after = try HAL.snapshot()
        let equal = NSDictionary(dictionary: before).isEqual(to: after) && NSDictionary(dictionary: before).isEqual(to: during)
        let removed = try !HAL.devices().contains { (try? HAL.uid($0)) == MirrorEngine.deviceUID }
        printJSON(["owner": reading, "during": during, "after": after, "settingsUnchanged": equal,
                   "deviceRemoved": removed, "cleanupErrors": engine.cleanupErrors])
        if !equal { throw MacamError(message: "Audio settings changed during test; inspect snapshots") }
        if !removed || !engine.cleanupErrors.isEmpty { throw MacamError(message: "Cleanup incomplete; inspect the ownership journal") }
        if r.nonzero == 0 && !args.contains("--allow-silence") { throw MacamError(message: "Owner got no non-silent samples; check source and recording permission") }
    } else { throw MacamError(message: "Unknown option. Use --help.") }
}
do {
    if CommandLine.arguments.count > 1 { try diagnostics() }
    else {
        let app = NSApplication.shared
        let controller = MenuBarController()
        app.delegate = controller
        app.run()
        withExtendedLifetime(controller) {}
    }
} catch {
    fputs("Macam: \(error.localizedDescription)\n", stderr)
    exit(1)
}
