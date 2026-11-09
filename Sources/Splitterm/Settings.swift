import AppKit
import SwiftUI
import SplittermCore

enum SettingsTab: Hashable { case general, profiles, keybindings, layouts }

/// Bridges the settings UI to `AppModel`; every edit is applied and saved immediately.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            guard !syncing, config != oldValue else { return }
            AppModel.shared.apply(config)
        }
    }
    @Published var tab: SettingsTab = .general
    @Published var selectedProfile: String = "default"
    @Published var selectedLayout: String?
    @Published var recording: Action?
    @Published var keyFilter = ""

    private var syncing = false
    private var recorderMonitor: Any?

    init() {
        config = AppModel.shared.config
        NotificationCenter.default.addObserver(self, selector: #selector(external),
                                               name: .splittermConfigChanged, object: nil)
    }

    @objc private func external() {
        let latest = AppModel.shared.config
        guard latest != config else { return }
        syncing = true
        config = latest
        syncing = false
        if config.profiles[selectedProfile] == nil { selectedProfile = "default" }
        if let l = selectedLayout, config.layouts[l] == nil { selectedLayout = nil }
    }

    // MARK: Profiles

    var profileBinding: Binding<Profile> {
        Binding(get: { [unowned self] in self.config.profiles[self.selectedProfile] ?? Profile() },
                set: { [unowned self] in self.config.profiles[self.selectedProfile] = $0 })
    }

    func addProfile(duplicating: Bool) {
        let base = duplicating ? (config.profiles[selectedProfile] ?? Profile()) : Profile()
        guard let name = Prompt.text(title: duplicating ? "Duplicate Profile" : "New Profile",
                                     defaultValue: duplicating ? "\(selectedProfile) copy" : "profile"),
              !name.isEmpty else { return }
        guard config.profiles[name] == nil else {
            Prompt.error("A profile named “\(name)” already exists", "Choose another name.")
            return
        }
        config.profiles[name] = base
        selectedProfile = name
    }

    func deleteSelectedProfile() {
        let name = selectedProfile
        guard name != "default",
              Prompt.confirm(title: "Delete profile “\(name)”?",
                             message: "Terminals using it switch to the default profile.",
                             okTitle: "Delete", destructive: true) else { return }
        selectedProfile = "default"
        config.profiles[name] = nil
    }

    // MARK: Keybindings

    func shortcut(for action: Action) -> Shortcut? {
        let raw = config.keybindings[action.rawValue] ?? Action.defaultBindings[action] ?? ""
        return Shortcut(raw)
    }

    func set(_ shortcut: Shortcut?, for action: Action) {
        let value = shortcut?.description ?? ""
        if value == (Action.defaultBindings[action] ?? "") {
            config.keybindings[action.rawValue] = nil
        } else {
            config.keybindings[action.rawValue] = value
        }
    }

    var conflicts: Set<Action> {
        var seen: [Shortcut: Action] = [:]
        var result = Set<Action>()
        for a in Action.allCases {
            guard let sc = shortcut(for: a) else { continue }
            if let other = seen[sc] { result.insert(a); result.insert(other) } else { seen[sc] = a }
        }
        return result
    }

    static let reserved: [String: String] = [
        "cmd+q": "Quit", "cmd+h": "Hide", "cmd+m": "Minimize", "cmd+c": "Copy", "cmd+v": "Paste",
        "cmd+a": "Select All", "cmd+tab": "the app switcher", "cmd+space": "Spotlight",
        "cmd+`": "window cycling", "cmd+opt+h": "Hide Others", "cmd+ctrl+f": "Full Screen",
    ]

    func startRecording(_ action: Action) {
        stopRecording()
        recording = action
        KeyDispatcher.shared.suspended = true
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.recording else { return event }
            let mods = KeyModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            if event.keyCode == 0x35, mods.isEmpty {          // Escape cancels
                self.stopRecording(); return nil
            }
            if (event.keyCode == 0x33 || event.keyCode == 0x75), mods.isEmpty {   // Delete unbinds
                self.set(nil, for: action); self.stopRecording(); return nil
            }
            guard let sc = Shortcut(event: event) else { NSSound.beep(); return nil }
            let isFunctionKey = sc.key.hasPrefix("f") && sc.key.count > 1
            guard !mods.subtracting(.shift).isEmpty || isFunctionKey else {
                NSSound.beep()   // plain keys must reach the terminal
                return nil
            }
            self.set(sc, for: action)
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m) }
        recorderMonitor = nil
        recording = nil
        KeyDispatcher.shared.suspended = false
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel

    init() {
        let model = SettingsModel()
        self.model = model
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Splitterm Settings"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(tab: SettingsTab) {
        model.tab = tab
        if !(window?.isVisible ?? false) { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { model.stopRecording() }
}

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ProfilesSettingsView(model: model)
                .tabItem { Label("Profiles", systemImage: "paintpalette") }
                .tag(SettingsTab.profiles)
            KeybindingsSettingsView(model: model)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(SettingsTab.keybindings)
            LayoutsSettingsView(model: model)
                .tabItem { Label("Layouts", systemImage: "rectangle.split.3x1") }
                .tag(SettingsTab.layouts)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 500)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Broadcast") {
                Picker("Mode at launch", selection: $model.config.global.broadcastDefault) {
                    ForEach(BroadcastMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper(value: $model.config.global.confirmBroadcastReturnAt, in: 0...200) {
                    Text(model.config.global.confirmBroadcastReturnAt == 0
                         ? "Never ask before broadcasting Return"
                         : "Ask before sending Return to \(model.config.global.confirmBroadcastReturnAt)+ receivers")
                }
                Toggle("Forget groups when their last terminal closes", isOn: $model.config.global.autocleanGroups)
            }
            Section("Windows") {
                Toggle("Hide the tab bar when a window has one tab", isOn: $model.config.global.hideTabBarWhenSingle)
                Toggle("Ask before closing several terminals at once", isOn: $model.config.global.confirmCloseMultiple)
                Toggle("Focus follows mouse", isOn: $model.config.global.focusFollowsMouse)
                TextField("Layout to open at launch", text: $model.config.global.startupLayout)
            }
            Section("Config") {
                Text(ConfigStore.fileURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Open Config File") { (NSApp.delegate as? AppDelegate)?.openConfigFile(nil) }
                    Button("Import Terminator Config…") { (NSApp.delegate as? AppDelegate)?.importTerminatorConfig(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProfilesSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                List(selection: Binding<String?>(get: { model.selectedProfile },
                                                 set: { if let v = $0 { model.selectedProfile = v } })) {
                    ForEach(model.config.sortedProfileNames, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                .frame(width: 170)
                HStack {
                    Button { model.addProfile(duplicating: false) } label: { Image(systemName: "plus") }
                        .help("New profile")
                    Button { model.addProfile(duplicating: true) } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate profile")
                    Button { model.deleteSelectedProfile() } label: { Image(systemName: "minus") }
                        .help("Delete profile")
                        .disabled(model.selectedProfile == "default")
                    Spacer()
                }
            }
            ProfileEditor(profile: model.profileBinding)
        }
    }
}

struct ProfileEditor: View {
    @Binding var profile: Profile
    private static let monospacedFamilies: [String] = {
        let fm = NSFontManager.shared
        return fm.availableFontFamilies.filter { family in
            guard let member = fm.availableMembers(ofFontFamily: family)?.first,
                  let postScript = member.first as? String,
                  let font = NSFont(name: postScript, size: 12) else { return false }
            return font.isFixedPitch
        }
    }()

    var body: some View {
        Form {
            Section("Text") {
                Picker("Font", selection: $profile.fontName) {
                    Text("System monospaced (SF Mono)").tag("")
                    ForEach(Self.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                    if !profile.fontName.isEmpty && !Self.monospacedFamilies.contains(profile.fontName) {
                        Text(profile.fontName).tag(profile.fontName)
                    }
                }
                Stepper(value: $profile.fontSize, in: 6...48, step: 1) {
                    Text("Size: \(Int(profile.fontSize)) pt")
                }
                Picker("Cursor", selection: $profile.cursorShape) {
                    Text("Block").tag(CursorShape.block)
                    Text("Underline").tag(CursorShape.underline)
                    Text("Bar").tag(CursorShape.beam)
                }
                Toggle("Blinking cursor", isOn: $profile.cursorBlink)
            }
            Section("Colours") {
                ColorPicker("Text", selection: colour($profile.foreground), supportsOpacity: false)
                ColorPicker("Background", selection: colour($profile.background), supportsOpacity: false)
                ColorPicker("Cursor", selection: colour($profile.cursorColor), supportsOpacity: false)
                ColorPicker("Selection", selection: colour($profile.selectionColor), supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Palette")
                    paletteRow(0..<8)
                    paletteRow(8..<16)
                }
                HStack {
                    Text("Window opacity")
                    Slider(value: $profile.opacity, in: 0.3...1)
                    Text("\(Int(profile.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Section("Shell") {
                Toggle("Run as a login shell", isOn: $profile.loginShell)
                TextField("Custom command (replaces the shell)", text: $profile.customCommand)
                Picker("When the shell exits", selection: $profile.exitAction) {
                    Text("Close the terminal").tag(ExitAction.close)
                    Text("Keep it open").tag(ExitAction.hold)
                    Text("Restart the shell").tag(ExitAction.restart)
                }
                TextField("Scrollback lines", value: $profile.scrollbackLines, format: .number)
            }
            Section("Behaviour") {
                Toggle("Show the title bar with the group button", isOn: $profile.showTitlebar)
                Toggle("New splits join the current group", isOn: $profile.splitToGroup)
                Toggle("Use Option as Meta key", isOn: $profile.optionAsMeta)
                Toggle("Copy text when selected", isOn: $profile.copyOnSelect)
            }
        }
        .formStyle(.grouped)
    }

    private func paletteRow(_ range: Range<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { i in
                ColorPicker("", selection: colour($profile.palette[i]), supportsOpacity: false)
                    .labelsHidden()
                    .help(i < 8 ? "Colour \(i)" : "Bright colour \(i - 8)")
            }
        }
    }

    private func colour(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: hex.wrappedValue) ?? .black) },
                set: { hex.wrappedValue = NSColor($0).hexString })
    }
}

struct KeybindingsSettingsView: View {
    @ObservedObject var model: SettingsModel

    private var actions: [Action] {
        let f = model.keyFilter.lowercased()
        return Action.allCases.filter { f.isEmpty || $0.title.lowercased().contains(f) || $0.rawValue.contains(f) }
    }

    var body: some View {
        let conflicts = model.conflicts
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter actions", text: $model.keyFilter).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Spacer()
                Button("Reset All to Defaults") { model.config.keybindings = [:] }
            }
            Text("Click a shortcut, then press the new keys. Esc cancels, Delete unbinds. Unbound keys always go to the terminal.")
                .font(.caption).foregroundStyle(.secondary)
            List(actions, id: \.self) { action in
                KeybindingRow(model: model, action: action, conflicting: conflicts.contains(action))
            }
        }
    }
}

struct KeybindingRow: View {
    @ObservedObject var model: SettingsModel
    let action: Action
    let conflicting: Bool

    var body: some View {
        let sc = model.shortcut(for: action)
        let reservedFor = sc.flatMap { SettingsModel.reserved[$0.description] }
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                if conflicting {
                    Text("Same shortcut as another action").font(.caption).foregroundStyle(.red)
                } else if let reservedFor {
                    Text("Overrides \(reservedFor)").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                if model.recording == action { model.stopRecording() } else { model.startRecording(action) }
            } label: {
                Text(model.recording == action ? "Press keys…" : (sc?.displayString ?? "—"))
                    .frame(minWidth: 110)
                    .monospaced()
            }
            Button {
                model.set(Shortcut(Action.defaultBindings[action] ?? ""), for: action)
            } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .help("Restore default")
                .disabled(model.config.keybindings[action.rawValue] == nil)
        }
    }
}

struct LayoutsSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                List(selection: $model.selectedLayout) {
                    ForEach(model.config.sortedLayoutNames, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(width: 170)
                HStack {
                    Button("Save Current…") { (NSApp.delegate as? AppDelegate)?.saveLayoutPrompt() }
                    Spacer()
                }
            }
            if let name = model.selectedLayout, let layout = model.config.layouts[name] {
                LayoutEditor(model: model, name: name, layout: layout)
            } else {
                VStack {
                    Spacer()
                    Text("Arrange windows, tabs and splits, then choose Save Current… to keep them as a layout.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

struct LayoutEditor: View {
    @ObservedObject var model: SettingsModel
    let name: String
    let layout: LayoutFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.title3.weight(.semibold))
                Spacer()
                Button("Launch") { AppModel.shared.launchLayout(named: name) }
                Button("Delete…", role: .destructive) {
                    if Prompt.confirm(title: "Delete layout “\(name)”?", message: "This can't be undone.",
                                      okTitle: "Delete", destructive: true) {
                        model.selectedLayout = nil
                        model.config.layouts[name] = nil
                    }
                }
            }
            Text("Commands are typed into each terminal's shell after it starts. Folders starting with ~ are relative to your home folder.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                ForEach(Array(layout.windows.indices), id: \.self) { w in
                    ForEach(Array(layout.windows[w].tabs.indices), id: \.self) { t in
                        Section("Window \(w + 1) · Tab \(t + 1)\(layout.windows[w].tabs[t].title.map { " · \($0)" } ?? "")") {
                            ForEach(Array(layout.windows[w].tabs[t].root.terminals.indices), id: \.self) { i in
                                TerminalSpecEditor(spec: binding(w, t, i), index: i,
                                                   profiles: model.config.sortedProfileNames)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func binding(_ w: Int, _ t: Int, _ i: Int) -> Binding<LayoutTerminal> {
        let name = self.name
        let model = self.model
        return Binding(
            get: { model.config.layouts[name]?.windows[w].tabs[t].root.terminals[i] ?? LayoutTerminal() },
            set: { newValue in
                guard var l = model.config.layouts[name] else { return }
                l.windows[w].tabs[t].root = l.windows[w].tabs[t].root.replacingTerminal(at: i, with: newValue)
                model.config.layouts[name] = l
            })
    }
}

struct TerminalSpecEditor: View {
    @Binding var spec: LayoutTerminal
    let index: Int
    let profiles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal \(index + 1)\(spec.title.map { " — \($0)" } ?? "")").font(.headline)
            TextField("Command", text: optional($spec.command))
            TextField("Folder", text: optional($spec.cwd))
            HStack {
                Picker("Profile", selection: Binding(get: { spec.profile ?? "default" },
                                                     set: { spec.profile = $0 == "default" ? nil : $0 })) {
                    ForEach(profiles, id: \.self) { Text($0).tag($0) }
                }
                TextField("Group", text: optional($spec.group))
            }
        }
        .padding(.vertical, 2)
    }

    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" },
                set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
