//! Where a find stands: which match is current, of how many.

const std = @import("std");
const log = std.log.scoped(.ziggui_find_count);

/// A find's matches, as a `FindBar` reports them ("3 of 40", "No matches").
pub const FindCount = struct {
    const Self = @This();

    /// The current match, counting from 0; null when none is current yet.
    current: ?usize = null,
    /// How many matches were found.
    total: usize,
    /// Whether the find stopped counting at a limit, so there are more than `total`.
    more: bool = false,

    /// The count in words: "No matches", "3 of 40" (with a "+" when there
    /// are more), or "40 matches" before one is current. A `current` at or
    /// past `total` (a match the last find no longer found) counts as none
    /// current, so it never reads "41 of 40".
    ///
    /// - `self`: the count.
    /// - `allocator`: the build arena.
    /// - Returns: the words; propagates allocation failure.
    pub fn textAlloc(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        if (self.total == 0) return "No matches";
        const more: []const u8 = if (self.more) "+" else "";
        if (self.current) |current| if (current < self.total) return allocator.print("{d} of {d}{s}", .{ current + 1, self.total, more });
        return allocator.print("{d}{s} {s}", .{ self.total, more, if (self.total == 1 and !self.more) "match" else "matches" });
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a find count says where the find stands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqualStrings("No matches", try (FindCount{ .total = 0 }).textAlloc(allocator));
    try std.testing.expectEqualStrings("3 of 40", try (FindCount{ .current = 2, .total = 40 }).textAlloc(allocator));
    try std.testing.expectEqualStrings("1 of 500+", try (FindCount{ .current = 0, .total = 500, .more = true }).textAlloc(allocator));
    try std.testing.expectEqualStrings("1 match", try (FindCount{ .total = 1 }).textAlloc(allocator));
    try std.testing.expectEqualStrings("40 matches", try (FindCount{ .total = 40 }).textAlloc(allocator));
}

test "a find count past its total has no current match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqualStrings("40 matches", try (FindCount{ .current = 40, .total = 40 }).textAlloc(allocator));
    try std.testing.expectEqualStrings("40+ matches", try (FindCount{ .current = 90, .total = 40, .more = true }).textAlloc(allocator));
    try std.testing.expectEqualStrings("40 of 40", try (FindCount{ .current = 39, .total = 40 }).textAlloc(allocator));
    try std.testing.expectEqualStrings("No matches", try (FindCount{ .current = 0, .total = 0 }).textAlloc(allocator));
}
