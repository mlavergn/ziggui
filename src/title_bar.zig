//! An app-drawn title bar, for a window with zigui's `custom_titlebar` (off
//! macOS): one row over the theme family's own bar (`zigui.Theme.drawTitleBar`),
//! its leading content (an icon, a `MenuBar`), a centered middle (a path)
//! that truncates and then hides, and its trailing content (`WindowButtons`).
//! The row's empty space is the window's drag band. Pure composition over
//! zigui's `Drawing`, `GeometryReader` and stacks.

// View constructors are PascalCase functions, as in zigui (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_title_bar);
const mod = @import("module.zig");
const zigui = @import("zigui");

/// The title bar's height, in points (Windows 11's caption height).
pub const title_bar_height: f32 = 32;

/// Which platform's window buttons `WindowButtons` draws: they follow the
/// system the app runs on, never the theme.
pub const WindowButtonStyle = enum {
    const Self = @This();

    /// Windows 11's caption buttons: 46 pt wide glyphs across the bar's
    /// height, a wash on hover, red behind close.
    windows,

    /// GNOME's (Adwaita): small glyphs on faint circles, the circle darker on hover.
    gnome,
};

/// The middle's text and color, in the build arena: what its
/// `GeometryReader` builds from at paint time.
const Middle = struct {
    const Self = @This();

    /// The narrowest the middle may be and still show; narrower, it hides.
    const min_width: f32 = 80;

    /// The text.
    text: []const u8,

    /// Its color.
    color: zigui.Color,

    /// The middle at the width it is given: the text, centered and
    /// truncated to fit, or nothing when there is too little room.
    ///
    /// - `self`: the middle.
    /// - `size`: the room it has.
    /// - Returns: the view.
    fn build(self: *const Self, size: zigui.Size) zigui.View {
        if (size.width < Self.min_width) return zigui.Empty();
        return zigui.Text(self.text).font(.footnote).mono().foreground(self.color).truncated()
            .frame(size.width, size.height);
    }
};

/// The bar's background: the theme family's title bar.
const Backdrop = struct {
    const Self = @This();

    /// Draws `zigui.Theme.drawTitleBar` across the bar.
    ///
    /// - `self`: unused; the theme comes from the frame.
    /// - `pen`: draws.
    /// - `rect`: the bar.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, pen: *zigui.Pen, rect: zigui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        try pen.ctx.theme.drawTitleBar(pen.ctx.surface(pen.canvas), rect);
    }
};

/// Which window button.
const ButtonKind = enum {
    const Self = @This();

    /// Minimizes the window: a dash.
    minimize,

    /// Maximizes the window: a square.
    maximize,

    /// Restores a maximized window: two overlapping squares.
    restore,

    /// Closes the window: a cross.
    close,
};

/// One window button, in the build arena: drawn at paint time, so it can
/// read the pointer for its hover look.
const Button = struct {
    const Self = @This();

    /// The red behind Windows 11's close button under the pointer.
    const close_red = zigui.Color.fromRgb8(196, 43, 28);

    /// The platform's look.
    style: WindowButtonStyle,

    /// Which button.
    kind: ButtonKind,

    /// The glyph's color (the bar's text color).
    color: zigui.Color,

    /// Draws the button: its hover wash (red behind close on Windows) or
    /// GNOME's circle, then its glyph.
    ///
    /// - `self`: the button.
    /// - `pen`: draws.
    /// - `rect`: the button's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, pen: *zigui.Pen, rect: zigui.Rect) std.mem.Allocator.Error!void {
        const hovered = if (pen.ctx.hover_point) |point| rect.contains(point) else false;
        var glyph = self.color;
        var half: f32 = 5;
        switch (self.style) {
            .windows => if (hovered) {
                if (self.kind == .close) {
                    try pen.fill(rect, 0, Self.close_red);
                    glyph = zigui.Color.white;
                } else try pen.fill(rect, 0, self.color.withAlpha(0.1));
            },
            .gnome => {
                const diameter: f32 = 24;
                const circle: zigui.Rect = .{ .x = rect.x + (rect.width - diameter) / 2, .y = rect.y + (rect.height - diameter) / 2, .width = diameter, .height = diameter };
                try pen.fill(circle, diameter / 2, self.color.withAlpha(if (hovered) 0.2 else 0.1));
                half = 4;
            },
        }
        const center_x = @round(rect.x + rect.width / 2) + 0.5;
        const center_y = @round(rect.y + rect.height / 2) + 0.5;
        const line_width: f32 = if (self.style == .gnome) 1.5 else 1;
        switch (self.kind) {
            .minimize => try pen.line(.{ .x = center_x - half, .y = center_y }, .{ .x = center_x + half, .y = center_y }, line_width, glyph),
            .maximize => try Self.square(pen, center_x - half, center_y - half, 2 * half, line_width, glyph),
            .restore => {
                try Self.square(pen, center_x - half, center_y - half + 2, 2 * half - 2, line_width, glyph);
                try pen.line(.{ .x = center_x - half + 2, .y = center_y - half }, .{ .x = center_x + half, .y = center_y - half }, line_width, glyph);
                try pen.line(.{ .x = center_x + half, .y = center_y - half }, .{ .x = center_x + half, .y = center_y + half - 2 }, line_width, glyph);
            },
            .close => {
                try pen.line(.{ .x = center_x - half, .y = center_y - half }, .{ .x = center_x + half, .y = center_y + half }, line_width, glyph);
                try pen.line(.{ .x = center_x - half, .y = center_y + half }, .{ .x = center_x + half, .y = center_y - half }, line_width, glyph);
            },
        }
    }

    /// The outline of a square.
    ///
    /// - `pen`: draws.
    /// - `x`: its left.
    /// - `y`: its top.
    /// - `side`: its side.
    /// - `line_width`: the line width.
    /// - `color`: the line color.
    /// - Returns: nothing; propagates allocation failure.
    fn square(pen: *zigui.Pen, x: f32, y: f32, side: f32, line_width: f32, color: zigui.Color) std.mem.Allocator.Error!void {
        try pen.line(.{ .x = x, .y = y }, .{ .x = x + side, .y = y }, line_width, color);
        try pen.line(.{ .x = x + side, .y = y }, .{ .x = x + side, .y = y + side }, line_width, color);
        try pen.line(.{ .x = x + side, .y = y + side }, .{ .x = x, .y = y + side }, line_width, color);
        try pen.line(.{ .x = x, .y = y + side }, .{ .x = x, .y = y }, line_width, color);
    }
};

/// A title bar: `leading` (an icon, a `MenuBar`), then `middle` centered
/// between it and `trailing` (`WindowButtons`), truncated to fit and hidden
/// when there is too little room, over the theme family's own bar. Its text
/// takes `zigui.Theme.titleBarForeground`; give the `MenuBar` the same
/// color and `.fill = false`, so it keeps its titles' width and the middle
/// gets the rest. The empty space is left to the window's drag band.
///
/// - `leading`: what sits at the left.
/// - `middle`: the centered text (a path); empty for none.
/// - `trailing`: what sits at the right.
/// - Returns: the bar, `title_bar_height` tall and as wide as it is given.
pub fn TitleBar(leading: zigui.View, middle: []const u8, trailing: zigui.View) zigui.View {
    const alloc = zigui.buildAlloc();
    const theme = zigui.buildTheme();
    const backdrop = alloc.create(Backdrop) catch @panic("oom");
    backdrop.* = .{};
    const center = alloc.create(Middle) catch @panic("oom");
    center.* = .{ .text = middle, .color = theme.titleBarForeground().withAlpha(0.8) };
    return zigui.ZStack(.{
        zigui.Drawing(Backdrop, backdrop, Backdrop.draw).frameMaxWidth().frameHeight(title_bar_height),
        zigui.HStack(.{
            leading,
            zigui.GeometryReader(Middle, center, Middle.build).frameMaxWidth().frameHeight(title_bar_height),
            trailing,
        }).spacing(8).frameMaxWidth().frameHeight(title_bar_height),
    }).frameMaxWidth().frameHeight(title_bar_height);
}

/// The window buttons: minimize, maximize (restore when `maximized`) and
/// close, in the platform's look. They stay live with a popover or a modal
/// open (`popoverPassthrough`, `modalPassthrough`), so a window can be
/// minimized or closed under a dialog.
///
/// - `style`: the platform's look.
/// - `maximized`: the window is maximized, so the middle button restores it.
/// - `actions`: what they do.
/// - Returns: the buttons, `title_bar_height` tall.
pub fn WindowButtons(style: WindowButtonStyle, maximized: bool, actions: mod.WindowActions) zigui.View {
    const alloc = zigui.buildAlloc();
    const color = zigui.buildTheme().titleBarForeground();
    const width: f32 = switch (style) {
        .windows => 46,
        .gnome => 30,
    };
    const kinds = [_]ButtonKind{ .minimize, if (maximized) .restore else .maximize, .close };
    const calls = [_]zigui.Callback{ actions.minimize, actions.maximize, actions.close };
    const views = alloc.alloc(zigui.View, kinds.len) catch @panic("oom");
    for (views, kinds, calls) |*view, kind, call| {
        const button = alloc.create(Button) catch @panic("oom");
        button.* = .{ .style = style, .kind = kind, .color = color };
        view.* = zigui.Drawing(Button, button, Button.draw).frame(width, title_bar_height)
            .onTap(call)
            .popoverPassthrough()
            .modalPassthrough()
            .accessibilityLabel(@tagName(kind));
    }
    const buttons = zigui.view.makeStackFromSlice(.horizontal, 0, .center, views);
    return switch (style) {
        .windows => buttons,
        .gnome => buttons.paddingInsets(.{ .trailing = 4 }),
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

const TestWindow = struct {
    const Self = @This();

    var minimized: u32 = 0;
    var maximized: u32 = 0;
    var closed: u32 = 0;

    fn minimize(_: ?*anyopaque) void {
        minimized += 1;
    }
    fn maximize(_: ?*anyopaque) void {
        maximized += 1;
    }
    fn close(_: ?*anyopaque) void {
        closed += 1;
    }

    const actions: mod.WindowActions = .{
        .minimize = .{ .func = Self.minimize },
        .maximize = .{ .func = Self.maximize },
        .close = .{ .func = Self.close },
    };
};

test "the window buttons sit at the right and do what they say, under a modal too" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var modal = zigui.State(bool).init(std.testing.allocator, true);
    defer modal.deinit();
    TestWindow.minimized = 0;
    TestWindow.maximized = 0;
    TestWindow.closed = 0;

    canvas.begin(zigui.macos.light);
    const bar = TitleBar(zigui.Text("File"), "/src/app", WindowButtons(.windows, false, TestWindow.actions));
    const view = zigui.VStack(.{ bar, zigui.Spacer() }).frameMaxWidth().frameMaxHeight()
        .alert(modal.binding(), zigui.Rectangle(zigui.Color.blue).frame(80, 80));
    canvas.end();
    var frame = try canvas.render(view, 600, 300);
    frame.deinit();
    // Windows: three 46 pt buttons flush right; close is the last.
    try std.testing.expect(canvas.tap(.{ .x = 600 - 23, .y = title_bar_height / 2 }));
    try std.testing.expect(canvas.tap(.{ .x = 600 - 46 - 23, .y = title_bar_height / 2 }));
    try std.testing.expect(canvas.tap(.{ .x = 600 - 92 - 23, .y = title_bar_height / 2 }));
    try std.testing.expectEqual(@as(u32, 1), TestWindow.closed);
    try std.testing.expectEqual(@as(u32, 1), TestWindow.maximized);
    try std.testing.expectEqual(@as(u32, 1), TestWindow.minimized);
    try std.testing.expect(modal.get());
    // Anywhere else, the alert's scrim takes the tap.
    try std.testing.expect(canvas.tap(.{ .x = 20, .y = title_bar_height / 2 }));
    try std.testing.expect(!modal.get());
}

test "close turns red under the pointer on Windows, and the middle hides when there is no room" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();

    canvas.begin(zigui.macos.light);
    const wide = TitleBar(zigui.Text("File"), "/src/app", WindowButtons(.windows, true, TestWindow.actions));
    canvas.end();
    var plain = try canvas.render(wide, 600, 32);
    defer plain.deinit();
    try std.testing.expect(plain.at(600 - 4, 4).r > 0.9 and plain.at(600 - 4, 4).g > 0.9);
    // The path is drawn somewhere in the middle.
    var inked = false;
    for (200..400) |x| inked = inked or plain.at(@intCast(x), 16).luminance() < 0.6;
    try std.testing.expect(inked);

    canvas.begin(zigui.macos.light);
    const narrow = TitleBar(zigui.Text("File"), "/src/app", WindowButtons(.gnome, false, TestWindow.actions));
    canvas.end();
    var tight = try canvas.render(narrow, 160, 32);
    defer tight.deinit();
    // 160 pt: File and three 30 pt GNOME buttons leave under 80 pt, so no path.
    var any = false;
    for (50..60) |x| any = any or tight.at(@intCast(x), 16).luminance() < 0.6;
    try std.testing.expect(!any);
}

test "a menu bar that does not fill keeps its titles clear of what is before it, near the narrowest" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};
    const menus = [_]mod.MenuBarMenu{
        .{ .title = "File", .items = &.{} },       .{ .title = "View", .items = &.{} },
        .{ .title = "Repository", .items = &.{} }, .{ .title = "Actions", .items = &.{} },
        .{ .title = "Help", .items = &.{} },
    };
    for ([_]f32{ 460, 640, 900 }) |width| {
        canvas.begin(zigui.macos.light);
        const bar = TitleBar(
            zigui.HStack(.{ zigui.Rectangle(zigui.Color.black).frame(16, 16), mod.MenuBar(&state, &menus, .{ .fill = false }) }).spacing(4).paddingInsets(.{ .leading = 10 }),
            "/a/rather/long/path/to/some/repository",
            WindowButtons(.windows, false, TestWindow.actions),
        );
        canvas.end();
        var frame = try canvas.render(bar, @intFromFloat(width), 32);
        frame.deinit();
        // The first title starts after the 16 pt mark (10 + 16 + 4), and the
        // last ends before the buttons, at every width.
        const first = canvas.hits.items[0].rect;
        const last = canvas.hits.items[menus.len - 1].rect;
        try std.testing.expect(first.x >= 30);
        try std.testing.expect(last.maxX() <= width - 3 * 46);
    }
}
