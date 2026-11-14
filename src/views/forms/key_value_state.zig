//! The rows of a `KeyValueEditor`: name and value fields that keep their
//! addresses while rows come and go.

const std = @import("std");
const log = std.log.scoped(.ziggui_key_value_state);
const mod = @import("module.zig");

/// One row of a `KeyValueEditor`: its name field and its value field.
/// Heap-allocated by `KeyValueState`, so the fields keep their addresses
/// (the focus and the pointer hold them across frames).
pub const KeyValueRow = struct {
    const Self = @This();

    /// The name field.
    key: mod.TextFieldState,

    /// The value field.
    value: mod.TextFieldState,

    /// An empty row.
    ///
    /// - `allocator`: where the fields keep their text.
    /// - Returns: the row.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .key = mod.TextFieldState.init(allocator), .value = mod.TextFieldState.init(allocator) };
        return self;
    }

    /// Frees both fields' text; the focus and the pointer forget them.
    ///
    /// - `self`: the row.
    pub fn deinit(self: *Self) void {
        self.value.deinit();
        self.key.deinit();
    }
};

/// What a `KeyValueEditor` edits: name/value rows (headers, environment
/// variables), app-owned like a `TextFieldState` so edits survive frames.
pub const KeyValueState = struct {
    const Self = @This();

    /// The rows, top to bottom, each on the heap.
    rows: std.ArrayList(*mod.KeyValueRow) = .empty,

    /// Where the rows and their text live.
    allocator: std.mem.Allocator,

    /// No rows.
    ///
    /// - `allocator`: where the rows and their text live.
    /// - Returns: the state.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees every row.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        self.freeRows(self.rows.items);
        self.rows.deinit(self.allocator);
    }

    /// Replaces every row with `replacement`, in order. On failure the rows
    /// are as they were.
    ///
    /// - `self`: the state.
    /// - `replacement`: each row's name and value.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setPairs(self: *Self, replacement: []const [2][]const u8) std.mem.Allocator.Error!void {
        var fresh: std.ArrayList(*mod.KeyValueRow) = .empty;
        errdefer {
            self.freeRows(fresh.items);
            fresh.deinit(self.allocator);
        }
        try fresh.ensureTotalCapacity(self.allocator, replacement.len);
        for (replacement) |pair| {
            const row = try self.allocator.create(mod.KeyValueRow);
            row.* = mod.KeyValueRow.init(self.allocator);
            fresh.appendAssumeCapacity(row);
            try row.key.setText(pair[0]);
            try row.value.setText(pair[1]);
        }
        self.freeRows(self.rows.items);
        self.rows.deinit(self.allocator);
        self.rows = fresh;
    }

    /// The rows' names and values as they read now, skipping rows whose name
    /// and value are both empty.
    ///
    /// - `self`: the state.
    /// - `arena`: where the slice and copies of the texts are made.
    /// - Returns: the pairs; propagates allocation failure.
    pub fn pairs(self: *const Self, arena: std.mem.Allocator) std.mem.Allocator.Error![]const [2][]const u8 {
        var list: std.ArrayList([2][]const u8) = .empty;
        try list.ensureTotalCapacity(arena, self.rows.items.len);
        for (self.rows.items) |row| {
            const key = row.key.text();
            const value = row.value.text();
            if (key.len == 0 and value.len == 0) continue;
            list.appendAssumeCapacity(.{ try arena.dupe(u8, key), try arena.dupe(u8, value) });
        }
        return list.items;
    }

    /// Appends an empty row and focuses its name field.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; propagates allocation failure.
    pub fn add(self: *Self) std.mem.Allocator.Error!void {
        const row = try self.allocator.create(mod.KeyValueRow);
        errdefer self.allocator.destroy(row);
        row.* = mod.KeyValueRow.init(self.allocator);
        try self.rows.append(self.allocator, row);
        mod.Focus.shared().set(&row.key);
    }

    /// Removes row `index` (its fields leave the focus); out of range is a no-op.
    ///
    /// - `self`: the state.
    /// - `index`: the row.
    pub fn remove(self: *Self, index: usize) void {
        if (index >= self.rows.items.len) return;
        const row = self.rows.orderedRemove(index);
        self.freeRows(&.{row});
    }

    /// How many rows there are, empty ones included.
    ///
    /// - `self`: the state.
    /// - Returns: the count.
    pub fn count(self: *const Self) usize {
        return self.rows.items.len;
    }

    /// Frees `doomed` and their text.
    ///
    /// - `self`: the state whose allocator made them.
    /// - `doomed`: the rows.
    fn freeRows(self: *const Self, doomed: []const *mod.KeyValueRow) void {
        for (doomed) |row| {
            row.deinit();
            self.allocator.destroy(row);
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "key/value rows set, read back, add, remove and count" {
    var state = KeyValueState.init(std.testing.allocator);
    defer state.deinit();
    try state.setPairs(&.{ .{ "Accept", "application/json" }, .{ "X-Trace", "1" } });
    try std.testing.expectEqual(@as(usize, 2), state.count());

    try state.add();
    defer mod.Focus.shared().clear();
    try std.testing.expectEqual(@as(usize, 3), state.count());
    try std.testing.expect(mod.Focus.shared().focused() == &state.rows.items[2].key);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // The empty row is left out.
    const read = try state.pairs(arena.allocator());
    try std.testing.expectEqual(@as(usize, 2), read.len);
    try std.testing.expectEqualStrings("X-Trace", read[1][0]);

    try state.rows.items[2].value.setText("only a value");
    try std.testing.expectEqual(@as(usize, 3), (try state.pairs(arena.allocator())).len);

    // Removing the focused row leaves nothing focused.
    state.remove(2);
    try std.testing.expect(mod.Focus.shared().focused() == null);
    state.remove(0);
    state.remove(9);
    try std.testing.expectEqual(@as(usize, 1), state.count());
    try std.testing.expectEqualStrings("X-Trace", state.rows.items[0].key.text());

    try state.setPairs(&.{});
    try std.testing.expectEqual(@as(usize, 0), state.count());
}
