//! The platform web view a `WebPage` drives, as function pointers: the SDL
//! runtime installs its own (WebKit on macOS) as its loop starts, so the
//! views stay free of any platform code, and tests install a fake.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_page_backend);
const mod = @import("module.zig");

/// One platform web view's operations. Every function runs on the UI thread
/// and takes the native handle `create` returned. The native page reports
/// back through the `WebPage` it was made for: `WebPage.update` on a change
/// of address, title, history or failure, `WebPage.receive` for a bridge
/// message.
pub const WebPageBackend = struct {
    const Self = @This();

    /// Why this platform cannot show a web page yet, or null when it can. A
    /// backend that sets it never has `create` called: its pages report this
    /// text as their failure.
    unsupported: ?[]const u8 = null,

    /// Makes a native page with nothing loaded, which reports to `page`, or
    /// returns null when the platform refuses.
    create: *const fn (page: *mod.WebPage) ?*anyopaque,

    /// Takes the page's view out of the window and frees the native page.
    destroy: *const fn (handle: *anyopaque) void,

    /// The platform view to place (an `NSView` on macOS), owned by the handle.
    view: *const fn (handle: *anyopaque) ?*anyopaque,

    /// Sets the origin the bridges hear: the main frame of `url`'s origin
    /// only (for a URL with no host, `url` itself). Before it, they hear none.
    trust: *const fn (handle: *anyopaque, url: [:0]const u8) void,

    /// Loads `url`; false when it is not an address the platform can parse.
    load: *const fn (handle: *anyopaque, url: [:0]const u8) bool,

    /// Goes back one page in the history, if it can.
    go_back: *const fn (handle: *anyopaque) void,

    /// Goes forward one page in the history, if it can.
    go_forward: *const fn (handle: *anyopaque) void,

    /// Loads the page showing again.
    reload: *const fn (handle: *anyopaque) void,

    /// Lets the page post messages under `name` (replacing one of that name).
    add_bridge: *const fn (handle: *anyopaque, name: [:0]const u8) void,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
