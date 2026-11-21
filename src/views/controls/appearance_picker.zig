//! A settings page's appearance choice, drawn as macOS draws it: a small
//! window for each of Auto, Light and Dark, the chosen one ringed.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_appearance_picker);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The colors a thumbnail's little window is drawn in: fixed, so Light and
/// Dark read the same under every theme.
const ThumbnailPalette = struct {
    const Self = @This();

    /// The desktop behind the window.
    desktop: renderer.Color,
    /// The menu bar across the desktop's top.
    menu_bar: renderer.Color,
    /// The window's content.
    window: renderer.Color,
    /// The window's title bar.
    title_bar: renderer.Color,
    /// The window's sidebar.
    sidebar: renderer.Color,
    /// The content's lines of text.
    text: renderer.Color,

    /// The light thumbnail's colors.
    const light = Self{
        .desktop = renderer.Color.hex(0xC4D3EA),
        .menu_bar = renderer.Color.hex(0xEEF2F8),
        .window = renderer.Color.hex(0xFFFFFF),
        .title_bar = renderer.Color.hex(0xE7E7EA),
        .sidebar = renderer.Color.hex(0xF0F0F3),
        .text = renderer.Color.hex(0xD3D3D8),
    };

    /// The dark thumbnail's colors.
    const dark = Self{
        .desktop = renderer.Color.hex(0x2B3445),
        .menu_bar = renderer.Color.hex(0x1D2330),
        .window = renderer.Color.hex(0x262628),
        .title_bar = renderer.Color.hex(0x3A3A3D),
        .sidebar = renderer.Color.hex(0x313134),
        .text = renderer.Color.hex(0x4B4B50),
    };
};

/// One choice's thumbnail: what its `Canvas` draws.
const AppearanceThumbnail = struct {
    const Self = @This();

    /// The thumbnail's size, in points, as macOS draws it.
    const size = renderer.Size{ .width = 68, .height = 44 };
    /// The thumbnail's corner radius.
    const radius: f32 = 6;
    /// The ring's width around the chosen thumbnail.
    const ring: f32 = 3;

    /// The appearance it shows.
    appearance: mod.Appearance,
    /// The accent, for the window's selected sidebar row.
    accent: renderer.Color,
    /// The hairline around the thumbnail, so Dark keeps its edge on a dark window.
    outline: renderer.Color,

    /// One choice: its thumbnail, ringed in the accent while chosen, over its
    /// title; a tap chooses it.
    ///
    /// - `appearance`: the choice.
    /// - `chosen`: whether it is the one selected.
    /// - `selection`: the selected appearance's index, set by a tap.
    /// - Returns: the choice's view.
    fn choice(appearance: mod.Appearance, chosen: bool, selection: mod.Binding(i64)) mod.View {
        const scope = mod.BuildScope.shared();
        const tokens = scope.tokens();
        const thumbnail = scope.allocator().create(Self) catch @panic("oom");
        thumbnail.* = .{ .appearance = appearance, .accent = tokens.accent, .outline = tokens.separator };
        // Its corners are drawn rounded rather than clipped: a clip's edge
        // anti-aliases differently on the GPU, a fill's does not.
        const picture = mod.Canvas(Self, thumbnail, Self.draw).frame(size.width, size.height);
        // The ring is a ground the thumbnail sits on, so a chiseled theme
        // draws it as it does every other fill, not as a bevel.
        var ringed = mod.StackBuilder.make(.vertical, 0, .center, .{picture}).padding(ring).cornerRadius(radius + ring);
        if (chosen) ringed = ringed.background(tokens.accent);
        return mod.StackBuilder.make(.vertical, 5, .center, .{
            ringed,
            mod.Text(appearance.title()).font(.subheadline).foreground(if (chosen) tokens.label else tokens.secondary_label),
        }).onTap(mod.Callback.select(selection, @backingInt(appearance)))
            .accessibilityLabel(appearance.title())
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = chosen });
    }

    /// Draws the thumbnail: Light's or Dark's little window, or Auto's, light
    /// on its left half and dark on its right, inside a hairline.
    ///
    /// - `self`: the thumbnail.
    /// - `graphics`: what it draws with.
    /// - `frame`: its frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, graphics: *mod.GraphicsContext, frame: renderer.Rect) std.mem.Allocator.Error!void {
        switch (self.appearance) {
            .light => try self.scene(graphics, frame, ThumbnailPalette.light),
            .dark => try self.scene(graphics, frame, ThumbnailPalette.dark),
            .automatic => {
                const half = frame.width / 2;
                try graphics.display_list.pushClip(.{ .x = frame.x, .y = frame.y, .width = half, .height = frame.height }, 0);
                try self.scene(graphics, frame, ThumbnailPalette.light);
                try graphics.display_list.popClip();
                try graphics.display_list.pushClip(.{ .x = frame.x + half, .y = frame.y, .width = frame.width - half, .height = frame.height }, 0);
                try self.scene(graphics, frame, ThumbnailPalette.dark);
                try graphics.display_list.popClip();
            },
        }
        // Inset by half its width, so all of it lies inside the frame.
        const hairline = graphics.context.theme.metrics.hairline;
        const edge = renderer.Rect{ .x = frame.x + hairline / 2, .y = frame.y + hairline / 2, .width = frame.width - hairline, .height = frame.height - hairline };
        try graphics.stroke(edge, radius - hairline / 2, hairline, self.outline);
    }

    /// Draws a desktop with a menu bar and a window on it: a title bar with
    /// its three buttons, a sidebar with its selected row in the accent, and
    /// lines of text.
    ///
    /// - `self`: the thumbnail.
    /// - `graphics`: what it draws with.
    /// - `frame`: the thumbnail's frame.
    /// - `palette`: the colors.
    /// - Returns: nothing; propagates allocation failure.
    fn scene(self: *const Self, graphics: *mod.GraphicsContext, frame: renderer.Rect, palette: ThumbnailPalette) std.mem.Allocator.Error!void {
        // The menu bar, its top corners the thumbnail's, then the desktop below it.
        const menu_bar_height: f32 = 4;
        try graphics.fill(.{ .x = frame.x, .y = frame.y, .width = frame.width, .height = menu_bar_height + radius }, radius, palette.menu_bar);
        try graphics.fill(.{ .x = frame.x, .y = frame.y + menu_bar_height, .width = frame.width, .height = frame.height - menu_bar_height }, radius, palette.desktop);
        try graphics.fill(.{ .x = frame.x, .y = frame.y + menu_bar_height, .width = frame.width, .height = radius }, 0, palette.desktop);

        const window = renderer.Rect{ .x = frame.x + 9, .y = frame.y + 9, .width = frame.width - 18, .height = frame.height - 13 };
        try graphics.fill(window, 3, palette.window);
        const title_height: f32 = 7;
        try graphics.fill(.{ .x = window.x, .y = window.y, .width = window.width, .height = title_height }, 3, palette.title_bar);
        // Square off the title bar's lower corners.
        try graphics.fill(.{ .x = window.x, .y = window.y + 3, .width = window.width, .height = title_height - 3 }, 0, palette.title_bar);
        const buttons = [_]renderer.Color{ renderer.Color.hex(0xFF5F57), renderer.Color.hex(0xFEBC2E), renderer.Color.hex(0x28C840) };
        const button_size: f32 = 2.6;
        for (buttons, 0..) |color, index| {
            const x = window.x + 3 + @as(f32, @floatFromInt(index)) * 4;
            try graphics.fill(.{ .x = x, .y = window.y + (title_height - button_size) / 2, .width = button_size, .height = button_size }, button_size / 2, color);
        }

        const body_y = window.y + title_height;
        const body_height = window.maxY() - body_y;
        const sidebar_width: f32 = 13;
        try graphics.fill(.{ .x = window.x, .y = body_y, .width = sidebar_width, .height = body_height - 3 }, 0, palette.sidebar);
        try graphics.fill(.{ .x = window.x + 2, .y = body_y + 3, .width = sidebar_width - 4, .height = 3 }, 1, self.accent);
        try graphics.fill(.{ .x = window.x + 2, .y = body_y + 8, .width = sidebar_width - 6, .height = 2 }, 1, palette.text);

        const text_x = window.x + sidebar_width + 4;
        const text_width = window.maxX() - 4 - text_x;
        const lines = [_]f32{ 0.85, 0.6, 0.72 };
        for (lines, 0..) |fraction, index| {
            const y = body_y + 3 + @as(f32, @floatFromInt(index)) * 5;
            try graphics.fill(.{ .x = text_x, .y = y, .width = text_width * fraction, .height = 2 }, 1, palette.text);
        }
    }
};

/// An appearance picker for a settings page, as macOS's Appearance setting
/// draws one: a little window for each of Auto, Light and Dark (Auto light on
/// its left half, dark on its right) over its title, the chosen one ringed in
/// the accent. A tap chooses one. It only records the choice: the app
/// resolves it (`Appearance.resolved`, given the system's scheme) and draws
/// in that theme. Put it in a `Form` with `LabeledContent("Appearance:", …)`.
///
/// - `selection`: the chosen `Appearance`'s index (`@backingInt`); app-owned.
/// - Returns: the picker, as wide as its three choices.
pub fn AppearancePicker(selection: mod.Binding(i64)) mod.View {
    const scope = mod.BuildScope.shared();
    const chosen = mod.Appearance.at(selection.get());
    const choices = scope.allocator().alloc(mod.View, mod.Appearance.all.len) catch @panic("oom");
    for (mod.Appearance.all, choices) |appearance, *choice| choice.* = AppearanceThumbnail.choice(appearance, appearance == chosen, selection);
    return mod.StackBuilder.fromSlice(.horizontal, 12, .top, choices);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an appearance picker rings the chosen one, and a tap chooses another" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    window.begin(renderer.MacosTheme.light);
    const picker = AppearancePicker(selection.binding());
    window.end();
    var frame = try window.render(picker, 300, 100);
    defer frame.deinit();

    // Auto is chosen: its ring is the accent; Light's place is the window's.
    const accent = mod.BuildScope.shared().tokens().accent;
    try std.testing.expect(frame.at(1, 30).approxEql(accent, 0.05));
    const light_x = 2 * AppearanceThumbnail.ring + AppearanceThumbnail.size.width + 12;
    try std.testing.expect(frame.at(@intFromFloat(light_x + 1), 30).approxEql(renderer.Color.white, 0.02));

    // The three choices are the only tap regions; the rightmost is Dark.
    try std.testing.expectEqual(@as(usize, 3), window.hits.items.len);
    var dark: ?renderer.Rect = null;
    for (window.hits.items) |hit| {
        if (dark == null or hit.rect.x > dark.?.x) dark = hit.rect;
    }
    try std.testing.expect(window.tap(.{ .x = dark.?.midX(), .y = dark.?.midY() }));
    try std.testing.expectEqual(mod.Appearance.dark, mod.Appearance.at(selection.get()));
}
