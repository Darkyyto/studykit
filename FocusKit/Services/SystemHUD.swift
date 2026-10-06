import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import Observation

@MainActor
@Observable
final class SystemHUD {
    enum Kind: Equatable {
        case volume
        case brightness
        case battery
    }

    struct Event: Equatable {
        let kind: Kind
        let value: Double
        let isMuted: Bool
        let isCharging: Bool
        let stamp: Date
    }

    private(set) var event: Event?

    @ObservationIgnored private var outputDevice = AudioObjectID(0)
    @ObservationIgnored private var lastVolume: Double?
    @ObservationIgnored private var lastMuted: Bool?
    @ObservationIgnored private var lastBrightness: Double?
    @ObservationIgnored private var lastCharging: Bool?
    @ObservationIgnored private var brightnessTimer: Timer?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private let readBrightness: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32)?
    @ObservationIgnored private let writeBrightness: (@convention(c) (UInt32, Float) -> Int32)?
    @ObservationIgnored private var keyTap: CFMachPort?
    @ObservationIgnored private var keySource: CFRunLoopSource?

    private(set) var replacesSystemIndicators = false

    static let enabledKey = "showsSystemHUD"
    static let replaceKey = "replacesSystemHUD"

    var wantsReplacement: Bool {
        UserDefaults.standard.bool(forKey: Self.replaceKey)
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            readBrightness = unsafeBitCast(symbol, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self)
            writeBrightness = dlsym(handle, "DisplayServicesSetBrightness").map {
                unsafeBitCast($0, to: (@convention(c) (UInt32, Float) -> Int32).self)
            }
        } else {
            readBrightness = nil
            writeBrightness = nil
        }
    }

    func start() {
        observeDefaultDevice()
        bindVolume()
        lastBrightness = brightness()
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }
        brightnessTimer?.tolerance = 0.1
        lastCharging = Self.batteryState()?.charging
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let hud = Unmanaged<SystemHUD>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hud.powerChanged() }
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        updateKeyTap()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateKeyTap() }
        }
    }

    func updateKeyTap(prompt: Bool = false) {
        guard wantsReplacement, isEnabled else {
            stopKeyTap()
            return
        }
        if prompt, !Self.hasAccessibility {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard keyTap == nil, Self.hasAccessibility else {
            replacesSystemIndicators = keyTap != nil
            return
        }
        let mask = CGEventMask(1 << 14)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let hud = Unmanaged<SystemHUD>.fromOpaque(context).takeUnretainedValue()
            nonisolated(unsafe) let incoming = event
            let swallow = MainActor.assumeIsolated { hud.handle(type: type, event: incoming) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context) else {
            replacesSystemIndicators = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keySource = source
        replacesSystemIndicators = true
    }

    private func stopKeyTap() {
        if let tap = keyTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = keySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        keyTap = nil
        keySource = nil
        replacesSystemIndicators = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return false
        }
        guard let system = NSEvent(cgEvent: event), system.type == .systemDefined, system.subtype.rawValue == 8 else {
            return false
        }
        let code = (system.data1 & 0xFFFF0000) >> 16
        let isDown = ((system.data1 & 0xFF00) >> 8) == 0xA
        let fine = system.modifierFlags.contains([.option, .shift])
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch code {
        case 0, 1:
            guard let current = volume() else { return false }
            if isDown {
                let target = min(1, max(0, current + (code == 0 ? step : -step)))
                setMuted(false)
                setVolume(target)
                publish(.volume, value: target)
                lastVolume = target
                lastMuted = false
            }
            return true
        case 7:
            guard volume() != nil else { return false }
            if isDown {
                let muted = !(self.muted() ?? false)
                setMuted(muted)
                publish(.volume, value: muted ? 0 : volume() ?? 0, muted: muted)
                lastMuted = muted
            }
            return true
        case 2, 3:
            guard let writeBrightness, let current = brightness() else { return false }
            if isDown {
                let target = min(1, max(0, current + (code == 2 ? step : -step)))
                _ = writeBrightness(CGMainDisplayID(), Float(target))
                publish(.brightness, value: target)
                lastBrightness = target
            }
            return true
        default:
            return false
        }
    }

    private func setVolume(_ value: Double) {
        var level = Float32(value)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(outputDevice, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
    }

    private func setMuted(_ muted: Bool) {
        var value = UInt32(muted ? 1 : 0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(outputDevice, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func publish(_ kind: Kind, value: Double, muted: Bool = false, charging: Bool = false) {
        guard isEnabled else { return }
        event = Event(kind: kind, value: min(1, max(0, value)), isMuted: muted, isCharging: charging, stamp: .now)
    }

    private func observeDefaultDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindVolume() }
        }
    }

    private func bindVolume() {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != outputDevice else { return }
        outputDevice = device
        lastVolume = volume()
        lastMuted = muted()
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(device, &property, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.volumeChanged(on: device) }
            }
        }
    }

    private func volumeChanged(on device: AudioObjectID) {
        guard device == outputDevice, let volume = volume() else { return }
        let isMuted = muted() ?? false
        defer {
            lastVolume = volume
            lastMuted = isMuted
        }
        guard abs(volume - (lastVolume ?? -1)) > 0.001 || isMuted != lastMuted else { return }
        publish(.volume, value: isMuted ? 0 : volume, muted: isMuted)
    }

    private func volume() -> Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    private func muted() -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func brightness() -> Double? {
        guard let readBrightness else { return nil }
        var value = Float(0)
        guard readBrightness(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    private func pollBrightness() {
        guard let value = brightness() else { return }
        defer { lastBrightness = value }
        guard let last = lastBrightness, abs(value - last) > 0.004 else { return }
        publish(.brightness, value: value)
    }

    private func powerChanged() {
        guard let state = Self.batteryState() else { return }
        defer { lastCharging = state.charging }
        guard let last = lastCharging, state.charging != last else { return }
        publish(.battery, value: state.level, charging: state.charging)
    }

    private static func batteryState() -> (level: Double, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let plugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Double(current) / Double(maximum), plugged)
        }
        return nil
    }
}
