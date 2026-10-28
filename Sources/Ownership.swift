// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreAudio
import Darwin

// An exclusive advisory lock prevents two Macam owners. A durable journal lists
// exact UUIDs before resource creation, so SIGKILL recovery never guesses by name.
final class AudioOwnership {
    struct Journal: Codable {
        let version: Int
        let deviceUID: String
        let tapUUID: String
    }
    private let lock: Int32
    private let journalURL: URL
    init() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Macam", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        journalURL = directory.appendingPathComponent("audio-resources.json")
        lock = open(directory.appendingPathComponent("owner.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw MacamError(message: "Cannot open Macam ownership lock: \(errno)") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock)
            throw MacamError(message: "Another Macam instance owns the audio input. Stop it first.")
        }
    }
    deinit { flock(lock, LOCK_UN); close(lock) }
    func prepare(uuid: UUID) throws {
        try recover()
        let journal = Journal(version: 1, deviceUID: MirrorEngine.deviceUID, tapUUID: uuid.uuidString)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: journalURL.path) { try FileManager.default.removeItem(at: journalURL) }
    }
    func recover() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else {
            if try HAL.devices().contains(where: { (try? HAL.uid($0)) == MirrorEngine.deviceUID }) {
                throw MacamError(message: "A Macam Audio device exists without its ownership journal. Refusing to remove an unverified resource.")
            }
            return
        }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.version == 1, journal.deviceUID == MirrorEngine.deviceUID,
              UUID(uuidString: journal.tapUUID) != nil else {
            throw MacamError(message: "Invalid Macam ownership journal; resources were left untouched.")
        }
        for device in try HAL.devices() where (try? HAL.uid(device)) == journal.deviceUID {
            guard (try? HAL.value(device, kAudioDevicePropertyTransportType, UInt32(0))) == kAudioDeviceTransportTypeAggregate,
                  (try? HAL.string(device, kAudioObjectPropertyName)) == "Macam Audio" else {
                throw MacamError(message: "Existing device does not match Macam's recorded aggregate")
            }
            var address = HAL.address(kAudioAggregateDevicePropertyTapList)
            var taps: Unmanaged<CFArray>?, size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
            try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &taps), "Read owned aggregate taps")
            let uuids = taps?.takeRetainedValue() as? [String] ?? []
            // A tap may already have vanished when its owner died. Reject any
            // unrelated tap attachment rather than destroying another resource.
            guard uuids.allSatisfy({ $0 == journal.tapUUID }) else {
                throw MacamError(message: "Recorded aggregate contains an unrelated tap; left untouched")
            }
            try check(AudioHardwareDestroyAggregateDevice(device), "Remove journaled Macam aggregate")
        }
        for tap in try HAL.ids(HAL.system, kAudioHardwarePropertyTapList) {
            guard (try? HAL.string(tap, kAudioTapPropertyUID)) == journal.tapUUID else { continue }
            var a = HAL.address(kAudioTapPropertyDescription)
            var desc: Unmanaged<CATapDescription>?, size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
            try check(AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &desc), "Read journaled tap")
            guard desc?.takeRetainedValue().name == MirrorEngine.tapPrefix + journal.tapUUID else {
                throw MacamError(message: "Tap UUID matches but its ownership name changed; left untouched")
            }
            try check(AudioHardwareDestroyProcessTap(tap), "Remove journaled Macam tap")
        }
        try clear()
    }
}
