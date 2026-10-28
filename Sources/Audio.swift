// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreAudio

struct MacamError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: UInt32(bitPattern: status) >> $0) }
        let fourCC = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? String(bytes: bytes, encoding: .ascii)! : ""
        throw MacamError(message: "\(operation): OSStatus \(status) \(fourCC)")
    }
}
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         _ initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: UInt32 = kAudioObjectPropertyElementMain) throws -> T {
        var a = address(selector, scope, element), result = initial
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutableBytes(of: &result) {
            try check(AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0.baseAddress!), "Read \(selector) on \(id)")
        }
        return result
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var a = address(selector), size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(id, &a, 0, nil, &size, &result), "Read string on \(id)")
        guard let result else { throw MacamError(message: "Missing audio object string") }
        return result.takeRetainedValue() as String
    }
    static func ids(_ id: AudioObjectID = system, _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        // Process/device lists can grow between the size query and the read.
        // Retry the query instead of disrupting capture for a new helper process.
        for attempt in 0..<3 {
            var a = address(selector, scope), size: UInt32 = 0
            try check(AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size), "Read list size")
            guard size > 0 else { return [] }
            var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
            let status = result.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0.baseAddress!)
            }
            if status == kAudioHardwareBadPropertySizeError && attempt < 2 { continue }
            try check(status, "Read object list")
            return Array(result.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
        }
        return [] // The final attempt always returns or throws.
    }
    static func devices() throws -> [AudioObjectID] { try ids(system, kAudioHardwarePropertyDevices) }
    static func uid(_ device: AudioObjectID) throws -> String { try string(device, kAudioDevicePropertyDeviceUID) }
    static func defaultOutput() throws -> AudioObjectID {
        try value(system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
    }
    static func formats(_ device: AudioObjectID) throws -> [AudioStreamBasicDescription] {
        try ids(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).map {
            try value($0, kAudioStreamPropertyVirtualFormat, AudioStreamBasicDescription())
        }
    }
    static func describe(_ device: AudioObjectID) -> [String: Any] {
        let formats = (try? formats(device)) ?? []
        return ["id": device, "name": (try? string(device, kAudioObjectPropertyName)) ?? "?",
                "uid": (try? uid(device)) ?? "?", "inputs": formats.map {
                    ["rate": $0.mSampleRate, "channels": $0.mChannelsPerFrame,
                     "format": $0.mFormatID, "flags": $0.mFormatFlags, "bits": $0.mBitsPerChannel] as [String: Any]
                }]
    }
    // Read-only snapshot. Missing/non-readable properties are explicitly omitted.
    static func snapshot() throws -> [String: Any] {
        guard try !devices().isEmpty else {
            throw MacamError(message: "Core Audio returned no devices. Run Macam outside the command sandbox on a logged-in Mac.")
        }
        var defaults: [String: String] = [:]
        for (key, selector) in [("input", kAudioHardwarePropertyDefaultInputDevice),
                                 ("output", kAudioHardwarePropertyDefaultOutputDevice),
                                 ("systemOutput", kAudioHardwarePropertyDefaultSystemOutputDevice)] {
            let id = try value(system, selector, AudioObjectID(0))
            defaults[key] = id == 0 ? "none" : try uid(id)
        }
        var devices: [String: [String: Any]] = [:]
        for d in try self.devices() where (try? uid(d)) != MirrorEngine.deviceUID {
            var properties: [String: Any] = [:]
            for (s, scope) in [("in", kAudioObjectPropertyScopeInput), ("out", kAudioObjectPropertyScopeOutput)] {
                // Include main and all stream channels, including devices with >2 channels.
                let streams = (try? ids(d, kAudioDevicePropertyStreams, scope: scope)) ?? []
                let channels = streams.reduce(0) { n, stream in
                    n + Int((try? value(stream, kAudioStreamPropertyVirtualFormat, AudioStreamBasicDescription()).mChannelsPerFrame) ?? 0)
                }
                for e in 0...channels {
                    if let v = try? value(d, kAudioDevicePropertyVolumeScalar, Float(0), scope: scope, element: UInt32(e)) {
                        properties["\(s).volume.\(e)"] = v
                    }
                    if let v = try? value(d, kAudioDevicePropertyMute, UInt32(0), scope: scope, element: UInt32(e)) {
                        properties["\(s).mute.\(e)"] = v
                    }
                }
            }
            devices[try uid(d)] = properties
        }
        return ["defaults": defaults, "devices": devices]
    }
}

final class InputMeter {
    let device: AudioObjectID
    private var proc: AudioDeviceIOProcID?
    private let meter: OpaquePointer
    init(device: AudioObjectID) throws {
        self.device = device
        guard let m = macam_meter_create() else { throw MacamError(message: "Meter allocation failed") }
        meter = m
        do {
            let formats = try HAL.formats(device)
            guard !formats.isEmpty, formats.reduce(0, { $0 + $1.mChannelsPerFrame }) == 2,
                  formats.allSatisfy({ $0.mFormatID == kAudioFormatLinearPCM && $0.mBitsPerChannel == 32 &&
                      $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 && $0.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 }) else {
                throw MacamError(message: "Macam Audio must provide stereo Float32 PCM: \(HAL.describe(device))")
            }
            try check(AudioDeviceCreateIOProcID(device, macam_input_callback, UnsafeMutableRawPointer(meter), &proc), "Create input callback")
            try check(AudioDeviceStart(device, proc), "Start input (allow System Audio Recording when prompted)")
        } catch {
            if let proc {
                AudioDeviceStop(device, proc)
                let status = AudioDeviceDestroyIOProcID(device, proc)
                // On an unexpected HAL teardown failure a callback could still
                // hold the context. Retain that allocation instead of freeing
                // memory that the real-time thread may still access.
                if status == noErr { macam_meter_destroy(meter) }
                else { fputs("Macam: input callback cleanup failed (\(status)); retaining callback memory for safety\n", stderr) }
            } else { macam_meter_destroy(meter) }
            throw error
        }
    }
    var reading: MacamReading { macam_meter_read(meter) }
    func close() throws {
        guard let proc else { return }
        AudioDeviceStop(device, proc)
        // DestroyIOProcID synchronizes with callbacks before context release.
        try check(AudioDeviceDestroyIOProcID(device, proc), "Destroy Macam input callback")
        self.proc = nil
    }
    deinit {
        do { try close(); macam_meter_destroy(meter) }
        catch { fputs("Macam: \(error.localizedDescription); retaining callback memory for safety\n", stderr) }
    }
}

final class MirrorEngine {
    static let deviceUID = "org.macam.Macam.Audio"
    static let tapPrefix = "org.macam.Macam.tap."
    private(set) var tap: AudioObjectID = 0
    private(set) var device: AudioObjectID = 0
    private(set) var meter: InputMeter?
    private var description: CATapDescription?
    private var ownership: AudioOwnership?
    private var fingerprint = ""
    private(set) var cleanupErrors: [String] = []

    func start(selection: CaptureSelection = CaptureSelection(), catalog: ProcessCatalog? = nil) throws {
        stop()
        guard device == 0, tap == 0, cleanupErrors.isEmpty else {
            throw MacamError(message: cleanupErrors.joined(separator: "\n"))
        }
        let catalog = try catalog ?? ProcessCatalog.load()
        if !selection.wholeSystem && selection.applications.isEmpty {
            throw MacamError(message: "Choose at least one source application")
        }
        if !selection.wholeSystem && selection.applications.contains(where: selection.isExcluded) {
            throw MacamError(message: "A selected source has playback exclusion enabled. Turn exclusion off or choose another source.")
        }
        let owner = try AudioOwnership()
        let d = CATapDescription()
        d.isMixdown = true
        d.isMono = false
        d.isExclusive = selection.wholeSystem
        d.name = Self.tapPrefix + d.uuid.uuidString
        d.isPrivate = false
        d.muteBehavior = .unmuted
        // Automatic restoration of process IDs by raw bundle ID can accidentally
        // broaden a Safari selection to shared WebKit helpers from other hosts.
        // Use explicit bundleIDs for unique identities and refresh resolved IDs.
        if #available(macOS 26.0, *) { d.isProcessRestoreEnabled = false }
        description = d
        do {
            try owner.prepare(uuid: d.uuid)
            ownership = owner
            apply(selection: selection, catalog: catalog, to: d)
            try check(AudioHardwareCreateProcessTap(d, &tap), "Create unmuted process tap")
            let tapUID = try HAL.string(tap, kAudioTapPropertyUID)
            // No physical subdevices, output streams, auto-start, or default-device writes.
            // The tap supplies the clock. Drift compensation has no second clock to align.
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Macam Audio",
                kAudioAggregateDeviceUIDKey: Self.deviceUID,
                kAudioAggregateDeviceIsPrivateKey: false,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID,
                                                   kAudioSubTapDriftCompensationKey: false]]
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device), "Create public Macam Audio input")
            meter = try InputMeter(device: device)
        } catch { stop(); throw error }
    }
    private func apply(selection: CaptureSelection, catalog: ProcessCatalog, to d: CATapDescription) {
        let config = catalog.configuration(selection)
        d.isExclusive = selection.wholeSystem
        d.processes = config.objects
        if #available(macOS 26.0, *) { d.bundleIDs = config.bundles }
        fingerprint = "\(selection.wholeSystem)|\(config.objects)|\(config.bundles)"
    }
    func update(selection: CaptureSelection, catalog: ProcessCatalog) throws {
        guard tap != 0, let description else { return }
        if !selection.wholeSystem && (selection.applications.isEmpty || selection.applications.contains(where: selection.isExcluded)) {
            throw MacamError(message: "Choose a source and turn off any playback exclusion that covers it")
        }
        let config = catalog.configuration(selection)
        let next = "\(selection.wholeSystem)|\(config.objects)|\(config.bundles)"
        guard next != fingerprint else { return }
        apply(selection: selection, catalog: catalog, to: description)
        var address = HAL.address(kAudioTapPropertyDescription)
        var object = Unmanaged.passUnretained(description)
        do {
            try check(AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: object)), &object), "Update Macam's tap sources")
        } catch { fingerprint = ""; throw error }
    }
    func stop() {
        cleanupErrors = []
        do { try meter?.close() }
        catch { cleanupErrors.append(error.localizedDescription); return }
        meter = nil
        if device != 0 {
            let status = AudioHardwareDestroyAggregateDevice(device)
            if status == noErr { device = 0 }
            else { cleanupErrors.append("Remove Macam Audio: OSStatus \(status)") }
        }
        if tap != 0 && device == 0 {
            let status = AudioHardwareDestroyProcessTap(tap)
            if status == noErr { tap = 0 }
            else { cleanupErrors.append("Remove Macam tap: OSStatus \(status)") }
        }
        if device == 0 && tap == 0 {
            description = nil
            if let ownership {
                do { try ownership.clear() } catch { cleanupErrors.append(error.localizedDescription) }
            }
            ownership = nil
            fingerprint = ""
        }
    }
    deinit { stop() }
}

func printJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) { print(string); fflush(stdout) }
}
func readingJSON(_ r: MacamReading) -> [String: Any] {
    ["callbacks": r.callbacks, "frames": r.frames, "samples": r.samples, "nonzeroSamples": r.nonzero,
     "timestampDiscontinuities": r.discontinuities, "peak": r.peak, "rms": r.rms, "maximumPeak": r.maximumPeak]
}
