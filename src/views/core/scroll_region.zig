//! A scroll view's frame and state, collected while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_region);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A scrollable viewport's frame paired with its `ScrollState`, collected during
/// painting (when `Context.scroll_regions` is set) so the app can route mouse
/// wheel events to the right region via `PointerInput.scroll`.
pub const ScrollRegion = struct {
    const Self = @This();

    /// The viewport.
    rect: renderer.Rect,

    /// The scroll position the wheel moves. An absorbing region's is a shared
    /// placeholder: check `absorbs` before writing through it.
    state: *mod.ScrollState,

    /// A `ScrollViewStateBoth`, which also takes sideways deltas.
    horizontal: bool = false,

    /// Where an up-and-down delta goes instead of `state` (`ScrollStateData.vertical_target`),
    /// or null for `state`.
    vertical_target: ?*mod.ScrollState = null,

    /// A modal's scrim (`absorbing`): it takes any wheel delta over it, either
    /// way, and moves nothing, so what the modal covers never scrolls behind it.
    absorbs: bool = false,

    /// Frames in an absorbing region the wheel still reaches what is behind
    /// (a modal's `modalPassthrough` frames).
    holes: []const renderer.Rect = &.{},

    /// The position an absorbing region names: never moved, since the wheel stops there.
    var absorbed_state: mod.ScrollState = .{};

    /// The region a sheet's or alert's scrim registers before the modal's
    /// content: a wheel over the modal's own scroll views moves them (they are
    /// registered after it, so in front), and any other delta, a sideways one
    /// over a modal that only scrolls up and down included, stops here.
    ///
    /// - `rect`: the scrim, the whole frame.
    /// - `holes`: frames the wheel still reaches behind it.
    /// - Returns: the region.
    pub fn absorbing(rect: renderer.Rect, holes: []const renderer.Rect) Self {
        return .{ .rect = rect, .state = &absorbed_state, .absorbs = true, .holes = holes };
    }

    /// Whether the region stops a wheel event at `point`: an absorbing one,
    /// outside its holes.
    ///
    /// - `self`: the region.
    /// - `point`: the pointer, inside `rect`.
    /// - Returns: whether the event stops here.
    pub fn stops(self: *const Self, point: renderer.Point) bool {
        if (!self.absorbs) return false;
        for (self.holes) |hole| {
            if (hole.contains(point)) return false;
        }
        return true;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an absorbing region stops the wheel outside its holes" {
    const hole: renderer.Rect = .{ .x = 10, .y = 10, .width = 20, .height = 20 };
    const region = ScrollRegion.absorbing(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, &.{hole});
    try std.testing.expect(region.stops(.{ .x = 50, .y = 50 }));
    try std.testing.expect(!region.stops(.{ .x = 15, .y = 15 }));

    var state: mod.ScrollState = .{};
    const plain: ScrollRegion = .{ .rect = region.rect, .state = &state };
    try std.testing.expect(!plain.stops(.{ .x = 50, .y = 50 }));
}
