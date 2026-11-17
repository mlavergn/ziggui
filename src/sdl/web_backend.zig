//! Picks this OS's web view at compile time and installs it as the one
//! `WebPage`s are made with. Their views are placed by the native-view host
//! (`NativeBackend`), as any `NativeView`.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_backend);
const mod = @import("module.zig");
const views = @import("views");

/// This OS's web view, as the event loop installs it.
pub const WebBackend = struct {
    const Self = @This();

    /// The platform web view: WebKit on macOS, WebKitGTK on Linux, WebView2
    /// on Windows.
    const Platform = switch (mod.os_tag) {
        .macos => mod.WkWebViewBackend,
        .windows => mod.WebView2Backend,
        else => mod.WebKitGtkBackend,
    };

    /// Installs this OS's web view as the one `WebPage`s are made with.
    pub fn install() void {
        views.WebPage.setBackend(&Platform.backend);
    }

    /// Uninstalls it; the loop calls this as it ends. Pages made before keep
    /// working (and freeing) through their own backend.
    pub fn uninstall() void {
        views.WebPage.setBackend(null);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
