import AppKit
import SplittermCore

/// Routes configured shortcuts to actions before the terminal sees the key,
/// so unbound keys always reach the shell (vim, tmux, emacs keep working).
@MainActor
final class KeyDispatcher {
    static let shared = KeyDispatcher()
    private var monitor: Any?
    /// Set while the keybinding recorder in Settings is capturing a shortcut.
    var suspended = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !suspended,
              let wc = NSApp.keyWindow?.windowController as? TerminalWindowController,
              event.window === wc.window,
              let shortcut = Shortcut(event: event),
              let action = AppModel.shared.bindings.byShortcut[shortcut]
        else { return event }
        wc.perform(action)
        return nil
    }
}

/// Builds the main menu. Shortcut labels come from the live keybinding table;
/// the keys themselves are handled by `KeyDispatcher` while a terminal window is key.
@MainActor
enum MainMenu {
    static func item(for action: Action, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? action.title,
                              action: #selector(AppDelegate.menuAction(_:)), keyEquivalent: "")
        item.representedObject = action.rawValue
        item.target = NSApp.delegate
        if let sc = AppModel.shared.bindings.byAction[action] {
            item.keyEquivalent = sc.menuKeyEquivalent
            item.keyEquivalentModifierMask = sc.modifiers.eventFlags
        }
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        top.submenu = menu
        return top
    }

    private static func plain(_ title: String, _ selector: Selector?, _ key: String = "",
                              _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = target
        return item
    }

    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = "Splitterm"
        let delegate = NSApp.delegate as AnyObject?

        main.addItem(submenu(appName, [
            plain("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item(for: .preferences),
            plain("Open Config File", #selector(AppDelegate.openConfigFile(_:)), "", [], target: delegate),
            plain("Import Terminator Config…", #selector(AppDelegate.importTerminatorConfig(_:)), "", [], target: delegate),
            plain("Secure Keyboard Entry", #selector(AppDelegate.toggleSecureKeyboard(_:)), "", [], target: delegate),
            .separator(),
            servicesItem(),
            .separator(),
            plain("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            plain("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            plain("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", []),
            .separator(),
            plain("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("Shell", [
            item(for: .newWindow), item(for: .newTab),
            .separator(),
            item(for: .splitRight), item(for: .splitDown), item(for: .splitAuto),
            .separator(),
            item(for: .closeTerminal), item(for: .closeWindow),
            .separator(),
            item(for: .layoutLauncher), item(for: .saveLayout),
        ]))

        main.addItem(submenu("Edit", [
            plain("Copy", #selector(NSText.copy(_:)), "c"),
            plain("Paste", #selector(NSText.paste(_:)), "v"),
            plain("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item(for: .resetTerminal), item(for: .resetAndClear),
            .separator(),
            item(for: .editTerminalTitle), item(for: .editTabTitle), item(for: .editWindowTitle),
        ]))

        main.addItem(submenu("View", [
            item(for: .toggleZoom),
            item(for: .rotateClockwise), item(for: .rotateCounterClockwise),
            .separator(),
            item(for: .zoomIn), item(for: .zoomOut), item(for: .zoomNormal),
            item(for: .zoomInAll), item(for: .zoomOutAll), item(for: .zoomNormalAll),
            .separator(),
            item(for: .nextProfile), item(for: .previousProfile),
            .separator(),
            plain("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("Broadcast", [
            item(for: .broadcastOff), item(for: .broadcastGroup), item(for: .broadcastAll),
            .separator(),
            item(for: .newGroup),
            item(for: .groupAllInTab), item(for: .ungroupAllInTab),
            item(for: .groupAllInWindow), item(for: .ungroupAllInWindow),
            .separator(),
            item(for: .insertNumber), item(for: .insertPaddedNumber),
        ]))

        let tabItems: [Action] = [.switchToTab1, .switchToTab2, .switchToTab3, .switchToTab4, .switchToTab5,
                                  .switchToTab6, .switchToTab7, .switchToTab8, .switchToTab9]
        let windowMenu = submenu("Window", [
            plain("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            plain("Zoom", #selector(NSWindow.performZoom(_:)), "", []),
            .separator(),
            item(for: .focusLeft), item(for: .focusRight), item(for: .focusUp), item(for: .focusDown),
            item(for: .focusNext), item(for: .focusPrevious),
            .separator(),
            item(for: .resizeLeft), item(for: .resizeRight), item(for: .resizeUp), item(for: .resizeDown),
            .separator(),
            item(for: .nextTab), item(for: .previousTab), item(for: .moveTabLeft), item(for: .moveTabRight),
            item(for: .detachTab),
            submenu("Go to Tab", tabItems.map { item(for: $0, title: $0 == .switchToTab9 ? "Last Tab" : nil) }),
            .separator(),
            plain("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "", []),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        let helpMenu = submenu("Help", [
            plain("Splitterm Help", #selector(AppDelegate.openHelp(_:)), "?", [.command], target: delegate),
            item(for: .preferencesKeybindings, title: "Keyboard Shortcuts…"),
        ])
        main.addItem(helpMenu)
        NSApp.helpMenu = helpMenu.submenu
        return main
    }

    private static func servicesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Services")
        item.submenu = menu
        NSApp.servicesMenu = menu
        return item
    }
}
