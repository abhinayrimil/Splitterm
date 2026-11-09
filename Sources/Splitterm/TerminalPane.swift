import AppKit
import Darwin
import SplittermCore
import SwiftTerm

/// SwiftTerm view subclass that fans user input out to broadcast receivers.
final class PaneTerminalView: LocalProcessTerminalView {
    weak var pane: TerminalPane?

    /// True when this view is the focused terminal of the key window.
    var isActiveSender: Bool {
        guard let window, window.isKeyWindow else { return false }
        return window.firstResponder === self
    }

    /// Bytes produced by keyboard, paste or IME (already translated) reach here.
    /// Broadcasting these bytes, rather than replaying key events as Terminator does,
    /// keeps composed characters and input-method text intact.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let pane, isActiveSender else {
            super.send(source: source, data: data)
            return
        }
        let model = AppModel.shared
        let receivers = model.receivers(of: pane)
        if receivers.isEmpty {
            super.send(source: source, data: data)
            return
        }
        let threshold = model.config.global.confirmBroadcastReturnAt
        if threshold > 0, receivers.count >= threshold, !model.largeBroadcastConfirmed, data.contains(13) {
            let ok = Prompt.confirm(title: "Send Return to \(receivers.count + 1) terminals?",
                                    message: "Broadcast is on (\(model.broadcast.title.lowercased())). This will run the command in every receiving terminal. You won't be asked again this session.",
                                    okTitle: "Send to All")
            guard ok else { return }
            model.largeBroadcastConfirmed = true
        }
        super.send(source: source, data: data)
        for r in receivers { r.sendToProcess(data) }
    }

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let clean = InputSafety.sanitizedPaste(text)
        send(txt: getTerminal().bracketedPasteMode ? "\u{1B}[200~\(clean)\u{1B}[201~" : clean)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        return pane?.contextMenu()
    }

    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        guard let pane, pane.profile.copyOnSelect, let text = getSelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Sits between SwiftTerm and the view to refuse what terminal output may not do to
/// the desktop: read or replace the clipboard (OSC 52) or open non-web links (OSC 8).
final class OutputGuard: TerminalViewDelegate {
    private let view: PaneTerminalView
    init(view: PaneTerminalView) { self.view = view }

    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard InputSafety.isOpenableLink(link) else { return }
        view.requestOpenLink(source: source, link: link, params: params)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { view.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) { view.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { view.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { view.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { view.scrolled(source: source, position: position) }
    func bell(source: TerminalView) { view.bell(source: source) }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) { view.iTermContent(source: source, content: content) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { view.rangeChanged(source: source, startY: startY, endY: endY) }
}

enum BroadcastRole { case none, grouped, sender, receiver }

/// One terminal: an optional Terminator-style title bar above a SwiftTerm view.
final class TerminalPane: NSView, LocalProcessTerminalViewDelegate {
    let id: UUID
    let header = PaneHeaderView()
    let terminalView: PaneTerminalView
    private let outputGuard: OutputGuard   // terminalDelegate is weak, so the pane owns it

    private(set) var profileName: String
    var group: String? { didSet { if group != oldValue { header.refresh() } } }
    var customTitle: String? { didSet { titleChanged() } }
    private(set) var autoTitle: String = ""
    private(set) var fontScale: CGFloat = 1

    /// Command typed into the shell at launch (kept so layouts can save it again).
    private(set) var layoutCommand: String?
    private var launchCwd: String?
    private var started = false
    private var exited = false
    private var trackingAreaRef: NSTrackingArea?

    var profile: Profile { AppModel.shared.config.profile(named: profileName) }
    var controller: TerminalWindowController? { window?.windowController as? TerminalWindowController }

    init(profile: String? = nil, cwd: String? = nil, command: String? = nil,
         group: String? = nil, title: String? = nil, uuid: UUID = UUID()) {
        self.id = uuid
        let model = AppModel.shared
        self.profileName = (profile.flatMap { model.config.profiles[$0] != nil ? $0 : nil }) ?? "default"
        self.terminalView = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        self.outputGuard = OutputGuard(view: terminalView)
        self.launchCwd = cwd
        self.layoutCommand = (command?.isEmpty ?? true) ? nil : command
        self.group = group
        self.customTitle = (title?.isEmpty ?? true) ? nil : title
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        terminalView.pane = self
        terminalView.processDelegate = self
        terminalView.terminalDelegate = outputGuard
        header.pane = self
        addSubview(header)
        addSubview(terminalView)
        if let group { model.createGroup(group) }
        model.register(self)
        applyProfile()

        NotificationCenter.default.addObserver(self, selector: #selector(configChanged),
                                               name: .splittermConfigChanged, object: nil)
        // Start on the next run-loop turn so layout code can size the view first.
        // Panes in background tabs start too, so layout commands run straight away.
        DispatchQueue.main.async { [weak self] in self?.startIfNeeded() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        startProcess()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let headerHeight: CGFloat = header.isHidden ? 0 : PaneHeaderView.height
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        terminalView.frame = NSRect(x: 0, y: headerHeight, width: bounds.width,
                                    height: max(0, bounds.height - headerHeight))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, !started {
            DispatchQueue.main.async { [weak self] in self?.startIfNeeded() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func mouseEntered(with event: NSEvent) {
        if AppModel.shared.config.global.focusFollowsMouse { focus() }
    }

    // MARK: Process

    static func userShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let s = String(cString: sh)
            if !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        if let s = ProcessInfo.processInfo.environment["SHELL"], !s.isEmpty { return s }
        return "/bin/zsh"
    }

    private func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["TERM_SESSION_ID", "XPC_SERVICE_NAME", "__CFBundleIdentifier"] { env.removeValue(forKey: key) }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Splitterm"
        env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        env["SPLITTERM_UUID"] = id.uuidString
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if env["SHELL"] == nil { env["SHELL"] = Self.userShell() }
        return env.map { "\($0.key)=\($0.value)" }
    }

    private func resolvedStartDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard var dir = launchCwd, !dir.isEmpty else { return home }
        if dir.hasPrefix("~") { dir = home + dir.dropFirst() }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue ? dir : home
    }

    func startProcess() {
        exited = false
        let p = profile
        let shell = Self.userShell()
        let shellName = (shell as NSString).lastPathComponent
        var args: [String] = []
        var execName: String? = nil
        if !p.customCommand.isEmpty {
            args = (p.loginShell ? ["-l"] : []) + ["-c", p.customCommand]
        } else if p.loginShell {
            execName = "-" + shellName   // argv[0] starting with "-" makes it a login shell
        }
        terminalView.startProcess(executable: shell, args: args, environment: environment(),
                                  execName: execName, currentDirectory: resolvedStartDirectory())
        if autoTitle.isEmpty { autoTitle = shellName; titleChanged() }
        if let cmd = layoutCommand, p.customCommand.isEmpty {
            // Typed after the shell starts so the shell stays open when the command ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.sendToProcess(ArraySlice(Array((cmd + "\r").utf8)))
            }
        }
    }

    func sendToProcess(_ data: ArraySlice<UInt8>) {
        guard !exited, let process = terminalView.process, process.running else { return }
        process.send(data: data)
    }

    func sendText(_ text: String) { sendToProcess(ArraySlice(Array(text.utf8))) }

    /// The shell's working directory, asked from the kernel. OSC 7 reports are ignored:
    /// any program's output can forge them.
    var currentDirectory: String? {
        if let pid = terminalView.process?.shellPid, pid > 0, let dir = Self.cwd(of: pid) { return dir }
        return launchCwd
    }

    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            let bytes = raw.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    func terminate() {
        guard !exited else { return }
        exited = true
        terminalView.process?.terminate()
    }

    /// Whether a program other than the shell owns the terminal (used for close prompts).
    var hasRunningChild: Bool {
        guard !exited, let process = terminalView.process, process.running else { return false }
        let foreground = tcgetpgrp(process.childfd)
        return foreground > 0 && foreground != process.shellPid
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            self?.autoTitle = title
            self?.titleChanged()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in self?.handleExit(code: exitCode) }
    }

    private func handleExit(code: Int32?) {
        guard !exited else { return }
        exited = true
        switch profile.exitAction {
        case .close:
            controller?.closePane(self, force: true)
        case .hold:
            terminalView.feed(text: "\r\n\u{1b}[2m[Process exited\(code.map { " with code \($0)" } ?? "")]\u{1b}[0m\r\n")
        case .restart:
            terminalView.feed(text: "\r\n")
            startProcess()
        }
    }

    // MARK: Appearance

    @objc private func configChanged() {
        if AppModel.shared.config.profiles[profileName] == nil { profileName = "default" }
        applyProfile()
    }

    func applyProfile() {
        let p = profile
        terminalView.font = p.font(scale: fontScale)
        let alpha = CGFloat(min(max(p.opacity, 0.3), 1))
        terminalView.nativeBackgroundColor = NSColor(hex: p.background, alpha: alpha) ?? .black
        terminalView.nativeForegroundColor = NSColor(hex: p.foreground) ?? .white
        terminalView.caretColor = NSColor(hex: p.cursorColor) ?? .white
        terminalView.selectedTextBackgroundColor = NSColor(hex: p.selectionColor) ?? .selectedTextBackgroundColor
        terminalView.installColors(p.palette.map { (NSColor(hex: $0) ?? .gray).terminalColor })
        terminalView.getTerminal().setCursorStyle(p.cursorStyle())
        terminalView.changeScrollback(p.scrollbackLines)
        terminalView.optionAsMetaKey = p.optionAsMeta
        header.isHidden = !p.showTitlebar
        header.refresh()
        needsLayout = true
        controller?.updateTranslucency()
    }

    func setProfile(_ name: String) {
        guard AppModel.shared.config.profiles[name] != nil else { return }
        profileName = name
        applyProfile()
    }

    func zoomFont(_ delta: Int) {
        fontScale = delta == 0 ? 1 : min(4, max(0.4, fontScale + CGFloat(delta) * 0.1))
        terminalView.font = profile.font(scale: fontScale)
    }

    var displayTitle: String {
        if let t = customTitle, !t.isEmpty { return t }
        return autoTitle.isEmpty ? "Terminal" : autoTitle
    }

    private func titleChanged() {
        header.refresh()
        controller?.paneTitleChanged(self)
    }

    var broadcastRole: BroadcastRole {
        let model = AppModel.shared
        if model.broadcast != .off, let sender = model.focusedPane {
            let receivers = model.receivers(of: sender)
            if !receivers.isEmpty {
                if sender === self { return .sender }
                if receivers.contains(where: { $0 === self }) { return .receiver }
            }
        }
        return group == nil ? .none : .grouped
    }

    // MARK: Focus

    func focus() {
        window?.makeFirstResponder(terminalView)
    }

    var isFocused: Bool { window?.firstResponder === terminalView }

    /// Cell size, used for keyboard resizing and minimum split sizes.
    var cellSize: NSSize {
        let font = terminalView.font
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        let height = ceil(font.ascender - font.descender + font.leading)
        return NSSize(width: max(width, 4), height: max(height, 8))
    }

    // MARK: Menus

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        for a: Action in [.splitRight, .splitDown, .newTab] { menu.addItem(MainMenu.item(for: a)) }
        menu.addItem(.separator())
        menu.addItem(MainMenu.item(for: .toggleZoom))
        menu.addItem(MainMenu.item(for: .closeTerminal))
        menu.addItem(.separator())

        let groupItem = NSMenuItem(title: "Group", action: nil, keyEquivalent: "")
        groupItem.submenu = groupMenu()
        menu.addItem(groupItem)

        let profiles = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let pm = NSMenu()
        for name in AppModel.shared.config.sortedProfileNames {
            let item = ClosureMenuItem(title: name) { [weak self] in self?.setProfile(name) }
            item.state = name == profileName ? .on : .off
            pm.addItem(item)
        }
        profiles.submenu = pm
        menu.addItem(profiles)
        menu.addItem(MainMenu.item(for: .editTerminalTitle))
        menu.addItem(.separator())
        menu.addItem(MainMenu.item(for: .resetAndClear))
        menu.addItem(MainMenu.item(for: .preferences))
        return menu
    }

    /// The Terminator grouping menu, opened from the title bar button or context menu.
    func groupMenu() -> NSMenu {
        let model = AppModel.shared
        let menu = NSMenu()

        let none = ClosureMenuItem(title: "None") { [weak self] in
            guard let self else { return }
            model.setGroup(nil, for: [self])
        }
        none.state = group == nil ? .on : .off
        menu.addItem(none)
        for g in model.groups {
            let item = ClosureMenuItem(title: g) { [weak self] in
                guard let self else { return }
                model.setGroup(g, for: [self])
            }
            item.state = group == g ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "New Group…") { [weak self] in self?.promptNewGroup() })
        menu.addItem(MainMenu.item(for: .groupAllInTab))
        menu.addItem(MainMenu.item(for: .ungroupAllInTab))
        menu.addItem(MainMenu.item(for: .groupAllInWindow))
        menu.addItem(MainMenu.item(for: .ungroupAllInWindow))
        if let g = group {
            menu.addItem(ClosureMenuItem(title: "Remove Group “\(g)”") { model.removeGroup(g) })
            menu.addItem(ClosureMenuItem(title: "Close Terminals in “\(g)”…") { [weak self] in
                self?.controller?.closeGroup(g)
            })
        }
        if !model.groups.isEmpty {
            menu.addItem(ClosureMenuItem(title: "Remove All Groups") { model.removeAllGroups() })
        }
        menu.addItem(.separator())
        for a: Action in [.broadcastOff, .broadcastGroup, .broadcastAll] {
            menu.addItem(MainMenu.item(for: a))
        }
        menu.addItem(.separator())
        menu.addItem(MainMenu.item(for: .insertNumber))
        menu.addItem(MainMenu.item(for: .insertPaddedNumber))
        return menu
    }

    func promptNewGroup() {
        let model = AppModel.shared
        guard let name = Prompt.text(title: "New Group", message: "Terminals in the same group receive broadcast input together.",
                                     defaultValue: model.nextGroupName()), !name.isEmpty else { return }
        model.setGroup(name, for: [self])
    }

    func promptTitle() {
        guard let t = Prompt.text(title: "Terminal Title", message: "Leave empty to use the title set by the shell.",
                                  defaultValue: customTitle ?? "") else { return }
        customTitle = t.isEmpty ? nil : t
    }

    func describe(focused: Bool) -> LayoutTerminal {
        let cwd = currentDirectory.map { path -> String in
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }
        return LayoutTerminal(profile: profileName == "default" ? nil : profileName,
                              group: group, title: customTitle, command: layoutCommand,
                              cwd: cwd, focused: focused ? true : nil, uuid: id.uuidString)
    }
}

/// Terminator-style per-terminal title bar: group button, title, broadcast colours.
final class PaneHeaderView: NSView {
    static let height: CGFloat = 22
    weak var pane: TerminalPane?
    private let groupButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private var background = NSColor.windowBackgroundColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        groupButton.bezelStyle = .inline
        groupButton.isBordered = false
        groupButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Group")
        groupButton.imagePosition = .imageLeading
        groupButton.font = .systemFont(ofSize: 11, weight: .medium)
        groupButton.target = self
        groupButton.action = #selector(showGroupMenu)
        groupButton.toolTip = "Group and broadcast"
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .center
        addSubview(groupButton)
        addSubview(titleLabel)
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: .splittermStateChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        groupButton.sizeToFit()
        let gw = min(max(groupButton.frame.width + 8, 28), bounds.width / 2)
        groupButton.frame = NSRect(x: 4, y: (bounds.height - 18) / 2, width: gw, height: 18)
        let lh: CGFloat = 15
        titleLabel.frame = NSRect(x: gw + 8, y: (bounds.height - lh) / 2,
                                  width: max(0, bounds.width - 2 * (gw + 8)), height: lh)
    }

    @objc private func stateChanged() { refresh() }

    func refresh() {
        guard let pane, !isHidden else { return }
        let model = AppModel.shared
        groupButton.title = pane.group ?? ""
        titleLabel.stringValue = pane.displayTitle
        let fg: NSColor
        switch pane.broadcastRole {
        case .sender:
            background = NSColor(hex: "#c80003") ?? .systemRed
            fg = .white
        case .receiver:
            background = NSColor(hex: "#0076c9") ?? .systemBlue
            fg = .white
        case .grouped:
            background = model.colour(forGroup: pane.group ?? "").withAlphaComponent(0.25)
            fg = .labelColor
        case .none:
            background = pane.isFocused ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                                        : NSColor.windowBackgroundColor
            fg = pane.isFocused ? .labelColor : .secondaryLabelColor
        }
        titleLabel.textColor = fg
        groupButton.contentTintColor = fg
        groupButton.attributedTitle = NSAttributedString(string: groupButton.title,
                                                         attributes: [.foregroundColor: fg, .font: groupButton.font!])
        needsLayout = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            pane?.promptTitle()
        } else {
            pane?.focus()
        }
    }

    @objc private func showGroupMenu() {
        guard let pane else { return }
        pane.focus()
        let menu = pane.groupMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: groupButton.frame.minX, y: groupButton.frame.maxY + 2), in: self)
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
