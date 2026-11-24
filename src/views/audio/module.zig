//! Audio outputs: the devices sound can play through, listed by the
//! `AudioOutputBackend` the SDL runtime installs, which `Player.setAudioOutput`
//! routes a player's sound to. And sound recorded and played apart from any
//! `Player`: `AudioRecorder` and `AudioClipPlayer` over SDL's audio devices
//! (`AudioDevices`, the `AudioDeviceBackend` the runtime installs), each take
//! an `AudioClip` an app stores as a WAV file.

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
/// What `AudioClip.decodeWav` refuses, and allocation failure.
pub const AudioClipError = @import("audio_clip.zig").AudioClipError;
/// What a WAV file's header says of its sound (`AudioClip.inspectWav`).
pub const AudioClipInfo = @import("audio_clip.zig").AudioClipInfo;
/// A mono 16-bit sound in memory, read from and written to WAV bytes.
pub const AudioClip = @import("audio_clip.zig").AudioClip;
/// Which way sound goes through an audio device.
pub const AudioDirection = @import("audio_direction.zig").AudioDirection;
/// One device the recorder or the clip player can open.
pub const AudioDevice = @import("audio_device.zig").AudioDevice;
/// The platform's audio streams, installed by the SDL runtime.
pub const AudioDeviceBackend = @import("audio_device_backend.zig").AudioDeviceBackend;
/// The installed audio device backend, and its device lists.
pub const AudioDevices = @import("audio_devices.zig").AudioDevices;
/// What a recorder is doing.
pub const AudioRecorderStatus = @import("audio_recorder.zig").AudioRecorderStatus;
/// A microphone recorder modeled on `AVAudioRecorder`.
pub const AudioRecorder = @import("audio_recorder.zig").AudioRecorder;
/// Plays an `AudioClip`, modeled on `AVAudioPlayer`.
pub const AudioClipPlayer = @import("audio_clip_player.zig").AudioClipPlayer;
/// One fake stream of `TestAudioDevices`.
pub const TestAudioStream = @import("test_audio_devices.zig").TestAudioStream;
/// A fake audio device backend for tests.
pub const TestAudioDevices = @import("test_audio_devices.zig").TestAudioDevices;
/// A two-way binding, as `AudioClipPlayer.volumeBinding` makes one.
pub const Binding = @import("../module.zig").Binding;
/// The frame clock the recorder and the clip player ask frames of.
pub const FrameClock = @import("../module.zig").FrameClock;

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
    _ = @import("audio_clip.zig");
    _ = @import("audio_direction.zig");
    _ = @import("audio_device.zig");
    _ = @import("audio_device_backend.zig");
    _ = @import("audio_devices.zig");
    _ = @import("audio_recorder.zig");
    _ = @import("audio_clip_player.zig");
    _ = @import("test_audio_devices.zig");
}
