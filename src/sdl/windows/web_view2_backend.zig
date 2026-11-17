//! The Windows `WebPageBackend`: not implemented yet. Its pages report
//! `unsupported` as their failure, and `WebView` draws its placeholder.
//!
//! The intended engine is WebView2 (Windows 10+, the Evergreen runtime):
//! an `ICoreWebView2Controller` in a child window kept over ziggui's
//! surface, `AddWebMessageReceived`/`WebMessageReceived` for the bridges,
//! `SourceChanged`, `DocumentTitleChanged` and `HistoryChanged` for
//! `WebPage.update`, and `NavigationCompleted` (`IsSuccess`, `WebErrorStatus`)
//! for the failure. The loader (`WebView2Loader.dll`) is to be loaded at run
//! time, so apps without a web view never need it.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_view2_backend);
const views = @import("views");

/// The Windows web view behind every `WebPage`: a stub for now.
pub const WebView2Backend = struct {
    const Self = @This();

    /// The backend `WebPage`s are made with: it refuses, saying why.
    pub const backend: views.WebPageBackend = .{
        .unsupported = "Web pages are not implemented on Windows yet.",
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

test "the Windows web view refuses, saying why" {
    try std.testing.expect(WebView2Backend.backend.unsupported != null);
}
