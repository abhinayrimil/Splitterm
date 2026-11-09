/// A ready-made set of terminal colours that can be applied to a profile.
public struct TerminalScheme: Sendable {
    public let name: String
    public let foreground: String
    public let background: String
    public let cursor: String
    public let selection: String
    public let palette: [String]

    public func apply(to profile: inout Profile) {
        profile.foreground = foreground
        profile.background = background
        profile.cursorColor = cursor
        profile.selectionColor = selection
        profile.palette = palette
    }

    public func matches(_ profile: Profile) -> Bool {
        let theirs = [profile.foreground, profile.background, profile.cursorColor, profile.selectionColor] + profile.palette
        let ours = [foreground, background, cursor, selection] + palette
        return theirs.map { $0.lowercased() } == ours
    }

    private static let solarized = [
        "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
        "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
    ]

    public static let all: [TerminalScheme] = [
        TerminalScheme(name: "Splitterm", foreground: "#d8d8d8", background: "#1e1e1e", cursor: "#d8d8d8",
                       selection: "#44475a", palette: Profile.defaultPalette),
        TerminalScheme(name: "Dracula", foreground: "#f8f8f2", background: "#282a36", cursor: "#f8f8f2", selection: "#44475a", palette: [
            "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
            "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
        ]),
        TerminalScheme(name: "Solarized Dark", foreground: "#839496", background: "#002b36", cursor: "#93a1a1",
                       selection: "#073642", palette: solarized),
        TerminalScheme(name: "Solarized Light", foreground: "#657b83", background: "#fdf6e3", cursor: "#586e75",
                       selection: "#eee8d5", palette: solarized),
        TerminalScheme(name: "Nord", foreground: "#d8dee9", background: "#2e3440", cursor: "#d8dee9", selection: "#434c5e", palette: [
            "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
            "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
        ]),
        TerminalScheme(name: "Gruvbox Dark", foreground: "#ebdbb2", background: "#282828", cursor: "#ebdbb2", selection: "#504945", palette: [
            "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
            "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2",
        ]),
        TerminalScheme(name: "Tokyo Night", foreground: "#c0caf5", background: "#1a1b26", cursor: "#c0caf5", selection: "#33467c", palette: [
            "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
        ]),
        TerminalScheme(name: "One Dark", foreground: "#abb2bf", background: "#282c34", cursor: "#528bff", selection: "#3e4451", palette: [
            "#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
            "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff",
        ]),
        TerminalScheme(name: "Monokai", foreground: "#f8f8f2", background: "#272822", cursor: "#f8f8f0", selection: "#49483e", palette: [
            "#272822", "#f92672", "#a6e22e", "#f4bf75", "#66d9ef", "#ae81ff", "#a1efe5", "#f8f8f2",
            "#75715e", "#f92672", "#a6e22e", "#f4bf75", "#66d9ef", "#ae81ff", "#a1efe5", "#f9f8f5",
        ]),
    ]
}
