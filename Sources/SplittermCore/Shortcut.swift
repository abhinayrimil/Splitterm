import Foundation

/// Modifier keys a shortcut can use. Raw values are independent of AppKit so this
/// type stays testable; the app maps them to `NSEvent.ModifierFlags`.
public struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift   = KeyModifiers(rawValue: 1 << 3)
}

/// A keyboard shortcut such as `cmd+shift+d`, matched by physical key code
/// (US ANSI positions) so that Shift does not change which key is meant.
public struct Shortcut: Hashable, Sendable, CustomStringConvertible {
    public let key: String          // normalised key name, e.g. "d", "up", "]"
    public let modifiers: KeyModifiers

    public init(key: String, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses strings like `cmd+shift+d`, `ctrl+opt+left`, `f11`.
    /// Returns nil for empty strings (unbound) or unknown keys.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        // "+" itself is spelled "plus"; split on "+" otherwise.
        var parts = trimmed.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if trimmed.hasSuffix("++") { parts.removeLast(2); parts.append("=") }
        guard let rawKey = parts.last, !rawKey.isEmpty else { return nil }
        var mods: KeyModifiers = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command", "super", "meta": mods.insert(.command)
            case "opt", "option", "alt": mods.insert(.option)
            case "ctrl", "control": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        let key = Shortcut.normalise(rawKey)
        guard KeyCodes.code(for: key) != nil else { return nil }
        self.key = key
        self.modifiers = mods
    }

    /// Builds a shortcut from a hardware key code and modifiers (used when matching events).
    public init?(keyCode: UInt16, modifiers: KeyModifiers) {
        guard let name = KeyCodes.name(for: keyCode) else { return nil }
        self.key = name
        self.modifiers = modifiers
    }

    public var keyCode: UInt16 { KeyCodes.code(for: key) ?? 0 }

    /// Canonical string form, e.g. `cmd+shift+d`.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Human-readable form with macOS symbols, e.g. `⇧⌘D`.
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += KeyCodes.displayName(for: key)
        return s
    }

    static func normalise(_ key: String) -> String {
        switch key {
        case "enter": return "return"
        case "esc": return "escape"
        case "backspace": return "delete"
        case "pgup", "page_up": return "pageup"
        case "pgdn", "page_down": return "pagedown"
        case "plus", "equal", "equals": return "="
        case "minus": return "-"
        case "leftbracket": return "["
        case "rightbracket": return "]"
        case "arrowup": return "up"
        case "arrowdown": return "down"
        case "arrowleft": return "left"
        case "arrowright": return "right"
        default: return key
        }
    }
}

extension Shortcut: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Shortcut(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid shortcut '\(s)'"))
        }
        self = parsed
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// macOS virtual key codes (Carbon `kVK_*`) for the US ANSI layout.
public enum KeyCodes {
    static let table: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "l": 0x25, "j": 0x26, "'": 0x27,
        "k": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
        "tab": 0x30, "space": 0x31, "`": 0x32, "delete": 0x33, "escape": 0x35,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
        "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
    static let reverse: [UInt16: String] = {
        var r: [UInt16: String] = [:]
        for (k, v) in table { r[v] = k }
        r[0x4C] = "return"   // keypad Enter behaves like Return
        return r
    }()

    public static func code(for key: String) -> UInt16? { table[key] }
    public static func name(for code: UInt16) -> String? { reverse[code] }

    public static func displayName(for key: String) -> String {
        switch key {
        case "return": return "↩"
        case "tab": return "⇥"
        case "space": return "Space"
        case "delete": return "⌫"
        case "forwarddelete": return "⌦"
        case "escape": return "⎋"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        case "home": return "↖"
        case "end": return "↘"
        default: return key.uppercased()
        }
    }
}
