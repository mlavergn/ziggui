# ziggui

> Cross-platform GUI widgets for Zig apps, with zigui behind one import.

## Overview

ziggui is the GUI dependency for apps built on [zigui](https://github.com/mlavergn/zigui). It re-exports zigui's views and adds the ones zigui lacks: chat pieces, a virtual list, a diff view, table rows, and draggable split views. Widget names follow SwiftUI's where SwiftUI has one. A component gallery shows every widget.

## Requirements

- Zig 0.17.0 or later
- Target platforms: macOS (Apple Silicon), Linux (ARM / x86_64)
- Sibling checkouts of `../zigui` (branch `marc`, cloned on first build if missing) and `../styleguide`
- SDL3 for windows, which Zig fetches and builds itself

## Setup

```sh
git clone git@github.com:mlavergn/ziggui.git
cd ziggui
make build
make test
```

## Configuration

None.

## Usage

Depend on ziggui in `build.zig.zon`, then import it in `build.zig`; add `ziggui_app` only for an executable that opens a window:

```zig
const ziggui = b.dependency("ziggui", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("ziggui", ziggui.module("ziggui"));
const app = @import("ziggui").linkApp(ziggui, .{ .target = target, .optimize = optimize });
exe.root_module.addImport("ziggui_app", app);
```

Pass `linkApp` the same target and optimize mode as the dependency. Don't also depend on zigui: a second copy's types won't match ziggui's.

App code writes `ziggui.VStack`, `ziggui.HSplitView`, and so on. If you need a zigui name that ziggui doesn't re-export, add it to `src/module.zig`. An app built on ziggui follows [`../styleguide/GUIDESIGN.md`](../styleguide/GUIDESIGN.md).

Open the component gallery:

```sh
make demo
```

## Architecture

```
ziggit ──┐
         ├─► ziggui ─► zigui (engine and SDL runtime)
zigagent ┘
```

```
src/       the library: zigui re-exported, plus ziggui's widgets
gallery/   the component gallery
```
