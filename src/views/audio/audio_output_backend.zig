//! The platform's audio devices, as function pointers: the SDL runtime installs
//! its own as its loop starts (as it does a `PlayerBackend`), so the views stay
//! free of platform code, and tests install a fake.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_output_backend);
const mod = @import("module.zig");

/// One platform's audio device listing. It runs on the UI thread.
pub const AudioOutputBackend = struct {
    const Self = @This();

    /// Lists the devices sound can play through now, each once, probing the
    /// system (call it when a menu opens, not every frame).
    ///
    /// - `allocator`: owns the list and its strings (an arena suits).
    /// - Returns: the outputs, none where the system reports none; propagates
    ///   allocation failure.
    list: *const fn (allocator: std.mem.Allocator) std.mem.Allocator.Error![]mod.AudioOutput,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
