//! How a scene's light is brought into the display's range.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_tone_mapping);

/// How a scene's light, after its exposure (`Scene.exposure`), is brought
/// into what a display shows.
pub const SceneToneMapping = enum {
    const Self = @This();

    /// Clamped at white: what's brighter clips (the light's own colors kept below).
    none,
    /// A film's curve (ACES, Narkowicz's fit): a toe darkening the deepest
    /// shadows, a shoulder rolling highlights off toward white rather than
    /// clipping them, so light brighter than white still shows its form.
    filmic,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
