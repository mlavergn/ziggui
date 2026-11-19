//! One device sound can play through (speakers, headphones, an HDMI display),
//! as `AudioOutputs.list` reports it and `Player.setAudioOutput` takes it.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_output);

/// One audio output device.
pub const AudioOutput = struct {
    const Self = @This();

    /// The platform's name for the device, stable while it stays plugged in,
    /// which `Player.setAudioOutput` routes a player's sound by (on Linux
    /// PipeWire's `node.name`, else the device's description).
    id: []const u8,

    /// The device's name as the system shows it ("Built-in Audio Analog Stereo").
    name: []const u8,

    /// The system's default output now, which a player with no output of its
    /// own plays through.
    is_default: bool = false,

    /// What follows the device's name where it is listed: " (default)" for
    /// the system's default, else nothing.
    ///
    /// - `self`: the output.
    /// - Returns: the mark, static.
    pub fn defaultMark(self: *const Self) []const u8 {
        return if (self.is_default) " (default)" else "";
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
