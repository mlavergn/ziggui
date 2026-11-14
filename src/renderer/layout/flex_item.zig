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

    /// A max at or past this is a filler's: a `Spacer`, or a frame told to take
    /// all the room (the engine measures with a huge proposal, not infinity).
    pub const fill_threshold: f32 = 100_000;

    /// Whether the item fills whatever room it is given, rather than having a natural size.
    ///
    /// - `self`: the item.
    /// - Returns: true for a `Spacer` or a max-width frame.
    pub fn fills(self: *const Self) bool {
        return self.max >= fill_threshold;
    }

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
