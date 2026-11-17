//! A player's picture in the view tree (SwiftUI's `VideoPlayer(player:)`).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_video_player);
const mod = @import("module.zig");

/// Shows `player`'s picture in its frame, aspect-fit on black. It fills what
/// it is offered (size it with `.frame`) and draws no controls: views stacked
/// over it in a `ZStack` are drawn on top of the picture, as SwiftUI's
/// `videoOverlay` is. In a window on macOS the platform player draws the
/// picture itself, behind the window's surface; on Linux it hands its frames
/// over and the view draws them in the surface; headless it is a black frame
/// with a video glyph.
///
/// - `player`: the player; it must outlive the frame.
/// - Returns: the view.
pub fn VideoPlayer(player: *mod.Player) mod.View {
    return .{ .kind = .{ .videoPlayer = .{ .player = player } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
