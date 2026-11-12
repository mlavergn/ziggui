//! What `Screenshot.render` draws: the image's size, the theme, and how many
//! frames are built before the one it keeps.

const std = @import("std");
const log = std.log.scoped(.ziggui_screenshot_options);
const renderer = @import("renderer");

/// What a headless frame is drawn at and with.
pub const ScreenshotOptions = struct {
    const Self = @This();

    /// The image's width, in points; one pixel per point.
    width: u32,

    /// The image's height, in points; one pixel per point.
    height: u32,

    /// The theme the frames are built and drawn with.
    theme: renderer.Theme,

    /// How many frames are built and laid out, as a window would, before the
    /// last of them is drawn (at least one). Two let scroll views lay out, then
    /// build the rows they show; a body whose first frame changes its state
    /// (focusing a chat) needs one more.
    frames: u32 = 2,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "two frames settle by default" {
    const options: ScreenshotOptions = .{ .width = 4, .height = 2, .theme = renderer.MacosTheme.light };
    try std.testing.expectEqual(@as(u32, 2), options.frames);
}
