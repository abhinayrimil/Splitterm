import Foundation

/// Which way a split places its second child relative to the first.
public enum SplitDirection: String, Codable, Sendable {
    /// Side by side: first on the left, second on the right.
    case right
    /// Stacked: first on top, second below.
    case down

    public var toggled: SplitDirection { self == .right ? .down : .right }
}

/// A saved workspace: one or more windows, each with tabs holding split trees.
public struct LayoutFile: Codable, Equatable, Sendable {
    public var windows: [LayoutWindow]
    public init(windows: [LayoutWindow]) { self.windows = windows }
}

public struct LayoutWindow: Codable, Equatable, Sendable {
    /// x, y, width, height in screen points (bottom-left origin, AppKit style).
    public var frame: [Double]?
    public var maximized: Bool?
    public var fullScreen: Bool?
    public var title: String?
    public var activeTab: Int?
    public var tabs: [LayoutTab]

    public init(frame: [Double]? = nil, maximized: Bool? = nil, fullScreen: Bool? = nil,
                title: String? = nil, activeTab: Int? = nil, tabs: [LayoutTab]) {
        self.frame = frame; self.maximized = maximized; self.fullScreen = fullScreen
        self.title = title; self.activeTab = activeTab; self.tabs = tabs
    }
}

public struct LayoutTab: Codable, Equatable, Sendable {
    public var title: String?
    public var root: LayoutNode
    public init(title: String? = nil, root: LayoutNode) { self.title = title; self.root = root }
}

public struct LayoutTerminal: Codable, Equatable, Sendable {
    public var profile: String?
    public var group: String?
    public var title: String?
    /// Typed into the shell after it starts, so the shell stays open when it exits.
    public var command: String?
    public var cwd: String?
    public var focused: Bool?
    public var uuid: String?

    public init(profile: String? = nil, group: String? = nil, title: String? = nil,
                command: String? = nil, cwd: String? = nil, focused: Bool? = nil, uuid: String? = nil) {
        self.profile = profile; self.group = group; self.title = title
        self.command = command; self.cwd = cwd; self.focused = focused; self.uuid = uuid
    }
}

/// A node in a split tree. Encoded as either
/// `{"terminal": {...}}` or `{"split": "right", "ratio": 0.5, "children": [a, b]}`.
public indirect enum LayoutNode: Equatable, Sendable {
    case terminal(LayoutTerminal)
    case split(direction: SplitDirection, ratio: Double, first: LayoutNode, second: LayoutNode)

    /// All terminals in depth-first order.
    public var terminals: [LayoutTerminal] {
        switch self {
        case .terminal(let t): return [t]
        case .split(_, _, let a, let b): return a.terminals + b.terminals
        }
    }
}

extension LayoutNode: Codable {
    enum CodingKeys: String, CodingKey { case terminal, split, ratio, children }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(LayoutTerminal.self, forKey: .terminal) {
            self = .terminal(t)
            return
        }
        let dir = try c.decode(SplitDirection.self, forKey: .split)
        let ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 0.5
        let children = try c.decode([LayoutNode].self, forKey: .children)
        guard children.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .children, in: c,
                debugDescription: "A split needs exactly two children, found \(children.count)")
        }
        self = .split(direction: dir, ratio: min(max(ratio, 0.05), 0.95),
                      first: children[0], second: children[1])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let t):
            try c.encode(t, forKey: .terminal)
        case .split(let dir, let ratio, let a, let b):
            try c.encode(dir, forKey: .split)
            try c.encode((ratio * 1000).rounded() / 1000, forKey: .ratio)
            try c.encode([a, b], forKey: .children)
        }
    }
}

public extension LayoutNode {
    /// Rotates the tree 90°, as Terminator's rotate_cw / rotate_ccw do.
    func rotated(clockwise: Bool) -> LayoutNode {
        switch self {
        case .terminal:
            return self
        case .split(let dir, let ratio, let a, let b):
            let ra = a.rotated(clockwise: clockwise), rb = b.rotated(clockwise: clockwise)
            // Clockwise: left/right becomes top/bottom keeping order; top/bottom becomes right/left.
            let keepsOrder = (dir == .right) == clockwise
            return keepsOrder
                ? .split(direction: dir.toggled, ratio: ratio, first: ra, second: rb)
                : .split(direction: dir.toggled, ratio: 1 - ratio, first: rb, second: ra)
        }
    }
}

public extension LayoutNode {
    /// Returns a copy with the terminal at depth-first `index` replaced.
    func replacingTerminal(at index: Int, with terminal: LayoutTerminal) -> LayoutNode {
        var counter = 0
        return replacing(&counter, index, terminal)
    }

    private func replacing(_ counter: inout Int, _ index: Int, _ terminal: LayoutTerminal) -> LayoutNode {
        switch self {
        case .terminal:
            defer { counter += 1 }
            return counter == index ? .terminal(terminal) : self
        case .split(let d, let r, let a, let b):
            let na = a.replacing(&counter, index, terminal)
            let nb = b.replacing(&counter, index, terminal)
            return .split(direction: d, ratio: r, first: na, second: nb)
        }
    }
}
