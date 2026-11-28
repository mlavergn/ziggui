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
/// [--options-menu] [--picker-menu] [--find] [--replace] [--editor-style] [--dialog] [--select] [--rename] [--path-entry]
/// [--search <text>] [--components] [--video <url or path>] [--ray-traced]
/// [--screenshot <out.bmp> [--size <w>x<h>] [--gpu] [--workers <n>] [--bench <n>]]`.
///
/// `--video` is what the Media Video section's "Load sample stream" plays instead
/// of Apple's HLS example: a URL or a local path (a Linux system may have no
/// H.264 decoder, which the example needs).
///
/// `--accent` picks the accent switcher's choice `n`: 0 (the default) keeps
/// the theme's own accent; 1 to 8 are `ziggui.Accent.all` in order (Orange,
/// Blue, Purple, Pink, Red, Yellow, Green, Graphite), drawn as the apps draw
/// them (`ziggui.Accent.theme`); past 8 is Graphite.
///
/// `--menu` opens the Menus & Commands section's menu `n` (`--section 10`).
/// `--sheet` and `--alert` present the Presentations section's sheet and
/// alert over any section; `--popover`, `--passthrough` and `--options-menu`
/// open its popover, its passthrough popover and its Options menu
/// (`--section 9`). `--picker-menu` opens the Pickers section's first menu
/// (`--section 3`), as the theme family opens it (`--theme`). `--find`,
/// `--dialog` and `--select` show the Text Editor section's find bar (after
/// `greeting`), its Open dialog, and a selection across three lines
/// (`--section 1`); `--replace` shows the find bar with its replace row
/// (`greeting` to `salutation`), and `--editor-style` dresses the editor in
/// a style of its own (Noto Serif, colors for its text, ground, caret,
/// selection, gutter, current line and matches, the colors bar open, `total`
/// found). `--rename` shows the Lists section's renamed row, its
/// name selected (`--section 6`). `--path-entry` shows the Files section's
/// path bar as the field a path is typed into (`--section 14`). `--search` types
/// its text into the sidebar's search, which shows its first match.
/// `--components` has the sidebar list every component the cards name, as
/// the top bar's switch does. `--ray-traced` turns on the Scenes section's
/// ray tracing (`--section 21`), drawn traced only through `--gpu` on a GPU
/// that traces rays.
///
/// `--gpu` draws the `--screenshot` frame through the SDL_GPU pipeline,
/// offscreen (no window), instead of the software rasterizer: the same build,
/// size and theme, so the two BMPs differ only by the backend (to within 1 LSB
/// a channel). `--bench <n>` then draws that frame `n` times more and prints
/// the milliseconds per frame, read back to RGBA8 (on the GPU, a full sync).
/// `--size` draws at another size than 980×660 points, one pixel each (a 4K
/// window is `--size 3840x2160`). `--workers <n>` rasterizes with `n`
/// workers (`ziggui.ParallelRasterizer`, as a window's software path does; 0
/// picks the machine's default), into buffers kept across `--bench`'s draws,
/// as a window keeps them; the image is the same bytes whatever `n`.
const Arguments = struct {
    const Self = @This();

    /// The width `--screenshot` draws at, in points.
    const screenshot_width: u32 = 980;

    /// The height `--screenshot` draws at, in points.
    const screenshot_height: u32 = 660;

    /// The largest side `--size` takes, in points (16K, the largest texture
    /// side GPUs commonly allow).
    const max_screenshot_side: u32 = 16384;

    /// The sidebar row to open on.
    section: i64 = 0,

    /// The theme family to open in, an index into `ziggui.ThemeFamily.all`.
    theme: i64 = 0,

    /// The accent switcher's choice to open with: 0 keeps the theme's own,
    /// n is `ziggui.Accent.all[n - 1]`.
    accent: i64 = 0,

    /// Open in the dark appearance instead of following the OS.
    dark: bool = false,

    /// The Menus & Commands section's menu to open, for a screenshot of it.
    menu: ?usize = null,

    /// Present the Presentations section's sheet.
    sheet: bool = false,

    /// Present the Presentations section's alert.
    alert: bool = false,

    /// Present the Presentations section's popover.
    popover: bool = false,

    /// Present the Presentations section's passthrough popover.
    passthrough: bool = false,

    /// Open the Presentations section's Options menu.
    options_menu: bool = false,

    /// Open the Pickers panel's first menu.
    picker_menu: bool = false,

    /// Show the Text Editor section's find bar, its first match selected.
    find: bool = false,

    /// Show the Text Editor section's find bar with its replace row.
    replace: bool = false,

    /// Dress the Text Editor section in a font and colors of its own.
    editor_style: bool = false,

    /// List every component in the sidebar, as the top bar's switch does.
    components: bool = false,

    /// Present the Text Editor section's Open dialog.
    dialog: bool = false,

    /// Select across three of the Text Editor section's lines.
    select: bool = false,

    /// Rename the Lists section's rename card's second row, its name selected in the field.
    rename: bool = false,
    /// Show the Files section's path bar as the field a path is typed into.
    path_entry: bool = false,
    /// Turn on the Scenes section's ray tracing.
    ray_traced: bool = false,
    /// Show the Media Audio section's voice memos with two sample memos, one
    /// playing, and a take recording, on `ziggui.TestAudioDevices` (headless).
    memos: bool = false,

    /// Draw one frame to this BMP instead of opening a window.
    screenshot: ?[]const u8 = null,

    /// Draw the screenshot through the GPU pipeline, offscreen.
    gpu: bool = false,

    /// How many more times to draw the screenshot, timed (0: none).
    bench: u32 = 0,

    /// The screenshot's width, in points.
    width: u32 = Self.screenshot_width,

    /// The screenshot's height, in points.
    height: u32 = Self.screenshot_height,

    /// How many workers rasterize the screenshot (0: the machine's default),
    /// or null for `ziggui.Screenshot.render`'s one thread.
    workers: ?u32 = null,

    /// What the Media Video section plays instead of its sample, or null.
    video: ?[:0]const u8 = null,

    /// What to type into the sidebar's search, or null.
    search: ?[:0]const u8 = null,

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
            } else if (std.mem.eql(u8, argument, "--picker-menu")) {
                arguments.picker_menu = true;
            } else if (std.mem.eql(u8, argument, "--find")) {
                arguments.find = true;
            } else if (std.mem.eql(u8, argument, "--replace")) {
                arguments.replace = true;
            } else if (std.mem.eql(u8, argument, "--editor-style")) {
                arguments.editor_style = true;
            } else if (std.mem.eql(u8, argument, "--components")) {
                arguments.components = true;
            } else if (std.mem.eql(u8, argument, "--dialog")) {
                arguments.dialog = true;
            } else if (std.mem.eql(u8, argument, "--select")) {
                arguments.select = true;
            } else if (std.mem.eql(u8, argument, "--rename")) {
                arguments.rename = true;
            } else if (std.mem.eql(u8, argument, "--path-entry")) {
                arguments.path_entry = true;
            } else if (std.mem.eql(u8, argument, "--ray-traced")) {
                arguments.ray_traced = true;
            } else if (std.mem.eql(u8, argument, "--memos")) {
                arguments.memos = true;
            } else if (std.mem.eql(u8, argument, "--gpu")) {
                arguments.gpu = true;
            } else if (std.mem.eql(u8, argument, "--bench") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.bench = std.fmt.parseInt(u32, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --bench {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, argument, "--workers") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.workers = std.fmt.parseInt(u32, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --workers {s} [{t}]", .{ argument_vector[index], err });
                    break :blk null;
                };
            } else if (std.mem.eql(u8, argument, "--size") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.parseSize(argument_vector[index]);
            } else if (std.mem.eql(u8, argument, "--theme") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.theme = std.fmt.parseInt(i64, argument_vector[index], 10) catch |err| blk: {
                    log.warn("ignoring --theme {s} [{t}]", .{ argument_vector[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, argument, "--search") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.search = argument_vector[index];
            } else if (std.mem.eql(u8, argument, "--video") and index + 1 < argument_vector.len) {
                index += 1;
                arguments.video = argument_vector[index];
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

    /// Reads `--size`'s `<width>x<height>`, each at least 1; a malformed
    /// size is logged and the default kept.
    ///
    /// - `self`: the arguments.
    /// - `text`: the size as typed.
    fn parseSize(self: *Self, text: []const u8) void {
        const separator = std.mem.findScalar(u8, text, 'x') orelse {
            log.warn("ignoring --size {s}: not <width>x<height>", .{text});
            return;
        };
        const width = std.fmt.parseInt(u32, text[0..separator], 10) catch |err| {
            log.warn("ignoring --size {s} [{t}]", .{ text, err });
            return;
        };
        const height = std.fmt.parseInt(u32, text[separator + 1 ..], 10) catch |err| {
            log.warn("ignoring --size {s} [{t}]", .{ text, err });
            return;
        };
        if (width == 0 or height == 0) {
            log.warn("ignoring --size {s}: empty", .{text});
            return;
        }
        if (width > Self.max_screenshot_side or height > Self.max_screenshot_side) {
            log.warn("ignoring --size {s}: a side past {d}", .{ text, Self.max_screenshot_side });
            return;
        }
        self.width = width;
        self.height = height;
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
        if (self.picker_menu) shown.pickers.openMenu();
        if (self.find) shown.editor.showMatch("greeting");
        if (self.replace) shown.editor.showReplace("greeting", "salutation");
        if (self.editor_style) shown.editor.showStyle();
        if (self.components) _ = shown.search.setListing(.components);
        if (self.dialog) shown.editor.openDialog();
        if (self.select) shown.editor.selectBetween("const greeting", "// Click");
        if (self.rename) shown.kit.rename_on_show = 1;
        if (self.path_entry) shown.kit.path_entry_on_show = true;
        if (self.search) |text| shown.search.field.setText(text) catch |err| log.err("search not typed: {s}", .{@errorName(err)});
        if (self.video) |video| shown.media.sample = video;
        if (self.ray_traced) {
            shown.scene_demo.ray_traced.set(true);
            shown.sky_demo.ray_traced.set(true);
        }
        if (self.memos) {
            ziggui.TestAudioDevices.install();
            shown.media.memos.showSample();
            // A second into the memo playing, and a loud moment of the take.
            ziggui.TestAudioDevices.playOut(gallery.VoiceMemos.sample_rate);
            const loud: [64]i16 = @splat(-24_000);
            ziggui.TestAudioDevices.capture(&loud);
        }
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

    // Noto Serif, from the fixtures, for the Text Editor's font menus,
    // headless too; freed once every frame and window is gone.
    Fonts.register(allocator, init.io);
    defer ziggui.FontRegistry.shared().reset();

    const shown = try allocator.create(gallery.Gallery);
    defer allocator.destroy(shown);
    shown.* = try gallery.Gallery.init(allocator);
    defer shown.deinit();
    // The Files section's path bar takes `~` for the user's home (the map lives as long as the process).
    shown.kit.files.home = init.environ_map.get("HOME") orelse init.environ_map.get("USERPROFILE");

    shown.section.set(arguments.section);
    shown.theme_family.set(arguments.theme);
    shown.accent.set(arguments.accent);
    shown.dark.set(arguments.dark);
    arguments.apply(shown);

    if (arguments.screenshot) |out| {
        const options: ziggui.ScreenshotOptions = .{
            .width = arguments.width,
            .height = arguments.height,
            .theme = shown.theme(),
        };
        if (!arguments.gpu and arguments.bench == 0 and arguments.workers == null) {
            const rgba = try ziggui.Screenshot.render(allocator, shown, gallery.Gallery.body, options);
            defer allocator.free(rgba);
            try Frame.write(allocator, init.io, out, rgba, options);
            try Frame.report(init.io, "wrote {s} ({d}x{d})\n", .{ out, options.width, options.height });
            return;
        }

        const frame = try Frame.create(allocator, options);
        defer frame.destroy();
        // The GPU first, so the frame is built knowing what it can draw (the
        // Scenes section's ray tracing).
        if (arguments.gpu) try frame.useGpu();
        if (arguments.workers) |workers| try frame.useWorkers(init.io, workers);
        try frame.build(shown);
        const rgba = try frame.draw();
        try Frame.write(allocator, init.io, out, rgba, options);
        try Frame.report(init.io, "wrote {s} ({d}x{d}, {s})\n", .{ out, options.width, options.height, frame.backendName() });
        if (arguments.bench > 0) try frame.bench(init.io, arguments.bench);
        return;
    }
    if (arguments.gpu or arguments.bench > 0 or arguments.workers != null) log.warn("--gpu, --workers and --bench draw a --screenshot; ignoring them", .{});

    WindowSettings.load(allocator, init.io, init.environ_map);
    defer WindowSettings.unload();
    // `--editor-style` asks for its own look, which a saved one must not replace.
    EditorSettings.load(shown, !arguments.editor_style);
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

    /// The software path's workers once `useWorkers` made them; null draws
    /// on this thread alone.
    pool: ?*ziggui.WorkerPool = null,

    /// The software path's pixels, kept across draws as a window keeps them.
    framebuffer: ziggui.Framebuffer = .empty,

    /// The last draw's image, RGBA8; owned by the frame.
    rgba: []u8 = &.{},

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
        if (self.pool) |pool| pool.destroy();
        self.framebuffer.deinit();
        if (self.rgba.len > 0) self.allocator.free(self.rgba);
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
    /// window opens; there is no fallback to the software rasterizer. Notes
    /// whether the device traces rays (`SystemInfo.ray_tracing`), as a window
    /// would, so a frame built after it draws the Scenes toggle as a window does.
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
        self.gpu.?.noteRayTracing();
    }

    /// Rasterizes with `count` workers from now on (`--workers`), as a
    /// window's software path does; 0 picks the machine's default.
    ///
    /// - `self`: the frame.
    /// - `io`: the I/O the workers sleep and wake through.
    /// - `count`: how many workers, the calling thread included; 0 for the default.
    /// - Returns: nothing; propagates allocation failure.
    fn useWorkers(self: *Self, io: std.Io, count: u32) !void {
        const workers: usize = if (count == 0) ziggui.WorkerPool.defaultWorkerCount() else count;
        self.pool = try ziggui.WorkerPool.create(self.allocator, io, workers);
    }

    /// How many workers the software path draws with.
    ///
    /// - `self`: the frame.
    /// - Returns: the worker count, 1 without a pool.
    fn workerCount(self: *const Self) usize {
        return if (self.pool) |pool| pool.workerCount() else 1;
    }

    /// Writes a line of the headless run's report (what was written, the
    /// bench's timing) to standard output.
    ///
    /// - `io`: the I/O that writes it.
    /// - `format`: the line's format string.
    /// - `args`: the values it formats.
    /// - Returns: nothing; propagates a failed write.
    fn report(io: std.Io, comptime format: []const u8, args: anytype) !void {
        var buffer: [256]u8 = undefined;
        var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
        try stdout.interface.print(format, args);
        try stdout.interface.flush();
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
    /// the GPU after `useGpu`, else with the software rasterizer, on the
    /// workers after `useWorkers`, into the pixels kept from the last draw.
    ///
    /// - `self`: the frame.
    /// - Returns: the image as RGBA8, rows top-down, owned by the frame until
    ///   the next draw; `error.GpuRenderFailed` when the GPU fails; propagates
    ///   allocation and rasterizing failures.
    fn draw(self: *Self) ![]const u8 {
        const options = self.screenshot.options;
        if (self.gpu) |*gpu| {
            _ = self.scene_arena.reset(.retain_capacity);
            const rgba = gpu.renderToRgba(self.scene_arena.allocator(), self.screenshot.commands, options.theme.colors.window_background, options.width, options.height) orelse return error.GpuRenderFailed;
            if (self.rgba.len > 0) self.allocator.free(self.rgba);
            self.rgba = rgba;
            return self.rgba;
        }
        const byte_count = @as(usize, options.width) * options.height * 4;
        if (self.rgba.len != byte_count) {
            if (self.rgba.len > 0) self.allocator.free(self.rgba);
            self.rgba = &.{};
            self.rgba = try self.allocator.alloc(u8, byte_count);
        }
        try self.screenshot.rasterizeInto(&self.framebuffer, self.rgba, self.pool);
        return self.rgba;
    }

    /// Draws the frame `count` times and prints the wall-clock milliseconds a
    /// frame took (`--bench`), each read back to RGBA8, so on the GPU a full
    /// sync; the software path reuses its pixels, as a window does.
    ///
    /// - `self`: the frame.
    /// - `io`: the I/O whose clock times the draws.
    /// - `count`: how many draws to time; at least one.
    /// - Returns: nothing; propagates `draw`'s failures.
    fn bench(self: *Self, io: std.Io, count: u32) !void {
        const start = std.Io.Timestamp.now(io, .awake);
        for (0..count) |_| _ = try self.draw();
        const elapsed = start.untilNow(io, .awake);
        const nanoseconds: f64 = @floatFromInt(elapsed.toNanoseconds());
        const milliseconds = nanoseconds / std.time.ns_per_ms / @as(f64, @floatFromInt(count));
        const options = self.screenshot.options;
        try Self.report(io, "{s}: {d:.2} ms/frame over {d} frames ({d} commands, {d}x{d}, {d} workers)\n", .{ self.backendName(), milliseconds, count, self.screenshot.commands.len, options.width, options.height, self.workerCount() });
    }
};

/// Where the gallery's window was left, kept in a file of the user's
/// settings (`gallery-window.zon` in `%APPDATA%\ziggui` on Windows,
/// `~/Library/Application Support/ziggui` on macOS, `$XDG_CONFIG_HOME/ziggui`
/// or `~/.config/ziggui` elsewhere), so the window reopens where and as
/// large as it was. ziggui keeps no settings; `WindowMemory` says when to
/// save. A file that cannot be read or parsed is logged and ignored (the
/// window opens at its default), and replaced by the next save.
const WindowSettings = struct {
    const Self = @This();

    /// How often the window wakes while a moved or resized window settles,
    /// so it is saved once it rests, in milliseconds.
    const settle_wake_ms = 100;

    /// The file's name in the settings folder.
    const file_name = "gallery-window.zon";

    /// The longest file read; a saved place is a few dozen bytes.
    const most_bytes = 4096;

    /// Where the window was last left, from the file, then from each frame.
    var saved: ?ziggui.WindowPlace = null;

    /// When the place changed, so it is saved once it rests.
    var memory: ziggui.WindowMemory = .{};

    /// The settings folder, null where the environment names none.
    var folder: ?[]const u8 = null;

    /// The allocator `folder` and the reads use.
    var settings_allocator: std.mem.Allocator = undefined;

    /// The I/O the file is read and written through.
    var settings_io: std.Io = undefined;

    /// Finds the settings folder and reads the saved place, if any.
    ///
    /// - `allocator`: allocator for the folder's path and the read.
    /// - `io`: the I/O the file is read and written through.
    /// - `environment`: the process's environment, which names the folder.
    fn load(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map) void {
        Self.settings_allocator = allocator;
        Self.settings_io = io;
        Self.folder = Self.folderOf(allocator, environment) catch |err| blk: {
            log.warn("window place not kept: {s}", .{@errorName(err)});
            break :blk null;
        };
        const folder_path = Self.folder orelse return;
        const path = std.fs.path.join(allocator, &.{ folder_path, file_name }) catch |err| {
            log.warn("window place not read: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .limited(most_bytes), .of(u8), 0) catch |err| {
            if (err != error.FileNotFound) log.warn("window place not read from {s}: {s}", .{ path, @errorName(err) });
            return;
        };
        defer allocator.free(source);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        Self.saved = std.zon.parse.fromSlice(ziggui.WindowPlace, .{
            .gpa = allocator,
            .arena = arena.allocator(),
            .source = source,
            .diagnostics = &diagnostics,
            .ignore_unknown_fields = true,
        }) catch |err| blk: {
            log.warn("window place in {s} ignored: {s}", .{ path, @errorName(err) });
            break :blk null;
        };
    }

    /// Frees the folder's path.
    fn unload() void {
        if (Self.folder) |folder_path| Self.settings_allocator.free(folder_path);
        Self.folder = null;
    }

    /// The frame hook: notes where the window is, and saves it once it has
    /// rested `WindowMemory.settle_ms`.
    fn note() void {
        const now = ziggui.FrameClock.shared().time();
        Self.memory.noteWindow(&Self.saved, ziggui.App.shared().windowPlace(), now);
        if (Self.memory.due(now)) Self.write();
    }

    /// Saves a change that has not rested yet, as the loop ends. The window
    /// is gone by then, so only what `note` saw last frame is left to write.
    fn flush() void {
        if (Self.memory.due(null)) Self.write();
    }

    /// Writes the saved place to the file, making the folder if need be;
    /// a failure is logged and the place kept for the next save.
    fn write() void {
        const place = Self.saved orelse return;
        _ = Self.writeZon(file_name, place, "window place");
    }

    /// Writes a value as ZON to a file in the settings folder, making the
    /// folder if need be, through `replaceFile`; a failure is logged.
    ///
    /// - `name`: the file's name in the folder.
    /// - `value`: what to write.
    /// - `what`: what it is, for the log.
    /// - Returns: whether it was written.
    fn writeZon(name: []const u8, value: anytype, comptime what: []const u8) bool {
        const folder_path = Self.folder orelse return false;
        var buffer: [4096]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        var serializer: std.zon.Serializer = .{ .writer = &writer };
        serializer.value(value, .{}) catch |err| {
            log.warn(what ++ " not saved: {s}", .{@errorName(err)});
            return false;
        };
        writer.writeByte('\n') catch |err| {
            log.warn(what ++ " not saved: {s}", .{@errorName(err)});
            return false;
        };
        const path = std.fs.path.join(Self.settings_allocator, &.{ folder_path, name }) catch |err| {
            log.warn(what ++ " not saved: {s}", .{@errorName(err)});
            return false;
        };
        defer Self.settings_allocator.free(path);
        std.Io.Dir.cwd().createDirPath(Self.settings_io, folder_path) catch |err| {
            log.warn(what ++ " not saved: no folder {s}: {s}", .{ folder_path, @errorName(err) });
            return false;
        };
        Self.replaceFile(path, writer.buffered()) catch |err| {
            log.warn(what ++ " not saved to {s}: {s}", .{ path, @errorName(err) });
            return false;
        };
        return true;
    }

    /// Writes `data` to a temporary file beside `path`, then renames it over
    /// `path`, so a crash mid-write leaves the old file whole, never a torn one.
    ///
    /// - `path`: the file replaced.
    /// - `data`: its new contents.
    /// - Returns: nothing; propagates a failed create, write or rename.
    fn replaceFile(path: []const u8, data: []const u8) !void {
        var atomic = try std.Io.Dir.cwd().createFileAtomic(Self.settings_io, path, .{ .replace = true });
        defer atomic.deinit(Self.settings_io);
        try atomic.file.writeStreamingAll(Self.settings_io, data);
        try atomic.replace(Self.settings_io);
    }

    /// The folder the gallery keeps its settings in, as this OS keeps them.
    /// A variable that is empty or relative is taken as unset (as the XDG
    /// base directory spec says), so the file never lands under the working
    /// directory.
    ///
    /// - `allocator`: allocator for the path.
    /// - `environment`: the process's environment.
    /// - Returns: the folder, owned by the caller, or null where the environment names none; propagates allocation failure.
    fn folderOf(allocator: std.mem.Allocator, environment: *const std.process.Environ.Map) !?[]const u8 {
        if (ziggui.sdl.os_tag == .windows) {
            const app_data = Self.absoluteVariable(environment, "APPDATA") orelse return null;
            return try std.fs.path.join(allocator, &.{ app_data, "ziggui" });
        }
        const home = Self.absoluteVariable(environment, "HOME");
        if (gallery.is_macos) return try std.fs.path.join(allocator, &.{ home orelse return null, "Library", "Application Support", "ziggui" });
        if (Self.absoluteVariable(environment, "XDG_CONFIG_HOME")) |config_home| return try std.fs.path.join(allocator, &.{ config_home, "ziggui" });
        return try std.fs.path.join(allocator, &.{ home orelse return null, ".config", "ziggui" });
    }

    /// An environment variable naming an absolute path.
    ///
    /// - `environment`: the process's environment.
    /// - `name`: the variable.
    /// - Returns: its value, or null when it is unset, empty or relative.
    fn absoluteVariable(environment: *const std.process.Environ.Map, name: []const u8) ?[]const u8 {
        const value = environment.get(name) orelse return null;
        return if (std.fs.path.isAbsolute(value)) value else null;
    }
};

/// The Text Editor section's settings (`ziggui.TextEditorSettings`), kept
/// in `gallery-editor.zon` beside `gallery-window.zon`: read as the window
/// opens, noted each frame and written once they have rested
/// `WindowMemory.settle_ms`, and at quit, through `WindowSettings`' folder
/// and atomic replace. Headless runs never read or write it, so screenshots
/// stay the same whatever was saved. A file that cannot be read or parsed is
/// logged and ignored.
const EditorSettings = struct {
    const Self = @This();

    /// The file's name in the settings folder.
    const file_name = "gallery-editor.zon";

    /// The longest file read; the settings are a few hundred bytes.
    const most_bytes = 16384;

    /// The editor whose settings are kept, while the window is up.
    var editor: ?*gallery.Editor = null;

    /// The settings as last written (or read).
    var written: ziggui.TextEditorSettings = .{};

    /// The settings as last noted, which `changed_at` times.
    var pending: ziggui.TextEditorSettings = .{};

    /// When the settings last changed and are not written yet, in ms.
    var changed_at: ?u64 = null;

    /// Reads the saved settings into the editor, if any; `WindowSettings.load` ran first.
    ///
    /// - `target`: the gallery, whose editor takes them.
    /// - `read`: whether to read the file (false keeps what the arguments set).
    fn load(target: *gallery.Gallery, read: bool) void {
        Self.editor = &target.editor;
        defer {
            Self.written = target.editor.settings;
            Self.pending = Self.written;
        }
        if (!read) return;
        const folder_path = WindowSettings.folder orelse return;
        const allocator = WindowSettings.settings_allocator;
        const path = std.fs.path.join(allocator, &.{ folder_path, file_name }) catch |err| {
            log.warn("editor settings not read: {s}", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        const source = std.Io.Dir.cwd().readFileAllocOptions(WindowSettings.settings_io, path, allocator, .limited(most_bytes), .of(u8), 0) catch |err| {
            if (err != error.FileNotFound) log.warn("editor settings not read from {s}: {s}", .{ path, @errorName(err) });
            return;
        };
        defer allocator.free(source);
        // The strings land in the arena; `restoreSettings` keeps the registry's own names.
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const saved = std.zon.parse.fromSlice(ziggui.TextEditorSettings, .{
            .gpa = arena.allocator(),
            .arena = arena.allocator(),
            .source = source,
            .diagnostics = &diagnostics,
            .ignore_unknown_fields = true,
        }) catch |err| {
            log.warn("editor settings in {s} ignored: {s}", .{ path, @errorName(err) });
            return;
        };
        target.editor.restoreSettings(saved);
    }

    /// Notes the editor's settings, timing a change, and writes them once
    /// they have rested.
    fn note() void {
        const target = Self.editor orelse return;
        const now = ziggui.FrameClock.shared().time();
        if (!std.meta.eql(target.settings, Self.pending)) {
            Self.pending = target.settings;
            Self.changed_at = now;
        }
        const since = Self.changed_at orelse return;
        if (now -| since >= ziggui.WindowMemory.settle_ms) Self.write();
    }

    /// Whether a change waits to be written, so the loop keeps waking.
    ///
    /// - Returns: true while one waits.
    fn settling() bool {
        return Self.changed_at != null;
    }

    /// Writes a change that has not rested yet, as the loop ends.
    fn flush() void {
        if (Self.changed_at != null) Self.write();
        Self.editor = null;
    }

    /// Writes the noted settings, making the folder if need be; a failure
    /// is logged and the settings tried again at the next change or quit.
    fn write() void {
        Self.changed_at = null;
        if (std.meta.eql(Self.pending, Self.written)) return;
        if (WindowSettings.writeZon(file_name, Self.pending, "editor settings")) Self.written = Self.pending;
    }
};

/// The font family the gallery registers at launch: Noto Serif from
/// `fixtures/fonts` (`gallery.fonts_path`), regular and bold.
const Fonts = struct {
    const Self = @This();

    /// The family's name, as the font menus list it.
    const family_name = "Noto Serif";

    /// The most bytes a face may hold.
    const most_bytes = 8 * 1024 * 1024;

    /// Reads the faces and registers the family; a face that cannot be
    /// read or parsed is logged and the family left out.
    ///
    /// - `allocator`: allocator for the reads and the registry's copies.
    /// - `io`: the I/O the faces are read through.
    fn register(allocator: std.mem.Allocator, io: std.Io) void {
        const regular = Self.read(allocator, io, "NotoSerif-Regular.ttf") orelse return;
        defer allocator.free(regular);
        const bold = Self.read(allocator, io, "NotoSerif-Bold.ttf");
        defer if (bold) |bytes| allocator.free(bytes);
        ziggui.FontRegistry.shared().register(allocator, .{ .name = family_name, .regular = regular, .bold = bold }) catch |err| {
            log.warn("{s} not registered: {s}", .{ family_name, @errorName(err) });
        };
    }

    /// Reads one face's file.
    ///
    /// - `allocator`: allocator for the bytes.
    /// - `io`: the I/O it is read through.
    /// - `file`: the file's name in the fonts folder.
    /// - Returns: the bytes, owned by the caller, or null (logged) when it cannot be read.
    fn read(allocator: std.mem.Allocator, io: std.Io, file: []const u8) ?[]u8 {
        const path = std.fs.path.join(allocator, &.{ gallery.fonts_path, file }) catch |err| {
            log.warn("{s} not read: {s}", .{ file, @errorName(err) });
            return null;
        };
        defer allocator.free(path);
        return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(most_bytes)) catch |err| {
            log.warn("{s} not read: {s}", .{ path, @errorName(err) });
            return null;
        };
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

    /// What macOS's Open Recent entries are made with, while the loop runs.
    var menu_allocator: std.mem.Allocator = undefined;

    /// Holds macOS's Open Recent entries since the last swap
    /// (`syncRecentMenu`); null before the first.
    var recents_arena: ?std.heap.ArenaAllocator = null;

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
        const platform: gallery.Platform = .{
            .minimize_fn = Self.minimize,
            .toggle_maximized_fn = Self.toggleMaximized,
            .is_maximized_fn = Self.isMaximized,
            .request_close_fn = Self.requestClose,
            .quit_fn = Self.quit,
            .animator_fn = Self.animator,
            .open_file_fn = Self.openFile,
            .save_file_fn = Self.saveFile,
            .take_file_fn = Self.takeFile,
        };
        target.showcase.platform = platform;
        defer target.showcase.platform = .{};
        // Every card's copy button puts its names on the clipboard.
        gallery.CardName.shared().copy_fn = Self.copyText;
        defer gallery.CardName.shared().copy_fn = null;
        // The Files section's Open and Save buttons show the system's panels.
        target.kit.platform = platform;
        defer target.kit.platform = .{};
        // The recent-projects card's Window menu (macOS) minimizes, zooms and closes.
        target.recents.platform = platform;
        defer target.recents.platform = .{};
        // The Media Native section shows a real AppKit view in a window.
        // The Media Video panel's full-screen button takes the window with it.
        target.media.set_full_screen_fn = Self.setFullScreen;
        target.media.is_full_screen_fn = Self.isFullScreen;
        defer {
            target.media.set_full_screen_fn = null;
            target.media.is_full_screen_fn = null;
        }
        // The Media Audio section's voice memos live beside the settings.
        target.media.memos.keep(WindowSettings.settings_io, WindowSettings.folder);
        const native_sample = Self.makeNativeSample();
        target.media.native_sample = native_sample;
        defer {
            target.media.native_sample = null;
            Self.releaseNativeSample(native_sample);
        }

        const app = ziggui.App.shared();
        app.setThemeProvider(Self.theme);
        app.setKeyHandler(Self.onKey);
        app.setKeyUpHandler(Self.onKeyUp);
        app.setQuitHandler(Self.onQuit);
        app.setMouseHandler(Self.onMouse);
        app.setBusyInterval(Self.wakeInterval);
        // The window reopens where and as large as it was left, and the
        // Text Editor with the settings it was left with.
        app.setFrameHook(Self.frameHook);
        defer {
            app.setFrameHook(null);
            WindowSettings.flush();
            EditorSettings.flush();
        }
        // On macOS the recent-projects card's table is the menu bar (after
        // the app menu): its entries' actions live as long as the bar, and
        // Open Recent's until the next swap (`syncRecentMenu`).
        var menu_arena = std.heap.ArenaAllocator.init(allocator);
        defer menu_arena.deinit();
        Self.menu_allocator = allocator;
        defer if (Self.recents_arena) |*arena| {
            arena.deinit();
            Self.recents_arena = null;
        };
        const menus: []const ziggui.CommandMenu = if (comptime gallery.is_macos) try gallery.RecentMenus.table.commandMenus(menu_arena.allocator(), &target.recents) else &.{};
        _ = target.recents.takeChange();
        const config: ziggui.AppConfig = .{
            .title = "Zig Gallery",
            .width = 980,
            .height = 660,
            .min_width = 640,
            .min_height = 420,
            .theme = target.theme(),
            // On macOS the gallery's top band is the title bar, the traffic
            // lights in its inset, its empty space dragging the window.
            .unified_titlebar = gallery.is_macos,
            .drag_band = if (gallery.is_macos) ziggui.WindowChrome.top_bar_height else 0,
            // A Windows machine whose GPU SDL_GPU cannot use draws on WARP,
            // slower than the software rasterizer, so the Scenes section
            // still shows its scene.
            .warp_fallback = true,
            .menus = menus,
        };
        try app.run(allocator, gallery.Gallery, target, config.restoring(WindowSettings.saved), gallery.Gallery.body, null);
    }

    /// The frame hook: notes the window's place and the editor's settings,
    /// saving each once it has rested.
    fn frameHook() void {
        WindowSettings.note();
        EditorSettings.note();
        Self.syncRecentMenu();
    }

    /// Swaps macOS's Open Recent for the recent-projects card's list once it
    /// changed: the new entries are made in an arena of their own, and the
    /// old one, whose actions the swap drops, freed after.
    fn syncRecentMenu() void {
        if (comptime !gallery.is_macos) return;
        const target = Self.shown orelse return;
        if (!target.recents.takeChange()) return;
        const entry = gallery.RecentMenus.table.find(gallery.RecentMenus.open_recent) orelse return;
        var fresh = std.heap.ArenaAllocator.init(Self.menu_allocator);
        const items = gallery.RecentMenus.Table.listedCommands(entry, fresh.allocator(), &target.recents) catch |err| {
            fresh.deinit();
            log.warn("the recent projects were not listed [{t}]", .{err});
            return;
        };
        ziggui.App.shared().replaceSubmenu(gallery.RecentMenus.open_recent, items);
        if (Self.recents_arena) |*old| old.deinit();
        Self.recents_arena = fresh;
    }

    /// Makes the Media Native section's platform view: on macOS a layer-hosting
    /// `NSView`, tinted and labelled, which `NativeView` places; elsewhere none.
    ///
    /// - Returns: the view, or null where there is no host.
    fn makeNativeSample() ?*anyopaque {
        return if (comptime gallery.is_macos) Self.makeAppKitSample() else null;
    }

    /// Makes the macOS sample view for `makeNativeSample`.
    ///
    /// - Returns: the view, owned by the caller.
    fn makeAppKitSample() ?*anyopaque {
        const pool = ziggui.sdl.ObjectiveC.pushPool();
        defer ziggui.sdl.ObjectiveC.popPool(pool);
        const layer = ziggui.sdl.ObjectiveC.new("CALayer");
        ziggui.sdl.ObjectiveC.send(void, layer, "setBackgroundColor:", .{ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.class("NSColor"), "systemTealColor", .{}), "CGColor", .{})});
        const label = ziggui.sdl.ObjectiveC.new("CATextLayer");
        ziggui.sdl.ObjectiveC.send(void, label, "setString:", .{ziggui.sdl.ObjectiveC.string("An AppKit NSView, placed by ziggui")});
        ziggui.sdl.ObjectiveC.send(void, label, "setFontSize:", .{@as(f64, 15)});
        ziggui.sdl.ObjectiveC.send(void, label, "setContentsScale:", .{@as(f64, 2)});
        ziggui.sdl.ObjectiveC.send(void, label, "setAlignmentMode:", .{ziggui.sdl.ObjectiveC.string("center")});
        ziggui.sdl.ObjectiveC.send(void, label, "setForegroundColor:", .{ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.class("NSColor"), "whiteColor", .{}), "CGColor", .{})});
        // Width- and height-sizable, so it follows the view's size.
        ziggui.sdl.ObjectiveC.send(void, label, "setAutoresizingMask:", .{@as(u32, 2 | 16)});
        ziggui.sdl.ObjectiveC.send(void, layer, "addSublayer:", .{label});
        ziggui.sdl.ObjectiveC.release(label);
        const view = ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.send(ziggui.sdl.Id, ziggui.sdl.ObjectiveC.class("NSView"), "alloc", .{}), "initWithFrame:", .{ziggui.sdl.CGRect{}});
        // Layer-hosting: the layer is set before `wantsLayer`.
        ziggui.sdl.ObjectiveC.send(void, view, "setLayer:", .{layer});
        ziggui.sdl.ObjectiveC.send(void, view, "setWantsLayer:", .{@as(u8, 1)});
        ziggui.sdl.ObjectiveC.release(layer);
        return view;
    }

    /// Frees the Media Native section's platform view, once the loop is done with it.
    ///
    /// - `view`: the view `makeNativeSample` made, or null.
    fn releaseNativeSample(view: ?*anyopaque) void {
        if (comptime gallery.is_macos) ziggui.sdl.ObjectiveC.release(view);
    }

    /// Takes the window into full screen or out of it (the Media Video panel's
    /// full-screen button).
    ///
    /// - `full_screen`: true for full screen.
    fn setFullScreen(full_screen: bool) void {
        ziggui.App.shared().setFullScreen(full_screen);
    }

    /// Reports whether the window is in full screen (the Media Video panel's
    /// check that it still is).
    ///
    /// - Returns: true in full screen.
    fn isFullScreen() bool {
        return ziggui.App.shared().isFullScreen();
    }

    /// Minimizes the window (the Windows section's minimize button).
    fn minimize() void {
        ziggui.App.shared().minimizeWindow();
    }

    /// Maximizes or restores the window (the Windows section's maximize button).
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

    /// Puts text on the system clipboard (a card's copy button).
    ///
    /// - `text`: the text.
    fn copyText(text: []const u8) void {
        ziggui.Clipboard.setText(std.heap.page_allocator, text);
    }

    /// Shows the system's open-file panel (the Files section's Open File… button).
    ///
    /// - `location`: the folder it starts in.
    /// - Returns: false when a dialog is already up.
    fn openFile(location: [:0]const u8) bool {
        return ziggui.FileDialog.shared().openFile(&.{}, location);
    }

    /// Shows the system's save panel (the Files section's Save As… button).
    ///
    /// - `location`: the folder and the name its field starts with.
    /// - Returns: false when a dialog is already up.
    fn saveFile(location: [:0]const u8) bool {
        return ziggui.FileDialog.shared().saveFile(&.{}, location);
    }

    /// Takes the outcome of the dialog last shown, once.
    ///
    /// - `allocator`: owns a picked path's copy.
    /// - Returns: the outcome, `.none` while the dialog is still up.
    fn takeFile(allocator: std.mem.Allocator) gallery.FileDialogOutcome {
        return switch (ziggui.FileDialog.shared().takeResult(allocator)) {
            .none => .none,
            .canceled => .canceled,
            .picked => |path| .{ .picked = path },
        };
    }

    /// How often the loop wakes: every frame while a hover popover waits out
    /// its delay (the pointer resting sends no events), else idle.
    ///
    /// - Returns: milliseconds between wakes, 0 for none.
    fn wakeInterval() u32 {
        // A moved or resized window is saved once it rests, which needs a wake.
        if (WindowSettings.memory.settling() or EditorSettings.settling()) return WindowSettings.settle_wake_ms;
        const target = Self.shown orelse return 0;
        return if (target.hoverWaiting()) 16 else 0;
    }

    /// A key went down: the Menus & Commands section's Alt tap and menu keys, the
    /// Text Editor section's shortcuts, and the File Browser's keys.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a panel used it.
    fn onKey(keycode: u32, modifiers: u16) bool {
        const target = Self.shown orelse return false;
        return target.keyDown(keycode, modifiers);
    }

    /// A key came up: Alt ends a tap; the Presentations section shows the keycode.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    fn onKeyUp(keycode: u32, modifiers: u16) void {
        _ = modifiers;
        const target = Self.shown orelse return;
        target.keyUp(keycode);
    }

    /// A quit was asked for: the Presentations section may ask first.
    ///
    /// - Returns: true to let the quit end the loop.
    fn onQuit() bool {
        const target = Self.shown orelse return true;
        return target.quitRequested();
    }

    /// A mouse event: a press cancels an Alt tap, and a left press on the
    /// File Browser's list hands it the arrow keys; over the Images & Drawing
    /// section's picture a pinch or a ⌘- or Ctrl-scroll zooms it about the
    /// pointer, and a left press on its zoom chip fits it again, consumed
    /// before it can start the picture's pan drag; over either of the Scenes
    /// section's scenes the same gestures zoom its camera. A plain scroll is
    /// left to the page, which scrolls.
    ///
    /// - `event`: the event.
    /// - Returns: true when the picture or a scene took it; otherwise ziggui handles it as usual.
    fn onMouse(event: ziggui.MouseEvent) bool {
        const target = Self.shown orelse return false;
        const point = ziggui.Point{ .x = event.x, .y = event.y };
        if (event.kind == .down) target.menu_bar.pointerDown();
        if (event.kind == .down and event.button == 1) target.pointerDown(point);
        if (target.shownScenes()) |scenes| {
            for (scenes) |scene| if (Self.zoomScene(scene, event, point)) return true;
            return false;
        }
        const zoom = target.pictureZoom() orelse return false;
        if (event.kind == .down and event.button == 1 and zoom.chipContains(point)) {
            zoom.fit();
            return true;
        }
        return switch (event.kind) {
            .pinch => zoom.pinch(point, event.scale),
            .wheel => event.commandOrControl() and zoom.wheel(point, event.delta_x, event.delta_y, true),
            else => false,
        };
    }

    /// Hands a pinch, or a ⌘-scroll, to a scene's camera.
    ///
    /// - `scene`: the scene.
    /// - `event`: the event.
    /// - `point`: the pointer, in points.
    /// - Returns: true when the scene's view took it.
    fn zoomScene(scene: *ziggui.Scene, event: ziggui.MouseEvent, point: ziggui.Point) bool {
        return switch (event.kind) {
            .pinch => ziggui.SceneCameraInput.pinch(scene, point, event.scale),
            .wheel => event.commandOrControl() and ziggui.SceneCameraInput.wheel(scene, point, event.delta_y),
            else => false,
        };
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
