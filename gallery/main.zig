const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_main);
const gallery = @import("gallery");
const ziggui = @import("ziggui");
const ziggui_app = @import("ziggui_app");

/// Log configuration for the executable.
pub const std_options: std.Options = .{
    .log_level = if (gallery.is_debug) .debug else .warn,
};

/// The command line: `ziggui-gallery [--section <n>] [--accent <n>] [--menu <n>] [--dark] [--screenshot <out.bmp>]`.
const Args = struct {
    const Self = @This();

    /// The width `--screenshot` draws at, in points.
    const screenshot_width: u32 = 980;

    /// The height `--screenshot` draws at, in points.
    const screenshot_height: u32 = 660;

    /// The sidebar row to open on.
    section: i64 = 0,

    /// The accent switcher's color to open with; 0 keeps the theme's own.
    accent: i64 = 0,

    /// Open in the dark appearance instead of following the OS.
    dark: bool = false,

    /// The Menu Bar panel's menu to open, for a screenshot of it.
    menu: ?usize = null,

    /// Draw one frame to this BMP instead of opening a window.
    screenshot: ?[]const u8 = null,

    /// Reads the argument vector; unknown or malformed arguments are logged and skipped.
    ///
    /// - `argv`: the full argument vector, program name included.
    /// - Returns: the parsed arguments.
    fn parse(argv: []const [:0]const u8) Self {
        var args: Self = .{};
        var index: usize = 1;
        while (index < argv.len) : (index += 1) {
            const arg = argv[index];
            if (std.mem.eql(u8, arg, "--dark")) {
                args.dark = true;
            } else if (std.mem.eql(u8, arg, "--screenshot") and index + 1 < argv.len) {
                index += 1;
                args.screenshot = argv[index];
            } else if (std.mem.eql(u8, arg, "--section") and index + 1 < argv.len) {
                index += 1;
                args.section = std.fmt.parseInt(i64, argv[index], 10) catch |err| blk: {
                    log.warn("ignoring --section {s} [{t}]", .{ argv[index], err });
                    break :blk 0;
                };
            } else if (std.mem.eql(u8, arg, "--menu") and index + 1 < argv.len) {
                index += 1;
                args.menu = std.fmt.parseInt(usize, argv[index], 10) catch |err| blk: {
                    log.warn("ignoring --menu {s} [{t}]", .{ argv[index], err });
                    break :blk null;
                };
            } else if (std.mem.eql(u8, arg, "--accent") and index + 1 < argv.len) {
                index += 1;
                args.accent = std.fmt.parseInt(i64, argv[index], 10) catch |err| blk: {
                    log.warn("ignoring --accent {s} [{t}]", .{ argv[index], err });
                    break :blk 0;
                };
            } else {
                log.warn("ignoring argument {s}", .{arg});
            }
        }
        return args;
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
    const args = Args.parse(try init.minimal.args.toSlice(init.arena.allocator()));

    const shown = try allocator.create(gallery.Gallery);
    defer allocator.destroy(shown);
    shown.* = try gallery.Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(args.section);
    shown.accent.set(args.accent);
    shown.dark.set(args.dark);
    if (args.menu) |menu| if (menu < shown.barMenus().len) shown.menu_bar.open(menu);

    if (args.screenshot) |out| {
        const rgba = try gallery.Screenshot.render(allocator, shown, Args.screenshot_width, Args.screenshot_height);
        defer allocator.free(rgba);
        const image = try gallery.Screenshot.bmp(allocator, rgba, Args.screenshot_width, Args.screenshot_height);
        defer allocator.free(image);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = image });
        std.debug.print("wrote {s} ({d}x{d})\n", .{ out, Args.screenshot_width, Args.screenshot_height });
        return;
    }

    try Window.run(allocator, shown, !args.dark);
}

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

        ziggui_app.setThemeProvider(Self.theme);
        ziggui_app.setKeyHandler(Self.onKey);
        ziggui_app.setKeyUpHandler(Self.onKeyUp);
        ziggui_app.setMouseHandler(Self.onMouse);
        try ziggui_app.run(allocator, gallery.Gallery, target, .{
            .title = "ziggui — Gallery",
            .width = 980,
            .height = 660,
            .min_width = 640,
            .min_height = 420,
            .theme = target.theme(),
        }, gallery.Gallery.body, null);
    }

    /// A key went down: the Menu Bar panel's Alt tap and menu keys.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `mods`: its `SDL_Keymod` mask.
    /// - Returns: true when the menu used it.
    fn onKey(keycode: u32, mods: u16) bool {
        const target = Self.shown orelse return false;
        return target.menuKeyDown(keycode, mods);
    }

    /// A key came up: Alt ends a tap.
    ///
    /// - `keycode`: its `SDL_Keycode`.
    /// - `mods`: its `SDL_Keymod` mask.
    fn onKeyUp(keycode: u32, mods: u16) void {
        _ = mods;
        const target = Self.shown orelse return;
        target.menuKeyUp(keycode);
    }

    /// A mouse event: a press cancels an Alt tap; none is consumed.
    ///
    /// - `event`: the event.
    /// - Returns: false, so zigui handles it as usual.
    fn onMouse(event: ziggui_app.MouseEvent) bool {
        const target = Self.shown orelse return false;
        if (event.kind == .down) target.menu_bar.pointerDown();
        return false;
    }

    /// The theme provider: the gallery's selection, the OS appearance on the first frame.
    ///
    /// - Returns: the theme to draw this frame with.
    fn theme() ziggui.Theme {
        const target = Self.shown orelse return ziggui.default_theme;
        if (Self.follow_os) {
            // SDL is up by the time the loop asks, so the OS can answer.
            target.dark.set(ziggui_app.colorScheme() == .dark);
            Self.follow_os = false;
        }
        return target.theme();
    }
};
