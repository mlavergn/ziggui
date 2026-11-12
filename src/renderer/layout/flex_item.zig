//! One stack child's main-axis bounds, for space distribution.

const std = @import("std");
const log = std.log.scoped(.ziggui_flex_item);

/// One stack child's main-axis bounds.
pub const FlexItem = struct {
    const Self = @This();

    /// Smallest main length the item will accept (its size at proposal 0).
    min: f32,
    /// Largest main length the item will grow to (its size at a huge proposal).
    max: f32,

    /// How much the item can grow past its minimum.
    ///
    /// - `self`: the item.
    /// - Returns: max minus min.
    pub fn flexibility(self: *const Self) f32 {
        return self.max - self.min;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
