import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import AppKit
import Darwin

let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/CodexCall", isDirectory: true)
let configURL = appSupportDir.appendingPathComponent("config.json")
let stateURL = appSupportDir.appendingPathComponent("state.json")
let pidURL = appSupportDir.appendingPathComponent("helper.pid")
let callTapReadyURL = appSupportDir.appendingPathComponent("call-tap-ready.pid")

let virtualRXName = "Codex Virtual RX"
let virtualTXName = "Codex Virtual TX"
let virtualClockName = "Codex Virtual Clock"

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func systemObject() -> AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

func deviceIDs() -> [AudioDeviceID] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject(), &address, 0, nil, &size) == noErr else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(systemObject(), &address, 0, nil, &size, &ids) == noErr else {
        return []
    }
    return ids
}

func deviceName(_ id: AudioDeviceID) -> String {
    var address = propertyAddress(kAudioObjectPropertyName)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) {
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return name as String
}

func deviceUID(_ id: AudioDeviceID) -> String {
    var address = propertyAddress(kAudioDevicePropertyDeviceUID)
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &uid) {
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return uid as String
}

func transportType(_ id: AudioDeviceID) -> UInt32 {
    var address = propertyAddress(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
        return 0
    }
    return value
}

func transportName(_ id: AudioDeviceID) -> String {
    switch transportType(id) {
    case kAudioDeviceTransportTypeVirtual: return "virtual"
    case kAudioDeviceTransportTypeAggregate: return "aggregate"
    case kAudioDeviceTransportTypeBuiltIn: return "built-in"
    case kAudioDeviceTransportTypeUSB: return "usb"
    case kAudioDeviceTransportTypeHDMI: return "hdmi"
    case kAudioDeviceTransportTypeDisplayPort: return "displayport"
    case kAudioDeviceTransportTypeAirPlay: return "airplay"
    case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
    case kAudioDeviceTransportTypeBluetoothLE: return "bluetooth-le"
    default: return "other"
    }
}

func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
        return 0
    }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func hasInput(_ id: AudioDeviceID) -> Bool { channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0 }
func hasOutput(_ id: AudioDeviceID) -> Bool { channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0 }

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    var address = propertyAddress(selector)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(systemObject(), &address, 0, nil, &size, &id) == noErr else {
        return 0
    }
    return id
}

@discardableResult
func setDefaultDevice(_ selector: AudioObjectPropertySelector, _ id: AudioDeviceID) -> Bool {
    var address = propertyAddress(selector)
    var value = id
    return AudioObjectSetPropertyData(
        systemObject(), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value
    ) == noErr
}

func defaultInput() -> AudioDeviceID { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }
func defaultOutput() -> AudioDeviceID { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
func defaultSystemOutput() -> AudioDeviceID {
    defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
}

func clockDeviceUID(fallback: String) -> String {
    if let id = findDevice(named: virtualClockName) { return deviceUID(id) }
    return fallback
}

func findDevice(named name: String) -> AudioDeviceID? {
    deviceIDs().first { deviceName($0) == name }
}

func findDevice(uid: String) -> AudioDeviceID? {
    deviceIDs().first { deviceUID($0) == uid }
}

func isVirtual(_ id: AudioDeviceID) -> Bool {
    let name = deviceName(id)
    return name == virtualRXName || name == virtualTXName || name == virtualClockName
}

func jsonString(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
    ), let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

func writeFile(_ url: URL, _ text: String) {
    try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

struct CallConfig: Codable {
    var physicalInputUID: String
    var physicalInputName: String
    var physicalOutputUID: String
    var physicalOutputName: String
    var originalDefaultInputUID: String?
    var originalDefaultOutputUID: String?
    var originalDefaultSystemOutputUID: String?
    var virtualRXName: String
    var virtualTXName: String
    var mode: String
}

struct CallState: Codable {
    var mode: String
    var state: String
    var goal: String?
    var number: String?
}

func loadConfig() -> CallConfig? {
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    return try? JSONDecoder().decode(CallConfig.self, from: data)
}

func saveConfig(_ config: CallConfig) {
    guard let data = try? JSONEncoder().encode(config) else { return }
    writeFile(configURL, String(data: data, encoding: .utf8) ?? "{}")
}

func loadState() -> CallState {
    guard let data = try? Data(contentsOf: stateURL),
          let state = try? JSONDecoder().decode(CallState.self, from: data) else {
        return CallState(mode: "normal", state: "NORMAL", goal: nil, number: nil)
    }
    return state
}

func saveState(_ state: CallState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    writeFile(stateURL, String(data: data, encoding: .utf8) ?? "{}")
}

func helperRunning() -> (Bool, Int32?) {
    guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
          let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return (false, nil)
    }
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    if kill(pid, 0) == 0, length > 0,
       String(cString: buffer).hasSuffix("/codex-call-helper") {
        return (true, pid)
    }
    return (false, pid)
}

func writePID() {
    writeFile(pidURL, "\(getpid())\n")
}

func clearPID() {
    try? FileManager.default.removeItem(at: pidURL)
}

final class RingBuffer {
    private var storage: UnsafeMutablePointer<Float>
    private let channels: Int
    private let capacity: Int
    private var writeFrame = 0
    private var readFrame = 0
    private var available = 0
    private let lock = NSLock()

    init(channels: Int, capacityFrames: Int) {
        self.channels = max(1, channels)
        self.capacity = max(1, capacityFrames)
        storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity * self.channels)
        storage.initialize(repeating: 0, count: self.capacity * self.channels)
    }

    deinit { storage.deallocate() }

    func write(_ src: UnsafePointer<Float>, frames: Int, srcChannels: Int) {
        guard frames > 0, srcChannels > 0 else { return }
        guard lock.try() else { return }
        defer { lock.unlock() }
        for frame in 0..<frames {
            let base = writeFrame * channels
            if srcChannels == channels {
                for channel in 0..<channels { storage[base + channel] = src[frame * srcChannels + channel] }
            } else if srcChannels == 1 {
                let value = src[frame]
                for channel in 0..<channels { storage[base + channel] = value }
            } else {
                for channel in 0..<channels {
                    storage[base + channel] = src[frame * srcChannels + min(channel, srcChannels - 1)]
                }
            }
            writeFrame = (writeFrame + 1) % capacity
            if available < capacity { available += 1 } else { readFrame = (readFrame + 1) % capacity }
        }
    }

    func read(into dst: UnsafeMutablePointer<Float>, frames: Int, dstChannels: Int) {
        guard frames > 0, dstChannels > 0 else { return }
        guard lock.try() else {
            for index in 0..<(frames * dstChannels) { dst[index] = 0 }
            return
        }
        defer { lock.unlock() }
        for frame in 0..<frames {
            if available <= 0 {
                for channel in 0..<dstChannels { dst[frame * dstChannels + channel] = 0 }
                continue
            }
            let base = readFrame * channels
            if dstChannels == channels {
                for channel in 0..<dstChannels { dst[frame * dstChannels + channel] = storage[base + channel] }
            } else if dstChannels == 1 {
                var sum: Float = 0
                for channel in 0..<channels { sum += storage[base + channel] }
                dst[frame] = sum / Float(channels)
            } else {
                for channel in 0..<dstChannels {
                    dst[frame * dstChannels + channel] = storage[base + min(channel, channels - 1)]
                }
            }
            readFrame = (readFrame + 1) % capacity
            available -= 1
        }
    }
}

final class Scratch {
    var data: [Float] = []
}

func inputToRings(_ inputData: UnsafePointer<AudioBufferList>, rings: [RingBuffer], scratch: Scratch) {
    guard !rings.isEmpty else { return }
    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    guard list.count > 0 else { return }
    var totalChannels = 0
    for buffer in list { totalChannels += Int(buffer.mNumberChannels) }
    guard totalChannels > 0 else { return }
    let first = list[0]
    let firstChannels = max(1, Int(first.mNumberChannels))
    let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * firstChannels)
    guard frames > 0 else { return }
    let needed = frames * totalChannels
    if scratch.data.count < needed { scratch.data = [Float](repeating: 0, count: needed) }
    scratch.data.withUnsafeMutableBufferPointer { destination in
        guard let base = destination.baseAddress else { return }
        var channelOffset = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let source = raw.assumingMemoryBound(to: Float.self)
            if channels == 1 {
                for frame in 0..<frames { base[frame * totalChannels + channelOffset] = source[frame] }
            } else {
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        base[frame * totalChannels + channelOffset + channel] = source[frame * channels + channel]
                    }
                }
            }
            channelOffset += channels
        }
    }
    scratch.data.withUnsafeBufferPointer { source in
        if let base = source.baseAddress {
            for ring in rings {
                ring.write(base, frames: frames, srcChannels: totalChannels)
            }
        }
    }
}

func inputToRing(_ inputData: UnsafePointer<AudioBufferList>, ring: RingBuffer, scratch: Scratch) {
    inputToRings(inputData, rings: [ring], scratch: scratch)
}

func ringToOutput(_ outputData: UnsafeMutablePointer<AudioBufferList>, ring: RingBuffer, scratch: Scratch) {
    let list = UnsafeMutableAudioBufferListPointer(outputData)
    guard list.count > 0 else { return }
    var totalChannels = 0
    for buffer in list { totalChannels += Int(buffer.mNumberChannels) }
    guard totalChannels > 0 else { return }
    let first = list[0]
    let firstChannels = max(1, Int(first.mNumberChannels))
    let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * firstChannels)
    guard frames > 0 else { return }
    let needed = frames * totalChannels
    if scratch.data.count < needed { scratch.data = [Float](repeating: 0, count: needed) }
    scratch.data.withUnsafeMutableBufferPointer { source in
        if let base = source.baseAddress {
            ring.read(into: base, frames: frames, dstChannels: totalChannels)
        }
    }
    scratch.data.withUnsafeBufferPointer { source in
        guard let base = source.baseAddress else { return }
        var channelOffset = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let destination = raw.assumingMemoryBound(to: Float.self)
            if channels == 1 {
                for frame in 0..<frames { destination[frame] = base[frame * totalChannels + channelOffset] }
            } else {
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        destination[frame * channels + channel] = base[frame * totalChannels + channelOffset + channel]
                    }
                }
            }
            channelOffset += channels
        }
    }
}

final class MixerScratch {
    var mix: [Float] = []
    var source: [Float] = []
}

func mixRings(
    _ rings: [RingBuffer],
    into mixBase: UnsafeMutablePointer<Float>,
    frames: Int,
    channels: Int,
    scratch: MixerScratch
) {
    let needed = frames * channels
    if scratch.source.count < needed { scratch.source = [Float](repeating: 0, count: needed) }
    for index in 0..<needed { mixBase[index] = 0 }
    for ring in rings {
        scratch.source.withUnsafeMutableBufferPointer { source in
            guard let sourceBase = source.baseAddress else { return }
            ring.read(into: sourceBase, frames: frames, dstChannels: channels)
            for index in 0..<needed {
                mixBase[index] = max(-1, min(1, mixBase[index] + sourceBase[index]))
            }
        }
    }
}

func ringsToOutput(
    _ outputData: UnsafeMutablePointer<AudioBufferList>,
    rings: [RingBuffer],
    scratch: MixerScratch
) {
    let list = UnsafeMutableAudioBufferListPointer(outputData)
    guard list.count > 0 else { return }
    var totalChannels = 0
    for buffer in list { totalChannels += Int(buffer.mNumberChannels) }
    guard totalChannels > 0 else { return }
    let first = list[0]
    let firstChannels = max(1, Int(first.mNumberChannels))
    let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * firstChannels)
    guard frames > 0 else { return }
    let needed = frames * totalChannels
    if scratch.mix.count < needed { scratch.mix = [Float](repeating: 0, count: needed) }

    scratch.mix.withUnsafeMutableBufferPointer { mix in
        guard let mixBase = mix.baseAddress else { return }
        mixRings(rings, into: mixBase, frames: frames, channels: totalChannels, scratch: scratch)
    }

    scratch.mix.withUnsafeBufferPointer { mix in
        guard let base = mix.baseAddress else { return }
        var channelOffset = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let destination = raw.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    destination[frame * channels + channel] =
                        base[frame * totalChannels + channelOffset + channel]
                }
            }
            channelOffset += channels
        }
    }
}

enum RouterError: Error {
    case ioProc(String)
}

final class Router {
    struct Link {
        let source: AudioDeviceID
        let destination: AudioDeviceID
    }

    private var procs: [(AudioDeviceID, AudioDeviceIOProcID)] = []
    private var rings: [RingBuffer] = []
    private var scratches: [Scratch] = []
    private var mixerScratches: [MixerScratch] = []
    private(set) var running = false

    func start(links: [Link]) throws {
        stop()
        do {
            var sourceRings: [AudioDeviceID: [RingBuffer]] = [:]
            var destinationRings: [AudioDeviceID: [RingBuffer]] = [:]
            for link in links {
                let ring = RingBuffer(channels: 8, capacityFrames: 96_000)
                rings.append(ring)
                sourceRings[link.source, default: []].append(ring)
                destinationRings[link.destination, default: []].append(ring)
            }
            for (source, sourceLinks) in sourceRings {
                let scratch = Scratch()
                scratches.append(scratch)
                try addCapture(source, rings: sourceLinks, scratch: scratch)
            }
            for (destination, destinationLinks) in destinationRings {
                let scratch = MixerScratch()
                mixerScratches.append(scratch)
                try addRender(destination, rings: destinationLinks, scratch: scratch)
            }
            running = true
        } catch {
            // Never leave a half-built graph running after one endpoint fails.
            stop()
            throw error
        }
    }

    private func addCapture(_ device: AudioDeviceID, rings: [RingBuffer], scratch: Scratch) throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil) {
            _, inputData, _, _, _ in
            inputToRings(inputData, rings: rings, scratch: scratch)
        }
        guard status == noErr, let proc = procID else {
            throw RouterError.ioProc("capture \(deviceName(device)): \(status)")
        }
        guard AudioDeviceStart(device, proc) == noErr else {
            AudioDeviceDestroyIOProcID(device, proc)
            throw RouterError.ioProc("start capture \(deviceName(device))")
        }
        procs.append((device, proc))
    }

    private func addRender(_ device: AudioDeviceID, rings: [RingBuffer], scratch: MixerScratch) throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil) {
            _, _, _, outputData, _ in
            ringsToOutput(outputData, rings: rings, scratch: scratch)
        }
        guard status == noErr, let proc = procID else {
            throw RouterError.ioProc("render \(deviceName(device)): \(status)")
        }
        guard AudioDeviceStart(device, proc) == noErr else {
            AudioDeviceDestroyIOProcID(device, proc)
            throw RouterError.ioProc("start render \(deviceName(device))")
        }
        procs.append((device, proc))
    }

    func stop() {
        for (device, proc) in procs {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        procs.removeAll()
        rings.removeAll()
        scratches.removeAll()
        mixerScratches.removeAll()
        running = false
    }
}

func resolvedPhysicalInput(preferredName: String?) -> AudioDeviceID? {
    if let name = preferredName, let id = findDevice(named: name) { return id }
    let current = defaultInput()
    if current != 0, !isVirtual(current), hasInput(current) { return current }
    return deviceIDs().first { hasInput($0) && !isVirtual($0) }
}

func resolvedPhysicalOutput(preferredName: String?) -> AudioDeviceID? {
    if let name = preferredName, let id = findDevice(named: name) { return id }
    let current = defaultOutput()
    if current != 0, !isVirtual(current), hasOutput(current) { return current }
    return deviceIDs().first { hasOutput($0) && !isVirtual($0) }
}

func deviceSummary(_ id: AudioDeviceID) -> [String: Any] {
    [
        "id": Int(id),
        "name": deviceName(id),
        "uid": deviceUID(id),
        "transport": transportName(id),
        "inputChannels": channelCount(id, scope: kAudioObjectPropertyScopeInput),
        "outputChannels": channelCount(id, scope: kAudioObjectPropertyScopeOutput),
    ]
}

func option(_ name: String, _ argv: [String]) -> String? {
    guard let index = argv.firstIndex(of: name), index + 1 < argv.count else { return nil }
    return argv[index + 1]
}

func commandDevices(json: Bool) {
    let ids = deviceIDs()
    let input = defaultInput()
    let output = defaultOutput()
    if json {
        let devices = ids.map { id -> [String: Any] in
            var summary = deviceSummary(id)
            summary["defaultInput"] = (id == input)
            summary["defaultOutput"] = (id == output)
            return summary
        }
        print(jsonString(["ok": true, "devices": devices]))
        return
    }
    for id in ids {
        var tags: [String] = []
        if id == input { tags.append("default-input") }
        if id == output { tags.append("default-output") }
        let suffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ","))]"
        print("- \(deviceName(id)) (\(transportName(id)), in:\(channelCount(id, scope: kAudioObjectPropertyScopeInput)) out:\(channelCount(id, scope: kAudioObjectPropertyScopeOutput)))\(suffix)")
    }
}

func commandStatus(json: Bool) {
    let state = loadState()
    let (running, pid) = helperRunning()
    let rx = findDevice(named: virtualRXName)
    let tx = findDevice(named: virtualTXName)
    let clock = findDevice(named: virtualClockName)
    let config = loadConfig()
    if json {
        print(jsonString([
            "ok": true,
            "state": state.state,
            "mode": state.mode,
            "goal": state.goal ?? NSNull(),
            "number": state.number ?? NSNull(),
            "helperRunning": running,
            "helperPid": pid.map { Int($0) } ?? NSNull(),
            "virtualRX": rx.map { deviceName($0) } ?? NSNull(),
            "virtualTX": tx.map { deviceName($0) } ?? NSNull(),
            "virtualClock": clock.map { deviceName($0) } ?? NSNull(),
            "physicalInput": config?.physicalInputName ?? NSNull(),
            "physicalOutput": config?.physicalOutputName ?? NSNull(),
        ]))
        return
    }
    print("State: \(state.state)")
    print("Mode: \(state.mode)")
    if let goal = state.goal { print("Goal: \(goal)") }
    print("Helper: \(running ? "running (pid \(pid ?? 0))" : "not running")")
}

func commandAudioStatus(json: Bool) {
    let rx = findDevice(named: virtualRXName)
    let tx = findDevice(named: virtualTXName)
    let clock = findDevice(named: virtualClockName)
    let config = loadConfig()
    let (running, pid) = helperRunning()
    let input = defaultInput()
    let output = defaultOutput()
    let state = loadState()
    let facetime = FileManager.default.fileExists(atPath: "/System/Applications/FaceTime.app")
    let phone = FileManager.default.fileExists(atPath: "/System/Applications/Phone.app")
    let appleCalling = facetime || phone

    if json {
        print(jsonString([
            "ok": true,
            "plugin": "loaded",
            "helperRunning": running,
            "helperPid": pid.map { Int($0) } ?? NSNull(),
            "virtualRX": rx != nil,
            "virtualTX": tx != nil,
            "virtualClock": clock != nil,
            "mode": state.mode.uppercased(),
            "physicalInput": config?.physicalInputName ?? deviceName(input),
            "physicalOutput": config?.physicalOutputName ?? deviceName(output),
            "codexInput": rx != nil ? virtualRXName : deviceName(input),
            "codexOutput": tx != nil ? virtualTXName : deviceName(output),
            "defaultInput": deviceName(input),
            "defaultOutput": deviceName(output),
            "appleCalling": appleCalling ? "available" : "unavailable",
        ]))
        return
    }

    print("Plugin: loaded")
    print("Native helper: \(running ? "running" : "not running")")
    print("Virtual RX: \(rx != nil ? "found" : "missing")")
    print("Virtual TX: \(tx != nil ? "found" : "missing")")
    print("Virtual Clock: \(clock != nil ? "found" : "missing")")
    print("")
    print("Mode: \(state.mode.uppercased())")
    print("")
    print("Physical mic:")
    print(config?.physicalInputName ?? deviceName(input))
    print("")
    print("Physical output:")
    print(config?.physicalOutputName ?? deviceName(output))
    print("")
    print("Codex input:")
    print(rx != nil ? virtualRXName : deviceName(input))
    print("")
    print("Codex output:")
    print(tx != nil ? virtualTXName : deviceName(output))
    print("")
    print("Apple call capability:")
    print(appleCalling ? "available" : "unavailable")
}

func commandSetup(argv: [String], json: Bool) {
    guard let rx = findDevice(named: virtualRXName),
          let tx = findDevice(named: virtualTXName),
          findDevice(named: virtualClockName) != nil else {
        let message = "Codex Virtual RX/TX/Clock not found. Install the virtual audio driver first."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }
    guard let input = resolvedPhysicalInput(preferredName: option("--physical-input", argv)) else {
        let message = "Could not determine a physical microphone."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }
    guard let output = resolvedPhysicalOutput(preferredName: option("--physical-output", argv)) else {
        let message = "Could not determine a physical output."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }

    let existing = loadConfig()
    let currentInput = defaultInput()
    let currentOutput = defaultOutput()
    let currentSystemOutput = defaultSystemOutput()
    let originalInput = (isVirtual(currentInput) ? existing?.originalDefaultInputUID : deviceUID(currentInput)) ?? existing?.originalDefaultInputUID
    let originalOutput = (isVirtual(currentOutput) ? existing?.originalDefaultOutputUID : deviceUID(currentOutput)) ?? existing?.originalDefaultOutputUID
    let originalSystemOutput = (isVirtual(currentSystemOutput)
        ? existing?.originalDefaultSystemOutputUID
        : deviceUID(currentSystemOutput)) ?? existing?.originalDefaultSystemOutputUID

    let config = CallConfig(
        physicalInputUID: deviceUID(input),
        physicalInputName: deviceName(input),
        physicalOutputUID: deviceUID(output),
        physicalOutputName: deviceName(output),
        originalDefaultInputUID: originalInput,
        originalDefaultOutputUID: originalOutput,
        originalDefaultSystemOutputUID: originalSystemOutput,
        virtualRXName: virtualRXName,
        virtualTXName: virtualTXName,
        mode: "normal"
    )
    saveConfig(config)
    saveState(CallState(mode: "normal", state: "NORMAL", goal: nil, number: nil))

    setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, rx)
    setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)

    if json {
        print(jsonString([
            "ok": true,
            "virtualRX": virtualRXName,
            "virtualTX": virtualTXName,
            "physicalInput": config.physicalInputName,
            "physicalOutput": config.physicalOutputName,
            "codexInput": virtualRXName,
            "codexOutput": virtualTXName,
        ]))
        return
    }
    print("Codex Call setup")
    print("")
    print("Virtual RX: OK")
    print("Virtual TX: OK")
    print("Physical microphone: \(config.physicalInputName)")
    print("Physical output: \(config.physicalOutputName)")
    print("Codex realtime input: \(virtualRXName)")
    print("Codex realtime output: \(virtualTXName)")
    print("Apple calling: available")
    print("")
    print("Ready to make calls.")
}

func commandRestore(json: Bool) {
    let config = loadConfig()
    var restored = false
    if let uid = config?.originalDefaultInputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id)
        restored = true
    }
    if let uid = config?.originalDefaultOutputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id)
        restored = true
    }
    if let uid = config?.originalDefaultSystemOutputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
        restored = true
    }
    saveState(CallState(mode: "normal", state: "NORMAL", goal: nil, number: nil))
    if json {
        print(jsonString([
            "ok": true,
            "restored": restored,
            "defaultInput": deviceName(defaultInput()),
            "defaultOutput": deviceName(defaultOutput()),
        ]))
        return
    }
    print("Restored default input: \(deviceName(defaultInput()))")
    print("Restored default output: \(deviceName(defaultOutput()))")
}

let callUIBundleIDs = ["com.apple.FaceTime", "com.apple.mobilephone", "com.apple.Phone"]
let callServiceBundleIDs = ["com.apple.avconferenced", "com.apple.TelephonyUtilities"]
let callAppBundleIDs = callUIBundleIDs + callServiceBundleIDs

func callUIAppRunning() -> Bool {
    processObjectIDs().contains { callUIBundleIDs.contains(processBundleID($0)) }
}

func callAppProcessObjects() -> [AudioObjectID] {
    if let pidString = ProcessInfo.processInfo.environment["CODEX_CALL_TAP_PID"],
       let pid = pid_t(pidString), let object = processObjectID(forPID: pid) {
        return [object]
    }
    let processes = processObjectIDs()
    let direct = processes.filter { callUIBundleIDs.contains(processBundleID($0)) }
    let activeServices = processes.filter {
        callServiceBundleIDs.contains(processBundleID($0))
            && (processIsRunningInput($0) || processIsRunningOutput($0))
    }
    if !direct.isEmpty { return direct + activeServices }
    let services = processes.filter { callServiceBundleIDs.contains(processBundleID($0)) }
    return activeServices.isEmpty ? services : activeServices
}

func callAudioActive() -> Bool {
    let processes = processObjectIDs()
    let direct = processes.filter { callUIBundleIDs.contains(processBundleID($0)) }
    if direct.contains(where: { processIsRunningInput($0) || processIsRunningOutput($0) }) {
        return true
    }
    // avconferenced can also be active for unrelated apps. Treat it as call audio
    // only while a Phone/FaceTime audio process is present.
    return !direct.isEmpty && processes.contains {
        callServiceBundleIDs.contains(processBundleID($0))
            && (processIsRunningInput($0) || processIsRunningOutput($0))
    }
}

func commandRun(argv: [String], json: Bool) {
    guard let config = loadConfig() else {
        let message = "No configuration. Run setup first."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }
    guard let rx = findDevice(named: config.virtualRXName), let tx = findDevice(named: config.virtualTXName) else {
        let message = "Codex Virtual RX/TX not found."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }
    guard let input = findDevice(uid: config.physicalInputUID) ?? resolvedPhysicalInput(preferredName: nil) else {
        let message = "Physical microphone not available."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }
    guard let output = findDevice(uid: config.physicalOutputUID) ?? resolvedPhysicalOutput(preferredName: nil) else {
        let message = "Physical output not available."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }

    let router = Router()
    var mode = ""
    var physicalOutput = output
    var callTapChild: Process?

    func teardownTap(stopRouting: Bool = true) {
        stopCallTap()
        if stopRouting { router.stop() }
    }

    func rebuild() {
        // Creating/destroying the private tap aggregate can invalidate already
        // running physical-output IOProcs. Start the speaker mixer only after the
        // child has finished creating and starting that aggregate.
        if mode == "call", !callTapReady() {
            router.stop()
            return
        }
        do {
            var links: [Router.Link] = []
            if mode == "call" {
                // The tap child writes the muted remote caller into RX. Capture RX
                // and TX here and mix both into ONE physical-output IOProc. Giving
                // the child a second speaker IOProc made the two render paths race,
                // while sharing one ring between RX and the speaker let either
                // consumer starve the other.
                links.append(Router.Link(source: rx, destination: physicalOutput))
                links.append(Router.Link(source: tx, destination: physicalOutput))
            } else {
                links.append(Router.Link(source: input, destination: rx))
                links.append(Router.Link(source: tx, destination: physicalOutput))
            }
            try router.start(links: links)
        } catch {
            if json { print(jsonString(["ok": false, "error": "\(error)"])) } else { print("Router error: \(error)") }
        }
    }

    func switchMode(_ newMode: String) {
        guard newMode != mode else { return }
        teardownTap()
        mode = newMode
        if mode == "call" {
            setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, tx)
            setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)
            setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, tx)
            spawnCallTap()
        } else {
            setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, rx)
            setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)
            setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, tx)
        }
        rebuild()
    }

    func spawnCallTap() {
        guard mode == "call", callTapChild == nil else { return }
        try? FileManager.default.removeItem(at: callTapReadyURL)
        let helper = CommandLine.arguments[0]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["tap-call", "--to", virtualRXName, "--json"]
        // Hidden aggregate/tap failures previously looked like connected calls with
        // silent audio, so keep child diagnostics in the app log.
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            callTapChild = process
            print("tap: spawned separate call tap -> \(virtualRXName)")
            fflush(stdout)
        } catch {
            print("tap: failed to spawn (\(error))")
            fflush(stdout)
        }
    }

    func stopCallTap() {
        if let child = callTapChild, child.isRunning {
            child.terminate()
            for _ in 0..<20 where child.isRunning {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
            }
            child.waitUntilExit()
        }
        callTapChild = nil
        try? FileManager.default.removeItem(at: callTapReadyURL)
    }

    func callTapReady() -> Bool {
        guard let child = callTapChild, child.isRunning,
              let text = try? String(contentsOf: callTapReadyURL, encoding: .utf8),
              Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) == child.processIdentifier else {
            return false
        }
        return true
    }

    switchMode(loadState().mode == "call" ? "call" : "normal")

    writePID()

    if json {
        print(jsonString([
            "ok": true,
            "running": true,
            "pid": Int(getpid()),
            "mode": mode,
            "physicalInput": deviceName(input),
            "physicalOutput": deviceName(output),
        ]))
    } else {
        print("Codex Call router running (pid \(getpid())), mode \(mode).")
        print("  input: \(deviceName(input)) -> \(deviceName(rx))")
        print("  \(deviceName(tx)) -> \(deviceName(output))")
    }
    fflush(stdout)

    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "codex-call.signals")
    var sources: [DispatchSourceSignal] = []
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
        source.setEventHandler { semaphore.signal() }
        source.resume()
        sources.append(source)
    }
    _ = sources

    let workQueue = DispatchQueue(label: "codexcall.work")
    let reassert = {
        let targetInput = mode == "call" ? tx : rx
        if defaultInput() != targetInput {
            setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, targetInput)
        }
        if defaultOutput() != tx {
            setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)
        }
        if defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) != tx {
            setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, tx)
        }
    }

    var inputListenerAddress = propertyAddress(kAudioHardwarePropertyDefaultInputDevice)
    AudioObjectAddPropertyListenerBlock(systemObject(), &inputListenerAddress, workQueue) { _, _ in
        reassert()
    }
    var outputListenerAddress = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    AudioObjectAddPropertyListenerBlock(systemObject(), &outputListenerAddress, workQueue) { _, _ in
        let newDefault = defaultOutput()
        if newDefault != tx, newDefault != rx, hasOutput(newDefault), newDefault != physicalOutput {
            physicalOutput = newDefault
            print("physical output updated: \(deviceName(newDefault))")
            fflush(stdout)
            rebuild()
        }
        reassert()
    }
    var systemOutputListenerAddress = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
    AudioObjectAddPropertyListenerBlock(systemObject(), &systemOutputListenerAddress, workQueue) { _, _ in
        reassert()
    }

    var lastProcessLog = Date.distantPast
    var callUIWasSeen = false
    var callAudioWasActive = false
    var callAudioIdleSince: Date?
    var callModeStartedAt = Date()
    let timer = DispatchSource.makeTimerSource(queue: workQueue)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler {
        reassert()
        let desired = loadState().mode == "call" ? "call" : "normal"
        if desired != mode {
            switchMode(desired)
            callModeStartedAt = Date()
            callUIWasSeen = false
            callAudioWasActive = false
            callAudioIdleSince = nil
        } else if mode == "call" {
            if let child = callTapChild, !child.isRunning {
                let status = child.terminationStatus
                callTapChild = nil
                try? FileManager.default.removeItem(at: callTapReadyURL)
                print("tap: child exited with status \(status); restarting")
                fflush(stdout)
            }
            if callTapChild == nil {
                router.stop()
                spawnCallTap()
            }
        }
        if mode == "call" {
            if callTapReady(), !router.running {
                rebuild()
                print("call monitor ready: RX + TX -> \(deviceName(physicalOutput))")
                fflush(stdout)
            }
            if callUIAppRunning() {
                callUIWasSeen = true
            }

            // Wait for the child to render remote audio into RX before announcing
            // IN_CALL. This also lets the aggregate settle before Codex first speaks.
            let audioActive = callAudioActive() && callTapReady()
            if audioActive {
                if !callAudioWasActive {
                    var state = loadState()
                    state.state = "IN_CALL"
                    saveState(state)
                    print("call audio active; state is IN_CALL")
                    fflush(stdout)
                }
                callAudioWasActive = true
                callAudioIdleSince = nil
            } else if callAudioWasActive || (callUIWasSeen && !callUIAppRunning()) {
                if callAudioIdleSince == nil {
                    callAudioIdleSince = Date()
                } else if Date().timeIntervalSince(callAudioIdleSince!) > 5 {
                    saveState(CallState(mode: "normal", state: "NORMAL", goal: nil, number: nil))
                    switchMode("normal")
                    callUIWasSeen = false
                    callAudioWasActive = false
                    callAudioIdleSince = nil
                    print("call audio ended; restored normal mode")
                    fflush(stdout)
                }
            } else if Date().timeIntervalSince(callModeStartedAt) > 120 {
                saveState(CallState(mode: "normal", state: "ERROR", goal: nil, number: nil))
                switchMode("normal")
                print("call never opened audio; restored normal mode")
                fflush(stdout)
            }
            if Date().timeIntervalSince(lastProcessLog) > 3 {
                lastProcessLog = Date()
                let active = processObjectIDs()
                    .filter { processIsRunningOutput($0) }
                    .map { processBundleID($0) }
                print("call-mode output processes: \(active)")
                fflush(stdout)
            }
        }
    }
    timer.resume()

    semaphore.wait()
    timer.cancel()
    router.stop()
    teardownTap(stopRouting: false)
    clearPID()

    if let uid = config.originalDefaultInputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id)
    }
    if let uid = config.originalDefaultOutputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id)
    }
    if let uid = config.originalDefaultSystemOutputUID, let id = findDevice(uid: uid) {
        setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
    }
    print("Router stopped; default audio devices restored.")
}

func commandRoute(argv: [String], json: Bool) {
    let mode = argv.count > 1 && !argv[1].hasPrefix("--") ? argv[1] : ""
    switch mode {
    case "normal":
        var state = loadState()
        state.mode = "normal"
        state.state = "NORMAL"
        state.goal = nil
        state.number = nil
        saveState(state)
        enterNormalModeDefaults()
        if json { print(jsonString(["ok": true, "mode": "normal"])) } else { print("Audio routing set to normal mode.") }
    case "call":
        var state = loadState()
        state.mode = "call"
        state.state = "IN_CALL"
        saveState(state)
        enterCallModeDefaults()
        if json { print(jsonString(["ok": true, "mode": "call"])) } else { print("Audio routing set to call mode.") }
    default:
        let message = "route requires 'normal' or 'call'."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(64)
    }
}

func commandDoctor(json: Bool) {
    let rx = findDevice(named: virtualRXName)
    let tx = findDevice(named: virtualTXName)
    let clock = findDevice(named: virtualClockName)
    let config = loadConfig()
    let (running, pid) = helperRunning()
    let input = defaultInput()
    let output = defaultOutput()
    let callMode = loadState().mode == "call"
    let expectedInput = callMode ? tx : rx
    let expectedInputName = callMode ? virtualTXName : virtualRXName
    let inputDefault = expectedInput != nil && input == expectedInput
    let txDefault = tx != nil && output == tx
    let facetime = FileManager.default.fileExists(atPath: "/System/Applications/FaceTime.app")
    let phone = FileManager.default.fileExists(atPath: "/System/Applications/Phone.app")

    let checks: [(String, Bool, String)] = [
        ("Virtual RX", rx != nil, rx != nil ? virtualRXName : "missing"),
        ("Virtual TX", tx != nil, tx != nil ? virtualTXName : "missing"),
        ("Virtual Clock", clock != nil, clock != nil ? virtualClockName : "missing"),
        ("Physical microphone", config != nil, config?.physicalInputName ?? "not configured"),
        ("Physical output", config != nil, config?.physicalOutputName ?? "not configured"),
        ("Default input is \(expectedInputName)", inputDefault, deviceName(input)),
        ("Default output is TX", txDefault, deviceName(output)),
        ("Helper running", running, running ? "pid \(pid ?? 0)" : "not running"),
        ("Apple calling", facetime || phone, (facetime || phone) ? "available" : "unavailable"),
    ]

    if json {
        let results = checks.map { ["name": $0.0, "ok": $0.1, "detail": $0.2] as [String: Any] }
        let allOK = checks.allSatisfy { $0.1 }
        print(jsonString(["ok": allOK, "checks": results]))
        return
    }
    print("Codex Call diagnostics")
    print("")
    for (name, ok, detail) in checks {
        print("\(ok ? "OK  " : "FAIL") \(name): \(detail)")
    }
    print("")
    print(checks.allSatisfy { $0.1 } ? "Ready." : "Problems found.")
}

func commandSelftest(json: Bool) {
    guard let input = resolvedPhysicalInput(preferredName: option("--input", CommandLine.arguments)) else {
        if json { print(jsonString(["ok": false, "error": "no physical input"])) } else { print("No physical input found.") }
        exit(2)
    }
    let ring = RingBuffer(channels: 8, capacityFrames: 96_000)
    let scratch = Scratch()
    var procID: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(&procID, input, nil) { _, inputData, _, _, _ in
        inputToRing(inputData, ring: ring, scratch: scratch)
    }
    guard status == noErr, let proc = procID else {
        if json { print(jsonString(["ok": false, "error": "cannot open \(deviceName(input))"])) } else { print("Cannot open \(deviceName(input)).") }
        exit(3)
    }
    AudioDeviceStart(input, proc)
    Thread.sleep(forTimeInterval: 1.0)
    AudioDeviceStop(input, proc)
    AudioDeviceDestroyIOProcID(input, proc)

    var probe = [Float](repeating: 0, count: 4096 * 8)
    let frames = 4096
    let channels = max(1, channelCount(input, scope: kAudioObjectPropertyScopeInput))
    var sum: Double = 0
    var count = 0
    probe.withUnsafeMutableBufferPointer { buffer in
        if let base = buffer.baseAddress {
            ring.read(into: base, frames: frames, dstChannels: channels)
            for index in 0..<(frames * channels) {
                let value = Double(base[index])
                sum += value * value
                count += 1
            }
        }
    }
    let rms = count > 0 ? (sum / Double(count)).squareRoot() : 0
    if json {
        print(jsonString(["ok": true, "device": deviceName(input), "rms": rms]))
    } else {
        print("Captured 1s from \(deviceName(input)); RMS level \(String(format: "%.5f", rms)).")
    }
}

func nominalSampleRate(_ id: AudioDeviceID) -> Double {
    var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
    var rate: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else {
        return 48_000
    }
    return rate > 0 ? rate : 48_000
}

final class LevelMeter {
    private let lock = NSLock()
    private var sum: Double = 0
    private var count: Int = 0
    private var peak: Float = 0
    func add(_ value: Float) {
        lock.lock()
        sum += Double(value) * Double(value)
        count += 1
        let magnitude = abs(value)
        if magnitude > peak { peak = magnitude }
        lock.unlock()
    }
    func snapshot() -> (rms: Double, peak: Float, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let rms = count > 0 ? (sum / Double(count)).squareRoot() : 0
        return (rms, peak, count)
    }
}

func commandLoopback(argv: [String], json: Bool) {
    guard let name = option("--device", argv), let device = findDevice(named: name) else {
        if json { print(jsonString(["ok": false, "error": "device not found"])) } else { print("Device not found.") }
        exit(2)
    }
    let seconds = Double(option("--seconds", argv) ?? "2") ?? 2
    let frequency = Double(option("--freq", argv) ?? "440") ?? 440
    let rate = nominalSampleRate(device)
    let meter = LevelMeter()
    var phase = 0.0

    var renderProc: AudioDeviceIOProcID?
    let renderStatus = AudioDeviceCreateIOProcIDWithBlock(&renderProc, device, nil) {
        _, _, _, outputData, _ in
        let list = UnsafeMutableAudioBufferListPointer(outputData)
        let step = 2.0 * Double.pi * frequency / rate
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let destination = raw.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for frame in 0..<frames {
                let value = Float(sin(phase)) * 0.25
                phase += step
                if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }
                for channel in 0..<channels { destination[frame * channels + channel] = value }
            }
        }
    }
    var captureProc: AudioDeviceIOProcID?
    let captureStatus = AudioDeviceCreateIOProcIDWithBlock(&captureProc, device, nil) {
        _, inputData, _, _, _ in
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let source = raw.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for index in 0..<(frames * channels) { meter.add(source[index]) }
        }
    }
    guard renderStatus == noErr, captureStatus == noErr, let render = renderProc, let capture = captureProc else {
        if json { print(jsonString(["ok": false, "error": "cannot create IOProc"])) } else { print("Cannot create IOProc.") }
        exit(3)
    }
    AudioDeviceStart(device, render)
    AudioDeviceStart(device, capture)
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(device, render)
    AudioDeviceStop(device, capture)
    AudioDeviceDestroyIOProcID(device, render)
    AudioDeviceDestroyIOProcID(device, capture)

    let result = meter.snapshot()
    if json {
        print(jsonString([
            "ok": true, "device": name, "rms": result.rms,
            "peak": Double(result.peak), "samples": result.count, "sampleRate": rate,
        ]))
    } else {
        print("Loopback \(name): rms=\(String(format: "%.5f", result.rms)) peak=\(String(format: "%.5f", Double(result.peak))) samples=\(result.count) rate=\(Int(rate))")
    }
}

func commandRingtest(json: Bool) {
    let ring = RingBuffer(channels: 8, capacityFrames: 96_000)
    let frames = 480
    var source = [Float](repeating: 0.25, count: frames)
    for index in 0..<frames { source[index] = 0.25 }
    source.withUnsafeBufferPointer { buffer in
        if let base = buffer.baseAddress { ring.write(base, frames: frames, srcChannels: 1) }
    }
    var destination = [Float](repeating: 0, count: frames * 2)
    destination.withUnsafeMutableBufferPointer { buffer in
        if let base = buffer.baseAddress { ring.read(into: base, frames: frames, dstChannels: 2) }
    }
    let rms = (destination.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(destination.count)).squareRoot()
    if json {
        print(jsonString(["ok": true, "rms": rms, "expected": 0.25]))
    } else {
        print("Ring test: rms=\(String(format: "%.5f", rms)) expected=0.25000")
    }
}

func commandGraphtest(json: Bool) {
    let frames = 480
    let first = RingBuffer(channels: 8, capacityFrames: 96_000)
    let second = RingBuffer(channels: 8, capacityFrames: 96_000)
    let firstSource = [Float](repeating: 0.25, count: frames)
    let secondSource = [Float](repeating: 0.50, count: frames)
    firstSource.withUnsafeBufferPointer { buffer in
        if let base = buffer.baseAddress { first.write(base, frames: frames, srcChannels: 1) }
    }
    secondSource.withUnsafeBufferPointer { buffer in
        if let base = buffer.baseAddress { second.write(base, frames: frames, srcChannels: 1) }
    }
    var mixed = [Float](repeating: 0, count: frames * 2)
    let scratch = MixerScratch()
    mixed.withUnsafeMutableBufferPointer { buffer in
        if let base = buffer.baseAddress {
            mixRings([first, second], into: base, frames: frames, channels: 2, scratch: scratch)
        }
    }
    let mean = mixed.reduce(0.0) { $0 + Double($1) } / Double(mixed.count)
    let ok = abs(mean - 0.75) < 0.000_001
    if json {
        print(jsonString(["ok": ok, "mean": mean, "expected": 0.75]))
    } else {
        print("Graph mix test: mean=\(String(format: "%.5f", mean)) expected=0.75000")
    }
    if !ok { exit(1) }
}

var retainedWindow: NSWindow?

func processObjectIDs() -> [AudioObjectID] {
    var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject(), &address, 0, nil, &size) == noErr else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(systemObject(), &address, 0, nil, &size, &ids) == noErr else {
        return []
    }
    return ids
}

func processBundleID(_ id: AudioObjectID) -> String {
    var address = propertyAddress(kAudioProcessPropertyBundleID)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return value as String
}

func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
    var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pidValue = pid
    var objectID = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        systemObject(), &address, UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &objectID
    )
    return status == noErr && objectID != 0 ? objectID : nil
}

func processObjectID(forBundleID bundle: String) -> AudioObjectID? {
    processObjectIDs().first { processBundleID($0) == bundle }
}

func processPID(_ id: AudioObjectID) -> Int32 {
    var address = propertyAddress(kAudioProcessPropertyPID)
    var pid: Int32 = 0
    var size = UInt32(MemoryLayout<Int32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr else { return 0 }
    return pid
}

func processIsRunningOutput(_ id: AudioObjectID) -> Bool {
    var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
    return value != 0
}

func processIsRunningInput(_ id: AudioObjectID) -> Bool {
    var address = propertyAddress(kAudioProcessPropertyIsRunningInput)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
    return value != 0
}

func processDevices(_ id: AudioObjectID) -> [AudioDeviceID] {
    var address = propertyAddress(kAudioProcessPropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func commandProcesses(json: Bool) {
    var rows: [[String: Any]] = []
    for id in processObjectIDs() {
        let bundle = processBundleID(id)
        let running = processIsRunningOutput(id)
        if bundle.isEmpty && !running { continue }
        rows.append([
            "bundleID": bundle,
            "pid": Int(processPID(id)),
            "objectID": Int(id),
            "outputActive": running,
            "inputActive": processIsRunningInput(id),
            "devices": processDevices(id).map { deviceName($0) },
        ])
    }
    rows.sort { ($0["outputActive"] as? Bool ?? false) && !($1["outputActive"] as? Bool ?? false) }
    if json {
        print(jsonString(["ok": true, "processes": rows]))
    } else {
        for row in rows {
            let out = (row["outputActive"] as? Bool ?? false) ? "OUT" : "   "
            let inp = (row["inputActive"] as? Bool ?? false) ? "IN" : "  "
            let devices = (row["devices"] as? [String] ?? []).joined(separator: ",")
            print("\(out) \(inp)  \(row["bundleID"] ?? "")  pid=\(row["pid"] ?? 0)  [\(devices)]")
        }
    }
}

func tapUID(_ tapID: AudioObjectID) -> String {
    var address = propertyAddress(kAudioTapPropertyUID)
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &uid) {
        AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return uid as String
}

func createProcessTap(processObjects: [AudioObjectID], mute: Bool) -> AudioObjectID? {
    let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
    description.name = "Codex Call Tap"
    description.uuid = UUID()
    description.muteBehavior = CATapMuteBehavior(rawValue: mute ? 1 : 0) ?? .unmuted
    description.isPrivate = true
    var tapID = AudioObjectID(0)
    let status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == noErr, tapID != 0 else { return nil }
    return tapID
}

func createTapAggregate(tapUIDString: String, clockDeviceUID: String) -> AudioObjectID? {
    var description: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Codex Call Tap",
        kAudioAggregateDeviceUIDKey: "com.codexcall.tap.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [
            [
                kAudioSubTapUIDKey: tapUIDString,
                kAudioSubTapDriftCompensationKey: true,
            ]
        ],
    ]
    if !clockDeviceUID.isEmpty {
        description[kAudioAggregateDeviceMainSubDeviceKey] = clockDeviceUID
        description[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: clockDeviceUID]]
    }
    var aggregateID = AudioObjectID(0)
    let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
    guard status == noErr, aggregateID != 0 else { return nil }
    return aggregateID
}

func commandTap(argv: [String], json: Bool) {
    let seconds = Double(option("--seconds", argv) ?? "3") ?? 3
    var processObject: AudioObjectID?
    if let pidString = option("--pid", argv), let pid = pid_t(pidString) {
        processObject = processObjectID(forPID: pid)
    } else if let bundle = option("--bundle", argv) {
        processObject = processObjectID(forBundleID: bundle)
    } else if let name = option("--process", argv) {
        processObject = processObjectIDs().first { processBundleID($0).contains(name) }
    }

    guard let target = processObject else {
        let message = "Target process not found. Pass --pid, --bundle, or --process."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(2)
    }

    let mute = !argv.contains("--unmuted")
    guard let tapID = createProcessTap(processObjects: [target], mute: mute) else {
        let message = "Failed to create process tap (needs Audio Recording permission)."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(3)
    }
    let clockUID = clockDeviceUID(fallback: deviceUID(defaultOutput()))
    let uid = tapUID(tapID)
    guard !uid.isEmpty, let aggregate = createTapAggregate(tapUIDString: uid, clockDeviceUID: clockUID) else {
        AudioHardwareDestroyProcessTap(tapID)
        let message = "Failed to create tap aggregate device."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(3)
    }

    let ring = RingBuffer(channels: 8, capacityFrames: 96_000)
    let captureScratch = Scratch()
    let meterBox = LevelMeter()

    var captureProc: AudioDeviceIOProcID?
    let captureStatus = AudioDeviceCreateIOProcIDWithBlock(&captureProc, aggregate, nil) {
        _, inputData, _, _, _ in
        inputToRing(inputData, ring: ring, scratch: captureScratch)
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let raw = buffer.mData, channels > 0 else { continue }
            let source = raw.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for index in 0..<(frames * channels) { meterBox.add(source[index]) }
        }
    }

    var renderProc: AudioDeviceIOProcID?
    var targetDevice: AudioDeviceID?
    if let toName = option("--to", argv), let device = findDevice(named: toName) {
        targetDevice = device
        let renderScratch = Scratch()
        let renderStatus = AudioDeviceCreateIOProcIDWithBlock(&renderProc, device, nil) {
            _, _, _, outputData, _ in
            ringToOutput(outputData, ring: ring, scratch: renderScratch)
        }
        if renderStatus == noErr, let proc = renderProc { AudioDeviceStart(device, proc) }
    }

    guard captureStatus == noErr, let capture = captureProc else {
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tapID)
        if json { print(jsonString(["ok": false, "error": "cannot capture tap"])) } else { print("Cannot capture tap.") }
        exit(3)
    }
    AudioDeviceStart(aggregate, capture)
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(aggregate, capture)
    AudioDeviceDestroyIOProcID(aggregate, capture)
    if let device = targetDevice, let proc = renderProc {
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
    }
    AudioHardwareDestroyAggregateDevice(aggregate)
    AudioHardwareDestroyProcessTap(tapID)

    let result = meterBox.snapshot()
    if json {
        print(jsonString([
            "ok": true, "rms": result.rms, "peak": Double(result.peak), "samples": result.count,
        ]))
    } else {
        print("Tap: rms=\(String(format: "%.5f", result.rms)) peak=\(String(format: "%.5f", Double(result.peak))) samples=\(result.count)")
    }
}


func commandTapCall(argv: [String], json: Bool) {
    let toName = option("--to", argv) ?? virtualRXName
    guard let toDevice = findDevice(named: toName) else {
        if json { print(jsonString(["ok": false, "error": "target device not found"])) }
        else { print("tap-call: target device not found") }
        exit(2)
    }
    let mute = !argv.contains("--unmuted")

    var processes: [AudioObjectID] = []
    // Background telephony services can exist with no live call. Wait for the
    // Phone/FaceTime process so the tap cannot bind to an idle service set.
    for _ in 0..<300 {
        if callUIAppRunning() {
            processes = callAppProcessObjects()
            if !processes.isEmpty { break }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard !processes.isEmpty else {
        if json { print(jsonString(["ok": false, "error": "no active call app process"])) }
        else { print("tap-call: no active call app process") }
        exit(3)
    }
    guard let tap = createProcessTap(processObjects: processes, mute: mute) else {
        if json { print(jsonString(["ok": false, "error": "tap create failed"])) }
        else { print("tap-call: process tap creation failed") }
        exit(3)
    }
    let clockUID = clockDeviceUID(fallback: deviceUID(defaultOutput()))
    let uid = tapUID(tap)
    guard !uid.isEmpty,
          let aggregate = createTapAggregate(tapUIDString: uid, clockDeviceUID: clockUID) else {
        AudioHardwareDestroyProcessTap(tap)
        if json { print(jsonString(["ok": false, "error": "aggregate failed"])) }
        else { print("tap-call: aggregate device creation failed") }
        exit(3)
    }

    let ring = RingBuffer(channels: 8, capacityFrames: 96_000)
    let captureScratch = Scratch()
    let renderScratch = Scratch()

    var captureProc: AudioDeviceIOProcID?
    let captureStatus = AudioDeviceCreateIOProcIDWithBlock(&captureProc, aggregate, nil) {
        _, inputData, _, _, _ in
        inputToRing(inputData, ring: ring, scratch: captureScratch)
    }
    var renderProc: AudioDeviceIOProcID?
    let renderStatus = AudioDeviceCreateIOProcIDWithBlock(&renderProc, toDevice, nil) {
        _, _, _, outputData, _ in
        ringToOutput(outputData, ring: ring, scratch: renderScratch)
    }
    guard captureStatus == noErr, renderStatus == noErr, let cap = captureProc, let ren = renderProc else {
        if let proc = captureProc { AudioDeviceDestroyIOProcID(aggregate, proc) }
        if let proc = renderProc { AudioDeviceDestroyIOProcID(toDevice, proc) }
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tap)
        if json { print(jsonString(["ok": false, "error": "i/o setup failed"])) }
        else { print("tap-call: audio I/O setup failed") }
        exit(3)
    }
    let renderStart = AudioDeviceStart(toDevice, ren)
    let captureStart = AudioDeviceStart(aggregate, cap)
    guard renderStart == noErr, captureStart == noErr else {
        if captureStart == noErr { AudioDeviceStop(aggregate, cap) }
        if renderStart == noErr { AudioDeviceStop(toDevice, ren) }
        AudioDeviceDestroyIOProcID(toDevice, ren)
        AudioDeviceDestroyIOProcID(aggregate, cap)
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tap)
        if json { print(jsonString(["ok": false, "error": "i/o start failed"])) }
        else { print("tap-call: audio I/O start failed") }
        exit(3)
    }

    try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    try? "\(getpid())\n".write(to: callTapReadyURL, atomically: true, encoding: .utf8)
    if json {
        print(jsonString([
            "ok": true,
            "to": toName,
            "processes": processes.map { processBundleID($0) },
        ]))
    } else {
        print("tap-call: routing remote audio to \(toName)")
    }
    fflush(stdout)

    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "codexcall.tapcall")
    var sources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
        source.setEventHandler { semaphore.signal() }
        source.resume()
        sources.append(source)
    }
    _ = sources
    semaphore.wait()

    try? FileManager.default.removeItem(at: callTapReadyURL)
    AudioDeviceStop(toDevice, ren)
    AudioDeviceStop(aggregate, cap)
    AudioDeviceDestroyIOProcID(toDevice, ren)
    AudioDeviceDestroyIOProcID(aggregate, cap)
    AudioHardwareDestroyAggregateDevice(aggregate)
    AudioHardwareDestroyProcessTap(tap)
}

func commandRequestMic(json: Bool) {
    func report(_ status: String) {
        try? status.write(toFile: "/tmp/codexcall-mic-status.txt", atomically: true, encoding: .utf8)
        if json { print(jsonString(["ok": status == "authorized", "status": status])) }
        else { print("Microphone permission: \(status)") }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Codex Call Helper"
    window.center()
    window.makeKeyAndOrderFront(nil)
    retainedWindow = window
    app.activate(ignoringOtherApps: true)

    func finish(_ status: String) {
        report(status)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.terminate(nil) }
    }

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        finish("authorized")
    case .denied:
        finish("denied")
    case .restricted:
        finish("restricted")
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { result in
            DispatchQueue.main.async { finish(result ? "authorized" : "denied") }
        }
    @unknown default:
        finish("unknown")
    }

    app.run()
}

func commandSetDefault(argv: [String], json: Bool) {
    var result: [String: Any] = ["ok": true]
    if let name = option("--input", argv), let id = findDevice(named: name) {
        setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id)
        result["input"] = name
    }
    if let name = option("--output", argv), let id = findDevice(named: name) {
        setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id)
        setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, id)
        result["output"] = name
    }
    result["defaultInput"] = deviceName(defaultInput())
    result["defaultOutput"] = deviceName(defaultOutput())
    if json { print(jsonString(result)) } else {
        print("Default input: \(deviceName(defaultInput()))")
        print("Default output: \(deviceName(defaultOutput()))")
    }
}

func sanitizePhoneNumber(_ raw: String) -> String? {
    var output = ""
    for character in raw {
        if character.isNumber || character == "+" {
            output.append(character)
        } else if character == " " || character == "-" || character == "(" || character == ")" {
            continue
        } else if character == "." {
            continue
        } else {
            return nil
        }
    }
    let digits = output.filter { $0.isNumber }
    guard digits.count >= 3 else { return nil }
    return output
}

@discardableResult
func initiateCall(number: String) -> Bool {
    guard let url = URL(string: "tel:\(number)") else { return false }
    return NSWorkspace.shared.open(url)
}

func terminateCallApplications(timeout: TimeInterval = 3) -> Bool {
    let applications = NSWorkspace.shared.runningApplications.filter {
        guard let bundleID = $0.bundleIdentifier else { return false }
        return callUIBundleIDs.contains(bundleID)
    }
    guard !applications.isEmpty else { return true }
    for application in applications { application.terminate() }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if applications.allSatisfy({ $0.isTerminated }) { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return applications.allSatisfy { $0.isTerminated }
}

func enterCallModeDefaults() {
    guard let config = loadConfig(),
          let tx = findDevice(named: config.virtualTXName) else { return }
    setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, tx)
    setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)
    setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, tx)
}

func enterNormalModeDefaults() {
    guard let config = loadConfig(),
          let rx = findDevice(named: config.virtualRXName),
          let tx = findDevice(named: config.virtualTXName) else { return }
    setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, rx)
    setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, tx)
    setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, tx)
}

func commandCall(argv: [String], json: Bool) {
    let action = argv.count > 1 && !argv[1].hasPrefix("--") ? argv[1] : ""
    switch action {
    case "start":
        guard findDevice(named: virtualClockName) != nil else {
            let message = "Codex Virtual Clock is missing; reinstall Codex Call before placing a call."
            if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
            exit(2)
        }
        guard let rawNumber = option("--number", argv), let number = sanitizePhoneNumber(rawNumber) else {
            let message = "A valid phone number is required."
            if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
            exit(64)
        }
        guard let goal = option("--goal", argv), !goal.isEmpty else {
            let message = "A call goal is required."
            if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
            exit(64)
        }
        saveState(CallState(mode: "call", state: "STARTING_CALL", goal: goal, number: number))
        enterCallModeDefaults()
        let started = initiateCall(number: number)
        saveState(CallState(
            mode: started ? "call" : "normal",
            state: started ? "STARTING_CALL" : "ERROR",
            goal: goal,
            number: number
        ))
        if !started { enterNormalModeDefaults() }
        if json {
            print(jsonString(["ok": started, "state": started ? "STARTING_CALL" : "ERROR", "number": number, "goal": goal]))
        } else if started {
            print("Calling \(number).\nGoal: \(goal)\nState: STARTING_CALL")
        } else {
            print("Failed to initiate call to \(number).")
        }
    case "end":
        var ending = loadState()
        ending.state = "ENDING_CALL"
        saveState(ending)
        let hungUp = terminateCallApplications()
        var state = loadState()
        state.mode = "normal"
        state.state = "NORMAL"
        state.goal = nil
        state.number = nil
        saveState(state)
        enterNormalModeDefaults()
        if json {
            print(jsonString(["ok": true, "state": "NORMAL", "hungUp": hungUp]))
        } else if hungUp {
            print("Call ended. Normal mode restored.")
        } else {
            print("Normal mode restored, but macOS did not confirm that the call app closed.")
        }
    default:
        let message = "call requires 'start' or 'end'."
        if json { print(jsonString(["ok": false, "error": message])) } else { print(message) }
        exit(64)
    }
}

let argv = Array(CommandLine.arguments.dropFirst())
let json = argv.contains("--json")
let command = argv.first ?? "audio-status"

switch command {
case "devices": commandDevices(json: json)
case "status": commandStatus(json: json)
case "audio-status": commandAudioStatus(json: json)
case "setup": commandSetup(argv: argv, json: json)
case "restore": commandRestore(json: json)
case "run": commandRun(argv: argv, json: json)
case "route": commandRoute(argv: argv, json: json)
case "doctor": commandDoctor(json: json)
case "selftest": commandSelftest(json: json)
case "set-default": commandSetDefault(argv: argv, json: json)
case "loopback": commandLoopback(argv: argv, json: json)
case "ringtest": commandRingtest(json: json)
case "graphtest": commandGraphtest(json: json)
case "request-mic": commandRequestMic(json: json)
case "tap": commandTap(argv: argv, json: json)
case "tap-call": commandTapCall(argv: argv, json: json)
case "processes": commandProcesses(json: json)
case "call": commandCall(argv: argv, json: json)
case "help", "--help", "-h":
    print("""
    codex-call-helper commands:
      devices            list audio devices
      status             report call state and helper status
      audio-status       full audio routing diagnostics
      setup              configure virtual routing and system defaults
      restore            restore original default audio devices
      run                run the routing engine (long running)
      route normal|call  switch routing mode
      doctor             run diagnostics
      selftest           capture a short sample from the physical microphone
      call start|end     call lifecycle (milestones 2/3)
    """)
default:
    if json {
        print(jsonString(["ok": false, "error": "unknown command: \(command)"]))
    } else {
        print("Unknown command: \(command)")
    }
    exit(64)
}
