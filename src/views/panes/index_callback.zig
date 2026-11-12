//! A callback that takes a row index: a list's tap handler.

const std = @import("std");
const log = std.log.scoped(.ziggui_index_callback);
const mod = @import("module.zig");

/// An `IndexCallback` and the index `IndexCallback.bind` bound it to.
const BoundIndex = struct {
    const Self = @This();

    /// The callback.
    callback: IndexCallback,

    /// The index it is called with.
    index: usize,

    /// The `mod.Callback` thunk: calls the bound callback with its index.
    ///
    /// - `pointer`: the `BoundIndex`.
    fn thunk(pointer: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(pointer.?));
        self.callback.call(self.index);
    }
};

/// A callback that takes a row index: a list's tap handler.
pub const IndexCallback = struct {
    const Self = @This();

    /// The context `function` gets back.
    context: ?*anyopaque = null,

    /// The handler.
    function: *const fn (?*anyopaque, usize) void,

    /// Wraps a method taking a typed context and an index, as ziggui's
    /// `Callback.init` wraps a method taking a context.
    ///
    /// - `T`: the context's type.
    /// - `context`: the context.
    /// - `method`: the method.
    /// - Returns: the callback.
    pub fn init(comptime T: type, context: *T, comptime method: fn (*T, usize) void) Self {
        const self = Self{ .context = context, .function = struct {
            const Self = @This();

            fn call(pointer: ?*anyopaque, index: usize) void {
                method(@ptrCast(@alignCast(pointer.?)), index);
            }
        }.call };
        return self;
    }

    /// Calls the handler with `index`.
    ///
    /// - `self`: the callback.
    /// - `index`: the row.
    pub fn call(self: *const Self, index: usize) void {
        self.function(self.context, index);
    }

    /// A `mod.Callback` that calls this one with `index`, bound in the build
    /// arena, so a row's `onTap` can say which row it was. `mod.PointerInput.shared().tapCount()`
    /// inside the handler tells a double click from a single one.
    ///
    /// - `self`: the callback.
    /// - `index`: the index to call it with.
    /// - Returns: the bound callback.
    pub fn bind(self: *const Self, index: usize) mod.Callback {
        const bound = mod.BuildScope.shared().allocator().create(BoundIndex) catch @panic("oom");
        bound.* = .{ .callback = self.*, .index = index };
        return .{ .context = bound, .function = BoundIndex.thunk };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a bound index callback calls its handler with the bound index" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const Probe = struct {
        const Self = @This();
        index: ?usize = null,
        fn onIndex(self: *Self, index: usize) void {
            self.index = index;
        }
    };
    var probe: Probe = .{};
    mod.BuildScope.shared().begin(arena.allocator());
    const callback = IndexCallback.init(Probe, &probe, Probe.onIndex).bind(7);
    mod.BuildScope.shared().end();
    callback.call();
    try std.testing.expectEqual(@as(?usize, 7), probe.index);
}
