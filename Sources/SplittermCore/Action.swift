import Foundation

/// Every user-invokable command. Raw values are the names used in the config file,
/// following Terminator's naming where an equivalent exists.
public enum Action: String, CaseIterable, Codable, Sendable {
    // Splits and terminals
    case splitRight = "split_right"
    case splitDown = "split_down"
    case splitAuto = "split_auto"
    case closeTerminal = "close_term"
    case closeWindow = "close_window"
    case toggleZoom = "toggle_zoom"
    case rotateClockwise = "rotate_cw"
    case rotateCounterClockwise = "rotate_ccw"

    // Focus
    case focusLeft = "go_left"
    case focusRight = "go_right"
    case focusUp = "go_up"
    case focusDown = "go_down"
    case focusNext = "go_next"
    case focusPrevious = "go_prev"

    // Resize
    case resizeLeft = "resize_left"
    case resizeRight = "resize_right"
    case resizeUp = "resize_up"
    case resizeDown = "resize_down"

    // Tabs and windows
    case newTab = "new_tab"
    case newWindow = "new_window"
    case nextTab = "next_tab"
    case previousTab = "prev_tab"
    case moveTabRight = "move_tab_right"
    case moveTabLeft = "move_tab_left"
    case detachTab = "detach_tab"
    case switchToTab1 = "switch_to_tab_1"
    case switchToTab2 = "switch_to_tab_2"
    case switchToTab3 = "switch_to_tab_3"
    case switchToTab4 = "switch_to_tab_4"
    case switchToTab5 = "switch_to_tab_5"
    case switchToTab6 = "switch_to_tab_6"
    case switchToTab7 = "switch_to_tab_7"
    case switchToTab8 = "switch_to_tab_8"
    case switchToTab9 = "switch_to_tab_9"

    // Broadcast and groups
    case broadcastOff = "broadcast_off"
    case broadcastGroup = "broadcast_group"
    case broadcastAll = "broadcast_all"
    case newGroup = "create_group"
    case groupAllInWindow = "group_win"
    case ungroupAllInWindow = "ungroup_win"
    case groupAllInTab = "group_tab"
    case ungroupAllInTab = "ungroup_tab"
    case insertNumber = "insert_number"
    case insertPaddedNumber = "insert_padded"

    // Font zoom
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case zoomNormal = "zoom_normal"
    case zoomInAll = "zoom_in_all"
    case zoomOutAll = "zoom_out_all"
    case zoomNormalAll = "zoom_normal_all"

    // Titles, profiles, terminal state
    case editTerminalTitle = "edit_terminal_title"
    case editTabTitle = "edit_tab_title"
    case editWindowTitle = "edit_window_title"
    case nextProfile = "next_profile"
    case previousProfile = "previous_profile"
    case resetTerminal = "reset"
    case resetAndClear = "reset_clear"

    // Layouts and app
    case layoutLauncher = "layout_launcher"
    case saveLayout = "save_layout"
    case preferences = "preferences"
    case preferencesKeybindings = "preferences_keybindings"

    public var title: String {
        switch self {
        case .splitRight: return "Split Right"
        case .splitDown: return "Split Down"
        case .splitAuto: return "Split Along Longer Side"
        case .closeTerminal: return "Close Terminal"
        case .closeWindow: return "Close Window"
        case .toggleZoom: return "Zoom Terminal"
        case .rotateClockwise: return "Rotate Clockwise"
        case .rotateCounterClockwise: return "Rotate Counterclockwise"
        case .focusLeft: return "Focus Left"
        case .focusRight: return "Focus Right"
        case .focusUp: return "Focus Up"
        case .focusDown: return "Focus Down"
        case .focusNext: return "Next Terminal"
        case .focusPrevious: return "Previous Terminal"
        case .resizeLeft: return "Move Divider Left"
        case .resizeRight: return "Move Divider Right"
        case .resizeUp: return "Move Divider Up"
        case .resizeDown: return "Move Divider Down"
        case .newTab: return "New Tab"
        case .newWindow: return "New Window"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .moveTabRight: return "Move Tab Right"
        case .moveTabLeft: return "Move Tab Left"
        case .detachTab: return "Move Tab to New Window"
        case .switchToTab1, .switchToTab2, .switchToTab3, .switchToTab4, .switchToTab5,
             .switchToTab6, .switchToTab7, .switchToTab8, .switchToTab9:
            return "Go to Tab \(tabIndex! + 1)"
        case .broadcastOff: return "Broadcast Off"
        case .broadcastGroup: return "Broadcast to Group"
        case .broadcastAll: return "Broadcast to All"
        case .newGroup: return "New Group…"
        case .groupAllInWindow: return "Group All in Window"
        case .ungroupAllInWindow: return "Ungroup All in Window"
        case .groupAllInTab: return "Group All in Tab"
        case .ungroupAllInTab: return "Ungroup All in Tab"
        case .insertNumber: return "Insert Terminal Number"
        case .insertPaddedNumber: return "Insert Padded Terminal Number"
        case .zoomIn: return "Bigger Font"
        case .zoomOut: return "Smaller Font"
        case .zoomNormal: return "Default Font Size"
        case .zoomInAll: return "Bigger Font (All)"
        case .zoomOutAll: return "Smaller Font (All)"
        case .zoomNormalAll: return "Default Font Size (All)"
        case .editTerminalTitle: return "Edit Terminal Title…"
        case .editTabTitle: return "Edit Tab Title…"
        case .editWindowTitle: return "Edit Window Title…"
        case .nextProfile: return "Next Profile"
        case .previousProfile: return "Previous Profile"
        case .resetTerminal: return "Reset Terminal"
        case .resetAndClear: return "Reset and Clear"
        case .layoutLauncher: return "Layout Launcher…"
        case .saveLayout: return "Save Layout…"
        case .preferences: return "Settings…"
        case .preferencesKeybindings: return "Keybinding Settings…"
        }
    }

    /// Zero-based tab index for the switch_to_tab actions.
    public var tabIndex: Int? {
        switch self {
        case .switchToTab1: return 0
        case .switchToTab2: return 1
        case .switchToTab3: return 2
        case .switchToTab4: return 3
        case .switchToTab5: return 4
        case .switchToTab6: return 5
        case .switchToTab7: return 6
        case .switchToTab8: return 7
        case .switchToTab9: return 8
        default: return nil
        }
    }

    /// Default macOS shortcuts. Empty string means unbound, as in Terminator.
    public static let defaultBindings: [Action: String] = [
        .splitRight: "cmd+d",
        .splitDown: "cmd+shift+d",
        .splitAuto: "cmd+opt+d",
        .closeTerminal: "cmd+w",
        .closeWindow: "cmd+shift+w",
        .toggleZoom: "cmd+shift+return",
        .rotateClockwise: "cmd+opt+r",
        .rotateCounterClockwise: "cmd+opt+shift+r",
        .focusLeft: "cmd+opt+left",
        .focusRight: "cmd+opt+right",
        .focusUp: "cmd+opt+up",
        .focusDown: "cmd+opt+down",
        .focusNext: "cmd+]",
        .focusPrevious: "cmd+[",
        .resizeLeft: "cmd+ctrl+left",
        .resizeRight: "cmd+ctrl+right",
        .resizeUp: "cmd+ctrl+up",
        .resizeDown: "cmd+ctrl+down",
        .newTab: "cmd+t",
        .newWindow: "cmd+n",
        .nextTab: "cmd+shift+]",
        .previousTab: "cmd+shift+[",
        .moveTabRight: "cmd+opt+shift+]",
        .moveTabLeft: "cmd+opt+shift+[",
        .detachTab: "",
        .switchToTab1: "cmd+1", .switchToTab2: "cmd+2", .switchToTab3: "cmd+3",
        .switchToTab4: "cmd+4", .switchToTab5: "cmd+5", .switchToTab6: "cmd+6",
        .switchToTab7: "cmd+7", .switchToTab8: "cmd+8", .switchToTab9: "cmd+9",
        .broadcastOff: "cmd+opt+o",
        .broadcastGroup: "cmd+opt+g",
        .broadcastAll: "cmd+opt+a",
        .newGroup: "",
        .groupAllInWindow: "cmd+ctrl+g",
        .ungroupAllInWindow: "cmd+ctrl+shift+g",
        .groupAllInTab: "cmd+ctrl+t",
        .ungroupAllInTab: "cmd+ctrl+shift+t",
        .insertNumber: "cmd+ctrl+1",
        .insertPaddedNumber: "cmd+ctrl+0",
        .zoomIn: "cmd+=",
        .zoomOut: "cmd+-",
        .zoomNormal: "cmd+0",
        .zoomInAll: "",
        .zoomOutAll: "",
        .zoomNormalAll: "",
        .editTerminalTitle: "cmd+ctrl+x",
        .editTabTitle: "cmd+ctrl+a",
        .editWindowTitle: "cmd+ctrl+w",
        .nextProfile: "",
        .previousProfile: "",
        .resetTerminal: "cmd+opt+shift+k",
        .resetAndClear: "cmd+k",
        .layoutLauncher: "cmd+shift+l",
        .saveLayout: "cmd+shift+s",
        .preferences: "cmd+,",
        .preferencesKeybindings: "",
    ]
}

/// Resolves the effective shortcut table from defaults plus user overrides.
public struct KeyBindingTable: Sendable {
    public private(set) var byAction: [Action: Shortcut] = [:]
    public private(set) var byShortcut: [Shortcut: Action] = [:]
    /// Shortcuts claimed by more than one action (the later action in `Action.allCases` loses).
    public private(set) var conflicts: [Shortcut: [Action]] = [:]

    public init(overrides: [String: String]) {
        for action in Action.allCases {
            let raw = overrides[action.rawValue] ?? Action.defaultBindings[action] ?? ""
            guard let sc = Shortcut(raw) else { continue }
            if let existing = byShortcut[sc] {
                conflicts[sc, default: [existing]].append(action)
                continue
            }
            byAction[action] = sc
            byShortcut[sc] = action
        }
    }
}
