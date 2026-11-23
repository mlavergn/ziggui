//! The look every chart here shares: its labels, its plot's ground and the
//! bands its caption and axis labels take from the plot.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_style);
const renderer = @import("renderer");
const views = @import("views");

/// The look every chart here shares (`LineChart`, `BarChart`), so they read
/// as one family side by side: 10pt labels in the secondary label color, a
/// plot filling the frame on a faint ground with 4pt corners, a caption band
/// over it and an axis band under it, each given to the plot when empty.
pub const ChartStyle = struct {
    const Self = @This();

    /// The caption's and labels' size, in points.
    pub const label_size: f32 = 10;
    /// The room between a label and the plot, in points.
    pub const label_gap: f32 = 2;
    /// A line's width (a series, a line through bars), in points.
    pub const line_width: f32 = 1.5;
    /// A reference line's width (a baseline, a grid line, a zero line), in points.
    pub const rule_width: f32 = 1;
    /// How opaque the plot's ground is, as a fraction of the label color's alpha.
    pub const ground_alpha: f32 = 0.04;
    /// The plot's corner radius, in points.
    pub const plot_radius: f32 = 4;

    /// The height a band of labels takes from the plot: a line of label text
    /// and its gap.
    ///
    /// - `graphics`: what the chart draws with.
    /// - Returns: the band's height, in points.
    pub fn band(graphics: *const views.GraphicsContext) f32 {
        return graphics.lineHeight(Self.label_size) + Self.label_gap;
    }

    /// The plot's rectangle: the frame less a caption band over it and an axis
    /// band under it, each only when the chart has them.
    ///
    /// - `graphics`: what the chart draws with.
    /// - `rect`: the chart's frame.
    /// - `captioned`: whether a caption goes over the plot.
    /// - `labelled`: whether labels go under the plot.
    /// - Returns: the plot, which may have no room (check before drawing).
    pub fn plot(graphics: *const views.GraphicsContext, rect: renderer.Rect, captioned: bool, labelled: bool) renderer.Rect {
        const height = Self.band(graphics);
        const caption_height: f32 = if (captioned) height else 0;
        const axis_height: f32 = if (labelled) height else 0;
        return .{ .x = rect.x, .y = rect.y + caption_height, .width = rect.width, .height = rect.height - caption_height - axis_height };
    }

    /// Reports whether a plot has room to draw in (a frame too small, or not a
    /// number, has none).
    ///
    /// - `area`: the plot's rectangle.
    /// - Returns: true when it is wider and taller than nothing.
    pub fn hasRoom(area: renderer.Rect) bool {
        return area.width > 0 and area.height > 0;
    }

    /// Fills the plot's faint ground, its corners rounded.
    ///
    /// - `graphics`: what the chart draws with.
    /// - `area`: the plot's rectangle.
    /// - `label`: the theme's label color, which the ground is a faint wash of.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawGround(graphics: *views.GraphicsContext, area: renderer.Rect, label: renderer.Color) std.mem.Allocator.Error!void {
        try graphics.fill(area, @min(Self.plot_radius, area.width / 2, area.height / 2), label.multiplyAlpha(Self.ground_alpha));
    }

    /// Draws the caption at the top-left of the chart's frame, when it has one.
    ///
    /// - `graphics`: what the chart draws with.
    /// - `caption`: the caption; empty for none.
    /// - `rect`: the chart's frame.
    /// - `color`: the labels' color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawCaption(graphics: *views.GraphicsContext, caption: []const u8, rect: renderer.Rect, color: renderer.Color) std.mem.Allocator.Error!void {
        if (caption.len > 0) try graphics.text(caption, Self.label_size, color, rect.origin());
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
