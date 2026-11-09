import AppKit

@MainActor
protocol TabBarDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, select index: Int)
    func tabBar(_ bar: TabBarView, close index: Int)
    func tabBar(_ bar: TabBarView, rename index: Int)
    func tabBar(_ bar: TabBarView, move from: Int, to: Int)
    func tabBar(_ bar: TabBarView, detach index: Int)
    func tabBarNewTab(_ bar: TabBarView)
}

/// A simple custom tab strip: click to select, double-click to rename,
/// drag to reorder, right-click for more.
final class TabBarView: NSView {
    static let height: CGFloat = 30
    weak var delegate: TabBarDelegate?
    private var buttons: [TabButton] = []
    private let addButton = NSButton()
    private var titles: [String] = []
    private var active = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        addButton.target = self
        addButton.action = #selector(addTab)
        addButton.toolTip = "New Tab"
        addSubview(addButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func update(titles: [String], active: Int) {
        self.titles = titles
        self.active = active
        while buttons.count < titles.count {
            let b = TabButton()
            b.bar = self
            addSubview(b)
            buttons.append(b)
        }
        while buttons.count > titles.count {
            buttons.removeLast().removeFromSuperview()
        }
        for (i, b) in buttons.enumerated() {
            b.index = i
            b.title = titles[i]
            b.isActive = i == active
        }
        needsLayout = true
    }

    private var tabWidth: CGFloat {
        guard !buttons.isEmpty else { return 0 }
        let available = bounds.width - 40
        return min(220, max(80, available / CGFloat(buttons.count)))
    }

    override func layout() {
        super.layout()
        let w = tabWidth
        for (i, b) in buttons.enumerated() where !b.isDragging {
            b.frame = NSRect(x: 4 + CGFloat(i) * w, y: 3, width: w - 4, height: bounds.height - 6)
        }
        addButton.frame = NSRect(x: 4 + CGFloat(buttons.count) * w + 2, y: (bounds.height - 22) / 2, width: 22, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    @objc private func addTab() { delegate?.tabBarNewTab(self) }

    // Called by TabButton
    func select(_ i: Int) { delegate?.tabBar(self, select: i) }
    func close(_ i: Int) { delegate?.tabBar(self, close: i) }
    func rename(_ i: Int) { delegate?.tabBar(self, rename: i) }
    func detach(_ i: Int) { delegate?.tabBar(self, detach: i) }

    func dragEnded(_ button: TabButton) {
        let w = tabWidth
        guard w > 0 else { return }
        let target = min(max(Int((button.frame.midX - 4) / w), 0), buttons.count - 1)
        button.isDragging = false
        if target != button.index {
            delegate?.tabBar(self, move: button.index, to: target)
        } else {
            needsLayout = true
        }
    }
}

final class TabButton: NSView {
    weak var bar: TabBarView?
    var index = 0
    var title = "" { didSet { label.stringValue = title; toolTip = title } }
    var isActive = false { didSet { needsDisplay = true; label.textColor = isActive ? .labelColor : .secondaryLabelColor } }
    var isDragging = false
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var dragStart: NSPoint?
    private var originX: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        addSubview(label)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 4, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 22, y: (bounds.height - 16) / 2, width: max(0, bounds.width - 44), height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isActive ? NSColor.controlBackgroundColor : NSColor.clear).setFill()
        path.fill()
        if isActive {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            bar?.rename(index)
            return
        }
        bar?.select(index)
        dragStart = event.locationInWindow
        originX = frame.minX
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let dx = event.locationInWindow.x - start.x
        if !isDragging, abs(dx) < 6 { return }
        isDragging = true
        frame.origin.x = originX + dx
        superview?.addSubview(self, positioned: .above, relativeTo: nil)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if isDragging { bar?.dragEnded(self) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let i = index
        menu.addItem(ClosureMenuItem(title: "Rename Tab…") { [weak self] in self?.bar?.rename(i) })
        menu.addItem(ClosureMenuItem(title: "Move Tab to New Window") { [weak self] in self?.bar?.detach(i) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Close Tab") { [weak self] in self?.bar?.close(i) })
        return menu
    }

    @objc private func closeTab() { bar?.close(index) }
}
