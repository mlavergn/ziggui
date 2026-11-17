//! The Linux `WebPageBackend`: not implemented yet. Its pages report
//! `unsupported` as their failure, and `WebView` draws its placeholder.
//!
//! The intended engine is WebKitGTK (`webkitgtk-6.0` on GTK4): a
//! `WebKitWebView` with a `WebKitUserContentManager` for the bridges
//! (`script-message-received::<name>`), its `uri`, `title` and back-forward
//! list signals for `WebPage.update`, and `load-failed` for the failure.
//! Placing it over ziggui's surface needs a native-view host for X11 and
//! Wayland (a GTK window or subsurface the loop keeps over the SDL window).
//! Linking GTK would make every ziggui app on Linux need it, so the library
//! is to be loaded at run time (or an app opts in at build time): decided
//! when this lands.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_kit_gtk_backend);
const views = @import("views");

/// The Linux web view behind every `WebPage`: a stub for now.
pub const WebKitGtkBackend = struct {
    const Self = @This();

    /// The backend `WebPage`s are made with: it refuses, saying why.
    pub const backend: views.WebPageBackend = .{
        .unsupported = "Web pages are not implemented on Linux yet.",
        .create = Self.create,
        .destroy = Self.ignore,
        .view = Self.view,
        .trust = Self.trust,
        .load = Self.load,
        .go_back = Self.ignore,
        .go_forward = Self.ignore,
        .reload = Self.ignore,
        .add_bridge = Self.addBridge,
    };

    /// Never called while `unsupported` is set.
    ///
    /// - `page`: the page; unused.
    /// - Returns: null.
    fn create(page: *views.WebPage) ?*anyopaque {
        _ = page;
        return null;
    }

    /// Never called: no page is made.
    ///
    /// - `handle`: the page; unused.
    fn ignore(handle: *anyopaque) void {
        _ = handle;
    }

    /// Never called: no page is made.
    ///
    /// - `handle`: the page; unused.
    /// - Returns: null.
    fn view(handle: *anyopaque) ?*anyopaque {
        _ = handle;
        return null;
    }

    /// Never called: no page is made.
    ///
    /// - `handle`: the page; unused.
    /// - `url`: the trusted address; unused.
    fn trust(handle: *anyopaque, url: [:0]const u8) void {
        _ = handle;
        _ = url;
    }

    /// Never called: no page is made.
    ///
    /// - `handle`: the page; unused.
    /// - `url`: the address; unused.
    /// - Returns: false.
    fn load(handle: *anyopaque, url: [:0]const u8) bool {
        _ = handle;
        _ = url;
        return false;
    }

    /// Never called: no page is made.
    ///
    /// - `handle`: the page; unused.
    /// - `name`: the bridge's name; unused.
    fn addBridge(handle: *anyopaque, name: [:0]const u8) void {
        _ = handle;
        _ = name;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the Linux web view refuses, saying why" {
    try std.testing.expect(WebKitGtkBackend.backend.unsupported != null);
}
