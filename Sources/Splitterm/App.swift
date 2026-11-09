import AppKit
import Carbon.HIToolbox
import SplittermCore

@main
@MainActor
enum SplittermApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var settings: SettingsWindowController?
    private var launcher: LayoutLauncherController?
    private var openedSomething = false
    private var secureKeyboardActive = false

    private var model: AppModel { AppModel.shared }

    // MARK: Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Config must be ready before launch-time URLs and folders are delivered.
        model.loadConfig()
        NSApp.mainMenu = MainMenu.build()
        KeyDispatcher.shared.install()
        NotificationCenter.default.addObserver(self, selector: #selector(configChanged),
                                               name: .splittermConfigChanged, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--layout"), i + 1 < args.count {
            openedSomething = true
            model.launchLayout(named: args[i + 1])
        }
        // URLs and folders passed via `open` arrive just after launch; wait for them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.openStartupWindowIfNeeded()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openStartupWindowIfNeeded() {
        guard !openedSomething, model.windowControllers.isEmpty else { return }
        let startup = model.config.global.startupLayout
        if !startup.isEmpty, model.config.layouts[startup] != nil {
            model.launchLayout(named: startup)
        }
        if model.windowControllers.isEmpty { model.newWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.windowControllers.isEmpty { model.newWindow() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.reloadIfChangedOnDisk()
        syncSecureKeyboard()
    }

    func applicationDidResignActive(_ notification: Notification) {
        syncSecureKeyboard()
    }

    // MARK: Secure Keyboard Entry

    private static let secureKeyboardKey = "secureKeyboardEntry"
    private var secureKeyboardEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.secureKeyboardKey) as? Bool ?? true
    }

    /// Enable and Disable calls must stay balanced, so only act on a change.
    private func syncSecureKeyboard() {
        let wanted = NSApp.isActive && secureKeyboardEnabled
        guard wanted != secureKeyboardActive else { return }
        secureKeyboardActive = wanted
        if wanted { EnableSecureEventInput() } else { DisableSecureEventInput() }
    }

    @objc func toggleSecureKeyboard(_ sender: Any?) {
        UserDefaults.standard.set(!secureKeyboardEnabled, forKey: Self.secureKeyboardKey)
        syncSecureKeyboard()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let panes = model.allPanes
        let running = panes.filter { $0.hasRunningChild }.count
        guard panes.count > 1 || running > 0 else { return .terminateNow }
        var msg = "\(panes.count) terminal\(panes.count == 1 ? "" : "s") will be closed."
        if running > 0 { msg += " \(running) of them are running a program." }
        return Prompt.confirm(title: "Quit Splitterm?", message: msg, okTitle: "Quit", destructive: true)
            ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        for p in model.allPanes { p.terminate() }
    }

    /// Handles `splitterm://layout/NAME`, `splitterm://new?cwd=PATH`, and folders dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        openedSomething = true
        for url in urls {
            if url.isFileURL {
                var isDir: ObjCBool = false
                let path = url.path
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                    model.newWindow(cwd: isDir.boolValue ? path : url.deletingLastPathComponent().path)
                }
                continue
            }
            guard url.scheme?.lowercased() == "splitterm" else { continue }
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            switch url.host?.lowercased() {
            case "layout":
                let name = url.pathComponents.dropFirst().joined(separator: "/")
                if !name.isEmpty { model.launchLayoutFromLink(named: name) }
            case "new":
                let cwd = comps?.queryItems?.first { $0.name == "cwd" }?.value
                let profile = comps?.queryItems?.first { $0.name == "profile" }?.value
                // A shell prompt can run code from its folder (git hooks, direnv), and a profile can run a command.
                if cwd != nil || profile != nil {
                    let details = "Folder: \(InputSafety.displaySafe(cwd ?? "home"))\nProfile: \(InputSafety.displaySafe(profile ?? "default"))"
                    guard Prompt.confirm(title: "Open a terminal from a link?", message: details,
                                         okTitle: "Open", destructive: true) else { continue }
                }
                model.newWindow(cwd: cwd, profile: profile)
            default:
                model.newWindow()
            }
        }
    }

    @objc private func configChanged() {
        NSApp.mainMenu = MainMenu.build()
    }

    // MARK: Actions

    @objc func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        perform(action)
    }

    func perform(_ action: Action) {
        switch action {
        case .layoutLauncher, .saveLayout, .preferences, .preferencesKeybindings:
            performAppAction(action)
            return
        default:
            break
        }
        if let wc = NSApp.keyWindow?.windowController as? TerminalWindowController {
            wc.perform(action)
            return
        }
        switch action {
        case .newWindow, .newTab:
            model.newWindow()
        case .closeTerminal, .closeWindow:
            NSApp.keyWindow?.performClose(nil)
        case .broadcastOff: model.broadcast = .off
        case .broadcastGroup: model.broadcast = .group
        case .broadcastAll: model.broadcast = .all
        default:
            if let wc = (NSApp.mainWindow?.windowController as? TerminalWindowController) ?? model.windowControllers.last {
                wc.window?.makeKeyAndOrderFront(nil)
                wc.perform(action)
            }
        }
    }

    func performAppAction(_ action: Action) {
        switch action {
        case .layoutLauncher:
            if launcher == nil { launcher = LayoutLauncherController() }
            launcher?.show()
        case .saveLayout:
            saveLayoutPrompt()
        case .preferences:
            showSettings(tab: .general)
        case .preferencesKeybindings:
            showSettings(tab: .keybindings)
        default:
            perform(action)
        }
    }

    func saveLayoutPrompt() {
        guard !model.windowControllers.isEmpty else { NSSound.beep(); return }
        let msg = "Saves every open window, tab and split with each terminal's profile, group, title and folder. Saving over an existing layout keeps commands you set for it."
        guard let name = Prompt.text(title: "Save Layout", message: msg, defaultValue: "default",
                                     placeholder: "Layout name", okTitle: "Save"),
              !name.isEmpty else { return }
        if model.config.layouts[name] != nil,
           !Prompt.confirm(title: "Replace layout “\(name)”?", message: "The saved layout will be updated to match the current windows.",
                           okTitle: "Replace") {
            return
        }
        model.saveCurrentLayout(as: name)
    }

    func showSettings(tab: SettingsTab) {
        if settings == nil { settings = SettingsWindowController() }
        settings?.show(tab: tab)
    }

    @objc func openConfigFile(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: ConfigStore.fileURL.path) { model.saveConfig() }
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    @objc func openHelp(_ sender: Any?) {
        if let readme = Bundle.main.url(forResource: "README", withExtension: "md") {
            NSWorkspace.shared.open(readme)
        } else {
            showSettings(tab: .keybindings)
        }
    }

    @objc func importTerminatorConfig(_ sender: Any?) {
        var url = TerminatorImporter.defaultURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let panel = NSOpenPanel()
            panel.message = "Choose a Terminator config file (usually ~/.config/terminator/config)"
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            Prompt.error("Couldn't read the file", url.path)
            return
        }
        let result = TerminatorImporter.importConfig(text: text)
        model.update { cfg in
            for (name, p) in result.profiles {
                // Keep our own default profile unless Terminator's was customised.
                cfg.profiles[name == "default" ? "terminator-default" : name] = p
            }
            for (name, l) in result.layouts {
                // The startup layout runs its commands unprompted, so an import must never become it.
                var target = name
                while target == "default" || target == cfg.global.startupLayout { target = "terminator-\(target)" }
                cfg.layouts[target] = l
            }
        }
        var msg = "Imported \(result.profiles.count) profile(s) and \(result.layouts.count) layout(s)."
        if result.profiles["default"] != nil { msg += " Terminator's default profile was saved as “terminator-default”." }
        if result.layouts["default"] != nil { msg += " Terminator's default layout was saved as “terminator-default” and won't open at launch." }
        if !result.warnings.isEmpty { msg += "\n\nSkipped:\n" + result.warnings.joined(separator: "\n") }
        Prompt.info("Terminator config imported", msg)
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSecureKeyboard(_:)) {
            menuItem.state = secureKeyboardEnabled ? .on : .off
            return true
        }
        guard let raw = menuItem.representedObject as? String, let action = Action(rawValue: raw) else {
            return true
        }
        switch action {
        case .broadcastOff: menuItem.state = model.broadcast == .off ? .on : .off
        case .broadcastGroup: menuItem.state = model.broadcast == .group ? .on : .off
        case .broadcastAll: menuItem.state = model.broadcast == .all ? .on : .off
        default: break
        }
        switch action {
        case .newWindow, .newTab, .layoutLauncher, .preferences, .preferencesKeybindings,
             .broadcastOff, .broadcastGroup, .broadcastAll, .closeWindow, .closeTerminal:
            return true
        case .saveLayout:
            return !model.windowControllers.isEmpty
        default:
            return !model.windowControllers.isEmpty
        }
    }
}
