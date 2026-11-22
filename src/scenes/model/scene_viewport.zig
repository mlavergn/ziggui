//! Where a view last drew a scene, for the gestures that move its camera.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_viewport);
const mod = @import("module.zig");

/// Where the view showing a scene drew it last, written by the view as it
/// paints: the gestures that move the camera act only over it, and only
/// while that frame is its window's last.
pub const SceneViewport = struct {
    const Self = @This();

    /// The view's frame (x, y, width, height), in points.
    rect: [4]f32,
    /// The part of the frame on screen (x, y, width, height), in points.
    visible: [4]f32,
    /// The frame number the view drew in.
    frame_number: u64,
    /// Whether it drew in the popover window rather than the main one.
    popover_window: bool,
    /// Whether the view lets gestures move the camera.
    camera_control: bool,

    /// Whether a point lies on the part of the view on screen.
    ///
    /// - `self`: the viewport.
    /// - `x`: the point's x, in points.
    /// - `y`: the point's y.
    /// - Returns: true when it does.
    pub fn shows(self: *const Self, x: f32, y: f32) bool {
        return x >= self.visible[0] and y >= self.visible[1] and x < self.visible[0] + self.visible[2] and y < self.visible[1] + self.visible[3];
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}

test "a viewport shows only the part of the view on screen" {
    const viewport = SceneViewport{ .rect = .{ 0, 0, 100, 100 }, .visible = .{ 0, 50, 100, 50 }, .frame_number = 1, .popover_window = false, .camera_control = true };
    try std.testing.expect(viewport.shows(10, 60));
    try std.testing.expect(!viewport.shows(10, 40));
    try std.testing.expect(!viewport.shows(100, 60));
}
