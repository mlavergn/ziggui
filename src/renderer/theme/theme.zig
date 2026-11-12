//! Theme: the design-token vocabulary *and* drawing strategy that give a ziggui
//! app its look. A `Theme` bundles three things:
//!
//!   * a **`Palette`** of semantic color roles (resolved for one `ColorScheme`),
//!   * a typographic scale and layout **`Metrics`**, and
//!   * a **`Painter`** — a small vtable of functions that draw the *chrome* of
//!     the theme-defining controls (buttons, switches, fields, segmented
//!     controls).
//!
//! Splitting the palette from the painter is what lets very different looks
//! coexist: macOS draws translucent "liquid glass" with gradient sheens, while
//! Windows 2000 chisels raised/sunken bevels from the same token vocabulary.
//! Components read tokens and call the painter rather than hard-coding a look,
//! so the whole UI restyles by swapping one `Theme`.
//!
//! A `Painter` depends only on the renderer (`Canvas`, `Color`, geometry) and
//! these tokens — never on the view layer — so the two compose without a
//! dependency cycle: the view layer owns text, layout, and interaction; the
//! painter owns decoration.
//!
//! Concrete themes live alongside this file (`MacosTheme`, `Win2000Theme`,
//! `Windows10Theme`, `KdeTheme`, `MuiTheme`); `ThemeFamily.forScheme` selects
//! one for the OS color scheme.

const std = @import("std");
const log = std.log.scoped(.ziggui_theme);
const mod = @import("module.zig");

/// The named text styles of a `Typography`, as `Theme.font` takes them.
pub const TextStyleName = enum {
    const Self = @This();

    /// `Typography.large_title`.
    largeTitle,
    /// `Typography.title`.
    title,
    /// `Typography.title2`.
    title2,
    /// `Typography.title3`.
    title3,
    /// `Typography.headline`.
    headline,
    /// `Typography.body`.
    body,
    /// `Typography.callout`.
    callout,
    /// `Typography.subheadline`.
    subheadline,
    /// `Typography.footnote`.
    footnote,
    /// `Typography.caption`.
    caption,
    /// `Typography.caption2`.
    caption2,
};

/// A fully-resolved theme for one `ColorScheme`: a palette, a type scale, layout
/// metrics, and the painter that gives it its look. Built per scheme by the
/// concrete theme structs; `ThemeFamily.forScheme` picks one for the OS
/// appearance.
pub const Theme = struct {
    const Self = @This();

    /// Human-readable name of the theme family (e.g. "macOS", "Windows 2000").
    name: []const u8 = "ziggui",
    /// The color scheme the palette is resolved for.
    scheme: mod.ColorScheme,
    /// The palette.
    colors: mod.Palette,
    /// The type scale.
    typography: mod.Typography,
    /// The layout metrics.
    metrics: mod.Metrics = .{},
    /// The chrome painter.
    painter: mod.Painter,

    /// The library-wide default theme (macOS light).
    pub const default = mod.MacosTheme.light;

    /// Resolve a named text style.
    ///
    /// - `self`: the theme.
    /// - `name`: the style's name.
    /// - Returns: the style.
    pub fn font(self: *const Self, name: TextStyleName) mod.TextStyle {
        return switch (name) {
            .largeTitle => self.typography.large_title,
            .title => self.typography.title,
            .title2 => self.typography.title2,
            .title3 => self.typography.title3,
            .headline => self.typography.headline,
            .body => self.typography.body,
            .callout => self.typography.callout,
            .subheadline => self.typography.subheadline,
            .footnote => self.typography.footnote,
            .caption => self.typography.caption,
            .caption2 => self.typography.caption2,
        };
    }

    /// Draw an app-drawn title bar's background (`Painter.title_bar`, else the
    /// window background with a hairline along the bottom).
    ///
    /// - `self`: the theme.
    /// - `surface`: what to draw on.
    /// - `rect`: the bar.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawTitleBar(self: *const Self, surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        if (self.painter.title_bar) |draw| return draw(surface, rect);
        try surface.fill(rect, 0, surface.palette.window_background);
        try surface.bottomHairline(rect);
    }

    /// The color text and glyphs take on an app-drawn title bar
    /// (`Painter.title_bar_foreground`, else `label`).
    ///
    /// - `self`: the theme.
    /// - Returns: the color.
    pub fn titleBarForeground(self: *const Self) mod.Color {
        if (self.painter.title_bar_foreground) |foreground| return foreground(&self.colors);
        return self.colors.label;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Theme: font() resolves named styles" {
    const theme = mod.MacosTheme.light;
    try std.testing.expectEqual(theme.typography.body, theme.font(.body));
    try std.testing.expectEqual(theme.typography.large_title, theme.font(.largeTitle));
}

test "Theme: the default is macOS light" {
    try std.testing.expectEqual(mod.ColorScheme.light, Theme.default.scheme);
}
