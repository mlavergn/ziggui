//! A plain status icon whose click runs a callback, so the app can open its
//! own popover panel: an NSStatusItem on macOS, a notification-area icon on
//! Windows and a StatusNotifierItem on Linux.

const std = @import("std");
const log = std.log.scoped(.ziggui_status_item);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The status icon (no menu attached). One per process (`shared`).
pub const StatusItem = struct {
    const Self = @This();

    /// Linux: the click callback, run on the UI loop by `takeLinuxClick`.
    linux_callback: ?views.Callback = null,

    /// The process's status item.
    var shared_item: Self = .{};

    /// The process's status item.
    ///
    /// - Returns: the shared status item.
    pub fn shared() *Self {
        return &shared_item;
    }

    /// Creates the status icon; its click (either button) runs `on_click`.
    /// `rgba` is the HiDPI (2x) bitmap; on macOS the icon shows at half its
    /// pixel size in points (36 px → 18 pt, the usual menu-bar glyph).
    ///
    /// - `self`: the status item.
    /// - `rgba`: the icon, row-major RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    /// - `tooltip`: the hover text.
    /// - `on_click`: runs on a click.
    /// - Returns: false on other platforms and when the OS has no tray to
    ///   reach; callers fall back to `MenuBarExtra`.
    pub fn create(self: *Self, rgba: []const u8, width: c_int, height: c_int, tooltip: [:0]const u8, on_click: views.Callback) bool {
        mod.App.shared().beforeSdlInit();
        _ = sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO);
        switch (mod.os_tag) {
            .macos => return mod.Cocoa.shared().createStatusItem(rgba, width, height, tooltip, on_click),
            .windows => return mod.Win32.shared().createStatusItem(rgba, width, height, tooltip, on_click),
            .linux => {
                if (!mod.StatusNotifier.shared().create(std.heap.c_allocator, rgba, width, height, tooltip)) return false;
                self.linux_callback = on_click;
                return true;
            },
            else => return false,
        }
    }

    /// Removes the status icon (macOS and Windows).
    ///
    /// - `self`: the status item.
    pub fn destroy(self: *const Self) void {
        _ = self;
        switch (mod.os_tag) {
            .macos => mod.Cocoa.shared().destroyStatusItem(),
            .windows => mod.Win32.shared().destroyStatusItem(),
            else => {},
        }
    }

    /// Linux: runs the click callback for a click the D-Bus thread handed
    /// over, anchoring the panel where it happened. The event loop calls it
    /// each iteration.
    ///
    /// - `self`: the status item.
    pub fn takeLinuxClick(self: *const Self) void {
        if (mod.os_tag != .linux) return;
        const at = mod.StatusNotifier.shared().takeClick() orelse return;
        const callback = self.linux_callback orelse return;
        const panel = mod.Panel.shared();
        if (!panel.statusClickCounts()) return;
        panel.click_at = at;
        defer panel.click_at = null;
        callback.call();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(StatusItem);
    // Nothing here does I/O to trace.
    _ = log;
}
