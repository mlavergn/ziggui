//! Where a point in a window falls for the window manager: content, the
//! title bar's empty space (drags the window), or an edge or corner that
//! resizes it. Pure; the SDL runtime's `WindowHitTest` maps the answer to
//! `SDL_HITTEST_*` for a window with a drag band or a custom title bar.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_hit_area);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The window state a hit test needs.
pub const WindowHitArea = struct {
    const Self = @This();

    /// The window's size, in the same points as the hit regions.
    size: renderer.Size,

    /// The top band whose empty space drags the window (0 = none).
    drag_band: f32 = 0,

    /// How far in from each edge a press resizes the window (0 = it doesn't:
    /// the OS frame does that, or the window is maximized).
    resize_edge: f32 = 0,

    /// Within the band, the frame's tap regions (they keep their clicks).
    hits: []const mod.HitRegion = &.{},

    /// A popup (the text context menu) is open: everything is content.
    menu_open: bool = false,

    /// The window is fullscreen: everything is content (a fullscreen window
    /// neither resizes from its edges nor drags by its title bar).
    fullscreen: bool = false,

    /// What a press at `point` does: an edge or corner first, then the drag
    /// band's empty space; a tap region there (not an overlay's dismiss region
    /// nor a right-click-only one) keeps the click.
    ///
    /// - `self`: the window's state.
    /// - `point`: the press.
    /// - Returns: what the press does.
    pub fn at(self: *const Self, point: renderer.Point) mod.WindowHit {
        if (self.menu_open or self.fullscreen) return .normal;
        const edge = self.resize_edge;
        if (edge > 0) {
            const left = point.x < edge;
            const right = point.x >= self.size.width - edge;
            const top = point.y < edge;
            const bottom = point.y >= self.size.height - edge;
            if (top and left) return .resizeTopLeft;
            if (top and right) return .resizeTopRight;
            if (bottom and left) return .resizeBottomLeft;
            if (bottom and right) return .resizeBottomRight;
            if (top) return .resizeTop;
            if (bottom) return .resizeBottom;
            if (left) return .resizeLeft;
            if (right) return .resizeRight;
        }
        if (point.y >= self.drag_band) return .normal;
        for (self.hits) |hit| {
            if (hit.action == .secondary or hit.action == .dismiss) continue;
            if (hit.rect.contains(point)) return .normal;
        }
        return .draggable;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "window hit: edges and corners resize, the band drags, its controls keep their clicks" {
    const Probe = struct {
        const Self = @This();
        fn noop(_: ?*anyopaque) void {}
        fn get(context: *anyopaque) bool {
            return @as(*bool, @ptrCast(context)).*;
        }
        fn set(context: *anyopaque, value: bool) void {
            @as(*bool, @ptrCast(context)).* = value;
        }
    };
    var shown = true;
    const dismiss: mod.Binding(bool) = .{ .context = &shown, .get_fn = Probe.get, .set_fn = Probe.set };
    const hits = [_]mod.HitRegion{
        // A menu title in the band, then a modal's dismiss region over everything.
        .{ .rect = .{ .x = 40, .y = 0, .width = 50, .height = 32 }, .action = .{ .callback = .{ .function = Probe.noop } }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 800, .height = 600 }, .action = .{ .dismiss = dismiss }, .disabled = false },
    };
    const area: WindowHitArea = .{ .size = .{ .width = 800, .height = 600 }, .drag_band = 32, .resize_edge = 6, .hits = &hits };
    try std.testing.expectEqual(mod.WindowHit.resizeTopLeft, area.at(.{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(mod.WindowHit.resizeTop, area.at(.{ .x = 400, .y = 3 }));
    try std.testing.expectEqual(mod.WindowHit.resizeBottomRight, area.at(.{ .x = 797, .y = 597 }));
    try std.testing.expectEqual(mod.WindowHit.resizeLeft, area.at(.{ .x = 1, .y = 300 }));
    try std.testing.expectEqual(mod.WindowHit.resizeRight, area.at(.{ .x = 795, .y = 300 }));
    // The band drags, even under the dismiss region; the title keeps its click.
    try std.testing.expectEqual(mod.WindowHit.draggable, area.at(.{ .x = 400, .y = 16 }));
    try std.testing.expectEqual(mod.WindowHit.normal, area.at(.{ .x = 60, .y = 16 }));
    // Below the band is content.
    try std.testing.expectEqual(mod.WindowHit.normal, area.at(.{ .x = 400, .y = 300 }));
    // Maximized (no resize edge), the top edge drags instead.
    var maximized = area;
    maximized.resize_edge = 0;
    try std.testing.expectEqual(mod.WindowHit.draggable, maximized.at(.{ .x = 400, .y = 2 }));
    // A popup open: everything is content.
    var popup = area;
    popup.menu_open = true;
    try std.testing.expectEqual(mod.WindowHit.normal, popup.at(.{ .x = 400, .y = 16 }));
    // Fullscreen: neither an edge nor the band does anything.
    var fullscreen = area;
    fullscreen.fullscreen = true;
    try std.testing.expectEqual(mod.WindowHit.normal, fullscreen.at(.{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(mod.WindowHit.normal, fullscreen.at(.{ .x = 400, .y = 16 }));
}
