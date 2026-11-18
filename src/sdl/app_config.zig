//! How `App.run` opens the main window and renders into it.

const std = @import("std");
const log = std.log.scoped(.ziggui_app_config);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");

/// The main window's title, size, theme, chrome, icon, and rendering choices.
pub const AppConfig = struct {
    const Self = @This();

    /// The window title.
    title: [:0]const u8 = "ziggui",

    /// The initial width, in points.
    width: u32 = 900,

    /// The initial height, in points.
    height: u32 = 600,

    /// The window's left edge at launch, in points (desktop coordinates), or
    /// null to center it. Ignored with `y` null, or when the frame would show
    /// on no display (one since unplugged).
    x: ?i32 = null,

    /// The window's top edge at launch, in points, or null to center it.
    y: ?i32 = null,

    /// Open maximized (the frame above is then the restored one).
    maximized: bool = false,

    /// Minimum window width the user can resize to (0 = no limit). Applied via
    /// SDL_SetWindowMinimumSize after the window is created.
    min_width: u32 = 0,

    /// Minimum window height the user can resize to (0 = no limit).
    min_height: u32 = 0,

    /// The theme, unless a theme provider (`App.setThemeProvider`) answers.
    theme: renderer.Theme = renderer.Theme.default,

    /// When true, the window's close button hides the window (keeping the app
    /// alive in the tray) instead of quitting. Use with a `MenuBarExtra` that
    /// offers a way back (e.g. an "Open" entry) and a "Quit". ⌘Q still quits.
    hide_on_close: bool = false,

    /// Render via the SDL_GPU backend (Metal/Vulkan) when available, falling
    /// back to the software rasterizer when it isn't. Set false to force the
    /// software path; the `ZIGGUI_SOFTWARE` environment variable does the same
    /// at runtime.
    gpu: bool = true,

    /// Optional window/taskbar icon, set via `SDL_SetWindowIcon` after the window
    /// is created. `rgba` is row-major RGBA8 (`width * height * 4` bytes); the
    /// surface is copied by SDL, so the caller may free `rgba` after `run` sets it.
    icon: ?mod.WindowIcon = null,

    /// Optional window/taskbar icon as PNG bytes (e.g. `@embedFile` of a
    /// 256 px PNG), decoded with SDL's built-in loader: the icon on macOS
    /// (the Dock) and Linux (X11 / Wayland window icon). On Windows an icon
    /// resource embedded in the .exe wins, since it carries every size and
    /// SDL already uses it for the window; `icon_png` is the fallback there.
    /// Ignored when `icon` is set.
    icon_png: ?[]const u8 = null,

    /// Supersampling factor: the UI is rendered into a framebuffer this many
    /// times larger per axis, then downscaled on present (SSAA). On a low-DPI
    /// (100%) display this is what makes text crisp: gamma adds weight, but
    /// only extra device pixels add edge resolution. 1 = off (default). 2 is a
    /// good value for 96-dpi monitors; it costs ~4× the fill (negligible on the
    /// GPU, heavier on the software fallback). Capped internally so an already
    /// HiDPI display isn't oversampled past ~2× effective device pixels.
    supersample: f32 = 1,

    /// macOS: hide the title and let the content run under a transparent
    /// titlebar as tall as `WindowChrome.top_bar_height` (a unified compact
    /// toolbar's), the traffic lights centred in the app's own top band, as
    /// in Finder / the Swift apps. The top `drag_band` points that
    /// hold no control then drag the window everywhere (on every OS), so an app
    /// that draws its own band behaves like a native titlebar.
    unified_titlebar: bool = false,

    /// The top band, in points, whose empty space drags the window (0 = none).
    drag_band: f32 = 0,

    /// Off macOS: no OS title bar or frame (a borderless, resizable window);
    /// the app draws its own title bar in the top `drag_band`, whose empty
    /// space drags the window, and the window's edges resize it
    /// (`WindowHitTest.custom_resize_edge` points in, unless maximized). The
    /// app's window buttons call `App.minimizeWindow`, `App.toggleMaximized`
    /// and `App.requestClose`. On Windows the window keeps the system shadow,
    /// rounded corners (11) and Aero Snap; Linux window managers draw no shadow
    /// for it. Ignored on macOS.
    custom_titlebar: bool = false,

    /// macOS menu bar menus, after the application menu (ignored elsewhere:
    /// there is no menu bar to put them in).
    menus: []const mod.CommandMenu = &.{},

    /// macOS: a "Settings… ⌘," entry in the application menu (after About)
    /// that runs this on the UI thread. Elsewhere there is no application
    /// menu, so an app offers its settings in its own window too.
    settings: ?views.Callback = null,

    /// A face behind the bundled emoji font for codepoints no bundled face has
    /// (a system CJK font, `renderer.Font.fromExternal`). Must outlive `run`.
    fallback_font: ?*const renderer.TtfFont = null,

    /// The largest width or height `restoring` opens a window at, in points:
    /// a size past it was read from a corrupt file.
    pub const max_restored_size: u32 = 16384;

    /// This configuration opening the window where it was saved: `x`, `y`,
    /// `width`, `height` and `maximized` from `place` (the size between
    /// `min_width`/`min_height` and `max_restored_size`), unchanged with none.
    ///
    /// - `self`: the configuration, its minimums set.
    /// - `place`: the saved place (`App.windowPlace`); null for the defaults.
    /// - Returns: the configuration to run with.
    pub fn restoring(self: *const Self, place: ?views.WindowPlace) Self {
        var placed = self.*;
        const saved = place orelse return placed;
        placed.x = saved.x;
        placed.y = saved.y;
        // A minimum past the cap would invert the range, which `clamp` asserts against.
        placed.width = std.math.clamp(saved.width, std.math.clamp(self.min_width, 1, max_restored_size), max_restored_size);
        placed.height = std.math.clamp(saved.height, std.math.clamp(self.min_height, 1, max_restored_size), max_restored_size);
        placed.maximized = saved.maximized;
        return placed;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "restoring opens the window at its saved place, never below the minimums" {
    const base: AppConfig = .{ .width = 1320, .height = 840, .min_width = 900, .min_height = 560 };
    const none = base.restoring(null);
    try std.testing.expectEqual(@as(u32, 1320), none.width);
    try std.testing.expectEqual(@as(?i32, null), none.x);
    const placed = base.restoring(.{ .x = 40, .y = -20, .width = 1500, .height = 300, .maximized = true });
    try std.testing.expectEqual(@as(?i32, 40), placed.x);
    try std.testing.expectEqual(@as(?i32, -20), placed.y);
    try std.testing.expectEqual(@as(u32, 1500), placed.width);
    try std.testing.expectEqual(@as(u32, 560), placed.height);
    try std.testing.expect(placed.maximized);
    // A corrupt file's size is cut to the largest window opened.
    const corrupt = base.restoring(.{ .x = 0, .y = 0, .width = std.math.maxInt(u32), .height = 700 });
    try std.testing.expectEqual(AppConfig.max_restored_size, corrupt.width);
    // A minimum past the cap opens at the cap rather than failing.
    const huge: AppConfig = .{ .min_width = std.math.maxInt(u32) };
    try std.testing.expectEqual(AppConfig.max_restored_size, huge.restoring(.{ .x = 0, .y = 0, .width = 800, .height = 600 }).width);
}
