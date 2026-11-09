# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ziggui is a Zig 0.17 module for cross-platform GUIs, and the only consumer of the sibling `../zigui`. It re-exports zigui's API and adds the widgets beyond it: the chat pieces, a virtual list, a diff view, table rows, and split views. Apps in `../` (ziggit, zigagent) depend on ziggui alone and never import zigui.

All Zig code follows `../styleguide/ZIGSTYLE.md` (a sibling checkout and its own repo; never edit it from here). The guide is authoritative: fix the code, never the guide. The two standing exceptions (view constructors as free functions, C.1.a; entry-point-only tracing, D.3.a) are described under Architecture conventions. Apps built on ziggui follow `../styleguide/GUIDESIGN.md`; its kit rules (A.1.c, B.4, C.1.c–d, C.2.b, E.4.d) bind ziggui too.

**Follow SwiftUI's naming wherever SwiftUI has an equivalent**, as upstream zigui does: `HSplitView`/`VSplitView`, `DisclosureGroup`, `GeometryReader`, `.clipped()`. Invent a name only when SwiftUI has none (`Chip`, `DiffView`).

## Build / Test

- Build: `zig build` (installs the static library)
- Tests: `zig build test --summary all` (library and `gallery/` are separate test compile steps; both run headless on zigui's core, no SDL)
- Gallery: `make demo` (`zig build run-gallery -Doptimize=ReleaseFast`; `ARGS="--dark"`, `--section <n>`, `--accent <n>`). Headless check: `zig-out/bin/ziggui-gallery --screenshot out.bmp [--section <n>] [--accent <n>] [--menu <n>] [--dark]` (`--menu` opens the Menu Bar section's menu `n`) after `zig build gallery`, then `sips -s format png out.bmp --out out.png` to look at it
- `-Dtest-filter` is declared, but it is only exported as `config.test_filter` and never passed to `addTest`, so it filters nothing.
- Format: `make format`. Lint: `make lint` (zlint against `../styleguide/zlint.json`, warnings are errors)
- Pre-commit gate: `make validate` (clean, format, lint, build, test)
- `format`, `lint`, `validate` and `buildxpin` come from `-include ../styleguide/Makefile.in`. The `Makefile` sets `ZIG_DIRS := src gallery`; add any new source root there.
- Docs: `make docs` (builds from `src/root.zig` and serves on 127.0.0.1:8080)
- The version lives in `build.zig.zon` `.version` and nowhere else; `make tag` tags and pushes it.
- After a change to a widget the apps use, rebuild ziggit and zigagent with `-Dapp` and compare their `--screenshot` output before and after (see each app's CLAUDE.md for the arguments). The rasterizer is deterministic, so a refactor should match byte for byte.

## Module layout

- `src/`: the library. Barrel `src/module.zig`, imported as `ziggui` by apps and the gallery, and as `mod` from `src/` files.
  - `ui` is zigui, whole. Below it, the zigui names the apps use are re-exported directly, grouped by area.
  - `build_tokens.zig`: `BuildTokens`, zigui's build tokens plus `label`, `separator`, `added`, `removed`, derived from `zigui.buildTheme()`. The barrel's `buildTokens` and `BuildTokens` shadow zigui's.
  - `chat.zig`: `StatusMark` (and its `StatusMarkState`), `DisclosureGroup`, `Chip`, `CodeBlock`, `Quote`, `Bubble`.
  - `index_callback.zig`: `IndexCallback` (`init` wraps a method, `bind` fixes the index).
  - `row_range.zig`: `RowRange`, the rows a `VirtualList` builds.
  - `diff_line.zig`: `DiffLine` (`hunkCount`, `hunkRow`, `revealHunk`), `DiffLineKind`, `diff_row_height`.
  - `panes.zig`: `VirtualList`, `DiffView`, `TableHeader`, `TableRow`.
  - `split_state.zig`: `SplitState`. `size` is what the user last dragged (-1 until then); layout clamps it without writing it back, and a press on the divider (`pressCallback`) starts a drag that keeps the unclamped position.
  - `split.zig`: `HSplitView`, `VSplitView`, built on zigui's `GeometryReader` and `.clipped()`.
  - `sdl_key.zig`: `SdlKey`, the SDL3 keycodes and modifier bits zigui's key handlers pass (`SDLK_*`, `SDL_KMOD_*`, stable ABI) as named constants, with `isModifier` and `isAlt`. Mirrored so key handling stays headless; the menu bar and ziggit's key map both read it, so never write a raw keycode or modifier bit.
  - `menu_bar_menu.zig`: `MenuBarMenu` (a title, its `MenuBarItem`s, a width, an optional icon; `fold` makes the one `☰` menu a narrow window shows, the menus' titles as `heading` entries) and `MenuBarItem` (`title`, `key_text`, `enabled`, `action`, `heading`; an empty title is a separator).
  - `menu_bar_options.zig`: `MenuBarOptions` (the titles' color on a colored title bar; `fill = false` keeps the bar as wide as its titles, as a `TitleBar` needs: filling, it would share the leftover with the middle and, near the narrowest, be squeezed under its titles, which then overflow onto what is before them).
  - `menu_bar_state.zig`: `MenuBarState` (the open menu, the highlighted item, an Alt tap under way, the fold last shown: `open`, `close`, `toggle`, `hover`, `key` over `MenuBarKey` (`←→` only with more than one menu, so a folded bar's stay put), `choose`, `altDown`/`otherKey`/`altUp`; and the app-facing `keyDown`/`keyUp`/`pointerDown`, which take zigui's raw SDL keycodes, and `shown`, which picks a `MenuBarMenus` form by width) and `MenuBarKey` (`fromKeycode` and its inverse `toKeycode`). A held Alt's key repeats start no new tap.
  - `menu_bar_menus.zig`: `MenuBarMenus`, a bar's menus in both forms (every one, and `MenuBarMenu.fold`'s `☰`) and the width they fold below. It keeps the allocator `init` was given and frees the folded form with it in `deinit`.
  - `menu_bar.zig`: `MenuBar`, a menu bar drawn in the window for systems without a global one, and `menu_bar_height`. Titles use zigui's `.onHover` (pointing at another title while one is open switches) and `.popoverPassthrough()` (a click on another title reaches it); the open one carries a popover of the entries, which zigui scrolls when taller than the window. The app forwards zigui's raw key-downs, key-ups (`setKeyUpHandler`) and mouse presses to the state's `keyDown`, `keyUp` and `pointerDown`, and draws `shown`'s menus; `.disabled(true)` makes the bar inert.
  - `window_actions.zig`: `WindowActions` (minimize, maximize, close callbacks).
  - `title_bar.zig`: `TitleBar(leading, middle, trailing)` over the theme family's bar (zigui's `Theme.drawTitleBar`), its middle text centered between the two, truncated, hidden under 80 pt; `WindowButtons(style, maximized, actions)`, drawn at paint time (they read the pointer for hover), `popoverPassthrough` and `modalPassthrough`, and the `WindowButtonStyle` it takes (`.windows`, `.gnome`: the platform's look, never the theme's); `title_bar_height` (32). For zigui's `custom_titlebar` windows.
  - `test_canvas.zig`: `TestCanvas`, a headless frame for the unit tests (a barrel test fixture). It collects overlays (popovers draw) and `onHover` regions; `hover(from, to)` replays a pointer move.
  - `test_menus.zig`: `TestMenus`, the menu bar's unit-test menus (File and Edit, with a separator and disabled entries), each entry counting its choice in `chosen` (a barrel test fixture).
- `src/root.zig`: exists only so `zig build docs` has a root (autodoc can't root at `module.zig`). It re-exports the barrel; don't add code to it.
- `gallery/`: the component gallery. Barrel `gallery/module.zig`, imported as `gallery`. `Gallery` holds all state and builds the view tree; `Screenshot` renders it headless. It imports `ziggui` only, never zigui. Only `gallery/main.zig` (its own root module) touches SDL, through `ziggui_app`. Every new ziggui component gets a gallery section: a `Section` variant, its `label`/`icon`, and a case in `Gallery.panel`.
- `build.zig`: `pub fn linkApp(ziggui_dep, opts)` forwards to zigui's `linkApp` on the same zigui dependency the `ziggui` module imports, so the app runtime and the module share one zigui (and its types). Apps import the result as `ziggui_app`; only executables that import it link SDL3 (fetched lazily, on first use), so the library and every view test headless.
  - Every declaration of the zigui dependency (the module, `linkApp`, `addGallery`) passes identical args (`target`, `optimize`). Different args make Zig build two zigui modules, and their `View`, `Theme` and so on no longer match. For the same reason apps never depend on zigui directly.
  - The SDL runtime stays in zigui; ziggui only forwards `linkApp`, so there is one SDL integration to maintain.
- `zig-pkg/`, `.zig-cache/`, `zig-out/`: fetched or generated; never hand-edit.

## Architecture conventions

- **The facade rule:** apps import `ziggui` and `ziggui_app` only. When an app needs a zigui name that is not re-exported, add it to the barrel (documented, in its area) so apps keep writing `ziggui.X`; apps never write `ziggui.ui.X`.
- **Where a change goes:** a widget composed from zigui's public API goes here. A change to the engine (a new view kind, a modifier, a paint primitive, an SDL hook) goes in `../zigui` on its `marc` branch, follows zigui's own CLAUDE.md, and is SwiftUI-shaped. zigui gained `GeometryReader`, `.clipped()` and `buildTheme()` this way so the split views could live here. zigui's `make validate` already fails at lint (about 98 warnings, before ziggui's changes), so judge an engine change by its build, its tests, and no new lint warnings.
- **Colors only ziggui uses** (`label`, `separator`, the diff greens and reds) are derived in `build_tokens.zig` from `zigui.buildTheme()`. Never add them to zigui's `BuildTokens` or `Palette`.
- **`GeometryReader` builds its content at paint time.** By then the build arena has ended, so zigui points `buildAlloc()` at `ctx.arena` while the content builds; `buildTokens()` still reads the frame's theme. Split panes are framed to their size and `.clipped()`. The drag strip is registered after the panes because hit regions are tested last-registered-first.
- **`VirtualList` and the table rows build their stacks with `zigui.view.makeStackFromSlice`**, not a `VStack` over a slice. A `VStack` changes spacing and alignment, which breaks the app screenshot match.
- **The ZIGSTYLE exception (C.1.a):** view constructors are free, PascalCase functions (`Chip(...)`, `HSplitView(...)`), as in zigui, so ziggui's widgets read like the zigui views beside them. Only view constructors are exempt: every other function, private helpers included, is a method on a struct (`IndexCallback.bind`, `RowRange.visible`, `DiffLine.hunkCount`; a private struct like `Table`, `DiffModel` or `Entries` holds the helpers). Each file with view constructors opens with the `//!` doc, then `// zlint-disable case-convention` under a comment saying why.
- Enum variants are camelCase (C.2: `.hunkHeader`), although zigui's are snake_case (`.chevron_down`); zlint does not check this. Struct-local test types (`Probe`) open with `const Self = @This();` too.
- No local aliases (B.4.a): write `zigui.View`, `zigui.Color`, never `const View = zigui.View;`, and in tests `mod.SdlKey.left_alt`, never `const left_alt = mod.SdlKey.left_alt;` (`const allocator = std.testing.allocator;` is the guide's own test pattern and stays). Imports go `std`, `log`, `mod`, then `zigui` (B.2.b).
- Spell names out: `title_bar_height`, `min_width`, `line_width`, `center_x`, `horizontalGradient`, never `title_bar_h`, `min_w`, `w`, `cx` or `hGradient`. zigui's own `ScrollState.viewport_h` and `content_h` are not ziggui's to rename.
- One primary public struct per file, the file named for it in snake_case (`build_tokens.zig` → `BuildTokens`). Supporting types go above it. A widget file (`chat.zig`, `panes.zig`, `split.zig`, `menu_bar.zig`, `title_bar.zig`) holds view constructors and no public struct: its private helper structs go above the constructors, and a public type the constructors take gets a file of its own (`split_state.zig`, `diff_line.zig`, `menu_bar_options.zig`, `window_actions.zig`). A supporting enum used only by one constructor stays beside it (`StatusMarkState`, `WindowButtonStyle`). Every struct and enum, supporting ones included, opens with `const Self = @This();`. Methods take `*Self`, or `*const Self` when read-only, including on enums. Order: `init`, `deinit`, public API, then private helpers.
- `init` builds a local `const self = Self{ ... };` and returns it. Types that hold pointers into themselves are heap-allocated with `create`/`destroy` (`TestCanvas`).
- Import siblings only through the barrel. Compile-time invariants (`is_debug`) live in the barrels; never `@import("builtin")` elsewhere (executables read `gallery.is_debug`).
- View constructors allocate from `zigui.buildAlloc()` and read colors from `mod.buildTokens()`; they run once per frame inside `beginBuild`/`endBuild`, or at paint time inside a `GeometryReader`.
- Every file except `src/root.zig` declares `std.log.scoped(.ziggui_<file>)` (the barrels `.ziggui_module` and `.ziggui_gallery_module`). **The tracing exception (D.3.a):** only entry points (`main`, `Window.run`, stateful `init`s, `Screenshot.render`) trace with `log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name })`. View constructors and the methods they call (`resolved`, `visible`, `bind`) run per frame, per row, so tracing them would flood a Debug build's stderr every frame. A file with nothing to trace says so in its `test` block (`// Nothing here does I/O to trace.` and `_ = log;`).
- Errors: a view constructor cannot fail, so an allocation in the build arena ends `catch @panic("oom")`, as zigui's own constructors do. Never swallow one with `catch ""` or a fallback value. Format with `Allocator.print`, not the deprecated `std.fmt.allocPrint`.
- Every public declaration gets a `///` doc: struct fields, constants, and each barrel re-export included. A function's doc (E.1.b) is a one-line summary, a blank `///`, one `` - `name`: `` bullet per parameter (`self` too), then `- Returns:` whenever it returns a value. An error union counts (`- Returns: nothing; propagates allocation failure.`); a plain `void` function has no `Returns` line. There is no `Parameters:` header.
- Tests go after the `// Unit Tests` divider. They use `std.testing.allocator`, `defer` every `deinit`, and start with `test { std.testing.refAllDecls(...) }`. Draw and tap with `mod.TestCanvas` (`begin`, build, `end`, `render`, `tap`).

## Project-state heads-ups

- ziggui builds against `../zigui` on its `marc` branch. Push `marc` before a fresh clone needs it. ziggit and zigagent clone ziggui from `git@github.com:mlavergn/ziggui.git`, which must exist and be pushed before a fresh app clone can fetch it.
- The gallery executable is declared only when ziggui is the root build (`b.dep_prefix.len == 0`), as zigui does for its showcase, so packages depending on ziggui never fetch SDL for it. ziggui's own configure does fetch it, lazily, on first use.
- The first build clones missing sibling dependencies (`zigbuildx.Deps.cloneMissing`). App builds also `git pull` sibling repos that are clean and have an upstream (zigbuildx sync); dirty repos and repos without an upstream are skipped with a warning.
- Not yet tested by hand: dragging a split divider with a real mouse in a window. Unit tests cover a press arming the drag and the drag math, and the gallery's Split Views section is the place to try it.
- `ziggui.BuildTokens` mirrors zigui's `BuildTokens` field by field. When zigui adds a token, add it to `src/build_tokens.zig`.
