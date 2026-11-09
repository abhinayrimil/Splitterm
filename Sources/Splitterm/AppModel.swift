import AppKit
import SplittermCore

extension Notification.Name {
    /// Broadcast mode, groups, focus or titles changed: headers and badges redraw.
    static let splittermStateChanged = Notification.Name("SplittermStateChanged")
    /// The config was reloaded or edited: panes re-apply profiles, menus rebuild.
    static let splittermConfigChanged = Notification.Name("SplittermConfigChanged")
}

/// App-wide state, the equivalent of Terminator's `Terminator` singleton:
/// windows, terminals, groups, broadcast mode and configuration.
@MainActor
final class AppModel {
    static let shared = AppModel()

    private(set) var config = AppConfig()
    private(set) var bindings = KeyBindingTable(overrides: [:])
    private var configDate: Date?

    var windowControllers: [TerminalWindowController] = []
    private let panes = NSHashTable<TerminalPane>.weakObjects()

    /// Known group names in creation order.
    private(set) var groups: [String] = []
    var broadcast: BroadcastMode = .group { didSet { stateChanged() } }
    /// Set once the user agrees to a large broadcast Return in this session.
    var largeBroadcastConfirmed = false

    private init() {}

    // MARK: Config

    func loadConfig() {
        switch ConfigStore.load() {
        case .loaded(let c), .created(let c):
            config = c
        case .failed(let c, let error):
            config = c
            DispatchQueue.main.async {
                Prompt.error("Couldn't read config.json",
                             "Using defaults. Fix the file and Splitterm reloads it when you switch back.\n\n\(error)")
            }
        }
        configDate = ConfigStore.modificationDate()
        bindings = KeyBindingTable(overrides: config.keybindings)
        broadcast = config.global.broadcastDefault
    }

    /// Reloads if the file changed on disk (checked when the app becomes active).
    func reloadIfChangedOnDisk() {
        let date = ConfigStore.modificationDate()
        guard let date, date != configDate else { return }
        if case .loaded(let c) = ConfigStore.load() {
            configDate = date
            apply(c, save: false)
        }
    }

    /// Replaces the config, optionally saves it, and refreshes everything.
    func apply(_ newConfig: AppConfig, save: Bool = true) {
        config = newConfig
        bindings = KeyBindingTable(overrides: config.keybindings)
        if save { saveConfig() }
        NotificationCenter.default.post(name: .splittermConfigChanged, object: nil)
        stateChanged()
    }

    func update(_ change: (inout AppConfig) -> Void) {
        var c = config
        change(&c)
        apply(c)
    }

    func saveConfig() {
        do {
            try ConfigStore.save(config)
            configDate = ConfigStore.modificationDate()
        } catch {
            Prompt.error("Couldn't save settings", error.localizedDescription)
        }
    }

    // MARK: Terminals

    func register(_ pane: TerminalPane) { panes.add(pane) }

    func unregister(_ pane: TerminalPane) {
        panes.remove(pane)
        hooverGroups()
        stateChanged()
    }

    /// Every terminal across all windows, in window → tab → tree order.
    var allPanes: [TerminalPane] {
        windowControllers.flatMap { $0.allPanes }
    }

    /// The terminal that has keyboard focus in the key window, if any.
    var focusedPane: TerminalPane? {
        guard let wc = NSApp.keyWindow?.windowController as? TerminalWindowController else { return nil }
        return wc.focusedPane
    }

    /// Terminals that mirror the sender's input under the current broadcast mode.
    func receivers(of sender: TerminalPane) -> [TerminalPane] {
        switch broadcast {
        case .off:
            return []
        case .all:
            return allPanes.filter { $0 !== sender }
        case .group:
            guard let g = sender.group else { return [] }
            return allPanes.filter { $0 !== sender && $0.group == g }
        }
    }

    /// The sender plus its receivers — used by paste-style actions such as insert number.
    func targets(of sender: TerminalPane) -> [TerminalPane] {
        [sender] + receivers(of: sender)
    }

    // MARK: Groups

    func createGroup(_ name: String) {
        guard !name.isEmpty, !groups.contains(name) else { return }
        groups.append(name)
        stateChanged()
    }

    func nextGroupName() -> String { GroupNames.next(excluding: Set(groups)) }

    func setGroup(_ name: String?, for panes: [TerminalPane]) {
        if let name { createGroup(name) }
        for p in panes { p.group = name }
        hooverGroups()
        stateChanged()
    }

    /// Clears a group from every terminal but keeps the terminals open.
    func removeGroup(_ name: String) {
        for p in allPanes where p.group == name { p.group = nil }
        groups.removeAll { $0 == name }
        stateChanged()
    }

    func removeAllGroups() {
        for p in allPanes { p.group = nil }
        groups.removeAll()
        stateChanged()
    }

    func hooverGroups() {
        guard config.global.autocleanGroups else { return }
        let inUse = Set(allPanes.compactMap { $0.group })
        groups.removeAll { !inUse.contains($0) }
    }

    /// A stable colour per group name for header tints.
    func colour(forGroup name: String) -> NSColor {
        let colours: [NSColor] = [.systemTeal, .systemOrange, .systemPurple, .systemGreen,
                                  .systemPink, .systemYellow, .systemIndigo, .systemBrown]
        let index = (groups.firstIndex(of: name) ?? abs(name.hashValue)) % colours.count
        return colours[index]
    }

    func stateChanged() {
        NotificationCenter.default.post(name: .splittermStateChanged, object: nil)
    }

    // MARK: Windows

    @discardableResult
    func newWindow(layout: LayoutWindow? = nil, cwd: String? = nil, profile: String? = nil) -> TerminalWindowController {
        let wc = TerminalWindowController(layout: layout, cwd: cwd, profile: profile)
        windowControllers.append(wc)
        wc.showWindow(nil)
        return wc
    }

    func windowClosed(_ wc: TerminalWindowController) {
        windowControllers.removeAll { $0 === wc }
        hooverGroups()
        stateChanged()
    }

    // MARK: Layouts

    func launchLayout(named name: String) {
        guard let layout = config.layouts[name] else {
            Prompt.error("No layout named “\(name)”", "Open the Layout Launcher to see saved layouts.")
            return
        }
        for w in layout.windows { newWindow(layout: w) }
    }

    /// Any web page can fire a `splitterm://` link, so commands never run from one unconfirmed.
    func launchLayoutFromLink(named name: String) {
        let commands = config.commands(inLayout: name)
        if !commands.isEmpty {
            let list = commands.prefix(10).map { InputSafety.displaySafe($0) }.joined(separator: "\n")
            let more = commands.count > 10 ? "\n…and \(commands.count - 10) more" : ""
            guard Prompt.confirm(title: "Run commands from a link?",
                                 message: "A link asked to open layout “\(InputSafety.displaySafe(name))”, which runs:\n\n\(list)\(more)",
                                 okTitle: "Open and Run", destructive: true) else { return }
        }
        launchLayout(named: name)
    }

    func captureLayout() -> LayoutFile {
        LayoutFile(windows: windowControllers.map { $0.describeLayout() })
    }

    /// Saves the current session under `name`. Commands set by hand on an existing layout
    /// are kept for terminals in the same position (fixes Terminator's "Save wipes commands").
    func saveCurrentLayout(as name: String) {
        var captured = captureLayout()
        if let old = config.layouts[name] {
            captured = Self.mergeCommands(from: old, into: captured)
        }
        update { $0.layouts[name] = captured }
    }

    static func mergeCommands(from old: LayoutFile, into new: LayoutFile) -> LayoutFile {
        var result = new
        for wi in result.windows.indices where wi < old.windows.count {
            for ti in result.windows[wi].tabs.indices where ti < old.windows[wi].tabs.count {
                let oldTerms = old.windows[wi].tabs[ti].root.terminals
                var index = 0
                result.windows[wi].tabs[ti].root = mapTerminals(result.windows[wi].tabs[ti].root) { t in
                    defer { index += 1 }
                    var t = t
                    if index < oldTerms.count, t.command == nil { t.command = oldTerms[index].command }
                    return t
                }
            }
        }
        return result
    }

    private static func mapTerminals(_ node: LayoutNode, _ f: (LayoutTerminal) -> LayoutTerminal) -> LayoutNode {
        switch node {
        case .terminal(let t): return .terminal(f(t))
        case .split(let d, let r, let a, let b):
            let na = mapTerminals(a, f)
            let nb = mapTerminals(b, f)
            return .split(direction: d, ratio: r, first: na, second: nb)
        }
    }
}
