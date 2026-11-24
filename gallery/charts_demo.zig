//! The Charts section: `LineChart` and what it takes, card by card: several
//! series with one primary, its scales (symmetric about a baseline, or a
//! domain given), a line broken where readings are missing, a chart built
//! from two sliders each frame, and sparklines with no caption or labels;
//! then `BarChart`: a week of steps with a grid and a line through the bars,
//! and a year's profit with its losses below zero, each bar colored.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_charts_demo);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The Charts section's cards and the state of the chart its sliders drive.
pub const ChartsDemo = struct {
    const Self = @This();

    /// A month's visitors this year (thousands), January (1) to December (12).
    const visitors_this_year = Self.months(.{ 42, 45, 51, 58, 63, 71, 76, 74, 69, 61, 55, 60 });
    /// A month's visitors last year (thousands), the faint comparison.
    const visitors_last_year = Self.months(.{ 38, 40, 44, 47, 52, 58, 64, 66, 60, 54, 49, 52 });
    /// The year's target (thousands): one flat line, its two ends.
    const visitors_target = [_]ziggui.Point{ .{ .x = 1, .y = 65 }, .{ .x = 12, .y = 65 } };
    /// A lens's distortion from the centre (0) to the edge (1), as a fraction
    /// of the radius, swinging out then back past zero.
    const lens_forward = Self.distortion(1);
    /// The lens's inverse distortion, the forward's near mirror.
    const lens_inverse = Self.distortion(-0.92);
    /// A processor's load (%) sampled each second for a minute.
    const processor_load = Self.load();
    /// A day of readings (°C) every two hours: a gap where the sensor dropped
    /// out (NaN), and a reading alone between two gaps.
    const day_readings = [_]ziggui.Point{
        .{ .x = 0, .y = 11 },                .{ .x = 2, .y = 9.5 },   .{ .x = 4, .y = 8.8 },                .{ .x = 6, .y = 10.2 },
        .{ .x = 8, .y = std.math.nan(f32) }, .{ .x = 10, .y = 17.5 }, .{ .x = 12, .y = std.math.nan(f32) }, .{ .x = 14, .y = 21.4 },
        .{ .x = 16, .y = 20.1 },             .{ .x = 18, .y = 17.2 }, .{ .x = 20, .y = 14.6 },              .{ .x = 22, .y = 12.9 },
        .{ .x = 24, .y = 11.8 },
    };
    /// A week of steps (thousands), a bar a day.
    const week_steps = [_]f32{ 3.5, 6.0, 4.5, 8.0, 5.5, 9.0, 7.0 };
    /// The day under each of `week_steps`.
    const week_days = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    /// A year's profit (thousands) a month, three months at a loss.
    const year_profit = [_]f32{ 4.2, 3.1, -1.8, 2.6, 5.0, -0.7, -2.4, 1.9, 3.8, 6.1, 4.4, 7.2 };
    /// The month under each of `year_profit`, its initial.
    const year_months = [_][]const u8{ "J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D" };
    /// How opaque a profit bar is, as a fraction of its color's alpha.
    const profit_alpha: f32 = 0.7;
    /// How many samples the sliders' wave is drawn through.
    const wave_samples = 121;
    /// How many prices each sparkline shows.
    const ticker_samples = 32;
    /// The sparklines' tickers: a name and the prices it walked through,
    /// made at compile time from a seed, a start and a drift a step.
    const tickers = [_]struct { name: []const u8, prices: [ticker_samples]ziggui.Point }{
        .{ .name = "ZIG", .prices = Self.walk(7, 41.5, 0.35) },
        .{ .name = "GUI", .prices = Self.walk(19, 128, -0.9) },
        .{ .name = "SDL", .prices = Self.walk(3, 12.4, 0.05) },
        .{ .name = "GPU", .prices = Self.walk(31, 77, 0.6) },
    };

    /// The wave's frequency, in cycles across the chart.
    frequency: ziggui.State(f32),
    /// How fast the wave dies away across the chart.
    damping: ziggui.State(f32),

    /// Makes the demo's state: a wave of three cycles, damped by 2.5.
    ///
    /// - `allocator`: what the state keeps its observers with.
    /// - Returns: the demo.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .frequency = ziggui.State(f32).init(allocator, 3),
            .damping = ziggui.State(f32).init(allocator, 2.5),
        };
        return self;
    }

    /// Releases the demo's state.
    ///
    /// - `self`: the demo.
    pub fn deinit(self: *Self) void {
        self.damping.deinit();
        self.frequency.deinit();
    }

    /// The section's cards, top to bottom.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn panel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.seriesCard(theme),
            Self.scalesCard(theme),
            Self.gapsCard(theme),
            self.liveCard(theme),
            Self.sparklinesCard(theme),
            Self.barsCard(theme),
            Self.signedBarsCard(theme),
        }).spacing(16);
    }

    /// The series card: this year's visitors over last year's, faint, and a
    /// target in a color of its own, from zero up.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn seriesCard(theme: ziggui.Theme) ziggui.View {
        const series = [_]ziggui.ChartSeries{
            .{ .points = &visitors_last_year, .emphasis = .secondary },
            .{ .points = &visitors_target, .color = ziggui.BuildScope.shared().tokens().warning },
            .{ .points = &visitors_this_year },
        };
        return gallery.Card.view(theme, "Several series: this year over last year, faint, and a target", "ziggui.LineChart · ziggui.ChartSeries · ziggui.ChartEmphasis", ziggui.LineChart(&series, .{
            .y_domain = .{ .lower = 0 },
            .caption = "Visitors, thousands",
            .x_start_label = "Jan",
            .x_end_label = "Dec",
        }).frameMaxWidth().frameHeight(140));
    }

    /// The scales card: a lens's distortion over its inverse on a scale
    /// symmetric about the baseline at zero, beside a processor's load on a
    /// domain given, 0 to 100 %, whatever it read.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn scalesCard(theme: ziggui.Theme) ziggui.View {
        const lens = [_]ziggui.ChartSeries{
            .{ .points = &lens_inverse, .emphasis = .secondary },
            .{ .points = &lens_forward },
        };
        const processor = [_]ziggui.ChartSeries{.{ .points = &processor_load, .color = ziggui.BuildScope.shared().tokens().added }};
        return gallery.Card.view(theme, "Scales: symmetric about a baseline, or a domain given", "ziggui.ChartDomain · LineChartOptions.x_domain · .y_domain · .baseline", ziggui.HStack(.{
            ziggui.LineChart(&lens, .{
                .x_domain = .{ .lower = 0, .upper = 1 },
                .y_domain = .{ .symmetric = true },
                .baseline = 0,
                .caption = "±2.13 %",
                .x_start_label = "centre",
                .x_end_label = "r max",
            }).frameMaxWidth().frameHeight(110),
            ziggui.LineChart(&processor, .{
                .y_domain = .{ .lower = 0, .upper = 100 },
                .baseline = 50,
                .caption = "Processor, 0–100 %",
                .x_start_label = "−60 s",
                .x_end_label = "now",
            }).frameMaxWidth().frameHeight(110),
        }).spacing(16));
    }

    /// The gaps card: a day of readings broken where the sensor dropped out,
    /// and a dot where one reading stands alone.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn gapsCard(theme: ziggui.Theme) ziggui.View {
        const day = [_]ziggui.ChartSeries{.{ .points = &day_readings, .color = ziggui.Color.fromRgb8(230, 126, 34) }};
        return gallery.Card.view(theme, "Gaps: a reading that is not a number breaks the line", "ChartSeries.points · LineChartOptions.caption · .x_start_label · .x_end_label", ziggui.LineChart(&day, .{
            .y_domain = .{ .lower = 0 },
            .caption = "Temperature, °C",
            .x_start_label = "00:00",
            .x_end_label = "24:00",
        }).frameMaxWidth().frameHeight(110));
    }

    /// The live card: a damped wave built in the build arena each frame from
    /// the two sliders under it, on a scale symmetric about zero.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn liveCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const frequency = self.frequency.get();
        const damping = self.damping.get();
        const points = allocator.alloc(ziggui.Point, wave_samples) catch @panic("oom");
        for (points, 0..) |*point, index| {
            const x = @as(f32, @floatFromInt(index)) / (wave_samples - 1);
            point.* = .{ .x = x, .y = @exp(-damping * x) * @cos(2 * std.math.pi * frequency * x) };
        }
        const envelope = allocator.alloc(ziggui.Point, wave_samples) catch @panic("oom");
        for (envelope, points) |*point, wave| point.* = .{ .x = wave.x, .y = @exp(-damping * wave.x) };
        const series = [_]ziggui.ChartSeries{
            .{ .points = envelope, .emphasis = .secondary },
            .{ .points = points },
        };
        const caption = allocator.print("{d:.1} cycles, damped by {d:.1}", .{ frequency, damping }) catch @panic("oom");
        return gallery.Card.view(theme, "Built each frame: drag the sliders", "ChartSeries in the build arena", ziggui.VStack(.{
            ziggui.LineChart(&series, .{
                .y_domain = .{ .symmetric = true },
                .baseline = 0,
                .caption = caption,
                .x_start_label = "0",
                .x_end_label = "1",
            }).frameMaxWidth().frameHeight(130),
            Self.sliderRow("Frequency", ziggui.Slider(self.frequency.binding(), 0.5, 8)),
            Self.sliderRow("Damping", ziggui.Slider(self.damping.binding(), 0, 6)),
        }).spacing(10));
    }

    /// The sparklines card: a row per ticker, its name, a small chart with no
    /// caption or labels, so the plot takes all its frame, its last price and
    /// the change across the chart, green up and red down.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn sparklinesCard(theme: ziggui.Theme) ziggui.View {
        var rows: [tickers.len]ziggui.View = undefined;
        for (&rows, 0..) |*row, index| row.* = Self.sparklineRow(index);
        const shown = ziggui.BuildScope.shared().allocator().dupe(ziggui.View, &rows) catch @panic("oom");
        return gallery.Card.view(theme, "Sparklines: no caption or labels, so the plot takes the frame", "ziggui.LineChartOptions", ziggui.StackBuilder.fromSlice(.vertical, 8, .leading, shown).frameMaxWidth());
    }

    /// The bars card: a week of steps, ruled into four bands, with a line
    /// through the bars' tops.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn barsCard(theme: ziggui.Theme) ziggui.View {
        var marks: [week_steps.len]ziggui.BarMark = undefined;
        for (&marks, week_steps, week_days) |*mark, steps, day| mark.* = .{ .label = day, .value = steps };
        return gallery.Card.view(theme, "Bars: a week of steps, a grid, and a line through the bars", "ziggui.BarChart · ziggui.BarMark · ziggui.BarChartOptions", ziggui.BarChart(&marks, .{
            .grid_divisions = 4,
            .overlay_line = true,
            .caption = "Steps, thousands",
        }).frameMaxWidth().frameHeight(150));
    }

    /// The signed bars card: a year's profit, its losses growing down from
    /// the zero line, each bar green or red by its own color.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn signedBarsCard(theme: ziggui.Theme) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        var marks: [year_profit.len]ziggui.BarMark = undefined;
        for (&marks, year_profit, year_months) |*mark, profit, month| {
            const color = if (profit >= 0) tokens.added else tokens.removed;
            mark.* = .{ .label = month, .value = profit, .color = color.multiplyAlpha(profit_alpha) };
        }
        return gallery.Card.view(theme, "Bars below zero, each in a color of its own", "BarMark.color · a value below zero", ziggui.BarChart(&marks, .{
            .grid_divisions = 3,
            .caption = "Profit, thousands",
        }).frameMaxWidth().frameHeight(130));
    }

    /// One sparkline row: the ticker's name, its chart, its last price and
    /// its change.
    ///
    /// - `index`: the ticker, an index into `tickers`.
    /// - Returns: the row.
    fn sparklineRow(index: usize) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        const allocator = ziggui.BuildScope.shared().allocator();
        const ticker = &tickers[index];
        const first = ticker.prices[0].y;
        const last = ticker.prices[ticker_samples - 1].y;
        const change = (last - first) / first * 100;
        const color = if (change >= 0) tokens.added else tokens.removed;
        const series = [_]ziggui.ChartSeries{.{ .points = &ticker.prices, .color = color }};
        const price = allocator.print("{d:.2}", .{last}) catch @panic("oom");
        const delta = allocator.print("{s}{d:.1} %", .{ if (change >= 0) "+" else "−", @abs(change) }) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Text(ticker.name).monospaced().frameWidth(48).frameAlign(.leading),
            ziggui.LineChart(&series, .{}).frame(160, 28),
            ziggui.Spacer(),
            ziggui.Text(price).monospaced(),
            ziggui.Text(delta).monospaced().foregroundStyle(color).frameWidth(72).frameAlign(.trailing),
        }).spacing(12).frameMaxWidth();
    }

    /// A slider with its label before it.
    ///
    /// - `title`: the label.
    /// - `slider`: the slider.
    /// - Returns: the row.
    fn sliderRow(title: []const u8, slider: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title).frameWidth(80).frameAlign(.leading), slider.frameMaxWidth() }).spacing(12).frameMaxWidth();
    }

    /// A year's monthly values as points, January at x = 1.
    ///
    /// - `values`: the twelve values.
    /// - Returns: the points.
    fn months(comptime values: [12]f32) [12]ziggui.Point {
        var points: [12]ziggui.Point = undefined;
        for (&points, values, 0..) |*point, value, index| point.* = .{ .x = @floatFromInt(index + 1), .y = value };
        return points;
    }

    /// A lens's distortion table: 24 samples from its centre to its edge,
    /// peaking at 2.13 % of the radius.
    ///
    /// - `scale`: what the forward table is multiplied by (negative mirrors it).
    /// - Returns: the samples, x from 0 to 1.
    fn distortion(comptime scale: f32) [24]ziggui.Point {
        var points: [24]ziggui.Point = undefined;
        for (&points, 0..) |*point, index| {
            const radius = @as(f32, @floatFromInt(index)) / 23;
            // r² rising, r⁴ pulling it back: a peak of 2.13 % at r ≈ 0.8.
            const value = 0.0214 * (2.08 * radius * radius - 1.62 * radius * radius * radius * radius) / 0.668;
            point.* = .{ .x = radius, .y = scale * value };
        }
        return points;
    }

    /// A minute of a processor's load: a slow swell with a burst in its
    /// middle, between 0 and 100 %.
    ///
    /// - Returns: the samples, x from 0 to 59 seconds.
    fn load() [60]ziggui.Point {
        @setEvalBranchQuota(10_000);
        var points: [60]ziggui.Point = undefined;
        for (&points, 0..) |*point, index| {
            const second: f32 = @floatFromInt(index);
            const swell = 30 + 12 * @sin(second / 9);
            const burst: f32 = if (index >= 24 and index < 34) 45 * @sin((second - 24) / 10 * std.math.pi) else 0;
            const jitter = 6 * @sin(second * 2.7) * @cos(second * 1.3);
            point.* = .{ .x = second, .y = std.math.clamp(swell + burst + jitter, 0, 100) };
        }
        return points;
    }

    /// A price's random walk, the same on every run: each step adds `drift`
    /// and a jolt from a linear congruential generator seeded by `seed`.
    ///
    /// - `seed`: where the generator starts.
    /// - `start`: the first price.
    /// - `drift`: what each step adds besides its jolt.
    /// - Returns: the prices, x from 0.
    fn walk(comptime seed: u32, comptime start: f32, comptime drift: f32) [ticker_samples]ziggui.Point {
        @setEvalBranchQuota(10_000);
        var points: [ticker_samples]ziggui.Point = undefined;
        var state: u32 = seed;
        var price = start;
        for (&points, 0..) |*point, index| {
            point.* = .{ .x = @floatFromInt(index), .y = price };
            state = state *% 1_664_525 +% 1_013_904_223;
            const jolt = (@as(f32, @floatFromInt(state >> 16)) / 65_535 - 0.5) * start * 0.06;
            price = @max(price + drift + jolt, 0.01);
        }
        return points;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the processor's load stays within its domain, and every ticker's prices stay positive" {
    for (ChartsDemo.processor_load) |point| try std.testing.expect(point.y >= 0 and point.y <= 100);
    for (ChartsDemo.tickers) |ticker| for (ticker.prices) |point| try std.testing.expect(point.y > 0);
}
