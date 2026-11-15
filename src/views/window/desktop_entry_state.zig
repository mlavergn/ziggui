//! Where the running executable's freedesktop entry stands, in the core so an
//! app's platform layer (and its headless half) can name it without SDL.

const std = @import("std");
const log = std.log.scoped(.ziggui_desktop_entry_state);

/// Where the running executable's freedesktop entry stands (see the SDL
/// runtime's `DesktopInstall.state`).
pub const DesktopEntryState = enum {
    const Self = @This();

    /// No entry of its own, and none installed system-wide.
    missing,
    /// Its entry runs this executable.
    current,
    /// Its entry runs another path (the executable moved).
    stale,
    /// A package installed one under `/usr/share` or `/usr/local/share`.
    system,
    /// Not Linux.
    unsupported,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
