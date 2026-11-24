//! What a `FindBar`'s field, buttons and keys do.

const std = @import("std");
const log = std.log.scoped(.ziggui_find_actions);
const mod = @import("module.zig");

/// A `FindBar`'s replace row: its field and its two buttons.
pub const FindReplace = struct {
    const Self = @This();

    /// The replacement's text; app-owned. Enter in it replaces.
    field: *mod.TextFieldState,

    /// Replace: the current match, then on to the next.
    on_replace: mod.Callback,

    /// Replace All.
    on_replace_all: mod.Callback,
};

/// A `FindBar`'s actions, and the keys that reach them while it shows:
/// Enter in the field submits, Shift-Enter in the field and ⌘⇧G go to the
/// previous match, ⌘G to the next, Esc closes the bar.
pub const FindActions = struct {
    const Self = @This();

    /// Enter in the field: runs the find (or goes to the next match).
    on_submit: mod.Callback,
    /// The next match.
    on_next: mod.Callback,
    /// The previous match.
    on_previous: mod.Callback,
    /// Closes the bar.
    on_done: mod.Callback,

    /// The search's options, which the bar's Aa (match case) and ab| (whole
    /// word) toggles flip; null for a bar without them.
    search_options: ?*mod.TextSearchOptions = null,

    /// The replace row under the find row; null for none.
    replace: ?FindReplace = null,

    /// Handles a key meant for the bar: call it from the app's key handler
    /// while the bar shows, before a focused field takes the key.
    ///
    /// ⌘G and ⌘⇧G are the bar's wherever the keyboard is, as a native find
    /// bar's are. Shift-Enter is the bar's only while its own field has the
    /// keyboard, so it still types a newline in the document. Esc closes the
    /// bar while its field has the keyboard or no field does, as a browser's
    /// find bar closes on Esc from the page it searches; while another field
    /// holds the keyboard, or a text field's context menu is open, Esc is
    /// theirs. Plain Enter is left to the field's submit.
    ///
    /// - `self`: the actions.
    /// - `key`: the key.
    /// - `field`: the bar's own field, the one passed to `FindBar`.
    /// - Returns: whether the key was the bar's (and was handled).
    pub fn handleKey(self: *const Self, key: mod.Key, field: *const mod.TextFieldState) bool {
        const focused = mod.Focus.shared().focused();
        const in_field = focused == field;
        if (key.isNamed(.escape)) {
            // The loop lets Esc close an open context menu only after the app's key handler declines it.
            if (mod.TextContextMenu.shared().isOpen()) return false;
            if (!in_field and focused != null) return false;
            self.on_done.call();
            return true;
        }
        if (key.isNamed(.enter) and key.shift) {
            if (!in_field) return false;
            self.on_previous.call();
            return true;
        }
        if (key.command and !key.alt and (key.char == 'g' or key.char == 'G')) {
            if (key.shift or key.char == 'G') self.on_previous.call() else self.on_next.call();
            return true;
        }
        return false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// Records which of a `FindActions`' actions ran, for the tests.
const FindProbe = struct {
    const Self = @This();

    /// The last action called.
    last: []const u8 = "",

    /// The actions, each recording itself in the probe.
    ///
    /// - `self`: the probe.
    /// - Returns: the actions.
    fn actions(self: *Self) FindActions {
        return .{
            .on_submit = mod.Callback.init(Self, self, Self.next),
            .on_next = mod.Callback.init(Self, self, Self.next),
            .on_previous = mod.Callback.init(Self, self, Self.previous),
            .on_done = mod.Callback.init(Self, self, Self.done),
        };
    }

    /// Records a next.
    ///
    /// - `self`: the probe.
    fn next(self: *Self) void {
        self.last = "next";
    }

    /// Records a previous.
    ///
    /// - `self`: the probe.
    fn previous(self: *Self) void {
        self.last = "previous";
    }

    /// Records a done.
    ///
    /// - `self`: the probe.
    fn done(self: *Self) void {
        self.last = "done";
    }
};

test "find actions take Esc, Shift-Enter and Command-G in their field, and leave other keys" {
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear();
    var probe: FindProbe = .{};
    const actions = probe.actions();
    mod.Focus.shared().set(&field);

    try std.testing.expect(actions.handleKey(.{ .name = .escape }, &field));
    try std.testing.expectEqualStrings("done", probe.last);
    try std.testing.expect(actions.handleKey(.{ .name = .enter, .shift = true }, &field));
    try std.testing.expectEqualStrings("previous", probe.last);
    try std.testing.expect(actions.handleKey(.{ .char = 'g', .command = true }, &field));
    try std.testing.expectEqualStrings("next", probe.last);
    try std.testing.expect(actions.handleKey(.{ .char = 'g', .command = true, .shift = true }, &field));
    try std.testing.expectEqualStrings("previous", probe.last);

    // Plain Enter is the field's submit; typing is the field's.
    probe.last = "";
    try std.testing.expect(!actions.handleKey(.{ .name = .enter }, &field));
    try std.testing.expect(!actions.handleKey(.{ .char = 'g' }, &field));
    try std.testing.expectEqualStrings("", probe.last);
}

test "find actions leave Esc and Shift-Enter to another focused field, and take Esc with none" {
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    var document = mod.TextFieldState.init(std.testing.allocator);
    defer document.deinit();
    defer mod.Focus.shared().clear();
    var probe: FindProbe = .{};
    const actions = probe.actions();

    // The document has the keyboard: Shift-Enter types its newline, Esc is its own.
    mod.Focus.shared().set(&document);
    try std.testing.expect(!actions.handleKey(.{ .name = .enter, .shift = true }, &field));
    try std.testing.expect(!actions.handleKey(.{ .name = .escape }, &field));
    try std.testing.expectEqualStrings("", probe.last);
    // ⌘G still finds from the document.
    try std.testing.expect(actions.handleKey(.{ .char = 'g', .command = true }, &field));
    try std.testing.expectEqualStrings("next", probe.last);

    // No field has the keyboard: Esc closes the bar; Shift-Enter is nobody's.
    probe.last = "";
    mod.Focus.shared().clear();
    try std.testing.expect(!actions.handleKey(.{ .name = .enter, .shift = true }, &field));
    try std.testing.expect(actions.handleKey(.{ .name = .escape }, &field));
    try std.testing.expectEqualStrings("done", probe.last);
}

test "find actions leave Esc to an open text context menu" {
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear();
    defer mod.TextContextMenu.shared().close();
    var probe: FindProbe = .{};
    const actions = probe.actions();

    mod.TextContextMenu.shared().open(&field, .{ .x = 10, .y = 10 });
    try std.testing.expect(!actions.handleKey(.{ .name = .escape }, &field));
    try std.testing.expectEqualStrings("", probe.last);
    // Closed, Esc closes the bar again.
    mod.TextContextMenu.shared().close();
    try std.testing.expect(actions.handleKey(.{ .name = .escape }, &field));
    try std.testing.expectEqualStrings("done", probe.last);
}
