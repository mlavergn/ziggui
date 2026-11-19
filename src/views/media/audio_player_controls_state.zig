//! What an `AudioPlayerControls` keeps across frames: the transport it shares
//! with the video controls (speed, play, the scrubber), its own skip lengths
//! (back 15 s, on 30 s, as a podcast player skips), and whether the volume
//! popover is up.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_player_controls_state);
const mod = @import("module.zig");

/// What an `AudioPlayerControls` keeps across frames, owned by the app: the
/// buttons' actions are its methods, so their callbacks point at memory that
/// outlives the frame.
pub const AudioPlayerControlsState = struct {
    const Self = @This();

    /// The transport shared with the video controls: the speed, play and
    /// pause, mute, the scrubber's binding, the player (set as the controls
    /// build); the bar's play, speed and mute buttons call its methods.
    transport: mod.VideoPlayerControlsState = .{},

    /// How far the back button moves the playhead, in seconds.
    skip_back_seconds: f64 = 15,

    /// How far the forward button moves the playhead, in seconds.
    skip_forward_seconds: f64 = 30,

    /// Whether the volume popover is up.
    volume_shown: bool = false,

    /// Moves the playhead `skip_back_seconds` back.
    ///
    /// - `self`: the state.
    pub fn skipBack(self: *Self) void {
        self.transport.skipBy(-self.skip_back_seconds);
    }

    /// Moves the playhead `skip_forward_seconds` on.
    ///
    /// - `self`: the state.
    pub fn skipForward(self: *Self) void {
        self.transport.skipBy(self.skip_forward_seconds);
    }

    /// Shows the volume popover, or hides it.
    ///
    /// - `self`: the state.
    pub fn toggleVolume(self: *Self) void {
        self.volume_shown = !self.volume_shown;
    }

    /// Whether the volume popover is up, as a binding (a tap on its scrim
    /// clears it).
    ///
    /// - `self`: the state; must outlive the view.
    /// - Returns: the binding.
    pub fn volumeShownBinding(self: *Self) mod.Binding(bool) {
        return .{ .context = self, .get_fn = Self.boundVolumeShown, .set_fn = Self.bindVolumeShown };
    }

    /// `volumeShownBinding`'s reader.
    ///
    /// - `context`: the state.
    /// - Returns: whether the popover is up.
    fn boundVolumeShown(context: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.volume_shown;
    }

    /// `volumeShownBinding`'s writer.
    ///
    /// - `context`: the state.
    /// - `shown`: whether the popover is up.
    fn bindVolumeShown(context: *anyopaque, shown: bool) void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.volume_shown = shown;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the audio controls skip back 15 s and on 30 s, and play at the chosen speed" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: AudioPlayerControlsState = .{};
    state.transport.player = &player;
    state.skipForward();
    try std.testing.expectEqual(@as(?f64, 30), player.seek_target);
    state.skipBack();
    try std.testing.expectEqual(@as(?f64, 0), player.seek_target);
    state.transport.nextRate();
    state.transport.togglePlay();
    try std.testing.expectEqual(@as(f32, 1.25), player.rate);
    state.toggleVolume();
    try std.testing.expect(state.volumeShownBinding().get());
    state.volumeShownBinding().set(false);
    try std.testing.expect(!state.volume_shown);
}
