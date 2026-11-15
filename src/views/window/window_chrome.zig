//! The pieces of a window's frame every app draws the same way: the macOS top
//! band clear of the traffic lights, the drawn title bar elsewhere (the app's
//! icon and menus, the centered title, the window buttons), and how its menu
//! bar spells a shortcut.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_chrome);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A window's frame: its measures and the views that make it.
pub const WindowChrome = struct {
    const Self = @This();

    /// The top band's height: on macOS the window's drag area.
    pub const top_bar_height: f32 = 40;
    /// The traffic lights' width, which the top band's text keeps clear of.
    pub const traffic_lights_width: f32 = 76;
    /// Below this window width a drawn title bar folds its menus into one `☰`.
    pub const fold_width: f32 = 640;
    /// The title bar icon's side, in points.
    pub const icon_side: f32 = 16;

    /// The top band on macOS (or a plain top band elsewhere): the app's title view, centered between the insets.
    ///
    /// - `title`: the title, styled as the app wants (cleaned for drawing by the app).
    /// - `mac`: inset for the traffic lights.
    /// - Returns: the band, `top_bar_height` tall.
    pub fn topBar(title: mod.View, mac: bool) mod.View {
        const inset: f32 = if (mac) traffic_lights_width else 12;
        return title.frameMaxWidth().paddingInsets(.{ .leading = inset, .trailing = inset }).frameHeight(top_bar_height).frameMaxWidth();
    }

    /// The title bar an app draws off macOS: its icon and menus, the title centered, the window buttons.
    ///
    /// - `icon`: the app's icon pixels, drawn at `icon_side`.
    /// - `menus`: the menu bar.
    /// - `title`: the centered text; cleaned for drawing.
    /// - `buttons`: the window buttons.
    /// - Returns: the bar.
    pub fn titleBar(icon: renderer.Image, menus: mod.View, title: []const u8, buttons: mod.View) mod.View {
        return mod.TitleBar(
            mod.HStack(.{
                mod.Image(icon).scaledToFit().frame(icon_side, icon_side),
                menus,
            }).spacing(4).paddingInsets(.{ .leading = 10 }),
            mod.DisplayText.clean(mod.BuildScope.shared().allocator(), title),
            buttons,
        );
    }

    /// How a drawn menu bar spells an entry's key: `⌘X` as `ctrl+X`, a bare shortcut letter as `ctrl+<key>`.
    ///
    /// - `allocator`: owns the text.
    /// - `hint`: the entry's key as the app writes it (`⌘R`, `d`), or empty.
    /// - `shortcut`: the entry's command shortcut, or empty.
    /// - Returns: the key's text, `hint` itself when it needs no change; propagates allocation failure.
    pub fn keyText(allocator: std.mem.Allocator, hint: []const u8, shortcut: []const u8) ![]const u8 {
        const command = "⌘";
        if (std.mem.startsWith(u8, hint, command)) {
            const rest = try std.ascii.allocUpperString(allocator, hint[command.len..]);
            return allocator.print("ctrl+{s}", .{rest});
        }
        if (hint.len > 0 or shortcut.len == 0) return hint;
        const key = try std.ascii.allocUpperString(allocator, shortcut);
        return allocator.print("ctrl+{s}", .{key});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(WindowChrome);
    // Nothing here does I/O to trace.
    _ = log;
}

test "window chrome spells ⌘ as ctrl+, and a bare shortcut as ctrl+<key>" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqualStrings("ctrl+R", try WindowChrome.keyText(allocator, "⌘R", ""));
    try std.testing.expectEqualStrings("ctrl+,", try WindowChrome.keyText(allocator, "", ","));
    try std.testing.expectEqualStrings("e", try WindowChrome.keyText(allocator, "e", "e"));
}
