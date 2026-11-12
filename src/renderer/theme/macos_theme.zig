//! macOS theme (light & dark): Apple's "Liquid Glass" appearance — translucent
//! surfaces, vertical gradient sheens, and bright edge rims. The painter draws
//! the chrome; palette values approximate macOS's dynamic system colors and the
//! SF Pro type scale. No Apple assets are used — only color/size tokens.

const std = @import("std");
const log = std.log.scoped(.ziggui_macos_theme);
const mod = @import("module.zig");

/// The macOS theme family: its painter and its light and dark themes.
pub const MacosTheme = struct {
    const Self = @This();

    /// macOS type scale (point sizes / weights roughly matching the system).
    const typography = mod.Typography{
        .large_title = .{ .size = 26, .weight = .bold },
        .title = .{ .size = 22, .weight = .regular },
        .title2 = .{ .size = 17, .weight = .regular },
        .title3 = .{ .size = 15, .weight = .regular },
        .headline = .{ .size = 13, .weight = .semibold },
        .body = .{ .size = 13, .weight = .regular },
        .callout = .{ .size = 12, .weight = .regular },
        .subheadline = .{ .size = 11, .weight = .regular },
        .footnote = .{ .size = 10, .weight = .regular },
        .caption = .{ .size = 10, .weight = .regular },
        .caption2 = .{ .size = 10, .weight = .regular },
    };

    /// Layout metrics matching the native macOS 26 control sizes (sampled).
    const metrics = mod.Metrics{
        // Buttons/segmented controls are 24pt tall on macOS 26.
        .control_height = 24,
        // Form buttons are *moderately* rounded (~5pt at 24pt height) — only
        // toolbar pills are capsules.
        .control_corner_radius = 5.5,
        // Sheets/alerts round at ~20pt; sidebar selection at 6pt.
        .panel_corner_radius = 20,
        .selection_corner_radius = 6,
    };

    // -------------------------------------------------------------------------
    // Painter — the Liquid Glass look
    // -------------------------------------------------------------------------
    //
    // Every value here was sampled from real macOS 26 (Tahoe) screenshots of the
    // same controls rendered by SwiftUI (`tools/parity/RefGallery.swift`), so the
    // painter reproduces what the OS actually draws rather than an interpretation:
    // flat fills (no gradients), a soft drop shadow that floats each capsule, a
    // one-pixel specular line under the top edge of tinted controls, and the dual
    // blues — `accent` (#007AFF) for prominent buttons vs `selection` (#3478F6,
    // AppKit's controlAccentColor) for switches/segmented chips/slider fills.
    // Raised glass still begins with a `backdropBlur` so controls genuinely frost
    // scrolled content beneath them (over a flat background the blur is a no-op).

    /// Backdrop frost strength for raised glass controls.
    const control_sigma: f32 = 4;
    /// Frost for popover/menu material panels.
    const popover_sigma: f32 = 18;

    /// The Liquid Glass chrome painter.
    pub const painter = mod.Painter{
        .button = Self.button,
        .field = Self.field,
        .glass_surface = Self.glassSurface,
        .segmented_track = Self.segmentedTrack,
        .segmented_selection = Self.segmentedSelection,
        .switch_track = Self.switchTrack,
        .switch_knob = Self.switchKnob,
        .slider = Self.slider,
        .stepper_box = Self.stepperBox,
        .progress = Self.progress,
        .panel = Self.panel,
    };

    // Palette values sampled from native macOS 26 captures (see the painter notes).

    /// macOS light.
    pub const light = mod.Theme{
        .name = "macOS",
        .scheme = .light,
        .typography = Self.typography,
        .painter = Self.painter,
        .metrics = Self.metrics,
        .colors = .{
            .accent = mod.Color.fromRgb8(1, 121, 254), // systemBlue (glassProminent fill)
            .label = mod.Color.black.withAlpha(0.85), // labelColor
            .secondary_label = mod.Color.fromRgb8(122, 122, 122),
            .tertiary_label = mod.Color.black.withAlpha(0.26),
            .on_accent = mod.Color.white,
            // Grouped content: a white window with slightly darker rows/cards.
            .window_background = mod.Color.white,
            .secondary_background = mod.Color.fromRgb8(247, 247, 247),
            .control_background = mod.Color.white,
            .separator = mod.Color.black.withAlpha(0.08),
            // controlAccentColor — switches, segmented chips, slider/progress fills.
            .selection = mod.Color.fromRgb8(52, 120, 246),
            .destructive = mod.Color.fromRgb8(255, 61, 65), // sampled glassProminent red
            // Liquid Glass
            .hover = mod.Color.black.withAlpha(0.05),
            .control_border = mod.Color.black.withAlpha(0.08),
            .glass = mod.Color.fromRgb8(248, 250, 251).withAlpha(0.90),
            .control_track = mod.Color.black.withAlpha(0.075),
            .scrim = mod.Color.black.withAlpha(0.20),
            .quaternary_fill = mod.Color.black.withAlpha(0.12),
            .sidebar_background = mod.Color.fromRgb8(250, 250, 250),
        },
    };

    /// macOS dark.
    pub const dark = mod.Theme{
        .name = "macOS",
        .scheme = .dark,
        .typography = Self.typography,
        .painter = Self.painter,
        .metrics = Self.metrics,
        .colors = .{
            .accent = mod.Color.fromRgb8(0, 121, 255),
            .label = mod.Color.white.withAlpha(0.85),
            .secondary_label = mod.Color.fromRgb8(156, 156, 156),
            .tertiary_label = mod.Color.white.withAlpha(0.25),
            .on_accent = mod.Color.white,
            .window_background = mod.Color.fromRgb8(27, 27, 27),
            .secondary_background = mod.Color.fromRgb8(34, 34, 34),
            .control_background = mod.Color.fromRgb8(44, 44, 44),
            .separator = mod.Color.white.withAlpha(0.12),
            .selection = mod.Color.fromRgb8(57, 124, 247),
            .destructive = mod.Color.fromRgb8(255, 69, 58),
            // Liquid Glass
            .hover = mod.Color.white.withAlpha(0.08),
            .control_border = mod.Color.white.withAlpha(0.14),
            .glass = mod.Color.fromRgb8(44, 44, 44).withAlpha(0.88),
            .control_track = mod.Color.white.withAlpha(0.065),
            .scrim = mod.Color.black.withAlpha(0.30),
            .quaternary_fill = mod.Color.white.withAlpha(0.17),
            .sidebar_background = mod.Color.fromRgb8(26, 27, 27),
        },
    };

    /// The soft drop shadow that floats a glass capsule off the surface: two
    /// offset translucent fills peeking out below the shape (drawn first, mostly
    /// covered by the fill itself). Matches the ~2pt ambient shadow under native
    /// controls.
    fn dropShadow(surface: mod.Surface, rect: mod.Rect, radius: f32, strength: f32) std.mem.Allocator.Error!void {
        try surface.fill(rect.offsetBy(0, 2).insetBy(-1, -1), radius + 1, mod.Color.black.withAlpha(0.05 * strength));
        try surface.fill(rect.offsetBy(0, 1), radius, mod.Color.black.withAlpha(0.10 * strength));
    }

    /// Neutral ("clear") Liquid Glass — the macOS 26 default control surface.
    /// Light mode: a near-white capsule with a white rim, a faint occlusion line
    /// under the top edge, and a soft shadow. Dark mode: a darker-than-backdrop
    /// fill with a brighter top rim.
    fn clearGlass(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState, dim: f32) std.mem.Allocator.Error!void {
        const lit = surface.scheme == .light;
        if (state.disabled) {
            // Native disabled glass is an outline ghost: no fill, no shadow, just
            // a hairline ring with dimmed text.
            const ring = if (lit) mod.Color.black.withAlpha(0.25) else mod.Color.white.withAlpha(0.27);
            try surface.stroke(rect, radius, 1, ring);
            return;
        }
        try Self.dropShadow(surface, rect, radius, if (lit) 1.0 else 1.6);
        try surface.backdropBlur(rect, radius, Self.control_sigma, mod.Color.transparent);
        const inset = @min(radius, rect.width / 2);
        if (lit) {
            try surface.fill(rect, radius, mod.Color.white.withAlpha(0.93 * dim));
            // white rim, brightest along the sides/bottom of the capsule
            try surface.stroke(rect, radius, 1, mod.Color.white.withAlpha(0.90 * dim));
            // faint occlusion line under the top edge
            try surface.lineSegment(
                .{ .x = rect.x + inset, .y = rect.y + 1 },
                .{ .x = rect.maxX() - inset, .y = rect.y + 1 },
                1,
                mod.Color.black.withAlpha(0.04 * dim),
            );
        } else {
            // Dark glass *lifts* off its backdrop — a translucent white wash (a
            // toolbar pill over a near-black window reads lighter, never darker).
            try surface.fill(rect, radius, mod.Color.white.withAlpha(0.09 * dim));
            try surface.stroke(rect, radius, 1, mod.Color.white.withAlpha(0.07 * dim));
            // brighter refractive line along the top edge
            try surface.lineSegment(
                .{ .x = rect.x + inset, .y = rect.y + 1 },
                .{ .x = rect.maxX() - inset, .y = rect.y + 1 },
                1,
                mod.Color.white.withAlpha(0.14 * dim),
            );
        }
        if (state.pressed) {
            try surface.fill(rect, radius, mod.Color.black.withAlpha(0.08));
        } else if (state.hovered) {
            try surface.fill(rect, radius, surface.palette.hover);
        }
    }

    /// Tinted Liquid Glass (prominent / destructive): a flat tint capsule with a
    /// bright 1px specular under the top edge and a soft shadow — exactly how
    /// native `.glassProminent` renders at rest.
    fn tintedGlass(surface: mod.Surface, rect: mod.Rect, radius: f32, tint: mod.Color, state: mod.ControlState, dim: f32) std.mem.Allocator.Error!void {
        var background = tint;
        if (state.pressed) background = background.darken(0.08) else if (state.hovered) background = background.lighten(0.06);
        if (!state.disabled) try Self.dropShadow(surface, rect, radius, 1);
        try surface.backdropBlur(rect, radius, Self.control_sigma, mod.Color.transparent);
        try surface.fill(rect, radius, background.withAlpha(0.97).multiplyAlpha(dim));
        const inset = @min(radius, rect.width / 2);
        try surface.lineSegment(
            .{ .x = rect.x + inset, .y = rect.y + 0.75 },
            .{ .x = rect.maxX() - inset, .y = rect.y + 0.75 },
            1.5,
            mod.Color.white.withAlpha(0.32 * dim),
        );
    }

    /// `Painter.button`.
    fn button(surface: mod.Surface, rect: mod.Rect, role: mod.Role, state: mod.ControlState) std.mem.Allocator.Error!mod.Color {
        const dim: f32 = if (state.disabled) 0.4 else 1.0;
        // In-content macOS 26 buttons are gently rounded rects (~5pt), not
        // capsules — capsules are the *toolbar pill* style (see `glassSurface`).
        const radius = @min(surface.metrics.control_corner_radius, rect.height / 2);
        switch (role) {
            // Native borderless buttons render with the secondary label color.
            .plain => return surface.palette.secondary_label,
            // The everyday button is *neutral* glass with an ordinary label; only
            // prominent (default-action) and destructive buttons carry a tint.
            .normal => {
                try Self.clearGlass(surface, rect, radius, state, dim);
                return if (state.disabled) surface.palette.tertiary_label else surface.palette.label;
            },
            .prominent => {
                try Self.tintedGlass(surface, rect, radius, surface.palette.accent, state, dim);
                return surface.palette.on_accent;
            },
            .destructive => {
                try Self.tintedGlass(surface, rect, radius, surface.palette.destructive, state, dim);
                return surface.palette.on_accent;
            },
        }
    }

    /// `Painter.field`.
    fn field(surface: mod.Surface, rect: mod.Rect, radius: f32, state: mod.ControlState) std.mem.Allocator.Error!void {
        try surface.fill(rect, radius, surface.palette.control_background);
        if (state.focused) {
            // The macOS focus glow: a soft accent halo outside the ring itself.
            try surface.stroke(rect.insetBy(-1.5, -1.5), radius + 1.5, 3, surface.palette.selection.withAlpha(0.25));
            try surface.stroke(rect, radius, 2, surface.palette.selection);
        } else {
            try surface.stroke(rect, radius, surface.metrics.hairline, surface.palette.separator);
        }
    }

    /// `Painter.segmented_track`.
    fn segmentedTrack(surface: mod.Surface, rect: mod.Rect) std.mem.Allocator.Error!void {
        // A flat translucent trough, moderately rounded (native is ~7pt at a 24pt
        // height — not a capsule), with no border.
        try surface.fill(rect, 7, surface.palette.control_track);
    }

    /// `Painter.segmented_selection`.
    fn segmentedSelection(surface: mod.Surface, segment: mod.Rect) std.mem.Allocator.Error!mod.Color {
        // The selected chip fills the full track height (no inset) as a flat
        // control-accent rounded rect with a faint top specular.
        try surface.fill(segment, 5.5, surface.palette.selection);
        const inset: f32 = 6;
        try surface.lineSegment(
            .{ .x = segment.x + inset, .y = segment.y + 1 },
            .{ .x = segment.maxX() - inset, .y = segment.y + 1 },
            1,
            mod.Color.white.withAlpha(0.25),
        );
        return surface.palette.on_accent;
    }

    /// `Painter.switch_track`.
    fn switchTrack(surface: mod.Surface, rect: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        if (on) {
            try surface.fill(rect, radius, surface.palette.selection);
        } else {
            const lit = surface.scheme == .light;
            const fill_color = if (lit) mod.Color.black.withAlpha(0.11) else mod.Color.white.withAlpha(0.09);
            try surface.fill(rect, radius, fill_color);
            try surface.stroke(rect, radius, surface.metrics.hairline, mod.Color.black.withAlpha(if (lit) 0.04 else 0.15));
        }
    }

    /// `Painter.switch_knob`.
    fn switchKnob(surface: mod.Surface, knob: mod.Rect, on: bool) std.mem.Allocator.Error!void {
        _ = on; // the knob looks the same on or off; its position encodes the state
        const radius = knob.width / 2;
        // a soft shadow grounds the floating knob against the track
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() + 0.75 }, radius, mod.Color.black.withAlpha(0.20));
        // dark-mode knobs are slightly translucent (they pick up the track tint)
        const knob_color = if (surface.scheme == .light) mod.Color.white else mod.Color.white.withAlpha(0.87);
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, knob_color);
    }

    /// `Painter.slider`.
    fn slider(surface: mod.Surface, track: mod.Rect, fraction: f32, knob: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        const lit = surface.scheme == .light;
        const track_radius = track.height / 2;
        const trough = if (lit) mod.Color.black.withAlpha(0.10) else mod.Color.white.withAlpha(0.09);
        try surface.fill(track, track_radius, trough);
        const filled = mod.Rect{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height };
        try surface.fill(filled, track_radius, surface.palette.selection);
        const radius = knob.width / 2;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() + 0.75 }, radius, mod.Color.black.withAlpha(0.20));
        const knob_color = if (lit) mod.Color.white else mod.Color.white.withAlpha(0.92);
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, knob_color);
    }

    /// `Painter.stepper_box`.
    fn stepperBox(surface: mod.Surface, rect: mod.Rect, state: mod.ControlState) std.mem.Allocator.Error!void {
        _ = state;
        // Native steppers are a flat grey chevron column — same fill as the
        // segmented trough, no border.
        try surface.fill(rect, 7, surface.palette.control_track);
    }

    /// `Painter.progress`.
    fn progress(surface: mod.Surface, rect: mod.Rect, fraction: f32) std.mem.Allocator.Error!void {
        const radius = rect.height / 2;
        const lit = surface.scheme == .light;
        const trough = if (lit) mod.Color.black.withAlpha(0.10) else mod.Color.white.withAlpha(0.09);
        try surface.fill(rect, radius, trough);
        const filled = mod.Rect{ .x = rect.x, .y = rect.y, .width = rect.width * std.math.clamp(fraction, 0, 1), .height = rect.height };
        try surface.fill(filled, radius, surface.palette.selection);
    }

    /// `Painter.panel`.
    fn panel(surface: mod.Surface, rect: mod.Rect, radius: f32, kind: mod.PanelKind) std.mem.Allocator.Error!void {
        // A wide ambient shadow halo grounds the floating panel.
        var ring: f32 = 1;
        while (ring <= 5) : (ring += 1) {
            try surface.stroke(rect.insetBy(-ring, -ring), radius + ring, 2, mod.Color.black.withAlpha(0.06 - ring * 0.009));
        }
        const lit = surface.scheme == .light;
        switch (kind) {
            // Native sheets/alerts are *opaque* elevated panels: white in light
            // mode, near-black (#161616) with a faint rim in dark mode.
            .modal => {
                const background = if (lit) mod.Color.white else mod.Color.fromRgb8(22, 22, 22);
                try surface.fill(rect, radius, background);
                if (!lit) try surface.stroke(rect, radius, 1, mod.Color.white.withAlpha(0.13));
            },
            // Popovers/menus are frosted material.
            .popover => {
                try surface.backdropBlur(rect, radius, Self.popover_sigma, surface.palette.glass);
                const rim = if (lit) mod.Color.black.withAlpha(0.08) else mod.Color.white.withAlpha(0.13);
                try surface.stroke(rect, radius, surface.metrics.hairline, rim);
            },
        }
    }

    /// The `.glassEffect()` surface: the same neutral clear glass as a button at
    /// rest (frost + sheen + rim + soft shadow).
    fn glassSurface(surface: mod.Surface, rect: mod.Rect, radius: f32) std.mem.Allocator.Error!void {
        try Self.clearGlass(surface, rect, radius, .{}, 1);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "macos: light and dark differ in background and label" {
    try std.testing.expect(!MacosTheme.light.colors.window_background.approxEql(MacosTheme.dark.colors.window_background, 0.01));
    // light label is dark-on-light; dark label is light-on-dark
    try std.testing.expect(MacosTheme.light.colors.label.isDark());
    try std.testing.expect(!MacosTheme.dark.colors.label.isDark());
}

test "macos: body font is 13pt regular" {
    try std.testing.expectEqual(@as(f32, 13), MacosTheme.light.typography.body.size);
    try std.testing.expectEqual(mod.FontWeight.regular, MacosTheme.light.typography.body.weight);
}

test "macos: accent is a recognizable blue" {
    const accent = MacosTheme.light.colors.accent;
    try std.testing.expect(accent.b > accent.r and accent.b > accent.g); // blue dominant
}

test "macos: default is light" {
    try std.testing.expectEqual(mod.ColorScheme.light, mod.Theme.default.scheme);
}

test "macos: liquid glass buttons frost their backdrop" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const surface = mod.Surface{ .canvas = &canvas, .palette = &MacosTheme.light.colors, .metrics = &MacosTheme.light.metrics, .scheme = .light };
    const rect = mod.Rect{ .x = 0, .y = 0, .width = 80, .height = 28 };
    const label_color = try MacosTheme.painter.button(surface, rect, .normal, .{});
    // Neutral glass keeps the ordinary label color…
    try std.testing.expect(label_color.approxEql(MacosTheme.light.colors.label, 0.001));
    // …and draws a backdrop frost (after the drop shadow).
    var saw_blur = false;
    for (canvas.commands.items) |command| {
        if (command == .blurRect) saw_blur = true;
    }
    try std.testing.expect(saw_blur);
}

test "macos: prominent and destructive buttons are tinted glass" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const surface = mod.Surface{ .canvas = &canvas, .palette = &MacosTheme.light.colors, .metrics = &MacosTheme.light.metrics, .scheme = .light };
    const rect = mod.Rect{ .x = 0, .y = 0, .width = 80, .height = 28 };
    try std.testing.expect((try MacosTheme.painter.button(surface, rect, .prominent, .{})).approxEql(MacosTheme.light.colors.on_accent, 0.001));
    try std.testing.expect((try MacosTheme.painter.button(surface, rect, .destructive, .{})).approxEql(MacosTheme.light.colors.on_accent, 0.001));
}

test "macos: popover panels are deep-frosted glass; modals are opaque" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const surface = mod.Surface{ .canvas = &canvas, .palette = &MacosTheme.dark.colors, .metrics = &MacosTheme.dark.metrics, .scheme = .dark };
    try MacosTheme.painter.panel(surface, .{ .x = 10, .y = 10, .width = 200, .height = 120 }, 16, .popover);
    var saw_blur = false;
    for (canvas.commands.items) |command| {
        if (command == .blurRect) {
            saw_blur = true;
            try std.testing.expect(command.blurRect.sigma > MacosTheme.control_sigma);
        }
    }
    try std.testing.expect(saw_blur);
    // A modal sheet/alert is an opaque elevated panel — no backdrop sampling.
    canvas.clearCommands();
    try MacosTheme.painter.panel(surface, .{ .x = 10, .y = 10, .width = 200, .height = 120 }, 16, .modal);
    for (canvas.commands.items) |command| try std.testing.expect(command != .blurRect);
}
