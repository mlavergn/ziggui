//! Panes over a scroll view: a list that builds only the rows in view, a unified
//! diff over it, and table rows, with the index callbacks and row ranges they use.

const std = @import("std");
const log = std.log.scoped(.ziggui_panes_module);

/// A callback that takes a row index (`init` wraps a method, `bind` fixes the index).
pub const IndexCallback = @import("index_callback.zig").IndexCallback;
/// The rows a `VirtualList` builds (`visible` says which are in view).
pub const RowRange = @import("row_range.zig").RowRange;
/// The height of one diff row, in points.
pub const diff_row_height = @import("diff_line.zig").diff_row_height;
/// What a `DiffLine` is.
pub const DiffLineKind = @import("diff_line.zig").DiffLineKind;
/// One row of a `DiffView` (`hunkCount`, `hunkRow` and `revealHunk` work on a diff; `wrap` and `wrapColumns` wrap one to a width, `anchorAt` and `offsetAt` keep a scroll position across a re-wrap).
pub const DiffLine = @import("diff_line.zig").DiffLine;
/// Where a scroll offset over a diff's rows falls, kept across a re-wrap (`DiffLine.anchorAt`, `DiffLine.offsetAt`).
pub const DiffAnchor = @import("diff_line.zig").DiffAnchor;
/// How a `DiffView` lays out a row (text size, cells, tabs, gutter), shared with `DiffLine.wrap`.
pub const DiffLayout = @import("diff_layout.zig").DiffLayout;
/// A list that builds only the rows in view.
pub const VirtualList = @import("panes.zig").VirtualList;
/// A `VirtualList` that also scrolls sideways, as wide as its widest row.
pub const VirtualListBoth = @import("panes.zig").VirtualListBoth;
/// A unified diff over a `VirtualList`.
pub const DiffView = @import("panes.zig").DiffView;
/// A `DiffView` whose lines can be selected and copied (`DiffSelection`).
pub const SelectableDiffView = @import("panes.zig").SelectableDiffView;
/// A `SelectableDiffView` with links on every hunk header, pinned to the pane's right edge (`HunkAction`).
pub const SelectableDiffViewWithActions = @import("panes.zig").SelectableDiffViewWithActions;
/// A link on a `SelectableDiffViewWithActions`' hunk headers, called with its hunk's index.
pub const HunkAction = @import("hunk_action.zig").HunkAction;
/// The lines selected in a `SelectableDiffView`, kept by the app.
pub const DiffSelection = @import("diff_selection.zig").DiffSelection;
/// A `SelectableDiffViewWithActions` with a find bar and its matches marked (`DiffFindState`).
pub const FindableDiffView = @import("panes.zig").FindableDiffView;
/// A diff's find, kept by the app: the query, the options, the matches and the current one.
pub const DiffFindState = @import("diff_find_state.zig").DiffFindState;
/// One match of a diff find: a row and a byte range of its text.
pub const DiffMatch = @import("diff_find_state.zig").DiffMatch;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// Which window drew which frame (`BuildScope.stamp`), from the views module.
pub const FrameStamp = @import("../module.zig").FrameStamp;
/// Text made safe to draw: each invalid UTF-8 byte becomes U+FFFD (from the views module).
pub const DisplayText = @import("../module.zig").DisplayText;
/// The build-time theme colors: ziggui's, plus ziggui's `label`, `separator`, `added`, `removed` (from the views module).
pub const BuildTokens = @import("../module.zig").BuildTokens;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// A drag handler a view hands the pointer (`onDrag`), from the views module.
pub const DragCallback = @import("../module.zig").DragCallback;
/// The live selection ⌘C copies (`TextSelection.shared()`), from the views module.
pub const TextSelection = @import("../module.zig").TextSelection;
/// Routes pointer events to a frame's regions (`PointerInput.shared()`), from the views module.
pub const PointerInput = @import("../module.zig").PointerInput;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;
/// A scroll view's app-owned offset and extents (from the views module).
pub const ScrollState = @import("../module.zig").ScrollState;
/// A scrolling viewport whose offset lives in a `ScrollState` (from the views module).
pub const ScrollViewState = @import("../module.zig").ScrollViewState;
/// A viewport that scrolls both ways, its offsets in a `ScrollState` (from the views module).
pub const ScrollViewStateBoth = @import("../module.zig").ScrollViewStateBoth;
/// Builds stack views from tuples or slices (`fromSlice` keeps its slice), from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless window for the unit tests (from the views module).
pub const TestWindow = @import("../module.zig").TestWindow;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// Steps over UTF-8 as the renderer draws it (`nextCodepointEnd`), from the views module.
pub const TextLines = @import("../module.zig").TextLines;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// A two-way handle to a value (from the views module).
pub const Binding = @import("../module.zig").Binding;
/// One styled run of a rich paragraph (from the views module).
pub const Span = @import("../module.zig").Span;
/// A text field's text, caret and selection (from the views module).
pub const TextFieldState = @import("../module.zig").TextFieldState;
/// Plain-text search over a buffer (from the views module).
pub const TextSearch = @import("../module.zig").TextSearch;
/// How a `TextSearch` matches: case and whole words (from the views module).
pub const TextSearchOptions = @import("../module.zig").TextSearchOptions;
/// Which field holds the keyboard (`Focus.shared()`), from the views module.
pub const Focus = @import("../module.zig").Focus;
/// A key press, as apps and menus handle it (from the views module).
pub const Key = @import("../module.zig").Key;
/// A find bar: a search field, the count, and Previous, Next and Done (from the views module).
pub const FindBar = @import("../module.zig").FindBar;
/// What a `FindBar`'s field, buttons and keys do (from the views module).
pub const FindActions = @import("../module.zig").FindActions;
/// A byte range of a text (a match), from the views module.
pub const TextRange = @import("../module.zig").TextRange;
/// A line with byte ranges marked, as preformatted spans, from the views module.
pub const HighlightSpans = @import("../module.zig").HighlightSpans;
/// What a find's matches were found for, from the views module.
pub const FindMatchesKey = @import("../module.zig").FindMatchesKey;
/// A find's matches, from the views module.
pub const FindMatches = @import("../module.zig").FindMatches;
/// Where a find stands: which match is current, of how many (from the views module).
pub const FindCount = @import("../module.zig").FindCount;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("index_callback.zig");
    _ = @import("row_range.zig");
    _ = @import("diff_line.zig");
    _ = @import("diff_layout.zig");
    _ = @import("diff_selection.zig");
    _ = @import("hunk_action.zig");
    _ = @import("diff_find_state.zig");
    _ = @import("panes.zig");
}
