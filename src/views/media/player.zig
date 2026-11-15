//! A media player modeled on AVFoundation's `AVPlayer`: one item at a time,
//! played, paused, sought and sampled, its picture shown by `VideoPlayer`
//! views. The platform player behind it comes from the installed
//! `PlayerBackend`, made on first need, so a player can be set up before the
//! window opens.

const std = @import("std");
const log = std.log.scoped(.ziggui_player);
const mod = @import("module.zig");

/// A media player the app owns, like a `ScrollState`: its address must stay
/// put while views show it. Call it from the UI thread.
pub const Player = struct {
    const Self = @This();

    /// How close the playhead must come to a seek's target for the seek to
    /// count as landed, in seconds (a seek lands on a keyframe near it).
    pub const seek_landing_seconds: f64 = 1;

    /// How long a seek may report `seeking` at most, in milliseconds: one
    /// past a live stream's edge has no end to clamp to, and lands nowhere
    /// `seekLanded` can see.
    pub const seek_timeout_ms: u64 = 10_000;

    /// How often a `VideoPlayer` asks for a frame while its player plays,
    /// waits, seeks or loads its item, so labels drawn from `observe` keep
    /// up, in milliseconds.
    pub const refresh_interval_ms: u64 = 250;

    /// Owns the item's URL.
    allocator: std.mem.Allocator,

    /// The platform player, once made.
    handle: ?*anyopaque = null,

    /// The backend `handle` came from (it frees it, even after the runtime
    /// has gone).
    backend: ?*const mod.PlayerBackend = null,

    /// The current item's URL, or null for none.
    item_url: ?[:0]u8 = null,

    /// The rate: 0 paused, 1 normal speed. What was asked for, until the
    /// platform player pauses itself (the item's end, a failure), which
    /// `observe` takes up.
    rate: f32 = 0,

    /// The volume, 0 silent to 1 full.
    volume: f32 = 1,

    /// The sound is off.
    muted: bool = false,

    /// Where the last seek is headed, until the playhead gets there.
    seek_target: ?f64 = null,

    /// Where the playhead was as the last seek began.
    seek_origin: f64 = 0,

    /// The `FrameClock` time the last seek began at; 0 with no clock.
    seek_started_ms: u64 = 0,

    /// The last sample, reused by every `observe` in the frame it was taken
    /// in; null until one is taken, and after a call that changes what it
    /// would say.
    sample: ?mod.PlayerObservation = null,

    /// The `FrameClock` time `sample` was taken at.
    sample_time_ms: u64 = 0,

    /// The backend new players use, installed by the SDL runtime as its loop
    /// starts; null headless and in tests, unless a test installs one.
    var installed_backend: ?*const mod.PlayerBackend = null;

    /// A player with no item.
    ///
    /// - `allocator`: owns the item's URL.
    /// - Returns: the player.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Stops the player, takes its picture off screen and frees it.
    ///
    /// - `self`: the player.
    pub fn deinit(self: *Self) void {
        if (self.handle) |handle| self.backend.?.destroy(handle);
        if (self.item_url) |url| self.allocator.free(url);
        self.* = .{ .allocator = self.allocator };
    }

    /// Installs the backend players are made with; the SDL runtime calls this
    /// as its loop starts and ends. A player keeps the backend it was made
    /// with.
    ///
    /// - `backend`: the platform player; null for none.
    pub fn setBackend(backend: ?*const mod.PlayerBackend) void {
        installed_backend = backend;
    }

    /// Replaces the current item (`AVPlayer.replaceCurrentItem(with:)`): the
    /// media at `url`, a URL (`https://…/master.m3u8`, `file:///…`) or a local
    /// path, or none when null. A playing player plays the new item.
    ///
    /// - `self`: the player.
    /// - `url`: the media, or null for none.
    /// - Returns: nothing; propagates allocation failure.
    pub fn replaceCurrentItem(self: *Self, url: ?[]const u8) std.mem.Allocator.Error!void {
        const copy: ?[:0]u8 = if (url) |text| try self.allocator.dupeSentinel(u8, text, 0) else null;
        if (self.item_url) |old| self.allocator.free(old);
        self.item_url = copy;
        self.seek_target = null;
        self.sample = null;
        if (self.nativeHandle()) |handle| self.backend.?.load(handle, self.item_url);
    }

    /// The current item's URL.
    ///
    /// - `self`: the player.
    /// - Returns: the URL, or null for none.
    pub fn currentItemUrl(self: *const Self) ?[]const u8 {
        return if (self.item_url) |url| url else null;
    }

    /// Plays at normal speed.
    ///
    /// - `self`: the player.
    pub fn play(self: *Self) void {
        self.setRate(1);
    }

    /// Pauses.
    ///
    /// - `self`: the player.
    pub fn pause(self: *Self) void {
        self.setRate(0);
    }

    /// Plays at `rate` (1 normal speed, 2 double); 0 pauses.
    ///
    /// - `self`: the player.
    /// - `rate`: the rate; a negative or non-finite one pauses.
    pub fn setRate(self: *Self, rate: f32) void {
        self.rate = if (std.math.isFinite(rate) and rate > 0) rate else 0;
        self.sample = null;
        if (self.nativeHandle()) |handle| self.backend.?.set_rate(handle, self.rate);
    }

    /// Moves the playhead to `seconds` from the item's start; `observe`
    /// reports `seeking` until it gets there (see `seekLanded`).
    ///
    /// - `self`: the player.
    /// - `seconds`: where to; clamped at 0, a non-finite value ignored.
    pub fn seek(self: *Self, seconds: f64) void {
        if (!std.math.isFinite(seconds)) return;
        const target = @max(seconds, 0);
        self.seek_origin = self.observe().current_seconds;
        self.seek_started_ms = mod.FrameClock.shared().time();
        self.seek_target = target;
        self.sample = null;
        if (self.nativeHandle()) |handle| self.backend.?.seek(handle, target);
    }

    /// Sets the volume.
    ///
    /// - `self`: the player.
    /// - `volume`: 0 silent to 1 full; clamped, a non-finite value ignored.
    pub fn setVolume(self: *Self, volume: f32) void {
        if (!std.math.isFinite(volume)) return;
        self.volume = std.math.clamp(volume, 0, 1);
        if (self.nativeHandle()) |handle| self.backend.?.set_volume(handle, self.volume);
    }

    /// Mutes or unmutes, keeping the volume.
    ///
    /// - `self`: the player.
    /// - `muted`: true for no sound.
    pub fn setMuted(self: *Self, muted: bool) void {
        self.muted = muted;
        if (self.nativeHandle()) |handle| self.backend.?.set_muted(handle, muted);
    }

    /// Samples the player's state, once a frame: a second call in the frame
    /// (the app's, then its `VideoPlayer`'s) returns the first one's sample,
    /// unless a call between them changed the player. With no backend
    /// (headless) it reports what it was asked for: the item, paused, unknown
    /// status; on a platform with no player yet, `.failed` and why. A rate the
    /// platform player dropped on its own becomes `rate`.
    ///
    /// - `self`: the player.
    /// - Returns: the sample; its `failure` stays valid until the next one.
    pub fn observe(self: *Self) mod.PlayerObservation {
        if (Self.unsupportedReason(self.backend orelse installed_backend)) |reason| {
            return .{ .status = .failed, .has_item = self.item_url != null, .failure = reason };
        }
        const handle = self.nativeHandle() orelse return .{ .has_item = self.item_url != null };
        // Time 0 is no clock (headless, tests): every call samples.
        const now = mod.FrameClock.shared().time();
        if (self.sample) |sample| if (now != 0 and now == self.sample_time_ms) return sample;
        var observation = self.backend.?.observe(handle);
        observation.has_item = self.item_url != null;
        if (observation.status != .unknown) self.rate = observation.rate;
        if (self.seek_target) |target| {
            const timed_out = now != 0 and self.seek_started_ms != 0 and now -| self.seek_started_ms >= seek_timeout_ms;
            if (observation.status == .failed or timed_out or self.seekLanded(target, observation)) self.seek_target = null else observation.seeking = true;
        }
        self.sample = observation;
        self.sample_time_ms = now;
        return observation;
    }

    /// Lists the current item's audio or subtitle tracks, in the order
    /// `selectTrack` indexes them; empty until the item is ready.
    ///
    /// - `self`: the player.
    /// - `allocator`: holds the list and its names and languages.
    /// - `kind`: audio or subtitles.
    /// - Returns: the tracks; propagates allocation failure.
    pub fn tracks(self: *Self, allocator: std.mem.Allocator, kind: mod.PlayerTrackKind) std.mem.Allocator.Error![]mod.PlayerTrack {
        const handle = self.nativeHandle() orelse return &.{};
        return self.backend.?.tracks(handle, allocator, kind);
    }

    /// Selects a track: the audio a player like AVPlayer switches to without
    /// a restart, or the subtitles shown.
    ///
    /// - `self`: the player.
    /// - `kind`: audio or subtitles.
    /// - `index`: an index into `tracks`' list, or null for no subtitles.
    pub fn selectTrack(self: *Self, kind: mod.PlayerTrackKind, index: ?usize) void {
        if (self.nativeHandle()) |handle| self.backend.?.select_track(handle, kind, index);
    }

    /// The platform player, made on first need from the installed backend
    /// and given the item, rate, volume and mute asked for before it existed.
    /// The SDL runtime reads it to put the picture on screen.
    ///
    /// - `self`: the player.
    /// - Returns: the handle, or null with no backend or when it refused.
    pub fn nativeHandle(self: *Self) ?*anyopaque {
        if (self.handle) |handle| return handle;
        const backend = installed_backend orelse return null;
        if (backend.unsupported != null) return null;
        const handle = backend.create() orelse return null;
        self.handle = handle;
        self.backend = backend;
        backend.set_volume(handle, self.volume);
        backend.set_muted(handle, self.muted);
        if (self.item_url != null) backend.load(handle, self.item_url);
        if (self.seek_target) |target| backend.seek(handle, target);
        if (self.rate > 0) backend.set_rate(handle, self.rate);
        return handle;
    }

    /// Whether the seek to `target` has landed: the playhead is within
    /// `seek_landing_seconds` of it (of the item's end, for a target past
    /// it), or past the halfway point from where it began, as when it landed
    /// and then played on, or was sampled late.
    ///
    /// - `self`: the player.
    /// - `target`: where the seek is headed.
    /// - `observation`: the platform player's sample.
    /// - Returns: true once it has landed.
    fn seekLanded(self: *const Self, target: f64, observation: mod.PlayerObservation) bool {
        if (observation.status != .readyToPlay) return false;
        const goal = if (observation.duration_seconds) |duration| @min(target, duration) else target;
        if (@abs(observation.current_seconds - goal) <= seek_landing_seconds) return true;
        const halfway = (self.seek_origin + goal) / 2;
        return (observation.current_seconds - halfway) * (goal - self.seek_origin) > 0;
    }

    /// Why `backend` cannot play video.
    ///
    /// - `backend`: the backend, or null for none.
    /// - Returns: its reason, or null when it can (or there is none).
    fn unsupportedReason(backend: ?*const mod.PlayerBackend) ?[]const u8 {
        const installed = backend orelse return null;
        return installed.unsupported;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// A backend that records what a player asks of it, for the tests.
const FakeBackend = struct {
    const Self = @This();

    /// The handle `create` hands out.
    var handle_storage: u8 = 0;
    /// How many players were made.
    var created: usize = 0;
    /// How many were freed.
    var destroyed: usize = 0;
    /// The last URL loaded, or empty for none.
    var loaded: [128]u8 = undefined;
    /// How many bytes of `loaded` are the URL.
    var loaded_length: usize = 0;
    /// How many loads there were.
    var loads: usize = 0;
    /// The last rate set.
    var rate: f32 = -1;
    /// The last seek.
    var seeked: f64 = -1;
    /// The playhead `observe` reports.
    var playhead: f64 = 0;
    /// The item's length `observe` reports, or null for none known.
    var duration: ?f64 = null;
    /// How many samples were taken.
    var observes: usize = 0;
    /// The last volume set.
    var volume: f32 = -1;
    /// The last mute set.
    var muted: bool = false;
    /// The last track selected, or null for none.
    var selected: ?usize = 99;

    /// The backend over these functions.
    const backend: mod.PlayerBackend = .{
        .create = Self.create,
        .destroy = Self.destroy,
        .load = Self.load,
        .set_rate = Self.setRate,
        .seek = Self.seek,
        .set_volume = Self.setVolume,
        .set_muted = Self.setMuted,
        .observe = Self.observe,
        .tracks = Self.tracks,
        .select_track = Self.selectTrack,
    };

    /// A backend that cannot play.
    const unsupported: mod.PlayerBackend = .{
        .unsupported = "no video here yet",
        .create = Self.create,
        .destroy = Self.destroy,
        .load = Self.load,
        .set_rate = Self.setRate,
        .seek = Self.seek,
        .set_volume = Self.setVolume,
        .set_muted = Self.setMuted,
        .observe = Self.observe,
        .tracks = Self.tracks,
        .select_track = Self.selectTrack,
    };

    /// Clears the record.
    fn reset() void {
        created = 0;
        destroyed = 0;
        loaded_length = 0;
        loads = 0;
        rate = -1;
        seeked = -1;
        playhead = 0;
        duration = null;
        observes = 0;
        volume = -1;
        muted = false;
        selected = 99;
    }

    /// The last URL loaded.
    ///
    /// - Returns: the URL, or empty for none.
    fn lastUrl() []const u8 {
        return loaded[0..loaded_length];
    }

    /// Makes a player.
    ///
    /// - Returns: the one handle.
    fn create() ?*anyopaque {
        created += 1;
        return &handle_storage;
    }

    /// Counts a freed player.
    fn destroy(_: *anyopaque) void {
        destroyed += 1;
    }

    /// Records the item loaded.
    ///
    /// - `url`: the item's URL, or null for none.
    fn load(_: *anyopaque, url: ?[:0]const u8) void {
        loads += 1;
        const text: []const u8 = if (url) |value| value else "";
        @memcpy(loaded[0..text.len], text);
        loaded_length = text.len;
    }

    /// Records the rate.
    ///
    /// - `value`: the rate.
    fn setRate(_: *anyopaque, value: f32) void {
        rate = value;
    }

    /// Records the seek.
    ///
    /// - `seconds`: where to.
    fn seek(_: *anyopaque, seconds: f64) void {
        seeked = seconds;
    }

    /// Records the volume.
    ///
    /// - `value`: the volume.
    fn setVolume(_: *anyopaque, value: f32) void {
        volume = value;
    }

    /// Records the mute.
    ///
    /// - `value`: true for no sound.
    fn setMuted(_: *anyopaque, value: bool) void {
        muted = value;
    }

    /// Samples the fake player: ready, playing at the rate set, at `playhead`.
    ///
    /// - Returns: the sample.
    fn observe(_: *anyopaque) mod.PlayerObservation {
        observes += 1;
        return .{ .status = .readyToPlay, .time_control = if (rate > 0) .playing else .paused, .rate = @max(rate, 0), .current_seconds = playhead, .duration_seconds = duration };
    }

    /// Two tracks of `kind`, English selected, then French.
    ///
    /// - `allocator`: holds the list and its strings.
    /// - `kind`: audio or subtitles.
    /// - Returns: the tracks; propagates allocation failure.
    fn tracks(_: *anyopaque, allocator: std.mem.Allocator, kind: mod.PlayerTrackKind) std.mem.Allocator.Error![]mod.PlayerTrack {
        const list = try allocator.alloc(mod.PlayerTrack, 2);
        const prefix = if (kind == .audio) "Audio" else "Subtitles";
        list[0] = .{ .name = try allocator.dupe(u8, prefix), .language = try allocator.dupe(u8, "en"), .selected = true };
        list[1] = .{ .name = try allocator.dupe(u8, prefix), .language = try allocator.dupe(u8, "fr") };
        return list;
    }

    /// Records the track selected.
    ///
    /// - `index`: the track, or null for none.
    fn selectTrack(_: *anyopaque, _: mod.PlayerTrackKind, index: ?usize) void {
        selected = index;
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "player: without a backend it keeps what it was asked for and reports it" {
    Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("https://example.com/master.m3u8");
    player.play();
    player.setVolume(4);
    try std.testing.expectEqualStrings("https://example.com/master.m3u8", player.currentItemUrl().?);
    try std.testing.expectEqual(@as(f32, 1), player.rate);
    try std.testing.expectEqual(@as(f32, 1), player.volume);
    const observation = player.observe();
    try std.testing.expect(observation.has_item);
    try std.testing.expectEqual(mod.PlayerStatus.unknown, observation.status);
    try std.testing.expect(player.nativeHandle() == null);
}

test "player: the native player is made on first need and given what was asked before" {
    FakeBackend.reset();
    Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    try player.replaceCurrentItem("file:///movie.mp4");
    player.setMuted(true);
    player.play();
    try std.testing.expectEqual(@as(usize, 0), FakeBackend.created);

    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    try std.testing.expect(player.nativeHandle() != null);
    try std.testing.expectEqual(@as(usize, 1), FakeBackend.created);
    try std.testing.expectEqualStrings("file:///movie.mp4", FakeBackend.lastUrl());
    try std.testing.expect(FakeBackend.muted);
    try std.testing.expectEqual(@as(f32, 1), FakeBackend.rate);

    player.pause();
    try std.testing.expectEqual(@as(f32, 0), FakeBackend.rate);
    try player.replaceCurrentItem(null);
    try std.testing.expectEqualStrings("", FakeBackend.lastUrl());
    player.deinit();
    try std.testing.expectEqual(@as(usize, 1), FakeBackend.destroyed);
    try std.testing.expectEqual(@as(usize, 1), FakeBackend.created);
}

test "player: a seek reports seeking until the playhead lands near its target" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");
    player.seek(-5);
    try std.testing.expectEqual(@as(f64, 0), FakeBackend.seeked);
    player.seek(120);
    try std.testing.expectEqual(@as(f64, 120), FakeBackend.seeked);
    FakeBackend.playhead = 3;
    try std.testing.expect(player.observe().seeking);
    FakeBackend.playhead = 119.6;
    try std.testing.expect(!player.observe().seeking);
    try std.testing.expect(player.seek_target == null);
}

test "player: a seek sampled late, past its end or played on after landing still lands" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");

    // Forward, first sampled seconds after it landed and played on.
    FakeBackend.playhead = 10;
    player.seek(120);
    FakeBackend.playhead = 10.4;
    try std.testing.expect(player.observe().seeking);
    FakeBackend.playhead = 126;
    try std.testing.expect(!player.observe().seeking);

    // Backward, played on past the target before the sample.
    player.seek(30);
    FakeBackend.playhead = 126.3;
    try std.testing.expect(player.observe().seeking);
    FakeBackend.playhead = 38;
    try std.testing.expect(!player.observe().seeking);

    // Past the end: the platform player stops at the end.
    FakeBackend.duration = 600;
    player.seek(10_000);
    FakeBackend.playhead = 600;
    try std.testing.expect(!player.observe().seeking);
}

test "player: a seek that lands nowhere it can see stops reporting seeking after its timeout" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    const clock = mod.FrameClock.shared();
    const saved = clock.time();
    defer clock.setTime(saved);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("https://example.com/live.m3u8");

    // Live, at its edge: a seek ahead is held at the edge, with no end known.
    FakeBackend.playhead = 100;
    clock.setTime(1000);
    player.seek(200);
    clock.setTime(1000 + Player.seek_timeout_ms - 1);
    try std.testing.expect(player.observe().seeking);
    clock.setTime(1000 + Player.seek_timeout_ms);
    try std.testing.expect(!player.observe().seeking);
}

test "player: a seek asked before the native player exists reaches it" {
    FakeBackend.reset();
    Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");
    player.seek(42);
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    try std.testing.expect(player.nativeHandle() != null);
    try std.testing.expectEqual(@as(f64, 42), FakeBackend.seeked);
}

test "player: a pause the platform player makes itself becomes its rate" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");
    player.play();
    _ = player.observe();
    try std.testing.expectEqual(@as(f32, 1), player.rate);
    // The item ends: the platform player pauses.
    FakeBackend.rate = 0;
    try std.testing.expectEqual(mod.PlayerTimeControl.paused, player.observe().time_control);
    try std.testing.expectEqual(@as(f32, 0), player.rate);
}

test "player: one sample a frame, retaken after a call that changes the player" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    const clock = mod.FrameClock.shared();
    const saved = clock.time();
    defer clock.setTime(saved);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");

    clock.setTime(1000);
    _ = player.observe();
    _ = player.observe();
    try std.testing.expectEqual(@as(usize, 1), FakeBackend.observes);
    player.play();
    try std.testing.expectEqual(mod.PlayerTimeControl.playing, player.observe().time_control);
    try std.testing.expectEqual(@as(usize, 2), FakeBackend.observes);
    clock.setTime(1250);
    _ = player.observe();
    try std.testing.expectEqual(@as(usize, 3), FakeBackend.observes);
}

test "player: tracks and selections pass through to the backend" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.backend);
    defer Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const subtitles = try player.tracks(arena.allocator(), .subtitle);
    try std.testing.expectEqual(@as(usize, 2), subtitles.len);
    try std.testing.expectEqualStrings("fr", subtitles[1].language);
    player.selectTrack(.subtitle, null);
    try std.testing.expect(FakeBackend.selected == null);
    player.selectTrack(.audio, 1);
    try std.testing.expectEqual(@as(?usize, 1), FakeBackend.selected);
}

test "player: a platform with no player yet reports failed and why, and makes none" {
    FakeBackend.reset();
    Player.setBackend(&FakeBackend.unsupported);
    defer Player.setBackend(null);
    var player = Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("file:///movie.mp4");
    player.play();
    const observation = player.observe();
    try std.testing.expectEqual(mod.PlayerStatus.failed, observation.status);
    try std.testing.expectEqualStrings("no video here yet", observation.failure);
    try std.testing.expectEqual(@as(usize, 0), FakeBackend.created);
}
