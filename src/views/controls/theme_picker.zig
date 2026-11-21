//! A settings page's theme choice: a small window for each theme family,
//! drawn in that family's colors, title bar and corners, over a row of accent
//! swatches, the chosen ones marked.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_theme_picker);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One theme family's thumbnail: what its `Canvas` draws.
const ThemeThumbnail = struct {
    const Self = @This();

    /// The thumbnail's size, in points.
    const size = renderer.Size{ .width = 52, .height = 34 };
    /// The thumbnail's corner radius.
    const radius: f32 = 5;
    /// A mini thumbnail's size (`ThemeFamilyPicker`), in points: the same
    /// picture, scaled down.
    const mini_size = renderer.Size{ .width = 32, .height = 21 };
    /// A mini thumbnail's corner radius.
    const mini_radius: f32 = 3;
    /// The desktop behind the little window, in a light appearance.
    const light_desktop = renderer.Color.hex(0xC4D3EA);
    /// The desktop behind the little window, in a dark appearance.
    const dark_desktop = renderer.Color.hex(0x2B3445);

    /// The family's theme, in the appearance and accent chosen.
    theme: renderer.Theme,
    /// The hairline around the thumbnail, so a dark one keeps its edge on a dark window.
    outline: renderer.Color,
    /// How much smaller than `size` it is drawn: 1 for a full thumbnail.
    scale: f32 = 1,
    /// Its corner radius.
    corner: f32 = radius,

    /// One family's choice: its thumbnail, ringed in the accent while chosen,
    /// over its name; a tap chooses it.
    ///
    /// - `family`: the theme family.
    /// - `index`: its index in `ThemeFamily.all`, what a tap sets.
    /// - `chosen`: whether it is the one selected.
    /// - `accent`: the accent chosen, or null for each family's own.
    /// - `selection`: the selected family's index, set by a tap.
    /// - Returns: the choice's view.
    fn choice(family: renderer.ThemeFamily, index: usize, chosen: bool, accent: ?mod.Accent, selection: mod.Binding(i64)) mod.View {
        const picture = Self.make(family, accent, 1, radius).frame(size.width, size.height);
        return mod.ThumbnailChoice.view(picture, radius, family.displayName(), .caption, 4, chosen, selection, @intCast(index));
    }

    /// One family's mini choice: its thumbnail scaled down, ringed in the
    /// accent while chosen, its name a hover hint; a tap chooses it. Chosen or
    /// not, it takes the same room.
    ///
    /// - `family`: the theme family.
    /// - `index`: its index in `ThemeFamily.all`, what a tap sets.
    /// - `chosen`: whether it is the one selected.
    /// - `accent`: the accent chosen, or null for each family's own.
    /// - `selection`: the selected family's index, set by a tap.
    /// - Returns: the choice's view.
    fn mini(family: renderer.ThemeFamily, index: usize, chosen: bool, accent: ?mod.Accent, selection: mod.Binding(i64)) mod.View {
        const picture = Self.make(family, accent, mini_size.width / size.width, mini_radius).frame(mini_size.width, mini_size.height);
        return mod.ThumbnailChoice.compact(picture, mini_radius, family.displayName(), chosen, selection, @intCast(index));
    }

    /// The `Canvas` drawing a family's thumbnail in the appearance on show and
    /// the accent chosen.
    ///
    /// - `family`: the theme family.
    /// - `accent`: the accent chosen, or null for the family's own.
    /// - `scale`: how much smaller than `size` it is drawn.
    /// - `corner`: its corner radius.
    /// - Returns: the canvas, to be framed to the scaled size.
    fn make(family: renderer.ThemeFamily, accent: ?mod.Accent, scale: f32, corner: f32) mod.View {
        const scope = mod.BuildScope.shared();
        const dark = scope.theme().scheme == .dark;
        const thumbnail = scope.allocator().create(Self) catch @panic("oom");
        thumbnail.* = .{
            .theme = if (accent) |picked| picked.theme(family, dark) else family.forScheme(if (dark) .dark else .light),
            .outline = scope.tokens().separator,
            .scale = scale,
            .corner = corner,
        };
        return mod.Canvas(Self, thumbnail, Self.draw);
    }

    /// Draws the thumbnail: a desktop with a little window on it in the
    /// family's colors (its title bar as the family paints one, a sidebar with
    /// its selected row and a button in the accent, lines of text), inside a
    /// hairline; every measure scaled by `scale`.
    ///
    /// - `self`: the thumbnail.
    /// - `graphics`: what it draws with.
    /// - `frame`: its frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, graphics: *mod.GraphicsContext, frame: renderer.Rect) std.mem.Allocator.Error!void {
        const colors = &self.theme.colors;
        const metrics = &self.theme.metrics;
        const unit = self.scale;
        try graphics.fill(frame, self.corner, if (self.theme.scheme == .dark) dark_desktop else light_desktop);

        const window = renderer.Rect{ .x = frame.x + 6 * unit, .y = frame.y + 5 * unit, .width = frame.width - 12 * unit, .height = frame.height - 8 * unit };
        try graphics.fill(window, metrics.radius(2 * unit), colors.window_background);
        // The family paints its own title bar, in its own colors.
        const title_bar = renderer.Rect{ .x = window.x, .y = window.y, .width = window.width, .height = 6 * unit };
        const surface = renderer.Surface{ .display_list = graphics.display_list, .palette = colors, .metrics = metrics, .scheme = self.theme.scheme, .opacity = graphics.context.opacity };
        try self.theme.drawTitleBar(surface, title_bar);
        const mark = self.theme.titleBarForeground().withAlpha(0.7);
        for (0..3) |index| {
            const x = window.maxX() - 4 * unit - @as(f32, @floatFromInt(index)) * 3.5 * unit;
            try graphics.fill(.{ .x = x - 1 * unit, .y = title_bar.y + 2 * unit, .width = 2 * unit, .height = 2 * unit }, metrics.radius(1 * unit), mark);
        }

        const body_y = title_bar.maxY();
        const sidebar_width = 11 * unit;
        try graphics.fill(.{ .x = window.x, .y = body_y, .width = sidebar_width, .height = window.maxY() - body_y }, 0, colors.sidebar_background orelse colors.secondary_background);
        try graphics.fill(.{ .x = window.x + 2 * unit, .y = body_y + 3 * unit, .width = sidebar_width - 4 * unit, .height = 3 * unit }, metrics.radius(1 * unit), colors.accent);
        try graphics.fill(.{ .x = window.x + 2 * unit, .y = body_y + 8 * unit, .width = sidebar_width - 6 * unit, .height = 2 * unit }, metrics.radius(1 * unit), colors.secondary_label.withAlpha(0.5));

        const text_x = window.x + sidebar_width + 3 * unit;
        const text_width = window.maxX() - 3 * unit - text_x;
        for ([_]f32{ 0.85, 0.6 }, 0..) |fraction, index| {
            const y = body_y + 3 * unit + @as(f32, @floatFromInt(index)) * 4 * unit;
            try graphics.fill(.{ .x = text_x, .y = y, .width = text_width * fraction, .height = 2 * unit }, metrics.radius(1 * unit), colors.label.withAlpha(0.25));
        }
        try graphics.fill(.{ .x = window.maxX() - 3 * unit - 10 * unit, .y = window.maxY() - 6 * unit, .width = 10 * unit, .height = 4 * unit }, metrics.radius(1.5 * unit), colors.accent);

        try mod.ThumbnailChoice.outline(graphics, frame, self.corner, self.outline);
    }
};

/// The accent swatches under the thumbnails.
const AccentSwatches = struct {
    const Self = @This();

    /// A swatch's side, in points.
    const side: f32 = 16;
    /// The mark's side on the chosen swatch, in points.
    const mark: f32 = 6;

    /// The swatches, the chosen one marked, with the chosen accent's name
    /// under them.
    ///
    /// - `family`: the theme family chosen, whose own accent the first swatch shows.
    /// - `selection`: the chosen accent's choice index (`Accent.atChoice`), set by a tap.
    /// - Returns: the row and its name.
    fn row(family: renderer.ThemeFamily, selection: mod.Binding(i64)) mod.View {
        const scope = mod.BuildScope.shared();
        const tokens = scope.tokens();
        const own = family.forScheme(scope.theme().scheme).colors;
        const chosen = mod.Accent.atChoice(selection.get());
        const swatches = scope.allocator().alloc(mod.View, mod.Accent.all.len + 1) catch @panic("oom");
        swatches[0] = Self.swatch(own.accent, own.on_accent, chosen == null, 0, "Theme", selection);
        for (mod.Accent.all, swatches[1..], 1..) |accent, *swatch_view, index| {
            swatch_view.* = Self.swatch(accent.color(), accent.onColor(), chosen == accent, @intCast(index), accent.displayName(), selection);
        }
        const name = if (chosen) |accent| accent.displayName() else scope.allocator().print("{s}'s own", .{family.displayName()}) catch @panic("oom");
        return mod.StackBuilder.make(.vertical, 4, .leading, .{
            mod.StackBuilder.fromSlice(.horizontal, 6, .center, swatches),
            mod.Text(name).font(.caption).foreground(tokens.secondary_label),
        });
    }

    /// One swatch: a disc in the accent, a dot in its middle while chosen; a
    /// tap chooses it.
    ///
    /// - `color`: the accent.
    /// - `on`: what reads on it, the mark's color.
    /// - `chosen`: whether it is the one selected.
    /// - `index`: its choice index, what a tap sets.
    /// - `name`: what it is called, for accessibility.
    /// - `selection`: the chosen accent's choice index.
    /// - Returns: the swatch.
    fn swatch(color: renderer.Color, on: renderer.Color, chosen: bool, index: i64, name: []const u8, selection: mod.Binding(i64)) mod.View {
        const disc = mod.Circle(color).frame(side, side);
        const marked = if (chosen) mod.StackBuilder.make(.depth, 0, .center, .{ disc, mod.Circle(on).frame(mark, mark) }) else mod.StackBuilder.make(.depth, 0, .center, .{disc});
        return marked.onTap(mod.Callback.select(selection, index))
            .accessibilityLabel(name)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen });
    }
};

/// A theme picker for a settings page: a little window for each theme
/// family, drawn in that family's colors, title bar and corners in the
/// appearance on show and the accent chosen, over its name, the chosen one
/// ringed in the accent; under them a swatch for the chosen family's own
/// accent, then one for each `Accent`, the chosen one marked, and its name.
/// A tap chooses either. It only records the choices: the app draws in
/// `Accent.atChoice(accent)`'s theme of the family (`Accent.theme`), or the
/// family's own (`ThemeFamily.forScheme`) when that is null. Put it in a
/// `Form` with `LabeledContent("Theme:", …)`.
///
/// - `family`: the chosen family's index in `ThemeFamily.all`; app-owned.
/// - `accent`: the chosen accent's choice index (`Accent.atChoice`); app-owned.
/// - Returns: the picker, as wide as its five families.
pub fn ThemePicker(family: mod.Binding(i64), accent: mod.Binding(i64)) mod.View {
    const scope = mod.BuildScope.shared();
    const last: i64 = renderer.ThemeFamily.all.len - 1;
    const chosen_index: usize = @intCast(std.math.clamp(family.get(), 0, last));
    const picked = mod.Accent.atChoice(accent.get());
    const choices = scope.allocator().alloc(mod.View, renderer.ThemeFamily.all.len) catch @panic("oom");
    for (renderer.ThemeFamily.all, choices, 0..) |each, *choice, index| choice.* = ThemeThumbnail.choice(each, index, index == chosen_index, picked, family);
    return mod.StackBuilder.make(.vertical, 12, .leading, .{
        mod.StackBuilder.fromSlice(.horizontal, 8, .top, choices),
        AccentSwatches.row(renderer.ThemeFamily.all[chosen_index], accent),
    });
}

/// The theme families alone, small: a mini rendering of each family (its
/// colors, title bar and corners in the appearance on show and the accent
/// chosen), its name a hover hint, the chosen one ringed in the accent; a
/// tap chooses one. Each takes the same room chosen or not, so nothing moves
/// under the pointer. For a narrow place (a sidebar) where `ThemePicker`'s
/// titled thumbnails and swatches do not fit; the accent is the app's to offer.
///
/// - `family`: the chosen family's index in `ThemeFamily.all`; app-owned.
/// - `accent`: the chosen accent's choice index (`Accent.atChoice`), for the renderings.
/// - Returns: the row of renderings.
pub fn ThemeFamilyPicker(family: mod.Binding(i64), accent: mod.Binding(i64)) mod.View {
    const scope = mod.BuildScope.shared();
    const last: i64 = renderer.ThemeFamily.all.len - 1;
    const chosen_index: usize = @intCast(std.math.clamp(family.get(), 0, last));
    const picked = mod.Accent.atChoice(accent.get());
    const choices = scope.allocator().alloc(mod.View, renderer.ThemeFamily.all.len) catch @panic("oom");
    for (renderer.ThemeFamily.all, choices, 0..) |each, *choice, index| choice.* = ThemeThumbnail.mini(each, index, index == chosen_index, picked, family);
    return mod.StackBuilder.fromSlice(.horizontal, 4, .center, choices);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a theme picker rings the chosen family and marks the chosen accent; taps choose others" {
    const Order = struct {
        const Self = @This();

        /// Whether one region starts left of another.
        ///
        /// - `context`: unused.
        /// - `left`: one region.
        /// - `right`: the other.
        /// - Returns: true when `left` starts first.
        fn leftmost(context: void, left: renderer.Rect, right: renderer.Rect) bool {
            _ = context;
            return left.x < right.x;
        }
    };
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var family = renderer.State(i64).init(std.testing.allocator, 0);
    defer family.deinit();
    var accent = renderer.State(i64).init(std.testing.allocator, 0);
    defer accent.deinit();
    window.begin(renderer.MacosTheme.light);
    const picker = ThemePicker(family.binding(), accent.binding());
    window.end();
    var frame = try window.render(picker, 420, 120);
    defer frame.deinit();

    // macOS is chosen: its ring is the accent.
    const tokens = mod.BuildScope.shared().tokens();
    try std.testing.expect(frame.at(1, 20).approxEql(tokens.accent, 0.05));

    // Five families and nine swatches take taps; the families sit above the swatches.
    try std.testing.expectEqual(@as(usize, renderer.ThemeFamily.all.len + mod.Accent.all.len + 1), window.hits.items.len);
    var families: [renderer.ThemeFamily.all.len]renderer.Rect = undefined;
    var swatches: [mod.Accent.all.len + 1]renderer.Rect = undefined;
    var family_count: usize = 0;
    var swatch_count: usize = 0;
    for (window.hits.items) |hit| {
        if (hit.rect.height > AccentSwatches.side + 1) {
            families[family_count] = hit.rect;
            family_count += 1;
        } else {
            swatches[swatch_count] = hit.rect;
            swatch_count += 1;
        }
    }
    try std.testing.expectEqual(families.len, family_count);
    try std.testing.expectEqual(swatches.len, swatch_count);
    std.mem.sort(renderer.Rect, &families, {}, Order.leftmost);
    std.mem.sort(renderer.Rect, &swatches, {}, Order.leftmost);

    // A tap on the third family chooses Windows 2000; one on the third swatch chooses Blue.
    try std.testing.expect(window.tap(.{ .x = families[2].midX(), .y = families[2].midY() }));
    try std.testing.expectEqual(@as(i64, 2), family.get());
    try std.testing.expect(window.tap(.{ .x = swatches[2].midX(), .y = swatches[2].midY() }));
    try std.testing.expectEqual(@as(?mod.Accent, .blue), mod.Accent.atChoice(accent.get()));
}

test "a theme family picker is one mini rendering per family, each the same size, a tap choosing it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var family = renderer.State(i64).init(std.testing.allocator, 0);
    defer family.deinit();
    var accent = renderer.State(i64).init(std.testing.allocator, 0);
    defer accent.deinit();
    window.begin(renderer.MacosTheme.light);
    const picker = ThemeFamilyPicker(family.binding(), accent.binding());
    window.end();
    var frame = try window.render(picker, 200, 30);
    defer frame.deinit();
    try std.testing.expectEqual(@as(usize, renderer.ThemeFamily.all.len), window.hits.items.len);
    for (window.hits.items) |hit| try std.testing.expectEqual(window.hits.items[0].rect.width, hit.rect.width);
    var rightmost = window.hits.items[0].rect;
    for (window.hits.items) |hit| if (hit.rect.x > rightmost.x) {
        rightmost = hit.rect;
    };
    try std.testing.expect(window.tap(.{ .x = rightmost.midX(), .y = rightmost.midY() }));
    try std.testing.expectEqual(@as(i64, renderer.ThemeFamily.all.len - 1), family.get());
}
