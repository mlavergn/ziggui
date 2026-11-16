//! The standard controls over a `VideoPlayer`, as a platform player draws
//! them: full screen at the top leading corner, the volume at the top
//! trailing one, and the transport along the bottom.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_video_player_controls);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds the controls' parts.
const Controls = struct {
    const Self = @This();

    /// The ground of each group of controls: a translucent gray, lighter than
    /// a black picture and darker than a pale one, so white symbols read on
    /// any (a blur cannot see the picture, which the platform draws).
    const pill = renderer.Color.fromRgb8(72, 72, 72).withAlpha(0.75);

    /// The symbols' and labels' color.
    const ink = renderer.Color.white;

    /// The controls' height inside a group.
    const height: f32 = 30;

    /// The volume slider's width.
    const volume_width: f32 = 110;

    /// A tappable symbol: white, lit under the pointer.
    ///
    /// - `icon`: the symbol.
    /// - `size`: its size.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    fn symbol(icon: renderer.Icon, size: f32, action: mod.Callback) mod.View {
        return mod.HStack(.{mod.Icon(icon, size, ink)})
            .frame(height, height)
            .hoverFill(ink.withAlpha(0.15))
            .cornerRadius(height / 2)
            .onTap(action);
    }

    /// A tappable label (the speed), white, lit under the pointer.
    ///
    /// - `text`: the label.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    fn label(text: []const u8, action: mod.Callback) mod.View {
        return mod.Text(text).font(.footnote).weight(.semibold).foreground(ink)
            .paddingInsets(.{ .leading = 8, .trailing = 8 })
            .frameHeight(height)
            .hoverFill(ink.withAlpha(0.15))
            .cornerRadius(height / 2)
            .onTap(action);
    }

    /// A group of controls on its rounded ground.
    ///
    /// - `content`: the controls.
    /// - Returns: the group.
    fn group(content: mod.View) mod.View {
        return mod.StackBuilder.make(.horizontal, 0, .center, .{content})
            .paddingInsets(.{ .top = 6, .leading = 10, .bottom = 6, .trailing = 10 })
            .background(pill)
            .cornerRadius((height + 12) / 2);
    }

    /// The top row: full screen (when the app offers it) and the volume.
    ///
    /// - `state`: the controls' state.
    /// - `player`: the player.
    /// - Returns: the row.
    fn top(state: *mod.VideoPlayerControlsState, player: *mod.Player) mod.View {
        const full_screen = if (state.on_full_screen != null)
            Self.group(Self.symbol(if (state.full_screen) .minimize2 else .maximize2, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.fullScreen)))
        else
            mod.Empty();
        const volume = Self.group(mod.HStack(.{
            mod.Slider(player.volumeBinding(), 0, 1).foreground(ink).frameWidth(volume_width),
            Self.symbol(Self.volumeIcon(player), 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.toggleMute)),
        }).spacing(6));
        return mod.HStack(.{ full_screen, mod.Spacer(), volume });
    }

    /// The transport: skip back, play or pause, skip on, the elapsed time,
    /// the scrubber and the length (or "Live" for an item with no end), the
    /// subtitles and the speed.
    ///
    /// - `state`: the controls' state.
    /// - `player`: the player.
    /// - Returns: the bar.
    fn bottom(state: *mod.VideoPlayerControlsState, player: *mod.Player) mod.View {
        const observation = player.observe();
        const allocator = mod.BuildScope.shared().allocator();
        const playing = player.rate > 0;
        const elapsed = mod.Text(Self.clock(observation.current_seconds)).font(.footnote).mono().foreground(ink);
        // A live item has no end to scrub to; with no item the scrubber shows, idle.
        const live = observation.has_item and observation.duration_seconds == null;
        const scrubber = if (live) mod.HStack(.{
            mod.Text("Live").font(.footnote).weight(.semibold).foreground(ink),
            mod.Spacer(),
        }).frameMaxWidth() else mod.HStack(.{
            mod.Slider(state.progressBinding(), 0, 1).foreground(ink).disabled(observation.duration_seconds == null).frameMaxWidth(),
            mod.Text(Self.clock(observation.duration_seconds orelse 0)).font(.footnote).mono().foreground(ink),
        }).spacing(12).frameMaxWidth();
        const speed = allocator.print("{d}×", .{state.rate()}) catch @panic("oom");
        return Self.group(mod.HStack(.{
            Self.symbol(.rotateCcw, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.skipBack)),
            Self.symbol(if (playing) .pause else .play, 20, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.togglePlay)),
            Self.symbol(.rotateCw, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.skipForward)),
            elapsed.paddingInsets(.{ .leading = 6 }),
            scrubber,
            Self.symbol(.captions, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.nextSubtitles)),
            Self.label(speed, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.nextRate)),
        }).spacing(8).frameMaxWidth());
    }

    /// The mute button's symbol: crossed out while muted or silent, one wave
    /// up to half volume, two above it.
    ///
    /// - `player`: the player.
    /// - Returns: the symbol.
    fn volumeIcon(player: *const mod.Player) renderer.Icon {
        if (player.muted or player.volume == 0) return .volumeX;
        return if (player.volume <= 0.5) .volume1 else .volume2;
    }

    /// A time as the controls show it: `m:ss`, or `h:mm:ss` from an hour.
    ///
    /// - `seconds`: the time.
    /// - Returns: the label, in the build arena.
    fn clock(seconds: f64) []const u8 {
        const allocator = mod.BuildScope.shared().allocator();
        // Clamped: a backend reporting an absurd time must not trap the cast.
        const longest: f64 = std.math.maxInt(u32);
        const whole: u64 = if (std.math.isFinite(seconds)) @intFromFloat(std.math.clamp(seconds, 0, longest)) else 0;
        if (whole >= 3600) return allocator.print("{d}:{d:0>2}:{d:0>2}", .{ whole / 3600, whole / 60 % 60, whole % 60 }) catch @panic("oom");
        return allocator.print("{d}:{d:0>2}", .{ whole / 60, whole % 60 }) catch @panic("oom");
    }
};

/// The standard controls over a `VideoPlayer`, for a `ZStack` over it:
/// full screen at the top leading corner (when `state.on_full_screen` is
/// set), the volume and mute at the top trailing one, and along the bottom
/// skip back and on (`state.skip_seconds`), play or pause, the elapsed time,
/// a scrubber that seeks and the length ("Live" for an item with no end),
/// the subtitles (each tap the next track, then none) and the speed (each
/// tap the next of `VideoPlayerControlsState.rates`). They show while the
/// pointer is over the player or it is not playing, and hide as the pointer
/// leaves while it plays. Fills the frame it is offered.
///
/// - `player`: the player; it must outlive the frame.
/// - `state`: what the controls keep across frames; app-owned.
/// - Returns: the controls.
pub fn VideoPlayerControls(player: *mod.Player, state: *mod.VideoPlayerControlsState) mod.View {
    state.player = player;
    // Sampled first: the sample turns a stop the platform player made itself
    // (the item's end) into the rate `pinned` reads.
    _ = player.observe();
    const controls = mod.VStack(.{
        Controls.top(state, player),
        mod.Spacer(),
        Controls.bottom(state, player),
    }).padding(12)
        .frameMaxWidth()
        .frameMaxHeight();
    // Playing, they show only while the pointer is over the player, which the
    // painter reads where the pointer is, not as it crosses an edge: a pointer
    // resting on a player that appears or starts playing counts.
    const shown = if (state.pinned()) controls else controls.revealOnHover();
    return mod.StackBuilder.make(.vertical, 0, .center, .{shown}).frameMaxWidth().frameMaxHeight().hoverScope();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the controls' clock reads minutes, and hours from an hour" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    defer canvas.end();
    try std.testing.expectEqualStrings("0:04", Controls.clock(4.9));
    try std.testing.expectEqualStrings("9:59", Controls.clock(599));
    try std.testing.expectEqualStrings("1:02:03", Controls.clock(3723));
    try std.testing.expectEqualStrings("0:00", Controls.clock(std.math.nan(f64)));
    try std.testing.expectEqualStrings("1193046:28:15", Controls.clock(1e30));
}

test "playing, the controls show only while the pointer rests on the player" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    player.play();
    var state: mod.VideoPlayerControlsState = .{};
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    for ([_]?renderer.Point{ .{ .x = 240, .y = 135 }, null }) |pointer| {
        canvas.begin(renderer.MacosTheme.light);
        canvas.hover_point = pointer;
        const view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
        canvas.end();
        var frame = try canvas.render(view, 480, 270);
        defer frame.deinit();
        // Over the player its buttons take taps; away from it there are none.
        try std.testing.expectEqual(pointer != null, canvas.hits.items.len > 0);
    }
}

test "paused, the controls show and their play button plays" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: mod.VideoPlayerControlsState = .{};
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
    canvas.end();
    var frame = try canvas.render(view, 480, 270);
    defer frame.deinit();
    // The bottom bar: 12 in, 6 + 10 into its group, the skip button, 8, then play.
    try std.testing.expect(canvas.tap(.{ .x = 12 + 10 + 30 + 8 + 15, .y = 270 - 12 - 6 - 15 }));
    try std.testing.expectEqual(@as(f32, 1), player.rate);
}
