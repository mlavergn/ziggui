const std = @import("std");
const log = std.log.scoped(.ziggui_build_tokens);
const zigui = @import("zigui");

/// The theme colors composed (theme-less) constructors need at build time:
/// zigui's `BuildTokens`, plus the text, hairline and diff colors ziggui's
/// widgets tint with.
///
/// Constructors have no `Context`, so these come from the theme the app last
/// published with `setThemeTokens` (`zigui.buildTheme`). The defaults match
/// the macOS light theme, so headless tests render without any setup. Mirror
/// any field zigui adds to its `BuildTokens` here.
pub const BuildTokens = struct {
    const Self = @This();

    /// The accent color.
    accent: zigui.Color = zigui.Color.fromRgb8(0, 122, 255),

    /// Content drawn on the accent.
    on_accent: zigui.Color = zigui.Color.white,

    /// Selected-content tint (selected table rows, radio dots).
    selection: zigui.Color = zigui.Color.fromRgb8(52, 120, 246),

    /// Neutral selected-row fill.
    quaternary_fill: zigui.Color = zigui.Color.black.withAlpha(0.12),

    /// Secondary text, for subtitles in composed rows.
    secondary_label: zigui.Color = zigui.Color.fromRgb8(122, 122, 122),

    /// Subtle fill behind a hovered row.
    hover: zigui.Color = zigui.Color.black.withAlpha(0.06),

    /// Alternating-row stripe in tables.
    row_stripe: zigui.Color = zigui.Color.black.withAlpha(0.03),

    /// Primary text, for composed rows that tint some cells.
    label: zigui.Color = zigui.Color.black,

    /// Hairline color, for composed separators.
    separator: zigui.Color = zigui.Color.black.withAlpha(0.1),

    /// An added line's text in a diff: a green that reads on the scheme.
    added: zigui.Color = light_added,

    /// A removed line's text in a diff: a red that reads on the scheme.
    removed: zigui.Color = light_removed,

    /// The diff green on a light background.
    const light_added = zigui.Color.fromRgb8(36, 138, 61);

    /// The diff green on a dark background.
    const dark_added = zigui.Color.fromRgb8(63, 185, 80);

    /// The diff red on a light background.
    const light_removed = zigui.Color.fromRgb8(207, 34, 46);

    /// The diff red on a dark background.
    const dark_removed = zigui.Color.fromRgb8(248, 81, 73);

    /// The tokens for the theme the app last published.
    ///
    /// - Returns: zigui's build tokens with ziggui's colors derived from the same theme.
    pub fn current() Self {
        return Self.from(zigui.buildTokens(), zigui.buildTheme());
    }

    /// The tokens for `theme`, given zigui's tokens for it.
    ///
    /// - `base`: zigui's build tokens.
    /// - `theme`: the theme `base` was published from.
    /// - Returns: `base`'s colors plus ziggui's, derived from `theme`.
    pub fn from(base: zigui.BuildTokens, theme: zigui.Theme) Self {
        const dark = theme.scheme == .dark;
        const self = Self{
            .accent = base.accent,
            .on_accent = base.on_accent,
            .selection = base.selection,
            .quaternary_fill = base.quaternary_fill,
            .secondary_label = base.secondary_label,
            .hover = base.hover,
            .row_stripe = base.row_stripe,
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
    zigui.setThemeTokens(zigui.macos.dark);
    defer zigui.setThemeTokens(zigui.macos.light);
    const dark = BuildTokens.current();
    try std.testing.expectEqual(zigui.macos.dark.colors.label, dark.label);
    try std.testing.expectEqual(BuildTokens.dark_added, dark.added);
    try std.testing.expectEqual(zigui.buildTokens().accent, dark.accent);

    zigui.setThemeTokens(zigui.macos.light);
    const light = BuildTokens.current();
    try std.testing.expectEqual(zigui.macos.light.colors.separator, light.separator);
    try std.testing.expectEqual(BuildTokens.light_removed, light.removed);
}
