import AppKit
import SplittermCore

/// One tab: its split tree plus per-tab state.
@MainActor
final class TabItem {
    let root: TabRootView
    var customTitle: String?
    weak var lastFocused: TerminalPane?

    init(root: TabRootView, customTitle: String? = nil) {
        self.root = root
        self.customTitle = customTitle
    }
}

/// Window subclass that reports focus changes to its controller.
final class TerminalWindow: NSWindow {
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(responder)
        (windowController as? TerminalWindowController)?.firstResponderChanged()
        return ok
    }
}

/// Lays out the tab bar above the active tab.
final class WindowContentView: NSView {
    let tabBar = TabBarView()
    let host = NSView()
    var showsTabBar = false { didSet { tabBar.isHidden = !showsTabBar; needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(host)
        addSubview(tabBar)
        tabBar.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let barHeight = showsTabBar ? TabBarView.height : 0
        tabBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        host.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
        for v in host.subviews { v.frame = host.bounds }
    }
}

enum NavigationDirection { case left, right, up, down }

final class TerminalWindowController: NSWindowController, NSWindowDelegate, TabBarDelegate {
    private(set) var tabs: [TabItem] = []
    private(set) var activeIndex = 0
    private let content = WindowContentView(frame: NSRect(x: 0, y: 0, width: 900, height: 580))
    private let badgeLabel = NSTextField(labelWithString: "")
    private let badgeAccessory = NSTitlebarAccessoryViewController()
    var customWindowTitle: String? { didSet { updateWindowTitle() } }
    private var closingConfirmed = false

    // MARK: Lifecycle

    init(layout: LayoutWindow? = nil, cwd: String? = nil, profile: String? = nil, adopting tab: TabItem? = nil) {
        let window = TerminalWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                    backing: .buffered, defer: false)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 200)
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.contentView = content
        window.delegate = self
        content.tabBar.delegate = self
        setUpBadge()

        if let tab {
            tabs = [tab]
            selectTab(0)
        } else if let layout, !layout.tabs.isEmpty {
            restore(layout)
        } else {
            addTab(root: TerminalPane(profile: profile, cwd: cwd), title: nil)
        }
        if let f = layout?.frame, f.count == 4 {
            let rect = NSRect(x: f[0], y: f[1], width: max(f[2], 320), height: max(f[3], 200))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                window.setFrame(rect, display: false)
            } else {
                window.center()
            }
        } else {
            placeNewWindow(window)
        }
        customWindowTitle = layout?.title

        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: .splittermStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(configChanged),
                                               name: .splittermConfigChanged, object: nil)
        updateTranslucency()

        if layout?.maximized == true {
            DispatchQueue.main.async { window.zoom(nil) }
        }
        if layout?.fullScreen == true {
            DispatchQueue.main.async { window.toggleFullScreen(nil) }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func placeNewWindow(_ window: NSWindow) {
        if let last = AppModel.shared.windowControllers.last(where: { $0 !== self })?.window {
            let p = window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY))
            window.setFrameTopLeftPoint(p)
        } else {
            window.center()
        }
    }

    private func restore(_ layout: LayoutWindow) {
        var focusTargets: [Int: TerminalPane] = [:]
        for (i, t) in layout.tabs.enumerated() {
            let rootView = TabRootView.build(t.root)
            let item = TabItem(root: TabRootView(root: rootView), customTitle: t.title)
            let panes = item.root.panes
            let focusedIndex = t.root.terminals.firstIndex { $0.focused == true }
            if let fi = focusedIndex, fi < panes.count { focusTargets[i] = panes[fi] }
            item.lastFocused = focusTargets[i] ?? panes.first
            tabs.append(item)
        }
        selectTab(min(max(layout.activeTab ?? 0, 0), tabs.count - 1))
    }

    // MARK: Badge (broadcast indicator in the title bar)

    private func setUpBadge() {
        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 9
        badgeLabel.layer?.backgroundColor = (NSColor(hex: "#c80003") ?? .systemRed).cgColor
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        badgeLabel.frame = NSRect(x: 8, y: 5, width: 204, height: 18)
        holder.addSubview(badgeLabel)
        badgeAccessory.view = holder
        badgeAccessory.layoutAttribute = .trailing
        badgeAccessory.isHidden = true
        window?.addTitlebarAccessoryViewController(badgeAccessory)
    }

    private func updateBadge() {
        let model = AppModel.shared
        guard model.broadcast != .off, let sender = model.focusedPane, sender.controller === self else {
            badgeAccessory.isHidden = true
            return
        }
        let count = model.receivers(of: sender).count
        guard count > 0 else { badgeAccessory.isHidden = true; return }
        let scope = model.broadcast == .all ? "all" : "group \(sender.group ?? "")"
        badgeLabel.stringValue = "Broadcasting to \(scope) · \(count + 1) terminals"
        badgeLabel.sizeToFit()
        let w = min(320, badgeLabel.frame.width + 20)
        badgeLabel.frame = NSRect(x: 8, y: 5, width: w, height: 18)
        badgeAccessory.view.frame.size.width = w + 16
        badgeAccessory.isHidden = false
    }

    // MARK: Notifications

    @objc private func stateChanged() {
        updateBadge()
        updateWindowTitle()
        refreshTabBar()
    }

    @objc private func configChanged() {
        refreshTabBar()
        updateTranslucency()
    }

    func firstResponderChanged() {
        guard let tv = window?.firstResponder as? PaneTerminalView, let pane = tv.pane else { return }
        if let tab = tabs.first(where: { $0.root.panes.contains { $0 === pane } }) {
            tab.lastFocused = pane
        }
        AppModel.shared.stateChanged()
    }

    func windowDidBecomeKey(_ notification: Notification) { AppModel.shared.stateChanged() }
    func windowDidResignKey(_ notification: Notification) { AppModel.shared.stateChanged() }

    func updateTranslucency() {
        guard let window else { return }
        let translucent = allPanes.contains { $0.profile.opacity < 0.999 }
        window.isOpaque = !translucent
        window.backgroundColor = translucent ? .clear : .windowBackgroundColor
    }

    // MARK: Accessors

    var allPanes: [TerminalPane] { tabs.flatMap { $0.root.panes } }
    var activeTab: TabItem? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    var focusedPane: TerminalPane? {
        guard let tab = activeTab else { return nil }
        let panes = tab.root.panes
        if let tv = window?.firstResponder as? PaneTerminalView, let p = tv.pane, panes.contains(where: { $0 === p }) {
            return p
        }
        if let p = tab.lastFocused, panes.contains(where: { $0 === p }) { return p }
        return panes.first
    }

    // MARK: Titles

    func paneTitleChanged(_ pane: TerminalPane) {
        updateWindowTitle()
        refreshTabBar()
    }

    private func tabTitle(_ tab: TabItem) -> String {
        if let t = tab.customTitle, !t.isEmpty { return t }
        let panes = tab.root.panes
        let p = tab.lastFocused.flatMap { lf in panes.first { $0 === lf } } ?? panes.first
        return p?.displayTitle ?? "Terminal"
    }

    private func updateWindowTitle() {
        guard let window else { return }
        if let t = customWindowTitle, !t.isEmpty {
            window.title = t
        } else {
            window.title = focusedPane?.displayTitle ?? "Splitterm"
        }
    }

    private func refreshTabBar() {
        let hide = AppModel.shared.config.global.hideTabBarWhenSingle && tabs.count <= 1
        content.showsTabBar = !hide
        content.tabBar.update(titles: tabs.map(tabTitle), active: activeIndex)
    }

    // MARK: Tabs

    func addTab(root: NSView, title: String?, select: Bool = true) {
        let item = TabItem(root: TabRootView(root: root), customTitle: title)
        item.lastFocused = item.root.panes.first
        let index = tabs.isEmpty ? 0 : activeIndex + 1
        tabs.insert(item, at: index)
        if select { selectTab(index) } else { refreshTabBar() }
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        for v in content.host.subviews { v.removeFromSuperview() }
        activeIndex = index
        let root = tabs[index].root
        content.host.addSubview(root)
        root.frame = content.host.bounds
        root.autoresizingMask = [.width, .height]
        content.needsLayout = true
        refreshTabBar()
        let target = tabs[index].lastFocused ?? root.panes.first
        DispatchQueue.main.async { target?.focus() }
        updateWindowTitle()
        AppModel.shared.stateChanged()
    }

    func closeTab(at index: Int, force: Bool = false) {
        guard tabs.indices.contains(index) else { return }
        let panes = tabs[index].root.panes
        if !force {
            let running = panes.filter { $0.hasRunningChild }.count
            if (panes.count > 1 && AppModel.shared.config.global.confirmCloseMultiple) || running > 0 {
                let msg = running > 0 ? "\(running) terminal(s) are running a program." : "This tab has \(panes.count) terminals."
                guard Prompt.confirm(title: "Close this tab?", message: msg, okTitle: "Close Tab", destructive: true) else { return }
            }
        }
        for p in panes { dispose(p) }
        tabs[index].root.removeFromSuperview()
        tabs.remove(at: index)
        if tabs.isEmpty {
            closingConfirmed = true
            window?.close()
            return
        }
        selectTab(min(index, tabs.count - 1))
    }

    func moveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), tabs.indices.contains(to), from != to else { refreshTabBar(); return }
        let activeItem = activeTab
        let item = tabs.remove(at: from)
        tabs.insert(item, at: to)
        activeIndex = tabs.firstIndex(where: { $0 === activeItem }) ?? to
        selectTab(activeIndex)
    }

    func detachTab(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { NSSound.beep(); return }
        let item = tabs.remove(at: index)
        item.root.removeFromSuperview()
        selectTab(min(activeIndex >= index ? max(activeIndex - 1, 0) : activeIndex, tabs.count - 1))
        let wc = TerminalWindowController(adopting: item)
        AppModel.shared.windowControllers.append(wc)
        wc.showWindow(nil)
        wc.updateTranslucency()
    }

    // TabBarDelegate
    func tabBar(_ bar: TabBarView, select index: Int) { selectTab(index) }
    func tabBar(_ bar: TabBarView, close index: Int) { closeTab(at: index) }
    func tabBar(_ bar: TabBarView, rename index: Int) { promptTabTitle(index) }
    func tabBar(_ bar: TabBarView, move from: Int, to: Int) { moveTab(from: from, to: to) }
    func tabBar(_ bar: TabBarView, detach index: Int) { detachTab(at: index) }
    func tabBarNewTab(_ bar: TabBarView) { perform(.newTab) }

    private func promptTabTitle(_ index: Int) {
        guard tabs.indices.contains(index),
              let t = Prompt.text(title: "Tab Title", message: "Leave empty to follow the focused terminal.",
                                  defaultValue: tabs[index].customTitle ?? "") else { return }
        tabs[index].customTitle = t.isEmpty ? nil : t
        refreshTabBar()
    }

    // MARK: Splitting and closing

    func split(_ pane: TerminalPane, direction requested: SplitDirection?) {
        guard let tab = tabs.first(where: { $0.root.panes.contains { $0 === pane } }) else { return }
        tab.root.unzoom()
        let size = pane.bounds.size
        let direction = requested ?? (size.width >= size.height ? .right : .down)
        let cell = pane.cellSize
        let headerHeight = pane.profile.showTitlebar ? PaneHeaderView.height : 0
        let enough = direction == .right
            ? size.width >= 2 * (cell.width * 10) + SplitContainer.dividerThickness
            : size.height >= 2 * (cell.height * 3 + headerHeight) + SplitContainer.dividerThickness
        guard enough, let parent = pane.superview as? PaneParent else { NSSound.beep(); return }

        let newPane = TerminalPane(profile: pane.profileName, cwd: pane.currentDirectory,
                                   group: pane.profile.splitToGroup ? pane.group : nil)
        let placeholder = NSView()
        let oldFrame = pane.frame
        let split = SplitContainer(direction: direction, first: placeholder, second: newPane)
        parent.replaceChild(pane, with: split)
        split.replaceChild(placeholder, with: pane)
        split.frame = oldFrame
        split.layoutSubtreeIfNeeded()
        tab.lastFocused = newPane
        newPane.focus()
        AppModel.shared.stateChanged()
    }

    /// Closes one terminal and gives its space to its sibling.
    func closePane(_ pane: TerminalPane, force: Bool) {
        guard let tabIndex = tabs.firstIndex(where: { $0.root.panes.contains { $0 === pane } }) else { return }
        if !force, pane.hasRunningChild {
            guard Prompt.confirm(title: "Close this terminal?", message: "A program is still running in it.",
                                 okTitle: "Close", destructive: true) else { return }
        }
        let tab = tabs[tabIndex]
        tab.root.unzoom()
        if pane.superview === tab.root {
            closeTab(at: tabIndex, force: true)
            return
        }
        guard let split = pane.superview as? SplitContainer,
              let grandparent = split.superview as? PaneParent else { return }
        let sibling = split.other(than: pane)
        dispose(pane)
        grandparent.replaceChild(split, with: sibling)
        let next = sibling.descendantPanes.first
        tab.lastFocused = next
        if tabIndex == activeIndex { next?.focus() }
        AppModel.shared.stateChanged()
    }

    private func dispose(_ pane: TerminalPane) {
        pane.terminate()
        pane.removeFromSuperview()
        AppModel.shared.unregister(pane)
    }

    func closeGroup(_ group: String) {
        let model = AppModel.shared
        let victims = model.allPanes.filter { $0.group == group }
        guard !victims.isEmpty,
              Prompt.confirm(title: "Close \(victims.count) terminals in “\(group)”?",
                             message: "Their processes will be ended.", okTitle: "Close All", destructive: true)
        else { return }
        for p in victims { p.controller?.closePane(p, force: true) }
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingConfirmed { return true }
        let panes = allPanes
        let running = panes.filter { $0.hasRunningChild }.count
        if (panes.count > 1 && AppModel.shared.config.global.confirmCloseMultiple) || running > 0 {
            var msg = "This window has \(panes.count) terminal\(panes.count == 1 ? "" : "s")."
            if running > 0 { msg += " \(running) of them are running a program." }
            guard Prompt.confirm(title: "Close this window?", message: msg, okTitle: "Close Window", destructive: true)
            else { return false }
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        for p in allPanes { p.terminate(); AppModel.shared.unregister(p) }
        tabs.removeAll()
        AppModel.shared.windowClosed(self)
    }

    // MARK: Navigation

    func navigate(_ direction: NavigationDirection) {
        guard let tab = activeTab, let current = focusedPane else { return }
        tab.root.unzoom()
        let panes = tab.root.panes.filter { $0 !== current }
        let c = current.convert(current.bounds, to: tab.root)
        var best: (pane: TerminalPane, distance: CGFloat, offset: CGFloat)?
        for p in panes {
            let f = p.convert(p.bounds, to: tab.root)
            let overlapsY = f.minY < c.maxY - 1 && f.maxY > c.minY + 1
            let overlapsX = f.minX < c.maxX - 1 && f.maxX > c.minX + 1
            let distance: CGFloat
            let offset: CGFloat
            switch direction {
            case .left:
                guard overlapsY, f.maxX <= c.minX + 2 else { continue }
                distance = c.minX - f.maxX; offset = abs(f.midY - c.midY)
            case .right:
                guard overlapsY, f.minX >= c.maxX - 2 else { continue }
                distance = f.minX - c.maxX; offset = abs(f.midY - c.midY)
            case .up:
                guard overlapsX, f.maxY <= c.minY + 2 else { continue }
                distance = c.minY - f.maxY; offset = abs(f.midX - c.midX)
            case .down:
                guard overlapsX, f.minY >= c.maxY - 2 else { continue }
                distance = f.minY - c.maxY; offset = abs(f.midX - c.midX)
            }
            if best == nil || distance < best!.distance - 0.5 ||
                (abs(distance - best!.distance) <= 0.5 && offset < best!.offset) {
                best = (p, distance, offset)
            }
        }
        best?.pane.focus()
    }

    func cycleFocus(forward: Bool) {
        guard let tab = activeTab, let current = focusedPane else { return }
        tab.root.unzoom()
        let panes = tab.root.panes
        guard panes.count > 1, let i = panes.firstIndex(where: { $0 === current }) else { return }
        let next = (i + (forward ? 1 : -1) + panes.count) % panes.count
        panes[next].focus()
    }

    func resize(_ pane: TerminalPane, _ direction: NavigationDirection) {
        let wanted: SplitDirection = (direction == .left || direction == .right) ? .right : .down
        var view: NSView? = pane.superview
        while let v = view, !(v is TabRootView) {
            if let s = v as? SplitContainer, s.direction == wanted {
                let cell = pane.cellSize
                let step = wanted == .right ? cell.width : cell.height
                s.nudge(by: (direction == .left || direction == .up) ? -step : step)
                return
            }
            view = v.superview
        }
        NSSound.beep()
    }

    // MARK: Actions

    func perform(_ action: Action) {
        let model = AppModel.shared
        let pane = focusedPane
        switch action {
        case .splitRight: if let pane { split(pane, direction: .right) }
        case .splitDown: if let pane { split(pane, direction: .down) }
        case .splitAuto: if let pane { split(pane, direction: nil) }
        case .closeTerminal: if let pane { closePane(pane, force: false) }
        case .closeWindow: window?.performClose(nil)
        case .toggleZoom: if let pane { activeTab?.root.toggleZoom(pane) }
        case .rotateClockwise: activeTab?.root.rotate(clockwise: true); pane?.focus()
        case .rotateCounterClockwise: activeTab?.root.rotate(clockwise: false); pane?.focus()

        case .focusLeft: navigate(.left)
        case .focusRight: navigate(.right)
        case .focusUp: navigate(.up)
        case .focusDown: navigate(.down)
        case .focusNext: cycleFocus(forward: true)
        case .focusPrevious: cycleFocus(forward: false)

        case .resizeLeft: if let pane { resize(pane, .left) }
        case .resizeRight: if let pane { resize(pane, .right) }
        case .resizeUp: if let pane { resize(pane, .up) }
        case .resizeDown: if let pane { resize(pane, .down) }

        case .newTab:
            addTab(root: TerminalPane(profile: pane?.profileName, cwd: pane?.currentDirectory), title: nil)
        case .newWindow:
            model.newWindow(cwd: pane?.currentDirectory, profile: pane?.profileName)
        case .nextTab: if tabs.count > 1 { selectTab((activeIndex + 1) % tabs.count) }
        case .previousTab: if tabs.count > 1 { selectTab((activeIndex - 1 + tabs.count) % tabs.count) }
        case .moveTabRight: moveTab(from: activeIndex, to: activeIndex + 1)
        case .moveTabLeft: moveTab(from: activeIndex, to: activeIndex - 1)
        case .detachTab: detachTab(at: activeIndex)
        case .switchToTab1, .switchToTab2, .switchToTab3, .switchToTab4, .switchToTab5,
             .switchToTab6, .switchToTab7, .switchToTab8, .switchToTab9:
            if let i = action.tabIndex { selectTab(action == .switchToTab9 ? tabs.count - 1 : i) }

        case .broadcastOff: model.broadcast = .off
        case .broadcastGroup: model.broadcast = .group
        case .broadcastAll: model.broadcast = .all
        case .newGroup: pane?.promptNewGroup()
        case .groupAllInWindow: model.setGroup(model.nextGroupName(), for: allPanes)
        case .ungroupAllInWindow: model.setGroup(nil, for: allPanes)
        case .groupAllInTab: model.setGroup(model.nextGroupName(), for: activeTab?.root.panes ?? [])
        case .ungroupAllInTab: model.setGroup(nil, for: activeTab?.root.panes ?? [])
        case .insertNumber: insertNumbers(padded: false)
        case .insertPaddedNumber: insertNumbers(padded: true)

        case .zoomIn: pane?.zoomFont(1)
        case .zoomOut: pane?.zoomFont(-1)
        case .zoomNormal: pane?.zoomFont(0)
        case .zoomInAll: model.allPanes.forEach { $0.zoomFont(1) }
        case .zoomOutAll: model.allPanes.forEach { $0.zoomFont(-1) }
        case .zoomNormalAll: model.allPanes.forEach { $0.zoomFont(0) }

        case .editTerminalTitle: pane?.promptTitle()
        case .editTabTitle: promptTabTitle(activeIndex)
        case .editWindowTitle:
            if let t = Prompt.text(title: "Window Title", message: "Leave empty to follow the focused terminal.",
                                   defaultValue: customWindowTitle ?? "") {
                customWindowTitle = t.isEmpty ? nil : t
            }
        case .nextProfile, .previousProfile:
            guard let pane else { return }
            let names = model.config.sortedProfileNames
            guard names.count > 1, let i = names.firstIndex(of: pane.profileName) else { return }
            let step = action == .nextProfile ? 1 : -1
            pane.setProfile(names[(i + step + names.count) % names.count])
        case .resetTerminal:
            pane?.terminalView.getTerminal().resetToInitialState()
            pane?.terminalView.needsDisplay = true
        case .resetAndClear:
            guard let pane else { return }
            pane.terminalView.getTerminal().resetToInitialState()
            pane.terminalView.needsDisplay = true
            pane.sendText("\u{0c}")   // Ctrl-L: let the shell redraw its prompt

        case .layoutLauncher, .saveLayout, .preferences, .preferencesKeybindings:
            (NSApp.delegate as? AppDelegate)?.performAppAction(action)
        }
    }

    /// Types each target terminal's own number (1, 2, 3…) — Terminator's insert_number.
    private func insertNumbers(padded: Bool) {
        guard let pane = focusedPane else { return }
        let model = AppModel.shared
        let all = model.allPanes
        let width = String(all.count).count
        for target in model.targets(of: pane) {
            guard let i = all.firstIndex(where: { $0 === target }) else { continue }
            let n = String(i + 1)
            let text = padded ? String(repeating: "0", count: max(0, width - n.count)) + n : n
            target.sendText(text)
        }
    }

    // MARK: Layouts

    func describeLayout() -> LayoutWindow {
        let frame = window?.frame ?? .zero
        let isFull = window?.styleMask.contains(.fullScreen) ?? false
        return LayoutWindow(
            frame: [frame.minX, frame.minY, frame.width, frame.height].map { ($0).rounded() },
            maximized: (window?.isZoomed ?? false) && !isFull ? true : nil,
            fullScreen: isFull ? true : nil,
            title: customWindowTitle,
            activeTab: activeIndex,
            tabs: tabs.map { LayoutTab(title: $0.customTitle, root: $0.root.describe(focused: $0.lastFocused)) })
    }
}
