//! A 2D alignment: a horizontal and a vertical guide.

const std = @import("std");
const log = std.log.scoped(.ziggui_alignment);
const mod = @import("module.zig");

/// A 2D alignment combining a horizontal and vertical guide, with the common
/// SwiftUI presets.
pub const Alignment = struct {
    const Self = @This();

    /// The horizontal guide.
    horizontal: mod.HorizontalAlignment,
    /// The vertical guide.
    vertical: mod.VerticalAlignment,

    /// Centered on both axes.
    pub const center = Self{ .horizontal = .center, .vertical = .center };
    /// Leading edge, vertically centered.
    pub const leading = Self{ .horizontal = .leading, .vertical = .center };
    /// Trailing edge, vertically centered.
    pub const trailing = Self{ .horizontal = .trailing, .vertical = .center };
    /// Top edge, horizontally centered.
    pub const top = Self{ .horizontal = .center, .vertical = .top };
    /// Bottom edge, horizontally centered.
    pub const bottom = Self{ .horizontal = .center, .vertical = .bottom };
    /// Top-leading corner (SwiftUI's name, used as a decl literal).
    pub const topLeading = Self{ .horizontal = .leading, .vertical = .top };
    /// Top-trailing corner (SwiftUI's name, used as a decl literal).
    pub const topTrailing = Self{ .horizontal = .trailing, .vertical = .top };
    /// Bottom-leading corner (SwiftUI's name, used as a decl literal).
    pub const bottomLeading = Self{ .horizontal = .leading, .vertical = .bottom };
    /// Bottom-trailing corner (SwiftUI's name, used as a decl literal).
    pub const bottomTrailing = Self{ .horizontal = .trailing, .vertical = .bottom };

    /// Top-left origin at which a `child` of the given size should be placed so
    /// that it is aligned within a `parent`-sized box.
    ///
    /// - `self`: the alignment.
    /// - `parent`: the box's size.
    /// - `child`: the child's size.
    /// - Returns: the child's origin, relative to the box.
    pub fn position(self: *const Self, parent: mod.Size, child: mod.Size) mod.Point {
        return .{
            .x = (parent.width - child.width) * self.horizontal.fraction(),
            .y = (parent.height - child.height) * self.vertical.fraction(),
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Alignment: presets resolve fractions" {
    const centered = mod.Alignment.center;
    try std.testing.expectEqual(mod.HorizontalAlignment.center, centered.horizontal);
    try std.testing.expectEqual(mod.VerticalAlignment.center, centered.vertical);
    try std.testing.expectEqual(mod.HorizontalAlignment.leading, mod.Alignment.topLeading.horizontal);
    try std.testing.expectEqual(mod.VerticalAlignment.top, mod.Alignment.topLeading.vertical);
}

test "Alignment: position a child size within a parent size" {
    const parent = mod.Size{ .width = 100, .height = 100 };
    const child = mod.Size{ .width = 20, .height = 10 };
    // center -> (40, 45)
    try std.testing.expectEqual(mod.Point{ .x = 40, .y = 45 }, mod.Alignment.center.position(parent, child));
    // topLeading -> (0, 0)
    try std.testing.expectEqual(mod.Point{ .x = 0, .y = 0 }, mod.Alignment.topLeading.position(parent, child));
    // bottomTrailing -> (80, 90)
    try std.testing.expectEqual(mod.Point{ .x = 80, .y = 90 }, mod.Alignment.bottomTrailing.position(parent, child));
}
