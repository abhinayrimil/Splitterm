# Splitterm

A native macOS terminal built around [GNOME Terminator](https://github.com/gnome-terminator/terminator)'s workflow: split any terminal into a tree of panes, keep several trees in tabs, type into many terminals at once with grouped broadcast, and reopen whole workspaces from saved layouts.

Written in Swift with AppKit and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Requires macOS 13 Ventura or later. This is a clean-room reimplementation: no Terminator code is used.

## Install

**From a release DMG:** open `Splitterm-x.y.z.dmg` and drag Splitterm to Applications.

**From source** (needs the Xcode Command Line Tools; `make test` needs full Xcode for XCTest):

```sh
git clone https://github.com/abhinayrimil/Splitterm.git && cd Splitterm
make install          # builds dist/Splitterm.app + dist/Splitterm-1.0.0.dmg and copies the app to /Applications
```

Other targets: `make test`, `make run` (build for this Mac and launch), `make app` (release build and DMG only).

An ad-hoc signed build runs on the Mac that built it. To give it to other people, sign and notarise it (see [Distribution](#distribution)).

Optional command-line launcher:

```sh
cp scripts/splitterm /usr/local/bin/
splitterm                 # new window in the current folder
splitterm ~/src/app       # new window in that folder
splitterm --layout oncall # open a saved layout
```

## Using it

Every terminal has a thin title bar with a **group button** on the left. Right-click a terminal for split, zoom, group and profile options. All shortcuts below can be changed in **Settings → Keyboard**.

| Action | Shortcut |
| --- | --- |
| Split right / split down | ⌘D / ⇧⌘D |
| Split along the longer side | ⌥⌘D |
| Close terminal / close window | ⌘W / ⇧⌘W |
| Focus left, right, up, down | ⌥⌘ + arrow |
| Next / previous terminal | ⌘] / ⌘[ |
| Move the divider | ⌃⌘ + arrow |
| Zoom one terminal to fill the tab | ⇧⌘↩ |
| Rotate the splits | ⌥⌘R / ⌥⇧⌘R |
| New tab / new window | ⌘T / ⌘N |
| Next / previous tab | ⇧⌘] / ⇧⌘[ |
| Go to tab 1–8, last tab | ⌘1…⌘8, ⌘9 |
| Broadcast off / to group / to all | ⌥⌘O / ⌥⌘G / ⌥⌘A |
| Group all in tab / ungroup tab | ⌃⌘T / ⌃⇧⌘T |
| Group all in window / ungroup window | ⌃⌘G / ⌃⇧⌘G |
| Insert terminal number / padded | ⌃⌘1 / ⌃⌘0 |
| Font bigger / smaller / reset | ⌘= / ⌘- / ⌘0 |
| Clear (reset + clear) | ⌘K |
| Layout launcher / save layout | ⇧⌘L / ⇧⌘S |
| Edit terminal / tab / window title | ⌃⌘X / ⌃⌘A / ⌃⌘W |
| Settings | ⌘, |

Drag a divider to resize; double-click it to even it out. Drag tabs to reorder them, double-click a tab to rename it, right-click a tab to move it to a new window.

### Groups and broadcast

Put terminals in the same group from the group button (or **Broadcast** menu), then pick a broadcast mode:

- **Group** (default): typing in a grouped terminal also types into every other terminal in that group.
- **All**: typing in any terminal goes to every terminal in every window.
- **Off**: input goes only to the focused terminal.

The sender's title bar turns red and receivers turn blue; a badge in the window's title bar shows how many terminals are receiving. Paste is broadcast too. **Insert terminal number** types 1, 2, 3… into each receiving terminal, handy for `ssh web-0` + number.

Splitterm broadcasts the bytes the terminal produces, not raw key events, so accented characters, dead keys and input methods arrive correctly (a known Terminator limitation). Before Return is sent to 10 or more terminals you're asked once per session; change the number in **Settings → General**.

### Layouts

Arrange windows, tabs and splits, then **Shell → Save Layout…** (⇧⌘S). A layout records each window's size and position, tabs and their titles, every split ratio, and per terminal its profile, group, title and current folder. In **Settings → Layouts** you can add a command for each terminal; it is typed into the shell after it starts, so the shell stays open afterwards. Saving over an existing layout keeps those commands.

Open layouts from the **Layout Launcher** (⇧⌘L), from the command line (`splitterm --layout NAME`), or via `splitterm://layout/NAME` (Splitterm asks first if the layout runs commands). A layout named `default` opens at launch (change this in Settings → General).

### Profiles

A profile sets font, colours, 16-colour palette, cursor, opacity, scrollback, login shell, a custom command, what happens when the shell exits, whether the title bar shows, and whether new splits join the current group. Switch a terminal's profile from its right-click menu. Editing a profile updates every terminal using it immediately.

**Coming from Terminator?** Splitterm menu → **Import Terminator Config…** reads `~/.config/terminator/config` and imports its profiles and layouts.

## Config file

Everything lives in `~/.config/splitterm/config.json` (or `$XDG_CONFIG_HOME/splitterm/config.json`). Edit it by hand if you like; Splitterm reloads it when you switch back to the app. Keys you leave out use their defaults.

```json
{
  "global": { "broadcastDefault": "group", "hideTabBarWhenSingle": true, "startupLayout": "default" },
  "keybindings": { "split_right": "cmd+e", "new_tab": "" },
  "profiles": {
    "default": { "fontSize": 13 },
    "prod": { "background": "#2b0000", "splitToGroup": true }
  },
  "layouts": {
    "oncall": {
      "windows": [{
        "tabs": [{
          "title": "clusters",
          "root": {
            "split": "right", "ratio": 0.5,
            "children": [
              { "terminal": { "profile": "prod", "group": "prod", "command": "oc whoami", "cwd": "~" } },
              { "split": "down", "ratio": 0.6, "children": [
                { "terminal": { "group": "prod", "title": "logs" } },
                { "terminal": { "command": "k9s", "focused": true } }
              ]}
            ]
          }
        }]
      }]
    }
  }
}
```

- `split`: `right` puts the children side by side, `down` stacks them. `ratio` is the first child's share (0–1).
- Keybinding values look like `cmd+shift+d`, `ctrl+opt+left`, `f5`. An empty string unbinds an action. Action names follow Terminator's (`split_right`, `go_left`, `group_tab`, `broadcast_all`…); Settings → Keyboard lists them all.
- Shortcuts match physical key positions on a US layout.

## Security

Terminal output and web links are treated as untrusted:

- `splitterm://` links ask before opening a folder or profile, or running a layout's commands.
- Pasted text has escape characters removed, so it can't break out of bracketed paste.
- Programs can't read or replace the clipboard through OSC 52, so tmux and Neovim clipboard integration over OSC 52 won't work.
- ⌘-click opens only `http`, `https` and `mailto` links.
- **Secure Keyboard Entry** is on by default (Splitterm menu). It stops other apps seeing what you type, and also blocks their global hotkeys while Splitterm is in front.
- Programs run inside Splitterm can't use the camera or microphone.
- `config.json` is readable only by you.

## Distribution

Ad-hoc signing (the default) is enough for your own Mac. For other Macs you need an Apple Developer ID:

```sh
xcrun notarytool store-credentials splitterm --apple-id you@example.com --team-id TEAMID   # once
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=splitterm VERSION=1.0.0 make app
```

This signs with the hardened runtime, notarises the DMG with Apple and staples the ticket, so it opens without warnings. `BUNDLE_ID` sets the bundle identifier (default `dev.splitterm.app`). Use `UNIVERSAL=0` to build only for the current architecture.

The GitHub Actions workflow in `.github/workflows/build.yml` runs the tests and uploads a DMG for every push; tag `v1.2.3` to version it.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/SplittermCore` | Config, profiles, shortcuts, layouts, Terminator importer (Foundation only, unit tested) |
| `Sources/Splitterm` | The AppKit app: panes, splits, tabs, windows, broadcast, menus, settings, layout launcher |
| `Tests/SplittermCoreTests` | Unit tests |
| `Resources` | Info.plist, entitlements, icon |
| `scripts` | `build-app.sh` (build, sign, DMG, notarise), `splitterm` CLI launcher |
| `Vendor/SwiftTerm` | SwiftTerm 1.20.0, trimmed. Local changes: `Shaders.metal` is a copied resource so no `metal` compiler is needed, Sixel and Kitty decompression input is bounded, Kitty graphics can't load local files, and terminals don't inherit each other's PTY handles |

## Licence

Splitterm is released under the [MIT License](LICENSE). SwiftTerm is MIT licensed; see [its licence](Vendor/SwiftTerm/LICENSE). Terminator is GPL v2; none of its code is included here.
