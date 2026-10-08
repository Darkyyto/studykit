import AppKit
import CoreAudio
import IOKit.ps
import Observation
import SwiftUI

@MainActor
@Observable
final class DeviceWatcher {
    struct Notice: Equatable {
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
        let stamp = Date.now
    }

    static let audioKey = "noticesAudioDevices"
    static let capsLockKey = "noticesCapsLock"
    static let batteryKey = "noticesLowBattery"
    static let focusKey = "noticesFocusModes"

    private(set) var notice: Notice?

    @ObservationIgnored private var outputs: [String: String] = [:]
    @ObservationIgnored private var capsLock = false
    @ObservationIgnored private var batteryWarned: Int?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var focusLog: FocusLog?
    @ObservationIgnored private var lastFocus: (isOn: Bool, date: Date)?

    private static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        outputs = Self.bluetoothOutputs()
        capsLock = Self.isCapsLockOn()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCapsLock() }
        }
        timer?.tolerance = 0.1

        for (name, isOn) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
            observers.append(DistributedObserver(name) { [weak self] note in
                let mode = Self.focusMode(from: note)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.focusChanged(mode: mode, isOn: isOn) }
                }
            })
        }

        focusLog = FocusLog { [weak self] identifier, isOn in
            let mode = Self.focusMode(identifier: identifier)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.focusChanged(mode: mode, isOn: isOn) }
            }
        }
        syncFocusLog()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.syncFocusLog() }
            }
        })

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let watcher = Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.batteryChanged() }
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func post(_ title: String, detail: String, symbol: String, tint: Color) {
        notice = Notice(title: title, detail: detail, symbol: symbol, tint: tint)
    }

    private func devicesChanged() {
        let current = Self.bluetoothOutputs()
        defer { outputs = current }
        guard Self.isOn(Self.audioKey) else { return }
        if let added = current.keys.first(where: { outputs[$0] == nil }), let name = current[added] {
            post("Connected", detail: Self.shortName(name), symbol: Self.symbol(for: name), tint: Color(hex: 0x34C759))
        } else if let removed = outputs.keys.first(where: { current[$0] == nil }), let name = outputs[removed] {
            post("Disconnected", detail: Self.shortName(name), symbol: Self.symbol(for: name), tint: Color(white: 0.7))
        }
    }

    @ObservationIgnored private var focusLogRunning = false

    private func syncFocusLog() {
        let wanted = Self.isOn(Self.focusKey)
        guard wanted != focusLogRunning else { return }
        focusLogRunning = wanted
        if wanted {
            focusLog?.start()
        } else {
            focusLog?.stop()
        }
    }

    private func focusChanged(mode: FocusMode, isOn: Bool) {
        guard Self.isOn(Self.focusKey) else { return }
        if let lastFocus, lastFocus.isOn == isOn, Date.now.timeIntervalSince(lastFocus.date) < 2 { return }
        lastFocus = (isOn, .now)
        post(mode.title, detail: isOn ? "On" : "Off", symbol: mode.symbol, tint: isOn ? Color(hex: 0x7D7AFF) : Color(white: 0.7))
    }

    enum FocusMode: Sendable {
        case doNotDisturb, sleep, work, personal, driving, fitness, gaming, mindfulness, reading, other

        var title: String {
            switch self {
            case .doNotDisturb: "Do Not Disturb"
            case .sleep: "Sleep"
            case .work: "Work"
            case .personal: "Personal"
            case .driving: "Driving"
            case .fitness: "Fitness"
            case .gaming: "Gaming"
            case .mindfulness: "Mindfulness"
            case .reading: "Reading"
            case .other: "Focus"
            }
        }

        var symbol: String {
            switch self {
            case .doNotDisturb: "moon.fill"
            case .sleep: "bed.double.fill"
            case .work: "briefcase.fill"
            case .personal: "person.fill"
            case .driving: "car.fill"
            case .fitness: "figure.run"
            case .gaming: "gamecontroller.fill"
            case .mindfulness: "leaf.fill"
            case .reading: "book.fill"
            case .other: "moon.fill"
            }
        }
    }

    private nonisolated static func focusMode(identifier: String) -> FocusMode {
        let value = identifier.lowercased()
        let table: [(String, FocusMode)] = [
            ("sleep", .sleep), ("work", .work), ("personal", .personal), ("driving", .driving),
            ("fitness", .fitness), ("workout", .fitness), ("gaming", .gaming), ("mindful", .mindfulness),
            ("reading", .reading), ("donotdisturb.mode.default", .doNotDisturb),
        ]
        return table.first { value.contains($0.0) }?.1 ?? (value.isEmpty ? .doNotDisturb : .other)
    }

    private nonisolated static func focusMode(from note: Notification) -> FocusMode {
        var texts: [String] = []
        func collect(_ value: Any?) {
            switch value {
            case let string as String: texts.append(string.lowercased())
            case let dictionary as [AnyHashable: Any]: dictionary.values.forEach(collect)
            case let array as [Any]: array.forEach(collect)
            default: break
            }
        }
        collect(note.userInfo)
        collect(note.object)
        let joined = texts.joined(separator: " ")
        let table: [(String, FocusMode)] = [
            ("sleep", .sleep), ("work", .work), ("personal", .personal), ("driving", .driving),
            ("fitness", .fitness), ("gaming", .gaming), ("mindful", .mindfulness), ("reading", .reading),
            ("donotdisturb", .doNotDisturb), ("do not disturb", .doNotDisturb),
        ]
        return table.first { joined.contains($0.0) }?.1 ?? .other
    }

    private func checkCapsLock() {
        let on = Self.isCapsLockOn()
        guard on != capsLock else { return }
        capsLock = on
        guard Self.isOn(Self.capsLockKey) else { return }
        post("Caps Lock", detail: on ? "On" : "Off", symbol: on ? "capslock.fill" : "capslock", tint: on ? Color(hex: 0x34C759) : Color(white: 0.7))
    }

    private func batteryChanged() {
        guard let state = Self.batteryState() else { return }
        if state.charging || state.level > 20 {
            batteryWarned = nil
            return
        }
        let threshold = state.level <= 10 ? 10 : 20
        if let warned = batteryWarned, warned <= threshold { return }
        batteryWarned = threshold
        guard Self.isOn(Self.batteryKey) else { return }
        post("Low battery", detail: "\(state.level)%", symbol: threshold == 10 ? "battery.0percent" : "battery.25percent", tint: Color(hex: 0xFF5A4E))
    }

    static func shortName(_ name: String) -> String {
        let lower = name.lowercased()
        for model in ["AirPods Max", "AirPods Pro", "AirPods"] where lower.contains(model.lowercased()) {
            return model
        }
        return name
    }

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("speaker") || lower.contains("homepod") || lower.contains("boom") || lower.contains("jbl") { return "hifispeaker.fill" }
        return "headphones"
    }

    private static func isCapsLockOn() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }

    static func batteryState() -> (level: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (Int((Double(current) / Double(maximum) * 100).rounded()), charging)
        }
        return nil
    }

    static func bluetoothOutputs() -> [String: String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [:] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [:] }
        var result: [String: String] = [:]
        for device in devices {
            guard isBluetooth(device), hasOutput(device), let name = name(of: device) else { continue }
            result[uid(of: device) ?? name] = name
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.value).inserted }
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of device: AudioObjectID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    private static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
