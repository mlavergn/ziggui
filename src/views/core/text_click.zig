//! The geometry of a text field's or editor's clickable text, enough to map a
//! point to a caret without a `Context`.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_click);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Geometry captured for a `TextEditor`'s (or `TextField`'s) clickable text
/// area, enough to map a pixel point to a caret byte index (`caretIndexAt`)
/// without a `Context`.
pub const TextClick = struct {
    const Self = @This();

    /// The field the click edits.
    state: *mod.TextFieldState,

    /// The face the text is drawn in.
    face: *const renderer.TtfFont,

    /// The text's size.
    pixel_size: f32,

    /// The text's top-left.
    origin: renderer.Point,

    /// How far the text is scrolled down.
    scroll_y: f32,

    /// One line's height.
    line_height: f32,

    /// Wrapped visual rows (byte ranges into the text) when the editor is in
    /// soft-wrap mode; empty for the normal one-row-per-logical-line editor.
    /// Computed at paint and valid until the next rebuild (arena), so the click
    /// maps to a caret without re-wrapping. An edit in the same event batch
    /// (select all, delete) can leave them past the text's end, so
    /// `caretIndexAt` clamps them to it.
    rows: []const renderer.WrappedLine = &.{},

    /// Maps a pixel point to a caret byte index, clamping to the document (a
    /// point above/below/left maps to the nearest edge).
    ///
    /// - `self`: the text's geometry.
    /// - `point`: the click.
    /// - Returns: the byte index of the caret there.
    pub fn caretIndexAt(self: *const Self, point: renderer.Point) usize {
        const text = self.state.text();
        const relative_y = point.y - self.origin.y + self.scroll_y;
        // Soft-wrap editor: rows are visual wrapped lines (byte ranges into `text`).
        if (self.rows.len > 0) {
            var row_index: usize = if (relative_y <= 0) 0 else @intFromFloat(relative_y / self.line_height);
            if (row_index >= self.rows.len) row_index = self.rows.len - 1;
            // The rows were wrapped at the last paint; the text may have
            // shrunk since, so keep them inside it.
            const row = self.rows[row_index];
            const start = @min(row.start, text.len);
            const end = @min(row.end, text.len);
            return start + mod.EditorMetrics.init(self.face, self.pixel_size).caretInLine(text[start..end], point.x - self.origin.x);
        }
        const total = mod.TextLines.init(text).lineCount();
        var line_index: usize = if (relative_y <= 0) 0 else @intFromFloat(relative_y / self.line_height);
        if (line_index >= total) line_index = total - 1;
        const range = mod.TextLines.init(text).lineRange(line_index);
        return range.start + mod.EditorMetrics.init(self.face, self.pixel_size).caretInLine(text[range.start..range.end], point.x - self.origin.x);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a soft-wrap click after an edit shrank the text stays inside it" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello world, a prompt that is typed");
    // Rows wrapped at the last paint, before select-all and delete emptied it.
    const rows = [_]renderer.WrappedLine{ .{ .start = 0, .end = 18, .width = 100 }, .{ .start = 19, .end = 35, .width = 90 } };
    field.selectAll();
    field.backspace();
    const click: TextClick = .{ .state = &field, .face = &environment.font.face, .pixel_size = 14, .origin = .{ .x = 0, .y = 0 }, .scroll_y = 0, .line_height = 17, .rows = &rows };
    try std.testing.expectEqual(@as(usize, 0), click.caretIndexAt(.{ .x = 40, .y = 2 }));
    try std.testing.expectEqual(@as(usize, 0), click.caretIndexAt(.{ .x = 40, .y = 20 }));

    // Shrunk mid-row: the caret lands at most at the text's end.
    try field.setText("hello world");
    try std.testing.expectEqual(@as(usize, 11), click.caretIndexAt(.{ .x = 400, .y = 2 }));
    try std.testing.expectEqual(@as(usize, 11), click.caretIndexAt(.{ .x = 40, .y = 20 }));
}
