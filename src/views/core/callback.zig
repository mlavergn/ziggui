//! A type-erased tap handler (a button, a row, a toggle), and the ways to
//! make one from a plain function, a method, or a selection.

const std = @import("std");
const log = std.log.scoped(.ziggui_callback);
const mod = @import("module.zig");

/// What `Callback.select` binds: a (binding, value) pair stored in the build
/// arena, which outlives the frame until the next rebuild, so a hit region's
/// callback can safely read it.
const SelectContext = struct {
    const Self = @This();

    /// The selection the callback sets.
    binding: mod.Binding(i64),

    /// The value it sets it to.
    value: i64,

    /// Sets the binding to the value.
    ///
    /// - `context`: the `SelectContext`.
    fn apply(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.binding.set(self.value);
    }
};

/// A type-erased UI callback (button tap, toggle, etc.).
pub const Callback = struct {
    const Self = @This();

    /// What `function` gets back.
    context: ?*anyopaque = null,

    /// The handler.
    function: *const fn (?*anyopaque) void,

    /// Wraps a method taking a typed context pointer as a callback.
    ///
    /// - `T`: the context's type.
    /// - `context`: the context.
    /// - `method`: the method called with it.
    /// - Returns: the callback.
    pub fn init(comptime T: type, context: *T, comptime method: fn (*T) void) Self {
        const self = Self{ .context = context, .function = struct {
            const Self = @This();

            fn call(pointer: ?*anyopaque) void {
                method(@ptrCast(@alignCast(pointer.?)));
            }
        }.call };
        return self;
    }

    /// Wraps a plain zero-argument function as a callback.
    ///
    /// - `function`: the function called.
    /// - Returns: the callback.
    pub fn action(comptime function: fn () void) Self {
        const self = Self{ .function = struct {
            const Self = @This();

            fn call(_: ?*anyopaque) void {
                function();
            }
        }.call };
        return self;
    }

    /// A callback that sets `binding` to `value`: the building block for
    /// selection in composed controls (sidebar rows, radio options, table
    /// rows), which stay pure composition over `onTap` without a dedicated
    /// `HitAction`.
    ///
    /// - `binding`: the selection.
    /// - `value`: what a tap sets it to.
    /// - Returns: the callback, its context in the build arena.
    pub fn select(binding: mod.Binding(i64), value: i64) Self {
        const context = mod.BuildScope.shared().allocator().create(SelectContext) catch @panic("oom");
        context.* = .{ .binding = binding, .value = value };
        const self = Self{ .context = context, .function = SelectContext.apply };
        return self;
    }

    /// Wraps a method that can fail as a callback. A tap cannot return an
    /// error, so a failure is logged, `what` saying what did not happen, and
    /// the state is left as the method left it.
    ///
    /// - `T`: the context's type.
    /// - `context`: the context.
    /// - `method`: called with the context; returns an error union.
    /// - `what`: what a failure means, for the log ("key/value row not added").
    /// - Returns: the callback.
    pub fn attempt(comptime T: type, context: *T, comptime method: anytype, comptime what: []const u8) Self {
        const self = Self{ .context = context, .function = struct {
            const Self = @This();

            fn call(pointer: ?*anyopaque) void {
                if (method(@as(*T, @ptrCast(@alignCast(pointer.?))))) |_| {} else |err| log.err(what ++ " [{t}]", .{err});
            }
        }.call };
        return self;
    }

    /// Wraps a method that also takes a tag, as UIKit's target-action reads
    /// the sender's `tag`: one handler serves many views (a list's rows), and
    /// the tag says which. The (context, tag) pair is made in the build arena,
    /// which outlives the frame until the next rebuild.
    ///
    /// - `T`: the context's type.
    /// - `context`: the context.
    /// - `method`: called with the context and the tag.
    /// - `tag`: what tells this view apart (a row's index).
    /// - Returns: the callback, its context in the build arena.
    pub fn tagged(comptime T: type, context: *T, comptime method: fn (*T, usize) void, tag: usize) Self {
        const Tagged = struct {
            const Self = @This();

            /// The context `method` is called with.
            target: *T,

            /// The tag `method` is called with.
            tag: usize,

            /// Calls `method` with the context and the tag.
            ///
            /// - `pointer`: the `Tagged`.
            fn call(pointer: ?*anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(pointer.?));
                method(self.target, self.tag);
            }
        };
        const bound = mod.BuildScope.shared().allocator().create(Tagged) catch @panic("oom");
        bound.* = .{ .target = context, .tag = tag };
        const self = Self{ .context = bound, .function = Tagged.call };
        return self;
    }

    /// Calls the handler.
    ///
    /// - `self`: the callback.
    pub fn call(self: *const Self) void {
        self.function(self.context);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a tagged callback calls its method with its own tag" {
    const Probe = struct {
        const Self = @This();
        last: ?usize = null,
        fn removed(self: *Self, tag: usize) void {
            self.last = tag;
        }
    };
    var probe: Probe = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const scope = mod.BuildScope.shared();
    scope.begin(arena.allocator());
    defer scope.end();
    const first = Callback.tagged(Probe, &probe, Probe.removed, 3);
    const second = Callback.tagged(Probe, &probe, Probe.removed, 7);
    first.call();
    try std.testing.expectEqual(@as(?usize, 3), probe.last);
    second.call();
    try std.testing.expectEqual(@as(?usize, 7), probe.last);
}

test "an attempted callback calls its fallible method" {
    // A failure is logged with `log.err`, which the test runner counts as a
    // failed test, so only the success path is exercised here.
    const Probe = struct {
        const Self = @This();
        calls: u32 = 0,
        fn grow(self: *Self) std.mem.Allocator.Error!void {
            self.calls += 1;
        }
    };
    var probe: Probe = .{};
    const callback = Callback.attempt(Probe, &probe, Probe.grow, "probe not grown");
    callback.call();
    callback.call();
    try std.testing.expectEqual(@as(u32, 2), probe.calls);
}
