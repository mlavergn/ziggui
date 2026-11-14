//! The theme colors composed (theme-less) constructors read at build time.

const std = @import("std");
const log = std.log.scoped(.ziggui_build_tokens);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The handful of theme colors that *composed* (theme-less) constructors need at
/// build time — selection tints for `Sidebar`/`Table`/`RadioGroup`, and the
/// text, hairline and diff colors ziggui's widgets tint with. Constructors have
/// no `Context`, so the app publishes these once per frame with
/// `BuildScope.setTheme`. The defaults match the macOS light theme, so headless
/// tests and un-wired callers render correctly without any setup.
pub const BuildTokens = struct {
    const Self = @This();

    /// The accent color.
    accent: renderer.Color = renderer.Color.fromRgb8(0, 122, 255),

    /// Content drawn on the accent.
    on_accent: renderer.Color = renderer.Color.white,

    /// Selected-content tint (AppKit's controlAccentColor — selected table
    /// rows, radio dots). Slightly muted vs `accent` on macOS.
    selection: renderer.Color = renderer.Color.fromRgb8(52, 120, 246),

    /// Neutral selected-row fill (macOS 26 sidebar selection is grey).
    quaternary_fill: renderer.Color = renderer.Color.black.withAlpha(0.12),

    /// Secondary text color, for subtitles in composed rows.
    secondary_label: renderer.Color = renderer.Color.fromRgb8(122, 122, 122),

    /// Subtle fill behind a hovered row.
    hover: renderer.Color = renderer.Color.black.withAlpha(0.06),

    /// Alternating-row stripe in tables.
    row_stripe: renderer.Color = renderer.Color.black.withAlpha(0.03),

    /// Primary text, for composed rows that tint some cells.
    label: renderer.Color = renderer.MacosTheme.light.colors.label,

    /// Hairline color, for composed separators.
    separator: renderer.Color = renderer.MacosTheme.light.colors.separator,

    /// An added line's text in a diff: a green that reads on the scheme.
    added: renderer.Color = light_added,

    /// A removed line's text in a diff: a red that reads on the scheme.
    removed: renderer.Color = light_removed,

    /// Amber text for a warning: a caution that is not yet an error.
    warning: renderer.Color = light_warning,

    /// Blue text for information: a neutral notice that is not the accent.
    info: renderer.Color = light_info,

    /// A success badge's soft ground: `added` at a low alpha.
    success_soft: renderer.Color = light_added.withAlpha(light_soft_alpha),

    /// A danger badge's soft ground: `removed` at a low alpha.
    danger_soft: renderer.Color = light_removed.withAlpha(light_soft_alpha),

    /// A warning badge's soft ground: `warning` at a low alpha.
    warning_soft: renderer.Color = light_warning.withAlpha(light_soft_alpha),

    /// An info badge's soft ground: `info` at a low alpha.
    info_soft: renderer.Color = light_info.withAlpha(light_soft_alpha),

    /// A neutral badge's or key cap's soft ground: `secondary_label` at a low alpha.
    neutral_soft: renderer.Color = renderer.MacosTheme.light.colors.secondary_label.withAlpha(light_soft_alpha),

    /// The accent as readable text (a link, an accent badge's label).
    accent_text: renderer.Color = renderer.MacosTheme.light.colors.accent,

    /// The accent as a mark on a ground (a dot, a bar, a selected glyph).
    accent_mark: renderer.Color = renderer.MacosTheme.light.colors.accent,

    /// An accent badge's soft ground: the accent at a low alpha.
    accent_soft: renderer.Color = renderer.MacosTheme.light.colors.accent.withAlpha(accent_soft_alpha),

    /// The ground of code wells and lists, sunk below the window.
    sunken: renderer.Color = renderer.MacosTheme.light.colors.secondary_background,

    /// The ground of fields and thumbs, raised above the window.
    raised: renderer.Color = renderer.MacosTheme.light.colors.control_background,

    /// Tertiary text: placeholders, disabled labels.
    tertiary_label: renderer.Color = renderer.MacosTheme.light.colors.tertiary_label,

    /// A control's border, stronger than `separator`.
    line_strong: renderer.Color = renderer.MacosTheme.light.colors.control_border,

    /// The ring around a focused control.
    focus_ring: renderer.Color = renderer.MacosTheme.light.colors.accent,

    /// The ground of a bar along a window's edge (a key-hint bar): the
    /// theme's sidebar background, else its window background.
    bar_background: renderer.Color = renderer.MacosTheme.light.colors.sidebar_background orelse renderer.MacosTheme.light.colors.window_background,

    /// The diff green on a light background.
    const light_added = renderer.Color.fromRgb8(36, 138, 61);

    /// The diff green on a dark background.
    const dark_added = renderer.Color.fromRgb8(63, 185, 80);

    /// The diff red on a light background.
    const light_removed = renderer.Color.fromRgb8(207, 34, 46);

    /// The diff red on a dark background.
    const dark_removed = renderer.Color.fromRgb8(248, 81, 73);

    /// The warning amber on a light background.
    const light_warning = renderer.Color.fromRgb8(138, 97, 0);

    /// The warning amber on a dark background.
    const dark_warning = renderer.Color.fromRgb8(255, 204, 51);

    /// The info blue on a light background.
    const light_info = renderer.Color.fromRgb8(10, 95, 199);

    /// The info blue on a dark background.
    const dark_info = renderer.Color.fromRgb8(92, 171, 255);

    /// A soft ground's alpha over its strong hue on a light background.
    const light_soft_alpha: f32 = 0.14;

    /// A soft ground's alpha over its strong hue on a dark background.
    const dark_soft_alpha: f32 = 0.22;

    /// An accent badge's soft ground's alpha over the accent, in either scheme.
    const accent_soft_alpha: f32 = 0.15;

    /// The tokens for `theme`.
    ///
    /// - `theme`: the theme the app publishes.
    /// - Returns: its build-time colors.
    pub fn fromTheme(theme: renderer.Theme) Self {
        const dark = theme.scheme == .dark;
        const added = if (dark) dark_added else light_added;
        const removed = if (dark) dark_removed else light_removed;
        const warning = if (dark) dark_warning else light_warning;
        const info = if (dark) dark_info else light_info;
        const soft_alpha = if (dark) dark_soft_alpha else light_soft_alpha;
        const self = Self{
            .accent = theme.colors.accent,
            .on_accent = theme.colors.on_accent,
            .selection = theme.colors.selection,
            .quaternary_fill = theme.colors.quaternary_fill,
            .secondary_label = theme.colors.secondary_label,
            .hover = theme.colors.hover,
            .row_stripe = if (theme.scheme == .dark) renderer.Color.white.withAlpha(0.04) else renderer.Color.black.withAlpha(0.03),
            .label = theme.colors.label,
            .separator = theme.colors.separator,
            .added = added,
            .removed = removed,
            .warning = warning,
            .info = info,
            .success_soft = added.withAlpha(soft_alpha),
            .danger_soft = removed.withAlpha(soft_alpha),
            .warning_soft = warning.withAlpha(soft_alpha),
            .info_soft = info.withAlpha(soft_alpha),
            .neutral_soft = theme.colors.secondary_label.withAlpha(soft_alpha),
            .accent_text = theme.colors.accent,
            .accent_mark = theme.colors.accent,
            .accent_soft = theme.colors.accent.withAlpha(accent_soft_alpha),
            .sunken = theme.colors.secondary_background,
            .raised = theme.colors.control_background,
            .tertiary_label = theme.colors.tertiary_label,
            .line_strong = theme.colors.control_border,
            .focus_ring = theme.colors.accent,
            .bar_background = theme.colors.sidebar_background orelse theme.colors.window_background,
        };
        return self;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "tokens follow the published theme's scheme" {
    const scope = mod.BuildScope.shared();
    scope.setTheme(renderer.MacosTheme.dark);
    defer scope.setTheme(renderer.MacosTheme.light);
    const dark = scope.tokens();
    try std.testing.expectEqual(renderer.MacosTheme.dark.colors.label, dark.label);
    try std.testing.expectEqual(BuildTokens.dark_added, dark.added);
    try std.testing.expectEqual(renderer.MacosTheme.dark.colors.accent, dark.accent);

    scope.setTheme(renderer.MacosTheme.light);
    const light = scope.tokens();
    try std.testing.expectEqual(renderer.MacosTheme.light.colors.separator, light.separator);
    try std.testing.expectEqual(BuildTokens.light_removed, light.removed);
}

test "the design roles follow the scheme, and the defaults are the macOS light theme's" {
    const defaults = BuildTokens{};
    const light = BuildTokens.fromTheme(renderer.MacosTheme.light);
    const roles = .{ "warning", "info", "success_soft", "danger_soft", "warning_soft", "info_soft", "neutral_soft", "accent_text", "accent_mark", "accent_soft", "sunken", "raised", "tertiary_label", "line_strong", "focus_ring", "bar_background" };
    inline for (roles) |role| {
        try std.testing.expect(@field(defaults, role).approxEql(@field(light, role), 0.002));
    }
    const dark = BuildTokens.fromTheme(renderer.MacosTheme.dark);
    try std.testing.expectEqual(BuildTokens.dark_warning, dark.warning);
    try std.testing.expectEqual(BuildTokens.dark_info, dark.info);
    try std.testing.expectEqual(BuildTokens.dark_added.withAlpha(BuildTokens.dark_soft_alpha), dark.success_soft);
    try std.testing.expectEqual(renderer.MacosTheme.dark.colors.control_background, dark.raised);
    try std.testing.expectEqual(renderer.MacosTheme.dark.colors.sidebar_background.?, dark.bar_background);
}
