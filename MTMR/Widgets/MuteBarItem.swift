//
//  MuteBarItem.swift
//  Stripe
//
//  A mute toggle that talks to CoreAudio directly (no Accessibility permission
//  needed, unlike simulating the mute key) and shows the current state: a
//  highlighted "speaker.slash" while muted. It follows changes made anywhere
//  (keyboard, menu bar, other apps) and switches of the output device.
//

import Cocoa
import CoreAudio

class MuteBarItem: CustomButtonTouchBarItem, TearDownable {
    private var device = AudioObjectID(0)
    private lazy var muteListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.refresh() }
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.outputDeviceChanged() }
    }

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.toggle() })

        var defaultDevice = MuteBarItem.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, deviceListener)
        outputDeviceChanged()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func tearDown() {
        var defaultDevice = MuteBarItem.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, deviceListener)
        var mute = MuteBarItem.address(kAudioDevicePropertyMute)
        AudioObjectRemovePropertyListenerBlock(device, &mute, .main, muteListener)
    }

    // MARK: State

    private var isMuted: Bool {
        var address = MuteBarItem.address(kAudioDevicePropertyMute)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func toggle() {
        var address = MuteBarItem.address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &address),
           AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue {
            var value: UInt32 = isMuted ? 0 : 1
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else {
            // Some outputs (e.g. HDMI) have no mute control; fall back to the mute key.
            HIDPostAuxKey(NX_KEYTYPE_MUTE)
        }
        refresh()
    }

    private func refresh() {
        let muted = isMuted
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            accessibilityDescription: muted ? "Unmute" : "Mute")?.withSymbolConfiguration(config)
        image?.isTemplate = true
        self.image = image
        // Lit up while muted, like a toggled Control Strip button.
        backgroundColor = NSColor(white: 1, alpha: muted ? 0.62 : 0.32)
    }

    private func outputDeviceChanged() {
        var mute = MuteBarItem.address(kAudioDevicePropertyMute)
        AudioObjectRemovePropertyListenerBlock(device, &mute, .main, muteListener)
        device = MuteBarItem.defaultOutputDevice
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, muteListener)
        refresh()
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var defaultOutputDevice: AudioObjectID {
        var address = self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
