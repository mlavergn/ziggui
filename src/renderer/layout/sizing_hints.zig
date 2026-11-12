//! The intrinsic sizing of a layout leaf.

const std = @import("std");
const log = std.log.scoped(.ziggui_sizing_hints);
const mod = @import("module.zig");

/// Intrinsic sizing of a content leaf along both axes.
pub const SizingHints = struct {
    const Self = @This();

    /// The smallest the leaf may be.
    min: mod.Size = .{},
    /// The size the leaf reports when a dimension is unspecified.
    ideal: mod.Size = .{},
    /// The largest the leaf may be.
    max: mod.Size = .{ .width = std.math.inf(f32), .height = std.math.inf(f32) },

    /// A content box that always reports one fixed size.
    ///
    /// - `size`: the size.
    /// - Returns: hints whose minimum, ideal and maximum are all `size`.
    pub fn fixedSize(size: mod.Size) Self {
        return .{ .min = size, .ideal = size, .max = size };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
