//! A horizontal strip of an image: a range of whole rows.

const std = @import("std");
const log = std.log.scoped(.ziggui_row_band);
const mod = @import("module.zig");

/// A range of rows, half-open: `top` up to, not including, `bottom`. The
/// whole width of the image, so a band's pixels are contiguous in a
/// row-major buffer.
pub const RowBand = struct {
    const Self = @This();

    /// The first row.
    top: u32,
    /// One past the last row.
    bottom: u32,

    /// Every row of an image `height` rows tall.
    ///
    /// - `height`: the image's height, in rows.
    /// - Returns: the band.
    pub fn all(height: u32) Self {
        const self = Self{ .top = 0, .bottom = height };
        return self;
    }

    /// How many rows the band holds.
    ///
    /// - `self`: the band.
    /// - Returns: the row count, 0 for an empty band.
    pub fn rows(self: *const Self) u32 {
        return self.bottom -| self.top;
    }

    /// The band's part of a row-major buffer with `width` elements a row.
    ///
    /// - `self`: the band.
    /// - `T`: the element type.
    /// - `buffer`: the whole image's elements.
    /// - `width`: the elements in one row.
    /// - Returns: the band's elements.
    pub fn slice(self: *const Self, comptime T: type, buffer: []T, width: usize) []T {
        return buffer[@as(usize, self.top) * width .. @as(usize, self.bottom) * width];
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "RowBand: rows and slice" {
    const band: mod.RowBand = .{ .top = 1, .bottom = 3 };
    try std.testing.expectEqual(@as(u32, 2), band.rows());
    var buffer = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 4, 5 }, band.slice(u8, &buffer, 2));
    try std.testing.expectEqual(@as(u32, 0), (mod.RowBand{ .top = 3, .bottom = 1 }).rows());
    try std.testing.expectEqual(@as(u32, 5), mod.RowBand.all(5).rows());
}
