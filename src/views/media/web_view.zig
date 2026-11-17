//! A web page's view in the view tree (SwiftUI's `WebView(page)`).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_web_view);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Shows `page` where layout puts it: the platform web view, placed as a
/// `NativeView` (over the window's surface, hidden while a sheet, alert,
/// popover or menu is open, taking the keyboard on a click). It fills what
/// it is offered (size it with `.frame`). The first build makes the platform
/// page; headless, or where no platform web view exists, it is a placeholder
/// frame with a globe.
///
/// - `page`: the page; it must stay put while views show it.
/// - Returns: the view.
pub fn WebView(page: *mod.WebPage) mod.View {
    var view = mod.NativeView(page.nativeView());
    view.kind.nativeView.placeholder = .globe;
    return view;
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a web view with no platform page is a placeholder with a globe" {
    mod.WebPage.setBackend(null);
    var page = mod.WebPage.init(std.testing.allocator);
    defer page.deinit();
    const view = WebView(&page);
    try std.testing.expect(view.kind.nativeView.handle == null);
    try std.testing.expectEqual(renderer.Icon.globe, view.kind.nativeView.placeholder);
}
