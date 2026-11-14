//! The ziggui barrel: the renderer, the views and, in an app build, the SDL
//! runtime, behind one import.
//!
//! Consumers import `ziggui` and write `ziggui.X`. Two builds share this file:
//! the core one (`config.with_sdl = false`, for tests and libraries) and the
//! app one `linkApp` returns, which adds the SDL runtime as `ziggui.sdl` and
//! its app-facing types (`App`, `AppConfig`, `MenuBarExtra`, ...) at the top
//! level (`void` in the core build). Both sit on the same `renderer` and
//! `views` modules, so their types agree.
//!
//! Every public name of the two is re-exported here flat, each from the module
//! that owns it (`Binding` is the renderer's, which the views re-export). The
//! root `Icon` and `Image` are the views; the renderer's types of those names
//! are `IconName` and `ImagePixels` here.

const std = @import("std");
const log = std.log.scoped(.ziggui_module);
const builtin = @import("builtin");
const config = @import("config");
const renderer = @import("renderer");
const views = @import("views");

/// Whether this is a debug build.
pub const is_debug = builtin.mode == .debug;

/// The library version, from `build.zig.zon` (checked when the module compiles).
pub const version = std.SemanticVersion.parse(config.version) catch
    @compileError("build.zig.zon's .version is not a semantic version");

/// The SDL runtime: the window, its event loop, menus and tray. Present only
/// in the app build (`linkApp`); empty in the core one. Its app-facing types
/// are also below under "App runtime" (`void` in the core build).
pub const sdl = if (config.with_sdl) @import("sdl") else struct {};

// -----------------------------------------------------------------------------
// Geometry

/// A point in points.
pub const Point = renderer.Point;
/// A size in points.
pub const Size = renderer.Size;
/// A rectangle in points.
pub const Rect = renderer.Rect;
/// Per-side spacing (top, leading, bottom, trailing).
pub const EdgeInsets = renderer.EdgeInsets;
/// A horizontal and a vertical alignment guide together.
pub const Alignment = renderer.Alignment;
/// A horizontal alignment guide.
pub const HorizontalAlignment = renderer.HorizontalAlignment;
/// A vertical alignment guide.
pub const VerticalAlignment = renderer.VerticalAlignment;
/// Horizontal or vertical.
pub const Axis = renderer.Axis;

// -----------------------------------------------------------------------------
// Color and drawing

/// An RGBA color.
pub const Color = renderer.Color;
/// A color as four 8-bit channels.
pub const Rgba8 = renderer.Rgba8;
/// An 8-bit coverage mask (a rasterized glyph).
pub const Coverage = renderer.Coverage;
/// The RGBA8 pixels an `Image` draws, rows top-down.
pub const ImagePixels = renderer.Image;
/// One drawing operation.
pub const DrawCommand = renderer.DrawCommand;
/// A `DrawCommand.fillRoundedRect` payload.
pub const FillRoundedRectCommand = renderer.FillRoundedRectCommand;
/// A `DrawCommand.strokeRoundedRect` payload.
pub const StrokeRoundedRectCommand = renderer.StrokeRoundedRectCommand;
/// A `DrawCommand.linearGradient` payload.
pub const LinearGradientCommand = renderer.LinearGradientCommand;
/// A `DrawCommand.line` payload.
pub const LineCommand = renderer.LineCommand;
/// A `DrawCommand.glyph` payload.
pub const GlyphCommand = renderer.GlyphCommand;
/// A `DrawCommand.image` payload.
pub const ImageCommand = renderer.ImageCommand;
/// A `DrawCommand.blurRect` payload.
pub const BlurRectCommand = renderer.BlurRectCommand;
/// A `DrawCommand.pushClip` payload.
pub const PushClipCommand = renderer.PushClipCommand;
/// The draw commands a frame emits.
pub const Canvas = renderer.Canvas;
/// Pixels the rasterizer draws into.
pub const Framebuffer = renderer.Framebuffer;
/// The software rasterizer.
pub const Rasterizer = renderer.Rasterizer;
/// One instanced quad of the GPU scene.
pub const Instance = renderer.Instance;
/// A run of the GPU scene's instances, or a blur break.
pub const Step = renderer.Step;
/// A `Step.draw` payload.
pub const DrawStep = renderer.DrawStep;
/// A `Step.blur` payload.
pub const BlurStep = renderer.BlurStep;
/// A pending texture-atlas region upload.
pub const AtlasUpload = renderer.AtlasUpload;
/// The GPU scene's texture atlas bookkeeping.
pub const TextureAtlas = renderer.TextureAtlas;
/// A canvas translated for the GPU backend.
pub const GpuScene = renderer.GpuScene;

// -----------------------------------------------------------------------------
// Layout

/// A size a parent proposes to a child.
pub const Proposal = renderer.Proposal;
/// The intrinsic sizing of a layout leaf.
pub const SizingHints = renderer.SizingHints;
/// The direction a layout stack runs in.
pub const Direction = renderer.Direction;
/// A stack in the layout tree.
pub const StackNode = renderer.StackNode;
/// Padding around a child in the layout tree.
pub const PaddingNode = renderer.PaddingNode;
/// A frame modifier in the layout tree.
pub const FrameNode = renderer.FrameNode;
/// A spacer in the layout tree.
pub const SpacerNode = renderer.SpacerNode;
/// A leaf that measures itself against the live proposal.
pub const MeasuredNode = renderer.MeasuredNode;
/// A node of the layout tree.
pub const Node = renderer.Node;
/// The placement the arrange pass produces for a node.
pub const LayoutResult = renderer.LayoutResult;
/// One stack child's main-axis bounds.
pub const FlexItem = renderer.FlexItem;
/// Per-call scratch storage for a stack's children.
pub const Scratch = renderer.Scratch;
/// Shares a stack's main-axis length among its children.
pub const SpaceDistributor = renderer.SpaceDistributor;
/// Measures and arranges layout trees (`LayoutEngine.shared()`).
pub const LayoutEngine = renderer.LayoutEngine;

// -----------------------------------------------------------------------------
// State and animation

/// Something notified when state it depends on changes.
pub const Observer = renderer.Observer;
/// A value views observe.
pub const State = renderer.State;
/// A read/write handle on a `State`.
pub const Binding = renderer.Binding;
/// A timing curve.
pub const Easing = renderer.Easing;
/// One value animation.
pub const Tween = renderer.Tween;
/// The in-flight tweens of an app.
pub const Animator = renderer.Animator;

// -----------------------------------------------------------------------------
// Text

/// A parsed TrueType face (system fonts reach text through `TtfFont.fromExternal`).
pub const TtfFont = renderer.TtfFont;
/// Why a blob failed to parse as a TrueType font.
pub const TtfParseError = renderer.TtfParseError;
/// A codepoint resolved to the face that carries its glyph.
pub const ResolvedGlyph = renderer.ResolvedGlyph;
/// A glyph's coverage bitmap and its placement.
pub const RasterGlyph = renderer.RasterGlyph;
/// The callbacks of a face another engine (stb_truetype) reads.
pub const ExternalFace = renderer.ExternalFace;
/// Rasterized glyphs of a face.
pub const GlyphCache = renderer.GlyphCache;
/// A glyph and its pen position on a line.
pub const PositionedGlyph = renderer.PositionedGlyph;
/// One line of word-wrapped text.
pub const WrappedLine = renderer.WrappedLine;
/// Measures, lays out and wraps text in one face.
pub const TextShaper = renderer.TextShaper;
/// A font face.
pub const Font = renderer.Font;
/// Paints text and icon glyphs into a canvas; `TextPainter.shared().setGamma` sets the coverage gamma.
pub const TextPainter = renderer.TextPainter;
/// A text style's face selection (weight, italic, monospace).
pub const FontStyle = renderer.FontStyle;
/// The fallback faces text draws with.
pub const FontSet = renderer.FontSet;

// -----------------------------------------------------------------------------
// Themes

/// Light or dark.
pub const ColorScheme = renderer.ColorScheme;
/// A font weight.
pub const FontWeight = renderer.FontWeight;
/// A point size, weight and line-height multiple.
pub const TextStyle = renderer.TextStyle;
/// The semantic appearance of a control.
pub const Role = renderer.Role;
/// What a floating panel is for.
pub const PanelKind = renderer.PanelKind;
/// The interaction state of a control.
pub const ControlState = renderer.ControlState;
/// Semantic color roles for one color scheme.
pub const Palette = renderer.Palette;
/// A theme's text styles.
pub const Typography = renderer.Typography;
/// A theme's spacing, sizing, and radius metrics.
pub const Metrics = renderer.Metrics;
/// Everything a painter needs to draw chrome.
pub const Surface = renderer.Surface;
/// A theme's vtable of chrome-drawing functions.
pub const Painter = renderer.Painter;
/// The named text styles `Theme.font` takes.
pub const TextStyleName = renderer.TextStyleName;
/// A theme: palette, metrics and painter (`Theme.default` is the one apps start with).
pub const Theme = renderer.Theme;
/// A theme family (macOS, Windows, KDE, Material): `ThemeFamily.all`, and `forScheme` for its theme.
pub const ThemeFamily = renderer.ThemeFamily;
/// The macOS themes.
pub const MacosTheme = renderer.MacosTheme;
/// The Windows 2000 themes.
pub const Win2000Theme = renderer.Win2000Theme;
/// The Windows 10 themes.
pub const Windows10Theme = renderer.Windows10Theme;
/// The KDE Plasma themes.
pub const KdeTheme = renderer.KdeTheme;
/// The Material themes.
pub const MuiTheme = renderer.MuiTheme;
/// An app's accent, a setting: the brand's orange or one of macOS's (`theme` applies it, the macOS dark on black).
pub const Accent = views.Accent;

// -----------------------------------------------------------------------------
// Icons

/// The icon font's glyph names (the renderer's `Icon`; the root `Icon` is the view).
pub const IconName = renderer.Icon;

// -----------------------------------------------------------------------------
// View engine

/// A node of the view tree.
pub const View = views.View;
/// What a view is: one variant per kind of view.
pub const Kind = views.Kind;
/// A `Text`'s payload.
pub const TextData = views.TextData;
/// A `WrappedText`'s payload.
pub const WrappedTextData = views.WrappedTextData;
/// A `RichText`'s payload.
pub const RichTextData = views.RichTextData;
/// A `Spacer`'s payload.
pub const SpacerData = views.SpacerData;
/// A shape's payload.
pub const ShapeData = views.ShapeData;
/// A stack's payload.
pub const StackData = views.StackData;
/// A button's payload.
pub const ButtonData = views.ButtonData;
/// A switch's payload.
pub const ToggleData = views.ToggleData;
/// A slider's payload.
pub const SliderData = views.SliderData;
/// A stepper's payload.
pub const StepperData = views.StepperData;
/// A progress bar's payload.
pub const ProgressData = views.ProgressData;
/// An image's payload.
pub const ImageData = views.ImageData;
/// A label's payload.
pub const LabelData = views.LabelData;
/// An icon's payload.
pub const IconData = views.IconData;
/// An icon button's payload.
pub const IconButtonData = views.IconButtonData;
/// A fixed-offset scroll view's payload.
pub const ScrollData = views.ScrollData;
/// A text field's payload.
pub const TextFieldData = views.TextFieldData;
/// A text editor's payload.
pub const TextEditorData = views.TextEditorData;
/// A state-driven scroll view's payload.
pub const ScrollStateData = views.ScrollStateData;
/// A `GeometryReader`'s payload.
pub const GeometryData = views.GeometryData;
/// A picker's payload.
pub const PickerData = views.PickerData;
/// A `Drawing`'s payload.
pub const DrawingData = views.DrawingData;
/// The modifiers applied around a view's content.
pub const Modifiers = views.Modifiers;
/// A `.sheet`/`.alert`/`.popover` modifier.
pub const OverlayModifier = views.OverlayModifier;
/// A `.frame(...)` modifier's sizes and alignment.
pub const FrameSpecification = views.FrameSpecification;
/// What a background or shape is filled with.
pub const Fill = views.Fill;
/// A two-color linear gradient fill.
pub const GradientFill = views.GradientFill;
/// A translucent, blurred background.
pub const Material = views.Material;
/// A material's tint scale and blur.
pub const MaterialSpecification = views.MaterialSpecification;
/// How a presented overlay is drawn.
pub const OverlayStyle = views.OverlayStyle;
/// Named typographic styles.
pub const FontToken = views.FontToken;
/// The outline a shape view fills.
pub const ShapeKind = views.ShapeKind;
/// The semantic appearance of a button.
pub const ButtonRole = views.ButtonRole;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection).
pub const Callback = views.Callback;
/// What `View.onHover` calls: true on entering a view, false on leaving it.
pub const HoverCallback = views.HoverCallback;
/// What `View.onDrag` and `PointerInput.armDrag` call as the pointer moves.
pub const DragCallback = views.DragCallback;
/// A scroll view's app-owned offset and extents.
pub const ScrollState = views.ScrollState;
/// A scroll view's frame and state, collected while painting.
pub const ScrollRegion = views.ScrollRegion;
/// The overlay scrollbars a scroll view draws and drags.
pub const Scrollbar = views.Scrollbar;
/// A scrollbar thumb along one axis.
pub const Thumb = views.Thumb;
/// What a frame is painted with.
pub const Context = views.Context;
/// Where the input sinks stood before clipped content painted.
pub const InputMarks = views.InputMarks;
/// What a tap region does.
pub const HitAction = views.HitAction;
/// A slider track's tap action.
pub const SliderTrack = views.SliderTrack;
/// A stepper half's tap action.
pub const StepAction = views.StepAction;
/// A picker segment's tap action.
pub const SelectValue = views.SelectValue;
/// A text field's or editor's clickable text geometry.
pub const TextClick = views.TextClick;
/// A tap region registered while painting.
pub const HitRegion = views.HitRegion;
/// An `onHover` region registered while painting.
pub const HoverRegion = views.HoverRegion;
/// An accessibility role.
pub const A11yRole = views.A11yRole;
/// One node of the accessibility tree.
pub const A11yNode = views.A11yNode;
/// A popover or sheet waiting to be drawn.
pub const OverlayRequest = views.OverlayRequest;
/// A selectable paragraph's geometry for one frame.
pub const SelectHit = views.SelectHit;
/// What a `Drawing` paints with.
pub const Pen = views.Pen;
/// The build arena, published theme and tokens, viewport, wrap cache and link
/// handler: `BuildScope.shared().begin(arena)`/`end()`, `allocator()`,
/// `setTheme(theme)`, `theme()`, `tokens()`, `viewport()`, `print(...)`.
pub const BuildScope = views.BuildScope;
/// The build-time theme colors, `label`, `separator`, `added` and `removed`
/// included: `BuildScope.shared().tokens()`.
pub const BuildTokens = views.BuildTokens;
/// A cache of wrapped-text and rich-text layouts.
pub const WrapCache = views.WrapCache;
/// Builds stack views from tuples or slices (`StackBuilder.fromSlice` keeps its slice).
pub const StackBuilder = views.StackBuilder;
/// The built-in controls' geometry.
pub const ControlMetrics = views.ControlMetrics;
/// Lowers views to layout nodes.
pub const ViewLowering = views.ViewLowering;
/// Paints laid-out views.
pub const ViewPainter = views.ViewPainter;
/// Paints the built-in controls.
pub const ControlPainter = views.ControlPainter;
/// Paints the text views.
pub const TextViewPainter = views.TextViewPainter;
/// Lays out and paints a view tree: `render`, `renderInto`, `renderScaled`, `measure`.
pub const ViewRenderer = views.ViewRenderer;
/// A view tree drawn headless, for `--screenshot` and tests:
/// `Screenshot.render(allocator, state, State.body, options)` to RGBA8, `Screenshot.bmp` to a BMP file's bytes.
pub const Screenshot = views.Screenshot;
/// What `Screenshot.render` draws: `width`, `height`, `theme`, and `frames` (2) built before the last is drawn.
pub const ScreenshotOptions = views.ScreenshotOptions;
/// A headless frame: fonts and caches, `build` (a view tree to draw commands, settled as a window would), `rasterize` (software); under `Screenshot.render`, and the gallery's `--gpu`.
pub const ScreenshotFrame = views.ScreenshotFrame;
/// Routes the app's pointer events to a frame's regions: `PointerInput.shared().tap(...)`,
/// `drag`, `hover`, `scrollBoth`, `tapCount`, `clickShift`, `clickCommand`, `armDrag`, `endDrag`.
pub const PointerInput = views.PointerInput;
/// The keyboard focus: `Focus.shared().set(field)`, `clear()`, `focused()`, `submit()`.
pub const Focus = views.Focus;
/// The app's millisecond clock: `FrameClock.shared().setTime(ms)`, `time()`, `scrollbarsAnimating(now)`.
pub const FrameClock = views.FrameClock;
/// The live selection in selectable rich text: `TextSelection.shared().selectedText()`.
pub const TextSelection = views.TextSelection;
/// A selection's byte range in a selectable view.
pub const SelectionSpan = views.SelectionSpan;
/// The text-field context menu: `TextContextMenu.shared().open(field, point)`, `close()`, `isOpen()`.
pub const TextContextMenu = views.TextContextMenu;
/// The clipboard the context menu copies to and pastes from.
pub const ClipboardOperations = views.ClipboardOperations;

// -----------------------------------------------------------------------------
// Controls

/// One line of text.
pub const Text = views.Text;
/// Text that wraps to the width it is given.
pub const WrappedText = views.WrappedText;
/// A wrapped paragraph of styled spans.
pub const RichText = views.RichText;
/// Preformatted spans: leading spaces survive and lines do not wrap.
pub const RichTextPreformatted = views.RichTextPreformatted;
/// A wrapped paragraph of styled spans at a given line height.
pub const RichTextSpaced = views.RichTextSpaced;
/// A filled rectangle.
pub const Rectangle = views.Rectangle;
/// A filled rounded rectangle.
pub const RoundedRectangle = views.RoundedRectangle;
/// A filled circle.
pub const Circle = views.Circle;
/// A filled capsule.
pub const Capsule = views.Capsule;
/// A filled ellipse.
pub const Ellipse = views.Ellipse;
/// A gradient that fills its frame.
pub const LinearGradient = views.LinearGradient;
/// Three bouncing dots.
pub const LoadingDots = views.LoadingDots;
/// A push button.
pub const Button = views.Button;
/// A push button with a role (default, cancel, destructive).
pub const ButtonRoled = views.ButtonRoled;
/// A push button with an icon.
pub const ButtonIcon = views.ButtonIcon;
/// A push button with an icon and a role.
pub const ButtonIconRoled = views.ButtonIconRoled;
/// A switch over a `Binding(bool)`.
pub const Toggle = views.Toggle;
/// A slider over a range.
pub const Slider = views.Slider;
/// A stepper over a range.
pub const Stepper = views.Stepper;
/// A progress bar.
pub const ProgressView = views.ProgressView;
/// A pop-up menu over a selection binding.
pub const Picker = views.Picker;
/// A one-line text field.
pub const TextField = views.TextField;
/// A multi-line text editor.
pub const TextEditor = views.TextEditor;
/// A title behind a color swatch.
pub const Label = views.Label;
/// An image of RGBA pixels (`.scaledToFit()` to draw it at a frame's size).
pub const Image = views.Image;
/// An icon from the icon font.
pub const Icon = views.Icon;
/// A borderless icon button.
pub const IconButton = views.IconButton;
/// A view that paints itself through a callback.
pub const Drawing = views.Drawing;
/// A push button with its keyboard shortcut in a key cap after the label.
pub const ButtonKeyed = views.ButtonKeyed;
/// What a `Badge` says: its soft ground and strong text (`ground`, `text`).
pub const BadgeTone = views.BadgeTone;
/// A short label on a soft ground in its tone's strong color.
pub const Badge = views.Badge;
/// A keyboard key's glyph in a small cap.
pub const KeyCap = views.KeyCap;
/// A segmented control of equal segments, a neutral thumb on a track.
pub const SegmentedControl = views.SegmentedControl;

// -----------------------------------------------------------------------------
// Containers

/// Children stacked vertically.
pub const VStack = views.VStack;
/// Children side by side.
pub const HStack = views.HStack;
/// Children layered front to back.
pub const ZStack = views.ZStack;
/// A slice mapped to views, spliced into the enclosing stack.
pub const ForEach = views.ForEach;
/// Flexible space in a stack.
pub const Spacer = views.Spacer;
/// Flexible space with a least length.
pub const MinSpacer = views.MinSpacer;
/// A hairline across a stack.
pub const Divider = views.Divider;
/// A vertical hairline.
pub const VDivider = views.VDivider;
/// A view that draws nothing.
pub const Empty = views.Empty;
/// A scrolling viewport at the top.
pub const ScrollView = views.ScrollView;
/// A scrolling viewport at a fixed offset.
pub const ScrollViewOffset = views.ScrollViewOffset;
/// A scrolling viewport whose offset lives in a `ScrollState`.
pub const ScrollViewState = views.ScrollViewState;
/// A viewport that scrolls both ways, its offsets in a `ScrollState`.
pub const ScrollViewStateBoth = views.ScrollViewStateBoth;
/// Content built from the size it is laid out at.
pub const GeometryReader = views.GeometryReader;
/// A scrolling list of divider-separated rows.
pub const List = views.List;
/// A grid that fills rows of a fixed column count.
pub const LazyVGrid = views.LazyVGrid;
/// A grid that fills columns of a fixed row count.
pub const LazyHGrid = views.LazyHGrid;
/// One tab of a `TabView`.
pub const Tab = views.Tab;
/// Tabs over one shown page.
pub const TabView = views.TabView;
/// A navigation stack of routes.
pub const NavigationPath = views.NavigationPath;
/// A sidebar | detail split with a fixed sidebar.
pub const NavigationSplitView = views.NavigationSplitView;
/// A `NavigationSplitView` whose sidebar is an inset panel.
pub const NavigationSplitViewInset = views.NavigationSplitViewInset;
/// A button that pushes a route.
pub const NavigationLink = views.NavigationLink;
/// A button that pops a route.
pub const NavigationBackButton = views.NavigationBackButton;
/// A button that opens a popover of items.
pub const Menu = views.Menu;
/// A trigger view that opens a popover of items.
pub const ContextMenu = views.ContextMenu;
/// One row of a `Sidebar`.
pub const SidebarItem = views.SidebarItem;
/// How a `Sidebar` highlights its selection.
pub const SidebarStyle = views.SidebarStyle;
/// A sidebar list driven by a selection binding.
pub const Sidebar = views.Sidebar;
/// A `Sidebar` with an explicit selection style.
pub const SidebarStyled = views.SidebarStyled;
/// A vertical group of radio buttons.
pub const RadioGroup = views.RadioGroup;
/// One column of a `Table`.
pub const TableColumn = views.TableColumn;
/// A multi-column table of text rows.
pub const Table = views.Table;
/// The order a column is sorted in (`.forward`, `.reverse`), as SwiftUI's `SortOrder`.
pub const SortOrder = views.SortOrder;
/// A `DataTable`'s sort column and direction.
pub const SortColumn = views.SortColumn;
/// One column of a data table (and of `TableHeader`/`TableRow`).
pub const DataColumn = views.DataColumn;
/// A table of view rows with sortable headers.
pub const DataTable = views.DataTable;
/// The colors a `SelectableRow`'s content is drawn in (`selectionText`).
pub const SelectableRowStyle = views.SelectableRowStyle;
/// A list row showing its selection and whether its list has the focus.
pub const SelectableRow = views.SelectableRow;
/// A finished reorder: `from`, `to` (`apply` makes it on a slice).
pub const ReorderMove = views.ReorderMove;
/// What a list of `ReorderableRow`s drags: `ReorderState.init()`, `dropIndex`, `isDragging`, `takeMove`, `cancel`.
pub const ReorderState = views.ReorderState;
/// A list row dragged up or down to reorder its list: `ReorderableRow(content, &state, index, count, row_height)`.
pub const ReorderableRow = views.ReorderableRow;
/// A pane's title block: a title, a one-line description, an accessory.
pub const PaneHeader = views.PaneHeader;
/// A settings row: a label and its description, a control at the far edge.
pub const SettingRow = views.SettingRow;

// -----------------------------------------------------------------------------
// Text editing

/// One styled run of a `RichText`.
pub const Span = views.Span;
/// A laid-out piece of one span on one line of a rich paragraph.
pub const RichRun = views.RichRun;
/// One laid-out line of a rich paragraph.
pub const RichLine = views.RichLine;
/// A laid-out rich paragraph (`RichLayout.layOut` makes one).
pub const RichLayout = views.RichLayout;
/// The faces a rich paragraph's spans are measured and drawn in.
pub const RichFaces = views.RichFaces;
/// A text field's buffer, caret and selection.
pub const TextFieldState = views.TextFieldState;
/// Line and column geometry over a UTF-8 buffer.
pub const TextLines = views.TextLines;
/// Tab-aware widths of edited text (caret, selection, click).
pub const EditorMetrics = views.EditorMetrics;

// -----------------------------------------------------------------------------
// Window

/// The key-up and quit handlers the SDL runtime forwards SDL's events to (pure).
pub const AppHooks = views.AppHooks;
/// What a press in a window does for the window manager (pure; `WindowHitTest` maps it to SDL).
pub const WindowHit = views.WindowHit;
/// The window state a `WindowHit` is found from.
pub const WindowHitArea = views.WindowHitArea;
/// Escaped values for a freedesktop desktop entry (`.desktop`).
pub const DesktopEntry = views.DesktopEntry;
/// What `WindowButtons` do: minimize, maximize or restore, close.
pub const WindowActions = views.WindowActions;
/// A `TitleBar`'s height, in points.
pub const title_bar_height = views.title_bar_height;
/// Which platform's window buttons `WindowButtons` draws.
pub const WindowButtonStyle = views.WindowButtonStyle;
/// An app-drawn title bar: leading content, a centered middle, trailing content.
pub const TitleBar = views.TitleBar;
/// Minimize, maximize or restore, and close, in the platform's look.
pub const WindowButtons = views.WindowButtons;

// -----------------------------------------------------------------------------
// App runtime (the SDL runtime's app-facing types; `void` in the core build)

/// The running app: its window, loop flag, handlers, and `run` (app build only).
pub const App = if (config.with_sdl) sdl.App else void;
/// How `App.run` opens the window and renders (app build only).
pub const AppConfig = if (config.with_sdl) sdl.AppConfig else void;
/// Why the runtime could not start (app build only).
pub const AppError = if (config.with_sdl) sdl.AppError else void;
/// A window or tray icon as RGBA8 pixels (app build only).
pub const WindowIcon = if (config.with_sdl) sdl.WindowIcon else void;
/// The main window's position and size, in points (app build only).
pub const WindowFrame = if (config.with_sdl) sdl.WindowFrame else void;
/// The event loop `App.run` drives for one app state type (app build only).
pub const EventLoop = if (config.with_sdl) sdl.EventLoop else void;
/// A main-window mouse event in points, as `App.setMouseHandler` sees it (app build only).
pub const MouseEvent = if (config.with_sdl) sdl.MouseEvent else void;
/// What a `MouseEvent` reports: a press, a release, a move or a wheel turn (app build only).
pub const MouseEventKind = if (config.with_sdl) sdl.MouseEventKind else void;
/// The OS light/dark preference (app build only).
pub const SystemTheme = if (config.with_sdl) sdl.SystemTheme else void;
/// One native menu-bar menu, macOS (app build only).
pub const CommandMenu = if (config.with_sdl) sdl.CommandMenu else void;
/// One entry of a `CommandMenu` (app build only).
pub const CommandItem = if (config.with_sdl) sdl.CommandItem else void;
/// The popover panel window a status-item click opens (app build only).
pub const Panel = if (config.with_sdl) sdl.Panel else void;
/// What the popover panel shows and how big it is (app build only).
pub const PanelSpecification = if (config.with_sdl) sdl.PanelSpecification else void;
/// The system clipboard and the OS URL handler (app build only).
pub const Clipboard = if (config.with_sdl) sdl.Clipboard else void;
/// The native open-file and open-folder dialogs (app build only).
pub const FileDialog = if (config.with_sdl) sdl.FileDialog else void;
/// What a finished `FileDialog` returned (app build only).
pub const FileDialogResult = if (config.with_sdl) sdl.FileDialogResult else void;
/// A `FileDialog` file filter (app build only).
pub const FileFilter = if (config.with_sdl) sdl.FileFilter else void;
/// A system-tray icon with an OS-drawn menu (app build only).
pub const MenuBarExtra = if (config.with_sdl) sdl.MenuBarExtra else void;
/// A `MenuBarExtra` menu or submenu (app build only).
pub const MenuBarExtraMenu = if (config.with_sdl) sdl.MenuBarExtraMenu else void;
/// One `MenuBarExtra` menu entry (app build only).
pub const MenuBarExtraEntry = if (config.with_sdl) sdl.MenuBarExtraEntry else void;
/// A plain status icon whose click runs a callback, no menu (app build only).
pub const StatusItem = if (config.with_sdl) sdl.StatusItem else void;
/// The Linux freedesktop entry for the running executable (app build only).
pub const DesktopInstall = if (config.with_sdl) sdl.DesktopInstall else void;
/// Where the running executable's freedesktop entry stands (app build only).
pub const DesktopEntryState = if (config.with_sdl) sdl.DesktopEntryState else void;
/// The SDL_GPU backend (app build only).
pub const Gpu = if (config.with_sdl) sdl.Gpu else void;

// -----------------------------------------------------------------------------
// Chat

/// Where the thing a `StatusMark` stands for is.
pub const StatusMarkState = views.StatusMarkState;
/// A round mark for a row's state.
pub const StatusMark = views.StatusMark;
/// A header that folds content away, like SwiftUI's `DisclosureGroup`.
pub const DisclosureGroup = views.DisclosureGroup;
/// A small capsule: a mode, a model, an attachment.
pub const Chip = views.Chip;
/// Preformatted text on a tinted panel.
pub const CodeBlock = views.CodeBlock;
/// A quoted block behind a bar.
pub const Quote = views.Quote;
/// A message bubble.
pub const Bubble = views.Bubble;

// -----------------------------------------------------------------------------
// Panes

/// A callback that takes a row index (`init` wraps a method, `bind` fixes the index).
pub const IndexCallback = views.IndexCallback;
/// The rows a `VirtualList` builds (`visible` says which are in view).
pub const RowRange = views.RowRange;
/// The height of one diff row, in points.
pub const diff_row_height = views.diff_row_height;
/// What a `DiffLine` is.
pub const DiffLineKind = views.DiffLineKind;
/// One row of a `DiffView` (`hunkCount`, `hunkRow` and `revealHunk` work on a diff; `wrap` and `wrapColumns` wrap one to a width, `anchorAt` and `offsetAt` keep a scroll position across a re-wrap).
pub const DiffLine = views.DiffLine;
/// Where a scroll offset over a diff's rows falls, kept across a re-wrap (`DiffLine.anchorAt`, `DiffLine.offsetAt`).
pub const DiffAnchor = views.DiffAnchor;
/// How a `DiffView` lays out a row (text size, cells, tabs, gutter), shared with `DiffLine.wrap`.
pub const DiffLayout = views.DiffLayout;
/// A list that builds only the rows in view.
pub const VirtualList = views.VirtualList;
/// A `VirtualList` that also scrolls sideways, as wide as its widest row.
pub const VirtualListBoth = views.VirtualListBoth;
/// A unified diff over a `VirtualList`.
pub const DiffView = views.DiffView;
/// A table's header row.
pub const TableHeader = views.TableHeader;
/// One table row.
pub const TableRow = views.TableRow;

// -----------------------------------------------------------------------------
// Split views

/// Where a split view's divider sits.
pub const SplitState = views.SplitState;
/// Two panes side by side, like SwiftUI's `HSplitView`.
pub const HSplitView = views.HSplitView;
/// Two panes stacked, like SwiftUI's `VSplitView`.
pub const VSplitView = views.VSplitView;

// -----------------------------------------------------------------------------
// Hover popover

/// Which row of a list the pointer rests on, and since when (a `HoverPopover`'s delay).
pub const HoverState = views.HoverState;
/// A view's details in a popover once the pointer rests on it.
pub const HoverPopover = views.HoverPopover;

// -----------------------------------------------------------------------------
// Menu bar

/// The SDL3 keycodes and modifier bits ziggui's key handlers pass, mirrored so key handling stays headless.
pub const SdlKey = views.SdlKey;
/// One entry of a `MenuBarMenu`.
pub const MenuBarItem = views.MenuBarItem;
/// One menu of a `MenuBar`: a title and its entries (`fold` makes the narrow bar's `☰`).
pub const MenuBarMenu = views.MenuBarMenu;
/// How a `MenuBar` is drawn (the titles' color on a colored title bar).
pub const MenuBarOptions = views.MenuBarOptions;
/// A menu bar's menus, every one and folded into one `☰`, picked by width (`MenuBarState.shown`).
pub const MenuBarMenus = views.MenuBarMenus;
/// A key an open `MenuBar` reads (`fromKeycode` reads an SDL key event, `toKeycode` makes one).
pub const MenuBarKey = views.MenuBarKey;
/// A `MenuBar`'s state: the open menu, the highlighted entry, an Alt tap under way; takes the app's raw key and mouse events.
pub const MenuBarState = views.MenuBarState;
/// A `MenuBar`'s height, in points.
pub const menu_bar_height = views.menu_bar_height;
/// A menu bar drawn in the window, for systems without a global one.
pub const MenuBar = views.MenuBar;

// -----------------------------------------------------------------------------
// Status line

/// One `key action` pair of a `StatusLine`.
pub const KeyHint = views.KeyHint;
/// A `StatusLine`'s height, in points.
pub const status_line_height = views.status_line_height;
/// A window's status line: the keys that work now, as `key action` pairs.
pub const StatusLine = views.StatusLine;
/// The most hints a `KeyHintBar` shows.
pub const key_hint_bar_limit = views.key_hint_bar_limit;
/// A bar of the keys that work now, each a key cap followed by its action.
pub const KeyHintBar = views.KeyHintBar;

// -----------------------------------------------------------------------------
// Forms

/// One row of a `KeyValueEditor`: its name and value fields, on the heap.
pub const KeyValueRow = views.KeyValueRow;
/// What a `KeyValueEditor` edits: name/value rows (`setPairs`, `pairs`, `add`, `remove`, `count`).
pub const KeyValueState = views.KeyValueState;
/// An editor of name/value rows with an Add button.
pub const KeyValueEditor = views.KeyValueEditor;
/// What a `TokenField` edits: the tokens and their input (`setTokens`, `tokens`, `commit`, `remove`).
pub const TokenFieldState = views.TokenFieldState;
/// A field of short tokens: capsules, then an input that commits on Enter.
pub const TokenField = views.TokenField;
/// What a `FileNode` is: a folder or a file.
pub const FileNodeKind = views.FileNodeKind;
/// One entry of a `FileBrowser`'s folder.
pub const FileNode = views.FileNode;
/// What a `FileBrowser` shows (`open`, `up`, `enter`, `move`, `select`, `pickAlloc`).
pub const FileBrowserState = views.FileBrowserState;
/// A local file and folder picker drawn in the window.
pub const FileBrowser = views.FileBrowser;
/// A search field: a magnifying glass, the text, and a clear button.
pub const SearchField = views.SearchField;
/// A composed field's look: the raised ground, a strong hairline border, a 6pt corner.
pub const FieldChrome = views.FieldChrome;

// -----------------------------------------------------------------------------
// Testing

/// A headless frame for the view engine's unit tests.
pub const TestEnvironment = views.TestEnvironment;
/// A headless frame for the unit tests.
pub const TestCanvas = views.TestCanvas;
/// Two menus for the menu bar's unit tests, counting their choices.
pub const TestMenus = views.TestMenus;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "version is parsed from the package manifest" {
    try std.testing.expect(version.major != 0 or version.minor != 0 or version.patch != 0);
}
