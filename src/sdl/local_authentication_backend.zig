//! Picks this OS's device-owner authentication at compile time and installs
//! it for `AuthenticationContext` as the event loop starts: LocalAuthentication
//! (Touch ID, else the login password) on macOS. Elsewhere there is none yet:
//! nothing is available and apps offer their passwords alone.

const std = @import("std");
const log = std.log.scoped(.ziggui_local_authentication_backend);
const mod = @import("module.zig");
const views = @import("views");

/// This OS's authentication, as the event loop installs it.
pub const LocalAuthenticationBackend = struct {
    const Self = @This();

    /// The platform's authentication, or null where there is none yet.
    const platform: ?*const views.AuthenticationBackend = switch (mod.os_tag) {
        .macos => &mod.LaContextBackend.backend,
        else => null,
    };

    /// Installs this OS's authentication as the one `AuthenticationContext` asks.
    pub fn install() void {
        views.AuthenticationContext.setBackend(platform);
    }

    /// Uninstalls it; the loop calls this as it ends.
    pub fn uninstall() void {
        views.AuthenticationContext.setBackend(null);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
