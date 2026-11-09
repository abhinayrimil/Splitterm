import AppKit
import SplittermCore
import SwiftTerm

extension NSColor {
    convenience init?(hex: String, alpha: CGFloat = 1) {
        guard let c = RGB(hex: hex) else { return nil }
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent)).hex
    }

    /// SwiftTerm's 16-bit colour type.
    var terminalColor: SwiftTerm.Color {
        let c = usingColorSpace(.sRGB) ?? self
        return SwiftTerm.Color(red: UInt16(c.redComponent * 65535),
                               green: UInt16(c.greenComponent * 65535),
                               blue: UInt16(c.blueComponent * 65535))
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var m: KeyModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        self = m
    }

    var eventFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.command) { f.insert(.command) }
        if contains(.option) { f.insert(.option) }
        if contains(.control) { f.insert(.control) }
        if contains(.shift) { f.insert(.shift) }
        return f
    }
}

extension Shortcut {
    init?(event: NSEvent) {
        self.init(keyCode: event.keyCode,
                  modifiers: KeyModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask)))
    }

    /// The menu key equivalent string for this shortcut (lower-case; Shift goes in the mask).
    var menuKeyEquivalent: String {
        func fn(_ k: Int) -> String { String(Character(UnicodeScalar(UInt16(k))!)) }
        switch key {
        case "up": return fn(NSUpArrowFunctionKey)
        case "down": return fn(NSDownArrowFunctionKey)
        case "left": return fn(NSLeftArrowFunctionKey)
        case "right": return fn(NSRightArrowFunctionKey)
        case "pageup": return fn(NSPageUpFunctionKey)
        case "pagedown": return fn(NSPageDownFunctionKey)
        case "home": return fn(NSHomeFunctionKey)
        case "end": return fn(NSEndFunctionKey)
        case "forwarddelete": return fn(NSDeleteFunctionKey)
        case "return": return "\r"
        case "tab": return "\t"
        case "space": return " "
        case "escape": return "\u{1b}"
        case "delete": return "\u{8}"
        default:
            if key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...12).contains(n) {
                return fn(NSF1FunctionKey + n - 1)
            }
            return key
        }
    }
}

extension Profile {
    func font(scale: CGFloat = 1) -> NSFont {
        let size = max(6, CGFloat(fontSize) * scale)
        if !fontName.isEmpty {
            if let f = NSFont(name: fontName, size: size) { return f }
            // Accept a family name such as "JetBrains Mono".
            if let f = NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: size) {
                return f
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func cursorStyle() -> CursorStyle {
        switch (cursorShape, cursorBlink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.beam, true): return .blinkBar
        case (.beam, false): return .steadyBar
        }
    }
}

extension NSView {
    /// All `TerminalPane` descendants in depth-first (visual reading) order.
    var descendantPanes: [TerminalPane] {
        if let p = self as? TerminalPane { return [p] }
        return subviews.flatMap { $0.descendantPanes }
    }

    func pinEdges(to other: NSView, insets: NSEdgeInsets = NSEdgeInsetsZero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

/// Small modal prompts used for titles, group names and layout names.
@MainActor
enum Prompt {
    static func text(title: String, message: String = "", defaultValue: String = "",
                     placeholder: String = "", okTitle: String = "OK", window: NSWindow? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func confirm(title: String, message: String, okTitle: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        let ok = alert.addButton(withTitle: okTitle)
        if destructive { ok.hasDestructiveAction = true }
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func info(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    static func error(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
