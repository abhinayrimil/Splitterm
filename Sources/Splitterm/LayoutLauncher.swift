import AppKit
import SplittermCore

/// Searchable list of saved layouts: type to filter, arrows to move, Return to launch.
final class LayoutLauncherController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let table = NSTableView()
    private let launchButton = NSButton(title: "Launch", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete…", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Current…", target: nil, action: nil)
    private var names: [String] = []

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = "Layouts"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 300, height: 240)
        super.init(window: panel)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .splittermConfigChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        search.placeholderString = "Filter layouts"
        search.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 36
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(launch)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        launchButton.target = self
        launchButton.action = #selector(launch)
        launchButton.keyEquivalent = "\r"
        launchButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteLayout)
        deleteButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveCurrent)
        saveButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [saveButton, deleteButton, NSView(), launchButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        for v in [search, scroll, buttons] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    func show() {
        reload()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
    }

    @objc private func reload() {
        let filter = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        names = AppModel.shared.config.sortedLayoutNames.filter { filter.isEmpty || $0.lowercased().contains(filter) }
        table.reloadData()
        if !names.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateButtons()
    }

    private func updateButtons() {
        let has = table.selectedRow >= 0 && table.selectedRow < names.count
        launchButton.isEnabled = has
        deleteButton.isEnabled = has
        saveButton.isEnabled = !AppModel.shared.windowControllers.isEmpty
    }

    private var selectedName: String? {
        let r = table.selectedRow
        return names.indices.contains(r) ? names[r] : nil
    }

    @objc private func launch() {
        guard let name = selectedName else { return }
        window?.orderOut(nil)
        AppModel.shared.launchLayout(named: name)
    }

    @objc private func deleteLayout() {
        guard let name = selectedName,
              Prompt.confirm(title: "Delete layout “\(name)”?", message: "This can't be undone.",
                             okTitle: "Delete", destructive: true) else { return }
        AppModel.shared.update { $0.layouts[name] = nil }
    }

    @objc private func saveCurrent() {
        (NSApp.delegate as? AppDelegate)?.saveLayoutPrompt()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { names.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = names[row]
        let layout = AppModel.shared.config.layouts[name]
        let windows = layout?.windows.count ?? 0
        let terminals = layout?.windows.reduce(0) { $0 + $1.tabs.reduce(0) { $0 + $1.root.terminals.count } } ?? 0

        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 13, weight: name == "default" ? .semibold : .regular)
        let detail = NSTextField(labelWithString: "\(windows) window\(windows == 1 ? "" : "s") · \(terminals) terminal\(terminals == 1 ? "" : "s")")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // MARK: Search field keyboard handling

    func controlTextDidChange(_ obj: Notification) { reload() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            launch(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.orderOut(nil); return true
        default:
            return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !names.isEmpty else { return }
        let next = min(max(table.selectedRow + delta, 0), names.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }
}
