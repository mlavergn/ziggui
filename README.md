# ziggui

> A SwiftUI-style GUI library for Zig: a pure-Zig renderer, its views, and an SDL3 runtime, behind one import.

## Overview

ziggui is the GUI layer shared by a family of native Zig desktop apps. You describe the window as a tree of SwiftUI-shaped views (`VStack`, `Toggle`, `NavigationSplitView`, `GeometryReader`, …), rebuilt each frame from your app's state. ziggui lays it out, draws it in the platform's own look, and routes input back to your code. Names follow SwiftUI's wherever SwiftUI has one, so the API reads like SwiftUI written in Zig.

Three things set it apart:

- **One look across the apps.** Beyond the standard views, ziggui owns the parts every app on it draws alike: the window frame, the menu bar, notices, questions, empty panes and key hints. Apps built on it look and behave the same, and follow one design guide ([`../styleguide/GUIDESIGN.md`](../styleguide/GUIDESIGN.md)).
- **Pure Zig down to the pixels.** Layout, text, themes and a software rasterizer need no C and no window, so every view tests headless. Screenshots render byte for byte the same on every run. On screen, the same frame goes through the GPU.
- **One import.** An app writes `ziggui.VStack`, `ziggui.Theme`, `ziggui.App`; the build hands its executable the SDL runtime and its tests a core without it.

Since 1.0.0 ziggui includes what used to be the separate zigui library, and builds SDL 3.4.20 itself from the official release. Since 2.2.0 it also includes the web view that was the separate zigwebview package.

## Features

- **Views:** text and rich text (and one line with its search matches marked), buttons, toggles (switches or checkboxes), sliders, steppers, pickers (segmented, or a pop-up menu drawn and opened as each platform does: macOS's pop-up button, KDE's combo box, the Windows drop-down list, Material's exposed dropdown; a letter jumps to an option), segmented controls, text fields and a text editor (proportional or monospaced, with the platform's keys to move and delete a word at a time), images, icons (the Lucide set), shapes and gradients, and a `Canvas` that draws itself through a `GraphicsContext`, as SwiftUI's does (charts, a photo drawn from a texture of its own), a `ZoomableImage` that fits, zooms about the pointer (pinch, ⌘-scroll) and pans a picture under an overlay the app draws, and `CanvasMarkers` for marking one (crosshairs, rings, halos, a reticle, labels, a zoom chip, a callout, and the hit test for the nearest marker), with `AnnotationState` for marking it up: a segment's two clicks with a rubber band between, a second click off the picture clipped to its edge, and a marker taken and dragged in the picture's own units. A `SceneView` draws an app-owned 3D scene on the GPU, after SceneKit: a graph of nodes (boxes, spheres, planes, cylinders and meshes the app supplies), materials with a texture and a highlight, nodes that fade with their children, directional lights casting soft shadows, point lights, translucent surfaces, and a camera that orbits and zooms under the pointer. Stacks (and a stack that wraps into rows), grids, lists (with disclosure groups and folding outlines), tables (sortable, resizable columns, ⌘/⇧ selection by row ID that survives a re-sort or filter, filter fields under the headers, thousands of rows built only while in view), scroll views (overlay scroll bars, or kept up with `.scrollIndicators(.visible)`), tabs, navigation stacks of list rows and navigation split views, menus and context menus. Sheets, alerts and popovers. The pointer takes the system's look over a view (`.pointerStyle()`, as in SwiftUI): the I-beam over text, a resize over split-view dividers and table column edges, an open hand over what a drag moves (closed while it moves; AppKit's own hands on macOS).
- **Settings:** `Settings` draws an app's settings as macOS does, a toolbar of tabs over the selected page, and `Form`, `Section` and `LabeledContent` lay a page out in columns: labels right-aligned in one column as wide as the widest, controls beside them, checkboxes by default. `AppearancePicker` is the Appearance setting as macOS draws it: Auto, Light and Dark as little windows, the chosen one ringed. `ThemePicker` picks a theme family the same way, each drawn as a little window in its own colors and title bar, over swatches for the accent. `ThemeFamilyPicker` is its compact form: the families as mini renderings, their names as hover hints.
- **Themes:** five native-looking families (macOS, Windows 10, Windows 2000, KDE Plasma, Material), each light and dark, with an accent color. An app with its own design system can recolor every widget.
- **Rendering:** SDL_GPU on Metal, Vulkan or Direct3D 12, falling back to the software rasterizer automatically. Bundled fonts (Inter, JetBrains Mono, Noto Emoji) and a TrueType parser that treats font files as untrusted.
- **Widgets for real apps:** a virtual list that also scrolls sideways, one table for a few rows fitted inside a pane or millions built only while in view (sortable, resizable columns that scroll sideways under a header kept level, rows selected by ID with ⌘, ⇧ and the keys, a ⇧-range or ⌘A over a million rows costing nothing), a diff view whose long lines scroll or wrap (whose lines can be selected and copied, and whose hunk headers can carry links such as Stage and Discard), draggable split views, hover popovers and hover hints, chat pieces (bubbles, code blocks, disclosure groups, with a badge or count at the header's trailing edge if wanted, status marks), badges and key caps, setting, selectable and reorderable rows, outline rows that fold a tree, names renamed in place (a click on a selected one, as Finder renames), a key/value editor, a token field, a search field, a find bar (the count, Previous, Next, Done, and its keys: ⌘G, ⇧⌘G, Esc), and an in-window file-or-folder picker (a ".." row up, a filter for the files it offers, a scroll bar, and arrow keys, Return, Backspace and type-to-select).
- **The app's frame:** the macOS top band and, on Linux and Windows, a drawn title bar with the platform's window buttons and an in-window menu bar. One menu table builds both macOS's menu bar and the drawn one. A notice strip, confirm alerts, empty states, pane titles and a key-hint status line. Window memory: the window's place and size (maximized included) and every dragged split divider, held for the app to save once they stop moving and given back at launch, so a window reopens as it was left.
- **Desktop integration:** native menus, a status item or tray icon (an SNI icon over D-Bus on Linux) with a popover window of the app's views (taking the pointer as the main window does, the app's own mouse handler included), clipboard, file dialogs, revealing a file in Finder or Explorer, Linux desktop entries, and reopening the window where it was.
- **Video:** a player modeled on `AVPlayer`, drawn by the platform's own player behind the window's surface (AVFoundation on macOS), decoded by Media Foundation and drawn under it (Windows), or decoded by GStreamer and drawn in it (Linux, loaded at run time; it plays what the system's plugins decode), with standard controls painted over it: full screen, volume, skip, play, a scrubber, subtitles and speed (no skips or speed on a live stream), and room for an app's own buttons and menus among them; an audio player's bar too (speed, skip 15/30, play, the times over a scrubber, volume), after a podcast player's. A player's sound can go to one audio output, leaving the system default alone (Core Audio on macOS, Core Audio's endpoints on Windows, GStreamer's device monitor on Linux). `SystemInfoView` shows what a bug report needs: how the window draws (GPU or software, the driver, the GPU and its driver version), the media player, and the audio devices, its values selectable and `SystemReport.text` giving them as plain lines.
- **Native views:** `NativeView` places a platform view the app owns (an `NSView` such as a web view) where layout puts it, hides it while an overlay is open, and moves the keyboard between it and ziggui (macOS; Linux on X11 with GTK widgets; Windows with child windows; a placeholder elsewhere).
- **Web pages:** `WebPage` and `WebView`, after SwiftUI's: a page in the platform's own web view (WebKit on macOS; WebKitGTK on Linux under X11, loaded at run time, so apps run without it; WebView2 on Windows, through the runtime Windows 10 and 11 ship), with navigation, load failures, and bridges the page posts messages to, heard only from the origin it first loaded. ⌘C, ⌘X, ⌘V and ⌘A edit the page.
- **Secure fields:** a password field draws dots, never copies its text, and wipes it from memory when it leaves.

A component gallery shows every view in every theme, grouped as SwiftUI's documentation groups its views (Text, Controls, Pickers, Layout, Lists, Table, Navigation, Presentations, Menus & Commands, Windows, Scenes, …), every component on a card that names it (tests fail on one left out), its sidebar searchable by component name (`ziggui.WebView` finds the section that shows it), and a switch in its top bar lists the sections or every component by name.

## Platforms

| Platform | Status |
| --- | --- |
| macOS (Apple Silicon) | Full support, including video and web pages |
| Linux (x86_64, ARM) | Full support; video through GStreamer, web pages through WebKitGTK under X11 (both loaded at run time) |
| Windows (x86_64) | Full support: video through Media Foundation, web pages through the WebView2 runtime Windows 10 and 11 ship; built with mingw (MSVC builds untested) |

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
- `ZIGGUI_POPOVER_WINDOW_DUMP=<absolute path>`: write the popover window's frame to a file.
- `ZIGGUI_NO_FROST`: macOS only, leave the window glass off.

## Project layout

```
src/renderer/   pure Zig: geometry, layout, color, canvas, rasterizer, GPU scene, text, themes, state
src/scenes/     pure Zig: the 3D scene graph (math, nodes, geometry, materials, lights, cameras)
src/views/      the views: the engine, controls, containers, text, media, and the widget groups
src/sdl/        the SDL3 runtime: window, event loop, menus, tray, clipboard, dialogs, video, web pages, GPU
  macos/        the Objective-C bridge, AppKit, AVFoundation and WebKit code
  windows/      the Win32 calls SDL does not make, the child-window host, WebView2 and Media Foundation
  linux/        the D-Bus tray icon, desktop entries, GTK (native views, WebKitGTK web pages) and GStreamer video
src/module.zig  the ziggui barrel, the one module apps import
build/          the SDL3 C build
gallery/        the component gallery
fixtures/       fixed files the gallery shows
tools/icon/     mkico.py: a polygon SVG to .ico/.png/an iconset, for app icons
```

## License

MIT (see [`LICENSE`](LICENSE)).
