//! The keyboard focus: the text field keys go to, and its caret's blink.

const std = @import("std");
const log = std.log.scoped(.ziggui_focus);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A text field and where it was drawn, for `Focus.advance`'s reading order.
const FieldPlace = struct {
    const Self = @This();

    /// The field.
    field: *mod.TextFieldState,
    /// Where it was drawn.
    rect: renderer.Rect,

    /// Whether one field reads before another: on the same row (their tops
    /// within half the shorter's height) the leading one, else the higher.
    ///
    /// - `context`: none.
    /// - `first`: one field.
    /// - `second`: the other.
    /// - Returns: true when `first` comes first.
    fn readsBefore(context: void, first: Self, second: Self) bool {
        _ = context;
        const same_row = @abs(first.rect.y - second.rect.y) < @min(first.rect.height, second.rect.height) / 2;
        return if (same_row) first.rect.x < second.rect.x else first.rect.y < second.rect.y;
    }
};

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

    /// Moves the focus to the next text field, or the previous one, wrapping,
    /// as Tab and ⇧Tab do in SwiftUI on macOS (AppKit's key-view loop): in
    /// reading order by where the fields sit, top to bottom and, along a row,
    /// leading to trailing; its text selected, so typing replaces it. Only text
    /// fields take part (SwiftUI's default, without full keyboard access; a
    /// `TextEditor` takes Tab itself, to indent), and only those drawn after
    /// the last overlay's scrim when one is up, so a sheet's or an alert's
    /// fields cycle among themselves and never reach the window under it. With
    /// nothing focused, Tab goes to the first field and ⇧Tab to the last.
    ///
    /// - `self`: the focus.
    /// - `regions`: the frame's hit regions, in drawing order.
    /// - `backward`: ⇧Tab: the previous field rather than the next.
    /// - Returns: true when a field took the focus; false with none to take it.
    pub fn advance(self: *Self, regions: []const mod.HitRegion, backward: bool) bool {
        // A scrim covers everything drawn before it.
        var start: usize = 0;
        for (regions, 0..) |region, index| {
            if (region.action == .dismiss) start = index + 1;
        }
        var places_buffer: [64]FieldPlace = undefined;
        var count: usize = 0;
        for (regions[start..]) |region| {
            if (region.disabled) continue;
            const field = switch (region.action) {
                .focus => |field| field,
                else => continue,
            };
            // A field with two regions takes one place, its first.
            if (Self.placeOf(places_buffer[0..count], field) != null) continue;
            if (count == places_buffer.len) break;
            places_buffer[count] = .{ .field = field, .rect = region.rect };
            count += 1;
        }
        if (count == 0) return false;
        const places = places_buffer[0..count];
        // Few fields, and a row test that is not quite an order: insertion sort keeps it sane.
        std.sort.insertion(FieldPlace, places, {}, FieldPlace.readsBefore);
        const at = if (self.focused_field) |current| Self.placeOf(places, current) else null;
        const next = if (at) |index|
            (if (backward) (index + count - 1) % count else (index + 1) % count)
        else if (backward) count - 1 else 0;
        self.set(places[next].field);
        places[next].field.selectAll();
        return true;
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

    /// Where a field is among places, if it is there.
    ///
    /// - `places`: the places.
    /// - `field`: the field.
    /// - Returns: its index, or null.
    fn placeOf(places: []const FieldPlace, field: *const mod.TextFieldState) ?usize {
        for (places, 0..) |place, index| {
            if (place.field == field) return index;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "focus: Tab follows reading order within a sheet, never the window under its scrim" {
    var behind = mod.TextFieldState.init(std.testing.allocator);
    defer behind.deinit();
    var name = mod.TextFieldState.init(std.testing.allocator);
    defer name.deinit();
    var city = mod.TextFieldState.init(std.testing.allocator);
    defer city.deinit();
    var zip = mod.TextFieldState.init(std.testing.allocator);
    defer zip.deinit();
    try zip.setText("old");
    var shown: renderer.State(bool) = .init(std.testing.allocator, true);
    defer shown.deinit();
    // Drawn out of order: the second row's trailing field first, then the top row's, then the second row's leading one.
    const regions = [_]mod.HitRegion{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 20 }, .action = .{ .focus = &behind }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 400, .height = 400 }, .action = .{ .dismiss = shown.binding() }, .disabled = false },
        .{ .rect = .{ .x = 160, .y = 40, .width = 80, .height = 20 }, .action = .{ .focus = &zip }, .disabled = false },
        .{ .rect = .{ .x = 10, .y = 10, .width = 230, .height = 20 }, .action = .{ .focus = &name }, .disabled = false },
        .{ .rect = .{ .x = 10, .y = 41, .width = 140, .height = 20 }, .action = .{ .focus = &city }, .disabled = false },
    };
    const focus = Focus.shared();
    defer focus.clear();
    // Nothing focused: the first in reading order.
    try std.testing.expect(focus.advance(&regions, false));
    try std.testing.expectEqual(&name, focus.focused().?);
    try std.testing.expect(focus.advance(&regions, false));
    try std.testing.expectEqual(&city, focus.focused().?);
    try std.testing.expect(focus.advance(&regions, false));
    try std.testing.expectEqual(&zip, focus.focused().?);
    // Its text is selected, so typing replaces it.
    try std.testing.expect(zip.hasSelection());
    // On past the last: back to the sheet's first, not the field behind it; ⇧Tab goes back.
    try std.testing.expect(focus.advance(&regions, false));
    try std.testing.expectEqual(&name, focus.focused().?);
    try std.testing.expect(focus.advance(&regions, true));
    try std.testing.expectEqual(&zip, focus.focused().?);
    try std.testing.expect(!name.focused);
}
