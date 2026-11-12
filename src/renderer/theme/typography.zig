//! The typographic scale, mirroring SwiftUI's `Font.TextStyle` cases.

const std = @import("std");
const log = std.log.scoped(.ziggui_typography);
const mod = @import("module.zig");

/// A theme's text styles.
pub const Typography = struct {
    const Self = @This();

    /// `.largeTitle`.
    large_title: mod.TextStyle,
    /// `.title`.
    title: mod.TextStyle,
    /// `.title2`.
    title2: mod.TextStyle,
    /// `.title3`.
    title3: mod.TextStyle,
    /// `.headline`.
    headline: mod.TextStyle,
    /// `.body`, the default.
    body: mod.TextStyle,
    /// `.callout`.
    callout: mod.TextStyle,
    /// `.subheadline`.
    subheadline: mod.TextStyle,
    /// `.footnote`.
    footnote: mod.TextStyle,
    /// `.caption`.
    caption: mod.TextStyle,
    /// `.caption2`.
    caption2: mod.TextStyle,

    /// The default font for unstyled text.
    ///
    /// - `self`: the scale.
    /// - Returns: the body style.
    pub fn defaultStyle(self: *const Self) mod.TextStyle {
        return self.body;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
