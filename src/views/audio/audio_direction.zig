//! Which way sound goes through an audio device: in from a microphone
//! (`AudioRecorder`) or out to a speaker (`AudioClipPlayer`).

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_direction);

/// Which way sound goes through a device.
pub const AudioDirection = enum {
    const Self = @This();

    /// In: a microphone, a line input.
    recording,
    /// Out: speakers, headphones.
    playback,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
