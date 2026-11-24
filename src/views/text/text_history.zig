//! The undo and redo record of one text field: each edit's removed and
//! inserted bytes, grouped into the steps ⌘Z takes back. `TextFieldState`
//! records into it and applies its groups; nothing here touches a buffer.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_history);

/// What an edit was, which decides whether it joins the group before it.
pub const TextEditKind = enum {
    const Self = @This();

    /// Text typed at the caret (no line break): a run of it is one step.
    typing,

    /// A codepoint deleted before the caret (Backspace): a run of it is one step.
    deletingBackward,

    /// A codepoint deleted after the caret (Delete): a run of it is one step.
    deletingForward,

    /// Anything else (a paste, a cut, a line break, a replace): a step of its own.
    other,
};

/// One edit: the bytes at `start` that were `removed` and what was `inserted` in their place.
pub const TextEdit = struct {
    const Self = @This();

    /// The byte the edit starts at.
    start: usize,

    /// The bytes it removed, owned.
    removed: []u8,

    /// The bytes it inserted, owned.
    inserted: []u8,

    /// Zeroes and frees the edit's bytes: an editor may hold a secret (a
    /// stored value being edited), and its copies leave no trace either.
    ///
    /// - `self`: the edit.
    /// - `allocator`: what the bytes came from.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        std.crypto.secureZero(u8, self.removed);
        std.crypto.secureZero(u8, self.inserted);
        allocator.free(self.removed);
        allocator.free(self.inserted);
    }
};

/// One undo step: its edits in the order they were made, and the field's
/// caret, selection and revision either side of them.
pub const TextEditGroup = struct {
    const Self = @This();

    /// The edits, oldest first.
    edits: std.ArrayList(TextEdit) = .empty,

    /// The kind of the edits it holds (`other` for a group `beginUndoGrouping` opened).
    kind: TextEditKind,

    /// The caret before the first edit.
    caret_before: usize,

    /// The selection anchor before the first edit.
    anchor_before: ?usize,

    /// The field's revision before the first edit.
    revision_before: u64,

    /// The caret after the last edit.
    caret_after: usize = 0,

    /// The field's revision after the last edit.
    revision_after: u64 = 0,

    /// The frame clock's time at the last edit, in ms.
    time_ms: u64,

    /// Frees the group's edits.
    ///
    /// - `self`: the group.
    /// - `allocator`: what the edits came from.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.edits.items) |*edit| edit.deinit(allocator);
        self.edits.deinit(allocator);
    }

    /// How many bytes undoing the group puts back.
    ///
    /// - `self`: the group.
    /// - Returns: the removed bytes' total.
    pub fn removedLength(self: *const Self) usize {
        var total: usize = 0;
        for (self.edits.items) |edit| total += edit.removed.len;
        return total;
    }

    /// How many bytes redoing the group puts back.
    ///
    /// - `self`: the group.
    /// - Returns: the inserted bytes' total.
    pub fn insertedLength(self: *const Self) usize {
        var total: usize = 0;
        for (self.edits.items) |edit| total += edit.inserted.len;
        return total;
    }
};

/// An edit as `TextFieldState` reports it, before it is applied.
pub const TextEditRecord = struct {
    const Self = @This();

    /// The byte the edit starts at.
    start: usize,

    /// The bytes it removes, borrowed (copied by `record`).
    removed: []const u8,

    /// The bytes it inserts, borrowed (copied by `record`).
    inserted: []const u8,

    /// What it is.
    kind: TextEditKind,

    /// The caret before it.
    caret_before: usize,

    /// The selection anchor before it.
    anchor_before: ?usize,

    /// The field's revision before it.
    revision_before: u64,
};

/// A field's undo and redo stacks. Typing, Backspace and Delete runs join
/// one step while the caret stays where the last edit left it and no more
/// than `coalesce_ms` pass between them; anything else is a step of its own,
/// and `beginUndoGrouping`/`endUndoGrouping` make several edits one step. At most
/// `levels_of_undo` steps are kept, the oldest dropped first.
pub const TextHistory = struct {
    const Self = @This();

    /// Where the steps and their bytes are kept (the field's allocator).
    allocator: std.mem.Allocator,

    /// The steps ⌘Z takes back, oldest first.
    undo_stack: std.ArrayList(TextEditGroup) = .empty,

    /// The steps ⇧⌘Z puts back, the next one last.
    redo_stack: std.ArrayList(TextEditGroup) = .empty,

    /// The most steps kept.
    levels_of_undo: usize = 1000,

    /// The longest pause, in ms, inside one typing step.
    coalesce_ms: u64 = 1000,

    /// How deep `beginUndoGrouping` calls nest.
    grouping_level: u32 = 0,

    /// Whether the next edit opens a new step whatever it is.
    sealed: bool = false,

    /// An empty history.
    ///
    /// - `allocator`: where the steps and their bytes are kept.
    /// - Returns: the history.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees every step.
    ///
    /// - `self`: the history.
    pub fn deinit(self: *Self) void {
        self.clear();
        self.undo_stack.deinit(self.allocator);
        self.redo_stack.deinit(self.allocator);
    }

    /// Forgets every step, keeping the stacks' memory.
    ///
    /// - `self`: the history.
    pub fn clear(self: *Self) void {
        for (self.undo_stack.items) |*group| group.deinit(self.allocator);
        for (self.redo_stack.items) |*group| group.deinit(self.allocator);
        self.undo_stack.clearRetainingCapacity();
        self.redo_stack.clearRetainingCapacity();
        self.sealed = true;
    }

    /// Whether there is a step to undo.
    ///
    /// - `self`: the history.
    /// - Returns: true when the undo stack holds one.
    pub fn canUndo(self: *const Self) bool {
        return self.undo_stack.items.len > 0;
    }

    /// Whether there is a step to redo.
    ///
    /// - `self`: the history.
    /// - Returns: true when the redo stack holds one.
    pub fn canRedo(self: *const Self) bool {
        return self.redo_stack.items.len > 0;
    }

    /// Opens a step that every edit until the matching `endUndoGrouping` joins
    /// (replace all, indenting a block). Calls nest.
    ///
    /// - `self`: the history.
    pub fn beginUndoGrouping(self: *Self) void {
        if (self.grouping_level == 0) self.sealed = true;
        self.grouping_level += 1;
    }

    /// Closes the step `beginUndoGrouping` opened, once the outermost call ends.
    ///
    /// - `self`: the history.
    pub fn endUndoGrouping(self: *Self) void {
        if (self.grouping_level == 0) return;
        self.grouping_level -= 1;
        if (self.grouping_level == 0) self.sealed = true;
    }

    /// Makes the next edit open a step of its own.
    ///
    /// - `self`: the history.
    pub fn seal(self: *Self) void {
        self.sealed = true;
    }

    /// Records an edit before it is applied: it joins the last step when it
    /// continues it, else opens a new one (dropping the redo stack and, past
    /// `levels_of_undo`, the oldest step). `settle` finishes it once applied.
    ///
    /// - `self`: the history.
    /// - `edit`: the edit.
    /// - `now_ms`: the frame clock's time.
    /// - Returns: nothing; propagates allocation failure (nothing recorded then).
    pub fn record(self: *Self, edit: TextEditRecord, now_ms: u64) std.mem.Allocator.Error!void {
        const allocator = self.allocator;
        const removed = try allocator.dupe(u8, edit.removed);
        errdefer {
            std.crypto.secureZero(u8, removed);
            allocator.free(removed);
        }
        const inserted = try allocator.dupe(u8, edit.inserted);
        errdefer {
            std.crypto.secureZero(u8, inserted);
            allocator.free(inserted);
        }
        const joins = self.continuesLast(edit, now_ms);
        if (!joins) {
            try self.undo_stack.ensureUnusedCapacity(allocator, 1);
            self.undo_stack.appendAssumeCapacity(.{
                .kind = if (self.grouping_level > 0) .other else edit.kind,
                .caret_before = edit.caret_before,
                .anchor_before = edit.anchor_before,
                .revision_before = edit.revision_before,
                .time_ms = now_ms,
            });
        }
        const group = &self.undo_stack.items[self.undo_stack.items.len - 1];
        group.edits.append(allocator, .{ .start = edit.start, .removed = removed, .inserted = inserted }) catch |err| {
            if (!joins) {
                var dropped = self.undo_stack.pop().?;
                dropped.deinit(allocator);
            }
            return err;
        };
        group.time_ms = now_ms;
        self.sealed = false;
        if (!joins) {
            for (self.redo_stack.items) |*stale| stale.deinit(allocator);
            self.redo_stack.clearRetainingCapacity();
            while (self.undo_stack.items.len > @max(self.levels_of_undo, 1)) {
                var oldest = self.undo_stack.orderedRemove(0);
                oldest.deinit(allocator);
            }
        }
    }

    /// Notes where the edit `record` took left the field.
    ///
    /// - `self`: the history.
    /// - `caret`: the caret after it.
    /// - `revision`: the field's revision after it.
    pub fn settle(self: *Self, caret: usize, revision: u64) void {
        if (self.undo_stack.items.len == 0) return;
        const group = &self.undo_stack.items[self.undo_stack.items.len - 1];
        group.caret_after = caret;
        group.revision_after = revision;
    }

    /// The step `undo` takes back next.
    ///
    /// - `self`: the history.
    /// - Returns: the newest undo step, or null.
    pub fn nextUndo(self: *const Self) ?*const TextEditGroup {
        if (self.undo_stack.items.len == 0) return null;
        return &self.undo_stack.items[self.undo_stack.items.len - 1];
    }

    /// The step `redo` puts back next.
    ///
    /// - `self`: the history.
    /// - Returns: the newest redo step, or null.
    pub fn nextRedo(self: *const Self) ?*const TextEditGroup {
        if (self.redo_stack.items.len == 0) return null;
        return &self.redo_stack.items[self.redo_stack.items.len - 1];
    }

    /// Makes room to move a step between the stacks, so the move after an
    /// undo or redo is applied cannot fail.
    ///
    /// - `self`: the history.
    /// - Returns: nothing; propagates allocation failure.
    pub fn reserveMove(self: *Self) std.mem.Allocator.Error!void {
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        try self.redo_stack.ensureUnusedCapacity(self.allocator, 1);
    }

    /// Moves the step just undone onto the redo stack (after `reserveMove`).
    ///
    /// - `self`: the history.
    pub fn didUndo(self: *Self) void {
        const group = self.undo_stack.pop() orelse return;
        self.redo_stack.appendAssumeCapacity(group);
        self.sealed = true;
    }

    /// Moves the step just redone back onto the undo stack (after `reserveMove`).
    ///
    /// - `self`: the history.
    pub fn didRedo(self: *Self) void {
        const group = self.redo_stack.pop() orelse return;
        self.undo_stack.appendAssumeCapacity(group);
        self.sealed = true;
    }

    /// Whether an edit continues the last step.
    ///
    /// - `self`: the history.
    /// - `edit`: the edit.
    /// - `now_ms`: the frame clock's time.
    /// - Returns: true when it joins that step.
    fn continuesLast(self: *const Self, edit: TextEditRecord, now_ms: u64) bool {
        const last = self.nextUndo() orelse return false;
        if (self.sealed) return false;
        // Inside `beginUndoGrouping` everything joins the step it opened.
        if (self.grouping_level > 0) return true;
        if (edit.kind == .other or last.kind != edit.kind) return false;
        if (edit.caret_before != last.caret_after) return false;
        if (edit.anchor_before) |anchor| if (anchor != edit.caret_before) return false;
        if (now_ms > last.time_ms and now_ms - last.time_ms > self.coalesce_ms) return false;
        return switch (edit.kind) {
            .typing => edit.removed.len == 0,
            .deletingBackward, .deletingForward => edit.inserted.len == 0,
            .other => false,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "history: a typing run is one step, a pause or a moved caret starts another" {
    const allocator = std.testing.allocator;
    var history = TextHistory.init(allocator);
    defer history.deinit();
    try history.record(.{ .start = 0, .removed = "", .inserted = "a", .kind = .typing, .caret_before = 0, .anchor_before = null, .revision_before = 0 }, 100);
    history.settle(1, 1);
    try history.record(.{ .start = 1, .removed = "", .inserted = "b", .kind = .typing, .caret_before = 1, .anchor_before = null, .revision_before = 1 }, 200);
    history.settle(2, 2);
    try std.testing.expectEqual(@as(usize, 1), history.undo_stack.items.len);
    // A pause past `coalesce_ms`.
    try history.record(.{ .start = 2, .removed = "", .inserted = "c", .kind = .typing, .caret_before = 2, .anchor_before = null, .revision_before = 2 }, 1500);
    history.settle(3, 3);
    try std.testing.expectEqual(@as(usize, 2), history.undo_stack.items.len);
    // The caret moved away first.
    try history.record(.{ .start = 0, .removed = "", .inserted = "d", .kind = .typing, .caret_before = 0, .anchor_before = null, .revision_before = 3 }, 1500);
    history.settle(1, 4);
    try std.testing.expectEqual(@as(usize, 3), history.undo_stack.items.len);
    // Another kind.
    try history.record(.{ .start = 0, .removed = "d", .inserted = "", .kind = .deletingBackward, .caret_before = 1, .anchor_before = null, .revision_before = 4 }, 1500);
    history.settle(0, 5);
    try std.testing.expectEqual(@as(usize, 4), history.undo_stack.items.len);
}

test "history: beginUndoGrouping joins every edit, and the cap drops the oldest step" {
    const allocator = std.testing.allocator;
    var history = TextHistory.init(allocator);
    defer history.deinit();
    history.levels_of_undo = 3;
    history.beginUndoGrouping();
    for (0..4) |index| {
        try history.record(.{ .start = index, .removed = "", .inserted = "x", .kind = .other, .caret_before = index, .anchor_before = null, .revision_before = index }, 0);
        history.settle(index + 1, index + 1);
    }
    history.endUndoGrouping();
    try std.testing.expectEqual(@as(usize, 1), history.undo_stack.items.len);
    try std.testing.expectEqual(@as(usize, 4), history.nextUndo().?.edits.items.len);
    for (0..5) |index| {
        try history.record(.{ .start = 0, .removed = "", .inserted = "y", .kind = .other, .caret_before = 0, .anchor_before = null, .revision_before = index }, 0);
    }
    try std.testing.expectEqual(@as(usize, 3), history.undo_stack.items.len);
    try std.testing.expectEqual(@as(usize, 1), history.undo_stack.items[0].edits.items.len);
}
