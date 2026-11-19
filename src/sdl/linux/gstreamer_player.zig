//! The Linux `PlayerBackend`: GStreamer's `playbin` per `Player`, loaded at
//! run time (`Gstreamer`), so an app runs without it; its players then report
//! `.failed`. It plays what the system's GStreamer plugins decode: a codec
//! with no plugin installed (H.264 without gst-libav, say) fails with
//! GStreamer's own "missing plug-in" message.
//!
//! The picture is drawn by ziggui, in the window's surface: `playbin`'s video
//! sink is an `appsink` taking RGBA at square pixels, whose each new frame
//! wakes the window (`FrameClock.wake`, from GStreamer's streaming thread);
//! `VideoPlayer` asks for the latest (`frame`) as it paints and draws it with
//! `DisplayList.drawVideoFrame`, uploaded to a texture of its own each frame. So
//! what an app stacks over the player (the controls, a sheet) draws on top,
//! as on macOS, where the picture sits behind the surface instead; the X11
//! child window the native-view host uses would cover them. No region is
//! collected (`presents` is false).
//!
//! The pipeline's bus is drained as the player is observed, on the UI
//! thread: no GLib main loop is involved. A network stream that runs dry
//! posts buffering messages, and the player pauses the pipeline until it has
//! buffered again, as GStreamer asks of an application. Linux only; other
//! targets reach it only behind `os_tag == .linux`.

const std = @import("std");
const log = std.log.scoped(.ziggui_gstreamer_player);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// One `Player`'s pipeline and what it reports.
const NativePlayer = struct {
    const Self = @This();

    /// The `playbin`, owned.
    playbin: *anyopaque,
    /// Its `appsink` video sink, owned by the `playbin`.
    sink: *anyopaque,
    /// The `playbin`'s bus, owned.
    bus: *anyopaque,
    /// An item is loaded.
    has_item: bool = false,
    /// The rate asked for: 0 paused.
    rate: f32 = 0,
    /// The rate the pipeline plays at, set with the last seek.
    playback_rate: f64 = 1,
    /// The state the `playbin` last reached.
    state: c_int = mod.Gstreamer.state_null,
    /// The pipeline prerolled since the item was loaded: it can play.
    ready: bool = false,
    /// How much of its buffer a running-dry stream has refilled, in percent,
    /// or null while it is not buffering.
    buffering: ?c_int = null,
    /// The item is live (it does not preroll): it is never paused to buffer.
    live: bool = false,
    /// A seek asked for before the pipeline could take one, in seconds.
    pending_seek: ?f64 = null,
    /// Why the item failed, until the next load.
    failure: [512]u8 = undefined,
    /// How many bytes of `failure` are used.
    failure_length: usize = 0,
    /// The latest frame's pixels, RGBA8, owned.
    pixels: []u8 = &.{},
    /// The latest frame's width, in pixels; 0 before the first.
    frame_width: u32 = 0,
    /// The latest frame's height, in pixels.
    frame_height: u32 = 0,
    /// The latest frame's generation (`PlayerFrame.generation`).
    generation: u64 = 0,
    /// A preroll sample (the first frame paused, or after a seek) came that
    /// `frame` has not taken: set on GStreamer's streaming thread.
    preroll_ready: std.atomic.Value(bool) = .init(false),

    /// Keeps `text` as the failure, cut on a character to fit.
    ///
    /// - `self`: the player.
    /// - `text`: why it failed.
    fn fail(self: *Self, text: []const u8) void {
        const length = views.DisplayText.fitLength(text, self.failure.len);
        @memcpy(self.failure[0..length], text[0..length]);
        self.failure_length = length;
    }
};

/// The Linux player behind every `Player`.
pub const GstreamerPlayer = struct {
    const Self = @This();

    /// The backend `Player`s are made with.
    pub const backend: views.PlayerBackend = .{
        .name = "GStreamer",
        .version = Self.version,
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
        .frame = Self.frame,
        .set_audio_output = Self.setAudioOutput,
    };

    /// No picture is placed behind the surface: `VideoPlayer` draws the
    /// frames itself, so the loop collects no regions.
    pub const presents = false;

    /// The caps the app sink takes: RGBA at square pixels, which `playbin`
    /// converts and scales any video to.
    const sink_caps = "video/x-raw,format=RGBA,pixel-aspect-ratio=1/1";

    /// The callbacks every app sink wakes the window with.
    const callbacks: mod.GstAppSinkCallbacks = .{ .new_preroll = Self.onPreroll, .new_sample = Self.onFrame };

    /// The generation the last frame taken by any player got, so each new
    /// frame's is unique in the process (UI thread only).
    var last_generation: u64 = 0;

    /// Places nothing: the frames are drawn in the surface.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `VideoPlayer` regions (none are collected).
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.VideoRegion) void {
        _ = window;
        _ = regions;
    }

    /// Nothing is in the window to take out.
    pub fn detachAll() void {}

    /// GStreamer's version ("GStreamer 1.26.2"), starting it if it has not
    /// started.
    ///
    /// - `allocator`: owns the text.
    /// - Returns: the version, or null where GStreamer cannot start; propagates
    ///   allocation failure.
    fn version(allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
        const api = mod.Gstreamer.start() orelse return null;
        const text = api.gst_version_string() orelse return null;
        defer api.g_free(text);
        return try allocator.dupe(u8, std.mem.span(text));
    }

    /// Makes a `playbin` with an RGBA app sink as its video sink and no item.
    ///
    /// - Returns: the handle, or null where GStreamer cannot run or will not
    ///   make the elements.
    fn create() ?*anyopaque {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const api = mod.Gstreamer.start() orelse return null;
        const playbin = api.gst_element_factory_make("playbin", null) orelse {
            log.warn("GStreamer has no playbin: video is unavailable", .{});
            return null;
        };
        _ = api.gst_object_ref_sink(playbin);
        const sink = api.gst_element_factory_make("appsink", null) orelse {
            log.warn("GStreamer has no appsink: video is unavailable", .{});
            api.gst_object_unref(playbin);
            return null;
        };
        if (api.gst_caps_from_string(sink_caps)) |caps| {
            api.g_object_set(sink, "caps", caps, @as(?*anyopaque, null));
            api.gst_mini_object_unref(caps);
        }
        // Only the newest frame is kept: one the window has not drawn yet is
        // dropped for the next, rather than holding the pipeline back.
        api.g_object_set(sink, "max-buffers", @as(c_uint, 1), "drop", @as(c_int, 1), @as(?*anyopaque, null));
        api.g_object_set(playbin, "video-sink", sink, @as(?*anyopaque, null));
        const bus = api.gst_element_get_bus(playbin) orelse {
            api.gst_object_unref(playbin);
            return null;
        };
        const native = std.heap.c_allocator.create(NativePlayer) catch |err| {
            log.warn("player not made: {s}", .{@errorName(err)});
            api.gst_object_unref(bus);
            api.gst_object_unref(playbin);
            return null;
        };
        native.* = .{ .playbin = playbin, .sink = sink, .bus = bus };
        api.gst_app_sink_set_callbacks(sink, &callbacks, native, null);
        return native;
    }

    /// Stops the pipeline and frees it.
    ///
    /// - `handle`: the player.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        if (mod.Gstreamer.running()) |api| {
            _ = api.gst_element_set_state(native.playbin, mod.Gstreamer.state_null);
            api.gst_object_unref(native.bus);
            api.gst_object_unref(native.playbin);
        }
        std.heap.c_allocator.free(native.pixels);
        std.heap.c_allocator.destroy(native);
    }

    /// Replaces the item: a URL, or a local path made a `file:` URL; null
    /// leaves the player empty. The new item starts paused unless the rate
    /// asked for is above 0.
    ///
    /// - `handle`: the player.
    /// - `url`: the item, or null.
    fn load(handle: *anyopaque, url: ?[:0]const u8) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return;
        _ = api.gst_element_set_state(native.playbin, mod.Gstreamer.state_null);
        Self.drain(api, native);
        native.* = .{ .playbin = native.playbin, .sink = native.sink, .bus = native.bus, .rate = native.rate, .pixels = native.pixels };
        const address = url orelse return;
        native.has_item = true;
        var converted: ?[*:0]u8 = null;
        defer if (converted) |owned| api.g_free(owned);
        const uri: [*:0]const u8 = if (api.gst_uri_is_valid(address) != 0) address else blk: {
            converted = api.gst_filename_to_uri(address, null);
            break :blk converted orelse {
                native.fail("Not an address or a file.");
                return;
            };
        };
        api.g_object_set(native.playbin, "uri", uri, @as(?*anyopaque, null));
        Self.applyState(api, native);
    }

    /// Plays at `rate` (1 normal speed); 0 pauses. A rate other than the one
    /// playing is a seek in place at the new rate.
    ///
    /// - `handle`: the player.
    /// - `rate`: the rate.
    fn setRate(handle: *anyopaque, rate: f32) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return;
        native.rate = rate;
        if (!native.has_item) return;
        if (rate > 0 and @as(f64, rate) != native.playback_rate and native.ready) {
            native.playback_rate = rate;
            Self.seekTo(api, native, Self.position(api, native) orelse 0);
        }
        Self.applyState(api, native);
    }

    /// Moves the playhead to `seconds`, once the pipeline can take a seek.
    ///
    /// - `handle`: the player.
    /// - `seconds`: where to, from the item's start.
    fn seek(handle: *anyopaque, seconds: f64) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return;
        if (!native.ready) {
            native.pending_seek = seconds;
            return;
        }
        Self.seekTo(api, native, seconds);
    }

    /// Sets the volume, 0 silent to 1 full.
    ///
    /// - `handle`: the player.
    /// - `volume`: the volume.
    fn setVolume(handle: *anyopaque, volume: f32) void {
        const api = mod.Gstreamer.running() orelse return;
        api.g_object_set(Self.nativeOf(handle).playbin, "volume", @as(f64, std.math.clamp(volume, 0, 1)), @as(?*anyopaque, null));
    }

    /// Routes the sound to one output (`GstreamerAudioOutputs.createSink`'s
    /// sink as `playbin`'s `audio-sink`), or to the system default when null
    /// (`playbin`'s own `autoaudiosink`). `playbin` takes a new sink only
    /// stopped, so a loaded item is stopped, rerouted and started again, an
    /// item with an end where it was, at the rate it played at. An output
    /// gone since it was listed leaves the default.
    ///
    /// - `handle`: the player.
    /// - `id`: the output's id, or null for the system default.
    /// - Returns: false when no output has that id now (the system default
    ///   plays), else true.
    fn setAudioOutput(handle: *anyopaque, id: ?[:0]const u8) bool {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return false;
        const sink: ?*anyopaque = if (id) |wanted| mod.GstreamerAudioOutputs.createSink(api, wanted) else null;
        const routed = id == null or sink != null;
        if (!routed) log.warn("audio output {s} not found: the system default plays", .{id.?});
        const resume_at = if (native.has_item) Self.resumePoint(api, native) else null;
        if (native.has_item) {
            _ = api.gst_element_set_state(native.playbin, mod.Gstreamer.state_null);
            Self.drain(api, native);
        }
        api.g_object_set(native.playbin, "audio-sink", sink, @as(?*anyopaque, null));
        if (!native.has_item) return routed;
        native.state = mod.Gstreamer.state_null;
        native.ready = false;
        native.buffering = null;
        native.pending_seek = resume_at;
        // The restarted pipeline plays at 1 until the preroll's seek gives it
        // the rate asked for (`drain`).
        native.playback_rate = 1;
        Self.applyState(api, native);
        return routed;
    }

    /// Mutes or unmutes, keeping the volume.
    ///
    /// - `handle`: the player.
    /// - `muted`: true to mute.
    fn setMuted(handle: *anyopaque, muted: bool) void {
        const api = mod.Gstreamer.running() orelse return;
        api.g_object_set(Self.nativeOf(handle).playbin, "mute", @as(c_int, @intFromBool(muted)), @as(?*anyopaque, null));
    }

    /// Takes what the pipeline posted since the last call, then samples it.
    ///
    /// - `handle`: the player.
    /// - Returns: its state now; `failure` lives in the handle.
    fn observe(handle: *anyopaque) views.PlayerObservation {
        const native = Self.nativeOf(handle);
        var observation: views.PlayerObservation = .{ .has_item = native.has_item, .rate = native.rate };
        const api = mod.Gstreamer.running() orelse return observation;
        Self.drain(api, native);
        if (native.failure_length > 0) {
            observation.status = .failed;
            observation.failure = native.failure[0..native.failure_length];
            return observation;
        }
        if (!native.has_item) return observation;
        observation.status = if (native.ready) .readyToPlay else .unknown;
        observation.rate = native.rate;
        observation.time_control = if (native.rate <= 0)
            .paused
        else if (native.state == mod.Gstreamer.state_playing and native.buffering == null)
            .playing
        else
            .waitingToPlay;
        observation.current_seconds = native.pending_seek orelse (Self.position(api, native) orelse 0);
        var duration: i64 = 0;
        if (!native.live and api.gst_element_query_duration(native.playbin, mod.Gstreamer.format_time, &duration) != 0 and duration > 0) {
            observation.duration_seconds = @as(f64, @floatFromInt(duration)) / mod.Gstreamer.nanoseconds_per_second;
        }
        observation.likely_to_keep_up = native.ready and native.buffering == null;
        observation.buffer_empty = if (native.buffering) |percent| percent == 0 else !native.ready;
        observation.presentation_width = @floatFromInt(native.frame_width);
        observation.presentation_height = @floatFromInt(native.frame_height);
        return observation;
    }

    /// Lists the item's audio or subtitle streams, named by their title or
    /// language tags.
    ///
    /// - `handle`: the player.
    /// - `allocator`: holds the list and its strings.
    /// - `kind`: audio or subtitles.
    /// - Returns: the tracks, empty until the item is ready; propagates
    ///   allocation failure.
    fn tracks(handle: *anyopaque, allocator: std.mem.Allocator, kind: views.PlayerTrackKind) std.mem.Allocator.Error![]views.PlayerTrack {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return &.{};
        if (!native.ready) return &.{};
        const names: [3][*:0]const u8 = switch (kind) {
            .audio => .{ "n-audio", "current-audio", "get-audio-tags" },
            .subtitle => .{ "n-text", "current-text", "get-text-tags" },
        };
        var count: c_int = 0;
        var current: c_int = -1;
        api.g_object_get(native.playbin, names[0], &count, names[1], &current, @as(?*anyopaque, null));
        const shown = kind == .audio or (Self.flags(api, native) & mod.Gstreamer.play_flag_text) != 0;
        var list: std.ArrayList(views.PlayerTrack) = .empty;
        errdefer {
            for (list.items) |track| {
                allocator.free(track.name);
                allocator.free(track.language);
            }
            list.deinit(allocator);
        }
        var index: c_int = 0;
        while (index < count) : (index += 1) {
            var tags: ?*anyopaque = null;
            api.g_signal_emit_by_name(native.playbin, names[2], index, &tags);
            defer if (tags) |held| api.gst_mini_object_unref(held);
            const language = try Self.tagText(api, allocator, tags, "language-code");
            errdefer allocator.free(language);
            const title = try Self.tagText(api, allocator, tags, "title");
            const name = if (title.len > 0) title else if (language.len > 0) blk: {
                allocator.free(title);
                break :blk try allocator.dupe(u8, language);
            } else blk: {
                allocator.free(title);
                break :blk try allocator.print("Track {d}", .{index + 1});
            };
            errdefer allocator.free(name);
            try list.append(allocator, .{ .name = name, .language = language, .selected = shown and index == current });
        }
        return list.toOwnedSlice(allocator);
    }

    /// Plays the audio stream at `index`, or shows the subtitle stream at
    /// `index` (none when null).
    ///
    /// - `handle`: the player.
    /// - `kind`: audio or subtitles.
    /// - `index`: an index into `tracks`' list, or null for no subtitles.
    fn selectTrack(handle: *anyopaque, kind: views.PlayerTrackKind, index: ?usize) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return;
        switch (kind) {
            .audio => if (index) |chosen| api.g_object_set(native.playbin, "current-audio", @as(c_int, @intCast(chosen)), @as(?*anyopaque, null)),
            .subtitle => {
                const current = Self.flags(api, native);
                if (index) |chosen| {
                    api.g_object_set(native.playbin, "flags", current | mod.Gstreamer.play_flag_text, "current-text", @as(c_int, @intCast(chosen)), @as(?*anyopaque, null));
                } else {
                    api.g_object_set(native.playbin, "flags", current & ~mod.Gstreamer.play_flag_text, @as(?*anyopaque, null));
                }
            },
        }
    }

    /// The newest frame the sink holds, copied out; else the one before,
    /// with its generation, so it is not uploaded again.
    ///
    /// - `handle`: the player.
    /// - Returns: the picture, valid until the next call, or null before the
    ///   first frame.
    fn frame(handle: *anyopaque) ?views.PlayerFrame {
        const native = Self.nativeOf(handle);
        const api = mod.Gstreamer.running() orelse return null;
        // Playing, the samples; paused, the preroll sample, taken once each
        // time one comes (the sink keeps handing back the same one).
        const sample = api.gst_app_sink_try_pull_sample(native.sink, 0) orelse
            if (native.preroll_ready.swap(false, .acquire)) api.gst_app_sink_try_pull_preroll(native.sink, 0) else null;
        if (sample) |held| {
            defer api.gst_mini_object_unref(held);
            Self.copyFrame(api, native, held);
        }
        if (native.frame_width == 0) return null;
        const size = @as(usize, native.frame_width) * native.frame_height * 4;
        return .{ .image = .{ .width = native.frame_width, .height = native.frame_height, .pixels = native.pixels[0..size] }, .generation = native.generation };
    }

    /// Copies a sample's RGBA pixels into the player's frame.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    /// - `sample`: the sample.
    fn copyFrame(api: *const mod.GstreamerApi, native: *NativePlayer, sample: *anyopaque) void {
        const caps = api.gst_sample_get_caps(sample) orelse return;
        const structure = api.gst_caps_get_structure(caps, 0) orelse return;
        var width: c_int = 0;
        var height: c_int = 0;
        if (api.gst_structure_get_int(structure, "width", &width) == 0 or api.gst_structure_get_int(structure, "height", &height) == 0) return;
        if (width <= 0 or height <= 0) return;
        const buffer = api.gst_sample_get_buffer(sample) orelse return;
        var map: mod.GstMapInfo = .{};
        if (api.gst_buffer_map(buffer, &map, mod.Gstreamer.map_read) == 0) return;
        defer api.gst_buffer_unmap(buffer, &map);
        const pixel_width: u32 = @intCast(width);
        const pixel_height: u32 = @intCast(height);
        // RGBA rows are whole words, so GStreamer pads none.
        const size = std.math.mul(usize, @as(usize, pixel_width) * pixel_height, 4) catch {
            log.warn("video frame of {d}x{d} dropped: too large", .{ pixel_width, pixel_height });
            return;
        };
        const data = map.data orelse return;
        if (map.size < size) return;
        if (native.pixels.len < size) {
            const grown = std.heap.c_allocator.realloc(native.pixels, size) catch |err| {
                log.warn("video frame of {d}x{d} dropped: {s}", .{ pixel_width, pixel_height, @errorName(err) });
                return;
            };
            native.pixels = grown;
        }
        @memcpy(native.pixels[0..size], data[0..size]);
        native.frame_width = pixel_width;
        native.frame_height = pixel_height;
        last_generation += 1;
        native.generation = last_generation;
    }

    /// Takes every message the pipeline posted, keeping its state, buffering,
    /// end and failure.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    fn drain(api: *const mod.GstreamerApi, native: *NativePlayer) void {
        while (api.gst_bus_pop(native.bus)) |message| {
            defer api.gst_mini_object_unref(message);
            if (message.type == mod.Gstreamer.message_error) {
                var failure: ?*mod.Gerror = null;
                api.gst_message_parse_error(message, &failure, null);
                if (failure) |reported| {
                    defer api.g_error_free(reported);
                    if (native.failure_length == 0) native.fail(std.mem.span(reported.message orelse "The item could not be played."));
                }
            } else if (message.type == mod.Gstreamer.message_element and api.gst_is_missing_plugin_message(message) != 0) {
                // Posted before the error, which says only that a plug-in is
                // missing: this names it ("H.264 (High Profile) decoder").
                if (api.gst_missing_plugin_message_get_description(message)) |description| {
                    defer api.g_free(description);
                    var text: [native.failure.len]u8 = undefined;
                    const line = std.mem.print(&text, "Missing a GStreamer plug-in: {s}.", .{std.mem.span(description)}) catch std.mem.span(description);
                    if (native.failure_length == 0) native.fail(line);
                }
            } else if (message.type == mod.Gstreamer.message_eos) {
                // Played to its end: paused there, the rate dropped, as the
                // platform players do.
                native.rate = 0;
                Self.applyState(api, native);
            } else if (message.type == mod.Gstreamer.message_buffering) {
                var percent: c_int = 100;
                api.gst_message_parse_buffering(message, &percent);
                native.buffering = if (percent < 100) percent else null;
                Self.applyState(api, native);
            } else if (message.type == mod.Gstreamer.message_state_changed and message.src == native.playbin) {
                var reached: c_int = 0;
                api.gst_message_parse_state_changed(message, null, &reached, null);
                native.state = reached;
            } else if (message.type == mod.Gstreamer.message_async_done and message.src == native.playbin) {
                native.ready = true;
                // A rate asked for before the pipeline could take a seek (a
                // new item, a reroute's restart) goes with the waiting seek,
                // or with a seek in place; a live item takes no rate.
                const rate_waiting = native.rate > 0 and @as(f64, native.rate) != native.playback_rate and !native.live;
                if (rate_waiting) native.playback_rate = native.rate;
                if (native.pending_seek) |seconds| {
                    native.pending_seek = null;
                    Self.seekTo(api, native, seconds);
                } else if (rate_waiting) Self.seekTo(api, native, Self.position(api, native) orelse 0);
            }
        }
    }

    /// Asks the pipeline for the state the rate and buffering call for:
    /// playing at a rate above 0 unless a stream is refilling, else paused.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    fn applyState(api: *const mod.GstreamerApi, native: *NativePlayer) void {
        if (!native.has_item or native.failure_length > 0) return;
        const refilling = native.buffering != null and !native.live;
        const wanted = if (native.rate > 0 and !refilling) mod.Gstreamer.state_playing else mod.Gstreamer.state_paused;
        const result = api.gst_element_set_state(native.playbin, wanted);
        if (result == mod.Gstreamer.state_change_failure) {
            Self.drain(api, native);
            if (native.failure_length == 0) native.fail("The item could not be played.");
        } else if (result == mod.Gstreamer.state_change_no_preroll) {
            native.live = true;
            native.ready = true;
        }
    }

    /// Seeks to `seconds` at the playback rate, flushing, to the exact frame.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    /// - `seconds`: where to.
    fn seekTo(api: *const mod.GstreamerApi, native: *NativePlayer, seconds: f64) void {
        const nanoseconds: i64 = @intFromFloat(@max(seconds, 0) * mod.Gstreamer.nanoseconds_per_second);
        const seek_flags = mod.Gstreamer.seek_flush | mod.Gstreamer.seek_accurate;
        if (api.gst_element_seek(native.playbin, native.playback_rate, mod.Gstreamer.format_time, seek_flags, mod.Gstreamer.seek_type_set, nanoseconds, mod.Gstreamer.seek_type_none, -1) == 0) {
            log.debug("seek to {d:.2}s refused", .{seconds});
        }
    }

    /// The playhead.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    /// - Returns: seconds from the item's start, or null while unknown.
    fn position(api: *const mod.GstreamerApi, native: *NativePlayer) ?f64 {
        var nanoseconds: i64 = 0;
        if (api.gst_element_query_position(native.playbin, mod.Gstreamer.format_time, &nanoseconds) == 0 or nanoseconds < 0) return null;
        return @as(f64, @floatFromInt(nanoseconds)) / mod.Gstreamer.nanoseconds_per_second;
    }

    /// Where a restarted item picks up: a seek still waiting for the
    /// pipeline, else the playhead of an item with an end; a live one (no
    /// end) starts again at its live edge.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    /// - Returns: seconds from the item's start, or null to start afresh.
    fn resumePoint(api: *const mod.GstreamerApi, native: *NativePlayer) ?f64 {
        // Asked for before the item could take it: its length is not known yet.
        if (native.pending_seek) |seconds| return seconds;
        if (native.live) return null;
        var duration: i64 = 0;
        if (api.gst_element_query_duration(native.playbin, mod.Gstreamer.format_time, &duration) == 0 or duration <= 0) return null;
        return Self.position(api, native);
    }

    /// `playbin`'s `flags`.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `native`: the player.
    /// - Returns: the `GstPlayFlags` mask.
    fn flags(api: *const mod.GstreamerApi, native: *NativePlayer) c_int {
        var value: c_int = 0;
        api.g_object_get(native.playbin, "flags", &value, @as(?*anyopaque, null));
        return value;
    }

    /// A tag's text, copied.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `allocator`: holds the copy.
    /// - `tags`: the `GstTagList`, or null.
    /// - `tag`: the tag's name.
    /// - Returns: the text, empty when the list has none; propagates
    ///   allocation failure.
    fn tagText(api: *const mod.GstreamerApi, allocator: std.mem.Allocator, tags: ?*anyopaque, tag: [*:0]const u8) std.mem.Allocator.Error![]u8 {
        const list = tags orelse return allocator.dupe(u8, "");
        var value: ?[*:0]u8 = null;
        if (api.gst_tag_list_get_string(list, tag, &value) == 0) return allocator.dupe(u8, "");
        const text = value orelse return allocator.dupe(u8, "");
        defer api.g_free(text);
        return allocator.dupe(u8, std.mem.span(text));
    }

    /// The app sink's `new_preroll`: notes that a preroll sample came, for
    /// `frame` to take once, and wakes the window. Runs on GStreamer's
    /// streaming thread.
    ///
    /// - `sink`: the app sink; unused.
    /// - `data`: the player.
    /// - Returns: `GST_FLOW_OK`.
    fn onPreroll(sink: *anyopaque, data: ?*anyopaque) callconv(.c) c_int {
        if (data) |player| {
            const native: *NativePlayer = @ptrCast(@alignCast(player));
            native.preroll_ready.store(true, .release);
        }
        return Self.onFrame(sink, data);
    }

    /// The app sink's `new_sample`: a frame is ready, so the window draws
    /// again. Runs on GStreamer's streaming thread.
    ///
    /// - `sink`: the app sink; unused.
    /// - `data`: unused.
    /// - Returns: `GST_FLOW_OK`.
    fn onFrame(sink: *anyopaque, data: ?*anyopaque) callconv(.c) c_int {
        _ = sink;
        _ = data;
        views.FrameClock.shared().wake();
        return 0;
    }

    /// The player behind a handle.
    ///
    /// - `handle`: the handle `create` returned.
    /// - Returns: the player.
    fn nativeOf(handle: *anyopaque) *NativePlayer {
        return @ptrCast(@alignCast(handle));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the Linux player draws its frames in the surface" {
    // Its function pointers reach `dlopen`, which only POSIX targets have.
    if (comptime mod.os_tag != .linux) return error.SkipZigTest;
    try std.testing.expect(!GstreamerPlayer.presents);
    try std.testing.expect(GstreamerPlayer.backend.unsupported == null);
    try std.testing.expect(GstreamerPlayer.backend.frame != null);
}
