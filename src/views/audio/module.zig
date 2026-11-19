//! Audio outputs: the devices sound can play through, listed by the
//! `AudioOutputBackend` the SDL runtime installs, which `Player.setAudioOutput`
//! routes a player's sound to.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_module);

/// One device sound can play through.
pub const AudioOutput = @import("audio_output.zig").AudioOutput;
/// A platform's audio device listing, installed by the SDL runtime.
pub const AudioOutputBackend = @import("audio_output_backend.zig").AudioOutputBackend;
/// The system's audio outputs, through the installed backend.
pub const AudioOutputs = @import("audio_outputs.zig").AudioOutputs;
/// Builds the list a backend returns: strings copied, each id once.
pub const AudioOutputCollector = @import("audio_output_collector.zig").AudioOutputCollector;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("audio_output.zig");
    _ = @import("audio_output_backend.zig");
    _ = @import("audio_outputs.zig");
    _ = @import("audio_output_collector.zig");
}
