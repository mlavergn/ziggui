const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_media);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The sample the Video panel plays: Apple's public HLS example (10 minutes,
/// fMP4, an English audio rendition and two subtitle ones). Fetched only when
/// "Load sample stream" is pressed.
const sample_url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8";

/// How far the skip buttons move the playhead, in seconds.
const skip_seconds: f64 = 10;

/// The Video panel: a `VideoPlayer` with controls drawn over the picture, the
/// buttons that load and clear its item, and what the player reports.
pub const Media = struct {
    const Self = @This();

    /// Owns the player and the subtitle lists a tap reads.
    allocator: std.mem.Allocator,

    /// The panel's player.
    player: ziggui.Player,

    /// Constructs the panel's player, with no item.
    ///
    /// - `allocator`: allocator for the player; must outlive the panel.
    /// - Returns: the panel.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator, .player = ziggui.Player.init(allocator) };
        return self;
    }

    /// Stops and frees the player.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.player.deinit();
    }

    /// The Video panel: the picture with a control bar over it, the item's
    /// buttons, and the player's state.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn videoPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const observation = self.player.observe();
        const picture = ziggui.ZStack(.{
            ziggui.VideoPlayer(&self.player).cornerRadius(8),
            ziggui.VStack(.{ ziggui.Spacer(), self.controlBar(observation) }).padding(10),
        }).frameHeight(270);
        return ziggui.VStack(.{
            Self.card(theme, "VideoPlayer: the platform player draws the picture, ziggui the controls over it", picture),
            ziggui.HStack(.{
                ziggui.Button("Load sample stream", ziggui.Callback.init(Self, self, Self.loadSample)),
                ziggui.Button("Clear", ziggui.Callback.init(Self, self, Self.clear)),
                ziggui.Spacer(),
            }).spacing(8).frameMaxWidth(),
            Self.leading(ziggui.Text(Self.describe(observation)).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated()),
        }).spacing(16);
    }

    /// The bar over the picture: play or pause, skip back, mute, the time,
    /// and the subtitles switch.
    ///
    /// - `self`: the panel.
    /// - `observation`: the player's state this frame.
    /// - Returns: the bar.
    fn controlBar(self: *Self, observation: ziggui.PlayerObservation) ziggui.View {
        const playing = self.player.rate > 0;
        return ziggui.HStack(.{
            ziggui.IconButton(if (playing) .pause else .play, 14, ziggui.Callback.init(Self, self, Self.togglePlay)),
            ziggui.IconButton(.rotateCcw, 14, ziggui.Callback.init(Self, self, Self.skipBack)),
            ziggui.IconButton(if (self.player.muted) .volumeX else .volume2, 14, ziggui.Callback.init(Self, self, Self.toggleMute)),
            ziggui.Text(Self.clock(observation)).foreground(ziggui.Color.white).font(.footnote).mono(),
            ziggui.Spacer(),
            ziggui.IconButton(.captions, 14, ziggui.Callback.init(Self, self, Self.nextSubtitles)),
        }).spacing(6).padding(6).background(ziggui.Color.black.withAlpha(0.55)).cornerRadius(8).frameMaxWidth();
    }

    /// Plays the sample stream from its start.
    ///
    /// - `self`: the panel.
    fn loadSample(self: *Self) void {
        self.player.replaceCurrentItem(sample_url) catch |err| log.warn("sample not loaded [{t}]", .{err});
        self.player.play();
    }

    /// Stops and removes the item.
    ///
    /// - `self`: the panel.
    fn clear(self: *Self) void {
        self.player.pause();
        self.player.replaceCurrentItem(null) catch |err| log.warn("item not cleared [{t}]", .{err});
    }

    /// Plays when paused, from the start once the item has played to its
    /// end; pauses when playing.
    ///
    /// - `self`: the panel.
    fn togglePlay(self: *Self) void {
        // The sample brings in a pause the player made itself (the item's end).
        const observation = self.player.observe();
        if (self.player.rate > 0) return self.player.pause();
        if (observation.duration_seconds) |duration| {
            if (observation.current_seconds >= duration - ziggui.Player.seek_landing_seconds) self.player.seek(0);
        }
        self.player.play();
    }

    /// Moves the playhead `skip_seconds` back.
    ///
    /// - `self`: the panel.
    fn skipBack(self: *Self) void {
        self.player.seek(self.player.observe().current_seconds - skip_seconds);
    }

    /// Mutes or unmutes.
    ///
    /// - `self`: the panel.
    fn toggleMute(self: *Self) void {
        self.player.setMuted(!self.player.muted);
    }

    /// Steps the subtitles to the next track, and from the last one to none.
    ///
    /// - `self`: the panel.
    fn nextSubtitles(self: *Self) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const tracks = self.player.tracks(arena.allocator(), .subtitle) catch |err| {
            log.warn("subtitles not listed [{t}]", .{err});
            return;
        };
        if (tracks.len == 0) return;
        var next: ?usize = 0;
        for (tracks, 0..) |track, index| {
            if (track.selected) next = if (index + 1 < tracks.len) index + 1 else null;
        }
        self.player.selectTrack(.subtitle, next);
    }

    /// The time label: where the playhead is, of how long, or "Live" for a
    /// ready item with no end; just the playhead until the item is ready.
    ///
    /// - `observation`: the player's state.
    /// - Returns: the label, in the build arena.
    fn clock(observation: ziggui.PlayerObservation) []const u8 {
        const allocator = ziggui.BuildScope.shared().allocator();
        const current: u64 = @intFromFloat(@max(observation.current_seconds, 0));
        const live = observation.status == .readyToPlay;
        const duration = observation.duration_seconds orelse
            return allocator.print("{d}:{d:0>2}{s}", .{ current / 60, current % 60, if (live) " Live" else "" }) catch @panic("oom");
        const total: u64 = @intFromFloat(@max(duration, 0));
        return allocator.print("{d}:{d:0>2} / {d}:{d:0>2}", .{ current / 60, current % 60, total / 60, total % 60 }) catch @panic("oom");
    }

    /// What the player reports, in a line.
    ///
    /// - `observation`: the player's state.
    /// - Returns: the line, in the build arena.
    fn describe(observation: ziggui.PlayerObservation) []const u8 {
        if (observation.status == .failed) {
            return ziggui.BuildScope.shared().allocator().print("Failed: {s}", .{observation.failure}) catch @panic("oom");
        }
        if (!observation.has_item) return "No item. Load sample stream plays Apple's HLS example (over the network).";
        return ziggui.BuildScope.shared().allocator().print("{t}, {t}{s}, {d:.1} s buffered, {d}x{d}", .{
            observation.status,
            observation.time_control,
            if (observation.seeking) " (seeking)" else "",
            observation.buffered_seconds,
            observation.presentation_width,
            observation.presentation_height,
        }) catch @panic("oom");
    }

    /// A titled group on the secondary background, as the other panels draw.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the group's heading.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(theme: ziggui.Theme, title: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            ziggui.StackBuilder.make(.vertical, 0, .leading, .{content})
                .frameMaxWidth()
                .padding(14)
                .background(theme.colors.secondary_background)
                .cornerRadius(theme.metrics.corner_radius)
                .frameMaxWidth(),
        }).spacing(8).frameMaxWidth();
    }

    /// Pins `view` to the leading edge of a full-width row.
    ///
    /// - `view`: the view.
    /// - Returns: the row.
    fn leading(view: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ view, ziggui.Spacer() }).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}

test "media: the time label reads the playhead and length, or live" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();
    try std.testing.expectEqualStrings("1:05 / 10:00", Media.clock(.{ .current_seconds = 65.4, .duration_seconds = 600 }));
    try std.testing.expectEqualStrings("0:07 Live", Media.clock(.{ .status = .readyToPlay, .current_seconds = 7 }));
    try std.testing.expectEqualStrings("0:00", Media.clock(.{}));
    try std.testing.expectEqualStrings("Failed: gone", Media.describe(.{ .status = .failed, .failure = "gone" }));
}
