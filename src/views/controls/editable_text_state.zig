//! What an `EditableText` keeps between frames: its text, whether it is being
//! edited, and the click that will start an edit.

const std = @import("std");
const log = std.log.scoped(.ziggui_editable_text_state);
const mod = @import("module.zig");

/// The app-owned state of an `EditableText`, a label renamed in place as
/// Finder renames a file: a click on it while it is selected, slower than a
/// double click, arms an edit that starts `edit_delay_ms` later if no second
/// click made it a double click and the pointer is still over it. Editing, it
/// is a field with all its text selected: Enter or a press elsewhere commits
/// (`on_commit`, only for a changed, non-empty text; empty puts the old text
/// back), and Esc cancels, through `keyDown`, which the app's key handler
/// calls first (the event loop would otherwise only drop the keyboard, as a
/// press elsewhere does). Its field's address must stay put while it edits.
pub const EditableTextState = struct {
    const Self = @This();

    /// How long after the arming click the edit starts, in milliseconds: time
    /// for a second click to make it a double click instead.
    pub const edit_delay_ms: u64 = 300;

    /// Owns the text kept for a cancel.
    allocator: std.mem.Allocator,

    /// The text, and the field that edits it.
    field: mod.TextFieldState,

    /// The text as it was when the edit began, for Esc or an empty commit.
    original: std.ArrayList(u8) = .empty,

    /// Whether the label is being edited.
    editing: bool = false,

    /// When the arming click came (`FrameClock` time), or null with none waiting.
    armed_at: ?u64 = null,

    /// Whether the pointer is over the label (its `onHover`).
    hovered: bool = false,

    /// Whether the last frame drew it selected: a click arms an edit only then.
    selected: bool = false,

    /// What a click on the label also calls (a row's select), as the last
    /// frame passed it. Its context may live in that frame's build arena, so
    /// it is called only before the next frame begins (a tap).
    on_tap: ?mod.Callback = null,

    /// What a commit of a changed text calls, as the last frame passed it.
    /// Like `on_tap`, called only before the next frame begins (Enter), or
    /// after `update` has stored the building frame's (a press elsewhere).
    on_commit: ?mod.Callback = null,

    /// Constructs the state showing `text`.
    ///
    /// - `allocator`: owns the text and its field's buffer; must outlive the state.
    /// - `initial`: the text shown, copied.
    /// - Returns: the state; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator, initial: []const u8) std.mem.Allocator.Error!Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var self = Self{ .allocator = allocator, .field = mod.TextFieldState.init(allocator) };
        errdefer self.field.deinit();
        try self.field.setText(initial);
        return self;
    }

    /// Releases the text; the field leaves the focus as it goes.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        self.original.deinit(self.allocator);
        self.field.deinit();
    }

    /// The text: the committed one, or what is typed while editing.
    ///
    /// - `self`: the state.
    /// - Returns: the text, borrowed until the next change.
    pub fn text(self: *const Self) []const u8 {
        return self.field.text();
    }

    /// Replaces the text from code, ending an edit without a commit.
    ///
    /// - `self`: the state.
    /// - `string`: the new text, copied.
    /// - Returns: nothing; propagates allocation failure.
    pub fn setText(self: *Self, string: []const u8) std.mem.Allocator.Error!void {
        self.finish();
        try self.field.setText(string);
    }

    /// Starts editing now: the field takes the keyboard with all its text selected.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; propagates allocation failure.
    pub fn beginEditing(self: *Self) std.mem.Allocator.Error!void {
        self.original.clearRetainingCapacity();
        try self.original.appendSlice(self.allocator, self.field.text());
        self.editing = true;
        self.armed_at = null;
        mod.Focus.shared().set(&self.field);
        self.field.selectAll();
    }

    /// Ends an edit, keeping the text typed (Enter, a press elsewhere): an
    /// empty text puts the old one back, and a changed one calls `on_commit`.
    ///
    /// - `self`: the state.
    pub fn commit(self: *Self) void {
        if (!self.editing) return;
        self.finish();
        if (self.field.text().len == 0) {
            self.restore();
            return;
        }
        if (std.mem.eql(u8, self.field.text(), self.original.items)) return;
        if (self.on_commit) |callback| callback.call();
    }

    /// Ends an edit, putting the old text back (Esc).
    ///
    /// - `self`: the state.
    pub fn cancel(self: *Self) void {
        if (!self.editing) return;
        self.finish();
        self.restore();
    }

    /// Takes Esc while the field edits, to cancel; the app's key handler
    /// calls it before ziggui handles the key.
    ///
    /// - `self`: the state.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when it took the key.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (!self.editing or keycode != mod.SdlKey.escape or modifiers & mod.SdlKey.modifier_mask != 0) return false;
        if (mod.Focus.shared().focused() != &self.field) return false;
        self.cancel();
        return true;
    }

    /// A click on the label (its tap): calls `on_tap`, then arms an edit when
    /// the label was already selected, unless the click completes a double click.
    ///
    /// - `self`: the state.
    pub fn press(self: *Self) void {
        if (self.on_tap) |callback| callback.call();
        if (mod.PointerInput.shared().isDoubleClick()) {
            self.armed_at = null;
            return;
        }
        if (self.selected) self.armed_at = mod.FrameClock.shared().time();
    }

    /// Notes the pointer entering or leaving the label (its `onHover`).
    ///
    /// - `context`: the state.
    /// - `inside`: whether the pointer is over it.
    pub fn hoverChanged(context: ?*anyopaque, inside: bool) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.hovered = inside;
    }

    /// Brings the state up to the frame being built: notes what the view was
    /// given, commits an edit whose field lost the keyboard (a press
    /// elsewhere; `on_commit` then runs as the view builds), and starts an
    /// armed edit once its delay has passed with the pointer still over the
    /// label, asking for a frame then until it has.
    ///
    /// - `self`: the state.
    /// - `selected`: whether the label draws selected.
    /// - `on_tap`: what a click also calls.
    /// - `on_commit`: what a commit of a changed text calls.
    /// - `now`: the frame's time, in milliseconds.
    /// - Returns: nothing; propagates allocation failure.
    pub fn update(self: *Self, selected: bool, on_tap: ?mod.Callback, on_commit: mod.Callback, now: u64) std.mem.Allocator.Error!void {
        self.selected = selected;
        self.on_tap = on_tap;
        self.on_commit = on_commit;
        if (self.editing and mod.Focus.shared().focused() != &self.field) self.commit();
        const armed_at = self.armed_at orelse return;
        if (!selected) {
            self.armed_at = null;
            return;
        }
        const due = armed_at + edit_delay_ms;
        if (now < due) {
            mod.FrameClock.shared().requestFrameAt(due);
            return;
        }
        self.armed_at = null;
        if (self.hovered) try self.beginEditing();
    }

    /// Leaves editing and the keyboard, and drops a waiting click.
    ///
    /// - `self`: the state.
    fn finish(self: *Self) void {
        self.editing = false;
        self.armed_at = null;
        if (mod.Focus.shared().focused() == &self.field) mod.Focus.shared().clear();
    }

    /// Puts back the text the edit began with.
    ///
    /// - `self`: the state.
    fn restore(self: *Self) void {
        self.field.setText(self.original.items) catch |err| log.warn("text not restored: {s}", .{@errorName(err)});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(EditableTextState);
}

test "a click on a selected label edits it after the delay, unless a double click or a move away came first" {
    const Probe = struct {
        const Self = @This();

        /// How many commits came.
        var commits: u32 = 0;

        /// Counts a commit.
        fn committed() void {
            Self.commits += 1;
        }
    };
    const clock = mod.FrameClock.shared();
    defer clock.setTime(0);
    var state = try EditableTextState.init(std.testing.allocator, "notes.txt");
    defer state.deinit();
    defer mod.Focus.shared().clear();
    const on_commit = mod.Callback.action(Probe.committed);

    // Not selected: a click arms nothing.
    clock.setTime(1000);
    try state.update(false, null, on_commit, 1000);
    state.press();
    try std.testing.expect(state.armed_at == null);

    // Selected and hovered: armed, then editing once the delay has passed.
    try state.update(true, null, on_commit, 1000);
    EditableTextState.hoverChanged(&state, true);
    state.press();
    try state.update(true, null, on_commit, 1000 + EditableTextState.edit_delay_ms - 1);
    try std.testing.expect(!state.editing);
    try state.update(true, null, on_commit, 1000 + EditableTextState.edit_delay_ms);
    try std.testing.expect(state.editing);
    try std.testing.expectEqual(@as(?*mod.TextFieldState, &state.field), mod.Focus.shared().focused());
    try std.testing.expectEqualStrings("notes.txt", state.field.selectedText());

    // Esc cancels: the old text comes back and nothing is committed.
    try state.field.setText("draft");
    try std.testing.expect(state.keyDown(mod.SdlKey.escape, 0));
    try std.testing.expect(!state.editing);
    try std.testing.expectEqualStrings("notes.txt", state.text());
    try std.testing.expectEqual(@as(u32, 0), Probe.commits);

    // Enter (or a press elsewhere) commits a changed text, once.
    try state.beginEditing();
    try state.field.setText("plans.txt");
    state.commit();
    try std.testing.expectEqualStrings("plans.txt", state.text());
    try std.testing.expectEqual(@as(u32, 1), Probe.commits);

    // Losing the keyboard commits too; an empty text puts the old one back.
    try state.beginEditing();
    try state.field.setText("");
    mod.Focus.shared().clear();
    try state.update(true, null, on_commit, 2000);
    try std.testing.expect(!state.editing);
    try std.testing.expectEqualStrings("plans.txt", state.text());
    try std.testing.expectEqual(@as(u32, 1), Probe.commits);

    // The pointer gone before the delay: no edit.
    clock.setTime(3000);
    state.press();
    EditableTextState.hoverChanged(&state, false);
    try state.update(true, null, on_commit, 3000 + EditableTextState.edit_delay_ms);
    try std.testing.expect(!state.editing);
}
