//! Holds a window's place and its dragged dividers for an app to save and
//! reopen as the user left them.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_memory);
const mod = @import("module.zig");

/// Holds a window's place and its dragged dividers for the app to save.
///
/// The app keeps the values in its own settings (a `?WindowPlace`, and a
/// struct of `?f32`, one per `SplitState`, null for a divider never dragged)
/// and this beside them, unsaved. Each frame it notes the window
/// (`noteWindow`) and the dividers (`notePanes`), then saves when `due` says
/// they have rested `settle_ms`, so a drag writes once, not once a frame;
/// `due(null)` at a quit saves at once. While `settling`, the app keeps the
/// loop waking (`App.setBusyInterval`), or `due` is not asked until the
/// next event. At launch `restore` puts the dividers back and
/// `AppConfig.restoring` the window.
pub const WindowMemory = struct {
    const Self = @This();

    /// How long the window and the dividers rest before `due` says to save.
    pub const settle_ms: u64 = 500;

    /// When a note last changed the values, until `due` hands them over; 0
    /// for a change noted with no clock.
    moved_ms: ?u64 = null,

    /// Notes where the window is. With nothing saved yet (a first launch),
    /// the first place noted is adopted without counting as a move: the
    /// window is where the app opens it anyway, so nothing is written until
    /// the user moves or resizes it.
    ///
    /// - `self`: the memory.
    /// - `saved`: the app's saved place; set to `place` when it differs.
    /// - `place`: where the window is now (`App.windowPlace`); null with no window, which changes nothing.
    /// - `now`: `FrameClock.shared().time()`; null when there is no clock (a quit).
    pub fn noteWindow(self: *Self, saved: *?mod.WindowPlace, place: ?mod.WindowPlace, now: ?u64) void {
        const current = place orelse return;
        const old = saved.* orelse {
            saved.* = current;
            return;
        };
        if (std.meta.eql(old, current)) return;
        saved.* = current;
        self.moved_ms = now orelse 0;
    }

    /// Notes where each divider is: a dragged one's size goes into its
    /// field of `panes`; one never dragged keeps what `panes` holds.
    ///
    /// - `self`: the memory.
    /// - `panes`: a pointer to the app's saved sizes, a struct of `?f32`.
    /// - `splits`: a struct of `*SplitState` (or `*const`) with the same field names as `panes`.
    /// - `now`: `FrameClock.shared().time()`; null when there is no clock (a quit).
    pub fn notePanes(self: *Self, panes: anytype, splits: anytype, now: ?u64) void {
        inline for (@typeInfo(@TypeOf(panes.*)).@"struct".field_names) |name| {
            const split = @field(splits, name);
            if (split.size >= 0) {
                const old = @field(panes.*, name);
                if (old == null or old.? != split.size) {
                    @field(panes.*, name) = split.size;
                    self.moved_ms = now orelse 0;
                }
            }
        }
    }

    /// Reports whether what moved is to be saved now: it has rested
    /// `settle_ms`, or `now` is null. True once per change.
    ///
    /// - `self`: the memory.
    /// - `now`: `FrameClock.shared().time()`; null to save at once (a quit).
    /// - Returns: true when the app should save its settings.
    pub fn due(self: *Self, now: ?u64) bool {
        const since = self.moved_ms orelse return false;
        if (now) |time| if (time -| since < settle_ms) return false;
        self.moved_ms = null;
        return true;
    }

    /// Reports whether a change waits for `due`: the app keeps waking the
    /// loop until it is saved.
    ///
    /// - `self`: the memory.
    /// - Returns: true while one waits.
    pub fn settling(self: *const Self) bool {
        return self.moved_ms != null;
    }

    /// Puts each divider where `panes` says it was dragged; a null field
    /// leaves its divider at its default. Layout clamps a size that no
    /// longer fits.
    ///
    /// - `panes`: the app's saved sizes, a struct of `?f32`.
    /// - `splits`: a struct of `*SplitState` with the same field names as `panes`.
    pub fn restore(panes: anytype, splits: anytype) void {
        inline for (@typeInfo(@TypeOf(panes)).@"struct".field_names) |name| {
            // A size read from a file may be anything: only a real length is kept.
            if (@field(panes, name)) |size| if (std.math.isFinite(size) and size >= 0) {
                @field(splits, name).size = size;
            };
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Values only: nothing here does I/O to trace.
    _ = log;
}

test "window memory: a moved window and a dragged divider are due once they rest, once" {
    var memory: WindowMemory = .{};
    var saved: ?mod.WindowPlace = null;
    var panes: struct { sidebar: ?f32 = null, detail: ?f32 = 200 } = .{};
    var sidebar: mod.SplitState = .{};
    var detail: mod.SplitState = .{};
    const place: mod.WindowPlace = .{ .x = 40, .y = 60, .width = 1500, .height = 900 };

    // A first launch: where the window opens is adopted, not a move.
    memory.noteWindow(&saved, .{ .x = 0, .y = 0, .width = 1200, .height = 800 }, 500);
    try std.testing.expect(saved != null);
    try std.testing.expect(!memory.settling());
    try std.testing.expect(!memory.due(null));

    memory.noteWindow(&saved, place, 1000);
    memory.notePanes(&panes, .{ .sidebar = &sidebar, .detail = &detail }, 1000);
    try std.testing.expectEqual(place, saved.?);
    // Never dragged: the saved size stays.
    try std.testing.expectEqual(@as(?f32, null), panes.sidebar);
    try std.testing.expectEqual(@as(?f32, 200), panes.detail);
    try std.testing.expect(memory.settling());
    try std.testing.expect(!memory.due(1000 + WindowMemory.settle_ms - 1));

    // Still moving: the rest starts again.
    sidebar.size = 300;
    memory.notePanes(&panes, .{ .sidebar = &sidebar, .detail = &detail }, 1200);
    try std.testing.expectEqual(@as(?f32, 300), panes.sidebar);
    try std.testing.expect(!memory.due(1000 + WindowMemory.settle_ms));
    try std.testing.expect(memory.due(1200 + WindowMemory.settle_ms));
    try std.testing.expect(!memory.settling());
    try std.testing.expect(!memory.due(9000));

    // Nothing moved: nothing due.
    memory.noteWindow(&saved, place, 9000);
    memory.notePanes(&panes, .{ .sidebar = &sidebar, .detail = &detail }, 9000);
    memory.noteWindow(&saved, null, 9000);
    try std.testing.expect(!memory.settling());

    // Maximized, then a quit: due at once.
    memory.noteWindow(&saved, .{ .x = 40, .y = 60, .width = 1500, .height = 900, .maximized = true }, 9100);
    try std.testing.expect(memory.due(null));
    try std.testing.expect(saved.?.maximized);
}

test "window memory: restore puts back the dragged dividers and nothing else" {
    var sidebar: mod.SplitState = .{};
    var detail: mod.SplitState = .{};
    var other: mod.SplitState = .{};
    // Read from a file at run time, as an app's are.
    var panes: struct { sidebar: ?f32 = 300, detail: ?f32 = null, other: ?f32 = std.math.nan(f32) } = .{};
    _ = &panes;
    WindowMemory.restore(panes, .{ .sidebar = &sidebar, .detail = &detail, .other = &other });
    try std.testing.expectEqual(@as(f32, 300), sidebar.size);
    try std.testing.expect(detail.size < 0);
    try std.testing.expect(other.size < 0);
}
