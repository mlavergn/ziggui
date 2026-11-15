# ziggui

> A SwiftUI-style GUI library for Zig: a pure-Zig renderer, its views, and an SDL3 runtime, behind one import.

## Overview

ziggui is the GUI layer shared by a family of native Zig desktop apps. You describe the window as a tree of SwiftUI-shaped views (`VStack`, `Toggle`, `NavigationSplitView`, `GeometryReader`, …), rebuilt each frame from your app's state. ziggui lays it out, draws it in the platform's own look, and routes input back to your code. Names follow SwiftUI's wherever SwiftUI has one, so the API reads like SwiftUI written in Zig.

Three things set it apart:

- **One look across the apps.** Beyond the standard views, ziggui owns the parts every app on it draws alike: the window frame, the menu bar, notices, questions, empty panes and key hints. Apps built on it look and behave the same, and follow one design guide ([`../styleguide/GUIDESIGN.md`](../styleguide/GUIDESIGN.md)).
- **Pure Zig down to the pixels.** Layout, text, themes and a software rasterizer need no C and no window, so every view tests headless. Screenshots render byte for byte the same on every run. On screen, the same frame goes through the GPU.
- **One import.** An app writes `ziggui.VStack`, `ziggui.Theme`, `ziggui.App`; the build hands its executable the SDL runtime and its tests a core without it.

Since 1.0.0 ziggui includes what used to be the separate zigui library, and builds SDL 3.4.20 itself from the official release.

## Features

- **Views:** text and rich text, buttons, toggles, sliders, steppers, pickers, segmented controls, text fields and a text editor, images, icons (the Lucide set), shapes and gradients. Stacks, grids, lists, tables, scroll views, tabs, navigation split views, menus and context menus. Sheets, alerts and popovers.
- **Themes:** five native-looking families (macOS, Windows 10, Windows 2000, KDE Plasma, Material), each light and dark, with an accent color. An app with its own design system can recolor every widget.
- **Rendering:** SDL_GPU on Metal, Vulkan or Direct3D 12, falling back to the software rasterizer automatically. Bundled fonts (Inter, JetBrains Mono, Noto Emoji) and a TrueType parser that treats font files as untrusted.
- **Widgets for real apps:** a virtual list that also scrolls sideways, a diff view whose long lines scroll or wrap, draggable split views, hover popovers and hover hints, chat pieces (bubbles, code blocks, disclosure groups, status marks), badges and key caps, setting, selectable and reorderable rows, a key/value editor, a token field, a search field, and an in-window file-or-folder picker.
- **The app's frame:** the macOS top band and, on Linux and Windows, a drawn title bar with the platform's window buttons and an in-window menu bar. One menu table builds both macOS's menu bar and the drawn one. A notice strip, confirm alerts, empty states, pane titles and a key-hint status line.
- **Desktop integration:** native menus, a status item or tray icon (an SNI icon over D-Bus on Linux), panels, clipboard, file dialogs, revealing a file in Finder or Explorer, Linux desktop entries, and reopening the window where it was.
- **Video:** a player modeled on `AVPlayer`, drawn by the platform's own player behind the window's surface, with ziggui's controls painted over it (AVFoundation on macOS).
- **Secure fields:** a password field draws dots, never copies its text, and wipes it from memory when it leaves.

A component gallery shows every view in every theme.

## Platforms

| Platform | Status |
| --- | --- |
| macOS (Apple Silicon) | Full support, including video |
| Linux (x86_64, ARM) | Full support except video (the player reports it unsupported) |
| Windows (x86_64) | Full support except video; built with mingw (MSVC builds untested) |

## Apps built on ziggui

```
ziggit ───┐
zigagent ─┤
zigmcp ───┤
zigr2 ────┼─► ziggui ─► SDL3 (built from the 3.4.20 release)
zigiptv ──┤
zigcode ──┤
zigbase ──┘  (the template new apps start from)
```

- **ziggit:** a git client: CLI, TUI, web UI and native app over the local `git`.
- **zigagent:** many AI agent sessions (Claude, Codex, Grok, Gemini, Copilot, Apple on-device) watched from one control screen.
- **zigmcp:** an MCP client and endpoint, with a native explorer (ZigMCP).
- **zigr2:** Cloudflare R2 object storage, with a native browser.
- **zigiptv:** an IPTV data manager and HLS relay, with a native player.
- **zigcode:** a development environment for agentic coding.
- **zigbase:** the template a new app starts from.

## Getting started

Requirements:

- Zig 0.17.1 or later (0.17.0 miscompiles `@intCast` in optimized builds)
- A sibling checkout of `../styleguide` (for `make format`, `make lint`, `make validate`)
- Nothing to install for SDL3: Zig fetches the release and builds it on first use

```sh
git clone git@github.com:mlavergn/ziggui.git
cd ziggui
make build
make test     # headless: never builds SDL or opens a window
make demo     # the component gallery, in a window
```

The gallery also renders without a window, which is how changes are checked:

```sh
zig build gallery -Doptimize=ReleaseFast
zig-out/bin/ziggui-gallery --screenshot out.bmp --section 7
zig-out/bin/ziggui-gallery --screenshot gpu.bmp --section 7 --gpu   # through the GPU, offscreen
```

## Using ziggui in an app

Add ziggui to `build.zig.zon`, then give the executable the app module from `linkApp` (which builds and links SDL3) and the tests the core module (which never does), both under the name `ziggui`:

```zig
const ziggui_dep = b.dependency("ziggui", .{ .target = target, .optimize = optimize });
const ziggui_build = @import("ziggui");
exe.root_module.addImport("ziggui", ziggui_build.linkApp(ziggui_dep, .{ .target = target, .optimize = optimize }));
tests.root_module.addImport("ziggui", ziggui_dep.module("ziggui"));
```

A window is your state plus a function that turns it into views:

```zig
const std = @import("std");
const ziggui = @import("ziggui");

const Counter = struct {
    const Self = @This();

    count: u32 = 0,

    fn increment(self: *Self) void {
        self.count += 1;
    }

    fn body(self: *Self) ziggui.View {
        const label = ziggui.BuildScope.shared().allocator().print("Tapped {d} times", .{self.count}) catch @panic("oom");
        return ziggui.VStack(.{
            ziggui.Text(label).font(.title),
            ziggui.Button("Tap me", ziggui.Callback.init(Self, self, Self.increment)),
        }).spacing(12).padding(24);
    }
};

pub fn main(init: std.process.Init) !void {
    var counter: Counter = .{};
    try ziggui.App.shared().run(init.gpa, Counter, &counter, .{ .title = "Counter", .width = 360, .height = 200 }, Counter.body, null);
}
```

`body` runs each frame. What it builds lives in that frame's arena, so a view never outlives the frame it was built in. To test a window, render it headless with `ziggui.Screenshot`. The apps above are full examples, and [`CLAUDE.md`](CLAUDE.md) documents the internals.

## Configuration

Build options, beyond Zig's standard target and optimize:

- `-Dtest-filter=<text>`: run only the unit tests whose names match.
- `-Dsdl3-prefix=<dir>`: link a prebuilt SDL3 (`include/`, `lib/`) instead of building the release.
- `-Dwindows-console`: keep a console window for the Windows gallery (log output).

Environment variables the runtime reads:

- `ZIGGUI_SOFTWARE`: render with the software rasterizer instead of the GPU.
- `ZIGGUI_FRAME_LOG`: log per-frame timing.
- `ZIGGUI_PANEL_DUMP=<path>`: write the panel's frame to a file.
- `ZIGGUI_NO_FROST`: macOS only, leave the window glass off.

## Project layout

```
src/renderer/   pure Zig: geometry, layout, color, canvas, rasterizer, GPU scene, text, themes, state
src/views/      the views: the engine, controls, containers, text, media, and the widget groups
src/sdl/        the SDL3 runtime: window, event loop, menus, tray, clipboard, dialogs, video, GPU
src/module.zig  the ziggui barrel, the one module apps import
build/          the SDL3 C build
gallery/        the component gallery
fixtures/       fixed files the gallery shows
tools/icon/     mkico.py: a polygon SVG to .ico/.png/an iconset, for app icons
```

## License

MIT (see [`LICENSE`](LICENSE)).
