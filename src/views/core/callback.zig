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
