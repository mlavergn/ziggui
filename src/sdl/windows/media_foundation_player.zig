//! The Windows `PlayerBackend`: Media Foundation's `IMFMediaEngine` (HTML5
//! media semantics: HLS, MP4, and whatever codecs Windows has) in
//! frame-server mode, one engine per `Player`.
//!
//! macOS shows its picture behind the window's surface; on Windows SDL's
//! swapchain is opaque to the desktop compositor, so nothing behind it can
//! show. Instead each frame `present` has the engine write its newest
//! picture (`OnVideoStreamTick`, `TransferVideoFrame`) into a WIC bitmap and
//! hands the bitmap's BGRA rows, read under a lock kept until the next
//! picture, to the renderer as a `VideoUnderlay`, which fills the hole the
//! `VideoPlayer` erased *under* what was painted after it, so controls and
//! overlays still draw over the picture. Decoding runs on the engine's own
//! threads; the UI thread copies a new frame only into the GPU's upload
//! buffer (rows WIC pads are first packed into a buffer of the player's). While a shown player plays, `present` asks for a frame every
//! display refresh or so. Audio and audio-track selection go through the
//! engine (`IMFMediaEngineEx` streams); there are no subtitle tracks.
//! Windows only: every caller is behind `os_tag == .windows`.

const std = @import("std");
const log = std.log.scoped(.ziggui_media_foundation_player);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// WIC's `WICRect`.
const WICRect = extern struct {
    const Self = @This();

    X: i32,
    Y: i32,
    Width: i32,
    Height: i32,
};

extern "mfplat" fn MFStartup(version: u32, flags: u32) callconv(.winapi) mod.HRESULT;
extern "mfplat" fn MFCreateAttributes(attributes: *?*anyopaque, size: u32) callconv(.winapi) mod.HRESULT;
extern "oleaut32" fn SysAllocString(text: [*:0]const u16) callconv(.winapi) ?[*:0]u16;
extern "oleaut32" fn SysFreeString(text: ?[*:0]u16) callconv(.winapi) void;

/// The identifiers the player needs.
const Guid = struct {
    const Self = @This();

    /// `CLSID_MFMediaEngineClassFactory`.
    const class_factory = std.os.windows.GUID.parse("{b44392da-499b-446b-a4cb-005fead0e6d5}");
    /// `IID_IMFMediaEngineClassFactory`.
    const iid_class_factory = std.os.windows.GUID.parse("{4d645ace-26aa-4688-9be1-df3516990b93}");
    /// `IID_IMFMediaEngineEx`.
    const iid_engine_ex = std.os.windows.GUID.parse("{83015ead-b1e6-40d0-a98a-37145ffe1ad1}");
    /// `IID_IMFMediaEngineAudioEndpointId`: the engine's output device.
    const iid_audio_endpoint_id = std.os.windows.GUID.parse("{7a3bac98-0e76-49fb-8c20-8a86fd98eaf2}");
    /// `IID_IMFMediaEngineNotify`.
    const iid_notify = std.os.windows.GUID.parse("{fee7c112-e776-42b5-9bbf-0048524e2bd5}");
    /// `MF_MEDIA_ENGINE_CALLBACK`.
    const engine_callback = std.os.windows.GUID.parse("{c60381b8-83a4-41f8-a3d0-de05076849a9}");
    /// `MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT`.
    const video_output_format = std.os.windows.GUID.parse("{5066893c-8cf9-42bc-8b8a-472212e52726}");
    /// `CLSID_WICImagingFactory`.
    const imaging_factory = std.os.windows.GUID.parse("{cacaf262-9370-4615-a13b-9f5539da4c0a}");
    /// `IID_IWICImagingFactory`.
    const iid_imaging_factory = std.os.windows.GUID.parse("{ec5ec8a9-c395-4314-9c77-54d7a935ff70}");
    /// `GUID_WICPixelFormat32bppBGRA`.
    const pixel_format_bgra = std.os.windows.GUID.parse("{6fddc324-4e03-4bfe-b185-3d77768dc90f}");
    /// `MF_MT_MAJOR_TYPE`.
    const major_type = std.os.windows.GUID.parse("{48eba18e-f8c9-4687-bf11-0a74c9f96a8f}");
    /// `MFMediaType_Audio`.
    const audio = std.os.windows.GUID.parse("{73647561-0000-0010-8000-00aa00389b71}");
    /// `MF_SD_LANGUAGE`.
    const language = std.os.windows.GUID.parse("{00af2180-bdc2-423c-abca-f503593bc121}");
    /// `MF_SD_STREAM_NAME`.
    const stream_name = std.os.windows.GUID.parse("{4f1b099d-d314-41e5-a781-7fefaa4c501f}");
};

/// `IMFMediaEngine`'s (and `IMFMediaEngineEx`'s) vtable slots.
const EngineSlot = struct {
    const Self = @This();

    /// `GetError(IMFMediaError**)`.
    const get_error = 3;
    /// `SetSource(BSTR)`.
    const set_source = 6;
    /// `SetPreload(MF_MEDIA_ENGINE_PRELOAD)`.
    const set_preload = 10;
    /// `GetBuffered(IMFMediaTimeRange**)`.
    const get_buffered = 11;
    /// `GetReadyState()`, a `USHORT`.
    const get_ready_state = 14;
    /// `IsSeeking()`, a `BOOL`.
    const is_seeking = 15;
    /// `GetCurrentTime()`, a `double`.
    const get_current_time = 16;
    /// `SetCurrentTime(double)`.
    const set_current_time = 17;
    /// `GetDuration()`, a `double`.
    const get_duration = 19;
    /// `IsPaused()`, a `BOOL`.
    const is_paused = 20;
    /// `SetDefaultPlaybackRate(double)`.
    const set_default_playback_rate = 22;
    /// `GetPlaybackRate()`, a `double`.
    const get_playback_rate = 23;
    /// `SetPlaybackRate(double)`.
    const set_playback_rate = 24;
    /// `IsEnded()`, a `BOOL`.
    const is_ended = 27;
    /// `Play()`.
    const play = 32;
    /// `Pause()`.
    const pause = 33;
    /// `SetMuted(BOOL)`.
    const set_muted = 35;
    /// `SetVolume(double)`.
    const set_volume = 37;
    /// `GetNativeVideoSize(DWORD*, DWORD*)`.
    const get_native_video_size = 40;
    /// `Shutdown()`.
    const shutdown = 42;
    /// `TransferVideoFrame(IUnknown*, MFVideoNormalizedRect*, RECT*, MFARGB*)`.
    const transfer_video_frame = 43;
    /// `OnVideoStreamTick(LONGLONG*)`: `S_OK` when a new frame is ready.
    const on_video_stream_tick = 44;
    /// `IMFMediaEngineEx::GetNumberOfStreams(DWORD*)`.
    const get_number_of_streams = 54;
    /// `IMFMediaEngineEx::GetStreamAttribute(DWORD, REFGUID, PROPVARIANT*)`.
    const get_stream_attribute = 55;
    /// `IMFMediaEngineEx::GetStreamSelection(DWORD, BOOL*)`.
    const get_stream_selection = 56;
    /// `IMFMediaEngineEx::SetStreamSelection(DWORD, BOOL)`.
    const set_stream_selection = 57;
    /// `IMFMediaEngineEx::ApplyStreamSelections()`.
    const apply_stream_selections = 58;
};

/// The other Media Foundation and WIC vtable slots the player calls.
const OtherSlot = struct {
    const Self = @This();

    /// `IMFMediaEngineClassFactory::CreateInstance(DWORD, IMFAttributes*, IMFMediaEngine**)`.
    const create_engine = 3;
    /// `IMFMediaEngineAudioEndpointId::SetAudioEndpointId(LPCWSTR)`.
    const set_audio_endpoint_id = 3;
    /// `IMFAttributes::SetUINT32(REFGUID, UINT32)`.
    const set_uint32 = 21;
    /// `IMFAttributes::SetUnknown(REFGUID, IUnknown*)`.
    const set_unknown = 27;
    /// `IMFMediaError::GetErrorCode()`, a `USHORT`.
    const error_code = 3;
    /// `IMFMediaTimeRange::GetLength()`, a `DWORD`.
    const range_length = 3;
    /// `IMFMediaTimeRange::GetStart(DWORD, double*)`.
    const range_start = 4;
    /// `IMFMediaTimeRange::GetEnd(DWORD, double*)`.
    const range_end = 5;
    /// `IWICImagingFactory::CreateBitmap(UINT, UINT, REFWICPixelFormatGUID, WICBitmapCreateCacheOption, IWICBitmap**)`.
    const create_bitmap = 17;
    /// `IWICBitmap::Lock(const WICRect*, DWORD, IWICBitmapLock**)`.
    const lock_bitmap = 8;
    /// `IWICBitmapLock::GetStride(UINT*)`.
    const lock_stride = 4;
    /// `IWICBitmapLock::GetDataPointer(UINT*, BYTE**)`.
    const lock_data = 5;
};

/// The vtable of the engine's callback object.
const NotifyVtable = extern struct {
    const Self = @This();

    /// `QueryInterface`.
    query_interface: *const fn (*Notify, *const std.os.windows.GUID, *?*anyopaque) callconv(.winapi) mod.HRESULT,
    /// `AddRef`.
    add_ref: *const fn (*Notify) callconv(.winapi) u32,
    /// `Release`.
    release: *const fn (*Notify) callconv(.winapi) u32,
    /// `EventNotify(DWORD event, DWORD_PTR param1, DWORD param2)`.
    event_notify: *const fn (*Notify, u32, usize, u32) callconv(.winapi) mod.HRESULT,
};

/// The engine's `IMFMediaEngineNotify`, which the engine requires. It is
/// called on the engine's threads and keeps nothing it hears (only its
/// reference count is shared, an atomic): the player polls the engine itself.
const Notify = extern struct {
    const Self = @This();

    /// The COM vtable; first, as COM requires.
    vtable: *const NotifyVtable = &Self.table,
    /// The references held, from any thread.
    references: std.atomic.Value(u32) = .init(1),

    /// The shared vtable.
    const table = NotifyVtable{
        .query_interface = Self.queryInterface,
        .add_ref = Self.addRef,
        .release = Self.release,
        .event_notify = Self.eventNotify,
    };

    /// `IUnknown::QueryInterface`: itself for `IUnknown` and `IMFMediaEngineNotify`.
    ///
    /// - `self`: the callback.
    /// - `interface`: the interface asked for.
    /// - `object`: receives the interface.
    /// - Returns: `S_OK`, or `E_NOINTERFACE`.
    fn queryInterface(self: *Self, interface: *const std.os.windows.GUID, object: *?*anyopaque) callconv(.winapi) mod.HRESULT {
        if (std.meta.eql(interface.*, mod.Com.iid_unknown) or std.meta.eql(interface.*, Guid.iid_notify)) {
            _ = self.references.fetchAdd(1, .monotonic);
            object.* = self;
            return mod.Com.ok;
        }
        object.* = null;
        return mod.Com.no_interface;
    }

    /// `IUnknown::AddRef`.
    ///
    /// - `self`: the callback.
    /// - Returns: the references now held.
    fn addRef(self: *Self) callconv(.winapi) u32 {
        return self.references.fetchAdd(1, .monotonic) + 1;
    }

    /// `IUnknown::Release`: frees the callback with its last reference.
    ///
    /// - `self`: the callback.
    /// - Returns: the references left.
    fn release(self: *Self) callconv(.winapi) u32 {
        const left = self.references.fetchSub(1, .acq_rel) - 1;
        if (left == 0) std.heap.c_allocator.destroy(self);
        return left;
    }

    /// `IMFMediaEngineNotify::EventNotify`: nothing to do, since the player
    /// polls the engine as it draws.
    ///
    /// - `self`: the callback; unused.
    /// - `event`: the `MF_MEDIA_ENGINE_EVENT`; unused.
    /// - `first`: its first parameter; unused.
    /// - `second`: its second parameter; unused.
    /// - Returns: `S_OK`.
    fn eventNotify(self: *Self, event: u32, first: usize, second: u32) callconv(.winapi) mod.HRESULT {
        _ = self;
        _ = event;
        _ = first;
        _ = second;
        return mod.Com.ok;
    }
};

/// One `Player`'s engine, its newest frame, and what it was asked to do.
const NativePlayer = struct {
    const Self = @This();

    /// The `IMFMediaEngineEx` (an `IMFMediaEngine` first).
    engine: *anyopaque,
    /// The engine's callback.
    notify: *Notify,
    /// The WIC bitmap frames are copied into, sized to the last frame.
    bitmap: ?*anyopaque = null,
    /// `bitmap`'s width.
    bitmap_width: u32 = 0,
    /// `bitmap`'s height.
    bitmap_height: u32 = 0,
    /// The read lock held on `bitmap` while `pixels` points into it.
    lock: ?*anyopaque = null,
    /// The newest frame, BGRA, rows packed: the locked bitmap's own rows, or
    /// `packed_rows` when WIC pads them.
    pixels: []const u8 = &.{},
    /// The frame's rows packed, when the bitmap's are padded; owned.
    packed_rows: []u8 = &.{},
    /// Its width.
    frame_width: u32 = 0,
    /// Its height.
    frame_height: u32 = 0,
    /// Bumped with each new frame.
    generation: u64 = 0,
    /// An item is loaded.
    has_item: bool = false,
    /// The rate asked for: 0 paused.
    rate: f32 = 0,
    /// Why the item failed, for `observe`.
    failure: [256]u8 = undefined,
    /// How many bytes of `failure` are used.
    failure_length: usize = 0,

    /// Calls a `BOOL`-returning engine method.
    ///
    /// - `self`: the player.
    /// - `slot`: the method's slot.
    /// - Returns: its answer.
    fn flag(self: *const Self, comptime slot: usize) bool {
        return mod.Com.method(*const fn (*anyopaque) callconv(.winapi) i32, self.engine, slot)(self.engine) != 0;
    }

    /// Calls a `double`-returning engine method.
    ///
    /// - `self`: the player.
    /// - `slot`: the method's slot.
    /// - Returns: its answer.
    fn number(self: *const Self, comptime slot: usize) f64 {
        return mod.Com.method(*const fn (*anyopaque) callconv(.winapi) f64, self.engine, slot)(self.engine);
    }

    /// Calls an engine method taking one `double`.
    ///
    /// - `self`: the player.
    /// - `slot`: the method's slot.
    /// - `value`: the argument.
    fn setNumber(self: *const Self, comptime slot: usize, value: f64) void {
        _ = mod.Com.method(*const fn (*anyopaque, f64) callconv(.winapi) mod.HRESULT, self.engine, slot)(self.engine, value);
    }

    /// Calls an engine method taking nothing.
    ///
    /// - `self`: the player.
    /// - `slot`: the method's slot.
    fn act(self: *const Self, comptime slot: usize) void {
        _ = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) mod.HRESULT, self.engine, slot)(self.engine);
    }

    /// Keeps a failure for `observe`, cut to fit on a character.
    ///
    /// - `self`: the player.
    /// - `text`: why the item failed.
    fn setFailure(self: *Self, text: []const u8) void {
        const length = views.DisplayText.fitLength(text, self.failure.len);
        @memcpy(self.failure[0..length], text[0..length]);
        self.failure_length = length;
    }

    /// The engine's error code (`MF_MEDIA_ENGINE_ERR`), 0 for none.
    ///
    /// - `self`: the player.
    /// - Returns: the code.
    fn errorCode(self: *const Self) u16 {
        var media_error: ?*anyopaque = null;
        _ = mod.Com.method(*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_error)(self.engine, &media_error);
        const held = media_error orelse return 0;
        defer mod.Com.release(held);
        return mod.Com.method(*const fn (*anyopaque) callconv(.winapi) u16, held, OtherSlot.error_code)(held);
    }

    /// How many seconds past the playhead are loaded.
    ///
    /// - `self`: the player.
    /// - `current`: the playhead.
    /// - Returns: the end of the loaded range holding it, less the playhead; 0 when none does.
    fn bufferedAhead(self: *const Self, current: f64) f64 {
        var ranges: ?*anyopaque = null;
        _ = mod.Com.method(*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_buffered)(self.engine, &ranges);
        const held = ranges orelse return 0;
        defer mod.Com.release(held);
        const count = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) u32, held, OtherSlot.range_length)(held);
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            var start: f64 = 0;
            var end: f64 = 0;
            _ = mod.Com.method(*const fn (*anyopaque, u32, *f64) callconv(.winapi) mod.HRESULT, held, OtherSlot.range_start)(held, index, &start);
            _ = mod.Com.method(*const fn (*anyopaque, u32, *f64) callconv(.winapi) mod.HRESULT, held, OtherSlot.range_end)(held, index, &end);
            if (current >= start - 0.25 and current <= end) return @max(0, end - current);
        }
        return 0;
    }

    /// Has the engine write its newest frame, when it has one the player has
    /// not taken yet, into the WIC bitmap, and points `pixels` at it.
    ///
    /// - `self`: the player.
    fn refreshFrame(self: *Self) void {
        var presentation_time: i64 = 0;
        const tick = mod.Com.method(*const fn (*anyopaque, *i64) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.on_video_stream_tick)(self.engine, &presentation_time);
        if (tick != mod.Com.ok) return;
        var width: u32 = 0;
        var height: u32 = 0;
        _ = mod.Com.method(*const fn (*anyopaque, *u32, *u32) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_native_video_size)(self.engine, &width, &height);
        if (width == 0 or height == 0) return;
        // The engine cannot write into a bitmap read under a lock.
        self.unlockFrame();
        if (!self.ensureBitmap(width, height)) return;
        const bitmap = self.bitmap.?;
        const target = mod.RECT{ .right = @intCast(width), .bottom = @intCast(height) };
        const transferred = mod.Com.method(*const fn (*anyopaque, *anyopaque, ?*const anyopaque, *const mod.RECT, ?*const anyopaque) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.transfer_video_frame)(self.engine, bitmap, null, &target, null);
        if (transferred < 0) {
            log.debug("frame not transferred [0x{x}]", .{@as(u32, @bitCast(transferred))});
            return;
        }
        self.lockFrame(bitmap, width, height);
    }

    /// Reads the bitmap's new frame under a lock kept until the next one:
    /// `pixels` is the bitmap's own rows when WIC packs them, else the rows
    /// packed into `packed_rows`, and the lock goes at once.
    ///
    /// - `self`: the player.
    /// - `bitmap`: the WIC bitmap the engine wrote the frame into.
    /// - `width`: the frame's width.
    /// - `height`: its height.
    fn lockFrame(self: *Self, bitmap: *anyopaque, width: u32, height: u32) void {
        var lock: ?*anyopaque = null;
        const area = WICRect{ .X = 0, .Y = 0, .Width = @intCast(width), .Height = @intCast(height) };
        _ = mod.Com.method(*const fn (*anyopaque, *const WICRect, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, bitmap, OtherSlot.lock_bitmap)(bitmap, &area, MediaFoundationPlayer.wic_lock_read, &lock);
        const held = lock orelse return;
        var stride: u32 = 0;
        var size: u32 = 0;
        var data: ?[*]const u8 = null;
        _ = mod.Com.method(*const fn (*anyopaque, *u32) callconv(.winapi) mod.HRESULT, held, OtherSlot.lock_stride)(held, &stride);
        _ = mod.Com.method(*const fn (*anyopaque, *u32, *?[*]const u8) callconv(.winapi) mod.HRESULT, held, OtherSlot.lock_data)(held, &size, &data);
        const row_bytes = @as(usize, width) * 4;
        const byte_count = row_bytes * height;
        const source = data orelse {
            mod.Com.release(held);
            return;
        };
        if (stride < row_bytes or size < @as(usize, stride) * (height - 1) + row_bytes) {
            mod.Com.release(held);
            return;
        }
        if (stride == row_bytes) {
            self.lock = held;
            self.pixels = source[0..byte_count];
        } else {
            defer mod.Com.release(held);
            if (self.packed_rows.len != byte_count) {
                if (self.packed_rows.len > 0) std.heap.c_allocator.free(self.packed_rows);
                self.packed_rows = std.heap.c_allocator.alloc(u8, byte_count) catch |err| {
                    log.warn("video frame of {d}x{d} dropped: {s}", .{ width, height, @errorName(err) });
                    self.packed_rows = &.{};
                    return;
                };
            }
            for (0..height) |row| @memcpy(self.packed_rows[row * row_bytes ..][0..row_bytes], source[row * stride ..][0..row_bytes]);
            self.pixels = self.packed_rows;
        }
        self.frame_width = width;
        self.frame_height = height;
        self.generation = MediaFoundationPlayer.nextGeneration();
    }

    /// Lets the bitmap's lock go, so the engine can write the next frame;
    /// `pixels` holds nothing until it does.
    ///
    /// - `self`: the player.
    fn unlockFrame(self: *Self) void {
        if (self.lock) |held| mod.Com.release(held);
        self.lock = null;
        self.pixels = &.{};
    }

    /// Makes the WIC bitmap frames are copied into, at a frame's size.
    ///
    /// - `self`: the player.
    /// - `width`: the frame's width.
    /// - `height`: its height.
    /// - Returns: false when WIC refused.
    fn ensureBitmap(self: *Self, width: u32, height: u32) bool {
        if (self.bitmap != null and self.bitmap_width == width and self.bitmap_height == height) return true;
        mod.Com.release(self.bitmap);
        self.bitmap = null;
        const factory = MediaFoundationPlayer.imagingFactory() orelse return false;
        var bitmap: ?*anyopaque = null;
        const result = mod.Com.method(*const fn (*anyopaque, u32, u32, *const std.os.windows.GUID, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, factory, OtherSlot.create_bitmap)(factory, width, height, &Guid.pixel_format_bgra, MediaFoundationPlayer.wic_cache_on_load, &bitmap);
        if (result < 0 or bitmap == null) return false;
        self.bitmap = bitmap;
        self.bitmap_width = width;
        self.bitmap_height = height;
        return true;
    }

    /// Reads a stream's string attribute.
    ///
    /// - `self`: the player.
    /// - `allocator`: owns the result.
    /// - `stream`: the stream's index.
    /// - `attribute`: the attribute.
    /// - Returns: the text, empty when the stream has none; propagates allocation failure.
    fn streamText(self: *const Self, allocator: std.mem.Allocator, stream: u32, attribute: *const std.os.windows.GUID) std.mem.Allocator.Error![]u8 {
        var value = mod.PROPVARIANT{};
        const result = mod.Com.method(*const fn (*anyopaque, u32, *const std.os.windows.GUID, *mod.PROPVARIANT) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_stream_attribute)(self.engine, stream, attribute, &value);
        defer mod.Com.clearVariant(&value);
        if (result < 0 or value.vt != mod.PROPVARIANT.vt_lpwstr) return allocator.alloc(u8, 0);
        return mod.Com.narrow(allocator, @ptrCast(@alignCast(value.pointer)));
    }

    /// Reports whether a stream carries audio.
    ///
    /// - `self`: the player.
    /// - `stream`: the stream's index.
    /// - Returns: true for an audio stream.
    fn isAudio(self: *const Self, stream: u32) bool {
        var value = mod.PROPVARIANT{};
        const result = mod.Com.method(*const fn (*anyopaque, u32, *const std.os.windows.GUID, *mod.PROPVARIANT) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_stream_attribute)(self.engine, stream, &Guid.major_type, &value);
        defer mod.Com.clearVariant(&value);
        if (result < 0 or value.vt != mod.PROPVARIANT.vt_clsid) return false;
        const major: *const std.os.windows.GUID = @ptrCast(@alignCast(value.pointer orelse return false));
        return std.meta.eql(major.*, Guid.audio);
    }

    /// How many streams the item has.
    ///
    /// - `self`: the player.
    /// - Returns: the count; 0 before the item's metadata loaded.
    fn streamCount(self: *const Self) u32 {
        var count: u32 = 0;
        _ = mod.Com.method(*const fn (*anyopaque, *u32) callconv(.winapi) mod.HRESULT, self.engine, EngineSlot.get_number_of_streams)(self.engine, &count);
        return count;
    }
};

/// The Windows player behind every `Player`.
pub const MediaFoundationPlayer = struct {
    const Self = @This();

    /// The backend `Player`s are made with.
    pub const backend: views.PlayerBackend = .{
        .name = "Media Foundation",
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
        .set_audio_output = Self.setAudioOutput,
    };

    /// Its pictures show in the window: the loop collects `VideoPlayer`
    /// regions, and `present` draws each frame under the hole.
    pub const presents = true;

    /// `MF_VERSION`.
    const mf_version: u32 = 0x00020070;
    /// `DXGI_FORMAT_B8G8R8A8_UNORM`, the frames' format.
    const dxgi_format_bgra: u32 = 87;
    /// `MF_MEDIA_ENGINE_PRELOAD_AUTOMATIC`.
    const preload_automatic: u32 = 4;
    /// `WICBitmapLockRead`.
    const wic_lock_read: u32 = 1;
    /// `WICBitmapCacheOnLoad`.
    const wic_cache_on_load: u32 = 1;
    /// `MF_MEDIA_ENGINE_READY_HAVE_METADATA`.
    const have_metadata: u16 = 1;
    /// `MF_MEDIA_ENGINE_READY_HAVE_FUTURE_DATA`.
    const have_future_data: u16 = 3;
    /// How long to wait between frames while a shown player plays: a
    /// 60 Hz display's refresh, so no new frame waits longer than one.
    const frame_interval_ms: u64 = 16;

    /// Media Foundation has started.
    var started: bool = false;
    /// The engine factory, made once.
    var engine_factory: ?*anyopaque = null;
    /// The WIC factory frames are copied with, made once.
    var wic_factory: ?*anyopaque = null;
    /// This frame's underlays, for the renderer.
    var frame_underlays: std.ArrayList(mod.VideoUnderlay) = .empty;

    /// The generation the last frame taken by any player got, so each new
    /// frame's is unique in the process: a player made where a freed one was
    /// never passes for it (UI thread only).
    var last_generation: u64 = 0;
    /// Copies each shown player's newest frame and lists where the renderer
    /// draws it this frame; asks for the next frame while one plays.
    ///
    /// - `window`: the main window; unused (the renderer draws the frames).
    /// - `regions`: the frame's `VideoPlayer` regions.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.VideoRegion) void {
        _ = window;
        frame_underlays.clearRetainingCapacity();
        var playing = false;
        for (regions) |region| {
            const handle = region.player.nativeHandle() orelse continue;
            const native = Self.nativeOf(handle);
            if (!native.has_item) continue;
            native.refreshFrame();
            if (native.rate > 0 and !native.flag(EngineSlot.is_paused) and !native.flag(EngineSlot.is_ended)) playing = true;
            frame_underlays.append(std.heap.c_allocator, .{
                .key = @intFromPtr(native),
                .generation = native.generation,
                .width = native.frame_width,
                .height = native.frame_height,
                .pixels = native.pixels,
                .frame = region.rect,
                .picture = region.rect.aspectFit(native.frame_width, native.frame_height),
            }) catch |err| log.debug("underlay not kept [{t}]", .{err});
        }
        if (playing) {
            const clock = views.FrameClock.shared();
            clock.requestFrameAt(clock.time() + Self.frame_interval_ms);
        }
    }

    /// This frame's frames to draw under the surface.
    ///
    /// - Returns: the underlays `present` listed, valid until its next call.
    pub fn underlays() []const mod.VideoUnderlay {
        return frame_underlays.items;
    }

    /// Forgets the frames listed; the loop is ending.
    pub fn detachAll() void {
        frame_underlays.clearAndFree(std.heap.c_allocator);
    }

    /// Makes an engine with no item.
    ///
    /// - Returns: the player, or null when Media Foundation refused.
    fn create() ?*anyopaque {
        if (!mod.Com.enterApartment()) return null;
        if (!started) {
            const result = MFStartup(Self.mf_version, 0);
            if (result < 0) {
                log.warn("MFStartup failed [0x{x}]", .{@as(u32, @bitCast(result))});
                return null;
            }
            started = true;
        }
        if (engine_factory == null) engine_factory = mod.Com.create(&Guid.class_factory, &Guid.iid_class_factory);
        const factory = engine_factory orelse return null;
        var attributes: ?*anyopaque = null;
        if (MFCreateAttributes(&attributes, 2) < 0) return null;
        const held_attributes = attributes orelse return null;
        defer mod.Com.release(held_attributes);
        const notify = std.heap.c_allocator.create(Notify) catch |err| {
            log.warn("media engine not made: {s}", .{@errorName(err)});
            return null;
        };
        notify.* = .{};
        _ = mod.Com.method(*const fn (*anyopaque, *const std.os.windows.GUID, *anyopaque) callconv(.winapi) mod.HRESULT, held_attributes, OtherSlot.set_unknown)(held_attributes, &Guid.engine_callback, notify);
        _ = mod.Com.method(*const fn (*anyopaque, *const std.os.windows.GUID, u32) callconv(.winapi) mod.HRESULT, held_attributes, OtherSlot.set_uint32)(held_attributes, &Guid.video_output_format, Self.dxgi_format_bgra);
        var made: ?*anyopaque = null;
        const result = mod.Com.method(*const fn (*anyopaque, u32, *anyopaque, *?*anyopaque) callconv(.winapi) mod.HRESULT, factory, OtherSlot.create_engine)(factory, 0, held_attributes, &made);
        const engine = made orelse {
            log.warn("media engine not made [0x{x}]", .{@as(u32, @bitCast(result))});
            _ = Notify.release(notify);
            return null;
        };
        defer mod.Com.release(engine);
        const extended = mod.Com.query(engine, &Guid.iid_engine_ex) orelse {
            log.warn("media engine lacks IMFMediaEngineEx", .{});
            _ = Notify.release(notify);
            return null;
        };
        const native = std.heap.c_allocator.create(NativePlayer) catch |err| {
            log.warn("media engine not made: {s}", .{@errorName(err)});
            mod.Com.release(extended);
            _ = Notify.release(notify);
            return null;
        };
        native.* = .{ .engine = extended, .notify = notify };
        _ = mod.Com.method(*const fn (*anyopaque, u32) callconv(.winapi) mod.HRESULT, extended, EngineSlot.set_preload)(extended, Self.preload_automatic);
        return native;
    }

    /// Stops the engine and frees it, its bitmap and its frame.
    ///
    /// - `handle`: the player.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        for (frame_underlays.items, 0..) |underlay, index| {
            if (underlay.key == @intFromPtr(native)) {
                _ = frame_underlays.orderedRemove(index);
                break;
            }
        }
        native.act(EngineSlot.shutdown);
        native.unlockFrame();
        mod.Com.release(native.engine);
        mod.Com.release(native.bitmap);
        _ = Notify.release(native.notify);
        if (native.packed_rows.len > 0) std.heap.c_allocator.free(native.packed_rows);
        std.heap.c_allocator.destroy(native);
    }

    /// Replaces the item with the media at `url` (a URL, or a local path),
    /// or with none; it starts paused unless the rate is above 0.
    ///
    /// - `handle`: the player.
    /// - `url`: the media, or null.
    fn load(handle: *anyopaque, url: ?[:0]const u8) void {
        const native = Self.nativeOf(handle);
        native.failure_length = 0;
        native.frame_width = 0;
        native.frame_height = 0;
        native.generation = Self.nextGeneration();
        const address = url orelse {
            native.act(EngineSlot.pause);
            native.has_item = false;
            return;
        };
        const allocator = std.heap.c_allocator;
        const source = Self.sourceUrl(allocator, address) catch |err| {
            log.warn("media not opened: {s}", .{@errorName(err)});
            native.has_item = true;
            native.setFailure("The media could not be opened.");
            return;
        };
        defer allocator.free(source);
        const wide_source = mod.Com.wide(allocator, source) catch |err| {
            log.warn("media not opened: {s}", .{@errorName(err)});
            native.has_item = true;
            native.setFailure("The media could not be opened.");
            return;
        };
        defer allocator.free(wide_source);
        const string = SysAllocString(wide_source) orelse return;
        defer SysFreeString(string);
        const result = mod.Com.method(*const fn (*anyopaque, [*:0]u16) callconv(.winapi) mod.HRESULT, native.engine, EngineSlot.set_source)(native.engine, string);
        native.has_item = true;
        if (result < 0) {
            native.setFailure("The media could not be opened.");
            return;
        }
        if (native.rate > 0) {
            native.setNumber(EngineSlot.set_playback_rate, native.rate);
            native.act(EngineSlot.play);
        }
    }

    /// Plays at a rate, or pauses at 0.
    ///
    /// - `handle`: the player.
    /// - `rate`: the rate; 1 is normal speed.
    fn setRate(handle: *anyopaque, rate: f32) void {
        const native = Self.nativeOf(handle);
        native.rate = rate;
        if (rate <= 0) {
            native.act(EngineSlot.pause);
            return;
        }
        native.setNumber(EngineSlot.set_default_playback_rate, rate);
        native.setNumber(EngineSlot.set_playback_rate, rate);
        native.act(EngineSlot.play);
    }

    /// Moves the playhead.
    ///
    /// - `handle`: the player.
    /// - `seconds`: where, from the item's start.
    fn seek(handle: *anyopaque, seconds: f64) void {
        Self.nativeOf(handle).setNumber(EngineSlot.set_current_time, seconds);
    }

    /// Sets the volume.
    ///
    /// - `handle`: the player.
    /// - `volume`: 0 silent to 1 full.
    fn setVolume(handle: *anyopaque, volume: f32) void {
        Self.nativeOf(handle).setNumber(EngineSlot.set_volume, std.math.clamp(volume, 0, 1));
    }

    /// Mutes or unmutes, keeping the volume.
    ///
    /// - `handle`: the player.
    /// - `muted`: whether it is muted.
    fn setMuted(handle: *anyopaque, muted: bool) void {
        const native = Self.nativeOf(handle);
        _ = mod.Com.method(*const fn (*anyopaque, i32) callconv(.winapi) mod.HRESULT, native.engine, EngineSlot.set_muted)(native.engine, @intFromBool(muted));
    }

    /// Routes the sound to one output (`IMFMediaEngineAudioEndpointId`: a
    /// Core Audio endpoint id, `MmDeviceAudioOutputs`), or to the system
    /// default when null. An output gone since it was listed, or a Windows
    /// whose engine cannot route one player's sound, leaves the default.
    ///
    /// - `handle`: the player.
    /// - `id`: the output's id, or null for the system default.
    /// - Returns: false when the output was not found or could not be set
    ///   (the system default plays), else true.
    fn setAudioOutput(handle: *anyopaque, id: ?[:0]const u8) bool {
        const native = Self.nativeOf(handle);
        const found = if (id) |wanted| mod.MmDeviceAudioOutputs.hasOutput(wanted) else true;
        if (!found) log.warn("audio output {s} not found: the system default plays", .{id.?});
        const endpoint = mod.Com.query(native.engine, &Guid.iid_audio_endpoint_id) orelse {
            log.warn("this Media Foundation cannot route one player's sound: the system default plays", .{});
            return id == null;
        };
        defer mod.Com.release(endpoint);
        const allocator = std.heap.c_allocator;
        const wide: ?[:0]u16 = if (!found) null else if (id) |wanted| mod.Com.wide(allocator, wanted) catch |err| {
            log.warn("audio output id not converted: {s}", .{@errorName(err)});
            return false;
        } else null;
        defer if (wide) |text| allocator.free(text);
        const result = mod.Com.method(*const fn (*anyopaque, ?[*:0]const u16) callconv(.winapi) mod.HRESULT, endpoint, OtherSlot.set_audio_endpoint_id)(endpoint, if (wide) |text| text.ptr else null);
        if (result < 0) {
            log.warn("audio output not set [0x{x}]: the system default plays", .{@as(u32, @bitCast(result))});
            return id == null;
        }
        return found;
    }

    /// Samples the engine's state.
    ///
    /// - `handle`: the player.
    /// - Returns: the sample; `failure` points into the player.
    fn observe(handle: *anyopaque) views.PlayerObservation {
        const native = Self.nativeOf(handle);
        if (!native.has_item) return .{ .rate = native.rate };
        const code = native.errorCode();
        if (code != 0 and native.failure_length == 0) native.setFailure(Self.describeError(code));
        if (native.failure_length > 0) {
            return .{ .status = .failed, .has_item = true, .rate = native.rate, .failure = native.failure[0..native.failure_length] };
        }
        const ready = mod.Com.method(*const fn (*anyopaque) callconv(.winapi) u16, native.engine, EngineSlot.get_ready_state)(native.engine);
        const seeking = native.flag(EngineSlot.is_seeking);
        const ended = native.flag(EngineSlot.is_ended);
        // Played to its end, the engine stops: the rate asked for drops to 0,
        // as AVPlayer's does, so the next item does not start on its own.
        if (ended) native.rate = 0;
        const paused = native.flag(EngineSlot.is_paused) or ended;
        const current = native.number(EngineSlot.get_current_time);
        const duration = native.number(EngineSlot.get_duration);
        var width: u32 = 0;
        var height: u32 = 0;
        _ = mod.Com.method(*const fn (*anyopaque, *u32, *u32) callconv(.winapi) mod.HRESULT, native.engine, EngineSlot.get_native_video_size)(native.engine, &width, &height);
        const waiting = ready < Self.have_future_data or seeking;
        return .{
            .status = if (ready >= Self.have_metadata) .readyToPlay else .unknown,
            .time_control = if (paused) .paused else if (waiting) .waitingToPlay else .playing,
            .has_item = true,
            .rate = if (paused) 0 else @floatCast(native.number(EngineSlot.get_playback_rate)),
            .current_seconds = if (std.math.isFinite(current)) current else 0,
            .duration_seconds = if (std.math.isFinite(duration) and duration > 0) duration else null,
            .buffered_seconds = native.bufferedAhead(current),
            .likely_to_keep_up = ready >= Self.have_future_data,
            .buffer_empty = ready < Self.have_future_data,
            .seeking = seeking,
            .presentation_width = @floatFromInt(width),
            .presentation_height = @floatFromInt(height),
        };
    }

    /// Lists the item's audio streams; there are no subtitle tracks.
    ///
    /// - `handle`: the player.
    /// - `allocator`: owns the list and its texts.
    /// - `kind`: which tracks.
    /// - Returns: the tracks; propagates allocation failure.
    fn tracks(handle: *anyopaque, allocator: std.mem.Allocator, kind: views.PlayerTrackKind) std.mem.Allocator.Error![]views.PlayerTrack {
        if (kind != .audio) return allocator.alloc(views.PlayerTrack, 0);
        const native = Self.nativeOf(handle);
        var list: std.ArrayList(views.PlayerTrack) = .empty;
        errdefer {
            for (list.items) |track| {
                allocator.free(track.name);
                allocator.free(track.language);
            }
            list.deinit(allocator);
        }
        const count = native.streamCount();
        var stream: u32 = 0;
        while (stream < count) : (stream += 1) {
            if (!native.isAudio(stream)) continue;
            const language = try native.streamText(allocator, stream, &Guid.language);
            errdefer allocator.free(language);
            var name = try native.streamText(allocator, stream, &Guid.stream_name);
            if (name.len == 0) {
                allocator.free(name);
                name = if (language.len > 0) try allocator.dupe(u8, language) else try allocator.print("Track {d}", .{list.items.len + 1});
            }
            errdefer allocator.free(name);
            var selected: i32 = 0;
            _ = mod.Com.method(*const fn (*anyopaque, u32, *i32) callconv(.winapi) mod.HRESULT, native.engine, EngineSlot.get_stream_selection)(native.engine, stream, &selected);
            try list.append(allocator, .{ .name = name, .language = language, .selected = selected != 0 });
        }
        return list.toOwnedSlice(allocator);
    }

    /// Selects the audio stream at `index` of the list `tracks` returns;
    /// subtitles (and turning audio off) do nothing.
    ///
    /// - `handle`: the player.
    /// - `kind`: which tracks.
    /// - `index`: the track, or null.
    fn selectTrack(handle: *anyopaque, kind: views.PlayerTrackKind, index: ?usize) void {
        if (kind != .audio) return;
        const wanted = index orelse return;
        const native = Self.nativeOf(handle);
        const count = native.streamCount();
        var audio_index: usize = 0;
        var stream: u32 = 0;
        while (stream < count) : (stream += 1) {
            if (!native.isAudio(stream)) continue;
            _ = mod.Com.method(*const fn (*anyopaque, u32, i32) callconv(.winapi) mod.HRESULT, native.engine, EngineSlot.set_stream_selection)(native.engine, stream, @intFromBool(audio_index == wanted));
            audio_index += 1;
        }
        native.act(EngineSlot.apply_stream_selections);
    }

    /// The next frame generation, unique in the process.
    ///
    /// - Returns: the generation.
    fn nextGeneration() u64 {
        last_generation += 1;
        return last_generation;
    }

    /// The WIC factory frames are copied with, made on first need.
    ///
    /// - Returns: the factory, or null when COM refused.
    fn imagingFactory() ?*anyopaque {
        if (wic_factory == null) wic_factory = mod.Com.create(&Guid.imaging_factory, &Guid.iid_imaging_factory);
        return wic_factory;
    }

    /// The text a failed item reports, for an `MF_MEDIA_ENGINE_ERR`.
    ///
    /// - `code`: the code.
    /// - Returns: the text.
    fn describeError(code: u16) []const u8 {
        return switch (code) {
            1 => "Loading the media was stopped.",
            2 => "The media could not be loaded from the network.",
            3 => "The media could not be decoded.",
            4 => "The media's format is not supported.",
            5 => "The media is encrypted.",
            else => "The media could not be played.",
        };
    }

    /// The URL the engine opens: a URL as given, a local path as a `file:` URL.
    ///
    /// - `allocator`: owns the result.
    /// - `address`: the URL or path.
    /// - Returns: the URL; propagates allocation failure.
    fn sourceUrl(allocator: std.mem.Allocator, address: []const u8) std.mem.Allocator.Error![]u8 {
        if (std.mem.find(u8, address, "://") != null) return allocator.dupe(u8, address);
        const url = try allocator.alloc(u8, "file:///".len + address.len);
        @memcpy(url[0.."file:///".len], "file:///");
        for (address, url["file:///".len..]) |character, *slot| slot.* = if (character == '\\') '/' else character;
        return url;
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
    // Nothing here does I/O to trace.
    _ = log;
}

test "media foundation player: a local path becomes a file URL, a URL stays" {
    const allocator = std.testing.allocator;
    const file = try MediaFoundationPlayer.sourceUrl(allocator, "C:\\Videos\\clip.mp4");
    defer allocator.free(file);
    try std.testing.expectEqualStrings("file:///C:/Videos/clip.mp4", file);
    const stream = try MediaFoundationPlayer.sourceUrl(allocator, "https://example.com/master.m3u8");
    defer allocator.free(stream);
    try std.testing.expectEqualStrings("https://example.com/master.m3u8", stream);
}

test "media foundation player: a missing file fails, saying why" {
    if (comptime mod.os_tag != .windows) return error.SkipZigTest;
    views.Player.setBackend(&MediaFoundationPlayer.backend);
    defer views.Player.setBackend(null);
    var player = views.Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("C:\\ziggui-no-such-file.mp4");
    if (player.nativeHandle() == null) return error.SkipZigTest; // no Media Foundation (Windows N)
    player.play();
    var observation = player.observe();
    var tries: usize = 0;
    while (observation.status != .failed and tries < 200) : (tries += 1) {
        sdl_c.SDL_Delay(10);
        observation = player.observe();
    }
    try std.testing.expectEqual(views.PlayerStatus.failed, observation.status);
    try std.testing.expect(observation.failure.len > 0);
}
