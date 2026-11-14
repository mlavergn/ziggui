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

    /// macOS: hide the title and let the content run under a transparent,
    /// toolbar-height titlebar (the traffic lights float over the app's own
    /// top band, as in Finder / the Swift apps). The top `drag_band` points that
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
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
