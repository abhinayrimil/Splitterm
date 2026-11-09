import Foundation

public enum CursorShape: String, Codable, CaseIterable, Sendable {
    case block, underline, beam
}

public enum ExitAction: String, Codable, CaseIterable, Sendable {
    case close, hold, restart
}

/// A named bundle of appearance and shell settings applied per terminal.
/// Missing keys in the config file fall back to the defaults below.
public struct Profile: Codable, Equatable, Sendable {
    /// Font PostScript or family name. Empty means the system monospaced font (SF Mono).
    public var fontName: String = ""
    public var fontSize: Double = 13
    public var foreground: String = "#d8d8d8"
    public var background: String = "#1e1e1e"
    public var cursorColor: String = "#d8d8d8"
    public var selectionColor: String = "#44475a"
    /// Sixteen ANSI colours, normal then bright.
    public var palette: [String] = Profile.defaultPalette
    public var cursorShape: CursorShape = .block
    public var cursorBlink: Bool = true
    public var scrollbackLines: Int = 10_000
    /// 0.3–1.0; below 1 makes the window translucent.
    public var opacity: Double = 1.0
    public var loginShell: Bool = true
    /// When non-empty, runs instead of the user's shell (Terminator's custom_command).
    public var customCommand: String = ""
    public var exitAction: ExitAction = .close
    public var showTitlebar: Bool = true
    /// New splits join the source terminal's group.
    public var splitToGroup: Bool = false
    public var optionAsMeta: Bool = false
    public var copyOnSelect: Bool = false

    public init() {}

    public static let defaultPalette = [
        "#2e3436", "#cc0000", "#4e9a06", "#c4a000", "#3465a4", "#75507b", "#06989a", "#d3d7cf",
        "#555753", "#ef2929", "#8ae234", "#fce94f", "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec",
    ]

    enum CodingKeys: String, CodingKey {
        case fontName, fontSize, foreground, background, cursorColor, selectionColor, palette,
             cursorShape, cursorBlink, scrollbackLines, opacity, loginShell, customCommand,
             exitAction, showTitlebar, splitToGroup, optionAsMeta, copyOnSelect
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? d.foreground
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        cursorColor = try c.decodeIfPresent(String.self, forKey: .cursorColor) ?? d.cursorColor
        selectionColor = try c.decodeIfPresent(String.self, forKey: .selectionColor) ?? d.selectionColor
        let pal = try c.decodeIfPresent([String].self, forKey: .palette) ?? d.palette
        palette = pal.count == 16 ? pal : d.palette
        cursorShape = try c.decodeIfPresent(CursorShape.self, forKey: .cursorShape) ?? d.cursorShape
        cursorBlink = try c.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? d.cursorBlink
        scrollbackLines = try c.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? d.scrollbackLines
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        loginShell = try c.decodeIfPresent(Bool.self, forKey: .loginShell) ?? d.loginShell
        customCommand = try c.decodeIfPresent(String.self, forKey: .customCommand) ?? d.customCommand
        exitAction = try c.decodeIfPresent(ExitAction.self, forKey: .exitAction) ?? d.exitAction
        showTitlebar = try c.decodeIfPresent(Bool.self, forKey: .showTitlebar) ?? d.showTitlebar
        splitToGroup = try c.decodeIfPresent(Bool.self, forKey: .splitToGroup) ?? d.splitToGroup
        optionAsMeta = try c.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? d.optionAsMeta
        copyOnSelect = try c.decodeIfPresent(Bool.self, forKey: .copyOnSelect) ?? d.copyOnSelect
    }
}

/// Parses `#rgb`, `#rrggbb` or `#rrrrggggbbbb` (GTK style) into 0...1 components.
public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        let digits: Int
        switch s.count {
        case 3: digits = 1
        case 6: digits = 2
        case 12: digits = 4
        default: return nil
        }
        func comp(_ i: Int) -> Double {
            let start = s.index(s.startIndex, offsetBy: i * digits)
            let end = s.index(start, offsetBy: digits)
            let v = Double(Int(s[start..<end], radix: 16) ?? 0)
            let maxV = pow(16.0, Double(digits)) - 1
            return v / maxV
        }
        r = comp(0); g = comp(1); b = comp(2)
    }

    public var hex: String {
        func h(_ v: Double) -> String { String(format: "%02x", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + h(r) + h(g) + h(b)
    }
}
