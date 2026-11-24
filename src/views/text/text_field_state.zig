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

/// The lines an indent or outdent works on, by their first bytes.
const LineSpan = struct {
    const Self = @This();

    /// The first line's start.
    first: usize,

    /// The last line's start.
    last: usize,

    /// The caret's line alone.
    ///
    /// - `field`: the field.
    /// - Returns: the span.
    fn ofCaret(field: *const TextFieldState) Self {
        const start = mod.TextLines.init(field.buffer.items).lineStart(field.caret);
        return .{ .first = start, .last = start };
    }
};

/// The last revision any field was given, so each new one is unique in the
/// process: a cache keyed by a field's address and revision (a find's
/// matches) never mistakes a new field at a freed one's address for it.
var last_revision = std.atomic.Value(u64).init(0);

/// Enough spaces for the widest indentation level.
const spaces: [mod.TextIndentation.max_width]u8 = @splat(' ');

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

    /// A one-line field's sideways scroll, in points: kept by its painter
    /// across frames, so the text moves only when the caret leaves the view.
    scroll_x: f32 = 0,

    /// True for a `SecureField` (a password): its text is never copied,
    /// cut, or given to accessibility, and is wiped from memory it leaves.
    /// Set by the field's painter each frame; an app that fills the field
    /// with a stored secret before its first frame sets it first, so the
    /// buffer's growth wipes as it goes.
    secure: bool = false,

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

    /// Names the text's content: every edit gives it a value no field in the
    /// process has had, and undo and redo give back the value the text had then, so
    /// an app compares it with the one it saved at ("modified since saved")
    /// without diffing the buffer, and an undo back to a save reads clean.
    revision: u64 = 0,

    /// The undo and redo steps (none for a secure field).
    history: mod.TextHistory,

    /// What Tab inserts and where tab characters stop: read by a
    /// `TextEditor` (a one-line field's Tab moves the focus instead).
    indentation: mod.TextIndentation = .{},

    /// How the document's lines end on disk (`encodedAlloc`); the buffer
    /// always holds `\n`.
    line_ending: mod.LineEnding = .lf,

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
        const self = Self{ .allocator = allocator, .history = mod.TextHistory.init(allocator) };
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
        std.crypto.secureZero(u8, self.buffer.allocatedSlice());
        self.buffer.deinit(self.allocator);
        self.history.deinit();
    }

    /// The text.
    ///
    /// - `self`: the field.
    /// - Returns: the buffer's bytes, valid until the next mutation.
    pub fn text(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Replaces the text, the caret at its end: a load, so the undo history
    /// is forgotten (`setTextUndoable` keeps it).
    ///
    /// - `self`: the field.
    /// - `string`: the new text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setText(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        // The old text goes from memory, not only from view (`wipe`).
        self.wipe();
        try self.reserve(string.len);
        self.buffer.appendSliceAssumeCapacity(string);
        self.caret = self.buffer.items.len;
        self.last_caret = self.caret;
    }

    /// Empties the field and zeroes every byte it held: a password's or a key's field closing.
    ///
    /// - `self`: the field.
    pub fn wipe(self: *Self) void {
        // The whole buffer, since bytes deleted earlier linger past the
        // text's end. Cleared first: a clear marks the bytes undefined, which
        // a debug build fills, after any zeroing.
        self.buffer.clearRetainingCapacity();
        std.crypto.secureZero(u8, self.buffer.allocatedSlice());
        self.caret = 0;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.last_caret = 0;
        self.history.clear();
        self.newRevision();
    }

    /// Replaces the whole text as one step the user can undo (a format
    /// pass, a conversion), the caret at its end.
    ///
    /// - `self`: the field.
    /// - `string`: the new text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setTextUndoable(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        try self.edit(0, self.buffer.items.len, string, .other);
    }

    /// Replaces a byte range with text, as one step of its own: the one
    /// edit every other goes through. The caret lands after the text.
    ///
    /// - `self`: the field.
    /// - `start`: the range's first byte.
    /// - `stop`: the byte just past it.
    /// - `string`: the text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn replaceRange(self: *Self, start: usize, stop: usize, string: []const u8) std.mem.Allocator.Error!void {
        try self.edit(start, stop, string, .other);
    }

    /// Pastes text at the caret, replacing the selection, as one step of
    /// its own; in an editor (`multiline`) its line breaks become `\n`, while
    /// a one-line field takes the bytes as they are.
    ///
    /// - `self`: the field.
    /// - `string`: the text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paste(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        const range = self.editRange();
        if (!self.multiline or !mod.LineEnding.needsNormalizing(string)) return self.edit(range.start, range.stop, string, .other);
        const normalized = try mod.LineEnding.normalizeAlloc(self.allocator, string);
        defer {
            std.crypto.secureZero(u8, normalized);
            self.allocator.free(normalized);
        }
        try self.edit(range.start, range.stop, normalized, .other);
    }

    /// Loads a document as read from disk: its line ending and indentation
    /// detected (the indentation kept when none shows), its line breaks
    /// made `\n`, the undo history forgotten, the caret at its start.
    ///
    /// - `self`: the field.
    /// - `bytes`: the file's bytes.
    /// - Returns: nothing; propagates allocation failure.
    pub fn loadDocument(self: *Self, bytes: []const u8) std.mem.Allocator.Error!void {
        self.line_ending = mod.LineEnding.detect(bytes);
        if (mod.TextIndentation.detect(bytes)) |detected| self.indentation = detected;
        if (mod.LineEnding.needsNormalizing(bytes)) {
            const normalized = try mod.LineEnding.normalizeAlloc(self.allocator, bytes);
            defer self.allocator.free(normalized);
            try self.setText(normalized);
        } else try self.setText(bytes);
        self.caret = 0;
        self.last_caret = 0;
    }

    /// The text as a file holds it: each line break as `line_ending`.
    ///
    /// - `self`: the field.
    /// - `allocator`: where the copy goes.
    /// - Returns: the bytes, owned; propagates allocation failure.
    pub fn encodedAlloc(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return self.line_ending.encodeAlloc(allocator, self.buffer.items);
    }

    /// Changes how the document's lines end on disk. The text does not
    /// change, but the file would, so a change gives `revision` a new value
    /// (the document reads modified); it is no undo step.
    ///
    /// - `self`: the field.
    /// - `ending`: the new ending.
    pub fn setLineEnding(self: *Self, ending: mod.LineEnding) void {
        if (self.line_ending == ending) return;
        self.line_ending = ending;
        self.newRevision();
    }

    // --- indentation -------------------------------------------------------

    /// Tab in an editor: with a selection over more than one line, indents
    /// each of those lines (one undo step, the lines kept selected); else
    /// inserts a tab, or spaces up to the next stop, in place of any selection.
    ///
    /// - `self`: the field.
    /// - Returns: nothing; propagates allocation failure.
    pub fn indent(self: *Self) std.mem.Allocator.Error!void {
        if (self.selectedLines()) |lines| return self.indentLines(lines);
        const range = self.editRange();
        if (self.indentation.style == .tabs) return self.edit(range.start, range.stop, "\t", .typing);
        const width = self.indentation.columns();
        const column = self.visualColumn(range.start);
        try self.edit(range.start, range.stop, spaces[0 .. width - column % width], .typing);
    }

    /// ⇧Tab in an editor: takes one level (a tab, or up to a level of
    /// spaces) off the start of the caret's line, or of every line the
    /// selection touches, as one undo step.
    ///
    /// - `self`: the field.
    /// - Returns: nothing; propagates allocation failure.
    pub fn outdent(self: *Self) std.mem.Allocator.Error!void {
        const lines = self.selectedLines() orelse LineSpan.ofCaret(self);
        const revision_before = self.revision;
        self.beginUndoGrouping();
        defer self.endUndoGrouping();
        const anchor = self.selection_anchor;
        var start = if (anchor) |at| @min(at, self.caret) else self.caret;
        var stop = if (anchor) |at| @max(at, self.caret) else self.caret;
        const forward = if (anchor) |at| at <= self.caret else true;
        var line_start = lines.last;
        while (true) {
            const leading = self.leadingWhitespace(line_start);
            // A leading tab, else the spaces before any tab, up to a level.
            var taken: usize = 0;
            if (leading.len > 0 and leading[0] == '\t') {
                taken = 1;
            } else {
                while (taken < leading.len and taken < self.indentation.columns() and leading[taken] == ' ') taken += 1;
            }
            if (taken > 0) {
                start -= @min(taken, start -| line_start);
                stop -= @min(taken, stop -| line_start);
                self.remove(line_start, line_start + taken, .other);
            }
            if (line_start == lines.first) break;
            line_start = mod.TextLines.init(self.buffer.items).lineStart(line_start - 1);
        }
        if (self.revision != revision_before) self.restoreSelection(anchor != null, forward, start, stop);
    }

    /// Re-indents every line's leading whitespace in another style or width,
    /// as one undo step, and adopts it; the caret stays on its line.
    ///
    /// - `self`: the field.
    /// - `to`: the indentation to convert to.
    /// - Returns: nothing; propagates allocation failure.
    pub fn convertIndentation(self: *Self, to: mod.TextIndentation) std.mem.Allocator.Error!void {
        const lines = mod.TextLines.init(self.buffer.items);
        const caret_line = lines.lineIndex(self.caret);
        const from_line_end = lines.lineEnd(self.caret) - self.caret;
        // Every line's start, found in one pass, then converted from the last
        // back, so the starts before an edit stay where they were.
        var starts: std.ArrayList(usize) = .empty;
        defer starts.deinit(self.allocator);
        try starts.append(self.allocator, 0);
        for (self.buffer.items, 0..) |byte, index| {
            if (byte == '\n') try starts.append(self.allocator, index + 1);
        }
        const revision_before = self.revision;
        self.beginUndoGrouping();
        defer self.endUndoGrouping();
        var line_index = starts.items.len;
        while (line_index > 0) {
            line_index -= 1;
            const line_start = starts.items[line_index];
            const leading = self.leadingWhitespace(line_start);
            if (leading.len == 0) continue;
            const converted = try to.leadingAlloc(self.allocator, self.indentation.visualColumns(leading));
            defer self.allocator.free(converted);
            if (std.mem.eql(u8, converted, leading)) continue;
            try self.edit(line_start, line_start + leading.len, converted, .other);
        }
        self.indentation = to;
        if (self.revision == revision_before) return;
        const range = mod.TextLines.init(self.buffer.items).lineRange(caret_line);
        self.caret = range.end - @min(from_line_end, range.end - range.start);
        self.history.settle(self.caret, self.revision);
    }

    // --- undo --------------------------------------------------------------

    /// Whether there is a step to undo.
    ///
    /// - `self`: the field.
    /// - Returns: true when one is kept (never for a secure field).
    pub fn canUndo(self: *const Self) bool {
        return !self.secure and self.history.canUndo();
    }

    /// Whether there is a step to redo.
    ///
    /// - `self`: the field.
    /// - Returns: true when one is kept (never for a secure field).
    pub fn canRedo(self: *const Self) bool {
        return !self.secure and self.history.canRedo();
    }

    /// Takes back the last step: its edits undone newest first, the caret,
    /// selection and revision as they were before it.
    ///
    /// - `self`: the field.
    /// - Returns: whether there was one; propagates allocation failure (nothing changed then).
    pub fn undo(self: *Self) std.mem.Allocator.Error!bool {
        if (!self.canUndo()) return false;
        // Room first: growing the stacks moves the group.
        try self.history.reserveMove();
        const group = self.history.nextUndo().?;
        try self.reserve(group.removedLength());
        var index = group.edits.items.len;
        while (index > 0) {
            index -= 1;
            const step = group.edits.items[index];
            self.splice(step.start, step.start + step.inserted.len, step.removed);
        }
        self.caret = group.caret_before;
        self.selection_anchor = group.anchor_before;
        self.preferred_column = null;
        self.revision = group.revision_before;
        self.history.didUndo();
        return true;
    }

    /// Puts back the last step undone: its edits redone oldest first, the
    /// caret and revision as they were after it.
    ///
    /// - `self`: the field.
    /// - Returns: whether there was one; propagates allocation failure (nothing changed then).
    pub fn redo(self: *Self) std.mem.Allocator.Error!bool {
        if (!self.canRedo()) return false;
        try self.history.reserveMove();
        const group = self.history.nextRedo().?;
        try self.reserve(group.insertedLength());
        for (group.edits.items) |step| self.splice(step.start, step.start + step.removed.len, step.inserted);
        self.caret = group.caret_after;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.revision = group.revision_after;
        self.history.didRedo();
        return true;
    }

    /// Opens one undo step for every edit until `endUndoGrouping` (replace
    /// all, indenting a block). Calls nest.
    ///
    /// - `self`: the field.
    pub fn beginUndoGrouping(self: *Self) void {
        self.history.beginUndoGrouping();
    }

    /// Closes the undo step `beginUndoGrouping` opened.
    ///
    /// - `self`: the field.
    pub fn endUndoGrouping(self: *Self) void {
        self.history.endUndoGrouping();
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

    /// The selected text, for copying. A secure field's is always empty, so
    /// no copy path (ziggui's keys and menu, or an app's own Edit menu) can
    /// hand a password to the clipboard.
    ///
    /// - `self`: the field.
    /// - Returns: a slice into the buffer, empty when nothing is selected or
    ///   the field is secure; borrowed, valid only until the next mutation.
    pub fn selectedText(self: *const Self) []const u8 {
        if (self.secure) return self.buffer.items[0..0];
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
        self.remove(range.start, range.end, .other);
        return true;
    }

    // --- editing -----------------------------------------------------------

    /// Inserts text at the caret, replacing the selection.
    ///
    /// - `self`: the field.
    /// - `string`: the text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn insert(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        // A line break is a step of its own, as in every editor.
        const kind: mod.TextEditKind = if (std.mem.findScalar(u8, string, '\n') != null) .other else .typing;
        const range = self.editRange();
        try self.edit(range.start, range.stop, string, kind);
    }

    /// Deletes the selection, or the codepoint before the caret.
    ///
    /// - `self`: the field.
    pub fn backspace(self: *Self) void {
        if (self.deleteSelection()) return;
        if (self.caret == 0) return;
        if (self.multiline and self.indentation.style == .spaces) {
            // In leading spaces, back to the previous stop, as code editors do.
            const line_start = mod.TextLines.init(self.buffer.items).lineStart(self.caret);
            const before = self.buffer.items[line_start..self.caret];
            if (before.len > 1 and std.mem.trim(u8, before, " ").len == 0) {
                const width = self.indentation.columns();
                const count = if (before.len % width == 0) width else before.len % width;
                return self.remove(self.caret - count, self.caret, .deletingBackward);
            }
        }
        const start = mod.TextLines.init(self.buffer.items).previousCodepointStart(self.caret);
        self.remove(start, self.caret, .deletingBackward);
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
        self.remove(self.caret, stop, .deletingForward);
    }

    /// Deletes the selection, or back to the start of the word before the
    /// caret, as macOS's ⌥⌫ does: the same stops as `moveWordLeft`. A secure
    /// field deletes back to its start, so the key never shows where its
    /// spaces are.
    ///
    /// - `self`: the field.
    pub fn deleteWordBackward(self: *Self) void {
        if (self.deleteSelection()) return;
        const start = if (self.secure) 0 else self.wordStartBefore(self.caret);
        if (start == self.caret) return;
        self.remove(start, self.caret, .other);
    }

    /// Deletes the selection, or on to the end of the word after the caret,
    /// as macOS's ⌥⌦ does: the same stops as `moveWordRight`. A secure field
    /// deletes on to its end.
    ///
    /// - `self`: the field.
    pub fn deleteWordForward(self: *Self) void {
        if (self.deleteSelection()) return;
        const stop = if (self.secure) self.buffer.items.len else self.wordEndAfter(self.caret);
        if (stop == self.caret) return;
        self.remove(self.caret, stop, .other);
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

    /// Moves the caret to the start of the word before it, as macOS's ⌥←
    /// does: past anything that is not a word character (spaces, line breaks,
    /// punctuation), then past the run of word characters (`CharClass.word`:
    /// letters, digits, `_`, anything non-ASCII) before that. A plain move
    /// starts from a selection's left edge. A secure field goes to its start,
    /// so the gesture never shows where its spaces are.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveWordLeft(self: *Self, extend: bool) void {
        if (self.secure) return self.moveToStart(extend);
        const from = if (extend) self.caret else if (self.selectionRange()) |range| range.start else self.caret;
        self.beginExtend(extend);
        self.caret = self.wordStartBefore(from);
        self.preferred_column = null;
    }

    /// Moves the caret to the end of the word after it, as macOS's ⌥→ does:
    /// past anything that is not a word character, then past the run of word
    /// characters after that. A plain move starts from a selection's right
    /// edge. A secure field goes to its end.
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveWordRight(self: *Self, extend: bool) void {
        if (self.secure) return self.moveToEnd(extend);
        const from = if (extend) self.caret else if (self.selectionRange()) |range| range.end else self.caret;
        self.beginExtend(extend);
        self.caret = self.wordEndAfter(from);
        self.preferred_column = null;
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

    /// Moves the caret to the text's start (⌘↑ on macOS).
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveToStart(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        self.caret = 0;
        self.preferred_column = null;
    }

    /// Moves the caret to the text's end (⌘↓ on macOS).
    ///
    /// - `self`: the field.
    /// - `extend`: Shift is held: grow the selection.
    pub fn moveToEnd(self: *Self, extend: bool) void {
        self.beginExtend(extend);
        self.caret = self.buffer.items.len;
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

    /// Makes room for `extra` more bytes. A secure field grows by copying and
    /// wiping the old buffer, so no copy of the text is freed unwiped.
    ///
    /// - `self`: the field.
    /// - `extra`: the bytes to make room for.
    /// - Returns: nothing; propagates allocation failure.
    fn reserve(self: *Self, extra: usize) std.mem.Allocator.Error!void {
        const needed = self.buffer.items.len + extra;
        if (needed <= self.buffer.capacity) return;
        if (!self.secure) return self.buffer.ensureTotalCapacity(self.allocator, needed);
        var grown: std.ArrayList(u8) = try .initCapacity(self.allocator, @max(needed, self.buffer.capacity * 2));
        grown.appendSliceAssumeCapacity(self.buffer.items);
        std.crypto.secureZero(u8, self.buffer.allocatedSlice());
        self.buffer.deinit(self.allocator);
        self.buffer = grown;
    }

    /// The lines a selection over more than one line touches (a selection
    /// ending at a line's start leaves that line out).
    ///
    /// - `self`: the field.
    /// - Returns: the first and last lines' starts, or null for no such selection.
    fn selectedLines(self: *const Self) ?LineSpan {
        const range = self.selectionRange() orelse return null;
        const lines = mod.TextLines.init(self.buffer.items);
        const first = lines.lineStart(range.start);
        const last = lines.lineStart(if (range.end > range.start and lines.lineStart(range.end) == range.end) range.end - 1 else range.end);
        if (first == last) return null;
        return .{ .first = first, .last = last };
    }

    /// Indents every line of a span that holds text by one level, as one
    /// undo step, keeping the selection over them.
    ///
    /// - `self`: the field.
    /// - `lines`: the lines.
    /// - Returns: nothing; propagates allocation failure.
    fn indentLines(self: *Self, lines: LineSpan) std.mem.Allocator.Error!void {
        const unit = if (self.indentation.style == .tabs) "\t" else spaces[0..self.indentation.columns()];
        const anchor = self.selection_anchor;
        const forward = if (anchor) |at| at <= self.caret else true;
        var start = if (anchor) |at| @min(at, self.caret) else self.caret;
        var stop = if (anchor) |at| @max(at, self.caret) else self.caret;
        const revision_before = self.revision;
        self.beginUndoGrouping();
        defer self.endUndoGrouping();
        var line_start = lines.last;
        while (true) {
            const text_lines = mod.TextLines.init(self.buffer.items);
            if (text_lines.lineEnd(line_start) > line_start) {
                if (start > line_start) start += unit.len;
                stop += unit.len;
                try self.edit(line_start, line_start, unit, .other);
            }
            if (line_start == lines.first) break;
            line_start = mod.TextLines.init(self.buffer.items).lineStart(line_start - 1);
        }
        if (self.revision != revision_before) self.restoreSelection(anchor != null, forward, start, stop);
    }

    /// Puts a selection back after the edits of an indent or outdent, and
    /// notes it as where the undo step left the field (call it only when the
    /// step made an edit, or it would rewrite the step before).
    ///
    /// - `self`: the field.
    /// - `selected`: whether there was a selection (else only the caret).
    /// - `forward`: whether the caret was at its end.
    /// - `start`: the selection's new first byte (or the caret's place).
    /// - `stop`: the selection's new end.
    fn restoreSelection(self: *Self, selected: bool, forward: bool, start: usize, stop: usize) void {
        const length = self.buffer.items.len;
        if (selected) {
            self.selection_anchor = @min(if (forward) start else stop, length);
            self.caret = @min(if (forward) stop else start, length);
        } else {
            self.selection_anchor = null;
            self.caret = @min(start, length);
        }
        self.history.settle(self.caret, self.revision);
    }

    /// A line's leading spaces and tabs.
    ///
    /// - `self`: the field.
    /// - `line_start`: the line's first byte.
    /// - Returns: a slice into the buffer.
    fn leadingWhitespace(self: *const Self, line_start: usize) []const u8 {
        const items = self.buffer.items;
        var at = line_start;
        while (at < items.len and (items[at] == ' ' or items[at] == '\t')) at += 1;
        return items[line_start..at];
    }

    /// The column a byte sits at on its line, tabs stopping at the
    /// indentation's width and every other codepoint one column.
    ///
    /// - `self`: the field.
    /// - `index`: the byte.
    /// - Returns: its column, from 0.
    fn visualColumn(self: *const Self, index: usize) usize {
        const lines = mod.TextLines.init(self.buffer.items);
        const width = self.indentation.columns();
        var column: usize = 0;
        var at = lines.lineStart(index);
        while (at < index) : (at = lines.nextCodepointEnd(at)) {
            column = if (self.buffer.items[at] == '\t') (column / width + 1) * width else column + 1;
        }
        return column;
    }

    /// The range typing or pasting replaces: the selection, else the caret.
    ///
    /// - `self`: the field.
    /// - Returns: the range's first byte and the byte just past it.
    fn editRange(self: *const Self) struct { start: usize, stop: usize } {
        if (self.selectionRange()) |range| return .{ .start = range.start, .stop = range.end };
        const at = @min(self.caret, self.buffer.items.len);
        return .{ .start = at, .stop = at };
    }

    /// Replaces a byte range with text, recording it for undo: the one
    /// mutation every edit makes. The caret lands after the text and any
    /// selection goes. A history that cannot record is dropped (logged),
    /// never the edit.
    ///
    /// - `self`: the field.
    /// - `start`: the range's first byte.
    /// - `stop`: the byte just past it.
    /// - `string`: the text, copied.
    /// - `kind`: what the edit is, for joining undo steps.
    /// - Returns: nothing; propagates allocation failure (nothing changed then).
    fn edit(self: *Self, start: usize, stop: usize, string: []const u8, kind: mod.TextEditKind) std.mem.Allocator.Error!void {
        // Text from the field's own buffer (`replaceRange(0, 3, field.text()[5..])`)
        // would move as the buffer grows and overlap the splice: copy it first.
        const held = self.buffer.allocatedSlice();
        const address = @intFromPtr(string.ptr);
        if (string.len > 0 and address >= @intFromPtr(held.ptr) and address < @intFromPtr(held.ptr) + held.len) {
            const copy = try self.allocator.dupe(u8, string);
            defer {
                std.crypto.secureZero(u8, copy);
                self.allocator.free(copy);
            }
            return self.edit(start, stop, copy, kind);
        }
        const first = @min(start, self.buffer.items.len);
        const last = @min(@max(stop, first), self.buffer.items.len);
        if (string.len > last - first) try self.reserve(string.len - (last - first));
        self.apply(first, last, string, kind);
    }

    /// Removes a byte range, recording it for undo; a removal needs no room,
    /// so it cannot fail.
    ///
    /// - `self`: the field.
    /// - `start`: the range's first byte.
    /// - `stop`: the byte just past it.
    /// - `kind`: what the edit is, for joining undo steps.
    fn remove(self: *Self, start: usize, stop: usize, kind: mod.TextEditKind) void {
        const first = @min(start, self.buffer.items.len);
        self.apply(first, @min(@max(stop, first), self.buffer.items.len), "", kind);
    }

    /// Makes an edit whose room is already reserved: records it, splices
    /// it in, moves the caret after it and gives the text a new revision.
    ///
    /// - `self`: the field.
    /// - `first`: the range's first byte, within the text.
    /// - `last`: the byte just past it, within the text.
    /// - `string`: the text, copied.
    /// - `kind`: what the edit is, for joining undo steps.
    fn apply(self: *Self, first: usize, last: usize, string: []const u8, kind: mod.TextEditKind) void {
        const recorded = self.recordEdit(first, last, string, kind);
        self.splice(first, last, string);
        self.caret = first + string.len;
        self.selection_anchor = null;
        self.preferred_column = null;
        self.newRevision();
        if (recorded) self.history.settle(self.caret, self.revision);
    }

    /// Hands an edit about to be made to the history, unless the field is
    /// secure (whose history is wiped instead).
    ///
    /// - `self`: the field.
    /// - `start`: the range's first byte.
    /// - `stop`: the byte just past it.
    /// - `string`: the text replacing it.
    /// - `kind`: what the edit is.
    /// - Returns: whether it was recorded.
    fn recordEdit(self: *Self, start: usize, stop: usize, string: []const u8, kind: mod.TextEditKind) bool {
        if (self.secure) {
            self.history.clear();
            return false;
        }
        self.history.record(.{
            .start = start,
            .removed = self.buffer.items[start..stop],
            .inserted = string,
            .kind = kind,
            .caret_before = self.caret,
            .anchor_before = self.selection_anchor,
            .revision_before = self.revision,
        }, mod.FrameClock.shared().time()) catch |err| {
            log.warn("undo history dropped: {s}", .{@errorName(err)});
            self.history.clear();
            return false;
        };
        return true;
    }

    /// Replaces a byte range in the buffer, recording nothing; room for the
    /// text is already reserved (`reserve`).
    ///
    /// - `self`: the field.
    /// - `start`: the range's first byte.
    /// - `stop`: the byte just past it.
    /// - `string`: the text.
    fn splice(self: *Self, start: usize, stop: usize, string: []const u8) void {
        self.buffer.replaceRangeAssumeCapacity(start, stop - start, string);
    }

    /// Gives `revision` a value it never had.
    ///
    /// - `self`: the field.
    fn newRevision(self: *Self) void {
        self.revision = last_revision.fetchAdd(1, .monotonic) + 1;
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

    /// Where a word starts before a byte: back over every codepoint that is
    /// not a word character, then over the word characters before them.
    ///
    /// - `self`: the field.
    /// - `index`: the byte to look back from.
    /// - Returns: the word's first byte, or 0 when no word lies before.
    fn wordStartBefore(self: *const Self, index: usize) usize {
        const items = self.buffer.items;
        const lines = mod.TextLines.init(items);
        var at = @min(index, items.len);
        while (at > 0) {
            const previous = lines.previousCodepointStart(at);
            if (CharClass.of(items[previous]) == .word) break;
            at = previous;
        }
        while (at > 0) {
            const previous = lines.previousCodepointStart(at);
            if (CharClass.of(items[previous]) != .word) break;
            at = previous;
        }
        return at;
    }

    /// Where a word ends after a byte: on over every codepoint that is not a
    /// word character, then over the word characters after them.
    ///
    /// - `self`: the field.
    /// - `index`: the byte to look on from.
    /// - Returns: the byte just past the word, or the text's end when no word lies after.
    fn wordEndAfter(self: *const Self, index: usize) usize {
        const items = self.buffer.items;
        const lines = mod.TextLines.init(items);
        var at = @min(index, items.len);
        while (at < items.len and CharClass.of(items[at]) != .word) at = lines.nextCodepointEnd(at);
        while (at < items.len and CharClass.of(items[at]) == .word) at = lines.nextCodepointEnd(at);
        return at;
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

test "TextFieldState: to the text's start and end, Shift selecting" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello\nworld");
    field.caret = 3;
    field.moveToEnd(false);
    try std.testing.expectEqual(@as(usize, 11), field.caret);
    try std.testing.expect(!field.hasSelection());
    field.moveToStart(true);
    try std.testing.expectEqual(@as(usize, 0), field.caret);
    try std.testing.expectEqualStrings("hello\nworld", field.selectedText());
    field.moveToEnd(false);
    try std.testing.expect(!field.hasSelection());
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

test "TextFieldState: a secure field keeps its text as it grows" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.secure = true;
    try field.setText("ab");
    for (0..40) |_| try field.insert("c");
    try std.testing.expectEqual(@as(usize, 42), field.text().len);
    try std.testing.expectEqualStrings("abcc", field.text()[0..4]);
    try field.setText("short");
    try std.testing.expectEqualStrings("short", field.text());
}

test "TextFieldState: a secure field hands out no selection, and setText wipes deleted bytes" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.secure = true;
    try field.setText("hunter2");
    field.selectAll();
    try std.testing.expectEqualStrings("", field.selectedText());
    // "er2" deleted, then the field cleared: nothing of it is left in the buffer.
    field.caret = 4;
    field.selection_anchor = 7;
    _ = field.deleteSelection();
    try field.setText("");
    const memory = field.buffer.allocatedSlice();
    try std.testing.expect(std.mem.find(u8, memory, "hunt") == null);
    try std.testing.expect(std.mem.find(u8, memory, "er2") == null);
}

test "text field state wipes to empty, the old bytes zeroed" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("secret");
    const held = field.buffer.allocatedSlice();
    field.wipe();
    try std.testing.expectEqualStrings("", field.text());
    try std.testing.expectEqual(@as(usize, 0), field.caret);
    for (held) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "TextFieldState: word moves skip spaces and punctuation, then cross one word" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("  let snake_case = 42, café;\nnext");
    field.caret = 0;
    // Right: past the leading spaces to the end of each word in turn; `_`,
    // digits and non-ASCII letters belong to the word, punctuation does not.
    const ends = [_][]const u8{ "  let", "  let snake_case", "  let snake_case = 42", "  let snake_case = 42, café", "  let snake_case = 42, café;\nnext" };
    for (ends) |prefix| {
        field.moveWordRight(false);
        try std.testing.expectEqual(prefix.len, field.caret);
    }
    // At the end it stays there.
    field.moveWordRight(false);
    try std.testing.expectEqual(field.text().len, field.caret);
    // Left: back to the start of each word, across the line break.
    const starts = [_]usize{ "  let snake_case = 42, café;\n".len, "  let snake_case = 42, ".len, "  let snake_case = ".len, "  let ".len, "  ".len, 0 };
    for (starts) |start| {
        field.moveWordLeft(false);
        try std.testing.expectEqual(start, field.caret);
    }
}

test "TextFieldState: word moves extend with Shift and start from a selection's edge" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("one two three");
    field.caret = 0;
    field.moveWordRight(true);
    field.moveWordRight(true);
    try std.testing.expectEqualStrings("one two", field.selectedText());
    // A plain move leaves the selection from its right edge.
    field.moveWordRight(false);
    try std.testing.expect(field.selection_anchor == null);
    try std.testing.expectEqual("one two three".len, field.caret);
    field.selection_anchor = 4;
    field.caret = 7; // "two" selected
    field.moveWordLeft(false);
    try std.testing.expectEqual(@as(usize, 0), field.caret);
}

test "TextFieldState: a secure field's word moves go to its ends" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.secure = true;
    try field.setText("pass word");
    field.caret = 2;
    field.moveWordRight(false);
    try std.testing.expectEqual("pass word".len, field.caret);
    field.moveWordLeft(false);
    try std.testing.expectEqual(@as(usize, 0), field.caret);
}

test "TextFieldState: word deletes remove back to a word's start or on to its end" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("call(snake_case, café)");
    // Back from the end: the ")" and "café", then ", " and "snake_case".
    field.caret = field.text().len;
    field.deleteWordBackward();
    try std.testing.expectEqualStrings("call(snake_case, ", field.text());
    field.deleteWordBackward();
    try std.testing.expectEqualStrings("call(", field.text());
    try std.testing.expectEqual("call(".len, field.caret);
    // On from the start: "call", then "(" and "snake_case".
    try field.setText("call(snake_case, café)");
    field.caret = 0;
    field.deleteWordForward();
    try std.testing.expectEqualStrings("(snake_case, café)", field.text());
    try std.testing.expectEqual(@as(usize, 0), field.caret);
    field.deleteWordForward();
    try std.testing.expectEqualStrings(", café)", field.text());
    // At the ends there is nothing to delete.
    field.caret = 0;
    field.deleteWordBackward();
    try std.testing.expectEqualStrings(", café)", field.text());
    field.caret = field.text().len;
    field.deleteWordForward();
    try std.testing.expectEqualStrings(", café)", field.text());
}

test "TextFieldState: word deletes take a selection first, and clear a secure field's side" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("one two three");
    field.selection_anchor = 4;
    field.caret = 7;
    field.deleteWordBackward();
    try std.testing.expectEqualStrings("one  three", field.text());

    field.secure = true;
    try field.setText("pass word");
    field.caret = 6;
    field.deleteWordBackward();
    try std.testing.expectEqualStrings("ord", field.text());
    field.caret = 1;
    field.deleteWordForward();
    try std.testing.expectEqualStrings("o", field.text());
}

test "TextFieldState: a typing run undoes as one step and redoes" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    for ("abc") |byte| try field.insert(&.{byte});
    try field.insert("\n"); // a line break is a step of its own
    for ("de") |byte| try field.insert(&.{byte});
    try std.testing.expect(try field.undo());
    try std.testing.expectEqualStrings("abc\n", field.text());
    try std.testing.expect(try field.undo());
    try std.testing.expectEqualStrings("abc", field.text());
    try std.testing.expect(try field.undo());
    try std.testing.expectEqualStrings("", field.text());
    try std.testing.expect(!try field.undo());
    try std.testing.expect(try field.redo());
    try std.testing.expectEqualStrings("abc", field.text());
    try std.testing.expectEqual(@as(usize, 3), field.caret);
    // A new edit drops what was left to redo.
    try field.insert("!");
    try std.testing.expect(!field.canRedo());
}

test "TextFieldState: an undo back to a saved revision reads clean, and a new edit never reuses one" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("saved");
    const saved = field.revision;
    try field.insert("!");
    const edited = field.revision;
    try std.testing.expect(edited != saved);
    _ = try field.undo();
    try std.testing.expectEqual(saved, field.revision);
    _ = try field.redo();
    try std.testing.expectEqual(edited, field.revision);
    _ = try field.undo();
    try field.insert("?");
    try std.testing.expect(field.revision != saved and field.revision != edited);
}

test "TextFieldState: deletes undo with their selection, and runs of Backspace join" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello world");
    field.selection_anchor = 0;
    field.caret = 6; // "hello " selected
    field.backspace();
    try std.testing.expectEqualStrings("world", field.text());
    field.caret = 5;
    field.backspace();
    field.backspace();
    try std.testing.expectEqualStrings("wor", field.text());
    _ = try field.undo(); // both Backspaces
    try std.testing.expectEqualStrings("world", field.text());
    _ = try field.undo(); // the selection's delete, the selection back
    try std.testing.expectEqualStrings("hello world", field.text());
    try std.testing.expectEqualStrings("hello ", field.selectedText());
    try std.testing.expect(!field.canUndo()); // setText left nothing before
}

test "TextFieldState: an edit group undoes as one step, and a secure field keeps no history" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("a b c");
    field.beginUndoGrouping();
    try field.replaceRange(4, 5, "C");
    try field.replaceRange(0, 1, "A");
    field.endUndoGrouping();
    try std.testing.expectEqualStrings("A b C", field.text());
    _ = try field.undo();
    try std.testing.expectEqualStrings("a b c", field.text());

    var secret = TextFieldState.init(std.testing.allocator);
    defer secret.deinit();
    secret.secure = true;
    try secret.insert("hunter2");
    try std.testing.expect(!secret.canUndo());
    try std.testing.expect(!try secret.undo());
}

test "TextFieldState: a paste is a step of its own" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.insert("a");
    try field.paste("bc");
    try field.insert("d");
    _ = try field.undo();
    try std.testing.expectEqualStrings("abc", field.text());
    _ = try field.undo();
    try std.testing.expectEqualStrings("a", field.text());
}

test "TextFieldState: Tab inserts to the next stop, and Backspace in leading spaces goes back to one" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.multiline = true;
    try field.insert("ab");
    try field.indent();
    try std.testing.expectEqualStrings("ab  ", field.text());
    try field.setText("");
    try field.indent();
    try field.indent();
    try std.testing.expectEqualStrings("        ", field.text());
    field.backspace();
    try std.testing.expectEqualStrings("    ", field.text());
    field.indentation = .{ .style = .tabs };
    try field.indent();
    try std.testing.expectEqualStrings("    \t", field.text());
}

test "TextFieldState: Tab and Shift-Tab indent and outdent the selected lines as one step" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.multiline = true;
    try field.setText("one\n\ntwo\nthree");
    field.selection_anchor = 1;
    field.caret = 10; // "ne\n\ntwo\nt": the empty line stays empty
    try field.indent();
    try std.testing.expectEqualStrings("    one\n\n    two\n    three", field.text());
    try std.testing.expectEqualStrings("ne\n\n    two\n    t", field.selectedText());
    try field.outdent();
    try std.testing.expectEqualStrings("one\n\ntwo\nthree", field.text());
    try std.testing.expectEqualStrings("ne\n\ntwo\nt", field.selectedText());
    _ = try field.undo();
    try std.testing.expectEqualStrings("    one\n\n    two\n    three", field.text());
    _ = try field.undo();
    try std.testing.expectEqualStrings("one\n\ntwo\nthree", field.text());
    // A selection ending at a line's start leaves that line alone.
    field.selection_anchor = 0;
    field.caret = 5;
    try field.indent();
    try std.testing.expectEqualStrings("    one\n\ntwo\nthree", field.text());
    // Shift-Tab with no selection outdents the caret's line, a tab at a time.
    try field.setText("\t\tx");
    try field.outdent();
    try std.testing.expectEqualStrings("\tx", field.text());
}

test "TextFieldState: converting indentation retabs every line as one step" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("a\n    b\n        c\n\td");
    try field.convertIndentation(.{ .style = .tabs, .width = 4 });
    try std.testing.expectEqualStrings("a\n\tb\n\t\tc\n\td", field.text());
    try std.testing.expectEqual(mod.IndentationStyle.tabs, field.indentation.style);
    _ = try field.undo();
    try std.testing.expectEqualStrings("a\n    b\n        c\n\td", field.text());
}

test "TextFieldState: a document loads with its ending and indentation, and saves with its ending" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.loadDocument("a {\r\n  b\r\n}\r\n");
    try std.testing.expectEqualStrings("a {\n  b\n}\n", field.text());
    try std.testing.expectEqual(mod.LineEnding.crlf, field.line_ending);
    try std.testing.expectEqual(@as(u8, 2), field.indentation.width);
    const encoded = try field.encodedAlloc(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("a {\r\n  b\r\n}\r\n", encoded);
    const loaded = field.revision;
    field.setLineEnding(.lf);
    try std.testing.expect(field.revision != loaded);
    // A paste's CRLFs land as LFs in an editor.
    field.multiline = true;
    try field.paste("x\r\ny");
    try std.testing.expectEqualStrings("x\ny", field.text()[0..3]);
}

test "TextFieldState: an indent, outdent or conversion that changes nothing leaves the last step alone" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    field.multiline = true;
    try field.setText("a\n\n\nb");
    field.caret = 1;
    try field.insert("x"); // "ax\n\n\nb", the step leaving the caret at 2
    field.caret = 0;
    try field.outdent(); // no indentation to take
    try field.convertIndentation(.{ .style = .tabs }); // none to convert
    field.selection_anchor = 3;
    field.caret = 5; // the two empty lines, which take no indentation
    try field.indent();
    try std.testing.expectEqualStrings("ax\n\n\nb", field.text());
    try std.testing.expectEqual(@as(usize, 1), field.history.undo_stack.items.len);
    try std.testing.expectEqual(@as(usize, 2), field.history.nextUndo().?.caret_after);
}

test "TextFieldState: revisions never repeat across fields" {
    var first = TextFieldState.init(std.testing.allocator);
    defer first.deinit();
    var second = TextFieldState.init(std.testing.allocator);
    defer second.deinit();
    try first.insert("a");
    try second.insert("a");
    try std.testing.expect(first.revision != second.revision);
}

test "TextFieldState: text from the field's own buffer replaces a range safely" {
    var field = TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("abcdef");
    try field.replaceRange(0, 1, field.text()[1..]); // grows the buffer from itself
    try std.testing.expectEqualStrings("bcdefbcdef", field.text());
    try field.setTextUndoable(field.text()[0..3]);
    try std.testing.expectEqualStrings("bcd", field.text());
}
