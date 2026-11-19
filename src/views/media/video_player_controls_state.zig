//! What a `VideoPlayerControls` keeps across frames: the speed it plays at,
//! the skip length, and the app's full-screen hook.

const std = @import("std");
const log = std.log.scoped(.ziggui_video_player_controls_state);
const mod = @import("module.zig");

/// What a `VideoPlayerControls` keeps across frames, owned by the app (like
/// `SplitState`): the buttons' actions are its methods, so their callbacks
/// point at memory that outlives the frame.
pub const VideoPlayerControlsState = struct {
    const Self = @This();

    /// The speeds the speed button steps through.
    pub const rates = [_]f32{ 1, 1.25, 1.5, 2 };

    /// How far the skip buttons move the playhead, in seconds.
    skip_seconds: f64 = 15,

    /// What the full-screen button does (the app shows the player alone, and
    /// may take the window full screen); null leaves the button out.
    on_full_screen: ?mod.Callback = null,

    /// Whether the app shows the player full screen now, for the button's symbol.
    full_screen: bool = false,

    /// The index in `rates` the player plays at.
    rate_index: usize = 0,

    /// The player the controls drive, set as they build.
    player: ?*mod.Player = null,

    /// What the subtitles button does instead of stepping to the next track
    /// (an app that keeps the choice); null steps (`nextSubtitles`).
    on_subtitles: ?mod.Callback = null,

    /// The `FrameClock` time the controls stay up until wherever the pointer
    /// is (`reveal`: a key pressed); 0 for none.
    revealed_until_ms: u64 = 0,

    /// Whether the controls show wherever the pointer is: while the player
    /// is not playing. Playing, they show only while it is over the player.
    ///
    /// - `self`: the state.
    /// - Returns: true while they stay up.
    pub fn pinned(self: *const Self) bool {
        if (self.revealed()) return true;
        const player = self.player orelse return true;
        return player.rate == 0;
    }

    /// Keeps the controls up for `duration_ms` wherever the pointer is, as a
    /// player shows them when a key is pressed.
    ///
    /// - `self`: the state.
    /// - `duration_ms`: how long, in milliseconds.
    pub fn reveal(self: *Self, duration_ms: u64) void {
        self.revealed_until_ms = mod.FrameClock.shared().time() + duration_ms;
    }

    /// Whether a `reveal` holds the controls up now.
    ///
    /// - `self`: the state.
    /// - Returns: true until it ends.
    pub fn revealed(self: *const Self) bool {
        return self.revealed_until_ms > mod.FrameClock.shared().time();
    }

    /// The speed the speed button names and play resumes at.
    ///
    /// - `self`: the state.
    /// - Returns: the rate.
    pub fn rate(self: *const Self) f32 {
        return rates[self.rate_index % rates.len];
    }

    /// The scrubber's position as a binding, 0 at the start to 1 at the end:
    /// while a seek is landing it reads the seek's target, so the knob stays
    /// where it was dropped; setting it seeks.
    ///
    /// - `self`: the state; must outlive the view.
    /// - Returns: the binding.
    pub fn progressBinding(self: *Self) mod.Binding(f32) {
        return .{ .context = self, .get_fn = Self.boundProgress, .set_fn = Self.bindProgress };
    }

    /// Plays at the chosen speed when paused, from the start once the item
    /// has played to its end; pauses when playing.
    ///
    /// - `self`: the state.
    pub fn togglePlay(self: *Self) void {
        const player = self.player orelse return;
        // The sample brings in a pause the player made itself (the item's end).
        const observation = player.observe();
        if (player.rate > 0) return player.pause();
        if (observation.duration_seconds) |duration| {
            if (observation.current_seconds >= duration - mod.Player.seek_landing_seconds) player.seek(0);
        }
        player.setRate(self.rate());
    }

    /// Moves the playhead `skip_seconds` back.
    ///
    /// - `self`: the state.
    pub fn skipBack(self: *Self) void {
        self.skipBy(-self.skip_seconds);
    }

    /// Moves the playhead `skip_seconds` on.
    ///
    /// - `self`: the state.
    pub fn skipForward(self: *Self) void {
        self.skipBy(self.skip_seconds);
    }

    /// Moves the playhead by `seconds` from where it is, never before the
    /// start (the skip buttons, here and in `AudioPlayerControlsState`).
    ///
    /// - `self`: the state.
    /// - `seconds`: how far, back when negative.
    pub fn skipBy(self: *Self, seconds: f64) void {
        const player = self.player orelse return;
        player.seek(@max(0, player.observe().current_seconds + seconds));
    }

    /// Mutes or unmutes.
    ///
    /// - `self`: the state.
    pub fn toggleMute(self: *Self) void {
        const player = self.player orelse return;
        player.setMuted(!player.muted);
    }

    /// Steps to the next speed in `rates`, and back to the first after the
    /// last; a playing player takes it at once.
    ///
    /// - `self`: the state.
    pub fn nextRate(self: *Self) void {
        self.rate_index = (self.rate_index + 1) % rates.len;
        const player = self.player orelse return;
        if (player.rate > 0) player.setRate(self.rate());
    }

    /// Steps the subtitles to the next track, and from the last one to none.
    ///
    /// - `self`: the state.
    pub fn nextSubtitles(self: *Self) void {
        const player = self.player orelse return;
        var arena = std.heap.ArenaAllocator.init(player.allocator);
        defer arena.deinit();
        const tracks = player.tracks(arena.allocator(), .subtitle) catch |err| {
            log.warn("subtitles not listed [{t}]", .{err});
            return;
        };
        if (tracks.len == 0) return;
        var next: ?usize = 0;
        for (tracks, 0..) |track, index| {
            if (track.selected) next = if (index + 1 < tracks.len) index + 1 else null;
        }
        player.selectTrack(.subtitle, next);
    }

    /// Calls the app's full-screen hook.
    ///
    /// - `self`: the state.
    pub fn fullScreen(self: *Self) void {
        if (self.on_full_screen) |callback| callback.call();
    }

    /// `progressBinding`'s reader.
    ///
    /// - `context`: the state.
    /// - Returns: the playhead's share of the item, or 0 with no length.
    fn boundProgress(context: *anyopaque) f32 {
        const self: *Self = @ptrCast(@alignCast(context));
        const player = self.player orelse return 0;
        const observation = player.observe();
        const duration = observation.duration_seconds orelse return 0;
        if (duration <= 0) return 0;
        const at = if (observation.seeking) player.seek_target orelse observation.current_seconds else observation.current_seconds;
        return @floatCast(std.math.clamp(at / duration, 0, 1));
    }

    /// `progressBinding`'s writer: seeks to that share of the item.
    ///
    /// - `context`: the state.
    /// - `progress`: 0 at the start to 1 at the end.
    fn bindProgress(context: *anyopaque, progress: f32) void {
        const self: *Self = @ptrCast(@alignCast(context));
        const player = self.player orelse return;
        const duration = player.observe().duration_seconds orelse return;
        player.seek(@as(f64, std.math.clamp(progress, 0, 1)) * duration);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the controls stay up while paused, and step through the speeds" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: VideoPlayerControlsState = .{ .player = &player };
    try std.testing.expect(state.pinned());
    state.togglePlay();
    try std.testing.expectEqual(@as(f32, 1), player.rate);
    try std.testing.expect(!state.pinned());
    // Playing, a new speed takes at once; past the last it wraps.
    state.nextRate();
    try std.testing.expectEqual(@as(f32, 1.25), player.rate);
    for (0..3) |_| state.nextRate();
    try std.testing.expectEqual(@as(f32, 1), state.rate());
    state.togglePlay();
    try std.testing.expectEqual(@as(f32, 0), player.rate);
    state.toggleMute();
    try std.testing.expect(player.muted);
}
