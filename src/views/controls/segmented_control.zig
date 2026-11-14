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

/// The track's inset around its segments, in points.
const track_inset: f32 = 2;

/// The space on each side of a segment's title, in points.
const segment_padding: f32 = 10;

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
            .paddingInsets(.{ .leading = segment_padding, .trailing = segment_padding })
            .frameHeight(segment_height)
            .frameMaxWidth()
            .cornerRadius(5)
            .onTap(mod.Callback.select(selection, @intCast(index)));
        segment.* = if (chosen) content.background(tokens.raised).border(tokens.separator, 1) else content.hoverFill(tokens.hover);
    }
    return mod.StackBuilder.fromSlice(.horizontal, track_inset, .center, segments)
        .padding(track_inset)
        .background(tokens.quaternary_fill)
        .cornerRadius(6)
        .fixedSize();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a segmented control sizes to its titles, stretches on request, and selects on tap" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const options = [_][]const u8{ "Request", "Response", "Headers" };

    canvas.begin(renderer.MacosTheme.light);
    const compact = mod.HStack(.{ SegmentedControl(selection.binding(), &options), mod.Spacer() });
    canvas.end();
    var frame = try canvas.render(compact, 600, 24);
    defer frame.deinit();
    // The track ends well short of the row's far edge.
    try std.testing.expect(frame.at(590, 12).r > 0.99);
    try std.testing.expect(frame.at(1, 12).r < 0.99);

    canvas.begin(renderer.MacosTheme.light);
    const stretched = SegmentedControl(selection.binding(), &options).frameMaxWidth();
    canvas.end();
    var wide = try canvas.render(stretched, 600, 24);
    defer wide.deinit();
    // Stretched, the track reaches the far edge, and the last third is the last segment.
    try std.testing.expect(wide.at(597, 12).r < 0.99);
    try std.testing.expect(canvas.tap(.{ .x = 550, .y = 12 }));
    try std.testing.expectEqual(@as(i64, 2), selection.get());
}
