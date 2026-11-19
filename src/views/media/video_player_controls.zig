//! The standard controls over a `VideoPlayer`, as a platform player draws
//! them: full screen at the top leading corner, the volume at the top
//! trailing one, and the transport along the bottom; with an app's own
//! controls among them (`VideoPlayerControlsWith`), built from
//! `VideoPlayerControlButton` and `VideoPlayerControlMenu`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_video_player_controls);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a control menu's button does: flip whether its menu is shown.
const ControlMenuToggle = struct {
    const Self = @This();

    /// Flips `open`.
    ///
    /// - `open`: whether the menu is shown.
    fn flip(open: *renderer.State(bool)) void {
        open.set(!open.get());
    }
};

/// Builds the controls' parts.
const Controls = struct {
    const Self = @This();

    /// The volume slider's width.
    const volume_width: f32 = 110;

    /// The top row: full screen (when the app offers it) and the app's
    /// leading view, then the app's trailing views and the volume.
    ///
    /// - `state`: the controls' state.
    /// - `player`: the player.
    /// - `accessories`: the app's controls.
    /// - Returns: the row.
    fn top(state: *mod.VideoPlayerControlsState, player: *mod.Player, accessories: mod.VideoPlayerControlsAccessories) mod.View {
        const full_screen = if (state.on_full_screen != null)
            mod.MediaControlStyle.group(mod.MediaControlStyle.symbol(if (state.full_screen) .minimize2 else .maximize2, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.fullScreen)))
        else
            mod.Empty();
        const volume = mod.MediaControlStyle.group(mod.HStack(.{
            mod.Slider(player.volumeBinding(), 0, 1).foreground(mod.MediaControlStyle.ink).frameWidth(volume_width),
            mod.MediaControlStyle.symbol(mod.MediaControlStyle.volumeIcon(player), 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.toggleMute)),
        }).spacing(6));
        // Without accessories the row is the one it always was.
        if (accessories.top_leading == null and accessories.top_trailing.len == 0) return mod.HStack(.{ full_screen, mod.Spacer(), volume });
        const leading = if (accessories.top_leading) |view| mod.MediaControlStyle.group(view) else mod.Empty();
        const trailing = if (accessories.top_trailing.len > 0) mod.MediaControlStyle.group(mod.StackBuilder.fromSlice(.horizontal, 6, .center, accessories.top_trailing)) else mod.Empty();
        return mod.HStack(.{ full_screen, leading, mod.Spacer(), trailing, volume }).spacing(8);
    }

    /// The transport: skip back, play or pause, skip on, the elapsed time,
    /// the scrubber and the length (or "Live" for an item with no end, which
    /// has no skips or speed), the app's transport views, the subtitles and
    /// the speed.
    ///
    /// - `state`: the controls' state.
    /// - `player`: the player.
    /// - `accessories`: the app's controls.
    /// - Returns: the bar.
    fn bottom(state: *mod.VideoPlayerControlsState, player: *mod.Player, accessories: mod.VideoPlayerControlsAccessories) mod.View {
        const observation = player.observe();
        const allocator = mod.BuildScope.shared().allocator();
        const playing = player.rate > 0;
        const elapsed = mod.Text(mod.MediaControlStyle.clock(observation.current_seconds)).font(.footnote).mono().foreground(mod.MediaControlStyle.ink);
        // A live item has no end to scrub to; with no item the scrubber shows, idle.
        const live = observation.isLive();
        const scrubber = if (live) mod.HStack(.{
            mod.Text("Live").font(.footnote).weight(.semibold).foreground(mod.MediaControlStyle.ink),
            mod.Spacer(),
        }).frameMaxWidth() else mod.HStack(.{
            mod.Slider(state.progressBinding(), 0, 1).foreground(mod.MediaControlStyle.ink).disabled(observation.duration_seconds == null).frameMaxWidth(),
            mod.Text(mod.MediaControlStyle.clock(observation.duration_seconds orelse 0)).font(.footnote).mono().foreground(mod.MediaControlStyle.ink),
        }).spacing(12).frameMaxWidth();
        const speed = allocator.print("{d}×", .{state.rate()}) catch @panic("oom");
        const subtitles = state.on_subtitles orelse mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.nextSubtitles);
        var parts: std.ArrayList(mod.View) = .empty;
        if (!live) parts.append(allocator, mod.MediaControlStyle.symbol(.rotateCcw, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.skipBack))) catch @panic("oom");
        parts.append(allocator, mod.MediaControlStyle.symbol(if (playing) .pause else .play, 20, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.togglePlay))) catch @panic("oom");
        if (!live) parts.append(allocator, mod.MediaControlStyle.symbol(.rotateCw, 16, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.skipForward))) catch @panic("oom");
        parts.append(allocator, elapsed.paddingInsets(.{ .leading = 6 })) catch @panic("oom");
        parts.append(allocator, scrubber) catch @panic("oom");
        parts.appendSlice(allocator, accessories.transport) catch @panic("oom");
        parts.append(allocator, mod.MediaControlStyle.symbol(.captions, 16, subtitles)) catch @panic("oom");
        if (!live) parts.append(allocator, mod.MediaControlStyle.label(speed, mod.Callback.init(mod.VideoPlayerControlsState, state, mod.VideoPlayerControlsState.nextRate))) catch @panic("oom");
        return mod.MediaControlStyle.group(mod.StackBuilder.fromSlice(.horizontal, 8, .center, parts.items).frameMaxWidth());
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
    return VideoPlayerControlsWith(player, state, .{});
}

/// The standard controls with the app's own among them: `accessories.top_leading`
/// after the full-screen pill, `top_trailing` before the volume, `transport`
/// in the bar before the subtitles and speed. Otherwise as `VideoPlayerControls`.
///
/// - `player`: the player; it must outlive the frame.
/// - `state`: what the controls keep across frames; app-owned.
/// - `accessories`: the app's controls, built for this frame.
/// - Returns: the controls.
pub fn VideoPlayerControlsWith(player: *mod.Player, state: *mod.VideoPlayerControlsState, accessories: mod.VideoPlayerControlsAccessories) mod.View {
    state.player = player;
    // Sampled first: the sample turns a stop the platform player made itself
    // (the item's end) into the rate `pinned` reads.
    _ = player.observe();
    // A reveal (a key pressed) ends on its own: a frame is asked for then.
    if (state.revealed()) mod.FrameClock.shared().requestFrameAt(state.revealed_until_ms + 1);
    const controls = mod.VStack(.{
        Controls.top(state, player, accessories),
        mod.Spacer(),
        Controls.bottom(state, player, accessories),
    }).padding(12)
        .frameMaxWidth()
        .frameMaxHeight();
    // Playing, they show only while the pointer is over the player, which the
    // painter reads where the pointer is, not as it crosses an edge: a pointer
    // resting on a player that appears or starts playing counts.
    const shown = if (state.pinned()) controls else controls.revealOnHover();
    return mod.StackBuilder.make(.vertical, 0, .center, .{shown}).frameMaxWidth().frameMaxHeight().hoverScope();
}

/// A button among the controls, drawn as theirs: a white symbol, lit under
/// the pointer (for `VideoPlayerControlsAccessories`).
///
/// - `icon`: the symbol.
/// - `action`: what a tap does.
/// - Returns: the button.
pub fn VideoPlayerControlButton(icon: renderer.Icon, action: mod.Callback) mod.View {
    return mod.MediaControlStyle.symbol(icon, 16, action);
}

/// A menu among the controls: a control button whose tap shows `items`
/// (`MenuItem`s) in a popover, as `Menu` does with a plain button.
///
/// - `icon`: the button's symbol.
/// - `open`: whether the menu is shown; app-owned.
/// - `items`: the menu's entries.
/// - Returns: the button.
pub fn VideoPlayerControlMenu(icon: renderer.Icon, open: *renderer.State(bool), items: []const mod.View) mod.View {
    const content = mod.VStack(items).padding(6);
    return mod.MediaControlStyle.symbol(icon, 16, mod.Callback.init(renderer.State(bool), open, ControlMenuToggle.flip)).popover(open.binding(), content);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "playing, the controls show only while the pointer rests on the player" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    player.play();
    var state: mod.VideoPlayerControlsState = .{};
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    for ([_]?renderer.Point{ .{ .x = 240, .y = 135 }, null }) |pointer| {
        window.begin(renderer.MacosTheme.light);
        window.hover_point = pointer;
        const view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
        window.end();
        var frame = try window.render(view, 480, 270);
        defer frame.deinit();
        // Over the player its buttons take taps; away from it there are none.
        try std.testing.expectEqual(pointer != null, window.hits.items.len > 0);
    }
}

test "paused, the controls show and their play button plays" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: mod.VideoPlayerControlsState = .{};
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
    window.end();
    var frame = try window.render(view, 480, 270);
    defer frame.deinit();
    // The bottom bar: 12 in, 6 + 10 into its group, the skip button, 8, then play.
    try std.testing.expect(window.tap(.{ .x = 12 + 10 + 30 + 8 + 15, .y = 270 - 12 - 6 - 15 }));
    try std.testing.expectEqual(@as(f32, 1), player.rate);
}

/// Counts the taps on the tests' accessory buttons.
const AccessoryProbe = struct {
    const Self = @This();

    /// How many taps there were.
    taps: usize = 0,

    /// Counts a tap.
    ///
    /// - `self`: the probe.
    fn tap(self: *Self) void {
        self.taps += 1;
    }
};

test "a live item's controls have no skips or speed, and a reveal keeps them up while it plays" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: mod.VideoPlayerControlsState = .{};
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    // No item: the full controls (full screen off, so mute, skips, play,
    // subtitles, speed and the two sliders).
    window.begin(renderer.MacosTheme.light);
    var view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
    window.end();
    var frame = try window.render(view, 480, 270);
    frame.deinit();
    const full = window.hits.items.len;

    // A live item (headless, it has no length), playing with no pointer:
    // only the reveal shows the controls, without the skips, the speed and
    // the scrubber ("Live" in its place).
    try player.replaceCurrentItem("https://example.com/live.m3u8");
    player.play();
    state.reveal(1000);
    try std.testing.expect(state.revealed());
    window.begin(renderer.MacosTheme.light);
    view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
    window.end();
    frame = try window.render(view, 480, 270);
    frame.deinit();
    try std.testing.expectEqual(full - 4, window.hits.items.len);
}

test "the app's accessories sit among the standard controls and take taps" {
    mod.Player.setBackend(null);
    var player = mod.Player.init(std.testing.allocator);
    defer player.deinit();
    var state: mod.VideoPlayerControlsState = .{};
    var probe: AccessoryProbe = .{};
    var open = renderer.State(bool).init(std.testing.allocator, false);
    defer open.deinit();
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    window.begin(renderer.MacosTheme.light);
    var view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControls(&player, &state) });
    window.end();
    var frame = try window.render(view, 480, 270);
    frame.deinit();
    const standard = window.hits.items.len;

    window.begin(renderer.MacosTheme.light);
    const allocator = mod.BuildScope.shared().allocator();
    const trailing = try allocator.dupe(mod.View, &.{VideoPlayerControlMenu(.speaker, &open, &.{})});
    const transport = try allocator.dupe(mod.View, &.{VideoPlayerControlButton(.circleDot, mod.Callback.init(AccessoryProbe, &probe, AccessoryProbe.tap))});
    view = mod.ZStack(.{ mod.VideoPlayer(&player), VideoPlayerControlsWith(&player, &state, .{
        .top_leading = VideoPlayerControlButton(.chevronLeft, mod.Callback.init(AccessoryProbe, &probe, AccessoryProbe.tap)),
        .top_trailing = trailing,
        .transport = transport,
    }) });
    window.end();
    frame = try window.render(view, 480, 270);
    frame.deinit();
    try std.testing.expectEqual(standard + 3, window.hits.items.len);
    // The back button: 12 in, 10 into its pill, half the 30-point button.
    try std.testing.expect(window.tap(.{ .x = 12 + 10 + 15, .y = 12 + 6 + 15 }));
    try std.testing.expectEqual(@as(usize, 1), probe.taps);
}
