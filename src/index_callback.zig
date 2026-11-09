const std = @import("std");
const log = std.log.scoped(.ziggui_index_callback);
const zigui = @import("zigui");

/// An `IndexCallback` and the index `IndexCallback.bind` bound it to.
const BoundIndex = struct {
    const Self = @This();

    /// The callback.
    cb: IndexCallback,

    /// The index it is called with.
    index: usize,

    /// The `zigui.Callback` thunk: calls the bound callback with its index.
    ///
    /// - `p`: the `BoundIndex`.
    fn thunk(p: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(p.?));
        self.cb.call(self.index);
    }
};

/// A callback that takes a row index: a list's tap handler.
pub const IndexCallback = struct {
    const Self = @This();

    /// The context `func` gets back.
    ctx: ?*anyopaque = null,

    /// The handler.
    func: *const fn (?*anyopaque, usize) void,

    /// Wraps a method taking a typed context and an index, as zigui's
    /// `actionCtx` wraps a method taking a context.
    ///
    /// - `T`: the context's type.
    /// - `ctx`: the context.
    /// - `f`: the method.
    /// - Returns: the callback.
    pub fn init(comptime T: type, ctx: *T, comptime f: fn (*T, usize) void) Self {
        const self = Self{ .ctx = ctx, .func = struct {
            fn g(p: ?*anyopaque, index: usize) void {
                f(@ptrCast(@alignCast(p.?)), index);
            }
        }.g };
        return self;
    }

    /// Calls the handler with `index`.
    ///
    /// - `self`: the callback.
    /// - `index`: the row.
    pub fn call(self: *const Self, index: usize) void {
        self.func(self.ctx, index);
    }

    /// A `zigui.Callback` that calls this one with `index`, bound in the build
    /// arena, so a row's `onTap` can say which row it was. `zigui.tapCount()`
    /// inside the handler tells a double click from a single one.
    ///
    /// - `self`: the callback.
    /// - `index`: the index to call it with.
    /// - Returns: the bound callback.
    pub fn bind(self: *const Self, index: usize) zigui.Callback {
        const b = zigui.buildAlloc().create(BoundIndex) catch @panic("oom");
        b.* = .{ .cb = self.*, .index = index };
        return .{ .ctx = b, .func = BoundIndex.thunk };
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
    zigui.beginBuild(arena.allocator());
    const cb = IndexCallback.init(Probe, &probe, Probe.onIndex).bind(7);
    zigui.endBuild();
    cb.call();
    try std.testing.expectEqual(@as(?usize, 7), probe.index);
}
