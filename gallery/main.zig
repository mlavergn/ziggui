const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_main);
const gallery = @import("gallery");
const ziggui = @import("ziggui");

/// Log configuration for the executable.
pub const std_options: std.Options = .{
    .log_level = if (gallery.is_debug) .debug else .warn,
};

/// The command line: `ziggui-gallery [--section <n>] [--theme <n>] [--accent <n>]
/// [--dark] [--menu <n>] [--sheet] [--alert] [--popover] [--passthrough]
/// [--options-menu] [--find] [--dialog] [--select] [--screenshot <out.bmp>
/// [--gpu] [--bench <n>]]`.
///
/// `--accent` picks the accent switcher's choice `n`: 0 (the default) keeps
/// the theme's own accent; 1 to 8 are `ziggui.Accent.all` in order (Orange,
/// Blue, Purple, Pink, Red, Yellow, Green, Graphite), drawn as the apps draw
/// them (`ziggui.Accent.theme`); past 8 is Graphite.
///
/// `--menu` opens the Menu Bar section's menu `n`. `--sheet` and `--alert`
/// present the Overlays section's sheet and alert over any section;
/// `--popover`, `--passthrough` and `--options-menu` open its popover, its
/// passthrough popover and its Options menu (`--section 13`). `--find`,
/// `--dialog` and `--select` show the Editor section's find bar (after
/// `greeting`), its Open dialog, and a selection across three lines
/// (`--section 17`).
///
/// `--gpu` draws the `--screenshot` frame through the SDL_GPU pipeline,
/// offscreen (no window), instead of the software rasterizer: the same build,
/// size and theme, so the two BMPs differ only by the backend (to within 1 LSB
/// a channel). `--bench <n>` then draws that frame `n` times more and prints
/// the milliseconds per frame, read back to RGBA8 (on the GPU, a full sync).
const Arguments = struct {
    const Self = @This();

    /// The width `--screenshot` draws at, in points.
    const screenshot_width: u32 = 980;

    /// The height `--screenshot` draws at, in points.
    const screenshot_height: u32 = 660;

    /// The sidebar row to open on.
    section: i64 = 0,

    /// The theme family to open in, an index into `ziggui.ThemeFamily.all`.
    theme: i64 = 0,

    /// The accent switcher's choice to open with: 0 keeps the theme's own,
    /// n is `ziggui.Accent.all[n - 1]`.
    accent: i64 = 0,

    /// Open in the dark appearance instead of following the OS.
    dark: bool = false,

    /// The Menu Bar panel's menu to open, for a screenshot of it.
    menu: ?usize = null,

    /// Present the Overlays panel's sheet.
    sheet: bool = false,

    /// Present the Overlays panel's alert.
    alert: bool = false,

    /// Present the Overlays panel's popover.
    popover: bool = false,

    /// Present the Overlays panel's passthrough popover.
    passthrough: bool = false,

    /// Open the Overlays panel's Options menu.
    options_menu: bool = false,

    /// Show the Editor panel's find bar, its first match selected.
    find: bool = false,

    /// Present the Editor panel's Open dialog.
    dialog: bool = false,

    /// Select across three of the Editor panel's lines.
    select: bool = false,

    /// Draw one frame to this BMP instead of opening a window.
    screenshot: ?[]const u8 = null,

    /// Draw the screenshot through the GPU pipeline, offscreen.
    gpu: bool = false,

    /// How many more times to draw the screenshot, timed (0: none).
    bench: u32 = 0,

    /// Reads the argument vector; unknown or malformed arguments are logged and skipped.
    ///
    /// - `argument_vector`: the full argument vector, program name included.
    /// - Returns: the parsed arguments.
    fn parse(argument_vector: []const [:0]const u8) Self {
        var arguments: Self = .{};
        var index: usize = 1;
        while (index < argument_vector.len) : (index += 1) {
            const argument = argument_vector[index];
            if (std.mem.eql(u8, argument, "--dark")) {
                arguments.dark = true;
            } else if (std.mem.eql(u8, argument, "--sheet")) {
                arguments.sheet = true;
            } else if (std.mem.eql(u8, argument, "--alert")) {
                arguments.alert = true;
            } else if (std.mem.eql(u8, argument, "--popover")) {
                arguments.popover = true;
            } else if (std.mem.eql(u8, argument, "--passthrough")) {
                arguments.passthrough = true;
            } else if (std.mem.eql(u8, argument, "--options-menu")) {
                arguments.options_menu = true;
            } else if (std.mem.eql(u8, argument, "--find")) {
                arguments.find = true;
            } else if (std.mem.eql(u8, argument, "--dialog")) {
                arguments.dialog = true;
            } else if (std.mem.eql(u8, argument, "--select")) {
                arguments.select = true;
            } else if (std.mem.eql(u8, argument, "--gpu")) {
                arguments.gpu = true;
            } else if (std.mem.eql(u8, argument, "--bench") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.bench = std.fmt.parseInt(u32, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --bench {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, argument, "--theme") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.theme = std.fmt.parseInt(i64, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --theme {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, argument, "--screenshot") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.screenshot = argument_vector[index];
            } else if (std.mem.eql(u8, argument, "--section") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.section = std.fmt.parseInt(i64, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --section {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, argument, "--menu") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.menu = std.fmt.parseInt(usize, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --menu {s} [{t}]", .{ argument_vector[index], err });
                    break :blk null;
                };
            } else if (std.mem.eql(u8, argument, "--accent") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.accent = std.fmt.parseInt(i64, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --accent {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else {
                log.warn("ignoring argument {s}", .{argument});
            }
        }
        return arguments;
    }

    /// Sets up the overlays and demos the arguments ask for.
    ///
    /// - `self`: the arguments.
    /// - `shown`: the gallery to set up.
    fn apply(self: *const Self, shown: *gallery.Gallery) void {
        if (self.menu) |menu| if (menu < shown.barMenus().len) shown.menu_bar.open(menu);
        if (self.sheet) shown.showcase.openSheet();
        if (self.alert) shown.showcase.openAlert();
        if (self.popover) shown.showcase.show_popover.set(true);
        if (self.passthrough) shown.showcase.show_pass_popover.set(true);
        if (self.options_menu) shown.showcase.menu_open.set(true);
        if (self.find) shown.editor.showMatch("greeting");
        if (self.dialog) shown.editor.openDialog();
        if (self.select) shown.editor.selectBetween("const greeting", "// Click");
    }
};

/// Entry point for the ziggui gallery.
///
/// Everything the window shows is `gallery.Gallery`; this file only connects
/// it to SDL (`ziggui_app`), or with `--screenshot` draws one frame headless.
///
/// - `init`: process capabilities supplied by the runtime (allocator, IO, args).
/// - Returns: nothing on success; propagates allocation, file and window-system failures.
pub fn main(init: std.process.Init) !void {
    log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

    const allocator = init.gpa;
    const arguments = Arguments.parse(try init.minimal.args.toSlice(init.arena.allocator()));

    const shown = try allocator.create(gallery.Gallery);
    defer allocator.destroy(shown);
    shown.* = try gallery.Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(arguments.section);
    shown.theme_family.set(arguments.theme);
    shown.accent.set(arguments.accent);
    shown.dark.set(arguments.dark);
    arguments.apply(shown);

    if (arguments.screenshot) |out| {
        const options: ziggui.ScreenshotOptions = .{
            .width = Arguments.screenshot_width,
            .height = Arguments.screenshot_height,
            .theme = shown.theme(),
        };
        if (!arguments.gpu and arguments.bench == 0) {
            const rgba = try ziggui.Screenshot.render(allocator, shown, gallery.Gallery.body, options);
            defer allocator.free(rgba);
            try Frame.write(allocator, init.io, out, rgba, options);
            std.debug.print("wrote {s} ({d}x{d})\n", .{ out, options.width, options.height });
            return;
        }

        const frame = try Frame.create(allocator, options);
        defer frame.destroy();
        try frame.build(shown);
        if (arguments.gpu) try frame.useGpu();
        const rgba = try frame.draw();
        defer allocator.free(rgba);
        try Frame.write(allocator, init.io, out, rgba, options);
        std.debug.print("wrote {s} ({d}x{d}, {s})\n", .{ out, options.width, options.height, frame.backendName() });
        if (arguments.bench > 0) try frame.bench(init.io, arguments.bench);
        return;
    }
    if (arguments.gpu or arguments.bench > 0) log.warn("--gpu and --bench draw a --screenshot; ignoring them", .{});

    try Window.run(allocator, shown, !arguments.dark);
}

/// The `--screenshot` frame as draw commands, for `--gpu` and `--bench`: the
/// gallery built by `ziggui.ScreenshotFrame` exactly as `ziggui.Screenshot.render`
/// builds it, then drawn by the software rasterizer or, after `useGpu`, the
/// SDL_GPU pipeline offscreen.
///
/// Heap-allocated (`create`), as the `ScreenshotFrame` it holds is.
const Frame = struct {
    const Self = @This();

    /// The allocator the frame, its GPU device and its images come from.
    allocator: std.mem.Allocator,

    /// The fonts, caches and arena the gallery is built with; holds the commands.
    screenshot: *ziggui.ScreenshotFrame,

    /// The arena the GPU translates the commands into, reset by each `draw`.
    scene_arena: std.heap.ArenaAllocator,

    /// The offscreen GPU backend once `useGpu` started it (SDL's video is up while it is set).
    gpu: ?ziggui.sdl.Gpu = null,

    /// Makes a frame with nothing built yet.
    ///
    /// - `allocator`: allocator for the frame, its caches and its images.
    /// - `options`: the size, theme and frame count, as `ziggui.Screenshot.render` takes them.
    /// - Returns: the frame, owned by the caller (`destroy`); propagates allocation failure.
    fn create(allocator: std.mem.Allocator, options: ziggui.ScreenshotOptions) !*Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const screenshot = try ziggui.ScreenshotFrame.create(allocator, options);
        errdefer screenshot.destroy();
        const self = try allocator.create(Self);
        self.* = .{ .allocator = allocator, .screenshot = screenshot, .scene_arena = .init(allocator) };
        return self;
    }

    /// Frees the frame and its GPU device, and stops SDL's video if `useGpu` started it.
    ///
    /// - `self`: the frame; invalid afterwards.
    fn destroy(self: *Self) void {
        if (self.gpu) |*gpu| {
            gpu.deinit();
            ziggui.sdl.sdl_c.SDL_Quit();
        }
        self.scene_arena.deinit();
        self.screenshot.destroy();
        self.allocator.destroy(self);
    }

    /// Encodes RGBA8 pixels as a BMP and writes it.
    ///
    /// - `allocator`: allocator for the file's bytes.
    /// - `io`: the I/O the file is written with.
    /// - `path`: where to write it.
    /// - `rgba`: the pixels, rows top-down.
    /// - `options`: the image's size.
    /// - Returns: nothing; propagates allocation and file failures.
    fn write(allocator: std.mem.Allocator, io: std.Io, path: []const u8, rgba: []const u8, options: ziggui.ScreenshotOptions) !void {
        const image = try ziggui.Screenshot.bmp(allocator, rgba, options.width, options.height);
        defer allocator.free(image);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = image });
    }

    /// Builds the gallery's draw commands, as `ziggui.Screenshot.render` does.
    ///
    /// - `self`: the frame.
    /// - `shown`: the gallery to draw.
    /// - Returns: nothing; propagates allocation and painting failures.
    fn build(self: *Self, shown: *gallery.Gallery) !void {
        _ = try self.screenshot.build(shown, gallery.Gallery.body);
    }

    /// Draws with the SDL_GPU pipeline, offscreen, from now on (`--gpu`). No
    /// window opens; there is no fallback to the software rasterizer.
    ///
    /// - `self`: the frame.
    /// - Returns: nothing; `error.NoGpuBackend` (logged) when SDL's video or a GPU device cannot start.
    fn useGpu(self: *Self) !void {
        // A plain SDL_Init(VIDEO) would make the process a regular macOS app, with a Dock icon.
        _ = ziggui.sdl.sdl_c.SDL_SetHint(ziggui.sdl.sdl_c.SDL_HINT_MAC_BACKGROUND_APP, "1");
        if (!ziggui.sdl.sdl_c.SDL_Init(ziggui.sdl.sdl_c.SDL_INIT_VIDEO)) {
            log.err("--gpu: SDL_Init failed: {s}", .{ziggui.sdl.sdl_c.SDL_GetError()});
            return error.NoGpuBackend;
        }
        self.gpu = ziggui.sdl.Gpu.init(self.allocator, null) orelse {
            log.err("--gpu: no GPU backend: {s}", .{ziggui.sdl.sdl_c.SDL_GetError()});
            ziggui.sdl.sdl_c.SDL_Quit();
            return error.NoGpuBackend;
        };
    }

    /// What `draw` draws with, for the log lines.
    ///
    /// - `self`: the frame.
    /// - Returns: "raster", or the GPU driver's name ("metal", "vulkan", "direct3d12").
    fn backendName(self: *const Self) []const u8 {
        if (self.gpu) |*gpu| return gpu.driverName();
        return "raster";
    }

    /// Draws the built commands over the theme's window background: through
    /// the GPU after `useGpu`, else with the software rasterizer.
    ///
    /// - `self`: the frame.
    /// - Returns: the image as RGBA8, rows top-down, owned by the caller;
    ///   `error.GpuRenderFailed` when the GPU fails; propagates allocation and rasterizing failures.
    fn draw(self: *Self) ![]u8 {
        const options = self.screenshot.options;
        if (self.gpu) |*gpu| {
            _ = self.scene_arena.reset(.retain_capacity);
            return gpu.renderToRgba(self.scene_arena.allocator(), self.screenshot.commands, options.theme.colors.window_background, options.width, options.height) orelse error.GpuRenderFailed;
        }
        return self.screenshot.rasterize();
    }

    /// Draws the frame `count` times and prints the wall-clock milliseconds a
    /// frame took (`--bench`), each read back to RGBA8, so on the GPU a full sync.
    ///
    /// - `self`: the frame.
    /// - `io`: the I/O whose clock times the draws.
    /// - `count`: how many draws to time; at least one.
    /// - Returns: nothing; propagates `draw`'s failures.
    fn bench(self: *Self, io: std.Io, count: u32) !void {
        const start = std.Io.Timestamp.now(io, .awake);
        for (0..count) |_| self.allocator.free(try self.draw());
        const elapsed = start.untilNow(io, .awake);
        const nanoseconds: f64 = @floatFromInt(elapsed.toNanoseconds());
        const milliseconds = nanoseconds / std.time.ns_per_ms / @as(f64, @floatFromInt(count));
        std.debug.print("{s}: {d:.2} ms/frame over {d} frames ({d} commands)\n", .{ self.backendName(), milliseconds, count, self.screenshot.commands.len });
    }
};

/// The window: SDL's hooks into the gallery. SDL's hooks are plain functions,
/// so they reach the gallery through `shown`, set before the loop starts.
const Window = struct {
    const Self = @This();

    /// The gallery the window draws, while the loop runs.
    var shown: ?*gallery.Gallery = null;

    /// Whether the appearance should still be seeded from the OS, on the first frame.
    var follow_os = false;

    /// Runs the window until it closes.
    ///
    /// - `allocator`: allocator for the loop.
    /// - `target`: the gallery to draw.
    /// - `follow`: seed the light/dark appearance from the OS once SDL is up.
    /// - Returns: nothing; propagates allocation and window-system failures.
    fn run(allocator: std.mem.Allocator, target: *gallery.Gallery, follow: bool) !void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        Self.shown = target;
        defer Self.shown = null;
        Self.follow_os = follow;
        target.showcase.platform = .{
            .minimize_fn = Self.minimize,
            .toggle_maximized_fn = Self.toggleMaximized,
            .is_maximized_fn = Self.isMaximized,
            .request_close_fn = Self.requestClose,
            .quit_fn = Self.quit,
            .animator_fn = Self.animator,
        };
        defer target.showcase.platform = .{};

        const app = ziggui.App.shared();
        app.setThemeProvider(Self.theme);
        app.setKeyHandler(Self.onKey);
        app.setKeyUpHandler(Self.onKeyUp);
        app.setQuitHandler(Self.onQuit);
        app.setMouseHandler(Self.onMouse);
        app.setBusyInterval(Self.wakeInterval);
        try app.run(allocator, gallery.Gallery, target, .{
            .title = "ziggui — Gallery",
            .width = 980,
            .height = 660,
            .min_width = 640,
            .min_height = 420,
            .theme = target.theme(),
        }, gallery.Gallery.body, null);
    }

    /// Minimizes the window (the Window section's minimize button).
    fn minimize() void {
        ziggui.App.shared().minimizeWindow();
    }

    /// Maximizes or restores the window (the Window section's maximize button).
    fn toggleMaximized() void {
        ziggui.App.shared().toggleMaximized();
    }

    /// Whether the window is maximized.
    ///
    /// - Returns: true when it is.
    fn isMaximized() bool {
        return ziggui.App.shared().isMaximized();
    }

    /// Asks to close the window, as its own close button does.
    fn requestClose() void {
        ziggui.App.shared().requestClose();
    }

    /// Ends the loop without asking.
    fn quit() void {
        ziggui.App.shared().quit();
    }

    /// The running loop's animator.
    ///
    /// - Returns: the animator, or null outside the loop.
    fn animator() ?*ziggui.Animator {
        return ziggui.App.shared().animator();
    }

    /// How often the loop wakes: every frame while a hover popover waits out
    /// its delay (the pointer resting sends no events), else idle.
    ///
    /// - Returns: milliseconds between wakes, 0 for none.
    fn wakeInterval() u32 {
        const target = Self.shown orelse return 0;
        return if (target.hoverWaiting()) 16 else 0;
    }

    /// A key went down: the Menu Bar panel's Alt tap and menu keys, and the
    /// Editor panel's shortcuts.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a panel used it.
    fn onKey(keycode: u32, modifiers: u16) bool {
        const target = Self.shown orelse return false;
        return target.keyDown(keycode, modifiers);
    }

    /// A key came up: Alt ends a tap; the Overlays panel shows the keycode.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    fn onKeyUp(keycode: u32, modifiers: u16) void {
        _ = modifiers;
        const target = Self.shown orelse return;
        target.keyUp(keycode);
    }

    /// A quit was asked for: the Overlays panel may ask first.
    ///
    /// - Returns: true to let the quit end the loop.
    fn onQuit() bool {
        const target = Self.shown orelse return true;
        return target.quitRequested();
    }

    /// A mouse event: a press cancels an Alt tap; none is consumed.
    ///
    /// - `event`: the event.
    /// - Returns: false, so ziggui handles it as usual.
    fn onMouse(event: ziggui.MouseEvent) bool {
        const target = Self.shown orelse return false;
        if (event.kind == .down) target.menu_bar.pointerDown();
        return false;
    }

    /// The theme provider: the gallery's selection, the OS appearance on the first frame.
    ///
    /// - Returns: the theme to draw this frame with.
    fn theme() ziggui.Theme {
        const target = Self.shown orelse return ziggui.Theme.default;
        if (Self.follow_os) {
            // SDL is up by the time the loop asks, so the OS can answer.
            target.dark.set(ziggui.App.shared().colorScheme() == .dark);
            Self.follow_os = false;
        }
        return target.theme();
    }
};
