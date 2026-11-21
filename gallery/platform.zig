const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_platform);
const ziggui = @import("ziggui");

/// What a system file dialog left: nothing yet, a cancel, or the path picked.
pub const FileDialogOutcome = union(enum) {
    const Self = @This();

    /// No dialog finished since the last take (still up, or none shown).
    none,

    /// The user cancelled (or the dialog failed).
    canceled,

    /// The path the user picked; the taker owns it.
    picked: []u8,
};

/// What the gallery asks of the window it runs in: the window buttons, the
/// quit, the animator, and the system's open and save panels. `main.zig`
/// fills the hooks with `ziggui.App`'s and `ziggui.FileDialog`'s calls;
/// headless (the tests, `--screenshot`) they stay null, and each call does
/// what a window that is not there would.
pub const Platform = struct {
    const Self = @This();

    /// Minimizes the window.
    minimize_fn: ?*const fn () void = null,

    /// Maximizes the window, or restores it when it is maximized.
    toggle_maximized_fn: ?*const fn () void = null,

    /// Whether the window is maximized.
    ///
    /// - Returns: true while the window is maximized.
    is_maximized_fn: ?*const fn () bool = null,

    /// Asks to close the window, as its own close button does (the quit handler may refuse).
    request_close_fn: ?*const fn () void = null,

    /// Ends the loop without asking.
    quit_fn: ?*const fn () void = null,

    /// The running loop's animator, while there is one.
    ///
    /// - Returns: the window's animator, or null before the loop runs.
    animator_fn: ?*const fn () ?*ziggui.Animator = null,

    /// Shows the system's open-file panel.
    ///
    /// - `location`: the folder it starts in.
    /// - Returns: false when a dialog is already up.
    open_file_fn: ?*const fn (location: [:0]const u8) bool = null,

    /// Shows the system's save panel.
    ///
    /// - `location`: the folder and the name its field starts with.
    /// - Returns: false when a dialog is already up.
    save_file_fn: ?*const fn (location: [:0]const u8) bool = null,

    /// Takes the outcome of the dialog last shown, once.
    ///
    /// - `allocator`: owns a picked path's copy.
    /// - Returns: the outcome, `.none` while the dialog is still up.
    take_file_fn: ?*const fn (allocator: std.mem.Allocator) FileDialogOutcome = null,

    /// Minimizes the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn minimize(self: *const Self) void {
        if (self.minimize_fn) |hook| hook();
    }

    /// Maximizes or restores the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn toggleMaximized(self: *const Self) void {
        if (self.toggle_maximized_fn) |hook| hook();
    }

    /// Reports whether the window is maximized.
    ///
    /// - `self`: the platform.
    /// - Returns: true when it is; false with no window.
    pub fn isMaximized(self: *const Self) bool {
        const hook = self.is_maximized_fn orelse return false;
        return hook();
    }

    /// Asks to close the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn requestClose(self: *const Self) void {
        if (self.request_close_fn) |hook| hook();
    }

    /// Ends the loop, if one runs.
    ///
    /// - `self`: the platform.
    pub fn quit(self: *const Self) void {
        if (self.quit_fn) |hook| hook();
    }

    /// The animator, while a loop runs to drive it.
    ///
    /// - `self`: the platform.
    /// - Returns: the animator, or null headless.
    pub fn animator(self: *const Self) ?*ziggui.Animator {
        const hook = self.animator_fn orelse return null;
        return hook();
    }

    /// Shows the system's open-file panel, if there is a window to show it over.
    ///
    /// - `self`: the platform.
    /// - `location`: the folder it starts in; kept until its outcome is taken.
    /// - Returns: true when it showed; false headless or while another is up.
    pub fn openFile(self: *const Self, location: [:0]const u8) bool {
        const hook = self.open_file_fn orelse return false;
        return hook(location);
    }

    /// Shows the system's save panel, if there is a window to show it over.
    ///
    /// - `self`: the platform.
    /// - `location`: the folder and starting name; kept until its outcome is taken.
    /// - Returns: true when it showed; false headless or while another is up.
    pub fn saveFile(self: *const Self, location: [:0]const u8) bool {
        const hook = self.save_file_fn orelse return false;
        return hook(location);
    }

    /// Takes the outcome of the dialog last shown, once.
    ///
    /// - `self`: the platform.
    /// - `allocator`: owns a picked path's copy.
    /// - Returns: the outcome; `.none` headless or while it is still up.
    pub fn takeFile(self: *const Self, allocator: std.mem.Allocator) FileDialogOutcome {
        const hook = self.take_file_fn orelse return .none;
        return hook(allocator);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Platform);
    // Nothing here does I/O to trace.
    _ = log;
}

test "an empty platform does what a missing window would" {
    const platform: Platform = .{};
    platform.minimize();
    platform.toggleMaximized();
    platform.requestClose();
    platform.quit();
    try std.testing.expect(!platform.isMaximized());
    try std.testing.expectEqual(@as(?*ziggui.Animator, null), platform.animator());
    try std.testing.expect(!platform.openFile("/"));
    try std.testing.expect(!platform.saveFile("/Untitled.txt"));
    try std.testing.expect(platform.takeFile(std.testing.allocator) == .none);
}

test "a filled platform calls its hooks" {
    const Probe = struct {
        const Self = @This();

        var calls: u32 = 0;

        /// Counts a call.
        fn count() void {
            Self.calls += 1;
        }

        /// Answers yes.
        ///
        /// - Returns: true.
        fn yes() bool {
            return true;
        }
    };
    const platform: Platform = .{
        .minimize_fn = Probe.count,
        .toggle_maximized_fn = Probe.count,
        .request_close_fn = Probe.count,
        .quit_fn = Probe.count,
        .is_maximized_fn = Probe.yes,
    };
    platform.minimize();
    platform.toggleMaximized();
    platform.requestClose();
    platform.quit();
    try std.testing.expectEqual(@as(u32, 4), Probe.calls);
    try std.testing.expect(platform.isMaximized());
}
