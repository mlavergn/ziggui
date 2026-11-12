//! KDE Plasma theme (Breeze): the Linux desktop look — soft neutral surfaces,
//! a cyan-blue accent, gently rounded 3px corners, and subtle vertical
//! gradients with thin borders. Light (Breeze) & dark (Breeze Dark) follow the
//! OS appearance.

const std = @import("std");
const log = std.log.scoped(.ziggui_kde_theme);
const mod = @import("module.zig");

/// The KDE Plasma theme family: its painter and its light and dark themes.
pub const KdeTheme = struct {
    const Self = @This();

    /// Noto Sans / Oxygen scale.
    const typography = mod.Typography{
        .large_title = .{ .size = 24, .weight = .bold },
        .title = .{ .size = 20, .weight = .regular },
        .title2 = .{ .size = 16, .weight = .regular },
        .title3 = .{ .size = 14, .weight = .medium },
        .headline = .{ .size = 13, .weight = .bold },
        .body = .{ .size = 13, .weight = .regular },
        .callout = .{ .size = 12, .weight = .regular },
        .subheadline = .{ .size = 12, .weight = .regular },
        .footnote = .{ .size = 11, .weight = .regular },
        .caption = .{ .size = 11, .weight = .regular },
        .caption2 = .{ .size = 10, .weight = .regular },
    };

    /// Breeze rounds corners by ~3px and uses a slightly tall control.
    const metrics = mod.Metrics{
        .corner_radius = 6,
        .control_corner_radius = 3,
        .panel_corner_radius = 8,
        .selection_corner_radius = 3,
        .window_corner_radius = 6,
        .control_height = 28,
        .hairline = 1,
    };

    /// The Breeze chrome painter.
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

    /// Breeze.
    pub const light = mod.Theme{
        .name = "KDE Plasma",
        .scheme = .light,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(61, 174, 233), // Breeze blue
            .label = mod.Color.fromRgb8(35, 38, 41), // Breeze "Text"
            .secondary_label = mod.Color.fromRgb8(91, 95, 99),
            .tertiary_label = mod.Color.fromRgb8(136, 140, 144),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(239, 240, 241), // Breeze Window
            .secondary_background = mod.Color.fromRgb8(227, 229, 231),
            .control_background = mod.Color.fromRgb8(252, 252, 252), // Breeze View
            .separator = mod.Color.fromRgb8(188, 192, 196),
            .selection = mod.Color.fromRgb8(61, 174, 233),
            .destructive = mod.Color.fromRgb8(218, 68, 83), // Breeze red
            .hover = mod.Color.fromRgb8(61, 174, 233).withAlpha(0.12),
            .control_border = mod.Color.fromRgb8(188, 192, 196),
            .glass = mod.Color.fromRgb8(239, 240, 241).withAlpha(0.85),
            .control_track = mod.Color.fromRgb8(239, 240, 241),
        },
    };

    /// Breeze Dark.
    pub const dark = mod.Theme{
        .name = "KDE Plasma",
        .scheme = .dark,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(61, 174, 233),
            .label = mod.Color.fromRgb8(252, 252, 252),
            .secondary_label = mod.Color.fromRgb8(189, 195, 199),
            .tertiary_label = mod.Color.fromRgb8(127, 140, 141),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(42, 46, 50), // Breeze Dark Window
            .secondary_background = mod.Color.fromRgb8(49, 54, 59),
            .control_background = mod.Color.fromRgb8(35, 38, 41), // Breeze Dark View
            .separator = mod.Color.fromRgb8(81, 86, 91),
            .selection = mod.Color.fromRgb8(61, 174, 233),
            .destructive = mod.Color.fromRgb8(218, 68, 83),
            .hover = mod.Color.fromRgb8(61, 174, 233).withAlpha(0.18),
            .control_border = mod.Color.fromRgb8(81, 86, 91),
            .glass = mod.Color.fromRgb8(42, 46, 50).withAlpha(0.85),
            .control_track = mod.Color.fromRgb8(49, 54, 59),
        },
    };

    // -------------------------------------------------------------------------
    // Painter — subtle gradients + thin borders
    // -------------------------------------------------------------------------

    /// `Painter.button`.
    fn button(surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color {
        const radius = surface.metrics.control_corner_radius;
        if (role == .plain) return surface.palette.accent;
        if (role == .destructive) {
            try surface.verticalGradient(rect, radius, surface.palette.destructive.lighten(0.08), surface.palette.destructive.darken(0.06));
            try surface.stroke(rect, radius, 1, surface.palette.destructive.darken(0.15));
            return surface.palette.on_accent;
        }
        if (role == .prominent) {
            // The Breeze default action: the same gradient treatment in the accent.
            try surface.verticalGradient(rect, radius, surface.palette.accent.lighten(0.08), surface.palette.accent.darken(0.06));
            try surface.stroke(rect, radius, 1, surface.palette.accent.darken(0.15));
            return surface.palette.on_accent;
        }
        // Breeze buttons: a faint top-lit gradient over the control face with a thin
        // border; hover lifts toward the accent.
        const base = surface.palette.control_track;
        const top = if (state.hovered) base.lighten(0.12) else base.lighten(0.05);
        try surface.verticalGradient(rect, radius, top, base.darken(0.04));
        const border = if (state.hovered or state.focused) surface.palette.accent else surface.palette.control_border;
        try surface.stroke(rect, radius, 1, border);
        return surface.palette.label;
    }

    /// `Painter.field`.
    fn field(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void {
        try surface.fill(rect, radius, surface.palette.control_background);
        const color = if (state.focused) surface.palette.accent else surface.palette.control_border;
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
        const inner = segment.insetBy(2, 2);
        const radius = surface.metrics.control_corner_radius - 1;
        try surface.verticalGradient(inner, radius, surface.palette.accent.lighten(0.06), surface.palette.accent.darken(0.04));
        return surface.palette.on_accent;
    }

    /// `Painter.switch_track`.
    fn switchTrack(surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        if (on) {
            try surface.fill(rect, radius, surface.palette.accent);
        } else {
            try surface.fill(rect, radius, surface.palette.control_track.darken(0.04));
            try surface.stroke(rect, radius, 1, surface.palette.control_border);
        }
    }

    /// `Painter.switch_knob`.
    fn switchKnob(surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        _ = on;
        // A pale circular handle with a thin Breeze border.
        const radius = knob.width / 2;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, surface.palette.control_background);
        try surface.stroke(knob, radius, 1, surface.palette.control_border);
    }

    /// `Painter.slider`.
    fn slider(surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const track_radius = track.height / 2;
        try surface.fill(track, track_radius, surface.palette.control_track.darken(0.04));
        try surface.stroke(track, track_radius, 1, surface.palette.control_border);
        const filled = mod.Rect{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height };
        try surface.fill(filled, track_radius, surface.palette.accent);
        const radius = knob.width / 2;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, surface.palette.control_background);
        try surface.stroke(knob, radius, 1, surface.palette.control_border);
    }

    /// `Painter.stepper_box`.
    fn stepperBox(surface: mod.Surface, rect: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const radius = surface.metrics.control_corner_radius;
        try surface.verticalGradient(rect, radius, surface.palette.control_track.lighten(0.05), surface.palette.control_track.darken(0.04));
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
    }

    /// `Painter.progress`.
    fn progress(surface: mod.Surface, rect: mod.Rect, fraction: f32) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        try surface.fill(rect, radius, surface.palette.control_track.darken(0.04));
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
        const filled = mod.Rect{ .x = rect.x, .y = rect.y, .width = rect.width * std.math.clamp(fraction, 0, 1), .height = rect.height };
        try surface.fill(filled, radius, surface.palette.accent);
    }

    /// `Painter.panel`.
    fn panel(surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void {
        _ = kind; // one panel style fits all in this family
        try surface.fill(rect, radius, surface.palette.window_background);
        try surface.stroke(rect, radius, 1, surface.palette.control_border);
    }

    /// Breeze's header color: #DEE0E2 in light, #2A2E32 in dark.
    fn titleBar(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        try surface.fill(rect, 0, if (surface.scheme == .dark) mod.Color.fromRgb8(42, 46, 50) else mod.Color.fromRgb8(222, 224, 226));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "kde: breeze blue accent and rounded controls" {
    try std.testing.expect(KdeTheme.light.colors.accent.b > KdeTheme.light.colors.accent.r);
    try std.testing.expectEqual(@as(f32, 3), KdeTheme.light.metrics.control_corner_radius);
}

test "kde: light and dark differ" {
    try std.testing.expect(KdeTheme.light.colors.window_background.isDark() != KdeTheme.dark.colors.window_background.isDark());
}
