import AppKit
import SplittermCore

/// A view that holds pane-tree children and can swap one for another.
@MainActor
protocol PaneParent: NSView {
    func replaceChild(_ old: NSView, with new: NSView)
}

/// A two-child split. Stores its divider position as a ratio, as Terminator does,
/// so layouts reopen correctly at any window size.
final class SplitContainer: NSView, PaneParent {
    static let dividerThickness: CGFloat = 1
    static let grabSlop: CGFloat = 3
    static let minChild: CGFloat = 40

    var direction: SplitDirection { didSet { needsLayout = true; window?.invalidateCursorRects(for: self) } }
    var ratio: CGFloat { didSet { needsLayout = true; window?.invalidateCursorRects(for: self) } }
    private(set) var first: NSView
    private(set) var second: NSView
    private var dragging = false

    init(direction: SplitDirection, ratio: CGFloat = 0.5, first: NSView, second: NSView) {
        self.direction = direction
        self.ratio = ratio
        self.first = first
        self.second = second
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        first.removeFromSuperview()
        second.removeFromSuperview()
        addSubview(first)
        addSubview(second)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func other(than child: NSView) -> NSView { child === first ? second : first }

    func replaceChild(_ old: NSView, with new: NSView) {
        new.removeFromSuperview()
        if old === first {
            first = new
        } else if old === second {
            second = new
        } else {
            return
        }
        replaceSubview(old, with: new)
        needsLayout = true
    }

    func swapChildren() {
        (first, second) = (second, first)
        ratio = 1 - ratio
    }

    private var length: CGFloat { direction == .right ? bounds.width : bounds.height }

    private var clampedRatio: CGFloat {
        let usable = length - Self.dividerThickness
        guard usable > 2 * Self.minChild else { return 0.5 }
        let lo = Self.minChild / usable
        return min(max(ratio, lo), 1 - lo)
    }

    private var dividerRect: NSRect {
        let usable = length - Self.dividerThickness
        let pos = (usable * clampedRatio).rounded()
        return direction == .right
            ? NSRect(x: pos, y: 0, width: Self.dividerThickness, height: bounds.height)
            : NSRect(x: 0, y: pos, width: bounds.width, height: Self.dividerThickness)
    }

    private var grabRect: NSRect {
        dividerRect.insetBy(dx: direction == .right ? -Self.grabSlop : 0,
                            dy: direction == .down ? -Self.grabSlop : 0)
    }

    override func layout() {
        super.layout()
        let d = dividerRect
        if direction == .right {
            first.frame = NSRect(x: 0, y: 0, width: d.minX, height: bounds.height)
            second.frame = NSRect(x: d.maxX, y: 0, width: max(0, bounds.width - d.maxX), height: bounds.height)
        } else {
            first.frame = NSRect(x: 0, y: 0, width: bounds.width, height: d.minY)
            second.frame = NSRect(x: 0, y: d.maxY, width: bounds.width, height: max(0, bounds.height - d.maxY))
        }
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        dividerRect.fill()
    }

    override func resetCursorRects() {
        addCursorRect(grabRect, cursor: direction == .right ? .resizeLeftRight : .resizeUpDown)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        if grabRect.contains(local) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            ratio = 0.5   // double-click a divider to even it out
            return
        }
        dragging = grabRect.contains(p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        let usable = length - Self.dividerThickness
        guard usable > 0 else { return }
        let pos = direction == .right ? p.x : p.y
        ratio = min(max(pos / usable, 0.02), 0.98)
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    /// Moves the divider by `delta` points (keyboard resize).
    func nudge(by delta: CGFloat) {
        let usable = length - Self.dividerThickness
        guard usable > 0 else { return }
        ratio = min(max(clampedRatio + delta / usable, 0.02), 0.98)
    }
}

/// The root of one tab. Holds the split tree, and while zoomed shows a single pane on top.
final class TabRootView: NSView, PaneParent {
    private(set) var root: NSView
    private var zoom: (pane: TerminalPane, placeholder: NSView)?

    init(root: NSView) {
        self.root = root
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        root.removeFromSuperview()
        addSubview(root)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        root.frame = bounds
        zoom?.pane.frame = bounds
    }

    func replaceChild(_ old: NSView, with new: NSView) {
        guard old === root else { return }
        new.removeFromSuperview()
        replaceSubview(old, with: new)
        root = new
        needsLayout = true
    }

    var zoomedPane: TerminalPane? { zoom?.pane }

    func toggleZoom(_ pane: TerminalPane) {
        if zoom != nil { unzoom(); return }
        guard pane !== root, let parent = pane.superview as? PaneParent else { return }
        let placeholder = NSView()
        parent.replaceChild(pane, with: placeholder)
        root.isHidden = true
        addSubview(pane)
        pane.frame = bounds
        zoom = (pane, placeholder)
        pane.focus()
        AppModel.shared.stateChanged()
    }

    func unzoom() {
        guard let z = zoom else { return }
        zoom = nil
        z.pane.removeFromSuperview()
        if let parent = z.placeholder.superview as? PaneParent {
            parent.replaceChild(z.placeholder, with: z.pane)
        }
        root.isHidden = false
        needsLayout = true
        z.pane.focus()
        AppModel.shared.stateChanged()
    }

    /// Panes in tree order, including a zoomed pane in its real position.
    var panes: [TerminalPane] {
        guard let z = zoom else { return root.descendantPanes }
        return Self.panes(in: root, substituting: z.placeholder, with: z.pane)
    }

    private static func panes(in view: NSView, substituting placeholder: NSView, with pane: TerminalPane) -> [TerminalPane] {
        if view === placeholder { return [pane] }
        if let p = view as? TerminalPane { return [p] }
        return view.subviews.flatMap { panes(in: $0, substituting: placeholder, with: pane) }
    }

    // MARK: Layout serialisation

    func describe(focused: TerminalPane?) -> LayoutNode {
        unzoom()
        return Self.describe(root, focused: focused)
    }

    private static func describe(_ view: NSView, focused: TerminalPane?) -> LayoutNode {
        if let p = view as? TerminalPane { return .terminal(p.describe(focused: p === focused)) }
        if let s = view as? SplitContainer {
            return .split(direction: s.direction, ratio: Double(s.ratio),
                          first: describe(s.first, focused: focused),
                          second: describe(s.second, focused: focused))
        }
        return .terminal(LayoutTerminal())
    }

    static func build(_ node: LayoutNode, cwd: String? = nil) -> NSView {
        switch node {
        case .terminal(let t):
            return TerminalPane(profile: t.profile, cwd: t.cwd ?? cwd, command: t.command,
                                group: t.group, title: t.title,
                                uuid: t.uuid.flatMap(UUID.init(uuidString:)) ?? UUID())
        case .split(let d, let r, let a, let b):
            return SplitContainer(direction: d, ratio: CGFloat(r), first: build(a, cwd: cwd), second: build(b, cwd: cwd))
        }
    }

    /// Rotates the whole tree 90°, swapping side-by-side and stacked splits.
    func rotate(clockwise: Bool) {
        unzoom()
        Self.rotate(root, clockwise: clockwise)
        needsLayout = true
    }

    private static func rotate(_ view: NSView, clockwise: Bool) {
        guard let s = view as? SplitContainer else { return }
        rotate(s.first, clockwise: clockwise)
        rotate(s.second, clockwise: clockwise)
        // Same rule as LayoutNode.rotated(clockwise:).
        let keepsOrder = (s.direction == .right) == clockwise
        if !keepsOrder { s.swapChildren() }
        s.direction = s.direction.toggled
    }
}
