//! Themes: the token vocabulary (palette, typography, metrics), the painter
//! vtable, and the built-in theme families.

const std = @import("std");
const log = std.log.scoped(.ziggui_theme_module);

/// Light or dark.
pub const ColorScheme = @import("color_scheme.zig").ColorScheme;
/// A font weight.
pub const FontWeight = @import("font_weight.zig").FontWeight;
/// A point size, weight and line-height multiple.
pub const TextStyle = @import("text_style.zig").TextStyle;
/// The semantic appearance of a control.
pub const Role = @import("role.zig").Role;
/// What a floating panel is for.
pub const PanelKind = @import("panel_kind.zig").PanelKind;
/// The interaction state of a control.
pub const ControlState = @import("control_state.zig").ControlState;
/// Semantic color roles for one color scheme.
pub const Palette = @import("palette.zig").Palette;
/// A theme's text styles.
pub const Typography = @import("typography.zig").Typography;
/// A theme's spacing, sizing, and radius metrics.
pub const Metrics = @import("metrics.zig").Metrics;
/// Everything a painter needs to draw chrome.
pub const Surface = @import("surface.zig").Surface;
/// A theme's vtable of chrome-drawing functions.
pub const Painter = @import("painter.zig").Painter;
/// The named text styles `Theme.font` takes.
pub const TextStyleName = @import("theme.zig").TextStyleName;
/// A fully-resolved theme for one color scheme.
pub const Theme = @import("theme.zig").Theme;
/// The built-in theme families.
pub const ThemeFamily = @import("theme_family.zig").ThemeFamily;
/// The macOS Liquid Glass themes.
pub const MacosTheme = @import("macos_theme.zig").MacosTheme;
/// The Windows 2000 chiseled themes.
pub const Win2000Theme = @import("win2000_theme.zig").Win2000Theme;
/// The Windows 10 flat themes.
pub const Windows10Theme = @import("windows10_theme.zig").Windows10Theme;
/// The KDE Plasma Breeze themes.
pub const KdeTheme = @import("kde_theme.zig").KdeTheme;
/// The Material themes.
pub const MuiTheme = @import("mui_theme.zig").MuiTheme;

/// A 2D point (from the renderer).
pub const Point = @import("../module.zig").Point;
/// An axis-aligned rectangle (from the renderer).
pub const Rect = @import("../module.zig").Rect;
/// An RGBA color (from the renderer).
pub const Color = @import("../module.zig").Color;
/// A retained list of draw commands (from the renderer).
pub const Canvas = @import("../module.zig").Canvas;
/// A CPU pixel buffer (from the renderer).
pub const Framebuffer = @import("../module.zig").Framebuffer;
/// The CPU rasterizer (from the renderer).
pub const Rasterizer = @import("../module.zig").Rasterizer;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("color_scheme.zig");
    _ = @import("font_weight.zig");
    _ = @import("text_style.zig");
    _ = @import("role.zig");
    _ = @import("panel_kind.zig");
    _ = @import("control_state.zig");
    _ = @import("palette.zig");
    _ = @import("typography.zig");
    _ = @import("metrics.zig");
    _ = @import("surface.zig");
    _ = @import("painter.zig");
    _ = @import("theme.zig");
    _ = @import("theme_family.zig");
    _ = @import("macos_theme.zig");
    _ = @import("win2000_theme.zig");
    _ = @import("windows10_theme.zig");
    _ = @import("kde_theme.zig");
    _ = @import("mui_theme.zig");
}
