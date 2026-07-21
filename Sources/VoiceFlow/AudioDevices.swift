import CoreAudio
import Foundation

struct AudioInputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// CoreAudio enumeration of input-capable devices for the «Микрофон» menu.
enum AudioDevices {
    static func inputs() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }

        return ids.compactMap { id in
            guard hasInput(id), let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    /// The empirical cure for the system-wide «микрофон умер» wedge: writing
    /// the input volume (what the slider in System Settings does) makes
    /// coreaudiod reconfigure the device and audio flows again. Nudges the
    /// volume and restores it, so the user-visible level doesn't change.
    static func kickInput(uid: String?) -> Bool {
        guard let id = resolveInput(uid: uid) else { return false }
        var kicked = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr
            else { continue }
            var nudged: Float32 = volume > 0.5 ? volume - 0.02 : volume + 0.02
            guard AudioObjectSetPropertyData(id, &address, 0, nil, size, &nudged) == noErr
            else { continue }
            var original = volume
            AudioObjectSetPropertyData(id, &address, 0, nil, size, &original)
            DebugLog.log("mic: kicked device \(id) element \(element), volume \(volume)")
            kicked = true
        }
        return kicked
    }

    private static func resolveInput(uid: String?) -> AudioDeviceID? {
        if let uid, let device = inputs().first(where: { $0.uid == uid }) {
            return device.id
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
            id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private static func stringProperty(
        _ id: AudioDeviceID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let cf = value?.takeRetainedValue() else { return nil }
        return cf as String
    }
}
