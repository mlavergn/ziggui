//! Observation primitive for the dirty-flag reactivity model.
//!
//! An `Observer` is anything that wants to be notified when a piece of state it
//! depends on changes. In ziggui every view node embeds an Observer; when a
//! `State(T)` it reads is mutated, the node is marked dirty and re-rendered on
//! the next frame. This module keeps the mechanism decoupled from the view tree
//! so it can be tested in isolation.

const std = @import("std");
const log = std.log.scoped(.ziggui_observer);
const mod = @import("module.zig");

/// Something notified when state it depends on changes.
pub const Observer = struct {
    const Self = @This();

    /// Set when a dependency changes; cleared by the render loop after redraw.
    dirty: bool = true,
    /// Optional hook fired on every transition into the dirty state (e.g. to
    /// request a frame from the windowing layer). Receives this observer.
    on_dirty: ?*const fn (*Self) void = null,
    /// Opaque user pointer (e.g. the owning view node) for the callback.
    context: ?*anyopaque = null,

    /// Mark the observer dirty, firing `on_dirty` if it was clean.
    ///
    /// - `self`: the observer.
    pub fn markDirty(self: *Self) void {
        const was_clean = !self.dirty;
        self.dirty = true;
        if (was_clean) {
            if (self.on_dirty) |callback| callback(self);
        }
    }

    /// Mark the observer clean (after a redraw).
    ///
    /// - `self`: the observer.
    pub fn clear(self: *Self) void {
        self.dirty = false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Counts `on_dirty` calls.
const DirtyCounter = struct {
    const Self = @This();

    /// How many times `onDirty` ran.
    var calls: u32 = 0;

    /// Count one call.
    ///
    /// - `observer`: unused.
    fn onDirty(observer: *mod.Observer) void {
        _ = observer;
        calls += 1;
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Observer: starts dirty, clears, re-dirties" {
    var observer = mod.Observer{};
    try std.testing.expect(observer.dirty);
    observer.clear();
    try std.testing.expect(!observer.dirty);
    observer.markDirty();
    try std.testing.expect(observer.dirty);
}

test "Observer: on_dirty fires only on clean->dirty transition" {
    DirtyCounter.calls = 0;
    var observer = mod.Observer{ .dirty = false, .on_dirty = DirtyCounter.onDirty };
    observer.markDirty();
    observer.markDirty(); // already dirty -> no second call
    try std.testing.expectEqual(@as(u32, 1), DirtyCounter.calls);
    observer.clear();
    observer.markDirty();
    try std.testing.expectEqual(@as(u32, 2), DirtyCounter.calls);
}
