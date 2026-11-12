//! Windows 2000 theme: the classic "Luna-less" chiseled look — silver 3D-face
//! controls with raised/sunken bevels drawn from four edge colors, a navy
//! selection highlight, and square corners. Windows 2000 had no dark mode; the
//! `dark` palette is the same chiseled look on charcoal, for apps that follow
//! the OS appearance.

const std = @import("std");
const log = std.log.scoped(.ziggui_win2000_theme);
const mod = @import("module.zig");

/// The Windows 2000 theme family: its painter and its light and dark themes.
pub const Win2000Theme = struct {
    const Self = @This();

    /// Tahoma-ish UI scale: small, dense text like the classic Windows shell.
    const typography = mod.Typography{
        .large_title = .{ .size = 20, .weight = .bold },
        .title = .{ .size = 17, .weight = .bold },
        .title2 = .{ .size = 15, .weight = .bold },
        .title3 = .{ .size = 13, .weight = .bold },
        .headline = .{ .size = 12, .weight = .bold },
        .body = .{ .size = 12, .weight = .regular },
        .callout = .{ .size = 12, .weight = .regular },
        .subheadline = .{ .size = 11, .weight = .regular },
        .footnote = .{ .size = 11, .weight = .regular },
        .caption = .{ .size = 10, .weight = .regular },
        .caption2 = .{ .size = 10, .weight = .regular },
    };

    /// Square corners, 1px hairlines, a slightly taller default control.
    const metrics = mod.Metrics{
        .corner_radius = 0,
        .control_corner_radius = 0,
        .panel_corner_radius = 0,
        .selection_corner_radius = 0,
        .window_corner_radius = 0,
        .control_height = 23,
        .hairline = 1,
        .chiseled = true,
    };

    /// The chiseled chrome painter.
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

    /// Windows 2000 (its only scheme).
    pub const light = mod.Theme{
        .name = "Windows 2000",
        .scheme = .light,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(10, 36, 106), // classic navy selection
            .label = mod.Color.black,
            .secondary_label = mod.Color.fromRgb8(64, 64, 64),
            .tertiary_label = mod.Color.fromRgb8(128, 128, 128),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(212, 208, 200), // 3DFACE
            .secondary_background = mod.Color.fromRgb8(212, 208, 200),
            .control_background = mod.Color.white, // edit fields / lists
            .separator = mod.Color.fromRgb8(128, 128, 128),
            .selection = mod.Color.fromRgb8(10, 36, 106),
            .destructive = mod.Color.fromRgb8(170, 0, 0),
            .hover = mod.Color.fromRgb8(10, 36, 106).withAlpha(0.12),
            .control_border = mod.Color.fromRgb8(128, 128, 128),
            .glass = mod.Color.fromRgb8(212, 208, 200).withAlpha(0.95),
            .control_track = mod.Color.fromRgb8(212, 208, 200),
            // Bevel edges (the 3D scheme colors).
            .control_face = mod.Color.fromRgb8(212, 208, 200),
            .control_highlight = mod.Color.white,
            .control_light = mod.Color.fromRgb8(227, 224, 219),
            .control_shadow = mod.Color.fromRgb8(128, 128, 128),
            .control_dark_shadow = mod.Color.fromRgb8(64, 64, 64),
            .on_control = mod.Color.black,
        },
    };

    /// The same chiseled scheme colors on charcoal: edges run from a lit top-left
    /// to a near-black bottom-right, and the navy selection is lifted to stay legible.
    pub const dark = mod.Theme{
        .name = "Windows 2000",
        .scheme = .dark,
        .typography = Self.typography,
        .metrics = Self.metrics,
        .painter = Self.painter,
        .colors = .{
            .accent = mod.Color.fromRgb8(70, 110, 215),
            .label = mod.Color.fromRgb8(235, 235, 235),
            .secondary_label = mod.Color.fromRgb8(190, 190, 190),
            .tertiary_label = mod.Color.fromRgb8(130, 130, 130),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(56, 56, 56),
            .secondary_background = mod.Color.fromRgb8(56, 56, 56),
            .control_background = mod.Color.fromRgb8(28, 28, 28),
            .separator = mod.Color.fromRgb8(24, 24, 24),
            .selection = mod.Color.fromRgb8(70, 110, 215),
            .destructive = mod.Color.fromRgb8(230, 80, 80),
            .hover = mod.Color.fromRgb8(70, 110, 215).withAlpha(0.25),
            .control_border = mod.Color.fromRgb8(24, 24, 24),
            .glass = mod.Color.fromRgb8(56, 56, 56).withAlpha(0.95),
            .control_track = mod.Color.fromRgb8(56, 56, 56),
            .control_face = mod.Color.fromRgb8(56, 56, 56),
            .control_highlight = mod.Color.fromRgb8(110, 110, 110),
            .control_light = mod.Color.fromRgb8(82, 82, 82),
            .control_shadow = mod.Color.fromRgb8(30, 30, 30),
            .control_dark_shadow = mod.Color.fromRgb8(8, 8, 8),
            .on_control = mod.Color.fromRgb8(235, 235, 235),
        },
    };

    // -------------------------------------------------------------------------
    // Bevels — the heart of the chiseled look
    // -------------------------------------------------------------------------

    /// A two-ring 3D bevel (`Surface.bevel`): `raised` for a button at rest, sunken
    /// for a pressed button or an input well.
    fn bevel(surface: mod.Surface, rect: mod.Rect, raised: bool) std.mem.Allocator.Error!void {
        try surface.bevel(rect, raised);
    }

    // -------------------------------------------------------------------------
    // Painter
    // -------------------------------------------------------------------------

    /// `Painter.button`.
    fn button(surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color {
        if (role == .plain) return surface.palette.accent;
        var body = rect;
        if (role == .prominent) {
            // The classic default-button treatment: a black ring around the bevel.
            try surface.fill(body, 0, mod.Color.black);
            body = body.insetBy(1, 1);
        }
        try surface.fill(body, 0, surface.palette.control_face);
        try Self.bevel(surface, body, !state.pressed);
        return surface.palette.on_control;
    }

    /// `Painter.field`.
    fn field(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = radius; // always square
        _ = state;
        try surface.fill(rect, 0, surface.palette.control_background);
        try Self.bevel(surface, rect, false); // an input is a sunken well
    }

    /// `Painter.segmented_track`.
    fn segmentedTrack(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        try surface.fill(rect, 0, surface.palette.control_face);
        try Self.bevel(surface, rect, true);
    }

    /// `Painter.segmented_selection`.
    fn segmentedSelection(surface: mod.Surface, segment: mod.Rect) std.mem.Allocator.Error!mod.Color {
        // The selected tab/segment reads as a depressed button.
        try surface.fill(segment, 0, surface.palette.control_face);
        try Self.bevel(surface, segment, false);
        return surface.palette.on_control;
    }

    /// `Painter.switch_track`.
    fn switchTrack(surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        // Classic Windows has no switches — a boolean control is a *checkbox*: a
        // 13px sunken white well on the trailing edge with a black check when on.
        const box: f32 = 13;
        const check_box = mod.Rect{ .x = rect.maxX() - box, .y = rect.midY() - box / 2, .width = box, .height = box };
        try surface.fill(check_box, 0, surface.palette.control_background);
        try Self.bevel(surface, check_box, false);
        if (on) {
            // The check: a short down-stroke meeting a longer up-stroke.
            const middle = mod.Point{ .x = check_box.x + 5.5, .y = check_box.y + 9 };
            try surface.lineSegment(.{ .x = check_box.x + 3, .y = check_box.y + 6.5 }, middle, 1.8, surface.palette.on_control);
            try surface.lineSegment(middle, .{ .x = check_box.x + 10, .y = check_box.y + 3.5 }, 1.8, surface.palette.on_control);
        }
    }

    /// `Painter.switch_knob`.
    fn switchKnob(surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        // The checkbox is drawn entirely by `switchTrack`; there is no thumb.
        _ = surface;
        _ = knob;
        _ = on;
    }

    /// `Painter.slider`.
    fn slider(surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        // A sunken groove with a navy fill, and a raised square handle.
        try surface.fill(track, 0, surface.palette.control_background);
        try Self.bevel(surface, track, false);
        const filled = mod.Rect{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height };
        try surface.fill(filled, 0, surface.palette.accent);
        try surface.fill(knob, 0, surface.palette.control_face);
        try Self.bevel(surface, knob, true);
    }

    /// `Painter.stepper_box`.
    fn stepperBox(surface: mod.Surface, rect: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        try surface.fill(rect, 0, surface.palette.control_face);
        try Self.bevel(surface, rect, true); // a raised control box
    }

    /// `Painter.progress`.
    fn progress(surface: mod.Surface, rect: mod.Rect, fraction: f32) std.mem.Allocator.Error!void {
        try surface.fill(rect, 0, surface.palette.control_background);
        try Self.bevel(surface, rect, false); // a sunken trough
        const filled = mod.Rect{ .x = rect.x, .y = rect.y, .width = rect.width * std.math.clamp(fraction, 0, 1), .height = rect.height };
        try surface.fill(filled, 0, surface.palette.accent);
    }

    /// `Painter.panel`.
    fn panel(surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void {
        _ = kind; // one panel style fits all in this family
        _ = radius; // always square
        try surface.fill(rect, 0, surface.palette.control_face);
        try Self.bevel(surface, rect, true); // a raised window/panel
    }

    /// The classic active caption: navy to sky blue, left to right, in both schemes.
    fn titleBar(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        try surface.horizontalGradient(rect, 0, mod.Color.fromRgb8(10, 36, 106), mod.Color.fromRgb8(166, 202, 240));
    }

    /// White on the blue caption.
    fn titleBarForeground(_: *const mod.Palette) mod.Color {
        return mod.Color.white;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "win2000: square corners and silver face" {
    try std.testing.expectEqual(@as(f32, 0), Win2000Theme.light.metrics.control_corner_radius);
    try std.testing.expect(Win2000Theme.light.colors.window_background.approxEql(mod.Color.fromRgb8(212, 208, 200), 0.01));
}

test "win2000: selection is navy" {
    const accent = Win2000Theme.light.colors.accent;
    try std.testing.expect(accent.b > accent.r and accent.b > accent.g and accent.isDark());
}

test "win2000: dark is charcoal with the same square metrics" {
    try std.testing.expectEqual(mod.ColorScheme.dark, Win2000Theme.dark.scheme);
    try std.testing.expect(Win2000Theme.dark.colors.window_background.isDark());
    try std.testing.expect(Win2000Theme.dark.metrics.chiseled);
}
