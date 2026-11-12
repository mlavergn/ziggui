//! The keyboard focus: the text field keys go to, and its caret's blink.

const std = @import("std");
const log = std.log.scoped(.ziggui_focus);
const mod = @import("module.zig");

/// The focused text field, for routing keyboard events, and the caret's blink
/// phase. Managed by the app's event loop (and taps on fields).
pub const Focus = struct {
    const Self = @This();

    /// The focused field, if any.
    focused_field: ?*mod.TextFieldState = null,

    /// The caret's blink phase. The event loop flips it while a field is focused
    /// and holds it on while typing; tests and headless renders keep it on.
    caret_on: bool = true,

    /// The current thread's focus.
    threadlocal var shared_focus: Self = .{};

    /// The current thread's focus.
    ///
    /// - Returns: the shared focus.
    pub fn shared() *Self {
        return &shared_focus;
    }

    /// The focused text field, if any.
    ///
    /// - `self`: the focus.
    /// - Returns: the field, or null.
    pub fn focused(self: *const Self) ?*mod.TextFieldState {
        return self.focused_field;
    }

    /// Focuses a text field, unfocusing the one before it.
    ///
    /// - `self`: the focus.
    /// - `field`: the field.
    pub fn set(self: *Self, field: *mod.TextFieldState) void {
        if (self.focused_field) |previous| {
            if (previous != field) previous.focused = false;
        }
        field.focused = true;
        self.focused_field = field;
    }

    /// Clears the keyboard focus.
    ///
    /// - `self`: the focus.
    pub fn clear(self: *Self) void {
        if (self.focused_field) |previous| previous.focused = false;
        self.focused_field = null;
    }

    /// Drops every reference to `field`: it is no longer focused. Its
    /// `TextFieldState.deinit` calls this, so a freed field is never written to.
    ///
    /// - `self`: the focus.
    /// - `field`: the field going away.
    pub fn forget(self: *Self, field: *const mod.TextFieldState) void {
        if (self.focused_field == field) self.focused_field = null;
    }

    /// Submits the focused text field: fires its `.onSubmit` callback if it has
    /// one. A no-op when nothing is focused or no callback was set. The app
    /// calls this on Enter.
    ///
    /// - `self`: the focus.
    pub fn submit(self: *const Self) void {
        if (self.focused_field) |field| {
            if (field.on_submit) |callback| callback.call();
        }
    }

    /// Sets the caret's blink phase.
    ///
    /// - `self`: the focus.
    /// - `on`: whether the caret shows.
    pub fn setCaretVisible(self: *Self, on: bool) void {
        self.caret_on = on;
    }

    /// Whether the caret shows this frame.
    ///
    /// - `self`: the focus.
    /// - Returns: the blink phase.
    pub fn caretVisible(self: *const Self) bool {
        return self.caret_on;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
