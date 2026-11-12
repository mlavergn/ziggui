//! Windows 10 theme: the flat "Metro/Fluent-lite" look — solid fills, 1px
//! borders, square corners, and a single bright accent. Light & dark follow the
//! OS appearance.

const std = @import("std");
const log = std.log.scoped(.ziggui_windows10_theme);
const mod = @import("module.zig");

/// The Windows 10 theme family: its painter and its light and dark themes.
pub const Windows10Theme = struct {
    const Self = @This();

    /// Segoe UI scale: clean, slightly larger than the Win2000 shell.
    const typography = mod.Typography{
        .large_title = .{ .size = 24, .weight = .light },
        .title = .{ .size = 20, .weight = .regular },
        .title2 = .{ .size = 16, .weight = .regular },
        .title3 = .{ .size = 14, .weight = .semibold },
        .headline = .{ .size = 13, .weight = .semibold },
        .body = .{ .size = 13, .weight = .regular },
        .callout = .{ .size = 12, .weight = .regular },
        .subheadline = .{ .size = 12, .weight = .regular },
        .footnote = .{ .size = 11, .weight = .regular },
        .caption = .{ .size = 11, .weight = .regular },
        .caption2 = .{ .size = 10, .weight = .regular },
    };

    /// Flat and square, with a comfortable control height.
    const metrics = mod.Metrics{
        .corner_radius = 0,
        .control_corner_radius = 2,
        .panel_corner_radius = 0,
        .selection_corner_radius = 0,
        .window_corner_radius = 0,
        .control_height = 26,
        .hairline = 1,
    };

    /// The flat chrome painter.
    pub const painter = mod.Painter{
        .title_bar = Self.titleBar,
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

    /// Windows 10 light.
    pub const light = mod.Theme{
        .name = "Windows 10",
        .scheme = .light,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(0, 120, 215), // Windows 10 blue
            .label = mod.Color.fromRgb8(0, 0, 0),
            .secondary_label = mod.Color.fromRgb8(96, 96, 96),
            .tertiary_label = mod.Color.fromRgb8(140, 140, 140),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(240, 240, 240),
            .secondary_background = mod.Color.fromRgb8(230, 230, 230),
            .control_background = mod.Color.white,
            .separator = mod.Color.fromRgb8(204, 204, 204),
            .selection = mod.Color.fromRgb8(0, 120, 215),
            .destructive = mod.Color.fromRgb8(232, 17, 35),
            .hover = mod.Color.fromRgb8(229, 241, 251), // Win10 hover wash
            .control_border = mod.Color.fromRgb8(173, 173, 173),
            .glass = mod.Color.white.withAlpha(0.8),
            .control_track = mod.Color.fromRgb8(225, 225, 225),
        },
    };

    /// Windows 10 dark.
    pub const dark = mod.Theme{
        .name = "Windows 10",
        .scheme = .dark,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(96, 205, 255), // brighter accent on dark
            .label = mod.Color.white,
            .secondary_label = mod.Color.white.withAlpha(0.6),
            .tertiary_label = mod.Color.white.withAlpha(0.4),
            .on_accent = mod.Color.fromRgb8(0, 0, 0),
            .window_background = mod.Color.fromRgb8(32, 32, 32),
            .secondary_background = mod.Color.fromRgb8(43, 43, 43),
            .control_background = mod.Color.fromRgb8(51, 51, 51),
            .separator = mod.Color.fromRgb8(80, 80, 80),
            .selection = mod.Color.fromRgb8(0, 120, 215),
            .destructive = mod.Color.fromRgb8(255, 99, 71),
            .hover = mod.Color.white.withAlpha(0.08),
            .control_border = mod.Color.fromRgb8(96, 96, 96),
            .glass = mod.Color.fromRgb8(43, 43, 43).withAlpha(0.85),
            .control_track = mod.Color.fromRgb8(60, 60, 60),
        },
    };

    // -------------------------------------------------------------------------
    // Painter — flat fills + 1px borders
    // -------------------------------------------------------------------------

    /// `Painter.button`.
    fn button(surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color {
        const radius = surface.metrics.control_corner_radius;
        if (role == .plain) return surface.palette.accent;
        if (role == .destructive) {
            try surface.fill(rect, radius, surface.palette.destructive);
            return surface.palette.on_accent;
        }
        if (role == .prominent) {
            // The Win10 default action is a flat accent fill.
            var background = surface.palette.accent;
            if (state.pressed) background = background.darken(0.08) else if (state.hovered) background = background.lighten(0.06);
            try surface.fill(rect, radius, background);
            return surface.palette.on_accent;
        }
        // Default Win10 buttons are a neutral fill with a flat border; the accent is
        // reserved for the hover/focus border.
        try surface.fill(rect, radius, surface.palette.control_track);
        const border = if (state.hovered or state.focused) surface.palette.accent else surface.palette.control_border;
        try surface.stroke(rect, radius, 1, border);
        return surface.palette.label;
    }

    /// `Painter.field`.
    fn field(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void {
        try surface.fill(rect, radius, surface.palette.control_background);
        const color = if (state.focused) surface.palette.accent else surface.palette.separator;
        const width: f32 = if (state.focused) 2 else 1;
        try surface.stroke(rect, radius, width, color);
    }

    /// `Painter.segmented_track`.
    fn segmentedTrack(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        const radius = surface.metrics.control_corner_radius;
        try surface.fill(rect, radius, surface.palette.control_track);
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
    }

    /// `Painter.segmented_selection`.
    fn segmentedSelection(surface: mod.Surface, segment: mod.Rect) std.mem.Allocator.Error!mod.Color {
        // The selected segment is a solid accent block with accent-contrast text.
        try surface.fill(segment.insetBy(1, 1), surface.metrics.control_corner_radius, surface.palette.accent);
        return surface.palette.on_accent;
    }

    /// `Painter.switch_track`.
    fn switchTrack(surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        if (on) {
            try surface.fill(rect, radius, surface.palette.accent);
        } else {
            try surface.fill(rect, radius, surface.palette.control_track);
            try surface.stroke(rect, radius, 1, surface.palette.label);
        }
    }

    /// `Painter.switch_knob`.
    fn switchKnob(surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        // A flat circular thumb: bright on the accent track, neutral on the off track.
        const color = if (on) surface.palette.on_accent else surface.palette.label;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, knob.width / 2, color);
    }

    /// `Painter.slider`.
    fn slider(surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const track_radius = track.height / 2;
        try surface.fill(track, track_radius, surface.palette.control_track);
        const filled = mod.Rect{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height };
        try surface.fill(filled, track_radius, surface.palette.accent);
        // A solid accent thumb.
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
        try surface.fill(rect, radius, surface.palette.control_track);
        const filled = mod.Rect{ .x = rect.x, .y = rect.y, .width = rect.width * std.math.clamp(fraction, 0, 1), .height = rect.height };
        try surface.fill(filled, radius, surface.palette.accent);
    }

    /// `Painter.panel`.
    fn panel(surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void {
        _ = kind; // one panel style fits all in this family
        _ = radius; // always square
        try surface.fill(rect, 0, surface.palette.control_background);
        try surface.stroke(rect, 0, 1, surface.palette.control_border);
    }

    /// Windows 11's caption with the accent off: white in light, #202020 in dark,
    /// over a hairline.
    fn titleBar(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        try surface.fill(rect, 0, if (surface.scheme == .dark) mod.Color.fromRgb8(32, 32, 32) else mod.Color.white);
        try surface.bottomHairline(rect);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "windows10: flat with a bright accent" {
    try std.testing.expect(Windows10Theme.light.colors.accent.b > Windows10Theme.light.colors.accent.r);
    try std.testing.expectEqual(@as(f32, 2), Windows10Theme.light.metrics.control_corner_radius);
}

test "windows10: light and dark backgrounds differ" {
    try std.testing.expect(Windows10Theme.light.colors.window_background.isDark() != Windows10Theme.dark.colors.window_background.isDark());
}
