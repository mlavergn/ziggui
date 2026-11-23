//! A bar chart: labelled values drawn as bars from zero, each in an equal
//! slot, on a scale given or taken from the values, with an optional grid, a
//! line through the bars' ends and a caption, in the look every chart here
//! shares (`ChartStyle`). Composed on `Canvas`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_bar_chart);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");

/// How much of its slot a bar takes, centred in it.
const bar_share: f32 = 0.6;
/// A bar's corner radius, in points.
const bar_radius: f32 = 4;
/// How opaque a bar with no color of its own is, as a fraction of the accent's alpha.
const bar_alpha: f32 = 0.45;
/// The overlaid line's dots' radius, in points.
const dot_radius: f32 = 3;
/// How opaque the zero line is, as a fraction of the label color's alpha.
const zero_alpha: f32 = 0.5;
/// How many bars accessibility reads by label and value before it counts the rest.
const described_bars = 20;

/// One frame of a bar chart, in the build arena: the `Canvas`'s context.
const BarChartFrame = struct {
    const Self = @This();

    /// The bars, copied into the build arena (their labels are the caller's).
    marks: []const mod.BarMark,
    /// The value axis's scale.
    axis: mod.ChartAxis,
    /// How many bands the grid rules the plot into; 0 for no grid.
    grid_divisions: u8,
    /// Whether a line runs through the bars' ends.
    overlay_line: bool,
    /// The caption over the plot.
    caption: []const u8,
    /// Whether any bar has a label, so the labels' band is kept.
    labelled: bool,
    /// The line's and dots' color, and a bar's when it gives none.
    accent: renderer.Color,
    /// The grid's color.
    separator: renderer.Color,
    /// The theme's label color, which the plot's ground is a faint wash of.
    label: renderer.Color,
    /// The labels' and caption's color.
    label_color: renderer.Color,

    /// A frame from the bars, the options and the theme's colors, its scale
    /// resolved from the finite values and zero.
    ///
    /// - `marks`: the bars, already in the build arena.
    /// - `options`: the scale, grid, line and caption.
    /// - `tokens`: the theme's colors.
    /// - Returns: the frame.
    fn init(marks: []const mod.BarMark, options: mod.BarChartOptions, tokens: views.BuildTokens) Self {
        // Every bar grows from zero, so zero is always on the scale.
        var lower: f64 = 0;
        var upper: f64 = 0;
        var labelled = false;
        for (marks) |mark| {
            if (mark.label.len > 0) labelled = true;
            if (!std.math.isFinite(mark.value)) continue;
            lower = @min(lower, mark.value);
            upper = @max(upper, mark.value);
        }
        // Nothing but zero (or nothing at all): zero at the foot, as for
        // positive bars, rather than a range widened about it to −1…1.
        if (lower == 0 and upper == 0) upper = 1;
        const self = Self{
            .marks = marks,
            .axis = mod.ChartAxis.init(options.y_domain, lower, upper),
            .grid_divisions = options.grid_divisions,
            .overlay_line = options.overlay_line,
            .caption = options.caption,
            .labelled = labelled,
            .accent = tokens.accent,
            .separator = tokens.separator,
            .label = tokens.label,
            .label_color = tokens.secondary_label,
        };
        return self;
    }

    /// Draws the chart into its frame: the plot's ground, the grid, the zero
    /// line when bars go below it, the bars and their labels (each cut to its
    /// slot), the caption, then the line through the bars' ends and its dots.
    /// A frame with no room for a plot draws nothing.
    ///
    /// - `self`: the frame.
    /// - `graphics`: what it draws with.
    /// - `rect`: the view's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, graphics: *views.GraphicsContext, rect: renderer.Rect) std.mem.Allocator.Error!void {
        const plot = mod.ChartStyle.plot(graphics, rect, self.caption.len > 0, self.labelled);
        if (!mod.ChartStyle.hasRoom(plot)) return;
        try mod.ChartStyle.drawGround(graphics, plot, self.label);
        if (self.grid_divisions > 0) {
            for (0..@as(usize, self.grid_divisions) + 1) |step| {
                const y = plot.y + plot.height * @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(self.grid_divisions));
                try graphics.line(.{ .x = plot.x, .y = y }, .{ .x = plot.maxX(), .y = y }, mod.ChartStyle.rule_width, self.separator);
            }
        }
        const zero_y = Self.place(plot, self.axis, 0);
        if (self.axis.lower < 0 and self.axis.upper > 0) try graphics.line(.{ .x = plot.x, .y = zero_y }, .{ .x = plot.maxX(), .y = zero_y }, mod.ChartStyle.rule_width, self.label_color.multiplyAlpha(zero_alpha));
        try mod.ChartStyle.drawCaption(graphics, self.caption, rect, self.label_color);
        if (self.marks.len == 0) return;
        const slot = plot.width / @as(f32, @floatFromInt(self.marks.len));
        for (self.marks, 0..) |mark, index| {
            const slot_x = plot.x + slot * @as(f32, @floatFromInt(index));
            if (std.math.isFinite(mark.value)) {
                const end_y = Self.place(plot, self.axis, mark.value);
                const bar = renderer.Rect{ .x = slot_x + slot * (1 - bar_share) / 2, .y = @min(zero_y, end_y), .width = slot * bar_share, .height = @abs(end_y - zero_y) };
                if (bar.height > 0) try graphics.fill(bar, @min(bar_radius, bar.width / 2, bar.height / 2), mark.color orelse self.accent.multiplyAlpha(bar_alpha));
            }
            // A label wider than its slot is cut with an ellipsis, or left out
            // where not even that fits, so neighbours never overlap.
            const label = try graphics.context.truncateToWidth(mark.label, mod.ChartStyle.label_size, slot);
            if (label.len > 0) {
                const width = graphics.textWidth(label, mod.ChartStyle.label_size);
                try graphics.text(label, mod.ChartStyle.label_size, self.label_color, .{ .x = slot_x + (slot - width) / 2, .y = plot.maxY() + mod.ChartStyle.label_gap });
            }
        }
        if (self.overlay_line) try self.drawLine(graphics, plot, slot);
    }

    /// Draws the line through the bars' ends, broken at a value that is not
    /// finite, and then a dot on each end, over the line's joins.
    ///
    /// - `self`: the frame.
    /// - `graphics`: what it draws with.
    /// - `plot`: the plot's rectangle.
    /// - `slot`: each bar's slot width.
    /// - Returns: nothing; propagates allocation failure.
    fn drawLine(self: *const Self, graphics: *views.GraphicsContext, plot: renderer.Rect, slot: f32) std.mem.Allocator.Error!void {
        var previous: ?renderer.Point = null;
        for (self.marks, 0..) |mark, index| {
            const end = self.endOf(plot, slot, mark, index) orelse {
                previous = null;
                continue;
            };
            if (previous) |start| try graphics.line(start, end, mod.ChartStyle.line_width, self.accent);
            previous = end;
        }
        for (self.marks, 0..) |mark, index| {
            const end = self.endOf(plot, slot, mark, index) orelse continue;
            try graphics.fill(.{ .x = end.x - dot_radius, .y = end.y - dot_radius, .width = 2 * dot_radius, .height = 2 * dot_radius }, dot_radius, self.accent);
        }
    }

    /// Where a bar ends: the middle of its slot, at its value.
    ///
    /// - `self`: the frame.
    /// - `plot`: the plot's rectangle.
    /// - `slot`: each bar's slot width.
    /// - `mark`: the bar.
    /// - `index`: the bar's slot.
    /// - Returns: the point, or null when its value is not finite.
    fn endOf(self: *const Self, plot: renderer.Rect, slot: f32, mark: mod.BarMark, index: usize) ?renderer.Point {
        if (!std.math.isFinite(mark.value)) return null;
        return .{ .x = plot.x + slot * (@as(f32, @floatFromInt(index)) + 0.5), .y = Self.place(plot, self.axis, mark.value) };
    }

    /// Where a value lies on the plot, held to its edges, so a bar past a
    /// given range stops there and no value overflows.
    ///
    /// - `plot`: the plot's rectangle.
    /// - `axis`: the value axis.
    /// - `value`: the value, finite.
    /// - Returns: the y it lies at.
    fn place(plot: renderer.Rect, axis: mod.ChartAxis, value: f32) f32 {
        const fraction = std.math.clamp(axis.fraction(value), 0, 1);
        return @floatCast(@as(f64, plot.maxY()) - fraction * plot.height);
    }

    /// What the chart says to accessibility: "Bar chart", its caption, then
    /// the first `described_bars` labelled bars' labels and values, and how
    /// many more there are, so a long chart costs a frame little.
    ///
    /// - `self`: the frame.
    /// - `allocator`: the build arena.
    /// - Returns: the description; propagates allocation failure.
    fn describe(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(allocator, "Bar chart");
        if (self.caption.len > 0) try text.print(allocator, ", {s}", .{self.caption});
        var listed: usize = 0;
        var unlisted: usize = 0;
        for (self.marks) |mark| {
            if (mark.label.len == 0 or !std.math.isFinite(mark.value)) continue;
            if (listed == described_bars) {
                unlisted += 1;
                continue;
            }
            try text.print(allocator, "{s}{s} {d}", .{ if (listed == 0) ": " else ", ", mark.label, mark.value });
            listed += 1;
        }
        if (unlisted > 0) try text.print(allocator, ", and {d} more", .{unlisted});
        return text.items;
    }
};

/// A bar chart of `marks` drawn into its frame, as Swift Charts' `Chart` of
/// `BarMark`s: each value a bar from zero (up or down) centred in an equal
/// slot, its label under it (cut with an ellipsis to its slot), in the accent
/// at 0.45 unless it has a color of its own; on a plot with a faint ground,
/// as `LineChart` draws (`ChartStyle`); under a caption, ruled by a grid, and
/// with a line through the bars' ends, when `options` asks. It fills the
/// space it is offered, so give it a frame (`.frameMaxWidth().frameHeight(140)`).
/// Accessibility reads it as an image named "Bar chart", its caption and the
/// first 20 labelled bars' labels and values, then how many more;
/// `.accessibilityLabel` names it otherwise. A value that is not finite draws
/// no bar, and no bars or a frame too small for a plot draw what they can.
///
/// - `marks`: the bars, copied into the build arena; their labels must last
///   until the frame is drawn.
/// - `options`: the scale, grid, line and caption (`.{}` for none).
/// - Returns: the view.
pub fn BarChart(marks: []const mod.BarMark, options: mod.BarChartOptions) views.View {
    const scope = views.BuildScope.shared();
    const allocator = scope.allocator();
    const frame = allocator.create(BarChartFrame) catch @panic("oom");
    frame.* = BarChartFrame.init(allocator.dupe(mod.BarMark, marks) catch @panic("oom"), options, scope.tokens());
    const description = frame.describe(allocator) catch @panic("oom");
    return views.Canvas(BarChartFrame, frame, BarChartFrame.draw).accessibilityLabel(description);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a bar chart draws a bar from zero in each slot, its line and dots over them" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const marks = [_]mod.BarMark{ .{ .value = 1 }, .{ .value = 2, .color = renderer.Color.red } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, .{ .overlay_line = true, .grid_divisions = 2 }), 200, 100);
    const tokens = views.BuildScope.shared().tokens();
    var fills: std.ArrayList(renderer.FillRoundedRectCommand) = .empty;
    defer fills.deinit(std.testing.allocator);
    try mod.ChartProbe.fills(&display_list, &fills);
    // With no caption or labels the plot's ground fills the frame: two slots
    // of 100, each bar 60 wide, then a dot on each bar's end.
    try std.testing.expectEqual(5, fills.items.len);
    try mod.ChartProbe.expectRect(.{ .x = 0, .y = 0, .width = 200, .height = 100 }, fills.items[0].rect);
    try mod.ChartProbe.expectRect(.{ .x = 20, .y = 50, .width = 60, .height = 50 }, fills.items[1].rect);
    try std.testing.expectApproxEqAbs(tokens.accent.a * bar_alpha, fills.items[1].color.a, 1e-6);
    try mod.ChartProbe.expectRect(.{ .x = 120, .y = 0, .width = 60, .height = 100 }, fills.items[2].rect);
    try std.testing.expectEqual(renderer.Color.red, fills.items[2].color);
    try std.testing.expectEqual(renderer.Point{ .x = 50, .y = 50 }, fills.items[3].rect.center());
    try std.testing.expectEqual(renderer.Point{ .x = 150, .y = 0 }, fills.items[4].rect.center());
    // Three grid lines, then the line through the ends.
    var lines: std.ArrayList(renderer.LineCommand) = .empty;
    defer lines.deinit(std.testing.allocator);
    try mod.ChartProbe.lines(&display_list, &lines);
    try std.testing.expectEqual(4, lines.items.len);
    try std.testing.expectEqual(renderer.Point{ .x = 50, .y = 50 }, lines.items[3].start);
    try std.testing.expectEqual(tokens.accent, lines.items[3].color);
    try std.testing.expectEqual(mod.ChartStyle.line_width, lines.items[3].width);
}

test "a bar below zero grows down from the zero line" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const marks = [_]mod.BarMark{ .{ .value = 3 }, .{ .value = -1 } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, .{}), 200, 100);
    var fills: std.ArrayList(renderer.FillRoundedRectCommand) = .empty;
    defer fills.deinit(std.testing.allocator);
    try mod.ChartProbe.fills(&display_list, &fills);
    // −1 to 3 over 100 points: zero 75 down.
    try mod.ChartProbe.expectRect(.{ .x = 20, .y = 0, .width = 60, .height = 75 }, fills.items[1].rect);
    try mod.ChartProbe.expectRect(.{ .x = 120, .y = 75, .width = 60, .height = 25 }, fills.items[2].rect);
    var lines: std.ArrayList(renderer.LineCommand) = .empty;
    defer lines.deinit(std.testing.allocator);
    try mod.ChartProbe.lines(&display_list, &lines);
    try std.testing.expectEqual(1, lines.items.len);
    try std.testing.expectEqual(75, lines.items[0].start.y);
}

test "a bar chart of nothing, or of zeros, keeps zero at its foot" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const zeros = [_]mod.BarMark{ .{ .value = 0 }, .{ .value = 0 } };
    for ([_][]const mod.BarMark{ &.{}, &zeros }) |marks| {
        display_list.clearCommands();
        try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(marks, .{}), 200, 100);
        // The plot's ground alone: no zero line across it, no bar of no height.
        var fills: std.ArrayList(renderer.FillRoundedRectCommand) = .empty;
        defer fills.deinit(std.testing.allocator);
        try mod.ChartProbe.fills(&display_list, &fills);
        try std.testing.expectEqual(1, fills.items.len);
        for (display_list.commands.items) |command| try std.testing.expect(command != .line);
    }
}

test "a bar chart cuts each label to its slot" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const marks = [_]mod.BarMark{ .{ .label = "Wednesday", .value = 1 }, .{ .label = "Thursday", .value = 2 } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, .{}), 40, 80);
    // Two slots of 20: every glyph inside the frame, none crossing from one
    // slot into the other (whole, "Wednesday" would run 15 points past the
    // frame's left edge).
    var glyphs: usize = 0;
    for (display_list.commands.items) |command| {
        if (command != .glyph) continue;
        glyphs += 1;
        const rect = command.glyph.rect;
        try std.testing.expect(rect.x >= -0.5 and rect.maxX() <= 40.5);
        try std.testing.expect(!(rect.x < 19.5 and rect.maxX() > 20.5));
    }
    try std.testing.expect(glyphs > 0);
}

test "a bar chart skips what cannot draw and stays in its plot" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const marks = [_]mod.BarMark{
        .{ .label = "a", .value = 0.5 },                    .{ .label = "b", .value = std.math.nan(f32) },
        .{ .label = "c", .value = std.math.floatMax(f32) }, .{ .label = "d", .value = -std.math.inf(f32) },
    };
    const options: mod.BarChartOptions = .{ .y_domain = .{ .lower = 0, .upper = 1 }, .overlay_line = true };
    const sizes = [_][2]f32{ .{ 0, 0 }, .{ 1, 1 }, .{ 20, 300 }, .{ 300, 20 }, .{ 232, 128 }, .{ -5, -5 }, .{ std.math.nan(f32), 10 } };
    for (sizes) |size| {
        display_list.clearCommands();
        try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, options), size[0], size[1]);
        if (size[0] > 0 and size[1] > 0) try mod.ChartProbe.expectInside(&display_list, .{ .x = 0, .y = 0, .width = size[0], .height = size[1] });
        for (display_list.commands.items) |command| {
            if (command == .fillRoundedRect) try std.testing.expect(std.math.isFinite(command.fillRoundedRect.rect.y) and command.fillRoundedRect.rect.height >= 0);
        }
    }
    // In a roomy frame: the ground, two bars (the NaN and the infinity draw
    // none), the huge one held to the plot's top, and a dot each on "a" and
    // "c"; no segment, the NaN after "a" and the infinity after "c" breaking it.
    display_list.clearCommands();
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, options), 232, 160);
    var fills: std.ArrayList(renderer.FillRoundedRectCommand) = .empty;
    defer fills.deinit(std.testing.allocator);
    try mod.ChartProbe.fills(&display_list, &fills);
    try std.testing.expectEqual(5, fills.items.len);
    try std.testing.expectEqual(0, fills.items[2].rect.y);
    for (display_list.commands.items) |command| try std.testing.expect(command != .line);
}

test "a bar chart reads its bars to accessibility, the first twenty by name" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const marks = [_]mod.BarMark{ .{ .label = "Mon", .value = 35 }, .{ .label = "Tue", .value = 60 }, .{ .value = 9 } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, .{ .caption = "Steps" }).accessibilityIdentifier("steps"), 200, 120);
    try std.testing.expectEqual(views.A11yRole.image, a11y.items[0].role);
    try std.testing.expectEqualStrings("Bar chart, Steps: Mon 35, Tue 60", views.A11yNode.find(a11y.items, "steps").?.label);
    // Past twenty, the rest are counted, not read.
    var many: [described_bars + 5]mod.BarMark = undefined;
    for (&many, 0..) |*mark, index| mark.* = .{ .label = "x", .value = @floatFromInt(index) };
    a11y.clearRetainingCapacity();
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&many, .{}).accessibilityIdentifier("many"), 200, 120);
    const label = views.A11yNode.find(a11y.items, "many").?.label;
    try std.testing.expect(std.mem.endsWith(u8, label, ", x 19, and 5 more"));
    try std.testing.expectEqual(described_bars, std.mem.count(u8, label, "x "));
    // The app's own name replaces it.
    a11y.clearRetainingCapacity();
    try mod.ChartProbe.render(&environment, &display_list, &a11y, BarChart(&marks, .{}).accessibilityLabel("Steps by day").accessibilityIdentifier("steps"), 200, 120);
    try std.testing.expectEqualStrings("Steps by day", views.A11yNode.find(a11y.items, "steps").?.label);
}
