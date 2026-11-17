//! The macOS `PlayerBackend`: an `AVPlayer` per `Player`, its picture in an
//! `AVPlayerLayer` hosted by a view placed *behind* SDL's Metal view in the
//! window's content view. A `VideoPlayer` erases its frame in the window's
//! surface (made non-opaque here), so the picture shows through the hole and
//! everything ziggui draws after it (controls, a buffering card, sheets)
//! composites over the video. macOS only; nothing here is analyzed on other
//! targets, as `VideoBackend` reaches it only behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_av_foundation_player);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// `AVPlayerItemStatus`.
const item_status_ready: i64 = 1;
/// `AVPlayerItemStatusFailed` (and `AVPlayerStatusFailed`).
const item_status_failed: i64 = 2;
/// `AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate`.
const time_control_waiting: i64 = 1;
/// `AVPlayerTimeControlStatusPlaying`.
const time_control_playing: i64 = 2;
/// `NSWindowBelow`, for `addSubview:positioned:relativeTo:`.
const window_below: i64 = -1;
/// The timescale seeks are made in (a multiple of common frame rates).
const seek_timescale: i32 = 600;
/// How far AVFoundation may put a seek from its target, each way, in
/// seconds: loose enough to stay fast, and inside the window
/// (`Player.seek_landing_seconds`) in which `Player.observe` sees it land.
const seek_precision_seconds: f64 = 0.25;

comptime {
    std.debug.assert(seek_precision_seconds < views.Player.seek_landing_seconds);
}

/// One `Player`'s AVFoundation objects (each owned, +1) and where its
/// picture was last put; a node of the list of live players.
const NativePlayer = struct {
    const Self = @This();

    /// The `AVPlayer`.
    player: mod.Id,
    /// The `AVPlayerLayer` showing it.
    player_layer: mod.Id,
    /// The `CALayer` the view hosts: top-down, clipping the picture to what
    /// shows on screen.
    host_layer: mod.Id,
    /// The layer-hosting `NSView`, in the window's content view below SDL's.
    container: mod.Id,
    /// The corner radius last set.
    corner_radius: f64 = 0,
    /// The container is hidden.
    hidden: bool = true,
    /// The frame (`AvFoundationPlayer.frame_number`) it was last shown in.
    shown_in_frame: u64 = 0,
    /// Why the last load failed before AVFoundation saw it (a malformed URL).
    load_failure: []const u8 = "",
    /// The failure text `observe` hands out, copied out of AVFoundation.
    failure: [512]u8 = undefined,
    /// The next live player.
    next: ?*Self = null,
    /// The previous live player.
    previous: ?*Self = null,

    /// The player's current item, when it is ready to play (its media
    /// selection is loaded only then).
    ///
    /// - `self`: the player.
    /// - Returns: the item, or null.
    fn readyItem(self: *const Self) mod.Id {
        const item = mod.ObjectiveC.send(mod.Id, self.player, "currentItem", .{});
        if (item == null or mod.ObjectiveC.send(i64, item, "status", .{}) != item_status_ready) return null;
        return item;
    }

    /// Copies an `NSError`'s description into the player, where it stays
    /// until the next sample.
    ///
    /// - `self`: the player.
    /// - `error_object`: the error, or nil.
    /// - Returns: the copy (truncated to the buffer), or a generic reason.
    fn copyFailure(self: *Self, error_object: mod.Id) []const u8 {
        const description = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, error_object, "localizedDescription", .{}));
        if (description.len == 0) return "The media could not be played.";
        const length = @min(description.len, self.failure.len);
        @memcpy(self.failure[0..length], description[0..length]);
        return self.failure[0..length];
    }

    /// Hides the player's picture.
    ///
    /// - `self`: the player.
    fn hide(self: *Self) void {
        if (self.hidden) return;
        mod.ObjectiveC.send(void, self.container, "setHidden:", .{@as(u8, 1)});
        self.hidden = true;
    }
};

/// The AVFoundation player behind every `Player` on macOS, and the placement
/// of their pictures in the main window.
pub const AvFoundationPlayer = struct {
    const Self = @This();

    /// The backend `Player`s are made with.
    pub const backend: views.PlayerBackend = .{
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

    /// It shows pictures behind the window's surface.
    pub const presents = true;

    // Inside the struct, as Cocoa's are, so a file-level `refAllDecls` on
    // another OS never asks the linker for them.
    extern fn CMTimeMakeWithSeconds(seconds: f64, preferred_timescale: i32) mod.CMTime;
    extern fn CMTimeGetSeconds(time: mod.CMTime) f64;
    extern fn CGColorCreateSRGB(red: f64, green: f64, blue: f64, alpha: f64) ?*anyopaque;
    extern fn CGColorRelease(color: ?*anyopaque) void;
    extern const AVMediaCharacteristicAudible: mod.Id;
    extern const AVMediaCharacteristicLegible: mod.Id;
    extern const AVMediaCharacteristicContainsOnlyForcedSubtitles: mod.Id;
    extern const AVLayerVideoGravityResizeAspect: mod.Id;

    /// The first live player, or null.
    var first: ?*NativePlayer = null;

    /// Counts `present` calls, so a player not shown in the latest is hidden.
    var frame_number: u64 = 0;

    /// The content view's resizes, after which the pictures are placed (and
    /// SDL's surface made clear) again until a transition has settled.
    var settle: mod.ResizeSettle = .{};

    /// Puts each region's player picture where its view is, and hides every
    /// player no view showed this frame. Runs on the main thread after the
    /// view tree painted, before the frame is presented.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `VideoPlayer` regions, in points.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.VideoRegion) void {
        frame_number += 1;
        if (regions.len == 0 and first == null) return;
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const ns_window: mod.Id = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        const content = mod.ObjectiveC.send(mod.Id, ns_window, "contentView", .{});
        if (content == null) return;
        const size = mod.ObjectiveC.send(mod.CGRect, content, "bounds", .{}).size;
        const settling = settle.note(size.width, size.height, views.FrameClock.shared().time());
        // A full-screen transition can make SDL's surface opaque again, which
        // would cover the pictures with black.
        if (settling and regions.len > 0) Self.clearSurfaces(content);
        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "begin", .{});
        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "setDisableActions:", .{@as(u8, 1)});
        for (regions) |region| {
            const handle = region.player.nativeHandle() orelse continue;
            if (region.player.backend != &Self.backend) continue;
            Self.place(@ptrCast(@alignCast(handle)), content, region);
        }
        var node = first;
        while (node) |native| : (node = native.next) {
            if (native.shown_in_frame != frame_number) native.hide();
        }
        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "commit", .{});
    }

    /// Takes every picture out of its window: the loop is ending, and the
    /// window goes before the players do.
    pub fn detachAll() void {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        var node = first;
        while (node) |native| : (node = native.next) {
            mod.ObjectiveC.send(void, native.container, "removeFromSuperview", .{});
            native.hidden = true;
        }
    }

    /// Makes an `AVPlayer`, its layer and the view that hosts it (hidden
    /// until a frame shows it).
    ///
    /// - Returns: the handle, or null when AVFoundation is missing.
    fn create() ?*anyopaque {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const player = mod.ObjectiveC.new("AVPlayer");
        if (player == null) return null;
        const player_layer = mod.ObjectiveC.new("AVPlayerLayer");
        mod.ObjectiveC.send(void, player_layer, "setPlayer:", .{player});
        mod.ObjectiveC.send(void, player_layer, "setVideoGravity:", .{Self.AVLayerVideoGravityResizeAspect});
        const black = Self.CGColorCreateSRGB(0, 0, 0, 1);
        defer Self.CGColorRelease(black);
        mod.ObjectiveC.send(void, player_layer, "setBackgroundColor:", .{black});
        mod.ObjectiveC.send(void, player_layer, "setMasksToBounds:", .{@as(u8, 1)});

        const host_layer = mod.ObjectiveC.new("CALayer");
        mod.ObjectiveC.send(void, host_layer, "setGeometryFlipped:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, host_layer, "setMasksToBounds:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, host_layer, "addSublayer:", .{player_layer});

        const container = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSView"), "alloc", .{}), "initWithFrame:", .{mod.CGRect{}});
        // A layer-hosting view: the layer is set before `wantsLayer`, so
        // AppKit leaves its geometry to us.
        mod.ObjectiveC.send(void, container, "setLayer:", .{host_layer});
        mod.ObjectiveC.send(void, container, "setWantsLayer:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, container, "setHidden:", .{@as(u8, 1)});

        const native = std.heap.c_allocator.create(NativePlayer) catch |err| {
            log.warn("player not made: {s}", .{@errorName(err)});
            mod.ObjectiveC.release(container);
            mod.ObjectiveC.release(host_layer);
            mod.ObjectiveC.release(player_layer);
            mod.ObjectiveC.release(player);
            return null;
        };
        native.* = .{ .player = player, .player_layer = player_layer, .host_layer = host_layer, .container = container, .next = first };
        if (first) |head| head.previous = native;
        first = native;
        return native;
    }

    /// Stops the player, takes its view out of the window and frees it all.
    ///
    /// - `handle`: the player.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        mod.ObjectiveC.send(void, native.player, "pause", .{});
        mod.ObjectiveC.send(void, native.player, "replaceCurrentItemWithPlayerItem:", .{@as(mod.Id, null)});
        mod.ObjectiveC.send(void, native.player_layer, "setPlayer:", .{@as(mod.Id, null)});
        mod.ObjectiveC.send(void, native.container, "removeFromSuperview", .{});
        mod.ObjectiveC.release(native.container);
        mod.ObjectiveC.release(native.host_layer);
        mod.ObjectiveC.release(native.player_layer);
        mod.ObjectiveC.release(native.player);
        if (native.previous) |previous| previous.next = native.next else first = native.next;
        if (native.next) |next| next.previous = native.previous;
        std.heap.c_allocator.destroy(native);
    }

    /// Replaces the current item: a URL with a scheme, else a local path.
    ///
    /// - `handle`: the player.
    /// - `url`: the media, or null for none.
    fn load(handle: *anyopaque, url: ?[:0]const u8) void {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        native.load_failure = "";
        const text = url orelse {
            mod.ObjectiveC.send(void, native.player, "replaceCurrentItemWithPlayerItem:", .{@as(mod.Id, null)});
            return;
        };
        const string = mod.ObjectiveC.string(text.ptr);
        const allocated = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSURL"), "alloc", .{});
        const ns_url = if (std.mem.find(u8, text, "://") != null)
            mod.ObjectiveC.send(mod.Id, allocated, "initWithString:", .{string})
        else
            mod.ObjectiveC.send(mod.Id, allocated, "initFileURLWithPath:", .{string});
        defer mod.ObjectiveC.release(ns_url);
        if (ns_url == null) {
            native.load_failure = "The address is not a valid URL.";
            mod.ObjectiveC.send(void, native.player, "replaceCurrentItemWithPlayerItem:", .{@as(mod.Id, null)});
            return;
        }
        const item = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("AVPlayerItem"), "alloc", .{}), "initWithURL:", .{ns_url});
        defer mod.ObjectiveC.release(item);
        mod.ObjectiveC.send(void, native.player, "replaceCurrentItemWithPlayerItem:", .{item});
    }

    /// Plays at `rate`, or pauses at 0.
    ///
    /// - `handle`: the player.
    /// - `rate`: the rate.
    fn setRate(handle: *anyopaque, rate: f32) void {
        const native = Self.nativeOf(handle);
        if (rate > 0) mod.ObjectiveC.send(void, native.player, "setRate:", .{rate}) else mod.ObjectiveC.send(void, native.player, "pause", .{});
    }

    /// Seeks to `seconds`, within `seek_precision_seconds` either way.
    ///
    /// - `handle`: the player.
    /// - `seconds`: where to.
    fn seek(handle: *anyopaque, seconds: f64) void {
        const native = Self.nativeOf(handle);
        const tolerance = Self.CMTimeMakeWithSeconds(seek_precision_seconds, seek_timescale);
        mod.ObjectiveC.send(void, native.player, "seekToTime:toleranceBefore:toleranceAfter:completionHandler:", .{ Self.CMTimeMakeWithSeconds(seconds, seek_timescale), tolerance, tolerance, @as(mod.Id, null) });
    }

    /// Sets the volume.
    ///
    /// - `handle`: the player.
    /// - `volume`: 0 to 1.
    fn setVolume(handle: *anyopaque, volume: f32) void {
        mod.ObjectiveC.send(void, Self.nativeOf(handle).player, "setVolume:", .{volume});
    }

    /// Mutes or unmutes.
    ///
    /// - `handle`: the player.
    /// - `muted`: true for no sound.
    fn setMuted(handle: *anyopaque, muted: bool) void {
        mod.ObjectiveC.send(void, Self.nativeOf(handle).player, "setMuted:", .{@as(u8, @intFromBool(muted))});
    }

    /// Samples the player and its item.
    ///
    /// - `handle`: the player.
    /// - Returns: the sample; `failure` points into the handle.
    fn observe(handle: *anyopaque) views.PlayerObservation {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        var observation: views.PlayerObservation = .{};
        if (native.load_failure.len > 0) {
            observation.status = .failed;
            observation.failure = native.load_failure;
            return observation;
        }
        const player = native.player;
        observation.rate = mod.ObjectiveC.send(f32, player, "rate", .{});
        observation.time_control = switch (mod.ObjectiveC.send(i64, player, "timeControlStatus", .{})) {
            time_control_waiting => .waitingToPlay,
            time_control_playing => .playing,
            else => .paused,
        };
        if (mod.ObjectiveC.send(i64, player, "status", .{}) == item_status_failed) {
            observation.status = .failed;
            observation.failure = native.copyFailure(mod.ObjectiveC.send(mod.Id, player, "error", .{}));
            return observation;
        }
        const item = mod.ObjectiveC.send(mod.Id, player, "currentItem", .{});
        if (item == null) return observation;
        observation.status = switch (mod.ObjectiveC.send(i64, item, "status", .{})) {
            item_status_ready => .readyToPlay,
            item_status_failed => .failed,
            else => .unknown,
        };
        if (observation.status == .failed) observation.failure = native.copyFailure(mod.ObjectiveC.send(mod.Id, item, "error", .{}));

        const current = Self.secondsOf(mod.ObjectiveC.send(mod.CMTime, player, "currentTime", .{})) orelse 0;
        observation.current_seconds = current;
        if (Self.secondsOf(mod.ObjectiveC.send(mod.CMTime, item, "duration", .{}))) |duration| {
            if (duration > 0) observation.duration_seconds = duration;
        }
        const ranges = mod.ObjectiveC.send(mod.Id, item, "loadedTimeRanges", .{});
        const count = mod.ObjectiveC.send(u64, ranges, "count", .{});
        for (0..count) |index| {
            const value = mod.ObjectiveC.send(mod.Id, ranges, "objectAtIndex:", .{@as(u64, index)});
            const range = mod.ObjectiveC.send(mod.CMTimeRange, value, "CMTimeRangeValue", .{});
            const start = Self.secondsOf(range.start) orelse continue;
            const end = start + (Self.secondsOf(range.duration) orelse continue);
            // The range the playhead is in, allowing for a playhead a hair
            // ahead of a range that just began.
            if (start <= current + 0.5 and end >= current) observation.buffered_seconds = @max(observation.buffered_seconds, end - current);
        }
        observation.likely_to_keep_up = mod.ObjectiveC.send(u8, item, "isPlaybackLikelyToKeepUp", .{}) != 0;
        observation.buffer_empty = mod.ObjectiveC.send(u8, item, "isPlaybackBufferEmpty", .{}) != 0;
        const size = mod.ObjectiveC.send(mod.CGSize, item, "presentationSize", .{});
        observation.presentation_width = @floatCast(size.width);
        observation.presentation_height = @floatCast(size.height);
        return observation;
    }

    /// Lists the item's media selection options of one kind.
    ///
    /// - `handle`: the player.
    /// - `allocator`: holds the list and its strings.
    /// - `kind`: audio or subtitles.
    /// - Returns: the tracks, empty until the item is ready; propagates
    ///   allocation failure.
    fn tracks(handle: *anyopaque, allocator: std.mem.Allocator, kind: views.PlayerTrackKind) std.mem.Allocator.Error![]views.PlayerTrack {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const item = native.readyItem() orelse return &.{};
        const group = Self.selectionGroup(item, kind) orelse return &.{};
        const options = mod.ObjectiveC.send(mod.Id, group, "options", .{});
        const selection = mod.ObjectiveC.send(mod.Id, item, "currentMediaSelection", .{});
        const selected = mod.ObjectiveC.send(mod.Id, selection, "selectedMediaOptionInMediaSelectionGroup:", .{group});
        const count = mod.ObjectiveC.send(u64, options, "count", .{});
        const list = try allocator.alloc(views.PlayerTrack, count);
        // On a failure, what was copied goes back, for a caller not on an arena.
        var filled: usize = 0;
        errdefer {
            for (list[0..filled]) |track| {
                allocator.free(track.name);
                allocator.free(track.language);
            }
            allocator.free(list);
        }
        for (list, 0..) |*track, index| {
            const option = mod.ObjectiveC.send(mod.Id, options, "objectAtIndex:", .{@as(u64, index)});
            const name = try allocator.dupe(u8, mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, option, "displayName", .{})));
            errdefer allocator.free(name);
            const language = try allocator.dupe(u8, mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, option, "extendedLanguageTag", .{})));
            track.* = .{
                .name = name,
                .language = language,
                .selected = option == selected,
                .forced = mod.ObjectiveC.send(u8, option, "hasMediaCharacteristic:", .{Self.AVMediaCharacteristicContainsOnlyForcedSubtitles}) != 0,
            };
            filled += 1;
        }
        return list;
    }

    /// Selects one of the item's media selection options, or no subtitles.
    ///
    /// - `handle`: the player.
    /// - `kind`: audio or subtitles.
    /// - `index`: the option's index in `tracks`, or null for none.
    fn selectTrack(handle: *anyopaque, kind: views.PlayerTrackKind, index: ?usize) void {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const item = native.readyItem() orelse return;
        const group = Self.selectionGroup(item, kind) orelse return;
        var option: mod.Id = null;
        if (index) |wanted| {
            const options = mod.ObjectiveC.send(mod.Id, group, "options", .{});
            if (wanted >= mod.ObjectiveC.send(u64, options, "count", .{})) return;
            option = mod.ObjectiveC.send(mod.Id, options, "objectAtIndex:", .{@as(u64, wanted)});
        } else if (mod.ObjectiveC.send(u8, group, "allowsEmptySelection", .{}) == 0) return;
        mod.ObjectiveC.send(void, item, "selectMediaOption:inMediaSelectionGroup:", .{ option, group });
    }

    /// The handle as its native player.
    ///
    /// - `handle`: what `create` returned.
    /// - Returns: the native player.
    fn nativeOf(handle: *anyopaque) *NativePlayer {
        return @ptrCast(@alignCast(handle));
    }

    /// The item's audible or legible media selection group (an HLS stream's
    /// `EXT-X-MEDIA` renditions). The synchronous lookup is deprecated in
    /// favor of an async load, which needs a block; on a ready item the
    /// group is already loaded, so it does not wait.
    ///
    /// - `item`: a ready item.
    /// - `kind`: audio or subtitles.
    /// - Returns: the group, or null when the item has none.
    fn selectionGroup(item: mod.Id, kind: views.PlayerTrackKind) mod.Id {
        const asset = mod.ObjectiveC.send(mod.Id, item, "asset", .{});
        const characteristic = switch (kind) {
            .audio => Self.AVMediaCharacteristicAudible,
            .subtitle => Self.AVMediaCharacteristicLegible,
        };
        return mod.ObjectiveC.send(mod.Id, asset, "mediaSelectionGroupForMediaCharacteristic:", .{characteristic});
    }

    /// A `CMTime` in seconds.
    ///
    /// - `time`: the time.
    /// - Returns: the seconds, or null for an invalid or indefinite time
    ///   (a live stream's duration).
    fn secondsOf(time: mod.CMTime) ?f64 {
        const value = Self.CMTimeGetSeconds(time);
        return if (std.math.isFinite(value)) value else null;
    }

    /// Shows a player's picture at its region: the view in `content` below
    /// SDL's, framed to the part on screen, the layer to the whole frame
    /// inside it. Each frame is compared with the one AppKit holds, not the
    /// one last asked for: a full-screen transition moves the views behind
    /// our back. The host layer is the container's own, which AppKit places
    /// in the window: only its size is set here, never its position.
    ///
    /// - `native`: the player.
    /// - `content`: the window's content view.
    /// - `region`: where its `VideoPlayer` is, in points.
    fn place(native: *NativePlayer, content: mod.Id, region: views.VideoRegion) void {
        native.shown_in_frame = frame_number;
        if (mod.ObjectiveC.send(mod.Id, native.container, "superview", .{}) != content) {
            mod.ObjectiveC.send(void, native.container, "removeFromSuperview", .{});
            mod.ObjectiveC.send(void, content, "addSubview:positioned:relativeTo:", .{ native.container, window_below, @as(mod.Id, null) });
            Self.clearSurfaces(content);
        }
        const visible = region.visible;
        if (visible.width <= 0 or visible.height <= 0) {
            native.hide();
            return;
        }
        const bounds = mod.ObjectiveC.send(mod.CGRect, content, "bounds", .{});
        const flipped = mod.ObjectiveC.send(u8, content, "isFlipped", .{}) != 0;
        const top: f64 = if (flipped) visible.y else bounds.size.height - visible.y - visible.height;
        const container_frame = mod.CGRect{ .origin = .{ .x = visible.x, .y = top }, .size = .{ .width = visible.width, .height = visible.height } };
        if (!container_frame.eql(mod.ObjectiveC.send(mod.CGRect, native.container, "frame", .{}))) {
            mod.ObjectiveC.send(void, native.container, "setFrame:", .{container_frame});
        }
        const host_bounds = mod.CGRect{ .size = container_frame.size };
        if (!host_bounds.eql(mod.ObjectiveC.send(mod.CGRect, native.host_layer, "bounds", .{}))) {
            mod.ObjectiveC.send(void, native.host_layer, "setBounds:", .{host_bounds});
        }
        const layer_frame = mod.CGRect{
            .origin = .{ .x = region.rect.x - visible.x, .y = region.rect.y - visible.y },
            .size = .{ .width = region.rect.width, .height = region.rect.height },
        };
        if (!layer_frame.eql(mod.ObjectiveC.send(mod.CGRect, native.player_layer, "frame", .{}))) {
            mod.ObjectiveC.send(void, native.player_layer, "setFrame:", .{layer_frame});
        }
        const radius: f64 = region.corner_radius;
        if (radius != native.corner_radius) {
            mod.ObjectiveC.send(void, native.player_layer, "setCornerRadius:", .{radius});
            native.corner_radius = radius;
        }
        if (native.hidden) {
            mod.ObjectiveC.send(void, native.container, "setHidden:", .{@as(u8, 0)});
            native.hidden = false;
        }
    }

    /// Makes SDL's Metal surfaces in `content` non-opaque, so Core Animation
    /// blends the frame (its erased holes) over the pictures beneath it; a
    /// surface already so is left alone.
    ///
    /// - `content`: the window's content view.
    fn clearSurfaces(content: mod.Id) void {
        const metal_layer_class = mod.ObjectiveC.class("CAMetalLayer");
        const subviews = mod.ObjectiveC.send(mod.Id, content, "subviews", .{});
        const count = mod.ObjectiveC.send(u64, subviews, "count", .{});
        for (0..count) |index| {
            const view = mod.ObjectiveC.send(mod.Id, subviews, "objectAtIndex:", .{@as(u64, index)});
            const layer = mod.ObjectiveC.send(mod.Id, view, "layer", .{});
            if (layer != null and mod.ObjectiveC.send(u8, layer, "isKindOfClass:", .{metal_layer_class}) != 0 and mod.ObjectiveC.send(u8, layer, "isOpaque", .{}) != 0) {
                mod.ObjectiveC.send(void, layer, "setOpaque:", .{@as(u8, 0)});
            }
        }
        const own_layer = mod.ObjectiveC.send(mod.Id, content, "layer", .{});
        if (own_layer != null and mod.ObjectiveC.send(u8, own_layer, "isKindOfClass:", .{metal_layer_class}) != 0 and mod.ObjectiveC.send(u8, own_layer, "isOpaque", .{}) != 0) {
            mod.ObjectiveC.send(void, own_layer, "setOpaque:", .{@as(u8, 0)});
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "av foundation player: a missing file fails with AVFoundation's reason, and no item clears it" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const handle = AvFoundationPlayer.backend.create() orelse return error.SkipZigTest;
    defer AvFoundationPlayer.backend.destroy(handle);
    AvFoundationPlayer.backend.load(handle, "/nonexistent/ziggui-test-video.mp4");
    AvFoundationPlayer.backend.set_volume(handle, 0.5);
    AvFoundationPlayer.backend.set_muted(handle, true);
    AvFoundationPlayer.backend.set_rate(handle, 1);
    AvFoundationPlayer.backend.seek(handle, 3);
    // AVFoundation settles the item's status on the main run loop.
    var observation = AvFoundationPlayer.backend.observe(handle);
    var waited: u32 = 0;
    while (observation.status == .unknown and waited < 200) : (waited += 1) {
        TestRunLoop.spin();
        observation = AvFoundationPlayer.backend.observe(handle);
    }
    try std.testing.expectEqual(views.PlayerStatus.failed, observation.status);
    try std.testing.expect(observation.failure.len > 0);
    try std.testing.expect(observation.duration_seconds == null);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), (try AvFoundationPlayer.backend.tracks(handle, arena.allocator(), .audio)).len);
    AvFoundationPlayer.backend.select_track(handle, .subtitle, null);

    AvFoundationPlayer.backend.load(handle, null);
    observation = AvFoundationPlayer.backend.observe(handle);
    try std.testing.expectEqual(views.PlayerStatus.unknown, observation.status);
    try std.testing.expectEqualStrings("", observation.failure);
}

/// Runs the main run loop briefly, for the tests: AVFoundation posts status
/// changes to it.
const TestRunLoop = struct {
    const Self = @This();

    extern fn CFRunLoopRunInMode(mode: ?*const anyopaque, seconds: f64, return_after_source_handled: u8) i32;
    extern const kCFRunLoopDefaultMode: ?*const anyopaque;

    /// Runs the loop for up to 25 ms.
    fn spin() void {
        _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.025, 0);
    }
};
