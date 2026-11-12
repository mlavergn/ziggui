//! Translucent, blurred backgrounds, like macOS sidebars and HUDs.

const std = @import("std");
const log = std.log.scoped(.ziggui_material);

/// A material's blur `sigma` and the `alpha_scale` applied to the active
/// theme's `Palette.glass` tint (so the frost is scheme-correct: light glass
/// in light mode, dark glass in dark mode).
pub const MaterialSpecification = struct {
    const Self = @This();

    /// How much of the theme's glass tint shows.
    alpha_scale: f32,

    /// The blur radius.
    sigma: f32,
};

/// A translucent, blurred "material" (vibrancy) like macOS sidebars and HUDs.
/// Each level pairs a frost tint with a blur sigma. Painted via `blurRect`,
/// so it frosts whatever was drawn beneath it.
pub const Material = enum {
    const Self = @This();

    /// The faintest frost.
    ultraThin,
    /// A light frost.
    thin,
    /// The usual frost.
    regular,
    /// The heaviest frost.
    thick,

    /// The level's tint scale and blur.
    ///
    /// - `self`: the material.
    /// - Returns: its specification.
    pub fn specification(self: *const Self) MaterialSpecification {
        return switch (self.*) {
            .ultraThin => .{ .alpha_scale = 0.35, .sigma = 8 },
            .thin => .{ .alpha_scale = 0.55, .sigma = 10 },
            .regular => .{ .alpha_scale = 0.85, .sigma = 12 },
            .thick => .{ .alpha_scale = 1.0, .sigma = 14 },
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
