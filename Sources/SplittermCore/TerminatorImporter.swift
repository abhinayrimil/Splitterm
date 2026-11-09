import Foundation

/// Imports profiles and layouts from a GNOME Terminator config file
/// (`~/.config/terminator/config`, configobj INI format).
/// Keybindings are not imported: Terminator's Ctrl/Super defaults don't map cleanly to macOS.
public enum TerminatorImporter {
    public struct Result {
        public var profiles: [String: Profile] = [:]
        public var layouts: [String: LayoutFile] = [:]
        public var warnings: [String] = []
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/terminator/config")
    }

    /// Nested sections: section path (e.g. ["layouts", "work", "child1"]) → key/values.
    typealias Sections = [[String]: [String: String]]

    public static func importConfig(text: String) -> Result {
        let sections = parse(text)
        var result = Result()

        for (path, values) in sections where path.count == 2 && path[0] == "profiles" {
            result.profiles[path[1]] = profile(from: values)
        }

        let layoutNames = Set(sections.keys.filter { $0.count == 3 && $0[0] == "layouts" }.map { $0[1] })
        for name in layoutNames.sorted() {
            var nodes: [String: [String: String]] = [:]
            for (path, values) in sections where path.count == 3 && path[0] == "layouts" && path[1] == name {
                nodes[path[2]] = values
            }
            do {
                result.layouts[name] = try layout(from: nodes)
            } catch {
                result.warnings.append("Layout '\(name)': \(error)")
            }
        }
        return result
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> Sections {
        var sections: Sections = [:]
        var stack: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                let depth = line.prefix(while: { $0 == "[" }).count
                let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                stack = Array(stack.prefix(depth - 1)) + [name]
                if sections[stack] == nil { sections[stack] = [:] }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, let l = value.last,
               (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                value = String(value.dropFirst().dropLast())
            }
            sections[stack, default: [:]][key] = value
        }
        return sections
    }

    static func bool(_ s: String?) -> Bool? {
        guard let s = s?.lowercased() else { return nil }
        if ["true", "yes", "on", "1"].contains(s) { return true }
        if ["false", "no", "off", "0"].contains(s) { return false }
        return nil
    }

    static func profile(from v: [String: String]) -> Profile {
        var p = Profile()
        if let font = v["font"], bool(v["use_system_font"]) == false {
            // "DejaVu Sans Mono Bold 12" → family + size
            var parts = font.split(separator: " ").map(String.init)
            if let last = parts.last, let size = Double(last) {
                p.fontSize = size
                parts.removeLast()
            }
            let styleWords: Set<String> = ["Bold", "Italic", "Oblique", "Regular", "Book", "Medium", "Light"]
            while let last = parts.last, styleWords.contains(last) { parts.removeLast() }
            let family = parts.joined(separator: " ")
            p.fontName = (family == "Mono" || family == "Monospace") ? "" : family
        }
        if let fg = v["foreground_color"], let c = RGB(hex: fg) { p.foreground = c.hex }
        if let bg = v["background_color"], let c = RGB(hex: bg) { p.background = c.hex }
        if let cc = v["cursor_color"] ?? v["cursor_fg_color"], let c = RGB(hex: cc) { p.cursorColor = c.hex }
        if let pal = v["palette"] {
            let colours = pal.split(separator: ":").compactMap { RGB(hex: String($0))?.hex }
            if colours.count == 16 { p.palette = colours }
        }
        if let shape = v["cursor_shape"] {
            p.cursorShape = shape == "ibeam" ? .beam : (shape == "underline" ? .underline : .block)
        }
        if let b = bool(v["cursor_blink"]) { p.cursorBlink = b }
        if bool(v["scrollback_infinite"]) == true {
            p.scrollbackLines = 1_000_000
        } else if let s = v["scrollback_lines"], let n = Int(s) {
            p.scrollbackLines = n
        }
        if v["background_type"] == "transparent", let d = v["background_darkness"], let dark = Double(d) {
            p.opacity = max(0.3, dark)
        }
        if let b = bool(v["login_shell"]) { p.loginShell = b }
        if bool(v["use_custom_command"]) == true, let cmd = v["custom_command"] { p.customCommand = cmd }
        if let ea = v["exit_action"] {
            p.exitAction = ea == "hold" ? .hold : (ea == "restart" ? .restart : .close)
        }
        if let b = bool(v["show_titlebar"]) { p.showTitlebar = b }
        if let b = bool(v["split_to_group"]) { p.splitToGroup = b }
        if let b = bool(v["copy_on_selection"]) { p.copyOnSelect = b }
        return p
    }

    struct ImportError: Error, CustomStringConvertible {
        let description: String
    }

    static func layout(from nodes: [String: [String: String]]) throws -> LayoutFile {
        func children(of parent: String) -> [(String, [String: String])] {
            nodes.filter { $0.value["parent"] == parent }
                .map { ($0.key, $0.value) }
                .sorted { (Int($0.1["order"] ?? "0") ?? 0, $0.0) < (Int($1.1["order"] ?? "0") ?? 0, $1.0) }
        }

        func node(_ name: String, _ v: [String: String]) throws -> LayoutNode {
            switch v["type"] {
            case "Terminal":
                return .terminal(LayoutTerminal(
                    profile: v["profile"].flatMap { $0.isEmpty ? nil : $0 },
                    group: v["group"].flatMap { $0.isEmpty ? nil : $0 },
                    title: v["title"].flatMap { $0.isEmpty ? nil : $0 },
                    command: v["command"].flatMap { $0.isEmpty ? nil : $0 },
                    cwd: v["directory"].flatMap { $0.isEmpty ? nil : $0 },
                    uuid: v["uuid"]))
            case "HPaned", "VPaned":
                let kids = children(of: name)
                guard kids.count == 2 else {
                    throw ImportError(description: "\(name) has \(kids.count) children, expected 2")
                }
                // GTK HPaned lays children side by side; VPaned stacks them.
                let dir: SplitDirection = v["type"] == "HPaned" ? .right : .down
                let ratio = Double(v["ratio"] ?? "") ?? 0.5
                return .split(direction: dir, ratio: ratio,
                              first: try node(kids[0].0, kids[0].1),
                              second: try node(kids[1].0, kids[1].1))
            default:
                throw ImportError(description: "unsupported node type '\(v["type"] ?? "?")' at \(name)")
            }
        }

        var windows: [LayoutWindow] = []
        for (wname, wv) in children(of: "") where wv["type"] == "Window" {
            let kids = children(of: wname)
            guard let firstChild = kids.first else { continue }
            let (cname, cv) = firstChild
            var tabs: [LayoutTab] = []
            if cv["type"] == "Notebook" {
                let labels = (cv["labels"] ?? "").split(separator: ",").map {
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
                }
                for (i, (tname, tv)) in children(of: cname).enumerated() {
                    let title = i < labels.count && labels[i] != "None" && !labels[i].isEmpty ? labels[i] : nil
                    tabs.append(LayoutTab(title: title, root: try node(tname, tv)))
                }
            } else {
                tabs.append(LayoutTab(root: try node(cname, cv)))
            }
            var frame: [Double]? = nil
            if let size = wv["size"] {
                let nums = size.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if nums.count == 2 { frame = [100, 100, nums[0], nums[1]] }
            }
            windows.append(LayoutWindow(frame: frame,
                                        maximized: bool(wv["maximised"]),
                                        fullScreen: bool(wv["fullscreen"]),
                                        title: wv["title"], tabs: tabs))
        }
        guard !windows.isEmpty else { throw ImportError(description: "no windows found") }
        return LayoutFile(windows: windows)
    }
}
