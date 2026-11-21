//! Where stateless scroll views keep their positions between frames.

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_memory);
const mod = @import("module.zig");

/// One kept position: the scroll view it belongs to, when that last built.
const ScrollSlot = struct {
    const Self = @This();

    /// The scroll view's key (`BuildScope.scrollViewKey`).
    key: u64 = 0,
    /// Whether the slot holds a position.
    used: bool = false,
    /// The main window's frame the scroll view last built in.
    last_frame: u64 = 0,
    /// The position.
    state: mod.ScrollState = .{},
};

/// The positions of the frame's stateless `ScrollView`s (and the `List`s on
/// them), so they scroll as SwiftUI's do though the app keeps no
/// `ScrollState`: each is keyed by its place among the frame's stateless
/// scroll views, per window (`BuildScope.scrollViewKey`). A fixed pool, so it
/// allocates nothing and its positions never move in memory; when every slot
/// is taken, the one built longest ago gives way. One per thread (`shared`).
pub const ScrollMemory = struct {
    const Self = @This();

    /// How many positions it keeps at once.
    pub const capacity: usize = 64;

    /// The kept positions.
    slots: [capacity]ScrollSlot = @splat(.{}),

    /// The current thread's memory.
    threadlocal var shared_memory: Self = .{};

    /// The current thread's memory.
    ///
    /// - Returns: the shared memory.
    pub fn shared() *Self {
        return &shared_memory;
    }

    /// The position kept for the scroll view `key` names, made at the top on
    /// first need (in a free slot, else the one built longest ago), stamped
    /// with `frame` as used.
    ///
    /// - `self`: the memory.
    /// - `key`: the scroll view's key.
    /// - `frame`: the main window's frame being built.
    /// - Returns: the position, at the same address every frame it is kept.
    pub fn state(self: *Self, key: u64, frame: u64) *mod.ScrollState {
        var reuse: usize = 0;
        for (&self.slots, 0..) |*slot, index| {
            if (slot.used and slot.key == key) {
                slot.last_frame = frame;
                return &slot.state;
            }
            const best = &self.slots[reuse];
            if (best.used and (!slot.used or slot.last_frame < best.last_frame)) reuse = index;
        }
        self.slots[reuse] = .{ .key = key, .used = true, .last_frame = frame };
        return &self.slots[reuse].state;
    }

    /// Forgets every position: a new window's, or a test's, scroll views
    /// start at the top.
    ///
    /// - `self`: the memory.
    pub fn reset(self: *Self) void {
        self.slots = @splat(.{});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(ScrollMemory);
    // Nothing here does I/O to trace.
    _ = log;
}

test "scroll memory keeps a position per key at one address, and reuses the oldest when full" {
    var memory: ScrollMemory = .{};
    const first = memory.state(1, 1);
    first.offset = 40;
    try std.testing.expectEqual(first, memory.state(1, 2));
    try std.testing.expectEqual(@as(f32, 40), memory.state(1, 3).offset);
    try std.testing.expect(memory.state(2, 3) != first);
    // Filled, the slot built longest ago (key 2, frame 3) gives way.
    for (0..ScrollMemory.capacity - 2) |index| _ = memory.state(100 + index, 10);
    _ = memory.state(1, 11);
    const fresh = memory.state(999, 12);
    try std.testing.expectEqual(@as(f32, 0), fresh.offset);
    try std.testing.expectEqual(@as(f32, 40), memory.state(1, 13).offset);
}
