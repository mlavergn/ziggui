//! One device `AudioRecorder` records from or `AudioClipPlayer` plays
//! through, as `AudioDevices.list` reports it: SDL's audio devices, apart
//! from the `AudioOutput`s a `Player` routes its sound to.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_device);

/// One audio device the recorder or the clip player can open.
pub const AudioDevice = struct {
    const Self = @This();

    /// The backend's id for the device, valid while it stays plugged in
    /// (SDL's `SDL_AudioDeviceID`; not an `AudioOutput.id`).
    id: u32,

    /// The device's name as the system shows it ("MacBook Pro Microphone").
    name: []const u8,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
