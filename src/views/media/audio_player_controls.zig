//! An audio player's controls, as a podcast player draws them: one bar of the
//! speed, skip back 15, play or pause, skip on 30, the elapsed time over a
//! scrubber with the title and the time left, and the volume, on the media
//! controls' translucent pill. It drives a `Player` with no picture.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_player_controls);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds the bar's parts.
const AudioControls = struct {
    const Self = @This();

    /// The volume slider's width in its popover.
    const volume_width: f32 = 140;

    /// A skip button: the circular arrow with its seconds inside, white,
    /// lit under the pointer.
    ///
    /// - `icon`: the arrow (`rotateCcw` back, `rotateCw` on).
    /// - `seconds`: the skip's length, drawn inside.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    fn skip(icon: renderer.Icon, seconds: f64, action: mod.Callback) mod.View {
        const allocator = mod.BuildScope.shared().allocator();
        // Clamped, and 0 for a non-finite length, which would trap the cast.
        const whole: u32 = if (std.math.isFinite(seconds)) @intFromFloat(std.math.clamp(seconds, 0, 999)) else 0;
        const number = allocator.print("{d}", .{whole}) catch @panic("oom");
        return mod.MediaControlStyle.button(mod.ZStack(.{
            mod.Icon(icon, 24, mod.MediaControlStyle.ink),
            mod.Text(number).size(8).weight(.bold).foreground(mod.MediaControlStyle.ink),
        }), action);
    }

    /// The middle: the elapsed time, the title and the time left (or "Live"),
    /// over the scrubber (none for a live item).
    ///
    /// - `state`: the controls' state.
    /// - `observation`: the player's state.
    /// - `title`: what plays, or empty.
    /// - Returns: the column.
    fn timeline(state: *mod.AudioPlayerControlsState, observation: mod.PlayerObservation, title: []const u8) mod.View {
        const allocator = mod.BuildScope.shared().allocator();
        const live = observation.isLive();
        const trailing = if (live)
            "Live"
        else if (observation.duration_seconds) |duration|
            allocator.print("−{s}", .{mod.MediaControlStyle.clock(@max(0, duration - observation.current_seconds))}) catch @panic("oom")
        else
            mod.MediaControlStyle.clock(0);
        const times = mod.HStack(.{
            mod.Text(mod.MediaControlStyle.clock(observation.current_seconds)).font(.footnote).mono().foreground(mod.MediaControlStyle.ink),
            mod.Spacer(),
            mod.Text(mod.DisplayText.clean(allocator, title)).font(.footnote).foreground(mod.MediaControlStyle.ink.withAlpha(0.7)).truncated(),
            mod.Spacer(),
            mod.Text(trailing).font(.footnote).mono().foreground(mod.MediaControlStyle.ink),
        }).spacing(12).frameMaxWidth();
        if (live) return times;
        return mod.VStack(.{
            times,
            mod.Slider(state.transport.progressBinding(), 0, 1).foreground(mod.MediaControlStyle.ink).disabled(observation.duration_seconds == null).frameMaxWidth(),
        }).spacing(2).frameMaxWidth();
    }

    /// The volume button, its popover holding the mute button and the slider.
    ///
    /// - `state`: the controls' state.
    /// - `player`: the player.
    /// - Returns: the button.
    fn volume(state: *mod.AudioPlayerControlsState, player: *mod.Player) mod.View {
        const icon = mod.MediaControlStyle.volumeIcon(player);
        const panel = mod.HStack(.{
            mod.MediaControlStyle.symbol(icon, 16, mod.Callback.init(mod.VideoPlayerControlsState, &state.transport, mod.VideoPlayerControlsState.toggleMute)),
            mod.Slider(player.volumeBinding(), 0, 1).frameWidth(volume_width),
        }).spacing(6).padding(8);
        return mod.MediaControlStyle.symbol(icon, 18, mod.Callback.init(mod.AudioPlayerControlsState, state, mod.AudioPlayerControlsState.toggleVolume))
            .popover(state.volumeShownBinding(), panel);
    }
};

/// An audio player's controls in one bar, for a `Player` with no picture:
/// the speed (each tap the next of `VideoPlayerControlsState.rates`), skip
/// back (`skip_back_seconds`, 15) and on (`skip_forward_seconds`, 30), play
/// or pause, the elapsed time over a scrubber that seeks, with `title`
/// between it and the time left, and the volume (a popover of mute and a
/// slider). A live item (no end) has no speed, skips or scrubber, and says
/// "Live". Fills the width it is offered.
///
/// - `player`: the player; it must outlive the frame.
/// - `state`: what the controls keep across frames; app-owned.
/// - `title`: what plays (an episode, a station), or empty.
/// - Returns: the bar.
pub fn AudioPlayerControls(player: *mod.Player, state: *mod.AudioPlayerControlsState, title: []const u8) mod.View {
    const allocator = mod.BuildScope.shared().allocator();
    state.transport.player = player;
    const observation = player.observe();
    const live = observation.isLive();
    const playing = player.rate > 0;
    var parts: std.ArrayList(mod.View) = .empty;
    if (!live) {
        const speed = allocator.print("{d}×", .{state.transport.rate()}) catch @panic("oom");
        parts.append(allocator, mod.MediaControlStyle.label(speed, mod.Callback.init(mod.VideoPlayerControlsState, &state.transport, mod.VideoPlayerControlsState.nextRate))) catch @panic("oom");
        parts.append(allocator, AudioControls.skip(.rotateCcw, state.skip_back_seconds, mod.Callback.init(mod.AudioPlayerControlsState, state, mod.AudioPlayerControlsState.skipBack))) catch @panic("oom");
    }
    parts.append(allocator, mod.MediaControlStyle.symbol(if (playing) .pause else .play, 24, mod.Callback.init(mod.VideoPlayerControlsState, &state.transport, mod.VideoPlayerControlsState.togglePlay))) catch @panic("oom");
    if (!live) parts.append(allocator, AudioControls.skip(.rotateCw, state.skip_forward_seconds, mod.Callback.init(mod.AudioPlayerControlsState, state, mod.AudioPlayerControlsState.skipForward))) catch @panic("oom");
    parts.append(allocator, AudioControls.timeline(state, observation, title).paddingInsets(.{ .leading = 8, .trailing = 8 })) catch @panic("oom");
    parts.append(allocator, AudioControls.volume(state, player)) catch @panic("oom");
    // While it plays or loads, a frame now and then keeps the times moving.
    if (observation.has_item and (playing or observation.status == .unknown)) mod.FrameClock.shared().requestFrameAt(mod.FrameClock.shared().time() + mod.Player.refresh_interval_ms);
    return mod.MediaControlStyle.group(mod.StackBuilder.fromSlice(.horizontal, 8, .center, parts.items).frameMaxWidth()).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the audio controls play, and a live item has no speed, skips or scrubber" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: mod.AudioPlayerControlsState = .{};
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    window.begin(renderer.MacosTheme.light);
    var view = AudioPlayerControls(&player, &state, "An Episode");
    window.end();
    var frame = try window.render(view, 640, 80);
    frame.deinit();
    // Speed, both skips, play, the scrubber and the volume.
    const full = window.hits.items.len;
    try std.testing.expectEqual(@as(usize, 6), full);
    // Play: 10 into the pill, then the speed label, 8, a skip, 8, play.
    const play_x: f32 = 10 + window.hits.items[0].rect.width + 8 + 30 + 8 + 15;
    try std.testing.expect(window.tap(.{ .x = play_x, .y = 40 }));
    try std.testing.expectEqual(@as(f32, 1), player.rate);

    try player.replaceCurrentItem("https://example.com/radio.m3u8");
    window.begin(renderer.MacosTheme.light);
    view = AudioPlayerControls(&player, &state, "A Station");
    window.end();
    frame = try window.render(view, 640, 80);
    frame.deinit();
    // Play and the volume only.
    try std.testing.expectEqual(@as(usize, 2), window.hits.items.len);
}
