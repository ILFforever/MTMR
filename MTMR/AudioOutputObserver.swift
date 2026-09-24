//
//  AudioOutputObserver.swift
//  Stripe
//
//  Watches the default output device's volume and mute state, following
//  changes from anywhere (keys, menu bar, other apps) and switches of output
//  device, and calls back on the main thread.
//

import AudioToolbox // kAudioHardwareServiceDeviceProperty_VirtualMainVolume
import CoreAudio
import Foundation

final class AudioOutputObserver {
    private(set) var volume: Float = 0
    private(set) var isMuted = false

    private let onChange: () -> Void
    private var device = AudioObjectID(0)

    // Stored so exactly these blocks can be removed; they hold the observer weakly.
    private lazy var propertyListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.read()
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attachToDefaultDevice()
    }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        var defaultDevice = AudioOutputObserver.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, deviceListener)
        attachToDefaultDevice()
    }

    func stop() {
        var defaultDevice = AudioOutputObserver.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, deviceListener)
        detachFromDevice()
    }

    private static let watched = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    private func attachToDefaultDevice() {
        detachFromDevice()
        var address = AudioOutputObserver.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        for selector in AudioOutputObserver.watched {
            var property = AudioOutputObserver.address(selector)
            if AudioObjectHasProperty(device, &property) {
                AudioObjectAddPropertyListenerBlock(device, &property, .main, propertyListener)
            }
        }
        read()
    }

    private func detachFromDevice() {
        guard device != 0 else { return }
        for selector in AudioOutputObserver.watched {
            var property = AudioOutputObserver.address(selector)
            AudioObjectRemovePropertyListenerBlock(device, &property, .main, propertyListener)
        }
    }

    private func read() {
        var volumeAddress = AudioOutputObserver.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &volumeAddress),
           AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr {
            volume = value
        }

        var muteAddress = AudioOutputObserver.address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        isMuted = AudioObjectHasProperty(device, &muteAddress)
            && AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted) == noErr
            && muted != 0

        onChange()
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The speaker symbol macOS uses for this level: slash when muted, then 0–3 waves.
    var speakerSymbol: String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
