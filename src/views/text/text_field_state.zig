//! The editable-text model shared by `TextField` and `TextEditor`: a buffer,
//! a caret, a selection and the vertical-motion machinery, over `TextLines`'
//! UTF-8 line and column geometry. No view or render dependency, so it is
//! unit-testable in isolation and reused by both the single-line field and
//! the multi-line editor.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_field_state);
const mod = @import("module.zig");

/// Character class for word-wise selection (double-click). Runs of the same
/// class are selected together; UTF-8 multi-byte sequences count as `word` so
/// accented/CJK text groups naturally.
const CharClass = enum {
    const Self = @This();

    /// Letters, digits, `_` and any non-ASCII byte.
    word,

    /// Spaces, tabs and line breaks.
    space,

    /// Punctuation and everything else.
    other,

    /// The class of a byte.
    ///
    /// - `byte`: the byte.
    /// - Returns: its class.
    fn of(byte: u8) Self {
        if (byte >= 0x80) return .word;
        return switch (byte) {
            ' ', '\t', '\n', '\r' => .space,
            'a'...'z', 'A'...'Z', '0'...'9', '_' => .word,
            else => .other,
        };
    }
};

/// Editable text buffer + caret for a `TextField` or `TextEditor`. Owned by the
/// app (like a `State`), so editing survives across frames. Key events call its
/// methods. Beyond a caret it tracks an optional selection (`selection_anchor`)
/// and, for multi-line editors, the machinery for vertical motion and
/// caret-follow scrolling.
pub const TextFieldState = struct {
    const Self = @This();

    /// The text.
    buffer: std.ArrayList(u8) = .empty,

    /// The caret, a byte index.
    caret: usize = 0,

    /// Selection anchor (byte index). When non-null and different from `caret`,
    /// the selection is the ordered range [min, max]. A plain (un-shifted) move
    /// or any edit collapses it (back to `null`).
    selection_anchor: ?usize = null,

    /// Whether the field has the keyboard focus.
    focused: bool = false,

    /// True for a `TextEditor` (multi-line). The event loop then inserts a
    /// newline on Enter (instead of submitting) and routes Up/Down/Home/End/Tab.
    /// Set by the editor's painter each frame.
    multiline: bool = false,

    /// Preferred column (codepoints from the line start) for vertical motion, so
    /// a run of Up/Down keeps the original column across shorter lines. Reset by
    /// any horizontal move or edit.
    preferred_column: ?usize = null,

    /// The caret seen at the previous paint. `TextEditor` auto-scrolls to follow
    /// the caret only when it actually moved, so the wheel can scroll freely
    /// otherwise.
    last_caret: usize = 0,

    /// Bumped on every mutation so an app can cheaply detect "modified since
    /// saved" without diffing the buffer.
    revision: u64 = 0,

    /// The `.onSubmit` callback for this field, refreshed during paint while the
    /// field is focused so `Focus.submit` (called from the event loop on Enter)
    /// can fire it without the view tree.
    on_submit: ?mod.Callback = null,

    /// Where `buffer` grows.
    allocator: std.mem.Allocator,

    /// An empty field.
    ///
    /// - `allocator`: where the text is kept.
    /// - Returns: the field.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees the text, and drops every reference the focus, the context menu
    /// and a text drag hold to the field, so none outlives it.
    ///
    /// - `self`: the field.
    pub fn deinit(self: *Self) void {
        mod.PointerInput.shared().forget(self);
        mod.TextContextMenu.shared().forget(self);
        mod.Focus.shared().forget(self);
        self.buffer.deinit(self.allocator);
    }

    /// The text.
    ///
    /// - `self`: the field.
    /// - Returns: the buffer's bytes, valid until the next mutation.
    pub fn text(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Replaces the text, the caret at its end.
    ///
    /// - `self`: the field.
    /// - `string`: the new text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setText(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, string);
        self.caret = self.buffer.items.len;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.last_caret = self.caret;
        self.revision +%= 1;
    }

    // --- selection ---------------------------------------------------------

    /// The current selection as an ordered byte range.
    ///
    /// - `self`: the field.
    /// - Returns: the range, or null when the caret is a plain insertion point
    ///   (no anchor, or an empty selection).
    pub fn selectionRange(self: *const Self) ?struct { start: usize, end: usize } {
        const anchor = self.selection_anchor orelse return null;
        if (anchor == self.caret) return null;
        return .{ .start = @min(anchor, self.caret), .end = @max(anchor, self.caret) };
    }

    /// Whether some text is selected.
    ///
    /// - `self`: the field.
    /// - Returns: true for a non-empty selection.
    pub fn hasSelection(self: *const Self) bool {
        return self.selectionRange() != null;
    }

    /// The selected text.
    ///
    /// - `self`: the field.
    /// - Returns: a slice into the buffer, empty when nothing is selected;
    ///   borrowed, valid only until the next mutation.
    pub fn selectedText(self: *const Self) []const u8 {
        const range = self.selectionRange() orelse return self.buffer.items[0..0];
        return self.buffer.items[range.start..range.end];
    }

    /// Selects the whole text.
    ///
    /// - `self`: the field.
    pub fn selectAll(self: *Self) void {
        if (self.buffer.items.len == 0) {
            self.selection_anchor = null;
            return;
        }
        self.selection_anchor = 0;
        self.caret = self.buffer.items.len;
        self.preferred_column = null;
    }

    /// Selects the word (or run of whitespace/punctuation) containing a byte:
    /// the double-click gesture. Leaves an ordered selection with the caret at
    /// its end.
    ///
    /// - `self`: the field.
    /// - `index`: the byte clicked.
    pub fn selectWordAt(self: *Self, index: usize) void {
        const items = self.buffer.items;
        if (items.len == 0) {
            self.selection_anchor = null;
            self.caret = 0;
            return;
        }
        const lines = mod.TextLines.init(items);
        var clicked = @min(index, items.len);
        if (clicked == items.len) clicked = lines.previousCodepointStart(clicked); // classify the last char
        const class = CharClass.of(items[clicked]);
        var start = clicked;
        while (start > 0) {
            const previous = lines.previousCodepointStart(start);
            if (CharClass.of(items[previous]) != class) break;
            start = previous;
        }
        var stop = clicked;
        while (stop < items.len) {
            if (CharClass.of(items[stop]) != class) break;
            stop = lines.nextCodepointEnd(stop);
        }
        self.selection_anchor = start;
        self.caret = stop;
        self.preferred_column = null;
    }

    /// Deletes the selected range, if any.
    ///
    /// - `self`: the field.
    /// - Returns: true if something was removed.
    pub fn deleteSelection(self: *Self) bool {
        const range = self.selectionRange() orelse {
            self.selection_anchor = null;
            return false;
        };
        const count = range.end - range.start;
        std.mem.copyForwards(u8, self.buffer.items[range.start..], self.buffer.items[range.end..]);
        self.buffer.shrinkRetainingCapacity(self.buffer.items.len - count);
        self.caret = range.start;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.revision +%= 1;
        return true;
    }

    // --- editing -----------------------------------------------------------

    /// Inserts text at the caret, replacing the selection.
    ///
    /// - `self`: the field.
    /// - `string`: the text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn insert(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        _ = self.deleteSelection();
        try self.buffer.insertSlice(self.allocator, self.caret, string);
        self.caret += string.len;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.revision +%= 1;
    }

    /// Deletes the selection, or the codepoint before the caret.
    ///
    /// - `self`: the field.
    pub fn backspace(self: *Self) void {
        if (self.deleteSelection()) return;
        if (self.caret == 0) return;
        const start = mod.TextLines.init(self.buffer.items).previousCodepointStart(self.caret);
        const count = self.caret - start;
        std.mem.copyForwards(u8, self.buffer.items[start..], self.buffer.items[self.caret..]);
        self.buffer.shrinkRetainingCapacity(self.buffer.items.len - count);
        self.caret = start;
        self.preferred_column = null;
        self.revision +%= 1;
    }

    /// Forward-delete (the Delete key): deletes the selection, or the codepoint
    /// after the caret.
    ///
    /// - `self`: the field.
    pub fn deleteForward(self: *Self) void {
        if (self.deleteSelection()) return;
        const items = self.buffer.items;
        if (self.caret >= items.len) return;
        const stop = mod.TextLines.init(items).nextCodepointEnd(self.caret);
        std.mem.copyForwards(u8, self.buffer.items[self.caret..], self.buffer.items[stop..]);
        self.buffer.shrinkRetainingCapacity(items.len - (stop - self.caret));
        self.preferred_column = null;
        self.revision +%= 1;
    }

    // --- caret movement (extend = Shift held, growing the selection) -------

    /// Moves the caret one codepoint left; a plain move collapses a selection
    /// to its left edge.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveLeft(self: *Self, extend: bool) void {
        self.preferred_column = null;
        if (!extend) {
            if (self.selectionRange()) |range| {
                self.caret = range.start;
                self.selection_anchor = null;
                return;
            }
        }
        self.beginExtend(extend);
        if (self.caret > 0) self.caret = mod.TextLines.init(self.buffer.items).previousCodepointStart(self.caret);
    }

    /// Moves the caret one codepoint right; a plain move collapses a selection
    /// to its right edge.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveRight(self: *Self, extend: bool) void {
        self.preferred_column = null;
        if (!extend) {
            if (self.selectionRange()) |range| {
                self.caret = range.end;
                self.selection_anchor = null;
                return;
            }
        }
        self.beginExtend(extend);
        const items = self.buffer.items;
        if (self.caret < items.len) self.caret = mod.TextLines.init(items).nextCodepointEnd(self.caret);
    }

    /// Moves the caret to its line's start.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn home(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        self.caret = mod.TextLines.init(self.buffer.items).lineStart(self.caret);
        self.preferred_column = null;
    }

    /// Moves the caret to its line's end.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn end(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        self.caret = mod.TextLines.init(self.buffer.items).lineEnd(self.caret);
        self.preferred_column = null;
    }

    /// Moves the caret up a line, keeping the preferred column.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveUp(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        const lines = mod.TextLines.init(self.buffer.items);
        const line_start = lines.lineStart(self.caret);
        if (self.preferred_column == null) self.preferred_column = lines.column(self.caret);
        if (line_start == 0) {
            self.caret = 0; // already on the first line
            return;
        }
        const previous_end = line_start - 1; // the '\n' that ends the previous line
        const previous_start = lines.lineStart(previous_end);
        self.caret = lines.indexForColumn(previous_start, previous_end, self.preferred_column.?);
    }

    /// Moves the caret down a line, keeping the preferred column.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveDown(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        const lines = mod.TextLines.init(self.buffer.items);
        const line_end = lines.lineEnd(self.caret);
        if (self.preferred_column == null) self.preferred_column = lines.column(self.caret);
        if (line_end >= lines.bytes.len) {
            self.caret = lines.bytes.len; // already on the last line
            return;
        }
        const next_start = line_end + 1;
        const next_end = lines.lineEnd(next_start);
        self.caret = lines.indexForColumn(next_start, next_end, self.preferred_column.?);
    }

    /// The caret's 1-based line and column (counting codepoints), for a status bar.
    ///
    /// - `self`: the field.
    /// - Returns: the line and the column.
    pub fn lineColumn(self: *const Self) struct { line: usize, column: usize } {
        const lines = mod.TextLines.init(self.buffer.items);
        return .{
            .line = lines.lineIndex(self.caret) + 1,
            .column = lines.column(self.caret) + 1,
        };
    }

    /// Anchors a selection at the caret when Shift is held, or drops it.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held.
    fn beginExtend(self: *Self, extend: bool) void {
        if (extend) {
            if (self.selection_anchor == null) self.selection_anchor = self.caret;
        } else self.selection_anchor = null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "TextFieldState: editing operations" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.insert("hello");
    try std.testing.expectEqualStrings("hello", field.text());
    try std.testing.expectEqual(@as(usize, 5), field.caret);
    field.backspace();
    try std.testing.expectEqualStrings("hell", field.text());
    field.moveLeft(false);
    field.moveLeft(false);
    try field.insert("X");
    try std.testing.expectEqualStrings("heXll", field.text());
    try field.setText("done");
    try std.testing.expectEqualStrings("done", field.text());
    try std.testing.expectEqual(@as(usize, 4), field.caret);
}

test "TextFieldState: backspace handles a multi-byte codepoint" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.insert("é"); // 2 bytes
    try std.testing.expectEqual(@as(usize, 2), field.caret);
    field.backspace();
    try std.testing.expectEqual(@as(usize, 0), field.text().len);
}

test "TextFieldState: selection editing (insert/backspace replace, selectAll)" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello world");
    // Select "world" by anchoring at 6 and moving to the end.
    field.caret = 6;
    field.selection_anchor = 6;
    field.end(true);
    const range = field.selectionRange().?;
    try std.testing.expectEqual(@as(usize, 6), range.start);
    try std.testing.expectEqual(@as(usize, 11), range.end);
    // Typing replaces the selection.
    try field.insert("there");
    try std.testing.expectEqualStrings("hello there", field.text());
    try std.testing.expect(!field.hasSelection());
    // Select-all then backspace clears everything.
    field.selectAll();
    field.backspace();
    try std.testing.expectEqual(@as(usize, 0), field.text().len);
}

test "TextFieldState: a plain move collapses the selection to an edge" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("abcdef");
    field.caret = 1;
    field.selection_anchor = 4; // selection [1,4)
    field.moveLeft(false); // collapse to the left edge
    try std.testing.expectEqual(@as(usize, 1), field.caret);
    try std.testing.expect(!field.hasSelection());
    field.caret = 1;
    field.selection_anchor = 4;
    field.moveRight(false); // collapse to the right edge
    try std.testing.expectEqual(@as(usize, 4), field.caret);
    try std.testing.expect(!field.hasSelection());
}

test "TextFieldState: multi-line up/down keeps the preferred column" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello\nhi\nworld"); // lines: 0:"hello" 1:"hi" 2:"world"
    // Put the caret at column 4 of the first line ("hell|o").
    field.caret = 4;
    field.moveDown(false); // line 1 "hi" is shorter -> clamp to its end (col 2, byte 8)
    try std.testing.expectEqual(@as(usize, 8), field.caret);
    field.moveDown(false); // line 2 "world" -> preferred column 4 restored ("worl|d", byte 9+4)
    try std.testing.expectEqual(@as(usize, 13), field.caret);
    // Home/End and 1-based line/col.
    field.home(false);
    try std.testing.expectEqual(@as(usize, 9), field.caret);
    const line_column = field.lineColumn();
    try std.testing.expectEqual(@as(usize, 3), line_column.line);
    try std.testing.expectEqual(@as(usize, 1), line_column.column);
    field.end(false);
    try std.testing.expectEqual(@as(usize, 14), field.caret);
}

test "TextFieldState: forward delete and revision tracking" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("abc");
    const first_revision = field.revision;
    field.caret = 1;
    field.deleteForward(); // removes 'b'
    try std.testing.expectEqualStrings("ac", field.text());
    try std.testing.expectEqual(@as(usize, 1), field.caret);
    try std.testing.expect(field.revision != first_revision); // a mutation bumped the revision
    field.caret = field.buffer.items.len;
    field.deleteForward(); // at end -> no-op
    try std.testing.expectEqualStrings("ac", field.text());
}

test "TextFieldState: deinit drops the focus, the context menu and a text drag on it" {
    var other = TextFieldState.init(std.testing.allocator);
    defer other.deinit();
    const field = try std.testing.allocator.create(TextFieldState);
    defer std.testing.allocator.destroy(field);
    field.* = TextFieldState.init(std.testing.allocator);
    try field.setText("going away");
    mod.TextContextMenu.shared().open(field, .{ .x = 0, .y = 0 }); // focuses it too
    mod.PointerInput.shared().text_drag = field;
    field.deinit();
    try std.testing.expect(mod.Focus.shared().focused() == null);
    try std.testing.expect(!mod.TextContextMenu.shared().isOpen());
    try std.testing.expect(mod.PointerInput.shared().text_drag == null);

    // Focusing another field writes to no freed one, and freeing a field that
    // is not focused leaves the focus alone.
    mod.Focus.shared().set(&other);
    defer mod.Focus.shared().clear();
    var unfocused = TextFieldState.init(std.testing.allocator);
    unfocused.deinit();
    try std.testing.expect(mod.Focus.shared().focused() == &other);
    try std.testing.expect(other.focused);
}

test "TextFieldState: a bad UTF-8 byte is stepped and deleted alone" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("\xe2ab");
    field.caret = 0;
    field.moveRight(false); // past the lead byte only, not the "a" after it
    try std.testing.expectEqual(@as(usize, 1), field.caret);
    field.moveLeft(false);
    try std.testing.expectEqual(@as(usize, 0), field.caret);
    field.deleteForward(); // the lead byte alone
    try std.testing.expectEqualStrings("ab", field.text());
    try field.setText("a\x80b");
    field.backspace(); // "b"
    field.backspace(); // the stray continuation byte alone, not the "a" before it
    try std.testing.expectEqualStrings("a", field.text());
    try field.setText("\xe2abc");
    field.selectWordAt(0); // the bad byte and the letters are one word
    try std.testing.expectEqualStrings("\xe2abc", field.selectedText());
}
