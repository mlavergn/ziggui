# ziggui

> A SwiftUI-style GUI library for Zig: a pure-Zig renderer, its views, and an SDL3 runtime, behind one import.

## Overview

ziggui draws declarative, SwiftUI-shaped view trees (`VStack`, `Toggle`, `NavigationSplitView`, `GeometryReader`, …) with five native-looking theme families (macOS, Windows 10, Windows 2000, KDE Plasma, Material). Layout, text, themes and a software rasterizer are pure Zig and test headless; on screen, rendering goes through SDL_GPU (Metal, Vulkan, D3D12) with an automatic software fallback. Beyond the standard views it has chat pieces, a virtual list that also scrolls sideways, a diff view (long lines scroll sideways or wrap), table rows, draggable split views, a hover popover, and for Linux and Windows an in-window menu bar and a title bar with the platform's window buttons. Names follow SwiftUI's where SwiftUI has one. A component gallery shows every view.

Since 1.0.0 ziggui includes what used to be the separate zigui library, and builds SDL 3.4.20 itself from the official release.

## Requirements

- Zig 0.17.1 or later (0.17.0 miscompiles `@intCast` in optimized builds)
- Target platforms: macOS (Apple Silicon), Linux (ARM / x86_64), Windows (x86_64)
- A sibling checkout of `../styleguide` (for `make format`, `make lint`, `make validate`)
- Nothing to install for SDL3: Zig fetches the release and builds it on first use (Linux headers come from castholm/SDL_linux_deps)

## Setup

```sh
git clone git@github.com:mlavergn/ziggui.git
cd ziggui
make build
make test
```

`make test` never compiles or links SDL. The SDL runtime's own tests are a separate step, which builds SDL; for a foreign target it compiles them without running them:

```sh
zig build test-sdl --summary all
zig build test-sdl -Dtarget=x86_64-windows
```

## Configuration

Build options, beyond Zig's standard target and optimize:

- `-Dtest-filter=<text>`: run only the unit tests whose names match.
- `-Dsdl3-prefix=<dir>`: link a prebuilt SDL3 (`include/`, `lib/`) instead of building the release.
- `-Dwindows-console`: keep a console window for the Windows gallery (log output).

The runtime reads optional environment variables:

- `ZIGGUI_SOFTWARE`: render with the software rasterizer instead of the GPU.
- `ZIGGUI_FRAME_LOG`: log per-frame timing.
- `ZIGGUI_NO_FROST`: macOS only, leave the window glass off.

## Usage

Depend on ziggui in `build.zig.zon`, then in `build.zig` give the executable the app module from `linkApp` and the tests the core module, both under the name `ziggui`:

```zig
const ziggui_dep = b.dependency("ziggui", .{ .target = target, .optimize = optimize });
const ziggui_build = @import("ziggui");
exe.root_module.addImport("ziggui", ziggui_build.linkApp(ziggui_dep, .{ .target = target, .optimize = optimize }));
tests.root_module.addImport("ziggui", ziggui_dep.module("ziggui"));
```

Pass `linkApp` the same target and optimize mode as the dependency, and every call the same options; a mismatch panics at configure. Only the executable builds and links SDL3, and a dependent package fetches it only through `linkApp`; tests never compile or link it. One compilation holds only one of the two modules, so a module of yours that both the executable and the tests import is declared twice, once over each.

Code writes `ziggui.X` throughout: `ziggui.VStack`, `ziggui.HSplitView`, `ziggui.Theme`. The window and its event loop are `ziggui.App.shared()`, present only in the executable's build. An app built on ziggui follows [`../styleguide/GUIDESIGN.md`](../styleguide/GUIDESIGN.md).

Open the component gallery:

```sh
make demo
```

Render one gallery section without a window:

```sh
zig build gallery -Doptimize=ReleaseFast
zig-out/bin/ziggui-gallery --screenshot out.bmp --section 7
zig-out/bin/ziggui-gallery --screenshot gpu.bmp --section 7 --gpu   # through SDL_GPU, offscreen
```

## Architecture

```
ziggit ──┐
         ├─► ziggui ─► SDL3 (built from the 3.4.20 release)
zigagent ┘
```

```
src/renderer/   pure Zig: geometry, layout, color, canvas, rasterizer, GPU scene, text, themes, state
src/views/      the views: engine (core/), controls/, containers/, text/, and the widget groups
src/sdl/        the SDL3 runtime: window, event loop, menus, tray, clipboard, dialogs, GPU
src/module.zig  the ziggui barrel
build/          the SDL3 C build
gallery/        the component gallery
tools/icon/     mkico.py: a polygon SVG to .ico/.png/an iconset, for app icons
```
