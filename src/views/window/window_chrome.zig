//! The pieces of a window's frame every app draws the same way: the macOS top
//! band clear of the traffic lights, the drawn title bar elsewhere (the app's
//! icon and menus, the centered title, the window buttons), and how its menu
//! bar spells a shortcut.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_chrome);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A window's frame: its measures and the views that make it.
pub const WindowChrome = struct {
    const Self = @This();

    /// The top band's height: on macOS the window's drag area.
    pub const top_bar_height: f32 = 40;
    /// The traffic lights' width, which the top band's text keeps clear of
    /// (they end at 72pt: 12pt in, three 14pt lights 9pt apart).
    pub const traffic_lights_width: f32 = 76;
    /// Below this window width a drawn title bar folds its menus into one `☰`.
    pub const fold_width: f32 = 640;
    /// The title bar icon's side, in points.
    pub const icon_side: f32 = 16;
    /// The gap between `topBarLeading`'s leading view and its title.
    pub const leading_gap: f32 = 8;
    /// On macOS, the room `topBarLeading` leaves past `traffic_lights_width`
    /// before its leading view, as a toolbar's first item stands clear of the
    /// traffic lights: they end 72pt in (a unified compact titlebar's, as
    /// `Cocoa.unifyTitlebar` makes it), so the view starts 16pt past them.
    pub const lights_gap: f32 = 12;

    /// The top band on macOS (or a plain top band elsewhere): the app's title view, centered between the insets.
    ///
    /// - `title`: the title, styled as the app wants (cleaned for drawing by the app).
    /// - `mac`: inset for the traffic lights.
    /// - Returns: the band, `top_bar_height` tall.
    pub fn topBar(title: mod.View, mac: bool) mod.View {
        const inset: f32 = if (mac) traffic_lights_width else 12;
        return title.frameMaxWidth().paddingInsets(.{ .leading = inset, .trailing = inset }).frameHeight(top_bar_height).frameMaxWidth();
    }

    /// The top band with a view at its left: `topBar`'s title, still
    /// centered in the window, and `leading` after the inset (the traffic
    /// lights' and `lights_gap` on macOS, 12pt elsewhere), vertically
    /// centered. The band leaves that room around `leading` itself: pass the
    /// bare view, never one padded on its own (a padding there replaces the
    /// view's own, as every modifier does, and would land inside it). The
    /// title is inset by `leading_width` (and a gap) on both sides, so it
    /// stays centered and truncates before it reaches `leading`.
    ///
    /// - `leading`: the view at the left (a segmented control, say).
    /// - `leading_width`: how wide `leading` draws (`IconSegment.controlWidth`).
    /// - `title`: the title, styled as the app wants (cleaned for drawing by the app).
    /// - `mac`: inset for the traffic lights.
    /// - Returns: the band, `top_bar_height` tall.
    pub fn topBarLeading(leading: mod.View, leading_width: f32, title: mod.View, mac: bool) mod.View {
        const inset: f32 = if (mac) traffic_lights_width + lights_gap else 12;
        const title_inset = inset + leading_width + leading_gap;
        return mod.ZStack(.{
            title.frameMaxWidth().paddingInsets(.{ .leading = title_inset, .trailing = title_inset }).frameHeight(top_bar_height).frameMaxWidth(),
            mod.HStack(.{ leading, mod.Spacer() }).paddingInsets(.{ .leading = inset }).frameHeight(top_bar_height).frameMaxWidth(),
        }).frameHeight(top_bar_height).frameMaxWidth();
    }

    /// The title bar an app draws off macOS: its icon and menus, the title centered, the window buttons.
    ///
    /// - `icon`: the app's icon pixels, drawn at `icon_side`.
    /// - `menus`: the menu bar.
    /// - `title`: the centered text; cleaned for drawing.
    /// - `buttons`: the window buttons.
    /// - Returns: the bar.
    pub fn titleBar(icon: renderer.Image, menus: mod.View, title: []const u8, buttons: mod.View) mod.View {
        return mod.TitleBar(
            mod.HStack(.{
                mod.Image(icon).scaledToFit().frame(icon_side, icon_side),
                menus,
            }).spacing(4).paddingInsets(.{ .leading = 10 }),
            mod.DisplayText.clean(mod.BuildScope.shared().allocator(), title),
            buttons,
        );
    }

    /// `titleBar` with a view just before the window buttons: the icon and
    /// menus, the title centered between them and `trailing`, then
    /// `trailing` and the buttons.
    ///
    /// - `icon`: the app's icon pixels, drawn at `icon_side`.
    /// - `menus`: the menu bar.
    /// - `title`: the centered text; cleaned for drawing.
    /// - `trailing`: the view before the buttons (a segmented control, say).
    /// - `buttons`: the window buttons.
    /// - Returns: the bar.
    pub fn titleBarWith(icon: renderer.Image, menus: mod.View, title: []const u8, trailing: mod.View, buttons: mod.View) mod.View {
        return Self.titleBar(icon, menus, title, mod.HStack(.{ trailing, buttons }).spacing(8));
    }

    /// How a drawn menu bar spells an entry's key: `⌘X` as `ctrl+X`, a bare shortcut letter as `ctrl+<key>`.
    ///
    /// - `allocator`: owns the text.
    /// - `hint`: the entry's key as the app writes it (`⌘R`, `d`), or empty.
    /// - `shortcut`: the entry's command shortcut, or empty.
    /// - Returns: the key's text, `hint` itself when it needs no change; propagates allocation failure.
    pub fn keyText(allocator: std.mem.Allocator, hint: []const u8, shortcut: []const u8) ![]const u8 {
        const command = "⌘";
        if (std.mem.startsWith(u8, hint, command)) {
            const rest = try std.ascii.allocUpperString(allocator, hint[command.len..]);
            return allocator.print("ctrl+{s}", .{rest});
        }
        if (hint.len > 0 or shortcut.len == 0) return hint;
        const key = try std.ascii.allocUpperString(allocator, shortcut);
        return allocator.print("ctrl+{s}", .{key});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(WindowChrome);
    // Nothing here does I/O to trace.
    _ = log;
}

test "window chrome spells ⌘ as ctrl+, and a bare shortcut as ctrl+<key>" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try std.testing.expectEqualStrings("ctrl+R", try WindowChrome.keyText(allocator, "⌘R", ""));
    try std.testing.expectEqualStrings("ctrl+,", try WindowChrome.keyText(allocator, "", ","));
    try std.testing.expectEqualStrings("e", try WindowChrome.keyText(allocator, "e", "e"));
}

test "the top band keeps its title centered in the window with a view at its left" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var tapped: u32 = 0;
    const Probe = struct {
        const Self = @This();

        /// Counts a tap.
        ///
        /// - `context`: the count.
        fn tap(context: ?*anyopaque) void {
            const count: *u32 = @ptrCast(@alignCast(context.?));
            count.* += 1;
        }
    };
    const on_tap: mod.Callback = .{ .context = &tapped, .function = Probe.tap };

    window.begin(renderer.MacosTheme.light);
    const plain = WindowChrome.topBar(mod.HStack(.{mod.Rectangle(renderer.Color.black).frame(40, 10)}), true);
    window.end();
    var before = try window.render(plain, 600, WindowChrome.top_bar_height);
    defer before.deinit();

    window.begin(renderer.MacosTheme.light);
    const leading = mod.Rectangle(renderer.Color.black).frame(30, 20).onTap(on_tap);
    const band = WindowChrome.topBarLeading(leading, 30, mod.HStack(.{mod.Rectangle(renderer.Color.black).frame(40, 10)}), true);
    window.end();
    var after = try window.render(band, 600, WindowChrome.top_bar_height);
    defer after.deinit();

    // The title is where it was: centered in the window.
    try std.testing.expect(before.at(300, 20).r < 0.5);
    try std.testing.expect(after.at(300, 20).r < 0.5);
    try std.testing.expect(after.at(330, 20).r > 0.5);
    // The leading view sits clear of the traffic lights, and takes its taps;
    // the gap before it is the band's, never the view's.
    const start = WindowChrome.traffic_lights_width + WindowChrome.lights_gap;
    try std.testing.expect(after.at(start + 15, 20).r < 0.5);
    try std.testing.expect(after.at(start - 10, 20).r > 0.5);
    try std.testing.expect(window.tap(.{ .x = start + 15, .y = 20 }));
    try std.testing.expectEqual(1, tapped);
}

test "the drawn title bar puts a view before the window buttons" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const pixels = [_]u8{ 0, 0, 0, 255 };
    const icon: renderer.Image = .{ .width = 1, .height = 1, .pixels = &pixels };
    window.begin(renderer.MacosTheme.light);
    const bar = WindowChrome.titleBarWith(
        icon,
        mod.Empty(),
        "",
        mod.Rectangle(renderer.Color.black).frame(30, 20),
        mod.Rectangle(renderer.Color.white).frame(60, 20),
    );
    window.end();
    var frame = try window.render(bar, 600, mod.title_bar_height);
    defer frame.deinit();
    // The buttons are flush right; the trailing view sits 8pt before them.
    const y = mod.title_bar_height / 2;
    try std.testing.expect(frame.at(600 - 60 - 8 - 15, y).r < 0.5);
    try std.testing.expect(frame.at(600 - 30, y).r > 0.5);
}

test "an icon segmented control in the top band keeps its clicks; the band's empty space drags" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const segments = [_]mod.IconSegment{ .{ .icon = .gitBranch, .title = "Git" }, .{ .icon = .code, .title = "Files" } };
    window.begin(renderer.MacosTheme.light);
    const band = WindowChrome.topBarLeading(mod.IconSegmentedControl(selection.binding(), &segments), mod.IconSegment.controlWidth(segments.len), mod.Text("~/src/app"), true);
    window.end();
    var frame = try window.render(band, 800, WindowChrome.top_bar_height);
    defer frame.deinit();
    const area: mod.WindowHitArea = .{ .size = .{ .width = 800, .height = 600 }, .drag_band = WindowChrome.top_bar_height, .hits = window.hits.items };
    const second: renderer.Point = .{ .x = WindowChrome.traffic_lights_width + WindowChrome.lights_gap + 2 + 32 + 2 + 16, .y = 20 };
    // The track starts past the gap: the band behind the lights' gap is bare.
    try std.testing.expect(frame.at(WindowChrome.traffic_lights_width + WindowChrome.lights_gap / 2, 20).r > 0.99);
    try std.testing.expectEqual(mod.WindowHit.normal, area.at(second));
    try std.testing.expectEqual(mod.WindowHit.draggable, area.at(.{ .x = 600, .y = 20 }));
    try std.testing.expect(window.tap(second));
    try std.testing.expectEqual(@as(i64, 1), selection.get());
}
