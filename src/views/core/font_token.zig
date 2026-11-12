//! Named typographic styles, resolved against the theme at paint time.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_token);
const renderer = @import("renderer");

/// Named typographic styles, resolved against the active theme at paint time
/// (so `.font(.title)` honors theming and dark mode).
pub const FontToken = enum {
    const Self = @This();

    /// The largest title.
    largeTitle,
    /// A title.
    title,
    /// A second-level title.
    title2,
    /// A third-level title.
    title3,
    /// A bold heading line.
    headline,
    /// Body text.
    body,
    /// A callout.
    callout,
    /// A subheading.
    subheadline,
    /// A footnote.
    footnote,
    /// A caption.
    caption,
    /// A smaller caption.
    caption2,

    /// The theme's text style for this token.
    ///
    /// - `self`: the token.
    /// - `theme`: the theme resolved against.
    /// - Returns: the style (size and weight).
    pub fn style(self: *const Self, theme: renderer.Theme) renderer.TextStyle {
        return switch (self.*) {
            .largeTitle => theme.typography.large_title,
            .title => theme.typography.title,
            .title2 => theme.typography.title2,
            .title3 => theme.typography.title3,
            .headline => theme.typography.headline,
            .body => theme.typography.body,
            .callout => theme.typography.callout,
            .subheadline => theme.typography.subheadline,
            .footnote => theme.typography.footnote,
            .caption => theme.typography.caption,
            .caption2 => theme.typography.caption2,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
