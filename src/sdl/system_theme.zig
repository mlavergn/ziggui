//! The OS light/dark preference, as SDL reports it.

const std = @import("std");
const log = std.log.scoped(.ziggui_system_theme);

/// The OS-level light/dark preference, reported by SDL. Cross-platform: on
/// macOS it reads `AppleInterfaceStyle`, on Windows the `AppsUseLightTheme`
/// registry value, and on Linux the XDG `org.freedesktop.appearance` portal.
/// `.unknown` when the platform can't report one; callers should fall back.
///
/// An OS theme change emits `SDL_EVENT_SYSTEM_THEME_CHANGED`, which wakes the
/// run loop (every event triggers a rebuild on the next iteration), so an app
/// that re-queries `App.systemTheme` each frame follows the OS live without
/// extra wiring.
pub const SystemTheme = enum {
    const Self = @This();

    /// The platform reports no preference.
    unknown,
    /// Light appearance.
    light,
    /// Dark appearance.
    dark,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
