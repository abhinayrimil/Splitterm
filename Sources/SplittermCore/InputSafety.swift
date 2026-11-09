import Foundation

/// Rules for data that comes from outside the user's keyboard: pasted text,
/// terminal output and `splitterm://` links.
public enum InputSafety {
    /// Only these schemes open from a terminal link. Anything else could launch an
    /// arbitrary app handler or a local file chosen by whatever printed the link.
    public static func isOpenableLink(_ link: String) -> Bool {
        guard let scheme = URLComponents(string: link)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// Removes ESC and CSI so pasted text cannot end bracketed paste early and run as typed input.
    public static func sanitizedPaste(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { $0 != "\u{1B}" && $0 != "\u{9B}" })
        return String(scalars)
    }

    /// Makes untrusted text safe to show in a confirmation: no newlines or bidi
    /// overrides that could disguise it, and a bounded length.
    public static func displaySafe(_ text: String, limit: Int = 300) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(String(scalars).prefix(limit))
    }
}

public extension AppConfig {
    /// Every command that opening the named layout would run.
    func commands(inLayout name: String) -> [String] {
        guard let layout = layouts[name] else { return [] }
        let terminals = layout.windows.flatMap { $0.tabs }.flatMap { $0.root.terminals }
        return terminals.flatMap { t in
            [t.command ?? "", profile(named: t.profile ?? "default").customCommand]
        }.filter { !$0.isEmpty }
    }
}
