//! Picks this OS's media player at compile time and hands it to the event
//! loop: the `PlayerBackend` `Player`s are made with, and the placement of
//! their pictures at the `VideoPlayer` regions each frame collects.

const std = @import("std");
const log = std.log.scoped(.ziggui_video_backend);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// This OS's media player, as the event loop uses it. Each platform type has
/// the same declarations: `backend`, `presents`, `present` and `detachAll`,
/// and optionally `underlays`.
pub const VideoBackend = struct {
    const Self = @This();

    /// The platform player: AVFoundation on macOS (its picture behind the
    /// surface), Media Foundation on Windows (its frames drawn under the
    /// surface, `VideoUnderlay`), GStreamer on Linux (its frames drawn in it).
    const Platform = switch (mod.os_tag) {
        .macos => mod.AvFoundationPlayer,
        .windows => mod.MediaFoundationPlayer,
        else => mod.GstreamerPlayer,
    };

    /// Whether this OS shows pictures behind the window's surface: the loop
    /// collects `VideoPlayer` regions only then, else each draws a
    /// placeholder.
    pub const presents = Platform.presents;

    /// Installs this OS's player as the one `Player`s are made with.
    pub fn install() void {
        views.Player.setBackend(&Platform.backend);
    }

    /// Takes every picture out of the window and uninstalls the player; the
    /// loop calls this before it destroys the window. Players made before it
    /// keep working (and freeing) through their own backend.
    pub fn uninstall() void {
        Platform.detachAll();
        views.Player.setBackend(null);
    }

    /// Shows each region's player picture where its view is, and hides those
    /// no view showed this frame.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `VideoPlayer` regions, in points.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.VideoRegion) void {
        Platform.present(window, regions);
    }

    /// The frames the renderer draws under the surface this frame: Windows'
    /// player hands them over (`VideoUnderlay`); a player that shows its
    /// picture behind the window (macOS) has none.
    ///
    /// - Returns: the underlays, valid until the next `present`.
    pub fn underlays() []const mod.VideoUnderlay {
        if (comptime @hasDecl(Platform, "underlays")) return Platform.underlays();
        return &.{};
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
