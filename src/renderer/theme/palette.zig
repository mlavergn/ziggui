//! Semantic color roles, resolved for a single `ColorScheme`.

const std = @import("std");
const log = std.log.scoped(.ziggui_palette);
const mod = @import("module.zig");

/// Semantic color roles, resolved for a single `ColorScheme`. The first block
/// follows macOS's dynamic system colors; the bevel block at the end is only
/// meaningful for chiseled (Windows-9x/2000) painters and is defaulted so flat
/// themes can ignore it.
pub const Palette = struct {
    const Self = @This();

    /// The accent / tint color (macOS "System Blue" by default).
    accent: mod.Color,
    /// Primary text/content color (labelColor).
    label: mod.Color,
    /// Secondary text (secondaryLabelColor).
    secondary_label: mod.Color,
    /// Tertiary text (tertiaryLabelColor).
    tertiary_label: mod.Color,
    /// Color for content drawn on top of the accent (e.g. button text).
    on_accent: mod.Color,
    /// Window / scene background.
    window_background: mod.Color,
    /// Background for grouped content areas.
    secondary_background: mod.Color,
    /// Fill for controls (text fields, etc.).
    control_background: mod.Color,
    /// Hairline separators / dividers.
    separator: mod.Color,
    /// Selection highlight.
    selection: mod.Color,
    /// Destructive / error (System Red).
    destructive: mod.Color,

    // --- Translucent "liquid glass" roles (macOS) -------------------------
    /// A subtle fill painted behind a control/row while the cursor hovers it.
    hover: mod.Color,
    /// The bright hairline edge along the top/sides of a glass control.
    control_border: mod.Color,
    /// A translucent tint laid over blurred content for glass panels.
    glass: mod.Color,
    /// Fill for an unselected segmented/glass control track.
    control_track: mod.Color,
    /// The dimming wash drawn across the window beneath a modal overlay.
    scrim: mod.Color = mod.Color.black.withAlpha(0.2),
    /// Neutral selected-row fill (macOS sidebar selection is grey, not accent).
    quaternary_fill: mod.Color = mod.Color.black.withAlpha(0.10),
    /// Sidebar pane background, when it differs from `secondary_background`
    /// (macOS sidebars are #FAFAFA light / #1A1B1B dark). Null = fall back to
    /// `secondary_background`.
    sidebar_background: ?mod.Color = null,

    // --- Chiseled bevel roles (Windows 2000 / 9x) -------------------------
    // The 3D edge colors of the classic raised/sunken look. Defaulted so flat
    // and glass themes need not spell them out.
    /// The face color of a raised control (the button body).
    control_face: mod.Color = mod.Color.fromRgb8(212, 208, 200),
    /// Brightest bevel edge (outer top-left of a raised control).
    control_highlight: mod.Color = mod.Color.white,
    /// Light bevel edge (inner top-left).
    control_light: mod.Color = mod.Color.fromRgb8(223, 223, 223),
    /// Shadow bevel edge (inner bottom-right).
    control_shadow: mod.Color = mod.Color.fromRgb8(128, 128, 128),
    /// Darkest bevel edge (outer bottom-right).
    control_dark_shadow: mod.Color = mod.Color.fromRgb8(64, 64, 64),
    /// Label color on a raised/grey control (vs. `on_accent` for tinted ones).
    on_control: mod.Color = mod.Color.black,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Palette: bevel tokens default for non-chiseled themes" {
    // macOS doesn't set bevel tokens, so they fall back to the struct defaults.
    try std.testing.expect(mod.MacosTheme.light.colors.control_highlight.approxEql(mod.Color.white, 0.001));
}
