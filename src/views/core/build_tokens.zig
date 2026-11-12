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

    /// The diff green on a light background.
    const light_added = renderer.Color.fromRgb8(36, 138, 61);

    /// The diff green on a dark background.
    const dark_added = renderer.Color.fromRgb8(63, 185, 80);

    /// The diff red on a light background.
    const light_removed = renderer.Color.fromRgb8(207, 34, 46);

    /// The diff red on a dark background.
    const dark_removed = renderer.Color.fromRgb8(248, 81, 73);

    /// The tokens for `theme`.
    ///
    /// - `theme`: the theme the app publishes.
    /// - Returns: its build-time colors.
    pub fn fromTheme(theme: renderer.Theme) Self {
        const dark = theme.scheme == .dark;
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
            .added = if (dark) dark_added else light_added,
            .removed = if (dark) dark_removed else light_removed,
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
