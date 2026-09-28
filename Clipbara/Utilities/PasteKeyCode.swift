import Carbon.HIToolbox
import CoreGraphics

/// Finds the physical key that produces "v" while Command is held.
///
/// Apps match ⌘V by the character, not the key position, so a fixed key code
/// sends ⌘. on Dvorak. Translating with Command held also covers layouts such
/// as "Dvorak - QWERTY ⌘" that switch to QWERTY only while Command is down.
enum PasteKeyCode {
    static let qwertyV = CGKeyCode(kVK_ANSI_V)

    /// Returns the first key code whose Command layer types "v", checking the
    /// QWERTY position first. Falls back to the QWERTY position.
    static func find(in layouts: [(CGKeyCode) -> String?]) -> CGKeyCode {
        for translate in layouts {
            if translate(qwertyV)?.lowercased() == "v" { return qwertyV }
            for code in 0..<CGKeyCode(128) where code != qwertyV {
                if translate(code)?.lowercased() == "v" { return code }
            }
        }
        return qwertyV
    }

    /// The key for the current keyboard layout. Input methods such as Korean
    /// may not type Latin letters, so the ASCII capable layout is tried next.
    @MainActor
    static func current() -> CGKeyCode {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        let layouts = sources.compactMap { $0.flatMap(translator(for:)) }
        return find(in: layouts)
    }

    private static func translator(for source: TISInputSource) -> ((CGKeyCode) -> String?)? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        let commandState = UInt32((cmdKey >> 8) & 0xFF)

        return { code in
            data.withUnsafeBytes { buffer -> String? in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return nil
                }
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout,
                    code,
                    UInt16(kUCKeyActionDown),
                    commandState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length)
            }
        }
    }
}
