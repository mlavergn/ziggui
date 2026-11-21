//! The frame a settings picker draws each choice in: a thumbnail ringed in
//! the accent while chosen, over its title, a tap choosing it.

const std = @import("std");
const log = std.log.scoped(.ziggui_thumbnail_choice);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What `AppearancePicker` and `ThemePicker` share: the choice around a
/// thumbnail, and the hairline inside its edge.
pub const ThumbnailChoice = struct {
    const Self = @This();

    /// The ring's width around the chosen thumbnail, in points.
    pub const ring: f32 = 3;

    /// The ring's width around a chosen compact thumbnail, in points.
    pub const compact_ring: f32 = 2;

    /// One choice: its thumbnail on a ground ringed in the accent while
    /// chosen, over its title in `label` while chosen and `secondary_label`
    /// otherwise; a tap sets `selection` to `value`.
    ///
    /// - `picture`: the thumbnail, framed to its size; its corners drawn
    ///   rounded rather than clipped (a clip's edge anti-aliases differently on
    ///   the GPU, a fill's does not).
    /// - `radius`: the thumbnail's corner radius.
    /// - `title`: the choice's name, also its accessibility label.
    /// - `font`: the title's text style.
    /// - `spacing`: the room between the thumbnail and its title.
    /// - `chosen`: whether it is the one selected.
    /// - `selection`: the selected choice, set by a tap.
    /// - `value`: what a tap sets it to.
    /// - Returns: the choice's view.
    pub fn view(picture: mod.View, radius: f32, title: []const u8, font: mod.FontToken, spacing: f32, chosen: bool, selection: mod.Binding(i64), value: i64) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        // The ring is a ground the thumbnail sits on, so a chiseled theme
        // draws it as it does every other fill, not as a bevel.
        var ringed = mod.StackBuilder.make(.vertical, 0, .center, .{picture}).padding(ring).cornerRadius(radius + ring);
        if (chosen) ringed = ringed.background(tokens.accent);
        return mod.StackBuilder.make(.vertical, spacing, .center, .{
            ringed,
            mod.Text(title).font(font).foreground(if (chosen) tokens.label else tokens.secondary_label),
        }).onTap(mod.Callback.select(selection, value))
            .accessibilityLabel(title)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen });
    }

    /// A compact choice: its thumbnail on a ground ringed in the accent while
    /// chosen, no title under it but its title as a hover hint (`.help`) and
    /// accessibility label; a tap sets `selection` to `value`. Chosen or not,
    /// it takes the same room.
    ///
    /// - `picture`: the thumbnail, framed to its size.
    /// - `radius`: the thumbnail's corner radius.
    /// - `title`: the choice's name.
    /// - `chosen`: whether it is the one selected.
    /// - `selection`: the selected choice, set by a tap.
    /// - `value`: what a tap sets it to.
    /// - Returns: the choice's view.
    pub fn compact(picture: mod.View, radius: f32, title: []const u8, chosen: bool, selection: mod.Binding(i64), value: i64) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        var ringed = mod.StackBuilder.make(.vertical, 0, .center, .{picture}).padding(compact_ring).cornerRadius(radius + compact_ring);
        if (chosen) ringed = ringed.background(tokens.accent);
        return ringed.onTap(mod.Callback.select(selection, value))
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen });
    }

    /// Strokes a hairline just inside a thumbnail's edge, inset by half its
    /// width so all of it lies inside the frame: a dark thumbnail keeps its
    /// edge on a dark window.
    ///
    /// - `graphics`: what it draws with.
    /// - `frame`: the thumbnail's frame.
    /// - `radius`: the thumbnail's corner radius.
    /// - `color`: the hairline's color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn outline(graphics: *mod.GraphicsContext, frame: renderer.Rect, radius: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        const hairline = graphics.context.theme.metrics.hairline;
        const edge = renderer.Rect{ .x = frame.x + hairline / 2, .y = frame.y + hairline / 2, .width = frame.width - hairline, .height = frame.height - hairline };
        try graphics.stroke(edge, radius - hairline / 2, hairline, color);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(ThumbnailChoice);
    // Nothing here does I/O to trace.
    _ = log;
}

test "a thumbnail choice is one tap region that sets its value" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    window.begin(renderer.MacosTheme.light);
    const choice = ThumbnailChoice.view(mod.Rectangle(renderer.Color.red).frame(40, 30), 6, "Red", .caption, 4, false, selection.binding(), 7);
    window.end();
    var frame = try window.render(choice, 100, 80);
    defer frame.deinit();
    try std.testing.expectEqual(@as(usize, 1), window.hits.items.len);
    const region = window.hits.items[0].rect;
    try std.testing.expect(window.tap(.{ .x = region.midX(), .y = region.midY() }));
    try std.testing.expectEqual(@as(i64, 7), selection.get());
}
