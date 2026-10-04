import AppKit

enum ModifierKey: String, Codable, Hashable, CaseIterable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand
    case leftShift, rightShift
    case fn

    enum Kind: Int, Comparable {
        case fn, control, option, shift, command

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        var symbol: String {
            switch self {
            case .fn: "fn"
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftCommand, .rightCommand: .command
        case .leftShift, .rightShift: .shift
        case .fn: .fn
        }
    }

    var isRight: Bool {
        [.rightControl, .rightOption, .rightCommand, .rightShift].contains(self)
    }

    // Device-dependent bits from IOKit's NX_DEVICE*KEYMASK. CGEventFlags uses the same layout.
    static func active(in raw: UInt64) -> Set<ModifierKey> {
        var keys = Set<ModifierKey>()
        if raw & 0x0001 != 0 { keys.insert(.leftControl) }
        if raw & 0x2000 != 0 { keys.insert(.rightControl) }
        if raw & 0x0020 != 0 { keys.insert(.leftOption) }
        if raw & 0x0040 != 0 { keys.insert(.rightOption) }
        if raw & 0x0008 != 0 { keys.insert(.leftCommand) }
        if raw & 0x0010 != 0 { keys.insert(.rightCommand) }
        if raw & 0x0002 != 0 { keys.insert(.leftShift) }
        if raw & 0x0004 != 0 { keys.insert(.rightShift) }
        if raw & 0x80_0000 != 0 { keys.insert(.fn) }
        // Some keyboards and remappers set only the device-independent flag. Treat those as the left key.
        let fallbacks: [(UInt64, ModifierKey.Kind, ModifierKey)] = [
            (0x4_0000, .control, .leftControl), (0x8_0000, .option, .leftOption),
            (0x10_0000, .command, .leftCommand), (0x2_0000, .shift, .leftShift),
        ]
        for (mask, kind, key) in fallbacks where raw & mask != 0 && !keys.contains(where: { $0.kind == kind }) {
            keys.insert(key)
        }
        return keys
    }
}

struct Shortcut: Codable, Hashable {
    var modifiers: Set<ModifierKey>
    var keyCode: UInt16?
    var keyLabel: String?
    var sideSpecific: Bool

    static let defaultDictation = Shortcut(
        modifiers: [.leftControl, .leftOption], keyCode: nil, keyLabel: nil, sideSpecific: false
    )

    var isModifierOnly: Bool { keyCode == nil }

    func modifiersMatch(_ active: Set<ModifierKey>) -> Bool {
        sideSpecific ? active == modifiers : Self.kinds(active) == Self.kinds(modifiers)
    }

    func hasExtraModifiers(_ active: Set<ModifierKey>) -> Bool {
        sideSpecific ? !active.isSubset(of: modifiers) : !Self.kinds(active).isSubset(of: Self.kinds(modifiers))
    }

    /// Keycap labels in display order, e.g. ["Right ⌥"] or ["⌃", "⌥", "Space"].
    var keycaps: [String] {
        let sorted = modifiers.sorted { ($0.kind, $0.isRight ? 1 : 0) < ($1.kind, $1.isRight ? 1 : 0) }
        var caps: [String] = []
        var seenKinds = Set<ModifierKey.Kind>()
        for key in sorted where sideSpecific || seenKinds.insert(key.kind).inserted {
            let side = sideSpecific && key.kind != .fn ? (key.isRight ? "Right " : "Left ") : ""
            caps.append(side + key.kind.symbol)
        }
        if let keyLabel { caps.append(keyLabel) }
        return caps
    }

    var hasSides: Bool { modifiers.contains { $0.kind != .fn } }

    private static func kinds(_ keys: Set<ModifierKey>) -> Set<ModifierKey.Kind> {
        Set(keys.map(\.kind))
    }

    static let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]

    static func label(forKeyCode keyCode: UInt16, characters: String?) -> String {
        let named: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        ]
        if let name = named[keyCode] { return name }
        let trimmed = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed
    }
}

enum TriggerBehavior: String, CaseIterable, Identifiable {
    case holdOrTap
    case hold
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdOrTap: "Hold, or tap for hands-free"
        case .hold: "Hold to talk"
        case .toggle: "Press to start, press to stop"
        }
    }

    var explanation: String {
        switch self {
        case .holdOrTap: "Hold the shortcut while you speak and release to finish. A quick tap keeps recording on until you press it again."
        case .hold: "Recording runs only while the shortcut is held. Quick accidental taps are ignored."
        case .toggle: "Press once to start recording and again to finish."
        }
    }
}
