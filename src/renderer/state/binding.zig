//! A type-erased two-way handle into a value.

const std = @import("std");
const log = std.log.scoped(.ziggui_binding);

/// A type-erased two-way reference to a value of type T, decoupled from where
/// the value actually lives. Mirrors SwiftUI's `@Binding`.
///
/// - `T`: the value's type.
/// - Returns: the binding type.
pub fn Binding(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Where the value lives, passed to `get_fn` and `set_fn`.
        context: *anyopaque,
        /// Reads the value.
        get_fn: *const fn (*anyopaque) T,
        /// Writes the value.
        set_fn: *const fn (*anyopaque, T) void,

        /// The bound value.
        ///
        /// - `self`: the binding.
        /// - Returns: the value.
        pub fn get(self: *const Self) T {
            return self.get_fn(self.context);
        }

        /// Write the bound value.
        ///
        /// - `self`: the binding.
        /// - `value`: the new value.
        pub fn set(self: *const Self, value: T) void {
            self.set_fn(self.context, value);
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
