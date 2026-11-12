//! SDL3's native open dialogs: NSOpenPanel / IFileDialog / XDG portal.
//! Asynchronous: the OS panel runs alongside the loop and SDL invokes the
//! callback later, possibly on another thread, so the callback only copies
//! the path to the heap and pushes a user event to wake
//! `SDL_WaitEvent`; the app polls `FileDialog.takeResult` from its per-frame
//! hook or body. One dialog at a time.

const std = @import("std");
const log = std.log.scoped(.ziggui_file_dialog);
const mod = @import("module.zig");
const sdl_c = @import("sdl_c");

/// A dialog file filter, e.g. `.{ .name = "WAV audio", .pattern = "wav" }`.
/// `pattern` is a semicolon-separated extension list without dots ("wav;mp3").
pub const FileFilter = sdl_c.SDL_DialogFileFilter;

/// What a finished dialog returned.
pub const FileDialogResult = union(enum) {
    const Self = @This();

    /// No dialog finished since the last take (still open, or none shown).
    none,
    /// The user canceled (or the dialog failed).
    canceled,
    /// The user picked a file; caller owns the path.
    picked: []u8,
};

/// The open dialog and its pending result. One per process (`shared`).
pub const FileDialog = struct {
    const Self = @This();

    /// A dialog is showing (main thread only).
    open: bool = false,

    /// The dialog finished; set from SDL's callback thread.
    done: std.atomic.Value(bool) = .init(false),

    /// The picked path, copied whole from `path_allocator`; null when
    /// canceled. Guarded by `done`.
    path: ?[]u8 = null,

    /// Holds `path` between SDL's callback thread and `takeResult` on the main
    /// thread, so it must be thread-safe.
    const path_allocator = std.heap.page_allocator;

    /// The process's dialog state.
    var shared_dialog: Self = .{};

    /// The process's dialog state.
    ///
    /// - Returns: the shared file dialog.
    pub fn shared() *Self {
        return &shared_dialog;
    }

    /// Shows the native "Open File" dialog (single file). `filters` must point
    /// at memory that outlives the dialog (a global/comptime slice is the easy
    /// way): SDL holds the pointer until the user dismisses the panel. Poll
    /// `takeResult` each frame for the outcome. Call from the main thread.
    ///
    /// - `self`: the dialog state.
    /// - `filters`: the file filters, possibly empty.
    /// - `default_location`: the folder to open in, or null.
    /// - Returns: false if a dialog is already open.
    pub fn openFile(self: *Self, filters: []const FileFilter, default_location: ?[*:0]const u8) bool {
        if (self.open) return false;
        self.open = true;
        self.done.store(false, .release);
        sdl_c.SDL_ShowOpenFileDialog(
            Self.finished,
            null,
            mod.App.shared().window,
            if (filters.len > 0) filters.ptr else null,
            @intCast(filters.len),
            default_location orelse null,
            false, // allow_many
        );
        return true;
    }

    /// Shows the native "Open Folder" dialog (single folder). Shares the result
    /// plumbing of `openFile`: poll `takeResult` each frame for the chosen
    /// directory path. Call from the main thread.
    ///
    /// - `self`: the dialog state.
    /// - `default_location`: the folder to open in, or null.
    /// - Returns: false if a dialog is already open.
    pub fn openFolder(self: *Self, default_location: ?[*:0]const u8) bool {
        if (self.open) return false;
        self.open = true;
        self.done.store(false, .release);
        sdl_c.SDL_ShowOpenFolderDialog(
            Self.finished,
            null,
            mod.App.shared().window,
            default_location orelse null,
            false, // allow_many
        );
        return true;
    }

    /// Reports whether a dialog is showing (its result not yet taken).
    ///
    /// - `self`: the dialog state.
    /// - Returns: true while one is open.
    pub fn isOpen(self: *const Self) bool {
        return self.open;
    }

    /// Collects the finished dialog's outcome, once. Call from the main thread.
    ///
    /// - `self`: the dialog state.
    /// - `allocator`: owns a picked path's copy.
    /// - Returns: `.none` while the dialog is still up (or when none was shown);
    ///   `.picked` hands the caller an allocator-owned copy of the chosen path.
    pub fn takeResult(self: *Self, allocator: std.mem.Allocator) FileDialogResult {
        if (!self.open) return .none;
        if (!self.done.load(.acquire)) return .none;
        self.open = false;
        const path = self.path orelse return .canceled;
        self.path = null;
        defer Self.path_allocator.free(path);
        const copy = allocator.dupe(u8, path) catch {
            log.err("picked path dropped: no memory to copy its {d} bytes", .{path.len});
            return .canceled;
        };
        return .{ .picked = copy };
    }

    /// SDL's dialog callback: records the picked path and wakes the loop.
    fn finished(userdata: ?*anyopaque, filelist: [*c]const [*c]const u8, filter: c_int) callconv(.c) void {
        _ = userdata;
        _ = filter;
        const picked: ?[]const u8 = if (filelist != null and filelist[0] != null) std.mem.span(filelist[0]) else null;
        Self.shared().record(picked);
        // Wake the (possibly blocked) event loop so the app polls the result.
        var event = std.mem.zeroes(sdl_c.SDL_Event);
        event.type = sdl_c.SDL_EVENT_USER;
        _ = sdl_c.SDL_PushEvent(&event);
    }

    /// Records a finished dialog's outcome for `takeResult`: a whole copy of
    /// the picked path (never a cut one, which would name another file), or a
    /// cancel. Safe on SDL's callback thread: `done` publishes the copy.
    ///
    /// - `self`: the dialog state.
    /// - `picked`: the chosen path, or null when canceled.
    fn record(self: *Self, picked: ?[]const u8) void {
        self.path = null;
        if (picked) |path| {
            self.path = Self.path_allocator.dupe(u8, path) catch blk: {
                log.err("picked path reported as canceled: no memory to copy its {d} bytes", .{path.len});
                break :blk null;
            };
        }
        self.done.store(true, .release);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(FileDialog);
    // Nothing here does I/O to trace.
    _ = log;
}

test "file dialog: a path longer than any fixed buffer is handed over whole" {
    const allocator = std.testing.allocator;
    var dialog = FileDialog{ .open = true };
    const long_path = try allocator.alloc(u8, 9000);
    defer allocator.free(long_path);
    @memset(long_path, 'a');
    long_path[0] = '/';
    long_path[long_path.len - 1] = 'z';
    dialog.record(long_path);
    const result = dialog.takeResult(allocator);
    try std.testing.expect(result == .picked);
    defer allocator.free(result.picked);
    try std.testing.expectEqualStrings(long_path, result.picked);
    try std.testing.expect(dialog.takeResult(allocator) == .none);
}

test "file dialog: a cancel is reported once" {
    const allocator = std.testing.allocator;
    var dialog = FileDialog{ .open = true };
    try std.testing.expect(dialog.takeResult(allocator) == .none);
    dialog.record(null);
    try std.testing.expect(dialog.takeResult(allocator) == .canceled);
    try std.testing.expect(dialog.takeResult(allocator) == .none);
}
