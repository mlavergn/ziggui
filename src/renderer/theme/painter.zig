//! A theme's drawing strategy: the vtable of chrome-drawing functions.

const std = @import("std");
const log = std.log.scoped(.ziggui_painter);
const mod = @import("module.zig");

/// A vtable of chrome-drawing functions — the heart of a theme's identity. Each
/// draws only decoration (fills, borders, bevels, gradients); the view layer
/// draws labels, lays things out, and registers hit regions around them.
pub const Painter = struct {
    const Self = @This();

    /// Draw a push-button's background/border in `rect`, then return the color
    /// its label should be drawn in (so a theme controls both at once).
    button: *const fn (surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color,
    /// Draw a text-input surface (background + border) with the given corner
    /// `radius`; `state.focused` selects the focused appearance.
    field: *const fn (surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void,
    /// Draw the recessed track behind a whole segmented control.
    segmented_track: *const fn (surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void,
    /// Draw the highlight chip behind the selected segment (`segment`), then
    /// return the color its label should be drawn in (an accent-filled chip
    /// needs `on_accent` text; a pale chip keeps `label`).
    segmented_selection: *const fn (surface: mod.Surface, segment: mod.Rect) std.mem.Allocator.Error!mod.Color,
    /// Draw an on/off switch track. The sliding knob is drawn separately by
    /// `switch_knob` (the view layer owns the knob *geometry* and calls both in
    /// sequence).
    switch_track: *const fn (surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void,
    /// Draw the toggle's sliding thumb within `knob` (a square bounding the
    /// circular knob); `on` lets a theme tint it differently per state.
    switch_knob: *const fn (surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void,
    /// Draw a slider: the unfilled `track`, the filled portion (`track` scaled by
    /// `fraction` in 0..1), and the handle within `knob`.
    slider: *const fn (surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void,
    /// Draw the +/- control box chrome (fill + border/bevel); the divider and
    /// glyph lines are drawn by the view layer.
    stepper_box: *const fn (surface: mod.Surface, rect: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void,
    /// Draw a determinate progress bar: the track, then the filled portion
    /// (`rect` scaled by `fraction` in 0..1).
    progress: *const fn (surface: mod.Surface, rect: mod.Rect, fraction: f32) std.mem.Allocator.Error!void,
    /// Draw the frame (background + border/bevel) for a floating panel with the
    /// given corner `radius`: `kind` distinguishes modals (sheets/alerts) from
    /// popovers/menus so a theme can render them as different materials.
    panel: *const fn (surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void,
    /// Draw a freestanding glass surface behind arbitrary content (the
    /// `.glassEffect()` modifier — toolbar pills, floating bars, inset
    /// sidebars). Optional: themes without a glass identity fall back to a
    /// translucent `control_track` fill with a `control_border` ring.
    glass_surface: ?*const fn (surface: mod.Surface, rect: mod.Rect, radius: f32) std.mem.Allocator.Error!void = null,
    /// Draw the background of an app-drawn title bar across `rect` (a window
    /// with `Config.custom_titlebar`, off macOS). Optional: unset, the window
    /// background with a hairline along the bottom. See `Theme.drawTitleBar`.
    title_bar: ?*const fn (surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void = null,
    /// The color text and glyphs take on that title bar. Optional: unset,
    /// `label`. Pure, so composed views read it at build time
    /// (`Theme.titleBarForeground`).
    title_bar_foreground: ?*const fn (palette: *const mod.Palette) mod.Color = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
