//! Pieces for a chat transcript and the list beside it: a status mark for a
//! conversation's row, a disclosure group that folds a tool call or a thought
//! away, a capsule chip for a mode or an attachment, and the blocks a Markdown
//! reply is drawn with (a code block, a quote, a message bubble). All pure
//! composition over ziggui's stacks, shapes and text; none knows what a chat is
//! about.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_chat);
const mod = @import("module.zig");
const renderer = @import("renderer");

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
const waiting_orange = renderer.Color.fromRgb8(255, 149, 0);

/// The one header row and fold both disclosure groups are built from.
const Disclosure = struct {
    const Self = @This();

    /// A disclosure group: its tappable header row (chevron, header, space,
    /// and the accessory when there is one), with the content under it while
    /// expanded.
    ///
    /// - `header`: the always-shown label.
    /// - `accessory`: what sits at the row's trailing edge, or null for none.
    /// - `expanded`: whether `content` shows.
    /// - `on_toggle`: called when the header row is tapped.
    /// - `content`: what unfolds under the row.
    /// - Returns: the row alone, or the row over the content.
    fn group(header: mod.View, accessory: ?mod.View, expanded: bool, on_toggle: mod.Callback, content: mod.View) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        const chevron = mod.Icon(if (expanded) .chevronDown else .chevronRight, 12, tokens.secondary_label);
        const row_stack = if (accessory) |trailing|
            mod.HStack(.{ chevron, header, mod.Spacer(), trailing })
        else
            mod.HStack(.{ chevron, header, mod.Spacer() });
        const row = row_stack.spacing(6).frameMaxWidth().onTapGesture(on_toggle);
        if (!expanded) return row;
        return mod.VStack(.{
            row,
            content.paddingInsets(.{ .leading = 18 }).frameMaxWidth().frameAlign(.leading),
        }).spacing(4).alignment(.leading).frameMaxWidth();
    }
};

/// A round mark for a row's state: green idle, accent busy, orange waiting,
/// a faint dot starting, a hollow ring stopped.
///
/// - `mark`: the state to show.
/// - `size`: the mark's diameter, in points.
/// - Returns: the mark.
pub fn StatusMark(mark: StatusMarkState, size: f32) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return switch (mark) {
        .idle => mod.Circle(tokens.added).frame(size, size),
        .busy => mod.Circle(tokens.accent).frame(size, size),
        .waiting => mod.Circle(waiting_orange).frame(size, size),
        .starting => mod.Circle(tokens.secondary_label.withAlpha(0.45)).frame(size, size),
        .stopped => mod.Circle(renderer.Color.transparent).frame(size, size).border(tokens.secondary_label, 1.25).cornerRadius(size / 2),
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
pub fn DisclosureGroup(header: mod.View, expanded: bool, on_toggle: mod.Callback, content: mod.View) mod.View {
    return Disclosure.group(header, null, expanded, on_toggle, content);
}

/// A `DisclosureGroup` with an accessory at the trailing end of its header
/// row, past the space the header leaves: a count, a badge, a status mark,
/// right-aligned however long the header is. A tap on it folds the group, as
/// one on the header does.
///
/// - `header`: the always-shown label.
/// - `accessory`: what sits at the row's trailing edge.
/// - `expanded`: whether `content` shows.
/// - `on_toggle`: called when the header row is tapped.
/// - `content`: what unfolds under the header.
/// - Returns: the group.
pub fn DisclosureGroupAccessory(header: mod.View, accessory: mod.View, expanded: bool, on_toggle: mod.Callback, content: mod.View) mod.View {
    return Disclosure.group(header, accessory, expanded, on_toggle, content);
}

/// A small capsule with an optional leading icon: a mode, a model, an
/// attachment. Tappable when `on_tap` is set, with a hover fill.
///
/// - `label`: the text.
/// - `icon`: the leading icon, if any.
/// - `on_tap`: called when the chip is tapped; null makes it static.
/// - Returns: the chip.
pub fn Chip(label: []const u8, icon: ?mod.IconName, on_tap: ?mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const text = mod.Text(label).font(.footnote).foregroundStyle(tokens.label).truncated();
    const inner = if (icon) |glyph| mod.HStack(.{ mod.Icon(glyph, 12, tokens.secondary_label), text }).spacing(5) else text;
    const chip = inner
        .paddingInsets(.{ .top = 4, .leading = 10, .bottom = 4, .trailing = 10 })
        .background(tokens.quaternary_fill)
        .cornerRadius(12);
    const callback = on_tap orelse return chip;
    return chip.hoverFill(tokens.hover).onTapGesture(callback);
}

/// Preformatted text — a code block — in a monospaced face, wrapped, on a
/// tinted rounded panel; selectable for ⌘C.
///
/// - `code`: the text.
/// - Returns: the block.
pub fn CodeBlock(code: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return mod.WrappedText(code).font(.footnote).monospaced().textSelection(.enabled)
        .frameMaxWidth().frameAlign(.leading)
        .padding(10)
        .background(tokens.row_stripe)
        .border(tokens.separator, 1)
        .cornerRadius(8);
}

/// A quoted block: `content` behind a bar.
///
/// - `content`: what is quoted.
/// - Returns: the block.
pub fn Quote(content: mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return mod.HStack(.{
        mod.Rectangle(tokens.secondary_label.withAlpha(0.5)).frameWidth(3),
        content.frameMaxWidth().frameAlign(.leading),
    }).spacing(10).alignment(.top).frameMaxWidth();
}

/// A message bubble: `content` padded on a rounded fill.
///
/// - `content`: the message.
/// - `fill`: the bubble's color.
/// - Returns: the bubble.
pub fn Bubble(content: mod.View, fill: renderer.Color) mod.View {
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
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    window.begin(renderer.MacosTheme.light);
    const idle_view = StatusMark(.idle, 20);
    window.end();
    var idle = try window.render(idle_view, 20, 20);
    defer idle.deinit();
    const centre = idle.at(10, 10);
    try std.testing.expect(centre.g > centre.r and centre.g > centre.b);

    window.begin(renderer.MacosTheme.light);
    const stopped_view = StatusMark(.stopped, 20);
    window.end();
    var stopped = try window.render(stopped_view, 20, 20);
    defer stopped.deinit();
    // The middle of a ring is the background.
    try std.testing.expect(stopped.at(10, 10).r > 0.95 and stopped.at(10, 10).b > 0.95);
}

test "a disclosure group shows its content only while expanded" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        /// A tap that does nothing.
        fn noop(_: ?*anyopaque) void {}
    };
    const callback: mod.Callback = .{ .function = Probe.noop };
    window.begin(renderer.MacosTheme.light);
    defer window.end();
    const closed = DisclosureGroup(mod.Text("ls"), false, callback, mod.Text("a.txt"));
    const open = DisclosureGroup(mod.Text("ls"), true, callback, mod.Text("a.txt"));
    // Closed is the header row alone; open stacks the content under it.
    try std.testing.expect(closed.kind == .stack and closed.kind.stack.direction == .horizontal);
    try std.testing.expect(open.kind == .stack and open.kind.stack.direction == .vertical);
    try std.testing.expectEqual(@as(usize, 2), open.kind.stack.children.len);
}

test "a disclosure group's accessory sits at the trailing edge of its row" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        /// A tap that does nothing.
        fn noop(_: ?*anyopaque) void {}
    };
    const callback: mod.Callback = .{ .function = Probe.noop };
    window.begin(renderer.MacosTheme.light);
    const group = DisclosureGroupAccessory(mod.Text("Steps"), mod.Rectangle(renderer.Color.red).frame(10, 10), true, callback, mod.Text("one"));
    window.end();
    // Open, it is the row over the content; the row ends with the accessory, past a spacer.
    try std.testing.expect(group.kind == .stack and group.kind.stack.direction == .vertical);
    var shot = try window.render(group, 200, 60);
    defer shot.deinit();
    // The accessory's red reaches the row's trailing edge, well clear of the header.
    var least_x: u32 = 200;
    var most_x: u32 = 0;
    for (0..60) |y| for (0..200) |x| {
        const pixel = shot.at(@intCast(x), @intCast(y));
        if (pixel.r > 0.9 and pixel.g < 0.1 and pixel.b < 0.1) {
            least_x = @min(least_x, @as(u32, @intCast(x)));
            most_x = @max(most_x, @as(u32, @intCast(x)));
        }
    };
    try std.testing.expect(most_x >= 195);
    try std.testing.expect(least_x >= 185);
}

test "a chip is tappable only with a callback, and a code block keeps its text" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        /// A tap that does nothing.
        fn noop(_: ?*anyopaque) void {}
    };
    window.begin(renderer.MacosTheme.light);
    const plain = Chip("Ask", null, null);
    const tappable = Chip("Ask", .sparkles, .{ .function = Probe.noop });
    const code = CodeBlock("const x = 1;");
    window.end();
    try std.testing.expect(plain.modifiers.on_tap == null);
    try std.testing.expect(tappable.modifiers.on_tap != null);

    var frame = try window.render(code, 200, 40);
    defer frame.deinit();
    // The panel is tinted, darker than the white around it.
    try std.testing.expect(frame.at(4, 20).r < 1.0);
}
