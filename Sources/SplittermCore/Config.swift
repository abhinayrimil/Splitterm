import Foundation

public enum BroadcastMode: String, Codable, CaseIterable, Sendable {
    case off, group, all

    public var title: String {
        switch self {
        case .off: return "Off"
        case .group: return "Group"
        case .all: return "All"
        }
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var broadcastDefault: BroadcastMode = .group
    public var hideTabBarWhenSingle: Bool = true
    public var autocleanGroups: Bool = true
    public var confirmCloseMultiple: Bool = true
    /// Ask before sending Return to this many or more broadcast receivers (0 disables).
    public var confirmBroadcastReturnAt: Int = 10
    public var focusFollowsMouse: Bool = false
    /// Layout opened at launch when present; Terminator uses "default" too.
    public var startupLayout: String = "default"

    public init() {}

    enum CodingKeys: String, CodingKey {
        case broadcastDefault, hideTabBarWhenSingle, autocleanGroups, confirmCloseMultiple,
             confirmBroadcastReturnAt, focusFollowsMouse, startupLayout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlobalSettings()
        broadcastDefault = try c.decodeIfPresent(BroadcastMode.self, forKey: .broadcastDefault) ?? d.broadcastDefault
        hideTabBarWhenSingle = try c.decodeIfPresent(Bool.self, forKey: .hideTabBarWhenSingle) ?? d.hideTabBarWhenSingle
        autocleanGroups = try c.decodeIfPresent(Bool.self, forKey: .autocleanGroups) ?? d.autocleanGroups
        confirmCloseMultiple = try c.decodeIfPresent(Bool.self, forKey: .confirmCloseMultiple) ?? d.confirmCloseMultiple
        confirmBroadcastReturnAt = try c.decodeIfPresent(Int.self, forKey: .confirmBroadcastReturnAt) ?? d.confirmBroadcastReturnAt
        focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? d.focusFollowsMouse
        startupLayout = try c.decodeIfPresent(String.self, forKey: .startupLayout) ?? d.startupLayout
    }
}

/// The whole config file: `~/.config/splitterm/config.json`.
public struct AppConfig: Codable, Equatable, Sendable {
    public var global: GlobalSettings = GlobalSettings()
    public var profiles: [String: Profile] = ["default": Profile()]
    /// Action name → shortcut string; only overrides of the defaults need to be listed.
    /// An empty string unbinds an action.
    public var keybindings: [String: String] = [:]
    public var layouts: [String: LayoutFile] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey { case global, profiles, keybindings, layouts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        global = try c.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? GlobalSettings()
        profiles = try c.decodeIfPresent([String: Profile].self, forKey: .profiles) ?? [:]
        if profiles["default"] == nil { profiles["default"] = Profile() }
        keybindings = try c.decodeIfPresent([String: String].self, forKey: .keybindings) ?? [:]
        layouts = try c.decodeIfPresent([String: LayoutFile].self, forKey: .layouts) ?? [:]
    }

    public func profile(named name: String?) -> Profile {
        if let name, let p = profiles[name] { return p }
        return profiles["default"] ?? Profile()
    }

    public var sortedProfileNames: [String] {
        profiles.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    public var sortedLayoutNames: [String] {
        layouts.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}

/// Loads and saves the config file atomically.
public enum ConfigStore {
    public static var directory: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("splitterm")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/splitterm")
    }

    public static var fileURL: URL { directory.appendingPathComponent("config.json") }

    public enum LoadResult {
        case loaded(AppConfig)
        case created(AppConfig)
        case failed(AppConfig, Error)   // falls back to defaults; the file is left untouched
    }

    public static func load(from url: URL = fileURL) -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let cfg = AppConfig()
            try? save(cfg, to: url)
            return .created(cfg)
        }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try decode(data))
        } catch {
            return .failed(AppConfig(), error)
        }
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public static func encode(_ config: AppConfig) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(config)
    }

    public static func save(_ config: AppConfig, to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encode(config).write(to: url, options: .atomic)
        // Layout commands can hold hostnames or tokens: keep them private to this user.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func modificationDate(of url: URL = fileURL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Group names handed out automatically, as Terminator does.
public enum GroupNames {
    public static let pool = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
                              "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
                              "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]

    public static func next(excluding used: Set<String>) -> String {
        if let n = pool.first(where: { !used.contains($0) }) { return n }
        var i = 2
        while used.contains("Group \(i)") { i += 1 }
        return "Group \(i)"
    }
}
