//! Library barrel for ziggui: zigui's API and ziggui's own widgets, behind
//! one import.
//!
//! Apps depend on ziggui alone and never import zigui. Everything zigui
//! exports is reachable as `ziggui.ui.X`; the names apps use are re-exported
//! directly, so app code writes `ziggui.X` throughout. When an app needs a
//! zigui name that is not re-exported here, add it here (see CLAUDE.md).
//! ziggui's widgets follow SwiftUI's names where SwiftUI has one.

const std = @import("std");
const log = std.log.scoped(.ziggui_module);
const builtin = @import("builtin");
const zigui = @import("zigui");

/// Whether this is a debug build.
pub const is_debug = builtin.mode == .debug;

/// zigui, whole: every name it exports, for those not re-exported below.
pub const ui = zigui;

// -----------------------------------------------------------------------------
// zigui: views and layout

/// A node of the view tree.
pub const View = zigui.View;
/// zigui's view module, for its lower-level constructors (`makeStackFromSlice`).
pub const view = zigui.view;
/// Children stacked vertically.
pub const VStack = zigui.VStack;
/// Children side by side.
pub const HStack = zigui.HStack;
/// Children layered front to back.
pub const ZStack = zigui.ZStack;
/// Flexible space in a stack.
pub const Spacer = zigui.Spacer;
/// A hairline across a stack.
pub const Divider = zigui.Divider;
/// A view that draws nothing.
pub const Empty = zigui.Empty;
/// Content built from the size it is laid out at.
pub const GeometryReader = zigui.GeometryReader;
/// A scrolling viewport with a fixed offset.
pub const ScrollView = zigui.ScrollView;
/// A scrolling viewport whose offset lives in a `ScrollState`.
pub const ScrollViewState = zigui.ScrollViewState;
/// A scroll view's app-owned offset and extents.
pub const ScrollState = zigui.ScrollState;
/// A scroll view's frame and state, collected while painting.
pub const ScrollRegion = zigui.ScrollRegion;
/// One tab of a `TabView`.
pub const Tab = zigui.Tab;
/// Tabs over one shown page.
pub const TabView = zigui.TabView;
/// A sidebar | detail split with a fixed sidebar.
pub const NavigationSplitView = zigui.NavigationSplitView;
/// A sidebar list driven by a selection binding.
pub const Sidebar = zigui.Sidebar;
/// One row of a `Sidebar`.
pub const SidebarItem = zigui.SidebarItem;
/// A vertical group of radio buttons.
pub const RadioGroup = zigui.RadioGroup;
/// One column of a data table (and of `TableHeader`/`TableRow`).
pub const DataColumn = zigui.DataColumn;

// -----------------------------------------------------------------------------
// zigui: text, images and shapes

/// One line of text.
pub const Text = zigui.Text;
/// Text that wraps to the width it is given.
pub const WrappedText = zigui.WrappedText;
/// A wrapped paragraph of styled spans.
pub const RichText = zigui.RichText;
/// One styled run of a `RichText`.
pub const Span = zigui.Span;
/// An icon from the icon font.
pub const Icon = zigui.Icon;
/// The icon font's glyph names.
pub const IconName = zigui.IconName;
/// A filled rectangle.
pub const Rectangle = zigui.Rectangle;
/// A filled circle.
pub const Circle = zigui.Circle;

// -----------------------------------------------------------------------------
// zigui: controls and focus

/// A push button.
pub const Button = zigui.Button;
/// A push button with a role (default, cancel, destructive).
pub const ButtonRoled = zigui.ButtonRoled;
/// A push button with an icon.
pub const ButtonIcon = zigui.ButtonIcon;
/// A push button with an icon and a role.
pub const ButtonIconRoled = zigui.ButtonIconRoled;
/// A borderless icon button.
pub const IconButton = zigui.IconButton;
/// A switch over a `Binding(bool)`.
pub const Toggle = zigui.Toggle;
/// A pop-up menu over a selection binding.
pub const Picker = zigui.Picker;
/// A one-line text field.
pub const TextField = zigui.TextField;
/// A multi-line text editor.
pub const TextEditor = zigui.TextEditor;
/// A text field's buffer, caret and selection.
pub const TextFieldState = zigui.TextFieldState;
/// Focuses a text field.
pub const setFocus = zigui.setFocus;
/// Clears the keyboard focus.
pub const clearFocus = zigui.clearFocus;
/// The focused text field, if any.
pub const focusedField = zigui.focusedField;
/// How many clicks the current tap is (2 for a double click).
pub const tapCount = zigui.tapCount;
/// Whether Shift was held at the current tap's press (extend a selection).
pub const clickShift = zigui.clickShift;
/// Whether ⌘ (Ctrl off macOS) was held at the current tap's press (add to a selection).
pub const clickCmd = zigui.clickCmd;
/// Records the modifiers held at a press; the app runtime calls it, and tests do.
pub const setClickMods = zigui.setClickMods;
/// Sets the handler a tapped link calls.
pub const setLinkHandler = zigui.setLinkHandler;

// -----------------------------------------------------------------------------
// zigui: state and callbacks

/// A value views observe.
pub const State = zigui.State;
/// A read/write handle on a `State`.
pub const Binding = zigui.Binding;
/// A tap handler.
pub const Callback = zigui.Callback;
/// Wraps a method taking a typed context as a `Callback`.
pub const actionCtx = zigui.actionCtx;
/// A `Callback` that sets a selection binding to a value.
pub const selectAction = zigui.selectAction;

// -----------------------------------------------------------------------------
// zigui: theme and color

/// A theme: palette, metrics and painter.
pub const Theme = zigui.Theme;
/// The theme apps start with.
pub const default_theme = zigui.default_theme;
/// The registered theme families.
pub const theme_registry = zigui.theme_registry;
/// A theme family (macOS, Windows, KDE, Material).
pub const ThemeFamily = zigui.ThemeFamily;
/// A theme family's theme for a color scheme.
pub const themeForScheme = zigui.themeForScheme;
/// Light or dark.
pub const ColorScheme = zigui.ColorScheme;
/// The macOS themes.
pub const macos = zigui.macos;
/// An RGBA color.
pub const Color = zigui.Color;

// -----------------------------------------------------------------------------
// zigui: geometry

/// A size in points.
pub const Size = zigui.Size;
/// A point in points.
pub const Point = zigui.Point;
/// A rectangle in points.
pub const Rect = zigui.Rect;
/// Horizontal or vertical.
pub const Axis = zigui.Axis;

// -----------------------------------------------------------------------------
// zigui: frames and rendering (headless drawing and app harnesses)

/// Opens the build arena for a frame.
pub const beginBuild = zigui.beginBuild;
/// Closes the build arena.
pub const endBuild = zigui.endBuild;
/// The build arena, for composed constructors.
pub const buildAlloc = zigui.buildAlloc;
/// The whole theme published for the frame.
pub const buildTheme = zigui.buildTheme;
/// Publishes a theme's tokens for the frame.
pub const setThemeTokens = zigui.setThemeTokens;
/// What a frame is painted with.
pub const Context = zigui.Context;
/// Lays out and paints a view tree.
pub const render = zigui.render;
/// A tap region registered while painting.
pub const HitRegion = zigui.HitRegion;
/// Replays a tap on a frame's regions.
pub const dispatchTap = zigui.dispatchTap;
/// A popover or sheet waiting to be drawn.
pub const OverlayReq = zigui.OverlayReq;
/// The draw commands a frame emits.
pub const Canvas = zigui.Canvas;
/// The software rasterizer.
pub const raster = zigui.raster;
/// Pixels the rasterizer draws into.
pub const Framebuffer = zigui.Framebuffer;
/// A font face.
pub const Font = zigui.Font;
/// The fallback faces text draws with.
pub const FontSet = zigui.FontSet;
/// Rasterized glyphs of a face.
pub const GlyphCache = zigui.GlyphCache;

// -----------------------------------------------------------------------------
// ziggui: theme tokens

/// The build-time theme colors, zigui's plus ziggui's (`label`, `separator`,
/// `added`, `removed`).
pub const BuildTokens = @import("build_tokens.zig").BuildTokens;
/// The build-time theme colors for the frame.
pub const buildTokens = BuildTokens.current;

// -----------------------------------------------------------------------------
// ziggui: chat

/// Where the thing a `StatusMark` stands for is.
pub const StatusMarkState = @import("chat.zig").StatusMarkState;
/// A round mark for a row's state.
pub const StatusMark = @import("chat.zig").StatusMark;
/// A header that folds content away, like SwiftUI's `DisclosureGroup`.
pub const DisclosureGroup = @import("chat.zig").DisclosureGroup;
/// A small capsule: a mode, a model, an attachment.
pub const Chip = @import("chat.zig").Chip;
/// Preformatted text on a tinted panel.
pub const CodeBlock = @import("chat.zig").CodeBlock;
/// A quoted block behind a bar.
pub const Quote = @import("chat.zig").Quote;
/// A message bubble.
pub const Bubble = @import("chat.zig").Bubble;

// -----------------------------------------------------------------------------
// ziggui: panes

/// A callback that takes a row index (`init` wraps a method, `bind` fixes the index).
pub const IndexCallback = @import("index_callback.zig").IndexCallback;
/// The rows a `VirtualList` builds (`visible` says which are in view).
pub const RowRange = @import("row_range.zig").RowRange;
/// What a `DiffLine` is.
pub const DiffLineKind = @import("diff_line.zig").DiffLineKind;
/// One row of a `DiffView` (`hunkCount`, `hunkRow` and `revealHunk` work on a diff).
pub const DiffLine = @import("diff_line.zig").DiffLine;
/// The height of one diff row, in points.
pub const diff_row_h = @import("diff_line.zig").diff_row_h;
/// A list that builds only the rows in view.
pub const VirtualList = @import("panes.zig").VirtualList;
/// A unified diff over a `VirtualList`.
pub const DiffView = @import("panes.zig").DiffView;
/// A table's header row.
pub const TableHeader = @import("panes.zig").TableHeader;
/// One table row.
pub const TableRow = @import("panes.zig").TableRow;

// -----------------------------------------------------------------------------
// ziggui: split views

/// Where a split view's divider sits.
pub const SplitState = @import("split_state.zig").SplitState;
/// Two panes side by side, like SwiftUI's `HSplitView`.
pub const HSplitView = @import("split.zig").HSplitView;
/// Two panes stacked, like SwiftUI's `VSplitView`.
pub const VSplitView = @import("split.zig").VSplitView;

// -----------------------------------------------------------------------------
// Test Fixtures

/// A headless frame for the unit tests.
pub const TestCanvas = @import("test_canvas.zig").TestCanvas;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("build_tokens.zig");
    _ = @import("chat.zig");
    _ = @import("index_callback.zig");
    _ = @import("row_range.zig");
    _ = @import("diff_line.zig");
    _ = @import("panes.zig");
    _ = @import("split_state.zig");
    _ = @import("split.zig");
    _ = @import("test_canvas.zig");
}
