//! What an app's platform layer answers when there is no window: tests and
//! headless `--screenshot` runs. Plain functions, to fill an app's function
//! pointers (GUIDESIGN B.1.c).

const std = @import("std");
const log = std.log.scoped(.ziggui_headless_platform);
const mod = @import("module.zig");

/// The window system's side as a headless run sees it: light, no desktop
/// entry, nothing to do or open, and a clipboard of its own in memory.
pub const HeadlessPlatform = struct {
    const Self = @This();

    /// The in-memory clipboard's room, in bytes.
    const clipboard_max: usize = 4096;
    /// The in-memory clipboard, process-wide, as the real one is.
    // SAFETY: `setClipboardText` writes the first `clipboard_length` bytes before `clipboardText` reads them.
    var clipboard: [clipboard_max]u8 = undefined;
    /// How much of `clipboard` holds text.
    var clipboard_length: usize = 0;

    /// Always light, so headless frames compare.
    ///
    /// - Returns: false.
    pub fn dark() bool {
        return false;
    }

    /// No desktop entry to manage.
    ///
    /// - Returns: `.unsupported`.
    pub fn entryState() mod.DesktopEntryState {
        return .unsupported;
    }

    /// Declines: nothing was installed, removed, maximized, opened or shown.
    ///
    /// - Returns: false.
    pub fn no() bool {
        return false;
    }

    /// Does nothing: there is no window to quit, minimize or maximize.
    pub fn nothing() void {}

    /// Declines to show a file: there is no file manager.
    ///
    /// - `path`: the file.
    /// - Returns: false.
    pub fn reveal(path: []const u8) bool {
        _ = path;
        return false;
    }

    /// The in-memory clipboard's text.
    ///
    /// - `allocator`: owns the copy.
    /// - Returns: a copy, or null when it is empty or the copy fails (logged).
    pub fn clipboardText(allocator: std.mem.Allocator) ?[]u8 {
        if (Self.clipboard_length == 0) return null;
        return allocator.dupe(u8, Self.clipboard[0..Self.clipboard_length]) catch |err| {
            log.warn("the headless clipboard was not copied [{t}]", .{err});
            return null;
        };
    }

    /// Puts text on the in-memory clipboard, cut at its room.
    ///
    /// - `text`: the text.
    pub fn setClipboardText(text: []const u8) void {
        Self.clipboard_length = @min(text.len, clipboard_max);
        @memcpy(Self.clipboard[0..Self.clipboard_length], text[0..Self.clipboard_length]);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(HeadlessPlatform);
}

test "headless platform keeps clipboard text in memory, and declines the rest" {
    HeadlessPlatform.setClipboardText("https://example.com/a");
    const back = HeadlessPlatform.clipboardText(std.testing.allocator).?;
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualStrings("https://example.com/a", back);
    try std.testing.expect(!HeadlessPlatform.dark());
    try std.testing.expect(!HeadlessPlatform.reveal("/tmp/a"));
    try std.testing.expectEqual(mod.DesktopEntryState.unsupported, HeadlessPlatform.entryState());
}
