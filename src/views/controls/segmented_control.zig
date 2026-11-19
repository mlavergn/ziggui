//! A segmented control composed from stacks and text: a neutral thumb on a
//! track, never accent-colored.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_segmented_control);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The text size of a segment's title, in points.
const segment_text_size: f32 = 13;

/// A segment's height, in points; the track adds `track_inset` above and below.
const segment_height: f32 = 20;

/// The space on each side of a segment's title, in points.
const segment_padding: f32 = 10;

/// An icon segment's glyph size, in points.
const icon_size: f32 = 14;

/// The chrome every segmented control shares: each segment's, and the
/// track under them.
const Segments = struct {
    const Self = @This();

    /// One segment's chrome around its content: `segment_height` tall, stretched
    /// to its share, rounded, tapped to select it; the thumb when chosen, else a
    /// hover fill.
    ///
    /// - `content`: the title or icon.
    /// - `selection`: the control's selection.
    /// - `index`: the segment's index.
    /// - `chosen`: it is the selected one.
    /// - `tokens`: the frame's colors.
    /// - Returns: the segment.
    fn chrome(content: mod.View, selection: mod.Binding(i64), index: usize, chosen: bool, tokens: mod.BuildTokens) mod.View {
        const framed = content
            .frameHeight(segment_height)
            .frameMaxWidth()
            .cornerRadius(5)
            .onTap(mod.Callback.select(selection, @intCast(index)));
        return if (chosen) framed.background(tokens.raised).border(tokens.separator, 1) else framed.hoverFill(tokens.hover);
    }

    /// The track under the segments: inset, filled, rounded, at its ideal width.
    ///
    /// - `segments`: the segments, in the build arena.
    /// - `tokens`: the frame's colors.
    /// - Returns: the control.
    fn track(segments: []const mod.View, tokens: mod.BuildTokens) mod.View {
        return mod.StackBuilder.fromSlice(.horizontal, mod.ControlMetrics.segment_track_inset, .center, segments)
            .padding(mod.ControlMetrics.segment_track_inset)
            .background(tokens.quaternary_fill)
            .cornerRadius(6)
            .fixedSize();
    }
};

/// A segmented control over a selected index: a `quaternary_fill` track
/// (radius 6) of equal-width segments, the selected one a neutral thumb (the
/// `raised` ground, radius 5, a hairline border) with its title in `label` at
/// medium weight, the others in `secondary_label` with a hover fill. Tapping
/// a segment sets `selection` to its index. 24pt tall, 13pt titles. It keeps
/// its ideal width, every segment as wide as the widest title, unless the
/// caller stretches it with `.frameMaxWidth()`, which shares the width out
/// equally.
///
/// - `selection`: the selected segment's index.
/// - `options`: the segments' titles.
/// - Returns: the control.
pub fn SegmentedControl(selection: mod.Binding(i64), options: []const []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    const segments = allocator.alloc(mod.View, options.len) catch @panic("oom");
    const selected = selection.get();
    for (segments, options, 0..) |*segment, option, index| {
        const chosen = selected == @as(i64, @intCast(index));
        // Every title, hidden at the selected weight, under the visible one:
        // a depth stack is as wide as its widest child, so the segments come
        // out equal without measuring text while the view is built.
        const layers = allocator.alloc(mod.View, options.len + 1) catch @panic("oom");
        for (layers[0..options.len], options) |*layer, title| {
            layer.* = mod.Text(title).weight(.medium).opacity(0).accessibilityHidden(true);
        }
        layers[options.len] = mod.Text(option)
            .weight(if (chosen) .medium else .regular)
            .foreground(if (chosen) tokens.label else tokens.secondary_label);
        const content = mod.StackBuilder.fromSlice(.depth, 0, .center, layers)
            .size(segment_text_size)
            .paddingInsets(.{ .leading = segment_padding, .trailing = segment_padding });
        segment.* = Segments.chrome(content, selection, index, chosen, tokens);
    }
    return Segments.track(segments, tokens);
}

/// A segmented control of icons over a selected index: `SegmentedControl`'s
/// track, thumb and hover fill, each segment its Lucide icon (14pt, `label`
/// when selected, `secondary_label` otherwise) in a 32pt-wide segment, its
/// title the segment's accessibility label and hover hint. Tapping a segment
/// sets `selection` to its index; `.disabled(true)` ignores taps. 24pt tall;
/// it keeps its ideal width unless the caller stretches it with
/// `.frameMaxWidth()`, which shares the width out equally.
///
/// - `selection`: the selected segment's index.
/// - `segments`: the segments' icons and titles.
/// - Returns: the control.
pub fn IconSegmentedControl(selection: mod.Binding(i64), segments: []const mod.IconSegment) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    const views = allocator.alloc(mod.View, segments.len) catch @panic("oom");
    const selected = selection.get();
    for (views, segments, 0..) |*view, segment, index| {
        const chosen = selected == @as(i64, @intCast(index));
        // Padded, not framed: the chrome's frame stretches it.
        const content = mod.Icon(segment.icon, icon_size, if (chosen) tokens.label else tokens.secondary_label)
            .paddingInsets(.{ .leading = (mod.ControlMetrics.icon_segment_width - icon_size) / 2, .trailing = (mod.ControlMetrics.icon_segment_width - icon_size) / 2 });
        view.* = Segments.chrome(content, selection, index, chosen, tokens)
            .accessibilityLabel(segment.title)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen })
            .help(segment.title);
    }
    return Segments.track(views, tokens);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a segmented control sizes to its titles, stretches on request, and selects on tap" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const options = [_][]const u8{ "Request", "Response", "Headers" };

    window.begin(renderer.MacosTheme.light);
    const compact = mod.HStack(.{ SegmentedControl(selection.binding(), &options), mod.Spacer() });
    window.end();
    var frame = try window.render(compact, 600, 24);
    defer frame.deinit();
    // The track ends well short of the row's far edge.
    try std.testing.expect(frame.at(590, 12).r > 0.99);
    try std.testing.expect(frame.at(1, 12).r < 0.99);

    window.begin(renderer.MacosTheme.light);
    const stretched = SegmentedControl(selection.binding(), &options).frameMaxWidth();
    window.end();
    var wide = try window.render(stretched, 600, 24);
    defer wide.deinit();
    // Stretched, the track reaches the far edge, and the last third is the last segment.
    try std.testing.expect(wide.at(597, 12).r < 0.99);
    try std.testing.expect(window.tap(.{ .x = 550, .y = 12 }));
    try std.testing.expectEqual(@as(i64, 2), selection.get());
}

test "an icon segmented control draws one square-ish segment per icon, selects on tap, and ignores taps when disabled" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const segments = [_]mod.IconSegment{ .{ .icon = .gitBranch, .title = "Git" }, .{ .icon = .code, .title = "Files" } };

    window.begin(renderer.MacosTheme.light);
    const compact = mod.HStack(.{ IconSegmentedControl(selection.binding(), &segments), mod.Spacer() });
    window.end();
    var frame = try window.render(compact, 300, 24);
    defer frame.deinit();
    // Two 32pt segments and the track: well short of the row's far edge.
    try std.testing.expect(frame.at(1, 12).r < 0.99);
    try std.testing.expect(frame.at(120, 12).r > 0.99);
    try std.testing.expect(window.tap(.{ .x = 52, .y = 12 }));
    try std.testing.expectEqual(@as(i64, 1), selection.get());

    window.begin(renderer.MacosTheme.light);
    const off = mod.HStack(.{ IconSegmentedControl(selection.binding(), &segments).disabled(true), mod.Spacer() });
    window.end();
    var disabled = try window.render(off, 300, 24);
    defer disabled.deinit();
    _ = window.tap(.{ .x = 18, .y = 12 });
    try std.testing.expectEqual(@as(i64, 1), selection.get());
}
