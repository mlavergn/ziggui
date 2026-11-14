//! What a `TokenField` edits: a list of short tokens and the field new ones
//! are typed into.

const std = @import("std");
const log = std.log.scoped(.ziggui_token_field_state);
const mod = @import("module.zig");

/// A `TokenField`'s tokens (toolsets, tags), each owned by the state's
/// allocator, and the input field they are typed into. App-owned, so it
/// survives frames; keep it at a stable address (the field's focus).
pub const TokenFieldState = struct {
    const Self = @This();

    /// The field new tokens are typed into; `commit` takes its text.
    input: mod.TextFieldState,

    /// The committed tokens, in order, each owned by `allocator`.
    entries: std.ArrayList([]const u8) = .empty,

    /// Where the tokens and the input's text live.
    allocator: std.mem.Allocator,

    /// No tokens, an empty input.
    ///
    /// - `allocator`: where the tokens and the input's text live.
    /// - Returns: the state.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .input = mod.TextFieldState.init(allocator), .allocator = allocator };
        return self;
    }

    /// Frees the tokens and the input.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        self.freeTokens(self.entries.items);
        self.entries.deinit(self.allocator);
        self.input.deinit();
    }

    /// Replaces the tokens with copies of `replacement`, in order. On failure
    /// the tokens are as they were.
    ///
    /// - `self`: the state.
    /// - `replacement`: the new tokens.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setTokens(self: *Self, replacement: []const []const u8) std.mem.Allocator.Error!void {
        var fresh: std.ArrayList([]const u8) = .empty;
        errdefer {
            self.freeTokens(fresh.items);
            fresh.deinit(self.allocator);
        }
        try fresh.ensureTotalCapacity(self.allocator, replacement.len);
        for (replacement) |token| fresh.appendAssumeCapacity(try self.allocator.dupe(u8, token));
        self.freeTokens(self.entries.items);
        self.entries.deinit(self.allocator);
        self.entries = fresh;
    }

    /// The committed tokens, borrowed: valid until the next change.
    ///
    /// - `self`: the state.
    /// - Returns: the tokens.
    pub fn tokens(self: *const Self) []const []const u8 {
        return self.entries.items;
    }

    /// Takes the input's text: splits it on commas, trims spaces and tabs,
    /// appends each non-empty token not already present, and empties the input.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; propagates allocation failure.
    pub fn commit(self: *Self) std.mem.Allocator.Error!void {
        var parts = std.mem.splitScalar(u8, self.input.text(), ',');
        while (parts.next()) |part| {
            const token = std.mem.trim(u8, part, " \t");
            if (token.len == 0 or self.contains(token)) continue;
            const copy = try self.allocator.dupe(u8, token);
            errdefer self.allocator.free(copy);
            try self.entries.append(self.allocator, copy);
        }
        try self.input.setText("");
    }

    /// Removes token `index`; out of range is a no-op.
    ///
    /// - `self`: the state.
    /// - `index`: the token.
    pub fn remove(self: *Self, index: usize) void {
        if (index >= self.entries.items.len) return;
        self.allocator.free(self.entries.orderedRemove(index));
    }

    /// Reports whether `token` is already committed.
    ///
    /// - `self`: the state.
    /// - `token`: the token.
    /// - Returns: true when present.
    fn contains(self: *const Self, token: []const u8) bool {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry, token)) return true;
        }
        return false;
    }

    /// Frees `doomed`.
    ///
    /// - `self`: the state whose allocator made them.
    /// - `doomed`: the tokens.
    fn freeTokens(self: *const Self, doomed: []const []const u8) void {
        for (doomed) |token| self.allocator.free(token);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "tokens commit from comma-separated input, without blanks or repeats" {
    var state = TokenFieldState.init(std.testing.allocator);
    defer state.deinit();
    try state.setTokens(&.{ "repos", "issues" });
    try state.input.setText(" issues, actions ,, pull_requests,actions ");
    try state.commit();
    try std.testing.expectEqual(@as(usize, 4), state.tokens().len);
    try std.testing.expectEqualStrings("actions", state.tokens()[2]);
    try std.testing.expectEqualStrings("pull_requests", state.tokens()[3]);
    try std.testing.expectEqualStrings("", state.input.text());

    state.remove(0);
    state.remove(7);
    try std.testing.expectEqualStrings("issues", state.tokens()[0]);
    try state.setTokens(&.{"one"});
    try std.testing.expectEqual(@as(usize, 1), state.tokens().len);
}
