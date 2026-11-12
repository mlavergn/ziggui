//! Material UI theme (Google Material Design): flat, ink-on-paper surfaces with
//! a bold primary color, 4px rounded corners, "contained" filled buttons, thin
//! tracks with circular thumbs, and outlined inputs. Light & dark follow the OS
//! appearance (Material's baseline `#1976d2` primary on light, `#90caf9` on
//! dark). The renderer has no box-shadow primitive, so elevation is suggested
//! with subtle tints/borders rather than drop shadows.

const std = @import("std");
const log = std.log.scoped(.ziggui_mui_theme);
const mod = @import("module.zig");

/// The Material theme family: its painter and its light and dark themes.
pub const MuiTheme = struct {
    const Self = @This();

    /// Roboto-ish scale: Material's type ramp, scaled for a desktop UI.
    const typography = mod.Typography{
        .large_title = .{ .size = 28, .weight = .medium },
        .title = .{ .size = 24, .weight = .regular },
        .title2 = .{ .size = 20, .weight = .medium },
        .title3 = .{ .size = 18, .weight = .regular },
        .headline = .{ .size = 16, .weight = .medium },
        .body = .{ .size = 14, .weight = .regular },
        .callout = .{ .size = 14, .weight = .regular },
        .subheadline = .{ .size = 13, .weight = .regular },
        .footnote = .{ .size = 12, .weight = .regular },
        .caption = .{ .size = 12, .weight = .regular },
        .caption2 = .{ .size = 11, .weight = .regular },
    };

    /// Material rounds by 4px and uses a 36px-tall control (the spec button height).
    const metrics = mod.Metrics{
        .corner_radius = 8,
        .control_corner_radius = 4,
        .panel_corner_radius = 4,
        .selection_corner_radius = 4,
        .window_corner_radius = 0,
        .control_height = 36,
        .hairline = 1,
    };

    /// The Material chrome painter.
    pub const painter = mod.Painter{
        .title_bar = Self.titleBar,
        .title_bar_foreground = Self.titleBarForeground,
        .button = Self.button,
        .field = Self.field,
        .segmented_track = Self.segmentedTrack,
        .segmented_selection = Self.segmentedSelection,
        .switch_track = Self.switchTrack,
        .switch_knob = Self.switchKnob,
        .slider = Self.slider,
        .stepper_box = Self.stepperBox,
        .progress = Self.progress,
        .panel = Self.panel,
    };

    /// Material light.
    pub const light = mod.Theme{
        .name = "Material",
        .scheme = .light,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(25, 118, 210), // Material primary (#1976d2)
            .label = mod.Color.black.withAlpha(0.87), // text primary
            .secondary_label = mod.Color.black.withAlpha(0.60),
            .tertiary_label = mod.Color.black.withAlpha(0.38),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(250, 250, 250), // grey 50
            .secondary_background = mod.Color.white,
            .control_background = mod.Color.white,
            .separator = mod.Color.black.withAlpha(0.12), // divider
            .selection = mod.Color.fromRgb8(25, 118, 210),
            .destructive = mod.Color.fromRgb8(211, 47, 47), // error (#d32f2f)
            .hover = mod.Color.black.withAlpha(0.04),
            .control_border = mod.Color.black.withAlpha(0.23), // outlined input border
            .glass = mod.Color.white.withAlpha(0.7),
            .control_track = mod.Color.black.withAlpha(0.38), // switch-off track (spec)
        },
    };

    /// Material dark.
    pub const dark = mod.Theme{
        .name = "Material",
        .scheme = .dark,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(144, 202, 249), // dark primary (#90caf9)
            .label = mod.Color.white,
            .secondary_label = mod.Color.white.withAlpha(0.70),
            .tertiary_label = mod.Color.white.withAlpha(0.50),
            .on_accent = mod.Color.black.withAlpha(0.87), // dark text on the light-blue primary
            .window_background = mod.Color.fromRgb8(18, 18, 18), // Material dark background
            .secondary_background = mod.Color.fromRgb8(30, 30, 30),
            .control_background = mod.Color.fromRgb8(30, 30, 30), // surface (#1e1e1e)
            .separator = mod.Color.white.withAlpha(0.12),
            .selection = mod.Color.fromRgb8(144, 202, 249),
            .destructive = mod.Color.fromRgb8(244, 67, 54), // error (#f44336)
            .hover = mod.Color.white.withAlpha(0.08),
            .control_border = mod.Color.white.withAlpha(0.23),
            .glass = mod.Color.fromRgb8(30, 30, 30).withAlpha(0.8),
            .control_track = mod.Color.white.withAlpha(0.3), // switch-off track (spec)
        },
    };

    // -------------------------------------------------------------------------
    // Painter — flat fills, a strong primary, circular thumbs
    // -------------------------------------------------------------------------

    /// `Painter.button`.
    fn button(surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color {
        // A "text button": label-only, no container.
        if (role == .plain) return surface.palette.accent;
        const radius = surface.metrics.control_corner_radius;
        if (state.disabled) {
            // Material disables to neutral grey (action.disabledBackground), not a
            // faded primary.
            try surface.fill(rect, radius, surface.palette.label.withAlpha(0.12));
            return surface.palette.label.withAlpha(0.38);
        }
        const base = if (role == .destructive) surface.palette.destructive else surface.palette.accent;
        // Material darkens the container on hover (an action-state overlay).
        const fill_color = if (state.hovered) base.darken(0.08) else base;
        try surface.fill(rect, radius, fill_color);
        return surface.palette.on_accent;
    }

    /// `Painter.field`.
    fn field(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void {
        // The Material "outlined" text field: a thin box that thickens and tints to
        // the primary color on focus.
        try surface.fill(rect, radius, surface.palette.control_background);
        const color = if (state.focused) surface.palette.accent else surface.palette.control_border;
        const width: f32 = if (state.focused) 2 else 1;
        try surface.stroke(rect, radius, width, color);
    }

    /// `Painter.segmented_track`.
    fn segmentedTrack(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        // A toggle-button group: an outlined container.
        const radius = surface.metrics.control_corner_radius;
        try surface.fill(rect, radius, surface.palette.control_background);
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
    }

    /// `Painter.segmented_selection`.
    fn segmentedSelection(surface: mod.Surface, segment: mod.Rect) std.mem.Allocator.Error!mod.Color {
        // The selected toggle button is a primary-tinted cell with primary text
        // (MUI's ToggleButton selected state).
        try surface.fill(segment.insetBy(1, 1), surface.metrics.control_corner_radius, surface.palette.accent.withAlpha(0.12));
        return surface.palette.accent;
    }

    /// `Painter.switch_track`.
    fn switchTrack(surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        // The Material switch is a thin track the thumb overhangs — not a full-
        // height iOS pill. On tints to a translucent primary; off is a grey wash.
        const track_height: f32 = 14;
        const track = mod.Rect{ .x = rect.x + 2, .y = rect.midY() - track_height / 2, .width = rect.width - 4, .height = track_height };
        const color = if (on) surface.palette.accent.withAlpha(0.5) else surface.palette.control_track;
        try surface.fill(track, track_height / 2, color);
    }

    /// `Painter.switch_knob`.
    fn switchKnob(surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        // The thumb is wider than the track. On: solid primary. Off: a pale disc
        // with a hairline border standing in for the spec's elevation shadow.
        const radius = knob.width / 2;
        const off_thumb = if (surface.scheme == .dark) mod.Color.fromRgb8(189, 189, 189) else mod.Color.white;
        const color = if (on) surface.palette.accent else off_thumb;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, color);
        if (!on) try surface.stroke(knob, radius, 1, surface.palette.control_border);
    }

    /// `Painter.slider`.
    fn slider(surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const track_radius = track.height / 2;
        // An unfilled rail in a faded primary, a solid primary fill, a primary thumb.
        try surface.fill(track, track_radius, surface.palette.accent.withAlpha(0.38));
        const filled = mod.Rect{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height };
        try surface.fill(filled, track_radius, surface.palette.accent);
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, knob.width / 2, surface.palette.accent);
    }

    /// `Painter.stepper_box`.
    fn stepperBox(surface: mod.Surface, rect: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const radius = surface.metrics.control_corner_radius;
        try surface.fill(rect, radius, surface.palette.control_background);
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
    }

    /// `Painter.progress`.
    fn progress(surface: mod.Surface, rect: mod.Rect, fraction: f32) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        try surface.fill(rect, radius, surface.palette.accent.withAlpha(0.3));
        const filled = mod.Rect{ .x = rect.x, .y = rect.y, .width = rect.width * std.math.clamp(fraction, 0, 1), .height = rect.height };
        try surface.fill(filled, radius, surface.palette.accent);
    }

    /// `Painter.panel`.
    fn panel(surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void {
        _ = kind; // one panel style fits all in this family
        // A raised surface (card/menu/dialog). No shadow primitive, so a thin border
        // grounds it against the background.
        try surface.fill(rect, radius, surface.palette.control_background);
        try surface.stroke(rect, radius, 1, surface.palette.separator);
    }

    /// A Material top app bar: the accent (primary) color.
    fn titleBar(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        try surface.fill(rect, 0, surface.palette.accent);
    }

    /// Content on the app bar takes the on-accent color.
    fn titleBarForeground(palette: *const mod.Palette) mod.Color {
        return palette.on_accent;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "mui: material blue primary and 4px controls" {
    try std.testing.expect(MuiTheme.light.colors.accent.b > MuiTheme.light.colors.accent.r);
    try std.testing.expectEqual(@as(f32, 4), MuiTheme.light.metrics.control_corner_radius);
}

test "mui: light and dark backgrounds differ" {
    try std.testing.expect(MuiTheme.light.colors.window_background.isDark() != MuiTheme.dark.colors.window_background.isDark());
}

test "mui: dark mode uses dark text on the light primary" {
    try std.testing.expect(MuiTheme.dark.colors.on_accent.isDark());
}
