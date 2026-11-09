import XCTest
@testable import SplittermCore

final class ShortcutTests: XCTestCase {
    func testParseAndCanonicalForm() {
        let s = Shortcut("Shift+CMD+d")
        XCTAssertEqual(s?.key, "d")
        XCTAssertEqual(s?.modifiers, [.command, .shift])
        XCTAssertEqual(s?.description, "cmd+shift+d")
        XCTAssertEqual(Shortcut(s!.description), s)
    }

    func testSpecialKeys() {
        XCTAssertEqual(Shortcut("cmd+opt+left")?.keyCode, 0x7B)
        XCTAssertEqual(Shortcut("cmd+=")?.key, "=")
        XCTAssertEqual(Shortcut("cmd+plus")?.key, "=")
        XCTAssertEqual(Shortcut("cmd++")?.key, "=")
        XCTAssertEqual(Shortcut("cmd+shift+return")?.keyCode, 0x24)
        XCTAssertEqual(Shortcut("f11")?.modifiers, [])
    }

    func testRejectsBadInput() {
        XCTAssertNil(Shortcut(""))
        XCTAssertNil(Shortcut("cmd+"))
        XCTAssertNil(Shortcut("hyper+d"))
        XCTAssertNil(Shortcut("cmd+notakey"))
    }

    func testKeyCodeRoundTrip() {
        let s = Shortcut(keyCode: 0x02, modifiers: [.command])
        XCTAssertEqual(s, Shortcut("cmd+d"))
        XCTAssertEqual(Shortcut(keyCode: 0x4C, modifiers: [])?.key, "return")
    }

    func testDefaultBindingsAreValidAndConflictFree() {
        for (action, raw) in Action.defaultBindings where !raw.isEmpty {
            XCTAssertNotNil(Shortcut(raw), "Invalid default for \(action): \(raw)")
        }
        XCTAssertEqual(Set(Action.allCases), Set(Action.defaultBindings.keys))
        let table = KeyBindingTable(overrides: [:])
        XCTAssertTrue(table.conflicts.isEmpty, "Conflicts: \(table.conflicts)")
    }

    func testOverridesAndUnbinding() {
        let table = KeyBindingTable(overrides: ["split_right": "cmd+opt+shift+d", "new_tab": ""])
        XCTAssertEqual(table.byAction[.splitRight], Shortcut("cmd+opt+shift+d"))
        XCTAssertNil(table.byAction[.newTab])
        XCTAssertNil(table.byShortcut[Shortcut("cmd+t")!])
    }
}

final class LayoutTests: XCTestCase {
    let sample = """
    {"windows":[{"tabs":[{"title":"clusters","root":
      {"split":"right","ratio":0.5,"children":[
        {"terminal":{"profile":"prod","group":"prod","command":"oc whoami"}},
        {"split":"down","ratio":0.6,"children":[
          {"terminal":{"group":"prod","title":"logs"}},
          {"terminal":{"command":"k9s","focused":true}}]}]}}]}]}
    """

    func testDecodeAndRoundTrip() throws {
        let layout = try JSONDecoder().decode(LayoutFile.self, from: Data(sample.utf8))
        let root = layout.windows[0].tabs[0].root
        XCTAssertEqual(root.terminals.count, 3)
        XCTAssertEqual(root.terminals.filter { $0.group == "prod" }.count, 2)
        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(LayoutFile.self, from: data), layout)
    }

    func testRejectsSplitWithWrongChildCount() {
        let bad = #"{"split":"right","children":[{"terminal":{}}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LayoutNode.self, from: Data(bad.utf8)))
    }

    func testRotationIsReversible() throws {
        let layout = try JSONDecoder().decode(LayoutFile.self, from: Data(sample.utf8))
        let root = layout.windows[0].tabs[0].root
        XCTAssertEqual(root.rotated(clockwise: true).rotated(clockwise: false), root)
        let four = root.rotated(clockwise: true).rotated(clockwise: true)
            .rotated(clockwise: true).rotated(clockwise: true)
        XCTAssertEqual(four, root)
        if case .split(let dir, _, let first, _) = root.rotated(clockwise: true) {
            XCTAssertEqual(dir, .down)
            XCTAssertEqual(first.terminals.first?.profile, "prod")
        } else {
            XCTFail("expected split")
        }
    }
}

final class TerminalSchemeTests: XCTestCase {
    func testEverySchemeIsValidAndMatchesAfterApplying() {
        XCTAssertEqual(Set(TerminalScheme.all.map { $0.name }).count, TerminalScheme.all.count)
        for scheme in TerminalScheme.all {
            XCTAssertEqual(scheme.palette.count, 16, scheme.name)
            for hex in [scheme.foreground, scheme.background, scheme.cursor, scheme.selection] + scheme.palette {
                XCTAssertNotNil(RGB(hex: hex), scheme.name)
            }
            var p = Profile()
            p.opacity = 0.5
            scheme.apply(to: &p)
            XCTAssertTrue(scheme.matches(p), scheme.name)
            XCTAssertEqual(p.opacity, 0.5)
        }
    }

    func testDefaultProfileMatchesDefaultScheme() {
        XCTAssertEqual(TerminalScheme.all.first { $0.matches(Profile()) }?.name, "Splitterm")
    }

    func testHandEditedColourIsNoLongerAScheme() {
        var p = Profile()
        p.foreground = "#123456"
        XCTAssertNil(TerminalScheme.all.first { $0.matches(p) })
    }
}

final class InputSafetyTests: XCTestCase {
    func testOnlyWebLinksOpen() {
        XCTAssertTrue(InputSafety.isOpenableLink("HTTPS://example.com"))
        XCTAssertFalse(InputSafety.isOpenableLink("file:///etc/passwd"))
        XCTAssertFalse(InputSafety.isOpenableLink("splitterm://layout/x"))
        XCTAssertFalse(InputSafety.isOpenableLink("not a url"))
    }

    func testPasteCannotEndBracketedPaste() {
        XCTAssertEqual(InputSafety.sanitizedPaste("a\u{1B}[201~rm -rf\u{9B}b\n"), "a[201~rm -rfb\n")
    }

    func testDisplaySafeRemovesDisguises() {
        XCTAssertEqual(InputSafety.displaySafe("a\nb\u{202E}c"), "abc")
        XCTAssertEqual(InputSafety.displaySafe("abcd", limit: 2), "ab")
    }

    func testLayoutCommandsIncludeProfileCommands() {
        var cfg = AppConfig()
        var p = Profile(); p.customCommand = "evil"
        cfg.profiles["p"] = p
        let root = LayoutNode.split(direction: .right, ratio: 0.5,
                                    first: .terminal(LayoutTerminal(command: "ls")),
                                    second: .terminal(LayoutTerminal(profile: "p")))
        cfg.layouts["x"] = LayoutFile(windows: [LayoutWindow(tabs: [LayoutTab(root: root)])])
        XCTAssertEqual(cfg.commands(inLayout: "x"), ["ls", "evil"])
    }
}

final class ConfigTests: XCTestCase {
    func testMissingKeysUseDefaults() throws {
        let cfg = try ConfigStore.decode(Data(##"{"profiles":{"prod":{"background":"#300000"}}}"##.utf8))
        XCTAssertNotNil(cfg.profiles["default"])
        XCTAssertEqual(cfg.profiles["prod"]?.background, "#300000")
        XCTAssertEqual(cfg.profiles["prod"]?.fontSize, 13)
        XCTAssertEqual(cfg.global.broadcastDefault, .group)
        XCTAssertEqual(cfg.sortedProfileNames, ["default", "prod"])
    }

    func testEncodeDecodeRoundTrip() throws {
        var cfg = AppConfig()
        cfg.keybindings["split_right"] = "cmd+e"
        cfg.layouts["x"] = LayoutFile(windows: [LayoutWindow(tabs: [LayoutTab(root: .terminal(LayoutTerminal()))])])
        XCTAssertEqual(try ConfigStore.decode(try ConfigStore.encode(cfg)), cfg)
    }

    func testRGB() {
        XCTAssertEqual(RGB(hex: "#fff")?.hex, "#ffffff")
        XCTAssertEqual(RGB(hex: "#ffff00000000")?.hex, "#ff0000")
        XCTAssertNil(RGB(hex: "#zzz"))
    }

    func testGroupNames() {
        XCTAssertEqual(GroupNames.next(excluding: []), "Alpha")
        XCTAssertEqual(GroupNames.next(excluding: ["Alpha"]), "Beta")
        XCTAssertEqual(GroupNames.next(excluding: Set(GroupNames.pool)), "Group 2")
    }
}

final class TerminatorImportTests: XCTestCase {
    let sample = """
    [global_config]
      broadcast_default = group
    [keybindings]
    [profiles]
      [[default]]
        cursor_color = "#aaaaaa"
      [[prod]]
        use_system_font = False
        font = DejaVu Sans Mono Bold 12
        background_color = "#300000"
        scrollback_lines = 5000
        palette = "#000000:#cc0000:#4e9a06:#c4a000:#3465a4:#75507b:#06989a:#d3d7cf:#555753:#ef2929:#8ae234:#fce94f:#729fcf:#ad7fa8:#34e2e2:#eeeeec"
    [layouts]
      [[work]]
        [[[window0]]]
          type = Window
          parent = ""
          size = 1200, 800
        [[[pane0]]]
          type = HPaned
          parent = window0
          order = 0
          ratio = 0.3
        [[[term1]]]
          type = Terminal
          parent = pane0
          order = 1
          profile = prod
          command = top
        [[[term0]]]
          type = Terminal
          parent = pane0
          order = 0
          group = Alpha
    [plugins]
    """

    func testImportsProfilesAndLayouts() throws {
        let r = TerminatorImporter.importConfig(text: sample)
        XCTAssertEqual(r.warnings, [])
        let prod = try XCTUnwrap(r.profiles["prod"])
        XCTAssertEqual(prod.fontName, "DejaVu Sans Mono")
        XCTAssertEqual(prod.fontSize, 12)
        XCTAssertEqual(prod.background, "#300000")
        XCTAssertEqual(prod.scrollbackLines, 5000)
        XCTAssertEqual(prod.palette.first, "#000000")

        let work = try XCTUnwrap(r.layouts["work"])
        XCTAssertEqual(work.windows.first?.frame?[2], 1200)
        guard case .split(let dir, let ratio, let a, let b) = work.windows[0].tabs[0].root else {
            return XCTFail("expected split")
        }
        XCTAssertEqual(dir, .right)
        XCTAssertEqual(ratio, 0.3, accuracy: 0.0001)
        XCTAssertEqual(a.terminals.first?.group, "Alpha")
        XCTAssertEqual(b.terminals.first?.command, "top")
    }
}

final class LayoutEditTests: XCTestCase {
    func testReplacingTerminal() {
        let root = LayoutNode.split(direction: .right, ratio: 0.5,
                                    first: .terminal(LayoutTerminal(command: "a")),
                                    second: .split(direction: .down, ratio: 0.5,
                                                   first: .terminal(LayoutTerminal(command: "b")),
                                                   second: .terminal(LayoutTerminal(command: "c"))))
        let edited = root.replacingTerminal(at: 2, with: LayoutTerminal(command: "z"))
        XCTAssertEqual(edited.terminals.map { $0.command }, ["a", "b", "z"])
        XCTAssertEqual(root.replacingTerminal(at: 9, with: LayoutTerminal()), root)
    }
}
