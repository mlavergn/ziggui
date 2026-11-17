//! The views: the view engine (`core/`), rich text and editing state
//! (`text/`), the controls and containers built on it, window plumbing, and
//! ziggui's own widgets (chat, panes, split views, hover popover, menu bar,
//! status line, forms), behind one import. Everything is a view, as in SwiftUI, and
//! the widgets follow SwiftUI's names where SwiftUI has one.
//!
//! The root `ziggui` barrel re-exports every name here, flat; this barrel
//! re-exports each subdirectory's names flat too, so its files reach one
//! another as `mod.X` through their own directory's barrel.

const std = @import("std");
const log = std.log.scoped(.ziggui_views_module);

// -----------------------------------------------------------------------------
// The view engine (core/)

/// A node of the view tree.
pub const View = @import("core/module.zig").View;
/// What a view is: one variant per kind of view.
pub const Kind = @import("core/module.zig").Kind;
/// A `Text`'s payload.
pub const TextData = @import("core/module.zig").TextData;
/// A `WrappedText`'s payload.
pub const WrappedTextData = @import("core/module.zig").WrappedTextData;
/// A `RichText`'s payload.
pub const RichTextData = @import("core/module.zig").RichTextData;
/// A `Spacer`'s payload.
pub const SpacerData = @import("core/module.zig").SpacerData;
/// A shape's payload.
pub const ShapeData = @import("core/module.zig").ShapeData;
/// A stack's payload.
pub const StackData = @import("core/module.zig").StackData;
/// A button's payload.
pub const ButtonData = @import("core/module.zig").ButtonData;
/// A switch's payload.
pub const ToggleData = @import("core/module.zig").ToggleData;
/// A slider's payload.
pub const SliderData = @import("core/module.zig").SliderData;
/// A stepper's payload.
pub const StepperData = @import("core/module.zig").StepperData;
/// A progress bar's payload.
pub const ProgressData = @import("core/module.zig").ProgressData;
/// An image's payload.
pub const ImageData = @import("core/module.zig").ImageData;
/// A label's payload.
pub const LabelData = @import("core/module.zig").LabelData;
/// An icon's payload.
pub const IconData = @import("core/module.zig").IconData;
/// An icon button's payload.
pub const IconButtonData = @import("core/module.zig").IconButtonData;
/// A fixed-offset scroll view's payload.
pub const ScrollData = @import("core/module.zig").ScrollData;
/// A text field's payload.
pub const TextFieldData = @import("core/module.zig").TextFieldData;
/// A text editor's payload.
pub const TextEditorData = @import("core/module.zig").TextEditorData;
/// A state-driven scroll view's payload.
pub const ScrollStateData = @import("core/module.zig").ScrollStateData;
/// A `GeometryReader`'s payload.
pub const GeometryData = @import("core/module.zig").GeometryData;
/// A picker's payload.
pub const PickerData = @import("core/module.zig").PickerData;
/// A `Drawing`'s payload.
pub const DrawingData = @import("core/module.zig").DrawingData;
/// A `VideoPlayer`'s payload.
pub const VideoPlayerData = @import("core/module.zig").VideoPlayerData;
/// A `NativeView`'s payload.
pub const NativeViewData = @import("core/module.zig").NativeViewData;
/// The modifiers applied around a view's content.
pub const Modifiers = @import("core/module.zig").Modifiers;
/// How a `Toggle` draws: a switch or a checkbox (`.toggleStyle()`).
pub const ToggleStyle = @import("core/module.zig").ToggleStyle;
/// A `.sheet`/`.alert`/`.popover` modifier.
pub const OverlayModifier = @import("core/module.zig").OverlayModifier;
/// A `.frame(...)` modifier's sizes and alignment.
pub const FrameSpecification = @import("core/module.zig").FrameSpecification;
/// What a background or shape is filled with.
pub const Fill = @import("core/module.zig").Fill;
/// A two-color linear gradient fill.
pub const GradientFill = @import("core/module.zig").GradientFill;
/// A translucent, blurred background.
pub const Material = @import("core/module.zig").Material;
/// A material's tint scale and blur.
pub const MaterialSpecification = @import("core/module.zig").MaterialSpecification;
/// How a presented overlay is drawn.
pub const OverlayStyle = @import("core/module.zig").OverlayStyle;
/// Named typographic styles.
pub const FontToken = @import("core/module.zig").FontToken;
/// The outline a shape view fills.
pub const ShapeKind = @import("core/module.zig").ShapeKind;
/// The semantic appearance of a button.
pub const ButtonRole = @import("core/module.zig").ButtonRole;
/// The icon font's glyph names.
pub const IconName = @import("core/module.zig").IconName;
/// A read/write handle on a `State`.
pub const Binding = @import("core/module.zig").Binding;
/// An app's accent, a setting: the brand's orange or one of macOS's (`theme` applies it, the macOS dark on black).
pub const Accent = @import("core/module.zig").Accent;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection).
pub const Callback = @import("core/module.zig").Callback;
/// What `View.onHover` calls: true on entering a view, false on leaving it.
pub const HoverCallback = @import("core/module.zig").HoverCallback;
/// What `View.onDrag` calls.
pub const DragCallback = @import("core/module.zig").DragCallback;
/// A scroll view's app-owned offset and extents.
pub const ScrollState = @import("core/module.zig").ScrollState;
/// A scroll view's frame and state, collected while painting.
pub const ScrollRegion = @import("core/module.zig").ScrollRegion;
/// The overlay scrollbars a scroll view draws and drags.
pub const Scrollbar = @import("core/module.zig").Scrollbar;
/// A scrollbar thumb along one axis.
pub const Thumb = @import("core/module.zig").Thumb;
/// What a frame is painted with.
pub const Context = @import("core/module.zig").Context;
/// Where the input sinks stood before clipped content painted.
pub const InputMarks = @import("core/module.zig").InputMarks;
/// What a tap region does.
pub const HitAction = @import("core/module.zig").HitAction;
/// A slider track's tap action.
pub const SliderTrack = @import("core/module.zig").SliderTrack;
/// A stepper half's tap action.
pub const StepAction = @import("core/module.zig").StepAction;
/// A picker segment's tap action.
pub const SelectValue = @import("core/module.zig").SelectValue;
/// A text field's or editor's clickable text geometry.
pub const TextClick = @import("core/module.zig").TextClick;
/// A tap region registered while painting.
pub const HitRegion = @import("core/module.zig").HitRegion;
/// An `onHover` region registered while painting.
pub const HoverRegion = @import("core/module.zig").HoverRegion;
/// A `VideoPlayer`'s frame registered while painting.
pub const VideoRegion = @import("core/module.zig").VideoRegion;
/// A `NativeView`'s frame registered while painting.
pub const NativeRegion = @import("core/module.zig").NativeRegion;
/// An accessibility role.
pub const A11yRole = @import("core/module.zig").A11yRole;
/// One node of the accessibility tree.
pub const A11yNode = @import("core/module.zig").A11yNode;
/// A popover or sheet waiting to be drawn.
pub const OverlayRequest = @import("core/module.zig").OverlayRequest;
/// A selectable paragraph's geometry for one frame.
pub const SelectHit = @import("core/module.zig").SelectHit;
/// What a `Drawing` paints with.
pub const Pen = @import("core/module.zig").Pen;
/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`).
pub const BuildScope = @import("core/module.zig").BuildScope;
/// The build-time theme colors, `label`, `separator`, `added` and `removed` included.
pub const BuildTokens = @import("core/module.zig").BuildTokens;
/// A cache of wrapped-text and rich-text layouts.
pub const WrapCache = @import("core/module.zig").WrapCache;
/// Builds stack views from tuples or slices (`fromSlice` keeps its slice).
pub const StackBuilder = @import("core/module.zig").StackBuilder;
/// The built-in controls' geometry.
pub const ControlMetrics = @import("core/module.zig").ControlMetrics;
/// Lowers views to layout nodes.
pub const ViewLowering = @import("core/module.zig").ViewLowering;
/// Paints laid-out views.
pub const ViewPainter = @import("core/module.zig").ViewPainter;
/// Paints the built-in controls.
pub const ControlPainter = @import("core/module.zig").ControlPainter;
/// Paints the text views.
pub const TextViewPainter = @import("core/module.zig").TextViewPainter;
/// Measures and renders view trees, drawing their overlays (`render`, `renderScaled`, `measure`).
pub const ViewRenderer = @import("core/module.zig").ViewRenderer;
/// A body drawn to pixels with no window (`render`), and the pixels encoded as a BMP (`bmp`).
pub const Screenshot = @import("core/module.zig").Screenshot;
/// What `Screenshot.render` draws: the size, the theme, the frames built first.
pub const ScreenshotOptions = @import("core/module.zig").ScreenshotOptions;
/// A headless frame: fonts and caches, `build` (a view tree to draw commands, settled as a window would), `rasterize` (software); under `Screenshot.render`, and the gallery's `--gpu`.
pub const ScreenshotFrame = @import("core/module.zig").ScreenshotFrame;
/// Routes pointer events to a frame's regions (`PointerInput.shared()`).
pub const PointerInput = @import("core/module.zig").PointerInput;
/// The keyboard focus and the caret's blink (`Focus.shared()`).
pub const Focus = @import("core/module.zig").Focus;
/// The app's millisecond clock and scrollbar fade timing (`FrameClock.shared()`).
pub const FrameClock = @import("core/module.zig").FrameClock;
/// The live selection in selectable rich text (`TextSelection.shared()`).
pub const TextSelection = @import("core/module.zig").TextSelection;
/// A selection's byte range in a selectable view.
pub const SelectionSpan = @import("core/module.zig").SelectionSpan;
/// The text-field context menu (`TextContextMenu.shared()`).
pub const TextContextMenu = @import("core/module.zig").TextContextMenu;
/// The hover hint a view's `.help(text)` shows (`HelpTip.shared()`).
pub const HelpTip = @import("core/module.zig").HelpTip;
/// The clipboard the context menu copies to and pastes from.
pub const ClipboardOperations = @import("core/module.zig").ClipboardOperations;
/// A headless frame for the view engine's unit tests.
pub const TestEnvironment = @import("core/module.zig").TestEnvironment;
/// A headless frame for the unit tests.
pub const TestCanvas = @import("core/module.zig").TestCanvas;

// -----------------------------------------------------------------------------
// Rich text and editing state (text/)

/// One styled run of a `RichText`.
pub const Span = @import("text/module.zig").Span;
/// A laid-out piece of one span on one line of a rich paragraph.
pub const RichRun = @import("text/module.zig").RichRun;
/// One laid-out line of a rich paragraph.
pub const RichLine = @import("text/module.zig").RichLine;
/// A laid-out rich paragraph (`RichLayout.layOut` makes one).
pub const RichLayout = @import("text/module.zig").RichLayout;
/// The faces a rich paragraph's spans are measured and drawn in.
pub const RichFaces = @import("text/module.zig").RichFaces;
/// A text field's buffer, caret and selection.
pub const TextFieldState = @import("text/module.zig").TextFieldState;
/// Text made safe to draw: each invalid UTF-8 byte becomes U+FFFD.
pub const DisplayText = @import("text/module.zig").DisplayText;
/// Line and column geometry over a UTF-8 buffer.
pub const TextLines = @import("text/module.zig").TextLines;
/// Tab-aware widths of edited text (caret, selection, click).
pub const EditorMetrics = @import("text/module.zig").EditorMetrics;

// -----------------------------------------------------------------------------
// Controls (controls/)

/// One line of text.
pub const Text = @import("controls/module.zig").Text;
/// Text that wraps to the width it is given.
pub const WrappedText = @import("controls/module.zig").WrappedText;
/// A wrapped paragraph of styled spans.
pub const RichText = @import("controls/module.zig").RichText;
/// Preformatted spans: leading spaces survive and lines do not wrap.
pub const RichTextPreformatted = @import("controls/module.zig").RichTextPreformatted;
/// A wrapped paragraph of styled spans at a given line height.
pub const RichTextSpaced = @import("controls/module.zig").RichTextSpaced;
/// A filled rectangle.
pub const Rectangle = @import("controls/module.zig").Rectangle;
/// A filled rounded rectangle.
pub const RoundedRectangle = @import("controls/module.zig").RoundedRectangle;
/// A filled circle.
pub const Circle = @import("controls/module.zig").Circle;
/// A filled capsule.
pub const Capsule = @import("controls/module.zig").Capsule;
/// A filled ellipse.
pub const Ellipse = @import("controls/module.zig").Ellipse;
/// A gradient that fills its frame.
pub const LinearGradient = @import("controls/module.zig").LinearGradient;
/// Three bouncing dots.
pub const LoadingDots = @import("controls/module.zig").LoadingDots;
/// A push button.
pub const Button = @import("controls/module.zig").Button;
/// A push button with a role (default, cancel, destructive).
pub const ButtonRoled = @import("controls/module.zig").ButtonRoled;
/// A push button with an icon.
pub const ButtonIcon = @import("controls/module.zig").ButtonIcon;
/// A push button with an icon and a role.
pub const ButtonIconRoled = @import("controls/module.zig").ButtonIconRoled;
/// A switch over a `Binding(bool)`.
pub const Toggle = @import("controls/module.zig").Toggle;
/// A slider over a range.
pub const Slider = @import("controls/module.zig").Slider;
/// A stepper over a range.
pub const Stepper = @import("controls/module.zig").Stepper;
/// A progress bar.
pub const ProgressView = @import("controls/module.zig").ProgressView;
/// A pop-up menu over a selection binding.
pub const Picker = @import("controls/module.zig").Picker;
/// A one-line text field.
pub const TextField = @import("controls/module.zig").TextField;
/// A multi-line text editor.
pub const TextEditor = @import("controls/module.zig").TextEditor;
/// A title behind a color swatch.
pub const Label = @import("controls/module.zig").Label;
/// An image of RGBA pixels (`.scaledToFit()` to draw it at a frame's size).
pub const Image = @import("controls/module.zig").Image;
/// An icon from the icon font.
pub const Icon = @import("controls/module.zig").Icon;
/// A borderless icon button.
pub const IconButton = @import("controls/module.zig").IconButton;
/// A view that paints itself through a callback.
pub const Drawing = @import("controls/module.zig").Drawing;
/// A push button with its keyboard shortcut in a key cap after the label.
pub const ButtonKeyed = @import("controls/module.zig").ButtonKeyed;
/// What a `Badge` says: its soft ground and strong text (`ground`, `text`).
pub const BadgeTone = @import("controls/module.zig").BadgeTone;
/// A short label on a soft ground in its tone's strong color.
pub const Badge = @import("controls/module.zig").Badge;
/// A keyboard key's glyph in a small cap.
pub const KeyCap = @import("controls/module.zig").KeyCap;
/// A segmented control of equal segments, a neutral thumb on a track.
pub const SegmentedControl = @import("controls/module.zig").SegmentedControl;

// -----------------------------------------------------------------------------
// Containers (containers/)

/// Children stacked vertically.
pub const VStack = @import("containers/module.zig").VStack;
/// Children side by side.
pub const HStack = @import("containers/module.zig").HStack;
/// Children layered front to back.
pub const ZStack = @import("containers/module.zig").ZStack;
/// A slice mapped to views, spliced into the enclosing stack.
pub const ForEach = @import("containers/module.zig").ForEach;
/// Flexible space in a stack.
pub const Spacer = @import("containers/module.zig").Spacer;
/// Flexible space with a least length.
pub const MinSpacer = @import("containers/module.zig").MinSpacer;
/// A hairline across a stack.
pub const Divider = @import("containers/module.zig").Divider;
/// A vertical hairline.
pub const VDivider = @import("containers/module.zig").VDivider;
/// A view that draws nothing.
pub const Empty = @import("containers/module.zig").Empty;
/// A scrolling viewport at the top.
pub const ScrollView = @import("containers/module.zig").ScrollView;
/// A scrolling viewport at a fixed offset.
pub const ScrollViewOffset = @import("containers/module.zig").ScrollViewOffset;
/// A scrolling viewport whose offset lives in a `ScrollState`.
pub const ScrollViewState = @import("containers/module.zig").ScrollViewState;
/// A viewport that scrolls both ways, its offsets in a `ScrollState`.
pub const ScrollViewStateBoth = @import("containers/module.zig").ScrollViewStateBoth;
/// Content built from the size it is laid out at.
pub const GeometryReader = @import("containers/module.zig").GeometryReader;
/// A scrolling list of divider-separated rows.
pub const List = @import("containers/module.zig").List;
/// A grid that fills rows of a fixed column count.
pub const LazyVGrid = @import("containers/module.zig").LazyVGrid;
/// A grid that fills columns of a fixed row count.
pub const LazyHGrid = @import("containers/module.zig").LazyHGrid;
/// One tab of a `TabView`.
pub const Tab = @import("containers/module.zig").Tab;
/// Tabs over one shown page.
pub const TabView = @import("containers/module.zig").TabView;
/// A navigation stack of routes.
pub const NavigationPath = @import("containers/module.zig").NavigationPath;
/// A sidebar | detail split with a fixed sidebar.
pub const NavigationSplitView = @import("containers/module.zig").NavigationSplitView;
/// A `NavigationSplitView` whose sidebar is an inset panel.
pub const NavigationSplitViewInset = @import("containers/module.zig").NavigationSplitViewInset;
/// A list row that pushes a route: its title and a trailing chevron.
pub const NavigationLink = @import("containers/module.zig").NavigationLink;
/// A `NavigationLink` row led by an icon.
pub const NavigationLinkIcon = @import("containers/module.zig").NavigationLinkIcon;
/// A button that pops a route.
pub const NavigationBackButton = @import("containers/module.zig").NavigationBackButton;
/// A button that opens a popover of items.
pub const Menu = @import("containers/module.zig").Menu;
/// A trigger view that opens a popover of items.
pub const ContextMenu = @import("containers/module.zig").ContextMenu;
/// One entry of a pop-up menu, filled under the pointer.
pub const MenuItem = @import("containers/module.zig").MenuItem;
/// A pop-up menu's panel: its entries stacked at a fixed width.
pub const MenuList = @import("containers/module.zig").MenuList;
/// An empty pane's message: a quiet title over a wrapped detail, centered.
pub const EmptyState = @import("containers/module.zig").EmptyState;
/// The notice strip: a busy mark, the last notice, and an optional action.
pub const NoticeBar = @import("containers/module.zig").NoticeBar;
/// A pane's title row over a divider, in the accent while the pane has the keys.
pub const PaneTitle = @import("containers/module.zig").PaneTitle;
/// A form field: its label over the control, and a line of help under it.
pub const LabeledField = @import("containers/module.zig").LabeledField;
/// A question an app asks before something it cannot undo.
pub const Confirm = @import("containers/module.zig").Confirm;
/// A yes-or-no question's panel, the refusal first.
pub const ConfirmAlert = @import("containers/module.zig").ConfirmAlert;
/// The last thing an action said, kept for the notice strip.
pub const NoticeText = @import("text/module.zig").NoticeText;
/// One key press as an app's screens read it.
pub const Key = @import("menu_bar/module.zig").Key;
/// A key that is not a character.
pub const KeyName = @import("menu_bar/module.zig").KeyName;
/// An SDL key-down as ziggui's key handler passes it.
pub const SdlKeyEvent = @import("menu_bar/module.zig").SdlKeyEvent;
/// One native (macOS) menu-bar entry.
pub const CommandItem = @import("menu_bar/module.zig").CommandItem;
/// One native (macOS) menu-bar menu.
pub const CommandMenu = @import("menu_bar/module.zig").CommandMenu;
/// Which systems a menu entry shows on.
pub const MenuOnly = @import("menu_bar/module.zig").MenuOnly;
/// An app's menus as one table, built into either menu bar.
pub const MenuTable = @import("menu_bar/module.zig").MenuTable;
/// Where the running executable's freedesktop entry stands.
pub const DesktopEntryState = @import("window/module.zig").DesktopEntryState;
/// What an app's platform layer answers with no window: tests and headless runs.
pub const HeadlessPlatform = @import("window/module.zig").HeadlessPlatform;
/// A window's frame: its measures, its top band and drawn title bar, and how its menu bar spells a key.
pub const WindowChrome = @import("window/module.zig").WindowChrome;
/// One row of a `Sidebar`.
pub const SidebarItem = @import("containers/module.zig").SidebarItem;
/// How a `Sidebar` highlights its selection.
pub const SidebarStyle = @import("containers/module.zig").SidebarStyle;
/// A sidebar list driven by a selection binding.
pub const Sidebar = @import("containers/module.zig").Sidebar;
/// A `Sidebar` with an explicit selection style.
pub const SidebarStyled = @import("containers/module.zig").SidebarStyled;
/// A vertical group of radio buttons.
pub const RadioGroup = @import("containers/module.zig").RadioGroup;
/// One column of a `Table`.
pub const TableColumn = @import("containers/module.zig").TableColumn;
/// A multi-column table of text rows.
pub const Table = @import("containers/module.zig").Table;
/// A settings form in columns: labels right-aligned in one column, sections divided.
pub const Form = @import("containers/module.zig").Form;
/// A group of a `Form`'s rows.
pub const Section = @import("containers/module.zig").Section;
/// A `Form` row: a label in the form's label column, its controls beside it.
pub const LabeledContent = @import("containers/module.zig").LabeledContent;
/// An app's settings: a toolbar of tabs over the selected page.
pub const Settings = @import("containers/module.zig").Settings;
/// A `Table` whose columns the user drags wider or narrower.
pub const TableResizable = @import("containers/module.zig").TableResizable;
/// The column widths a user dragged in a `TableResizable`.
pub const TableColumnCustomization = @import("containers/module.zig").TableColumnCustomization;
/// The order a column is sorted in (`.forward`, `.reverse`), as SwiftUI's `SortOrder`.
pub const SortOrder = @import("containers/module.zig").SortOrder;
/// A `DataTable`'s sort column and direction.
pub const SortColumn = @import("containers/module.zig").SortColumn;
/// One column of a data table (and of `TableHeader`/`TableRow`).
pub const DataColumn = @import("containers/module.zig").DataColumn;
/// A table of view rows with sortable headers.
pub const DataTable = @import("containers/module.zig").DataTable;
/// The colors a `SelectableRow`'s content is drawn in (`selectionText`).
pub const SelectableRowStyle = @import("containers/module.zig").SelectableRowStyle;
/// A list row showing its selection and whether its list has the focus.
pub const SelectableRow = @import("containers/module.zig").SelectableRow;
/// A finished reorder: `from`, `to` (`apply` makes it on a slice).
pub const ReorderMove = @import("containers/module.zig").ReorderMove;
/// What a list of `ReorderableRow`s drags (`dropIndex`, `isDragging`, `takeMove`, `cancel`).
pub const ReorderState = @import("containers/module.zig").ReorderState;
/// A list row dragged up or down to reorder its list.
pub const ReorderableRow = @import("containers/module.zig").ReorderableRow;
/// A pane's title block: a title, a one-line description, an accessory.
pub const PaneHeader = @import("containers/module.zig").PaneHeader;
/// A settings row: a label and its description, a control at the far edge.
pub const SettingRow = @import("containers/module.zig").SettingRow;

// -----------------------------------------------------------------------------
// Window plumbing and the title bar (window/)

/// The key-up and quit handlers the SDL runtime's `App` forwards SDL's events to (pure).
pub const AppHooks = @import("window/module.zig").AppHooks;
/// What a press in a window does for the window manager (pure; the SDL runtime's `WindowHitTest` maps it to SDL).
pub const WindowHit = @import("window/module.zig").WindowHit;
/// The window state a `WindowHit` is found from.
pub const WindowHitArea = @import("window/module.zig").WindowHitArea;
/// Escaped values for a freedesktop desktop entry (`.desktop`).
pub const DesktopEntry = @import("window/module.zig").DesktopEntry;
/// What `WindowButtons` do: minimize, maximize or restore, close.
pub const WindowActions = @import("window/module.zig").WindowActions;
/// A `TitleBar`'s height, in points.
pub const title_bar_height = @import("window/module.zig").title_bar_height;
/// Which platform's window buttons `WindowButtons` draws.
pub const WindowButtonStyle = @import("window/module.zig").WindowButtonStyle;
/// An app-drawn title bar: leading content, a centered middle, trailing content.
pub const TitleBar = @import("window/module.zig").TitleBar;
/// Minimize, maximize or restore, and close, in the platform's look.
pub const WindowButtons = @import("window/module.zig").WindowButtons;

// -----------------------------------------------------------------------------
// Chat (chat/)

/// Where the thing a `StatusMark` stands for is.
pub const StatusMarkState = @import("chat/module.zig").StatusMarkState;
/// A round mark for a row's state.
pub const StatusMark = @import("chat/module.zig").StatusMark;
/// A header that folds content away, like SwiftUI's `DisclosureGroup`.
pub const DisclosureGroup = @import("chat/module.zig").DisclosureGroup;
/// A small capsule: a mode, a model, an attachment.
pub const Chip = @import("chat/module.zig").Chip;
/// Preformatted text on a tinted panel.
pub const CodeBlock = @import("chat/module.zig").CodeBlock;
/// A quoted block behind a bar.
pub const Quote = @import("chat/module.zig").Quote;
/// A message bubble.
pub const Bubble = @import("chat/module.zig").Bubble;

// -----------------------------------------------------------------------------
// Panes (panes/)

/// A callback that takes a row index (`init` wraps a method, `bind` fixes the index).
pub const IndexCallback = @import("panes/module.zig").IndexCallback;
/// The rows a `VirtualList` builds (`visible` says which are in view).
pub const RowRange = @import("panes/module.zig").RowRange;
/// The height of one diff row, in points.
pub const diff_row_height = @import("panes/module.zig").diff_row_height;
/// What a `DiffLine` is.
pub const DiffLineKind = @import("panes/module.zig").DiffLineKind;
/// One row of a `DiffView` (`hunkCount`, `hunkRow` and `revealHunk` work on a diff; `wrap` and `wrapColumns` wrap one to a width, `anchorAt` and `offsetAt` keep a scroll position across a re-wrap).
pub const DiffLine = @import("panes/module.zig").DiffLine;
/// Where a scroll offset over a diff's rows falls, kept across a re-wrap (`DiffLine.anchorAt`, `DiffLine.offsetAt`).
pub const DiffAnchor = @import("panes/module.zig").DiffAnchor;
/// How a `DiffView` lays out a row (text size, cells, tabs, gutter), shared with `DiffLine.wrap`.
pub const DiffLayout = @import("panes/module.zig").DiffLayout;
/// A list that builds only the rows in view.
pub const VirtualList = @import("panes/module.zig").VirtualList;
/// A `VirtualList` that also scrolls sideways, as wide as its widest row.
pub const VirtualListBoth = @import("panes/module.zig").VirtualListBoth;
/// A unified diff over a `VirtualList`.
pub const DiffView = @import("panes/module.zig").DiffView;
/// A table's header row.
pub const TableHeader = @import("panes/module.zig").TableHeader;
/// One table row.
pub const TableRow = @import("panes/module.zig").TableRow;

// -----------------------------------------------------------------------------
// Split views (split/)

/// Where a split view's divider sits.
pub const SplitState = @import("split/module.zig").SplitState;
/// Two panes side by side, like SwiftUI's `HSplitView`.
pub const HSplitView = @import("split/module.zig").HSplitView;
/// Two panes stacked, like SwiftUI's `VSplitView`.
pub const VSplitView = @import("split/module.zig").VSplitView;

// -----------------------------------------------------------------------------
// Hover popover (hover/)

/// Which row of a list the pointer rests on, and since when (a `HoverPopover`'s delay).
pub const HoverState = @import("hover/module.zig").HoverState;
/// A view's details in a popover once the pointer rests on it.
pub const HoverPopover = @import("hover/module.zig").HoverPopover;

// -----------------------------------------------------------------------------
// Menu bar (menu_bar/)

/// The SDL3 keycodes and modifier bits ziggui's key handlers pass, mirrored so key handling stays headless.
pub const SdlKey = @import("menu_bar/module.zig").SdlKey;
/// One entry of a `MenuBarMenu`.
pub const MenuBarItem = @import("menu_bar/module.zig").MenuBarItem;
/// One menu of a `MenuBar`: a title and its entries (`fold` makes the narrow bar's `☰`).
pub const MenuBarMenu = @import("menu_bar/module.zig").MenuBarMenu;
/// How a `MenuBar` is drawn (the titles' color on a colored title bar).
pub const MenuBarOptions = @import("menu_bar/module.zig").MenuBarOptions;
/// A menu bar's menus, every one and folded into one `☰`, picked by width (`MenuBarState.shown`).
pub const MenuBarMenus = @import("menu_bar/module.zig").MenuBarMenus;
/// A key an open `MenuBar` reads (`fromKeycode` reads an SDL key event, `toKeycode` makes one).
pub const MenuBarKey = @import("menu_bar/module.zig").MenuBarKey;
/// A `MenuBar`'s state: the open menu, the highlighted entry, an Alt tap under way; takes the app's raw key and mouse events.
pub const MenuBarState = @import("menu_bar/module.zig").MenuBarState;
/// A `MenuBar`'s height, in points.
pub const menu_bar_height = @import("menu_bar/module.zig").menu_bar_height;
/// A menu bar drawn in the window, for systems without a global one.
pub const MenuBar = @import("menu_bar/module.zig").MenuBar;
/// Two menus for the menu bar's unit tests, counting their choices.
pub const TestMenus = @import("menu_bar/module.zig").TestMenus;

// -----------------------------------------------------------------------------
// Status line (status_line/)

/// One `key action` pair of a `StatusLine`.
pub const KeyHint = @import("status_line/module.zig").KeyHint;
/// A `StatusLine`'s height, in points.
pub const status_line_height = @import("status_line/module.zig").status_line_height;
/// A window's status line: the keys that work now, as `key action` pairs.
pub const StatusLine = @import("status_line/module.zig").StatusLine;
/// The most hints a `KeyHintBar` shows.
pub const key_hint_bar_limit = @import("status_line/module.zig").key_hint_bar_limit;
/// A bar of the keys that work now, each a key cap followed by its action.
pub const KeyHintBar = @import("status_line/module.zig").KeyHintBar;

// -----------------------------------------------------------------------------
// Forms (forms/)

/// One row of a `KeyValueEditor`: its name and value fields, on the heap.
pub const KeyValueRow = @import("forms/module.zig").KeyValueRow;
/// What a `KeyValueEditor` edits: name/value rows (`setPairs`, `pairs`, `add`, `remove`, `count`).
pub const KeyValueState = @import("forms/module.zig").KeyValueState;
/// An editor of name/value rows with an Add button.
pub const KeyValueEditor = @import("forms/module.zig").KeyValueEditor;
/// What a `TokenField` edits: the tokens and their input (`setTokens`, `tokens`, `commit`, `remove`).
pub const TokenFieldState = @import("forms/module.zig").TokenFieldState;
/// A field of short tokens: capsules, then an input that commits on Enter.
pub const TokenField = @import("forms/module.zig").TokenField;
/// What a `FileNode` is: a folder or a file.
pub const FileNodeKind = @import("forms/module.zig").FileNodeKind;
/// One entry of a `FileBrowser`'s folder.
pub const FileNode = @import("forms/module.zig").FileNode;
/// What a `FileBrowser` picks: a path and what it is.
pub const FilePick = @import("forms/module.zig").FilePick;
/// What a `FileBrowser` shows (`open`, `up`, `enter`, `move`, `select`, `pickAlloc`).
pub const FileBrowserState = @import("forms/module.zig").FileBrowserState;
/// A local file and folder picker drawn in the window.
pub const FileBrowser = @import("forms/module.zig").FileBrowser;
/// A search field: a magnifying glass, the text, and a clear button.
pub const SearchField = @import("forms/module.zig").SearchField;
/// A composed field's look: the raised ground, a strong hairline border, a 6pt corner.
pub const FieldChrome = @import("forms/module.zig").FieldChrome;

// -----------------------------------------------------------------------------
// Media playback (media/)

/// Whether a player's item can play.
pub const PlayerStatus = @import("media/module.zig").PlayerStatus;
/// What a player is doing with time: paused, waiting, playing.
pub const PlayerTimeControl = @import("media/module.zig").PlayerTimeControl;
/// One sample of a player's state (`Player.observe`).
pub const PlayerObservation = @import("media/module.zig").PlayerObservation;
/// Audio or subtitles, for `Player.tracks` and `selectTrack`.
pub const PlayerTrackKind = @import("media/module.zig").PlayerTrackKind;
/// One audio or subtitle track of a player's item.
pub const PlayerTrack = @import("media/module.zig").PlayerTrack;
/// A platform media player's operations, installed by the SDL runtime.
pub const PlayerBackend = @import("media/module.zig").PlayerBackend;
/// A media player modeled on `AVPlayer` (`replaceCurrentItem`, `play`, `seek`, `observe`, `tracks`).
pub const Player = @import("media/module.zig").Player;
/// A player's picture in the view tree.
pub const VideoPlayer = @import("media/module.zig").VideoPlayer;
/// The standard controls over a `VideoPlayer`: full screen, volume, transport, scrubber.
pub const VideoPlayerControls = @import("media/module.zig").VideoPlayerControls;
/// What a `VideoPlayerControls` keeps across frames; app-owned.
pub const VideoPlayerControlsState = @import("media/module.zig").VideoPlayerControlsState;
/// What a platform web view reports about its page (`WebPage.update`).
pub const WebPageState = @import("media/module.zig").WebPageState;
/// A message a page posted to a bridge, borrowed for the call.
pub const WebPageMessage = @import("media/module.zig").WebPageMessage;
/// What `WebPage.onMessage` calls with each message.
pub const WebPageMessageCallback = @import("media/module.zig").WebPageMessageCallback;
/// A web page modeled on SwiftUI's `WebPage` (`load`, navigation, bridges, `onChange`).
pub const WebPage = @import("media/module.zig").WebPage;
/// A platform web view's operations, installed by the SDL runtime.
pub const WebPageBackend = @import("media/module.zig").WebPageBackend;
/// A web page's view in the view tree.
pub const WebView = @import("media/module.zig").WebView;
/// A platform view the app owns, placed where layout puts it.
pub const NativeView = @import("media/module.zig").NativeView;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("core/module.zig");
    _ = @import("text/module.zig");
    _ = @import("controls/module.zig");
    _ = @import("containers/module.zig");
    _ = @import("window/module.zig");
    _ = @import("chat/module.zig");
    _ = @import("panes/module.zig");
    _ = @import("split/module.zig");
    _ = @import("hover/module.zig");
    _ = @import("menu_bar/module.zig");
    _ = @import("status_line/module.zig");
    _ = @import("media/module.zig");
    _ = @import("forms/module.zig");
    _ = @import("view_engine_test.zig");
    _ = @import("integration_test.zig");
}
