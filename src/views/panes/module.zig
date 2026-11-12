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
/// One row of a `DiffView` (`hunkCount`, `hunkRow` and `revealHunk` work on a diff).
pub const DiffLine = @import("diff_line.zig").DiffLine;
/// A list that builds only the rows in view.
pub const VirtualList = @import("panes.zig").VirtualList;
/// A `VirtualList` that also scrolls sideways, as wide as its widest row.
pub const VirtualListBoth = @import("panes.zig").VirtualListBoth;
/// A unified diff over a `VirtualList`.
pub const DiffView = @import("panes.zig").DiffView;
/// A table's header row.
pub const TableHeader = @import("panes.zig").TableHeader;
/// One table row.
pub const TableRow = @import("panes.zig").TableRow;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// The build-time theme colors: ziggui's, plus ziggui's `label`, `separator`, `added`, `removed` (from the views module).
pub const BuildTokens = @import("../module.zig").BuildTokens;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// One column of a data table (and of `TableHeader`/`TableRow`), from the views module.
pub const DataColumn = @import("../module.zig").DataColumn;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
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
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("index_callback.zig");
    _ = @import("row_range.zig");
    _ = @import("diff_line.zig");
    _ = @import("panes.zig");
}
