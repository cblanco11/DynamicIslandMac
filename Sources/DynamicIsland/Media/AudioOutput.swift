import CoreAudio
import Foundation

/// The current audio output device.
///
/// The reference design puts an output-device control where a repeat button
/// would otherwise go. MediaRemote knows nothing about routing, but CoreAudio
/// does, so this is real information rather than a decorative icon: the glyph
/// reflects what sound is actually coming out of.
enum AudioOutput {

    struct Device: Equatable {
        var name: String
        /// SF Symbol matching the device's transport.
        var symbol: String
    }

    static func current() -> Device {
        guard let id = defaultOutputDeviceID() else {
            return Device(name: "Output", symbol: "speaker.wave.2.fill")
        }
        return Device(name: name(of: id) ?? "Output", symbol: symbol(for: transportType(of: id)))
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // CoreAudio hands back a +1 CFString, so it goes through Unmanaged
        // rather than letting Swift bridge a raw pointer to an Optional<CFString>.
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return transport
    }

    private static func symbol(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:            "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:        "headphones"
        case kAudioDeviceTransportTypeUSB:                "headphones"
        case kAudioDeviceTransportTypeAirPlay:            "airplayaudio"
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:        "tv"
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate:          "waveform"
        default:                                          "speaker.wave.2.fill"
        }
    }
}
