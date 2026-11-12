//! End-to-end integration tests: build a realistic SwiftUI-style screen with
//! the public component API, render it through the full pipeline (view → layout
//! → canvas → software rasterizer), and assert on the resulting pixels and on
//! interaction. This exercises the whole stack headlessly and stands in for the
//! `examples/settings` demo in CI.

const std = @import("std");
const log = std.log.scoped(.ziggui_integration_test);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A settings screen's state: a Wi‑Fi switch and a brightness slider.
const Settings = struct {
    const Self = @This();

    /// Whether Wi‑Fi is on.
    wifi: renderer.State(bool),

    /// The brightness, 0 to 1.
    brightness: renderer.State(f32),

    /// The settings screen: a title, a card of controls, a progress bar.
    ///
    /// - `self`: the state.
    /// - Returns: the screen.
    fn body(self: *Self) mod.View {
        const theme = renderer.MacosTheme.light;
        const card = mod.VStack(.{
            mod.HStack(.{
                mod.Label("Wi‑Fi", theme.colors.accent),
                mod.Spacer(),
                mod.Toggle("", self.wifi.binding()),
            }).frameMaxWidth(),
            mod.Divider(),
            mod.HStack(.{
                mod.Text("Brightness"),
                mod.Spacer(),
                mod.Slider(self.brightness.binding(), 0, 1).frameWidth(160),
            }).frameMaxWidth(),
        }).spacing(10)
            .padding(14)
            .background(theme.colors.control_background)
            .cornerRadius(10)
            .frameMaxWidth();

        return mod.VStack(.{
            mod.Text("Settings").font(.largeTitle).frameMaxWidth(),
            card,
            mod.ProgressView(0.62).frameMaxWidth(),
            mod.Spacer(),
        }).spacing(16).padding(20).frameMaxWidth();
    }
};

/// A headless frame: a font, its glyph cache, the build arena and the tap regions.
const Harness = struct {
    const Self = @This();

    /// The font text is drawn in.
    font: renderer.Font,

    /// The font's glyphs; set by `start`.
    cache: renderer.GlyphCache,

    /// The build arena.
    arena: std.heap.ArenaAllocator,

    /// The frame's tap regions.
    hits: std.ArrayList(mod.HitRegion),

    /// A harness not yet started.
    ///
    /// - Returns: the harness.
    fn init() Self {
        const self = Self{
            .font = renderer.Font.default(),
            .cache = undefined,
            .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
            .hits = .empty,
        };
        return self;
    }

    /// Frees the glyph cache and the arena, ending the build.
    ///
    /// - `self`: the harness.
    fn deinit(self: *Self) void {
        mod.BuildScope.shared().end();
        self.cache.deinit();
        self.arena.deinit();
    }

    /// Makes the glyph cache and begins a build.
    ///
    /// - `self`: the harness; must not move afterward.
    fn start(self: *Self) void {
        self.cache = renderer.GlyphCache.init(std.testing.allocator, &self.font.face);
        mod.BuildScope.shared().begin(self.arena.allocator());
    }

    /// A paint context over the harness, in the macOS light theme.
    ///
    /// - `self`: the harness.
    /// - Returns: the context.
    fn context(self: *Self) mod.Context {
        return mod.Context.init(renderer.MacosTheme.light, &self.cache, self.arena.allocator(), &self.hits);
    }
};

/// A showcase screen's state: the selected tab, a switch, a sheet.
const Showcase = struct {
    const Self = @This();

    /// The selected tab.
    tab: renderer.State(i64),

    /// Whether Wi‑Fi is on.
    wifi: renderer.State(bool),

    /// Whether the sheet is presented.
    show_sheet: renderer.State(bool),

    /// Presents the sheet.
    ///
    /// - `self`: the state.
    fn openSheet(self: *Self) void {
        self.show_sheet.set(true);
    }

    /// The showcase: a navigation split of a sidebar and tabs, with a sheet.
    ///
    /// - `self`: the state.
    /// - Returns: the screen.
    fn body(self: *Self) mod.View {
        const tabs = [_]mod.Tab{
            .{
                .label = "General",
                .content = mod.VStack(.{
                    mod.Toggle("Wi‑Fi", self.wifi.binding()).frameMaxWidth(),
                    // a frosted material card -> emits a blurRect
                    mod.Text("Frosted").padding(10).backgroundMaterial(.regular),
                }).spacing(8).frameMaxWidth(),
            },
            .{ .label = "Advanced", .content = mod.Text("Advanced") },
        };
        const sidebar = mod.VStack(.{
            mod.Text("Settings").font(.headline),
            mod.Button("Open Sheet", mod.Callback.init(Self, self, Self.openSheet)),
            mod.Spacer(),
        }).spacing(8);
        const detail = mod.TabView(self.tab.binding(), &tabs).frameMaxWidth();
        return mod.NavigationSplitView(sidebar, detail, renderer.MacosTheme.light.colors.secondary_background)
            .sheet(self.show_sheet.binding(), mod.Text("This is a sheet").padding(20));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "integration: settings screen renders a rich, non-empty frame" {
    var harness = Harness.init();
    harness.start();
    defer harness.deinit();

    var settings = Settings{
        .wifi = renderer.State(bool).init(std.testing.allocator, true),
        .brightness = renderer.State(f32).init(std.testing.allocator, 0.7),
    };
    defer {
        settings.wifi.deinit();
        settings.brightness.deinit();
    }

    var context = harness.context();
    const tree = settings.body();

    var canvas = renderer.Canvas.init(harness.arena.allocator());
    const width: u32 = 400;
    const height: u32 = 500;
    try canvas.fillRect(.{ .x = 0, .y = 0, .width = width, .height = height }, renderer.MacosTheme.light.colors.window_background);
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = width, .height = height }, &canvas);

    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, width, height);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.MacosTheme.light.colors.window_background);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);

    // The screen should produce a substantial command list...
    try std.testing.expect(canvas.count() > 15);
    // ...register interactive regions (toggle + slider)...
    try std.testing.expect(harness.hits.items.len >= 2);

    // ...and ink a meaningful number of dark (text) and accent (controls) pixels.
    var dark: u32 = 0;
    var accent: u32 = 0;
    for (framebuffer.pixels) |pixel| {
        if (pixel.luminance() < 0.45) dark += 1;
        if (pixel.b > pixel.r + 0.2 and pixel.b > 0.4) accent += 1;
    }
    try std.testing.expect(dark > 100); // title + labels rendered
    try std.testing.expect(accent > 50); // wifi switch (on) + slider fill + progress
}

test "integration: tapping the Wi‑Fi toggle flips state across a rebuild" {
    var harness = Harness.init();
    harness.start();
    defer harness.deinit();

    var settings = Settings{
        .wifi = renderer.State(bool).init(std.testing.allocator, true),
        .brightness = renderer.State(f32).init(std.testing.allocator, 0.5),
    };
    defer {
        settings.wifi.deinit();
        settings.brightness.deinit();
    }

    var context = harness.context();
    var canvas = renderer.Canvas.init(harness.arena.allocator());
    const width: u32 = 400;
    const height: u32 = 500;
    try mod.ViewRenderer.render(&context, settings.body(), .{ .x = 0, .y = 0, .width = width, .height = height }, &canvas);

    // Find the toggle hit region and tap its center.
    var tapped = false;
    for (harness.hits.items) |region| {
        if (region.action == .toggle) {
            try std.testing.expect(mod.PointerInput.shared().tap(harness.hits.items, region.rect.center()));
            tapped = true;
            break;
        }
    }
    try std.testing.expect(tapped);
    try std.testing.expect(!settings.wifi.get()); // flipped from true to false
}

test "integration: nav + tabs + sheet + material + a11y compose in one render" {
    var harness = Harness.init();
    harness.start();
    defer harness.deinit();

    var showcase = Showcase{
        .tab = renderer.State(i64).init(std.testing.allocator, 0),
        .wifi = renderer.State(bool).init(std.testing.allocator, true),
        .show_sheet = renderer.State(bool).init(std.testing.allocator, true),
    };
    defer {
        showcase.tab.deinit();
        showcase.wifi.deinit();
        showcase.show_sheet.deinit();
    }

    var context = harness.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    var a11y: std.ArrayList(mod.A11yNode) = .empty;
    context.overlays = &overlays;
    context.a11y = &a11y;

    var canvas = renderer.Canvas.init(harness.arena.allocator());
    const width: u32 = 600;
    const height: u32 = 460;
    try mod.ViewRenderer.render(&context, showcase.body(), .{ .x = 0, .y = 0, .width = width, .height = height }, &canvas);

    // the .sheet was presented -> one overlay collected, drawn as a scrim
    try std.testing.expectEqual(@as(usize, 1), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.sheet, overlays.items[0].style);

    // the material card emitted a blur command
    var has_blur = false;
    for (canvas.commands.items) |command| {
        if (command == .blurRect) has_blur = true;
    }
    try std.testing.expect(has_blur);

    // the accessibility tree captured the toggle (as a switch) and the button
    var switch_on = false;
    var has_button = false;
    for (a11y.items) |node| {
        if (node.role == .toggle and std.mem.eql(u8, node.value, "on")) switch_on = true;
        if (node.role == .button and std.mem.eql(u8, node.label, "Open Sheet")) has_button = true;
    }
    try std.testing.expect(switch_on);
    try std.testing.expect(has_button);

    // Dismiss the modal (its scrim correctly blocks taps to the content beneath),
    // then re-render and tap the second tab segment to switch tabs.
    showcase.show_sheet.set(false);
    harness.hits.clearRetainingCapacity();
    overlays.clearRetainingCapacity();
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, showcase.body(), .{ .x = 0, .y = 0, .width = width, .height = height }, &canvas);
    try std.testing.expectEqual(@as(usize, 0), overlays.items.len); // no overlay now

    var switched = false;
    for (harness.hits.items) |region| {
        if (region.action == .select and region.action.select.value == 1) {
            try std.testing.expect(mod.PointerInput.shared().tap(harness.hits.items, region.rect.center()));
            switched = true;
            break;
        }
    }
    try std.testing.expect(switched);
    try std.testing.expectEqual(@as(i64, 1), showcase.tab.get());
}
