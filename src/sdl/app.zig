//! The ziggui runtime's app: opens an OS window via SDL3, drives an event
//! loop (`EventLoop`), and presents frames. Rendering prefers the SDL_GPU
//! backend (`gpu/gpu.zig`: Metal on macOS, Vulkan on Linux/Windows) and falls
//! back to the pure-Zig software rasterizer (the `Canvas` command list
//! rasterized on the CPU and uploaded to an SDL streaming texture) when no GPU
//! is available: same command list, same output, so apps never notice which
//! backend ran.
//!
//! The `sdl` module is the only part of ziggui that links SDL/C. It is
//! compiled into application executables, never into the core library or its
//! test suite, so `zig build test` stays headless and works in Docker.
//!
//! An app sets its handlers on `App.shared()` and then calls
//! `App.shared().run(allocator, AppState, state, config, body, panel)`, which
//! returns when the loop ends.

const std = @import("std");
const log = std.log.scoped(.ziggui_app);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The running app: its window, its loop flag, and the handlers an app
/// installs. One per process (`shared`); `run` fills the window and loop
/// fields for its duration, so tray and menu callbacks can show or hide the
/// window or quit.
pub const App = struct {
    const Self = @This();

    /// Ceiling on the idle wait (ms) when the app has no busy work. A fully
    /// blocking `SDL_WaitEvent` only returns on an SDL event, so state changed by a
    /// context that posts none (most importantly a tray/menu callback) isn't
    /// observed until the next incidental event. When the window is visible that's
    /// the user's next mouse-over; when it's hidden-to-tray there's no window to
    /// receive one, so `quit()` from the tray would hang the process forever.
    /// Capping the wait lets the loop re-check `running` (and re-run the frame hook,
    /// e.g. tray status) ~every 250 ms while idle. Both idle wait sites skip the
    /// redraw on a timeout (nothing changed), so this stays ~free (measured <0.5%
    /// CPU idle) while bounding worst-case tray-action latency to this interval
    /// instead of "until the next incidental event".
    pub const idle_wake_ms: c_int = 1000;

    /// The caret blinks ~530 ms per phase (the macOS default); any key or click
    /// restarts the cycle solid, so the caret never vanishes while typing.
    pub const blink_ms: u64 = 530;

    /// The running window, set for the duration of `run`.
    window: ?*sdl_c.SDL_Window = null,

    /// The running loop's flag, set for the duration of `run`.
    running: ?*bool = null,

    /// Whether a window-close request hides to the tray (true) or quits (false).
    hide_on_close: bool = false,

    /// The running loop's animator, set for the duration of `run`.
    active_animator: ?*renderer.Animator = null,

    /// Bundled faces for weight/italic/mono (see `renderer.FontSet`); set for the run.
    fonts: ?*renderer.FontSet = null,

    /// An optional "busy" predicate (see `setBusyCheck`).
    busy_check: ?*const fn () bool = null,

    /// An optional wake-cadence provider (see `setBusyInterval`).
    busy_interval: ?*const fn () u32 = null,

    /// When the caret's blink cycle last restarted (SDL ticks).
    blink_epoch: u64 = 0,

    /// The phase the last frame drew, so idle waits know when a redraw is due.
    caret_drawn: bool = true,

    /// An optional theme provider (see `setThemeProvider`).
    theme_provider: ?*const fn () renderer.Theme = null,

    /// An optional per-frame hook (see `setFrameHook`).
    frame_hook: ?*const fn () void = null,

    /// An optional key-down handler (see `setKeyHandler`).
    key_handler: ?*const fn (keycode: u32, modifiers: u16) bool = null,

    /// The key-up and quit handlers (see `views.AppHooks`).
    hooks: views.AppHooks = .{},

    /// An optional focus handler (see `setFocusHandler`).
    focus_handler: ?*const fn (gained: bool) void = null,

    /// An optional typed-text handler (see `setTextHandler`).
    text_handler: ?*const fn (typed: []const u8) bool = null,

    /// An optional mouse handler (see `setMouseHandler`).
    mouse_handler: ?*const fn (event: mod.MouseEvent) bool = null,

    /// Called with the path of each file dropped onto the window.
    drop_handler: ?*const fn (path: []const u8) void = null,

    /// The cursor's last known position in logical points, or null when it has left
    /// the window. Fed into `Context.hover_point` each frame for hover highlights.
    hover_point: ?renderer.Point = null,

    /// The main window's `onHover` regions from the last frame (arena-backed, like
    /// the hit regions), compared with each pointer move by `views.PointerInput.hover`.
    hover_regions: std.ArrayList(views.HoverRegion) = .empty,

    /// Scale converting SDL mouse coordinates (logical window points) into the
    /// design-point space that hit/scroll regions live in. The event loop updates
    /// it each frame to `pixel_density / display_scale`: 1.0 on macOS (where the OS
    /// UI scale rides on the backing scale), but <1 on Windows/Linux at a non-100%
    /// OS display-scale setting, where the two diverge.
    event_scale: f32 = 1,

    /// When true, the loop prints rolling frame-time statistics (last/avg/max ms + the
    /// equivalent fps) to stderr ~once per second. Off by default; also enabled at
    /// startup if the `ZIGGUI_FRAME_LOG` environment variable is set. Useful for
    /// profiling the software rasterizer without a GPU profiler.
    frame_log: bool = false,

    /// The system cursors made so far: the arrow, then the I-beam.
    cursors: [2]?*sdl_c.SDL_Cursor = .{ null, null },

    /// Whether the I-beam is showing.
    text_cursor: bool = false,

    /// The main window's frame when it was last neither maximized, minimized
    /// nor full screen (`noteWindowFrame`); what `windowFrame` reports while
    /// it is maximized. Null until the window opens.
    restored_frame: ?mod.WindowFrame = null,

    /// The process's app.
    var shared_app: Self = .{};

    /// The process's app.
    ///
    /// - Returns: the shared app.
    pub fn shared() *Self {
        return &shared_app;
    }

    /// Runs the app until the loop ends. `body` is invoked each frame to
    /// (re)build the view tree from the current application state; state
    /// mutations triggered by events cause the next frame to reflect the change.
    /// When `panel` is non-null, a hidden borderless window hosting `panel.body`
    /// is created too; `Panel.show` opens it under the pointer (a status-item
    /// click is the usual trigger).
    ///
    /// - `self`: the app.
    /// - `allocator`: allocator for the loop's resources.
    /// - `AppState`: the app's state type.
    /// - `state`: the app's state, handed to `body`.
    /// - `config`: the window and rendering configuration.
    /// - `body`: builds the main window's view tree.
    /// - `panel`: the popover panel, or null for none.
    /// - Returns: nothing once the loop ends; propagates SDL start-up and
    ///   allocation failure.
    pub fn run(
        self: *Self,
        allocator: std.mem.Allocator,
        comptime AppState: type,
        state: *AppState,
        config: mod.AppConfig,
        body: *const fn (*AppState) views.View,
        panel: ?mod.PanelSpecification(AppState),
    ) !void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        _ = self;
        const event_loop = try mod.EventLoop(AppState).create(allocator, state, config, body, panel);
        defer event_loop.destroy();
        event_loop.run();
    }

    /// Wakes the event loop from any thread (a worker finished something the UI
    /// should show). Safe to call before/after `run`; a no-op while SDL is down.
    ///
    /// - `self`: the app.
    pub fn wake(self: *const Self) void {
        _ = self;
        var event = std.mem.zeroes(sdl_c.SDL_Event);
        event.type = sdl_c.SDL_EVENT_USER;
        _ = sdl_c.SDL_PushEvent(&event);
    }

    /// Asks the run loop to exit (e.g. from a tray "Quit" entry). Only flips the
    /// flag: a tray/menu callback fires inside macOS's Cocoa menu-tracking loop,
    /// which swallows any SDL wakeup event we'd push here, so the loop can't be
    /// woken from this context. Instead the loop caps its idle wait
    /// (`idle_wake_ms`) and re-checks `running` on the timeout.
    ///
    /// - `self`: the app.
    pub fn quit(self: *const Self) void {
        if (self.running) |running| running.* = false;
    }

    /// Shows and raises the window (e.g. from a tray "Open" entry).
    ///
    /// - `self`: the app.
    pub fn showWindow(self: *const Self) void {
        if (self.window) |window| {
            _ = sdl_c.SDL_ShowWindow(window);
            _ = sdl_c.SDL_RaiseWindow(window);
        }
    }

    /// Hides the window without quitting (the app keeps running in the tray).
    ///
    /// - `self`: the app.
    pub fn hideWindow(self: *const Self) void {
        if (self.window) |window| _ = sdl_c.SDL_HideWindow(window);
    }

    /// Minimizes the main window (a custom title bar's minimize button).
    ///
    /// - `self`: the app.
    pub fn minimizeWindow(self: *const Self) void {
        if (self.window) |window| _ = sdl_c.SDL_MinimizeWindow(window);
    }

    /// Maximizes the main window, or restores it when it is maximized (a custom
    /// title bar's maximize button).
    ///
    /// - `self`: the app.
    pub fn toggleMaximized(self: *const Self) void {
        const window = self.window orelse return;
        if (self.isMaximized()) _ = sdl_c.SDL_RestoreWindow(window) else _ = sdl_c.SDL_MaximizeWindow(window);
    }

    /// Reports whether the main window is maximized (a custom title bar draws
    /// restore rather than maximize).
    ///
    /// - `self`: the app.
    /// - Returns: true when it is; false with no window.
    pub fn isMaximized(self: *const Self) bool {
        const window = self.window orelse return false;
        return (sdl_c.SDL_GetWindowFlags(window) & sdl_c.SDL_WINDOW_MAXIMIZED) != 0;
    }

    /// The main window's frame to remember, in points: where it is and how
    /// big, or, while it is maximized, where it was and how big before (the
    /// frame `AppConfig.x`/`y`/`width`/`height` take with `maximized`).
    ///
    /// - `self`: the app.
    /// - Returns: the frame; null with no window.
    pub fn windowFrame(self: *const Self) ?mod.WindowFrame {
        const window = self.window orelse return null;
        if (self.isMaximized()) if (self.restored_frame) |restored| return restored;
        return Self.currentFrame(window);
    }

    /// Records `window`'s frame as its restored one, unless it is maximized,
    /// minimized or full screen. The event loop calls it as the main window
    /// opens, moves and resizes.
    ///
    /// - `self`: the app.
    /// - `window`: the main window.
    pub fn noteWindowFrame(self: *Self, window: *sdl_c.SDL_Window) void {
        const flags = sdl_c.SDL_GetWindowFlags(window);
        if ((flags & (sdl_c.SDL_WINDOW_MAXIMIZED | sdl_c.SDL_WINDOW_MINIMIZED | sdl_c.SDL_WINDOW_FULLSCREEN)) != 0) return;
        self.restored_frame = Self.currentFrame(window) orelse return;
    }

    /// Asks to close the main window, as its OS close button does: with
    /// `AppConfig.hide_on_close` it hides to the tray, else the quit handler
    /// (`setQuitHandler`) may refuse (a custom title bar's close button).
    ///
    /// - `self`: the app.
    pub fn requestClose(self: *const Self) void {
        if (self.hide_on_close) return self.hideWindow();
        if (self.running) |running| self.hooks.requestQuit(running);
    }

    /// Reports whether a window-close request hides to the tray (true) or quits
    /// (false). Mirrors `AppConfig.hide_on_close`, but can be toggled at runtime
    /// from a tray checkbox.
    ///
    /// - `self`: the app.
    /// - Returns: true when closing hides the window.
    pub fn hideOnClose(self: *const Self) bool {
        return self.hide_on_close;
    }

    /// Sets whether a window-close request hides to the tray.
    ///
    /// - `self`: the app.
    /// - `value`: true to hide, false to quit.
    pub fn setHideOnClose(self: *Self, value: bool) void {
        self.hide_on_close = value;
    }

    /// The running app's animator, so view callbacks can start animations
    /// (e.g. `App.shared().animator().?.animateTo(&state, 1, 0.3, .easeInOut)`).
    /// Set for the duration of `run`.
    ///
    /// - `self`: the app.
    /// - Returns: the animator, or null outside `run`.
    pub fn animator(self: *const Self) ?*renderer.Animator {
        return self.active_animator;
    }

    /// Sets an optional "busy" predicate: while it returns true the loop wakes on
    /// a ~60fps timeout (instead of blocking on input) and rebuilds each frame, so
    /// the app's `body` can poll in-flight work (e.g. a streaming socket). Mirrors
    /// the animator-active branch.
    ///
    /// - `self`: the app.
    /// - `check`: the predicate, or null for none.
    pub fn setBusyCheck(self: *Self, check: ?*const fn () bool) void {
        self.busy_check = check;
    }

    /// Sets a cadence-returning generalization of `setBusyCheck`: while the
    /// provider returns a non-zero interval (ms), the loop wakes on that timeout
    /// instead of blocking on input and rebuilds each frame, so a heavy GPU job
    /// can repaint a spinner at 10 fps (not fighting the worker for the GPU at 60)
    /// while video playback keeps its own smooth cadence. 0 means fully idle
    /// (block on input). Takes precedence over the boolean predicate when both
    /// are set.
    ///
    /// - `self`: the app.
    /// - `interval`: the provider, or null for none.
    pub fn setBusyInterval(self: *Self, interval: ?*const fn () u32) void {
        self.busy_interval = interval;
    }

    /// Sets an optional theme provider, queried once per frame so the app can
    /// switch light/dark (or any theme) live without restarting. When null the
    /// loop uses the static `AppConfig.theme`.
    ///
    /// - `self`: the app.
    /// - `provider`: the provider, or null for none.
    pub fn setThemeProvider(self: *Self, provider: ?*const fn () renderer.Theme) void {
        self.theme_provider = provider;
    }

    /// Sets an optional per-frame hook, invoked once each main-loop iteration
    /// (before the frame is drawn). Use it to push app state into retained OS
    /// surfaces that live outside the view tree, e.g. refreshing a system-tray
    /// menu's labels/icon. Runs on the main thread, so it is safe to call SDL
    /// tray setters from here.
    ///
    /// - `self`: the app.
    /// - `hook`: the hook, or null for none.
    pub fn setFrameHook(self: *Self, hook: ?*const fn () void) void {
        self.frame_hook = hook;
    }

    /// Sets an optional application key handler, called first on every key-down
    /// with the SDL keycode (`SDLK_*`) and modifier mask (`SDL_KMOD_*`, both
    /// reachable via `ziggui.sdl.sdl_c`). Returning true marks the key consumed: the
    /// loop then skips its default text-field editing for that event. Use it for
    /// app shortcuts and clipboard (e.g. ⌘S / ⌘O / ⌘C / ⌘V).
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setKeyHandler(self: *Self, handler: ?*const fn (keycode: u32, modifiers: u16) bool) void {
        self.key_handler = handler;
    }

    /// Sets an optional handler called on every main-window key-up with the SDL
    /// keycode and modifier mask, beside `setKeyHandler`'s key-downs (which it
    /// leaves alone). An app tells an Alt tap from the Alt of Alt+Tab or Alt+F4
    /// with it.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setKeyUpHandler(self: *Self, handler: ?*const fn (keycode: u32, modifiers: u16) void) void {
        self.hooks.key_up = handler;
    }

    /// Sets an optional handler asked before a quit: on `SDL_EVENT_QUIT` (⌘Q,
    /// the app menu's Quit, a logout) and on the main window's close button.
    /// Returning false keeps the loop running (an app with unsaved work asks
    /// first); unset, both quit as before. `quit()` never asks, so the app's own
    /// Quit, after its question, always ends the loop. The tray's hide-on-close
    /// is not a quit and is not asked about. Set it before SDL starts (`run`,
    /// `MenuBarExtra.init` or `StatusItem.create`, whichever comes first): while
    /// one is set, SDL's signal handlers are turned off
    /// (`SDL_HINT_NO_SIGNAL_HANDLERS`), so SIGINT and SIGTERM end the process as
    /// usual rather than becoming a quit the handler could refuse.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setQuitHandler(self: *Self, handler: ?*const fn () bool) void {
        self.hooks.quit = handler;
    }

    /// Sets an optional handler for the main window gaining (true) or losing
    /// (false) keyboard focus: an app re-reads state that may have changed while
    /// another app was in front.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setFocusHandler(self: *Self, handler: ?*const fn (gained: bool) void) void {
        self.focus_handler = handler;
    }

    /// Sets an optional handler for typed text (after IME composition), called
    /// before the focused field gets it. Returning true consumes it: a terminal
    /// view takes typing this way while it has the keyboard.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setTextHandler(self: *Self, handler: ?*const fn (typed: []const u8) bool) void {
        self.text_handler = handler;
    }

    /// Sets an optional handler that sees main-window mouse events first;
    /// returning true consumes one (the default hit-testing then skips it). A
    /// terminal view uses it for selection, the wheel and the program's own
    /// mouse reporting.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setMouseHandler(self: *Self, handler: ?*const fn (event: mod.MouseEvent) bool) void {
        self.mouse_handler = handler;
    }

    /// Sets the handler called with the path of each file dropped onto the window.
    ///
    /// - `self`: the app.
    /// - `handler`: the handler, or null for none.
    pub fn setDropHandler(self: *Self, handler: ?*const fn (path: []const u8) void) void {
        self.drop_handler = handler;
    }

    /// Turns the rolling frame-time log on or off (see `frame_log`).
    ///
    /// - `self`: the app.
    /// - `enabled`: true to log.
    pub fn setFrameLog(self: *Self, enabled: bool) void {
        self.frame_log = enabled;
    }

    /// Reads the OS-level light/dark preference.
    ///
    /// - `self`: the app.
    /// - Returns: the preference, `.unknown` when the platform reports none.
    pub fn systemTheme(self: *const Self) mod.SystemTheme {
        _ = self;
        return switch (sdl_c.SDL_GetSystemTheme()) {
            sdl_c.SDL_SYSTEM_THEME_LIGHT => .light,
            sdl_c.SDL_SYSTEM_THEME_DARK => .dark,
            else => .unknown,
        };
    }

    /// The OS color scheme as a `renderer.ColorScheme`, ready to hand to
    /// `family.forScheme(App.shared().colorScheme())`. Falls back to `.light`
    /// when the platform can't report a preference. Re-query it each frame (or
    /// in a theme provider) to follow the OS live.
    ///
    /// - `self`: the app.
    /// - Returns: the color scheme.
    pub fn colorScheme(self: *const Self) renderer.ColorScheme {
        return if (self.systemTheme() == .dark) .dark else .light;
    }

    /// Prepares what every `SDL_Init` here needs first, since SDL reads it only
    /// when it starts (a tray or status item may start it before `run`): with a
    /// quit handler, SDL's signal handlers stay off, as a handler may refuse a
    /// quit (see `setQuitHandler`); on macOS a Ctrl-click is a right click, as
    /// everywhere on the Mac, so it opens context menus (`onSecondaryTap`) and
    /// never reaches a tap with Ctrl held; and a UTF-8 locale (see `useUtf8Locale`).
    ///
    /// - `self`: the app.
    pub fn beforeSdlInit(self: *const Self) void {
        if (self.hooks.quit != null) _ = sdl_c.SDL_SetHint(sdl_c.SDL_HINT_NO_SIGNAL_HANDLERS, "1");
        if (mod.os_tag == .macos) _ = sdl_c.SDL_SetHint(sdl_c.SDL_HINT_MAC_CTRL_CLICK_EMULATE_RIGHT_CLICK, "1");
        Self.useUtf8Locale();
    }

    /// Brings an SDL event coordinate (logical window points) into the design
    /// points hit/scroll regions live in.
    ///
    /// - `self`: the app.
    /// - `x`: the event's x.
    /// - `y`: the event's y.
    /// - Returns: the point in region space.
    pub fn eventPoint(self: *const Self, x: f32, y: f32) renderer.Point {
        return .{ .x = x * self.event_scale, .y = y * self.event_scale };
    }

    /// The app-requested wake cadence: the interval provider when set, else
    /// 16 ms while the boolean busy predicate holds.
    ///
    /// - `self`: the app.
    /// - Returns: milliseconds between wakes, 0 when idle.
    pub fn busyIntervalMs(self: *const Self) u32 {
        if (self.busy_interval) |interval| return interval();
        if (self.busy_check) |check| {
            if (check()) return 16;
        }
        return 0;
    }

    /// The wait slice while idle: up to the next caret flip when a field is
    /// focused.
    ///
    /// - `self`: the app.
    /// - Returns: milliseconds to wait.
    pub fn idleWaitMs(self: *const Self) c_int {
        if (views.Focus.shared().focused() == null) return Self.idle_wake_ms;
        const left = Self.blink_ms - (sdl_c.SDL_GetTicks() -| self.blink_epoch) % Self.blink_ms;
        return @intCast(@min(left + 1, @as(u64, @intCast(Self.idle_wake_ms))));
    }

    /// Reports whether the caret shows at `now`.
    ///
    /// - `self`: the app.
    /// - `now`: SDL ticks.
    /// - Returns: true in the caret's visible phase.
    pub fn caretPhaseOn(self: *const Self, now: u64) bool {
        return ((now -| self.blink_epoch) / Self.blink_ms) % 2 == 0;
    }

    /// Shows the I-beam over text (fields, editors, selectable text), else the
    /// arrow.
    ///
    /// - `self`: the app.
    /// - `over_text`: true for the I-beam.
    pub fn setTextCursor(self: *Self, over_text: bool) void {
        if (over_text == self.text_cursor) return;
        self.text_cursor = over_text;
        const index: usize = @intFromBool(over_text);
        if (self.cursors[index] == null) self.cursors[index] = sdl_c.SDL_CreateSystemCursor(if (over_text) sdl_c.SDL_SYSTEM_CURSOR_TEXT else sdl_c.SDL_SYSTEM_CURSOR_DEFAULT);
        if (self.cursors[index]) |cursor| _ = sdl_c.SDL_SetCursor(cursor);
    }

    /// `window`'s frame as it is now, in points.
    ///
    /// - `window`: the window.
    /// - Returns: the frame; null when SDL cannot say.
    fn currentFrame(window: *sdl_c.SDL_Window) ?mod.WindowFrame {
        var x: c_int = 0;
        var y: c_int = 0;
        var width: c_int = 0;
        var height: c_int = 0;
        if (!sdl_c.SDL_GetWindowPosition(window, &x, &y)) return null;
        if (!sdl_c.SDL_GetWindowSize(window, &width, &height)) return null;
        return .{ .x = x, .y = y, .width = @intCast(@max(width, 0)), .height = @intCast(@max(height, 0)) };
    }

    /// Gives the C library a UTF-8 character-type locale before SDL talks to the
    /// display. Unix processes start in the "C" locale, and on X11 (which SDL
    /// also picks under GNOME/XWayland) the legacy WM_NAME title goes through
    /// Xlib's locale conversion: in "C" the UTF-8 bytes of "ziggui — Gallery" are
    /// stored as Latin-1 and the title bar shows "ziggui â\u{80}\u{94} Gallery".
    /// Only LC_CTYPE is touched (as GTK/Qt apps do), so number formatting and
    /// collation stay "C". Uses the user's locale, else C.UTF-8. No-op off
    /// Linux/BSD.
    fn useUtf8Locale() void {
        switch (mod.os_tag) {
            .linux, .freebsd, .openbsd, .netbsd, .dragonfly => {},
            else => return,
        }
        if (std.c.setlocale(.CTYPE, "")) |name| {
            const locale = std.mem.span(name);
            if (std.ascii.findIgnoreCase(locale, "utf-8") != null or std.ascii.findIgnoreCase(locale, "utf8") != null) return;
        }
        _ = std.c.setlocale(.CTYPE, "C.UTF-8");
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
}
