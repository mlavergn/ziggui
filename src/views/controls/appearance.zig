//! The light-or-dark choice an `AppearancePicker` offers: follow the system,
//! or keep one.

const std = @import("std");
const log = std.log.scoped(.ziggui_appearance);
const renderer = @import("renderer");

/// An app's appearance setting, as macOS's Appearance setting offers it:
/// follow the system's light or dark mode, or keep one. An `AppearancePicker`
/// binds to its index (`@backingInt`), as every ziggui selector binds an `i64`.
pub const Appearance = enum {
    const Self = @This();

    /// Follow the system: light or dark as it is.
    automatic,

    /// Always light.
    light,

    /// Always dark.
    dark,

    /// Every appearance, in the order a picker shows them.
    pub const all = [_]Self{ .automatic, .light, .dark };

    /// The appearance a selection's index names.
    ///
    /// - `index`: the index, as an `AppearancePicker`'s binding holds it.
    /// - Returns: the appearance; an index past the ends is clamped to them.
    pub fn at(index: i64) Self {
        return all[@intCast(std.math.clamp(index, 0, all.len - 1))];
    }

    /// What a picker calls it, as macOS does.
    ///
    /// - `self`: the appearance.
    /// - Returns: "Auto", "Light" or "Dark".
    pub fn title(self: *const Self) []const u8 {
        return switch (self.*) {
            .automatic => "Auto",
            .light => "Light",
            .dark => "Dark",
        };
    }

    /// The color scheme to draw in.
    ///
    /// - `self`: the appearance.
    /// - `system`: the system's color scheme now.
    /// - Returns: `system` when following it, else the one kept.
    pub fn resolved(self: *const Self, system: renderer.ColorScheme) renderer.ColorScheme {
        return switch (self.*) {
            .automatic => system,
            .light => .light,
            .dark => .dark,
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

test "an appearance follows the system only when automatic, and an index is clamped" {
    try std.testing.expectEqual(renderer.ColorScheme.dark, Appearance.automatic.resolved(.dark));
    try std.testing.expectEqual(renderer.ColorScheme.light, Appearance.light.resolved(.dark));
    try std.testing.expectEqual(renderer.ColorScheme.dark, Appearance.dark.resolved(.light));
    try std.testing.expectEqual(Appearance.dark, Appearance.at(2));
    try std.testing.expectEqual(Appearance.automatic, Appearance.at(-4));
    try std.testing.expectEqual(Appearance.dark, Appearance.at(9));
    try std.testing.expectEqualStrings("Auto", Appearance.automatic.title());
}
