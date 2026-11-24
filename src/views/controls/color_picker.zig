//! A color picker: a title and a row of swatches, the chosen one marked.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_color_picker);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The swatches and what a tap on one does.
const ColorSwatches = struct {
    const Self = @This();

    /// A swatch's side, in points.
    const side: f32 = 16;

    /// The mark's side on the chosen swatch, in points.
    const mark: f32 = 6;

    /// The fixed palette, the same under every theme: black, white, four
    /// grays, then the accents.
    const palette = [_]renderer.Color{
        renderer.Color.black,
        renderer.Color.white,
        renderer.Color.fromRgb8(0x3A, 0x3A, 0x3C),
        renderer.Color.fromRgb8(0x6E, 0x6E, 0x73),
        renderer.Color.fromRgb8(0xAE, 0xAE, 0xB2),
        renderer.Color.fromRgb8(0xE5, 0xE5, 0xEA),
    } ++ accents();

    /// The binding a tap sets and the color it sets it to, in the build arena.
    selection: mod.Binding(renderer.Color),

    /// The swatch's color.
    color: renderer.Color,

    /// Sets the selection to the swatch's color.
    ///
    /// - `self`: the tap's target.
    fn apply(self: *Self) void {
        self.selection.set(self.color);
    }

    /// The accents' colors, in `Accent.all`'s order.
    ///
    /// - Returns: the colors.
    fn accents() [mod.Accent.all.len]renderer.Color {
        var colors: [mod.Accent.all.len]renderer.Color = undefined;
        for (mod.Accent.all, &colors) |accent, *color| color.* = accent.color();
        return colors;
    }

    /// Whether two colors are the same to within a rounding of 8-bit channels.
    ///
    /// - `first`: one color.
    /// - `second`: the other.
    /// - Returns: true when they match.
    fn same(first: renderer.Color, second: renderer.Color) bool {
        const tolerance = 0.5 / 255.0;
        return @abs(first.r - second.r) <= tolerance and @abs(first.g - second.g) <= tolerance and @abs(first.b - second.b) <= tolerance and @abs(first.a - second.a) <= tolerance;
    }

    /// One swatch: a disc in the color with a hairline around it, a dot
    /// in its middle while chosen; a tap chooses it.
    ///
    /// - `color`: the swatch's color.
    /// - `chosen`: whether it is the selection.
    /// - `selection`: what a tap sets.
    /// - Returns: the swatch.
    fn swatch(color: renderer.Color, chosen: bool, selection: mod.Binding(renderer.Color)) mod.View {
        const scope = mod.BuildScope.shared();
        const target = scope.allocator().create(Self) catch @panic("oom");
        target.* = .{ .selection = selection, .color = color };
        const disc = mod.Circle(color).frame(side, side).border(scope.tokens().line_strong, 1).cornerRadius(side / 2);
        // The mark reads in black on a light color and in white on a dark one.
        const luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
        const on = if (luminance > 0.6) renderer.Color.black else renderer.Color.white;
        const marked = if (chosen) mod.StackBuilder.make(.depth, 0, .center, .{ disc, mod.Circle(on).frame(mark, mark) }) else mod.StackBuilder.make(.depth, 0, .center, .{disc});
        const name = scope.allocator().print("#{X:0>2}{X:0>2}{X:0>2}", .{ Self.channel(color.r), Self.channel(color.g), Self.channel(color.b) }) catch @panic("oom");
        return marked.onTapGesture(mod.Callback.init(Self, target, Self.apply))
            .accessibilityLabel(name)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen });
    }

    /// A channel as an 8-bit value.
    ///
    /// - `value`: the channel, 0 to 1.
    /// - Returns: 0 to 255.
    fn channel(value: f32) u8 {
        return @intFromFloat(@round(std.math.clamp(value, 0, 1) * 255));
    }
};

/// A color picker (SwiftUI's `ColorPicker(_:selection:)`): the title, then
/// a swatch for each color of a fixed palette the same under every theme
/// (black, white, four grays, then `Accent.all`'s hues), the selection
/// marked with a dot, and the selection's own swatch after them when it is
/// none of those. A tap on a swatch sets the selection. A fuller picker
/// (a grid, a hex field, the system panel) can replace the swatches without
/// changing how it is called.
///
/// - `title`: what it picks ("Text"); empty for none.
/// - `selection`: the color, set by a tap.
/// - Returns: the picker, as wide as its content.
pub fn ColorPicker(title: []const u8, selection: mod.Binding(renderer.Color)) mod.View {
    const scope = mod.BuildScope.shared();
    const chosen = selection.get();
    var listed = false;
    for (ColorSwatches.palette) |color| listed = listed or ColorSwatches.same(color, chosen);
    const count = ColorSwatches.palette.len + @intFromBool(!listed);
    const swatches = scope.allocator().alloc(mod.View, count) catch @panic("oom");
    for (ColorSwatches.palette, swatches[0..ColorSwatches.palette.len]) |color, *view| view.* = ColorSwatches.swatch(color, ColorSwatches.same(color, chosen), selection);
    if (!listed) swatches[count - 1] = ColorSwatches.swatch(chosen, true, selection);
    const row = mod.StackBuilder.fromSlice(.horizontal, 6, .center, swatches);
    if (title.len == 0) return row;
    return mod.StackBuilder.make(.horizontal, 10, .center, .{ mod.Text(title), row });
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a color picker marks its selection, adds it when it is not a swatch, and a tap sets it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var color = renderer.State(renderer.Color).init(std.testing.allocator, renderer.Color.white);
    defer color.deinit();

    window.begin(renderer.MacosTheme.light);
    const picker = ColorPicker("", color.binding());
    window.end();
    var frame = try window.render(picker, 400, 30);
    defer frame.deinit();
    try std.testing.expectEqual(ColorSwatches.palette.len, window.hits.items.len);
    // The first swatch is black.
    const first = window.hits.items[0].rect;
    try std.testing.expect(window.tap(.{ .x = first.midX(), .y = first.midY() }));
    try std.testing.expect(ColorSwatches.same(renderer.Color.black, color.get()));

    // A color off the palette gets a swatch of its own.
    color.set(renderer.Color.fromRgb8(1, 2, 3));
    window.begin(renderer.MacosTheme.light);
    const again = ColorPicker("Text", color.binding());
    window.end();
    var second = try window.render(again, 500, 30);
    defer second.deinit();
    try std.testing.expectEqual(ColorSwatches.palette.len + 1, window.hits.items.len);
}
