//! How the `TextField`s in a subtree draw their chrome, as `.textFieldStyle()` sets it.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_field_style);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How a `TextField` draws its chrome (SwiftUI's `TextFieldStyle`): set for a
/// subtree and inherited, as `.toggleStyle()` is.
pub const TextFieldStyle = enum {
    const Self = @This();

    /// The theme's field: its ground, border and focus ring.
    automatic,

    /// No chrome of its own: the text alone, on whatever its container draws.
    plain,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// Draws one view headless and returns its pixels, for the tests.
const StyleProbe = struct {
    const Self = @This();

    /// Draws `build(field)` in a 200 × 40 window.
    ///
    /// - `field`: the field the view shows.
    /// - `build`: makes the view around it.
    /// - Returns: the pixels, owned by the caller; propagates allocation failure.
    fn draw(field: *mod.TextFieldState, comptime build: fn (*mod.TextFieldState) mod.View) ![]renderer.Color {
        const window = try mod.TestWindow.create(std.testing.allocator);
        defer window.destroy();
        window.begin(renderer.MacosTheme.light);
        const view = build(field);
        window.end();
        var frame = try window.render(view, 200, 40);
        defer frame.deinit();
        return std.testing.allocator.dupe(renderer.Color, frame.pixels);
    }

    /// A field with the theme's chrome.
    ///
    /// - `field`: the field.
    /// - Returns: the view.
    fn automatic(field: *mod.TextFieldState) mod.View {
        return mod.TextField("", field).frameMaxWidth();
    }

    /// A field styled plain itself.
    ///
    /// - `field`: the field.
    /// - Returns: the view.
    fn plain(field: *mod.TextFieldState) mod.View {
        return mod.TextField("", field).textFieldStyle(.plain).frameMaxWidth();
    }

    /// A field in a stack styled plain, which it inherits.
    ///
    /// - `field`: the field.
    /// - Returns: the view.
    fn inherited(field: *mod.TextFieldState) mod.View {
        return mod.StackBuilder.make(.vertical, 0, .leading, .{mod.TextField("", field).frameMaxWidth()}).textFieldStyle(.plain);
    }
};

test "a plain text field draws no chrome, styled itself or by its container" {
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    const automatic = try StyleProbe.draw(&field, StyleProbe.automatic);
    defer std.testing.allocator.free(automatic);
    const plain = try StyleProbe.draw(&field, StyleProbe.plain);
    defer std.testing.allocator.free(plain);
    const inherited = try StyleProbe.draw(&field, StyleProbe.inherited);
    defer std.testing.allocator.free(inherited);
    try std.testing.expect(!std.mem.eql(u8, std.mem.sliceAsBytes(automatic), std.mem.sliceAsBytes(plain)));
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(plain), std.mem.sliceAsBytes(inherited));
    // An empty plain field on the window's ground draws nothing at all.
    for (plain) |pixel| try std.testing.expectEqual(plain[0], pixel);
}
