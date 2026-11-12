//! An app's accent, a setting: the brand's orange or one of macOS's, and the theme drawn in it.

const std = @import("std");
const log = std.log.scoped(.ziggui_accent);
const renderer = @import("renderer");

/// The color an app draws its accent in, a setting (GUIDESIGN E.2.i): its
/// brand's safety orange by default, or one of macOS's accent colors.
pub const Accent = enum {
    const Self = @This();

    /// Safety orange (#FF5F00), the brand's.
    orange,
    /// Blue.
    blue,
    /// Purple.
    purple,
    /// Pink.
    pink,
    /// Red.
    red,
    /// Yellow.
    yellow,
    /// Green.
    green,
    /// Graphite.
    graphite,

    /// Every accent, in a Settings sheet's order.
    pub const all = [_]Self{ .orange, .blue, .purple, .pink, .red, .yellow, .green, .graphite };

    /// The accent as a Settings sheet names it.
    ///
    /// - `self`: the accent.
    /// - Returns: its name.
    pub fn displayName(self: *const Self) []const u8 {
        return switch (self.*) {
            .orange => "Orange",
            .blue => "Blue",
            .purple => "Purple",
            .pink => "Pink",
            .red => "Red",
            .yellow => "Yellow",
            .green => "Green",
            .graphite => "Graphite",
        };
    }

    /// The accent's color.
    ///
    /// - `self`: the accent.
    /// - Returns: the color.
    pub fn color(self: *const Self) renderer.Color {
        return switch (self.*) {
            .orange => renderer.Color.fromRgb8(0xFF, 0x5F, 0x00),
            .blue => renderer.Color.fromRgb8(0x00, 0x6B, 0xE6),
            .purple => renderer.Color.fromRgb8(0x94, 0x44, 0xD2),
            .pink => renderer.Color.fromRgb8(0xFF, 0x2D, 0x78),
            .red => renderer.Color.fromRgb8(0xFF, 0x3B, 0x30),
            .yellow => renderer.Color.fromRgb8(0xFF, 0xCC, 0x00),
            .green => renderer.Color.fromRgb8(0x28, 0xC8, 0x40),
            .graphite => renderer.Color.fromRgb8(0x8E, 0x8E, 0x93),
        };
    }

    /// Text and icons drawn on the accent.
    ///
    /// - `self`: the accent.
    /// - Returns: white, as on macOS, but black on the yellow and the green.
    pub fn onColor(self: *const Self) renderer.Color {
        // White barely shows on the yellow and the green (about 1.5:1 and 2:1).
        return switch (self.*) {
            .yellow, .green => renderer.Color.black,
            else => renderer.Color.white,
        };
    }

    /// A theme family's theme in this accent, its macOS dark on true black:
    /// the theme provider's rules (GUIDESIGN E.2.i, E.2.j), never a view's.
    ///
    /// - `self`: the accent.
    /// - `family`: the theme family.
    /// - `dark`: dark rather than light.
    /// - Returns: the theme.
    pub fn theme(self: *const Self, family: renderer.ThemeFamily, dark: bool) renderer.Theme {
        var themed = family.forScheme(if (dark) .dark else .light);
        if (dark and family == .macos) {
            // True black, where macOS's own dark is a washed-out grey; controls a step above.
            themed.colors.window_background = renderer.Color.black;
            themed.colors.sidebar_background = renderer.Color.black;
            themed.colors.secondary_background = renderer.Color.fromRgb8(12, 12, 12);
            themed.colors.control_background = renderer.Color.fromRgb8(24, 24, 24);
            themed.colors.glass = renderer.Color.fromRgb8(24, 24, 24).withAlpha(0.88);
        }
        themed.colors.accent = self.color();
        themed.colors.selection = self.color();
        themed.colors.on_accent = self.onColor();
        return themed;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "every family draws in the accent, white on it but on the yellow and the green" {
    for (renderer.ThemeFamily.all) |family| {
        for ([_]bool{ false, true }) |dark| {
            for (Accent.all) |accent| {
                const themed = accent.theme(family, dark);
                try std.testing.expectEqual(accent.color(), themed.colors.accent);
                try std.testing.expectEqual(accent.color(), themed.colors.selection);
                try std.testing.expectEqual(accent.onColor(), themed.colors.on_accent);
            }
        }
    }
    try std.testing.expectEqual(renderer.Color.white, Accent.orange.onColor());
    try std.testing.expectEqual(renderer.Color.black, Accent.yellow.onColor());
}

test "the macOS family's dark draws on black, its light and other families' dark as their own" {
    try std.testing.expectEqual(renderer.Color.black, Accent.orange.theme(.macos, true).colors.window_background);
    try std.testing.expectEqual(renderer.ThemeFamily.macos.forScheme(.light).colors.window_background, Accent.orange.theme(.macos, false).colors.window_background);
    try std.testing.expectEqual(renderer.ThemeFamily.kde.forScheme(.dark).colors.window_background, Accent.orange.theme(.kde, true).colors.window_background);
}
