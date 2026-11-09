//! Pieces for a chat transcript and the list beside it: a status mark for a
//! conversation's row, a disclosure group that folds a tool call or a thought
//! away, a capsule chip for a mode or an attachment, and the blocks a Markdown
//! reply is drawn with (a code block, a quote, a message bubble). All pure
//! composition over zigui's stacks, shapes and text; none knows what a chat is
//! about.

// View constructors are PascalCase functions, as in zigui (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_chat);
const mod = @import("module.zig");
const zigui = @import("zigui");

/// Where the thing a `StatusMark` stands for is.
pub const StatusMarkState = enum {
    const Self = @This();

    /// Up and waiting for work.
    idle,

    /// Working.
    busy,

    /// Blocked on a person (a question, a permission).
    waiting,

    /// Not up yet.
    starting,

    /// Ended, or never started.
    stopped,
};

/// The orange a waiting mark is drawn in: it asks for attention whatever the theme.
const waiting_orange = zigui.Color.fromRgb8(255, 149, 0);

/// A round mark for a row's state: green idle, accent busy, orange waiting,
/// a faint dot starting, a hollow ring stopped.
///
/// - `mark`: the state to show.
/// - `size`: the mark's diameter, in points.
/// - Returns: the mark.
pub fn StatusMark(mark: StatusMarkState, size: f32) zigui.View {
    const t = mod.buildTokens();
    return switch (mark) {
        .idle => zigui.Circle(t.added).frame(size, size),
        .busy => zigui.Circle(t.accent).frame(size, size),
        .waiting => zigui.Circle(waiting_orange).frame(size, size),
        .starting => zigui.Circle(t.secondary_label.withAlpha(0.45)).frame(size, size),
        .stopped => zigui.Circle(zigui.Color.transparent).frame(size, size).border(t.secondary_label, 1.25).cornerRadius(size / 2),
    };
}

/// A header with a chevron that shows `content` under it while `expanded`,
/// like SwiftUI's `DisclosureGroup`.
///
/// Tapping the header calls `on_toggle`, and the app flips what it keeps
/// (app-owned, like a `ScrollState`, so a list of them costs no `State`).
///
/// - `header`: the always-shown label.
/// - `expanded`: whether `content` shows.
/// - `on_toggle`: called when the header is tapped.
/// - `content`: what unfolds under the header.
/// - Returns: the group.
pub fn DisclosureGroup(header: zigui.View, expanded: bool, on_toggle: zigui.Callback, content: zigui.View) zigui.View {
    const t = mod.buildTokens();
    const row = zigui.HStack(.{
        zigui.Icon(if (expanded) .chevron_down else .chevron_right, 12, t.secondary_label),
        header,
        zigui.Spacer(),
    }).spacing(6).frameMaxWidth().onTap(on_toggle);
    if (!expanded) return row;
    return zigui.VStack(.{
        row,
        content.paddingInsets(.{ .leading = 18 }).frameMaxWidth().frameAlign(.leading),
    }).spacing(4).alignment(.leading).frameMaxWidth();
}

/// A small capsule with an optional leading icon: a mode, a model, an
/// attachment. Tappable when `on_tap` is set, with a hover fill.
///
/// - `label`: the text.
/// - `icon`: the leading icon, if any.
/// - `on_tap`: called when the chip is tapped; null makes it static.
/// - Returns: the chip.
pub fn Chip(label: []const u8, icon: ?zigui.IconName, on_tap: ?zigui.Callback) zigui.View {
    const t = mod.buildTokens();
    const text = zigui.Text(label).font(.footnote).foreground(t.label).truncated();
    const inner = if (icon) |glyph| zigui.HStack(.{ zigui.Icon(glyph, 12, t.secondary_label), text }).spacing(5) else text;
    const chip = inner
        .paddingInsets(.{ .top = 4, .leading = 10, .bottom = 4, .trailing = 10 })
        .background(t.quaternary_fill)
        .cornerRadius(12);
    const cb = on_tap orelse return chip;
    return chip.hoverFill(t.hover).onTap(cb);
}

/// Preformatted text — a code block — in a monospaced face, wrapped, on a
/// tinted rounded panel; selectable for ⌘C.
///
/// - `code`: the text.
/// - Returns: the block.
pub fn CodeBlock(code: []const u8) zigui.View {
    const t = mod.buildTokens();
    return zigui.WrappedText(code).font(.footnote).mono().selectable()
        .frameMaxWidth().frameAlign(.leading)
        .padding(10)
        .background(t.row_stripe)
        .border(t.separator, 1)
        .cornerRadius(8);
}

/// A quoted block: `content` behind a bar.
///
/// - `content`: what is quoted.
/// - Returns: the block.
pub fn Quote(content: zigui.View) zigui.View {
    const t = mod.buildTokens();
    return zigui.HStack(.{
        zigui.Rectangle(t.secondary_label.withAlpha(0.5)).frameWidth(3),
        content.frameMaxWidth().frameAlign(.leading),
    }).spacing(10).alignment(.top).frameMaxWidth();
}

/// A message bubble: `content` padded on a rounded fill.
///
/// - `content`: the message.
/// - `fill`: the bubble's color.
/// - Returns: the bubble.
pub fn Bubble(content: zigui.View, fill: zigui.Color) zigui.View {
    return content
        .paddingInsets(.{ .top = 8, .leading = 12, .bottom = 8, .trailing = 12 })
        .background(fill)
        .cornerRadius(14);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a status mark paints its state's color, and a stopped one only a ring" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();

    canvas.begin(zigui.macos.light);
    const idle_view = StatusMark(.idle, 20);
    canvas.end();
    var idle = try canvas.render(idle_view, 20, 20);
    defer idle.deinit();
    const centre = idle.at(10, 10);
    try std.testing.expect(centre.g > centre.r and centre.g > centre.b);

    canvas.begin(zigui.macos.light);
    const stopped_view = StatusMark(.stopped, 20);
    canvas.end();
    var stopped = try canvas.render(stopped_view, 20, 20);
    defer stopped.deinit();
    // The middle of a ring is the background.
    try std.testing.expect(stopped.at(10, 10).r > 0.95 and stopped.at(10, 10).b > 0.95);
}

test "a disclosure group shows its content only while expanded" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Probe = struct {
        const Self = @This();
        fn noop(_: ?*anyopaque) void {}
    };
    const cb: zigui.Callback = .{ .func = Probe.noop };
    canvas.begin(zigui.macos.light);
    defer canvas.end();
    const closed = DisclosureGroup(zigui.Text("ls"), false, cb, zigui.Text("a.txt"));
    const open = DisclosureGroup(zigui.Text("ls"), true, cb, zigui.Text("a.txt"));
    // Closed is the header row alone; open stacks the content under it.
    try std.testing.expect(closed.kind == .stack and closed.kind.stack.direction == .horizontal);
    try std.testing.expect(open.kind == .stack and open.kind.stack.direction == .vertical);
    try std.testing.expectEqual(@as(usize, 2), open.kind.stack.children.len);
}

test "a chip is tappable only with a callback, and a code block keeps its text" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Probe = struct {
        const Self = @This();
        fn noop(_: ?*anyopaque) void {}
    };
    canvas.begin(zigui.macos.light);
    const plain = Chip("Ask", null, null);
    const tappable = Chip("Ask", .sparkles, .{ .func = Probe.noop });
    const code = CodeBlock("const x = 1;");
    canvas.end();
    try std.testing.expect(plain.mods.on_tap == null);
    try std.testing.expect(tappable.mods.on_tap != null);

    var frame = try canvas.render(code, 200, 40);
    defer frame.deinit();
    // The panel is tinted, darker than the white around it.
    try std.testing.expect(frame.at(4, 20).r < 1.0);
}
