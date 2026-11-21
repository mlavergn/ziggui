//! How a `Table` lays out, selects, sorts and draws its header: what an app passes
//! beside its rows.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_options);
const mod = @import("module.zig");

/// How a `Table` lays its rows out.
pub const TableLayout = enum {
    const Self = @This();

    /// A fixed header over rows built only while in view, scrolling both
    /// ways; as big as the table is given.
    scrolling,
    /// Every row built and the table as tall as they are, nothing scrolled:
    /// a short table inside a larger pane.
    fitted,
};

/// A `Table`'s options, for a table whose context is a `T`.
///
/// - `T`: the app's context type, as `Table` takes it.
/// - Returns: the options type.
pub fn TableOptions(comptime T: type) type {
    return struct {
        const Self = @This();

        /// How the rows are laid out: scrolling and built while in view, or
        /// fitted, every row built and the table as tall as they are.
        layout: mod.TableLayout = .scrolling,

        /// Whether the header shows (SwiftUI's `.tableColumnHeaders`):
        /// `.automatic` and `.visible` show it, `.hidden` leaves the rows alone.
        column_headers: mod.Visibility = .automatic,

        /// Each row's height, in points, or null for a `Table` row's: a line
        /// of the theme's body text and 5 points above and below it.
        row_height: ?f32 = null,

        /// What a tap, a ⌘/⇧ tap and the arrows select.
        selection_mode: mod.TableSelectionMode = .row,

        /// Whether ⌘ and ⇧ select several rows (a table with an `idFn`);
        /// false keeps one row selected, still by ID, so it survives a re-sort.
        multiple_selection: bool = true,

        /// What a double click or Enter calls with the row's position (the
        /// column, in `.cell` mode, is `state.cursor`'s).
        on_activate: ?mod.IndexCallback = null,

        /// What a sorting header tap calls, after `state.sort` changed: the
        /// app re-sorts its rows.
        on_sort: ?mod.Callback = null,

        /// What every selection change calls.
        on_selection: ?mod.Callback = null,

        /// Rows the app marks with the selection fill, beside the selection
        /// (the current find match, say), or null for none.
        ///
        /// - `context`: the app's context.
        /// - `row`: the row's position.
        /// - Returns: true to mark the row.
        highlighted: ?*const fn (context: *const T, row: usize) bool = null,

        /// A view under each column's title (a filter field, say), or null
        /// for a header of titles only.
        ///
        /// - `context`: the app's context.
        /// - `column`: the column's index.
        /// - Returns: the view, framed to the column's width.
        header_accessory: ?*const fn (context: *const T, column: usize) mod.View = null,

        /// The header's height, or null for a `Table` header's: a line of the
        /// theme's subheadline and 5 points above and below it (and with
        /// accessories, the theme's control height and their gap too).
        header_height: ?f32 = null,

        /// What shows in place of the rows while there are none (a scrolling
        /// table's), or null for nothing.
        empty: ?mod.View = null,

        /// Whether dragging a header's trailing edge resizes the column; a
        /// fitted table never does (it scrolls nothing, so a column dragged
        /// past its pane could not be reached).
        resizable: bool = true,
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(TableOptions(u8));
    // Nothing here does I/O to trace.
    _ = log;
}
