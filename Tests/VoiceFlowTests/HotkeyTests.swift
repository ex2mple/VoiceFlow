import Foundation
import VoiceFlowCore

// NX_DEVICE* bits from IOKit/IOLLEvent.h — what macOS puts in
// NSEvent.modifierFlags.rawValue for left/right modifier keys.
private let lCtl: UInt = 0x0001
private let lShift: UInt = 0x0002
private let rShift: UInt = 0x0004
private let lCmd: UInt = 0x0008
private let rCmd: UInt = 0x0010
private let lAlt: UInt = 0x0020
private let rAlt: UInt = 0x0040
private let rCtl: UInt = 0x2000
private let fnMask: UInt = 0x0080_0000
// Device-independent bits that always accompany the device ones.
private let optionGeneric: UInt = 0x0008_0000
private let commandGeneric: UInt = 0x0010_0000

func runHotkeyTests() {
    T.run("Hotkey: keyCodes match HIToolbox kVK_ constants") {
        T.equal(Hotkey.rightOption.keyCode, 61)
        T.equal(Hotkey.leftOption.keyCode, 58)
        T.equal(Hotkey.rightCommand.keyCode, 54)
        T.equal(Hotkey.leftCommand.keyCode, 55)
        T.equal(Hotkey.rightControl.keyCode, 62)
        T.equal(Hotkey.leftControl.keyCode, 59)
        T.equal(Hotkey.rightShift.keyCode, 60)
        T.equal(Hotkey.leftShift.keyCode, 56)
        T.equal(Hotkey.fn.keyCode, 63)
    }

    T.run("Hotkey: press detection uses device-specific bit") {
        T.expect(Hotkey.rightOption.isPressed(inFlags: rAlt | optionGeneric),
                 "right option down")
        T.expect(!Hotkey.rightOption.isPressed(inFlags: 0), "right option up")
        T.expect(Hotkey.fn.isPressed(inFlags: fnMask), "fn down")
        T.expect(!Hotkey.fn.isPressed(inFlags: 0), "fn up")
    }

    T.run("Hotkey: left and right of the same modifier don't shadow each other") {
        // Right option released while LEFT option is still held: the generic
        // .option bit stays set, but the right-device bit is gone. The old
        // `.contains(.option)` check missed this release and left the
        // recording stuck.
        let leftStillHeld = lAlt | optionGeneric
        T.expect(!Hotkey.rightOption.isPressed(inFlags: leftStillHeld),
                 "right option must read as released when only left is held")
        T.expect(Hotkey.leftOption.isPressed(inFlags: leftStillHeld),
                 "left option still held")
        let bothCmd = lCmd | rCmd | commandGeneric
        T.expect(Hotkey.leftCommand.isPressed(inFlags: bothCmd), "left cmd held")
        T.expect(Hotkey.rightCommand.isPressed(inFlags: bothCmd), "right cmd held")
    }

    T.run("Hotkey: every case has a distinct keyCode and title") {
        T.equal(Set(Hotkey.allCases.map(\.keyCode)).count, Hotkey.allCases.count)
        T.equal(Set(Hotkey.allCases.map(\.title)).count, Hotkey.allCases.count)
    }

    T.run("Hotkey: stored rawValues from old versions still decode") {
        T.equal(Hotkey(rawValue: "rightOption"), .rightOption)
        T.equal(Hotkey(rawValue: "rightCommand"), .rightCommand)
    }

    T.run("HotkeySpec: storage round-trip for both kinds") {
        let mod = HotkeySpec.modifier(.leftControl)
        T.equal(HotkeySpec(storageValue: mod.storageValue), mod)
        let key = HotkeySpec.key(code: 96, name: "F5")
        T.equal(key.storageValue, "key:96:F5")
        T.equal(HotkeySpec(storageValue: "key:96:F5"), key)
        T.equal(key.keyCode, 96)
        T.equal(key.title, "F5")
    }

    T.run("HotkeySpec: legacy modifier strings decode, garbage doesn't") {
        T.equal(HotkeySpec(storageValue: "rightOption"), .modifier(.rightOption))
        T.equal(HotkeySpec(storageValue: ""), nil)
        T.equal(HotkeySpec(storageValue: "key:xx:F5"), nil)
        T.equal(HotkeySpec(storageValue: "key:96:"), nil)
        T.equal(HotkeySpec(storageValue: "мусор"), nil)
    }

    T.run("HotkeySpec: recordable keys are F-keys only") {
        T.equal(HotkeySpec.recordableKeys[96], "F5")
        T.equal(HotkeySpec.recordableKeys[122], "F1")
        T.equal(HotkeySpec.recordableKeys[111], "F12")
        T.equal(HotkeySpec.recordableKeys[0], nil)   // «a» печатает текст
        T.equal(HotkeySpec.recordableKeys[49], nil)  // пробел
        T.equal(HotkeySpec.recordableKeys[53], nil)  // Esc — отмена записи
    }

    T.run("Hotkey: keyCode lookup covers every modifier") {
        for hk in Hotkey.allCases {
            T.equal(Hotkey.byKeyCode[hk.keyCode], hk)
        }
        T.equal(Hotkey.byKeyCode[57], nil) // Caps Lock — не хоткей
    }
}
