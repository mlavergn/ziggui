//! Picks this OS's audio output listing at compile time and installs it for
//! `AudioOutputs` as the event loop starts: Core Audio's devices on macOS,
//! the Core Audio (MMDevice) endpoints on Windows, GStreamer's device monitor
//! on Linux. Elsewhere there is none: apps list no outputs and their players
//! keep the system default.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_backend);
const mod = @import("module.zig");
const views = @import("views");

/// This OS's audio output listing, as the event loop installs it.
pub const AudioBackend = struct {
    const Self = @This();

    /// The platform's listing, or null where there is none yet.
    const platform: ?*const views.AudioOutputBackend = switch (mod.os_tag) {
        .macos => &mod.CoreAudioOutputs.backend,
        .windows => &mod.MmDeviceAudioOutputs.backend,
        .linux => &mod.GstreamerAudioOutputs.backend,
        else => null,
    };

    /// Installs this OS's listing as the one `AudioOutputs` asks.
    pub fn install() void {
        views.AudioOutputs.setBackend(platform);
    }

    /// Uninstalls it; the loop calls this as it ends.
    pub fn uninstall() void {
        views.AudioOutputs.setBackend(null);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
