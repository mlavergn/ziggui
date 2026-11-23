//! A line chart: series of points in data coordinates drawn as lines across a
//! faint plot, on x and y scales given or taken from the data, with an
//! optional baseline, a caption over the plot and labels at the ends of its x
//! axis. Composed on `Canvas`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_line_chart);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");

/// How opaque a secondary series is, as a fraction of its color's alpha.
const secondary_alpha: f32 = 0.35;
/// How far past the plot a point is placed at most, in points: farther, a
/// clipped segment's ends would lose their precision, while within it a
/// segment's slope across the plot changes by far less than a pixel.
const reach_past_plot: f64 = 1e6;

/// One frame of a line chart, in the build arena: the `Canvas`'s context.
const LineChartFrame = struct {
    const Self = @This();

    /// The series, copied into the build arena (their points are the caller's).
    series: []const mod.ChartSeries,
    /// The x axis's scale.
    x_axis: mod.ChartAxis,
    /// The y axis's scale.
    y_axis: mod.ChartAxis,
    /// Where the baseline crosses the y axis; null for none.
    baseline: ?f32,
    /// The caption over the plot.
    caption: []const u8,
    /// The label at the x axis's start.
    x_start_label: []const u8,
    /// The label at the x axis's end.
    x_end_label: []const u8,
    /// A series' color when it gives none.
    accent: renderer.Color,
    /// The baseline's color.
    separator: renderer.Color,
    /// The theme's label color, which the plot's ground is a faint wash of.
    label: renderer.Color,
    /// The labels' color.
    label_color: renderer.Color,

    /// A frame from the series, the options and the theme's colors, its scales
    /// resolved from the points that will draw (both coordinates finite).
    ///
    /// - `series`: the series, already in the build arena.
    /// - `options`: the scales, baseline and labels.
    /// - `tokens`: the theme's colors.
    /// - Returns: the frame.
    fn init(series: []const mod.ChartSeries, options: mod.LineChartOptions, tokens: views.BuildTokens) Self {
        const nan = std.math.nan(f64);
        var x_lower = nan;
        var x_upper = nan;
        var y_lower = nan;
        var y_upper = nan;
        for (series) |line| {
            for (line.points) |point| {
                if (!Self.drawable(point)) continue;
                // `@min`/`@max` keep the number over a NaN, so the first point seeds them.
                x_lower = @min(x_lower, point.x);
                x_upper = @max(x_upper, point.x);
                y_lower = @min(y_lower, point.y);
                y_upper = @max(y_upper, point.y);
            }
        }
        if (options.baseline) |baseline| {
            if (std.math.isFinite(baseline)) {
                y_lower = @min(y_lower, baseline);
                y_upper = @max(y_upper, baseline);
            }
        }
        const self = Self{
            .series = series,
            .x_axis = mod.ChartAxis.init(options.x_domain, x_lower, x_upper),
            .y_axis = mod.ChartAxis.init(options.y_domain, y_lower, y_upper),
            .baseline = options.baseline,
            .caption = options.caption,
            .x_start_label = options.x_start_label,
            .x_end_label = options.x_end_label,
            .accent = tokens.accent,
            .separator = tokens.separator,
            .label = tokens.label,
            .label_color = tokens.secondary_label,
        };
        return self;
    }

    /// Draws the chart into its frame: the caption, the plot's ground, the
    /// baseline, the secondary series, the primary ones over them, and the x
    /// axis's end labels. A frame with no room for a plot draws nothing.
    ///
    /// - `self`: the frame.
    /// - `graphics`: what it draws with.
    /// - `rect`: the view's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, graphics: *views.GraphicsContext, rect: renderer.Rect) std.mem.Allocator.Error!void {
        const plot = mod.ChartStyle.plot(graphics, rect, self.caption.len > 0, self.x_start_label.len > 0 or self.x_end_label.len > 0);
        if (!mod.ChartStyle.hasRoom(plot)) return;
        try mod.ChartStyle.drawGround(graphics, plot, self.label);
        if (self.baseline) |baseline| {
            if (self.y_axis.contains(baseline)) {
                const y: f32 = @floatCast(@as(f64, plot.maxY()) - self.y_axis.fraction(baseline) * plot.height);
                try graphics.line(.{ .x = plot.x, .y = y }, .{ .x = plot.maxX(), .y = y }, mod.ChartStyle.rule_width, self.separator);
            }
        }
        for ([_]mod.ChartEmphasis{ .secondary, .primary }) |emphasis| {
            for (self.series) |line| {
                if (line.emphasis == emphasis) try self.drawSeries(graphics, plot, line);
            }
        }
        try mod.ChartStyle.drawCaption(graphics, self.caption, rect, self.label_color);
        const axis_y = plot.maxY() + mod.ChartStyle.label_gap;
        if (self.x_start_label.len > 0) try graphics.text(self.x_start_label, mod.ChartStyle.label_size, self.label_color, .{ .x = plot.x, .y = axis_y });
        if (self.x_end_label.len > 0) {
            const width = graphics.textWidth(self.x_end_label, mod.ChartStyle.label_size);
            try graphics.text(self.x_end_label, mod.ChartStyle.label_size, self.label_color, .{ .x = plot.maxX() - width, .y = axis_y });
        }
    }

    /// Draws one series: a line through its points in order, clipped to the
    /// plot, broken at a point that cannot draw; a point alone between breaks
    /// is a dot.
    ///
    /// - `self`: the frame.
    /// - `graphics`: what it draws with.
    /// - `plot`: the plot's rectangle.
    /// - `line`: the series.
    /// - Returns: nothing; propagates allocation failure.
    fn drawSeries(self: *const Self, graphics: *views.GraphicsContext, plot: renderer.Rect, line: mod.ChartSeries) std.mem.Allocator.Error!void {
        const base = line.color orelse self.accent;
        const color = switch (line.emphasis) {
            .primary => base,
            .secondary => base.multiplyAlpha(secondary_alpha),
        };
        var previous: ?[2]f64 = null;
        var run_length: usize = 0;
        for (line.points) |point| {
            const at = if (Self.drawable(point)) self.place(plot, point) else null;
            if (at) |current| {
                if (previous) |start| {
                    if (Self.clip(plot, start, current)) |segment| try graphics.line(segment[0], segment[1], mod.ChartStyle.line_width, color);
                }
                previous = current;
                run_length += 1;
            } else {
                if (run_length == 1) try Self.drawDot(graphics, plot, previous.?, color);
                previous = null;
                run_length = 0;
            }
        }
        if (run_length == 1) try Self.drawDot(graphics, plot, previous.?, color);
    }

    /// Where a point of data lands in the plot.
    ///
    /// - `self`: the frame.
    /// - `plot`: the plot's rectangle.
    /// - `point`: the point, in data coordinates, both finite.
    /// - Returns: the point in the view's coordinates, at most
    ///   `reach_past_plot` past the plot, or null where it is not finite.
    fn place(self: *const Self, plot: renderer.Rect, point: renderer.Point) ?[2]f64 {
        const x = @as(f64, plot.x) + self.x_axis.fraction(point.x) * plot.width;
        const y = @as(f64, plot.maxY()) - self.y_axis.fraction(point.y) * plot.height;
        if (!(std.math.isFinite(x) and std.math.isFinite(y))) return null;
        return .{
            std.math.clamp(x, plot.minX() - reach_past_plot, plot.maxX() + reach_past_plot),
            std.math.clamp(y, plot.minY() - reach_past_plot, plot.maxY() + reach_past_plot),
        };
    }

    /// Draws a lone point as a dot, when it lies in the plot.
    ///
    /// - `graphics`: what it draws with.
    /// - `plot`: the plot's rectangle.
    /// - `at`: the point, in the view's coordinates.
    /// - `color`: the series' color.
    /// - Returns: nothing; propagates allocation failure.
    fn drawDot(graphics: *views.GraphicsContext, plot: renderer.Rect, at: [2]f64, color: renderer.Color) std.mem.Allocator.Error!void {
        const centre = (Self.clip(plot, at, at) orelse return)[0];
        const radius = mod.ChartStyle.line_width;
        try graphics.fill(.{ .x = centre.x - radius, .y = centre.y - radius, .width = 2 * radius, .height = 2 * radius }, radius, color);
    }

    /// Reports whether a point can draw: both its coordinates finite.
    ///
    /// - `point`: the point, in data coordinates.
    /// - Returns: true when it can.
    fn drawable(point: renderer.Point) bool {
        return std.math.isFinite(point.x) and std.math.isFinite(point.y);
    }

    /// The part of a segment inside a rectangle (Liang–Barsky), so a series
    /// past a given domain stops at the plot's edge.
    ///
    /// - `plot`: the rectangle.
    /// - `start`: one end, in the view's coordinates.
    /// - `end`: the other end.
    /// - Returns: the ends of the part inside, or null when none is.
    fn clip(plot: renderer.Rect, start: [2]f64, end: [2]f64) ?[2]renderer.Point {
        const delta = [2]f64{ end[0] - start[0], end[1] - start[1] };
        // Per edge (left, right, top, bottom): how the segment heads at it, and how far inside it starts.
        const heading = [4]f64{ -delta[0], delta[0], -delta[1], delta[1] };
        const room = [4]f64{ start[0] - plot.minX(), plot.maxX() - start[0], start[1] - plot.minY(), plot.maxY() - start[1] };
        var enter: f64 = 0;
        var leave: f64 = 1;
        for (heading, room) |toward, inside| {
            if (toward == 0) {
                if (inside < 0) return null;
                continue;
            }
            const crossing = inside / toward;
            if (toward < 0) {
                if (crossing > leave) return null;
                enter = @max(enter, crossing);
            } else {
                if (crossing < enter) return null;
                leave = @min(leave, crossing);
            }
        }
        return .{
            .{ .x = @floatCast(start[0] + enter * delta[0]), .y = @floatCast(start[1] + enter * delta[1]) },
            .{ .x = @floatCast(start[0] + leave * delta[0]), .y = @floatCast(start[1] + leave * delta[1]) },
        };
    }

    /// What the chart says to accessibility: "Line chart", then its caption
    /// and its x axis's span, where it has them.
    ///
    /// - `self`: the frame.
    /// - `allocator`: the build arena.
    /// - Returns: the description; propagates allocation failure.
    fn describe(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(allocator, "Line chart");
        if (self.caption.len > 0) try text.print(allocator, ", {s}", .{self.caption});
        if (self.x_start_label.len > 0 and self.x_end_label.len > 0) {
            try text.print(allocator, ", {s} to {s}", .{ self.x_start_label, self.x_end_label });
        } else if (self.x_start_label.len > 0 or self.x_end_label.len > 0) {
            try text.print(allocator, ", {s}{s}", .{ self.x_start_label, self.x_end_label });
        }
        return text.items;
    }
};

/// A line chart of `series` drawn into its frame, as Swift Charts' `Chart` of
/// `LineMark`s: each series a line through its points (in data coordinates,
/// left to right), the primary ones in the accent over the secondary ones,
/// faint; on a plot with a faint ground; under a caption and over labels at
/// the x axis's ends, when `options` gives them. It fills the space it is
/// offered, so give it a frame (`.frameMaxWidth().frameHeight(96)`).
/// Accessibility reads it as an image named "Line chart" and its caption and
/// axis labels; `.accessibilityLabel` names it otherwise. Points that are not
/// finite are skipped, and no series, a lone point or a frame too small for a
/// plot draw what they can.
///
/// - `series`: the lines, copied into the build arena; their points must last
///   until the frame is drawn.
/// - `options`: the scales, baseline and labels (`.{}` for none).
/// - Returns: the view.
pub fn LineChart(series: []const mod.ChartSeries, options: mod.LineChartOptions) views.View {
    const scope = views.BuildScope.shared();
    const allocator = scope.allocator();
    const frame = allocator.create(LineChartFrame) catch @panic("oom");
    frame.* = LineChartFrame.init(allocator.dupe(mod.ChartSeries, series) catch @panic("oom"), options, scope.tokens());
    const description = frame.describe(allocator) catch @panic("oom");
    return views.Canvas(LineChartFrame, frame, LineChartFrame.draw).accessibilityLabel(description);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a line chart draws its series across the plot, secondary first and faint" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const rising = [_]renderer.Point{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 } };
    const falling = [_]renderer.Point{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = -1 } };
    const series = [_]mod.ChartSeries{ .{ .points = &rising }, .{ .points = &falling, .emphasis = .secondary } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, LineChart(&series, .{ .y_domain = .{ .symmetric = true }, .baseline = 0 }), 100, 60);
    const tokens = views.BuildScope.shared().tokens();
    var lines: std.ArrayList(renderer.LineCommand) = .empty;
    defer lines.deinit(std.testing.allocator);
    try mod.ChartProbe.lines(&display_list, &lines);
    // The baseline across the middle, then the secondary series, then the primary.
    try std.testing.expectEqual(3, lines.items.len);
    try std.testing.expectEqual(30, lines.items[0].start.y);
    try std.testing.expectEqual(100, lines.items[0].end.x);
    try std.testing.expectEqual(tokens.separator, lines.items[0].color);
    try std.testing.expectEqual(60, lines.items[1].end.y);
    try std.testing.expectApproxEqAbs(tokens.accent.a * secondary_alpha, lines.items[1].color.a, 1e-6);
    try std.testing.expectEqual(renderer.Point{ .x = 0, .y = 30 }, lines.items[2].start);
    try std.testing.expectEqual(renderer.Point{ .x = 100, .y = 0 }, lines.items[2].end);
    try std.testing.expectEqual(tokens.accent, lines.items[2].color);
    try std.testing.expectEqual(mod.ChartStyle.line_width, lines.items[2].width);
    // With no labels the plot's ground fills the frame.
    try std.testing.expectEqual(renderer.Rect{ .x = 0, .y = 0, .width = 100, .height = 60 }, display_list.commands.items[0].fillRoundedRect.rect);
}

test "a line chart's labels take their room from the plot, and its color is its own" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const points = [_]renderer.Point{ .{ .x = 0, .y = 1 }, .{ .x = 4, .y = 1 } };
    const series = [_]mod.ChartSeries{.{ .points = &points, .color = renderer.Color.red }};
    const options: mod.LineChartOptions = .{ .caption = "±2.14 %", .x_start_label = "centre", .x_end_label = "r max", .y_domain = .{ .lower = 0, .upper = 2 } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, LineChart(&series, options), 200, 100);
    const context = environment.context();
    const band = renderer.TextShaper.init(context.cache.face).lineHeight(mod.ChartStyle.label_size) + mod.ChartStyle.label_gap;
    const plot = display_list.commands.items[0].fillRoundedRect.rect;
    try std.testing.expectEqual(band, plot.y);
    try std.testing.expectApproxEqAbs(100 - 2 * band, plot.height, 1e-4);
    var glyphs: usize = 0;
    for (display_list.commands.items) |command| {
        switch (command) {
            .line => |segment| {
                try std.testing.expectEqual(renderer.Color.red, segment.color);
                try std.testing.expectApproxEqAbs(plot.midY(), segment.start.y, 1e-4);
            },
            .glyph => glyphs += 1,
            else => {},
        }
    }
    try std.testing.expect(glyphs > 0);
    // Accessibility reads it as an image named by its caption and axis.
    try std.testing.expectEqual(1, a11y.items.len);
    try std.testing.expectEqual(views.A11yRole.image, a11y.items[0].role);
    try std.testing.expectEqualStrings("Line chart, ±2.14 %, centre to r max", a11y.items[0].label);
}

test "a line chart names itself as the app says" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const view = LineChart(&.{}, .{}).accessibilityLabel("Distortion").accessibilityIdentifier("lens-chart");
    try mod.ChartProbe.render(&environment, &display_list, &a11y, view, 80, 40);
    try std.testing.expectEqualStrings("Distortion", views.A11yNode.find(a11y.items, "lens-chart").?.label);
}

test "a line chart skips what cannot draw and stops at its plot's edge" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    // A run of two, a NaN break, a lone point (a dot), an infinity, then a run
    // leaving the y domain far above and below the plot.
    const broken = [_]renderer.Point{
        .{ .x = 0, .y = 0.5 }, .{ .x = 1, .y = 0.6 }, .{ .x = nan, .y = 0.2 }, .{ .x = 2, .y = 0.4 },
        .{ .x = 3, .y = inf }, .{ .x = 4, .y = 0.5 }, .{ .x = 5, .y = 1e30 },  .{ .x = 6, .y = -std.math.floatMax(f32) },
        .{ .x = 7, .y = 0.5 },
    };
    const nothing = [_]renderer.Point{ .{ .x = nan, .y = nan }, .{ .x = -inf, .y = 1 } };
    const series = [_]mod.ChartSeries{ .{ .points = &broken }, .{ .points = &nothing }, .{ .points = &.{} } };
    try mod.ChartProbe.render(&environment, &display_list, &a11y, LineChart(&series, .{ .x_domain = .{ .lower = 0, .upper = 7 }, .y_domain = .{ .lower = 0, .upper = 1 }, .baseline = 5 }), 140, 80);
    try mod.ChartProbe.expectInside(&display_list, .{ .x = 0, .y = 0, .width = 140, .height = 80 });
    var lines: usize = 0;
    var dots: usize = 0;
    for (display_list.commands.items[1..]) |command| {
        switch (command) {
            .line => lines += 1,
            .fillRoundedRect => dots += 1,
            else => {},
        }
    }
    // The baseline lies outside the domain; the first run's segment, the lone
    // point's dot, and the clipped segments into, between and out of the far values.
    try std.testing.expectEqual(1, dots);
    try std.testing.expectEqual(4, lines);
}

test "a line chart with nothing to chart, one point, or no room draws safely" {
    var environment = views.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var a11y: std.ArrayList(views.A11yNode) = .empty;
    const one = [_]renderer.Point{.{ .x = 3, .y = 3 }};
    const flat = [_]renderer.Point{ .{ .x = 0, .y = 2 }, .{ .x = 0, .y = 2 } };
    const sets = [_][]const mod.ChartSeries{ &.{}, &.{.{ .points = &one }}, &.{.{ .points = &flat }} };
    const sizes = [_][2]f32{ .{ 0, 0 }, .{ 1, 1 }, .{ 3, 200 }, .{ 200, 3 }, .{ 120, 60 }, .{ -5, -5 }, .{ std.math.nan(f32), 10 } };
    const options: mod.LineChartOptions = .{ .caption = "scale", .x_start_label = "start", .x_end_label = "end" };
    for (sets) |series| {
        for (sizes) |size| {
            display_list.clearCommands();
            try mod.ChartProbe.render(&environment, &display_list, &a11y, LineChart(series, options), size[0], size[1]);
            for (display_list.commands.items) |command| {
                if (command == .line) {
                    try std.testing.expect(std.math.isFinite(command.line.start.x) and std.math.isFinite(command.line.end.y));
                }
            }
        }
    }
    // One point in a roomy frame is a dot at the middle of its plot.
    display_list.clearCommands();
    try mod.ChartProbe.render(&environment, &display_list, &a11y, LineChart(&.{.{ .points = &one }}, .{}), 120, 60);
    const dot = display_list.commands.items[1].fillRoundedRect.rect;
    try std.testing.expectEqual(renderer.Point{ .x = 60, .y = 30 }, dot.center());
}
