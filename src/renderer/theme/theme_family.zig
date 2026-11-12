//! The catalog of built-in theme families and the logic that resolves one to a
//! concrete `Theme` for the current OS color scheme.
//!
//! A *family* (macOS, Windows 10, …) ships a light and a dark palette.
//! `forScheme` picks the right one, so the app can wire the OS appearance
//! (`App.systemTheme()`) straight through.

const std = @import("std");
const log = std.log.scoped(.ziggui_theme_family);
const mod = @import("module.zig");

/// The built-in theme families.
pub const ThemeFamily = enum {
    const Self = @This();

    /// macOS 26 Liquid Glass.
    macos,
    /// Windows 10 flat.
    windows10,
    /// Windows 2000 chiseled.
    win2000,
    /// KDE Plasma Breeze.
    kde,
    /// Google Material.
    mui,

    /// All families, in display order (handy for building a theme switcher).
    pub const all = [_]Self{ .macos, .windows10, .win2000, .kde, .mui };

    /// A human-readable name for menus/switchers.
    ///
    /// - `self`: the family.
    /// - Returns: the name.
    pub fn displayName(self: *const Self) []const u8 {
        return switch (self.*) {
            .macos => "macOS",
            .windows10 => "Windows 10",
            .win2000 => "Windows 2000",
            .kde => "KDE Plasma",
            .mui => "Material",
        };
    }

    /// Resolve the family to a concrete `Theme` for `scheme`.
    ///
    /// - `self`: the family.
    /// - `scheme`: light or dark.
    /// - Returns: the theme.
    pub fn forScheme(self: *const Self, scheme: mod.ColorScheme) mod.Theme {
        const dark = scheme == .dark;
        return switch (self.*) {
            .macos => if (dark) mod.MacosTheme.dark else mod.MacosTheme.light,
            .windows10 => if (dark) mod.Windows10Theme.dark else mod.Windows10Theme.light,
            .win2000 => if (dark) mod.Win2000Theme.dark else mod.Win2000Theme.light,
            .kde => if (dark) mod.KdeTheme.dark else mod.KdeTheme.light,
            .mui => if (dark) mod.MuiTheme.dark else mod.MuiTheme.light,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "registry: every family has a dark palette" {
    for (ThemeFamily.all) |family| try std.testing.expectEqual(mod.ColorScheme.dark, family.forScheme(.dark).scheme);
}

test "registry: macOS follows the requested scheme" {
    try std.testing.expectEqual(mod.ColorScheme.dark, ThemeFamily.macos.forScheme(.dark).scheme);
    try std.testing.expectEqual(mod.ColorScheme.light, ThemeFamily.macos.forScheme(.light).scheme);
}

test "registry: every family resolves and names itself" {
    for (ThemeFamily.all) |family| {
        const theme = family.forScheme(.light);
        try std.testing.expect(theme.name.len > 0);
        try std.testing.expect(family.displayName().len > 0);
    }
}

test "registry: each family draws its own title bar, with text that reads on it" {
    for (ThemeFamily.all) |family| {
        for ([_]mod.ColorScheme{ .light, .dark }) |scheme| {
            const theme = family.forScheme(scheme);
            var canvas = mod.Canvas.init(std.testing.allocator);
            defer canvas.deinit();
            const rect = mod.Rect{ .x = 0, .y = 0, .width = 100, .height = 32 };
            try theme.drawTitleBar(.{ .canvas = &canvas, .palette = &theme.colors, .metrics = &theme.metrics, .scheme = theme.scheme }, rect);
            var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 100, 32);
            defer framebuffer.deinit();
            framebuffer.clear(mod.Color.fromRgb8(255, 0, 255));
            try mod.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
            // The whole bar is painted (no magenta left), and its text contrasts with it.
            const bar = framebuffer.at(10, 10);
            try std.testing.expect(!bar.approxEql(mod.Color.fromRgb8(255, 0, 255), 0.05));
            const text = theme.titleBarForeground();
            try std.testing.expect(@abs(text.luminance() - bar.luminance()) > 0.3);
        }
    }
    // Windows 2000's caption runs navy to sky blue, white text on it.
    const classic = ThemeFamily.win2000.forScheme(.light);
    try std.testing.expect(classic.titleBarForeground().approxEql(mod.Color.white, 0.01));
    // Material's bar is the accent, with on-accent text.
    const material = ThemeFamily.mui.forScheme(.dark);
    try std.testing.expect(material.titleBarForeground().approxEql(material.colors.on_accent, 0.01));
}
