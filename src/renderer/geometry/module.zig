//! Geometry primitives: Point, Size, Rect, EdgeInsets, Alignment, Axis.
//! Pure value types mirroring the spatial vocabulary of SwiftUI's layout model
//! (top/leading/bottom/trailing insets, alignment guides), in plain Zig.

const std = @import("std");
const log = std.log.scoped(.ziggui_geometry_module);

/// A 2D point in logical coordinates.
pub const Point = @import("point.zig").Point;
/// A 2D extent in logical coordinates.
pub const Size = @import("size.zig").Size;
/// An axis-aligned, half-open rectangle.
pub const Rect = @import("rect.zig").Rect;
/// Per-side spacing (top, leading, bottom, trailing).
pub const EdgeInsets = @import("edge_insets.zig").EdgeInsets;
/// A horizontal alignment guide.
pub const HorizontalAlignment = @import("horizontal_alignment.zig").HorizontalAlignment;
/// A vertical alignment guide.
pub const VerticalAlignment = @import("vertical_alignment.zig").VerticalAlignment;
/// A horizontal and a vertical guide together.
pub const Alignment = @import("alignment.zig").Alignment;
/// The two layout axes.
pub const Axis = @import("axis.zig").Axis;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("point.zig");
    _ = @import("size.zig");
    _ = @import("rect.zig");
    _ = @import("edge_insets.zig");
    _ = @import("horizontal_alignment.zig");
    _ = @import("vertical_alignment.zig");
    _ = @import("alignment.zig");
    _ = @import("axis.zig");
}
