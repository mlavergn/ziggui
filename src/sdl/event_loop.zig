//! The event loop `App.run` drives: SDL's start-up, the main window (and the
//! optional popover panel), the per-frame build, raster and present, the
//! event dispatch, and the idle and busy waits between frames.

const std = @import("std");
const log = std.log.scoped(.ziggui_event_loop);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// Rolling per-second render-time accumulator (see `App.setFrameLog`).
const FrameStatistics = struct {
    const Self = @This();

    /// Frames since the last report.
    count: u32 = 0,
    /// Their summed render time.
    sum_ns: u64 = 0,
    /// The longest of them.
    max_ns: u64 = 0,
    /// When the last report printed (SDL ticks).
    last_report_ms: u64 = 0,

    /// Adds one frame's render time, printing a report about once a second.
    fn record(self: *Self, elapsed_ns: u64, now_ms: u64) void {
        self.count += 1;
        self.sum_ns += elapsed_ns;
        if (elapsed_ns > self.max_ns) self.max_ns = elapsed_ns;
        if (self.last_report_ms == 0) self.last_report_ms = now_ms;
        if (now_ms - self.last_report_ms >= 1000 and self.count > 0) {
            const last_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1.0e6;
            const average_ms = @as(f64, @floatFromInt(self.sum_ns)) / @as(f64, @floatFromInt(self.count)) / 1.0e6;
            const max_ms = @as(f64, @floatFromInt(self.max_ns)) / 1.0e6;
            std.debug.print("[ziggui] render: last {d:.2}ms  avg {d:.2}ms  max {d:.2}ms  ({d} frames, {d:.0} fps-equiv)\n", .{
                last_ms, average_ms, max_ms, self.count, if (average_ms > 0) 1000.0 / average_ms else 0,
            });
            self.count = 0;
            self.sum_ns = 0;
            self.max_ns = 0;
            self.last_report_ms = now_ms;
        }
    }
};

/// A wheel event's sideways and vertical deltas.
const WheelDelta = struct {
    const Self = @This();

    /// Sideways lines, positive = to the right.
    x: f32,
    /// Vertical lines, positive = away from the user.
    y: f32,
};

/// Everything one `draw` needs for one window (the main window or the panel),
/// shared by the main loop and the resize watch (which run on the same
/// thread, never concurrently).
fn WindowFrame(comptime AppState: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        window: *sdl_c.SDL_Window,
        sdl_renderer: ?*sdl_c.SDL_Renderer,
        gpu_backend: ?*mod.Gpu,
        cache: *renderer.GlyphCache,
        icon_cache: *renderer.GlyphCache,
        config: mod.AppConfig,
        state: *AppState,
        /// Builds the main window's tree.
        body: *const fn (*AppState) views.View,
        /// Non-null for a panel frame: that body replaces the main window's.
        panel_body: ?*const fn (*AppState) views.View = null,
        /// Where this frame's hover point lives (main window or panel).
        hover: ?*?renderer.Point = null,
        /// Where this frame's `onHover` regions go (the main window only).
        hover_regions: ?*std.ArrayList(views.HoverRegion) = null,
        /// Resize the window to the view tree's content height each frame
        /// (the tray popover: no scrollbars, like Swift's auto-sizing panel).
        auto_height: bool = false,
        /// Transparent panel frame: clear to alpha 0 and paint a translucent
        /// rounded background, so corners reveal the desktop behind it.
        transparent: bool = false,
        texture: *?*sdl_c.SDL_Texture,
        texture_width: *c_int,
        texture_height: *c_int,
        // Persistent pixel buffers reused across frames (realloc only on resize),
        // so steady-state frames allocate no per-frame framebuffer/RGBA scratch.
        framebuffer: *renderer.Framebuffer,
        rgba: *[]u8,
        perf_frequency: u64,
        statistics: *FrameStatistics,
        resize_arena: *std.heap.ArenaAllocator,
        resize_hits: *std.ArrayList(views.HitRegion),
        resize_scrolls: *std.ArrayList(views.ScrollRegion),

        /// Build, rasterize and present one frame into `frame_arena`, recording
        /// hit/scroll regions into the given lists. Returns false (no present) if
        /// the window is hidden or has a degenerate size.
        fn draw(
            self: *Self,
            frame_arena: *std.heap.ArenaAllocator,
            hits: *std.ArrayList(views.HitRegion),
            scrolls: *std.ArrayList(views.ScrollRegion),
        ) bool {
            const app = mod.App.shared();
            if ((sdl_c.SDL_GetWindowFlags(self.window) & sdl_c.SDL_WINDOW_HIDDEN) != 0) return false;
            // Logical size (points) drives layout; pixel size drives the
            // framebuffer so output is crisp on Retina. Their ratio is the scale.
            var logical_width: c_int = 0;
            var logical_height: c_int = 0;
            _ = sdl_c.SDL_GetWindowSize(self.window, &logical_width, &logical_height);
            var pixel_width: c_int = 0;
            var pixel_height: c_int = 0;
            _ = sdl_c.SDL_GetWindowSizeInPixels(self.window, &pixel_width, &pixel_height);
            if (logical_width <= 0 or logical_height <= 0 or pixel_width <= 0 or pixel_height <= 0) return false;
            const start_counter = sdl_c.SDL_GetPerformanceCounter();
            const float_pixel_width: f32 = @floatFromInt(pixel_width);
            const float_pixel_height: f32 = @floatFromInt(pixel_height);
            // `display_scale` is the OS-honored content scale: it folds the HiDPI
            // backing density AND the user's display-scale setting (Windows
            // 125/150/200%, fractional scaling on Linux). The earlier `pw/lw`
            // captured only the backing density, so non-100% OS scaling was
            // ignored everywhere except macOS (where the two coincide). We lay the
            // UI out in `device_pixels / display_scale` design points and scale
            // each ×display_scale, so a control keeps its physical size on any
            // display. A 0.0 return means SDL couldn't query it: fall back to 1.
            const display_scale = sdl_c.SDL_GetWindowDisplayScale(self.window);
            const base_scale: f32 = if (display_scale > 0) display_scale else 1;
            // Supersampling (SSAA): render into a framebuffer `supersample`×
            // larger per axis, then downscale on present. This is the lever that
            // makes text crisp on a low-DPI (100%) display. Capped so the *total*
            // device scale stays ≤ 2: a Retina/HiDPI panel already has the
            // pixels, so we never render it at 4×.
            const supersample: f32 = @max(1, @min(@max(1, self.config.supersample), 2 / base_scale));
            // `scale` is device-pixels-per-design-point (backing × supersample);
            // layout still happens in design points (`base_scale` only), so hit
            // regions and event mapping are unaffected by `supersample`.
            const scale: f32 = base_scale * supersample;
            const point_width = float_pixel_width / base_scale;
            const point_height_in = float_pixel_height / base_scale;
            var point_height = point_height_in;
            // SDL mouse events arrive in logical window points; hit regions live
            // in design points. Convert by pixel_density / display_scale (== 1 on
            // macOS); `supersample` cancels out since it doesn't change the
            // design space.
            const pixel_density = float_pixel_width / @as(f32, @floatFromInt(logical_width));
            app.event_scale = pixel_density / base_scale;
            // The framebuffer/scene is the oversampled device size; present
            // downscales it to the window's actual pixel size.
            var scaled_width: u32 = @intFromFloat(@round(float_pixel_width * supersample));
            var scaled_height: u32 = @intFromFloat(@round(float_pixel_height * supersample));

            // Frame clock for time-based UI (auto-hiding scrollbars, etc.).
            views.FrameClock.shared().setTime(sdl_c.SDL_GetTicks());

            // Live theme: query the provider (if any) so light/dark switches take
            // effect without a restart. Read it after `body` builds the tree so the
            // framebuffer clear and Context agree with whatever the body painted.
            _ = frame_arena.reset(.retain_capacity);
            const arena = frame_arena.allocator();
            const theme = if (app.theme_provider) |provider| provider() else self.config.theme;
            // Publish the active theme's selection tints so composed constructors
            // (Sidebar/Table/RadioGroup) pick up dark mode and custom accents.
            views.BuildScope.shared().setTheme(theme);
            views.BuildScope.shared().setViewport(point_width, point_height);
            app.caret_drawn = app.caretPhaseOn(sdl_c.SDL_GetTicks());
            views.Focus.shared().setCaretVisible(app.caret_drawn);
            views.BuildScope.shared().begin(arena);
            const root = if (self.panel_body) |panel_body| panel_body(self.state) else self.body(self.state);
            views.BuildScope.shared().end();

            // Reset to empty (not clearRetainingCapacity): the previous buffer was
            // arena-allocated and the reset above reclaimed it, so keeping the old
            // pointer would alias freshly handed-out arena memory.
            hits.* = .empty;
            scrolls.* = .empty;
            var overlays: std.ArrayList(views.OverlayRequest) = .empty;
            var context = views.Context.initFull(theme, self.cache, arena, hits, &overlays, null);
            context.scroll_regions = scrolls;
            context.icon_cache = self.icon_cache;
            context.fonts = app.fonts;
            context.hover_point = if (self.hover) |hover| hover.* else null;
            if (self.hover_regions) |list| {
                list.* = .empty; // arena-backed, like `hits`
                context.hover_regions = list;
            }

            // Auto-height panel: measure the tree and resize the window to it,
            // clamped to the screen's usable height. Swift's MenuBarExtra panel
            // sizes itself to its content; matching that keeps the footer
            // visible instead of scrolling inside a fixed frame.
            if (self.auto_height) autoHeight: {
                const measured = views.ViewRenderer.measure(&context, root, .{ .width = point_width, .height = null }) catch break :autoHeight;
                var wanted: f32 = @max(measured.height, 60);
                var bounds: sdl_c.SDL_Rect = undefined;
                const display = sdl_c.SDL_GetDisplayForWindow(self.window);
                if (sdl_c.SDL_GetDisplayUsableBounds(display, &bounds)) wanted = @min(wanted, @as(f32, @floatFromInt(bounds.h)));
                const wanted_points: c_int = @intFromFloat(@round(wanted));
                if (wanted_points == logical_height) break :autoHeight;
                _ = sdl_c.SDL_SetWindowSize(self.window, logical_width, wanted_points);
                var grown_pixel_width: c_int = 0;
                var grown_pixel_height: c_int = 0;
                _ = sdl_c.SDL_GetWindowSizeInPixels(self.window, &grown_pixel_width, &grown_pixel_height);
                if (grown_pixel_width <= 0 or grown_pixel_height <= 0) break :autoHeight;
                point_height = @as(f32, @floatFromInt(grown_pixel_height)) / base_scale;
                scaled_width = @intFromFloat(@round(@as(f32, @floatFromInt(grown_pixel_width)) * supersample));
                scaled_height = @intFromFloat(@round(@as(f32, @floatFromInt(grown_pixel_height)) * supersample));
                // Keep the bottom edge on screen when the panel grew.
                if (sdl_c.SDL_GetDisplayUsableBounds(display, &bounds)) {
                    var window_x: c_int = 0;
                    var window_y: c_int = 0;
                    if (sdl_c.SDL_GetWindowPosition(self.window, &window_x, &window_y)) {
                        const max_y = bounds.y + bounds.h - wanted_points;
                        if (window_y > max_y) _ = sdl_c.SDL_SetWindowPosition(self.window, window_x, if (max_y < bounds.y) bounds.y else max_y);
                    }
                }
            }

            // Coverage gamma for text: a straight sRGB alpha-blend renders the
            // anti-aliased edge of light glyphs on a dark background too thin
            // (the classic "soft" custom-UI text). Gamma-correcting the coverage
            // restores weight. Dark themes lighten the edge (~0.6 ≈ the
            // gamma-correct result); light themes are left untouched (1.0) since
            // dark-on-light doesn't suffer the same thinning. Both backends apply
            // the same exponent, so software/GPU output stays pixel-matched.
            const dark_ui = theme.colors.window_background.luminance() < 0.5;
            renderer.TextPainter.shared().setGamma(if (dark_ui) 0.6 else 1.0);

            var canvas = renderer.Canvas.init(arena);
            if (self.transparent) {
                // The frosted NSVisualEffectView behind the SDL content view is
                // the panel's own chrome (Swift's MenuBarExtra popover). Painting
                // an opaque-ish window-background fill here would cover that
                // frost with a flat gray rectangle, so only the hairline rim is
                // drawn: every other pixel stays transparent and lets the
                // material show through.
                // Appended before renderScaled, which scales only the view's commands, so scale it here.
                // Only macOS has glass behind the window; elsewhere the panel is a solid card.
                if (mod.os_tag != .macos) canvas.fillRoundedRect(.{ .x = 0, .y = 0, .width = point_width * scale, .height = point_height * scale }, 12 * scale, theme.colors.window_background) catch |err| log.debug("panel card not drawn [{t}]", .{err});
                canvas.strokeRoundedRect(.{ .x = 0.5 * scale, .y = 0.5 * scale, .width = (point_width - 1) * scale, .height = (point_height - 1) * scale }, 12 * scale, scale, theme.colors.separator) catch |err| log.debug("panel rim not drawn [{t}]", .{err});
            } else {
                // No background fill command here: the framebuffer's `clear` below paints
                // the window background with a fast @memset, so emitting a full-window
                // fillRoundedRect would just re-rasterize every pixel through the SDF path.
            }
            views.ViewRenderer.renderScaled(&context, root, .{ .x = 0, .y = 0, .width = point_width, .height = point_height }, scale, &canvas) catch |err| log.debug("view tree not drawn [{t}]", .{err});

            if (self.gpu_backend) |gpu| {
                // GPU backend: translate + replay the command list on the GPU.
                // `supersample` makes it render the scene oversampled and
                // downscale on the final blit (SSAA), mirroring the software
                // texture path below.
                const clear = if (self.transparent) renderer.Color.transparent else theme.colors.window_background;
                if (!gpu.frame(arena, canvas.commands.items, clear, supersample)) return false;
            } else {
                // Software backend. Persistent framebuffer + RGBA buffer:
                // reallocated only when the pixel size changes, so a
                // steady-state frame does zero pixel-buffer allocation.
                const sdl_renderer = self.sdl_renderer.?;
                self.framebuffer.ensureSize(self.allocator, scaled_width, scaled_height) catch return false;
                self.framebuffer.clear(if (self.transparent) renderer.Color.transparent else theme.colors.window_background);
                renderer.Rasterizer.init(arena, self.framebuffer).render(canvas.commands.items) catch return false;
                const byte_count: usize = @as(usize, scaled_width) * @as(usize, scaled_height) * 4;
                if (self.rgba.*.len != byte_count) {
                    if (self.rgba.*.len > 0) self.allocator.free(self.rgba.*);
                    self.rgba.* = self.allocator.alloc(u8, byte_count) catch return false;
                }
                self.framebuffer.toRgba8(self.rgba.*);

                // Debug: ZIGGUI_PANEL_DUMP=<path> writes the transparent (panel)
                // frame's RGBA buffer once per size: u32 w, u32 h, then w*h*4
                // bytes. For offline analysis of what the app actually drew.
                if (self.transparent) {
                    if (sdl_c.SDL_getenv("ZIGGUI_PANEL_DUMP")) |path_sentinel| {
                        const size_key: u64 = @as(u64, @intCast(scaled_width)) << 32 | @as(u64, @intCast(scaled_height));
                        const panel = mod.Panel.shared();
                        if (panel.dump_written != size_key) {
                            panel.dump_written = size_key;
                            const path = std.mem.span(@as([*:0]const u8, @ptrCast(path_sentinel)));
                            var threaded = std.Io.Threaded.init(self.allocator, .{});
                            defer threaded.deinit();
                            const io = threaded.io();
                            if (std.Io.Dir.createFileAbsolute(io, path, .{})) |file| {
                                var header: [8]u8 = undefined;
                                std.mem.writeInt(u32, header[0..4], @intCast(scaled_width), .little);
                                std.mem.writeInt(u32, header[4..8], @intCast(scaled_height), .little);
                                file.writeStreamingAll(io, header[0..]) catch |err| log.debug("panel dump header not written [{t}]", .{err});
                                file.writeStreamingAll(io, self.rgba.*) catch |err| log.debug("panel dump pixels not written [{t}]", .{err});
                                file.close(io);
                            } else |_| {}
                        }
                    }
                }

                // The texture is the oversampled size; `SDL_RenderTexture` with a
                // null dst stretches it to the window's pixel size, and the
                // LINEAR scale mode makes that a clean SSAA downsample.
                const texture_width: c_int = @intCast(scaled_width);
                const texture_height: c_int = @intCast(scaled_height);
                if (self.texture.* == null or self.texture_width.* != texture_width or self.texture_height.* != texture_height) {
                    if (self.texture.*) |texture| sdl_c.SDL_DestroyTexture(texture);
                    self.texture.* = sdl_c.SDL_CreateTexture(sdl_renderer, sdl_c.SDL_PIXELFORMAT_ABGR8888, sdl_c.SDL_TEXTUREACCESS_STREAMING, texture_width, texture_height);
                    if (self.texture.*) |texture| _ = sdl_c.SDL_SetTextureScaleMode(texture, sdl_c.SDL_SCALEMODE_LINEAR);
                    self.texture_width.* = texture_width;
                    self.texture_height.* = texture_height;
                }
                if (self.transparent) {
                    if (self.texture.*) |texture| _ = sdl_c.SDL_SetTextureBlendMode(texture, sdl_c.SDL_BLENDMODE_BLEND);
                    _ = sdl_c.SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 0);
                }
                _ = sdl_c.SDL_UpdateTexture(self.texture.*, null, self.rgba.*.ptr, @intCast(scaled_width * 4));
                _ = sdl_c.SDL_RenderClear(sdl_renderer);
                _ = sdl_c.SDL_RenderTexture(sdl_renderer, self.texture.*, null, null);
                _ = sdl_c.SDL_RenderPresent(sdl_renderer);
            }

            if (app.frame_log) {
                const end_counter = sdl_c.SDL_GetPerformanceCounter();
                const elapsed_ns = (end_counter -% start_counter) *% 1_000_000_000 / self.perf_frequency;
                self.statistics.record(elapsed_ns, sdl_c.SDL_GetTicks());
            }
            return true;
        }

        /// SDL event watch: fires synchronously while events are pumped, INCLUDING
        /// during the macOS modal live-resize loop (when the main loop is blocked
        /// in SDL_WaitEvent). Redraw on resize/expose so content reflows live
        /// instead of the old texture being stretched until the mouse is released.
        fn resizeWatch(userdata: ?*anyopaque, event: [*c]sdl_c.SDL_Event) callconv(.c) bool {
            const frame: *Self = @ptrCast(@alignCast(userdata.?));
            switch (event.*.type) {
                sdl_c.SDL_EVENT_WINDOW_RESIZED,
                sdl_c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                sdl_c.SDL_EVENT_WINDOW_EXPOSED,
                => _ = frame.draw(frame.resize_arena, frame.resize_hits, frame.resize_scrolls),
                else => {},
            }
            return true;
        }
    };
}

/// Dispatches SDL events against one frame's regions: to the panel or the
/// main window, the app's handlers first, then focus, taps, drags, hovers,
/// wheels, typing and key editing.
const EventRouter = struct {
    const Self = @This();

    /// The loop's run flag, cleared by a quit.
    running: *bool,
    /// The main window's hit regions from the last frame.
    hits: []const views.HitRegion,
    /// The main window's scroll regions from the last frame.
    scrolls: []const views.ScrollRegion,

    /// Waits up to `timeout_ms` for an event, then handles it and every event
    /// already queued (draining the queue even after a timeout).
    fn waitThenDrain(self: *const Self, timeout_ms: c_int) void {
        var event: sdl_c.SDL_Event = undefined;
        if (sdl_c.SDL_WaitEventTimeout(&event, timeout_ms)) {
            self.handle(&event);
            if (Self.endsBatch(&event)) return;
        }
        while (sdl_c.SDL_PollEvent(&event)) {
            self.handle(&event);
            if (Self.endsBatch(&event)) return;
        }
    }

    /// Whether the rest of the queue waits for the next frame after `event`:
    /// a press may have removed what this frame's regions point at (a row and
    /// its fields), so a second click queued behind it must see new regions.
    ///
    /// - `event`: the event just handled.
    /// - Returns: true for a mouse press.
    fn endsBatch(event: *const sdl_c.SDL_Event) bool {
        return event.type == sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    }

    /// Waits up to `timeout_ms` for an event; when one comes, handles it and
    /// every event already queued. Returns whether one came.
    fn waitForEvent(self: *const Self, timeout_ms: c_int) bool {
        var event: sdl_c.SDL_Event = undefined;
        if (sdl_c.SDL_WaitEventTimeout(&event, timeout_ms)) {
            self.handle(&event);
            if (Self.endsBatch(&event)) return true;
            while (sdl_c.SDL_PollEvent(&event)) {
                self.handle(&event);
                if (Self.endsBatch(&event)) return true;
            }
            return true;
        }
        return false;
    }

    /// Handles one event.
    fn handle(self: *const Self, event: *sdl_c.SDL_Event) void {
        const app = mod.App.shared();
        const panel = mod.Panel.shared();
        // With frame logging on, also log which events wake the loop (each wake
        // costs a full rebuild+raster) so redraw storms can be attributed.
        if (app.frame_log) std.debug.print("[ziggui] event 0x{x}\n", .{event.type});
        const on_panel = panel.id != 0 and switch (event.type) {
            sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl_c.SDL_EVENT_MOUSE_MOTION, sdl_c.SDL_EVENT_MOUSE_WHEEL, sdl_c.SDL_EVENT_KEY_DOWN, sdl_c.SDL_EVENT_KEY_UP, sdl_c.SDL_EVENT_TEXT_INPUT => switch (event.type) {
                sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN => event.button.windowID == panel.id,
                sdl_c.SDL_EVENT_MOUSE_MOTION => event.motion.windowID == panel.id,
                sdl_c.SDL_EVENT_MOUSE_WHEEL => event.wheel.windowID == panel.id,
                sdl_c.SDL_EVENT_KEY_DOWN, sdl_c.SDL_EVENT_KEY_UP => event.key.windowID == panel.id,
                else => event.text.windowID == panel.id,
            },
            sdl_c.SDL_EVENT_WINDOW_FOCUS_LOST, sdl_c.SDL_EVENT_WINDOW_CLOSE_REQUESTED, sdl_c.SDL_EVENT_WINDOW_MOUSE_LEAVE => event.window.windowID == panel.id,
            else => false,
        };
        if (!on_panel and !views.TextContextMenu.shared().isOpen()) if (app.mouse_handler) |handler| if (mod.MouseEvent.fromSdl(event)) |mouse| if (handler(mouse)) return;
        const target_hits: []const views.HitRegion = if (on_panel) panel.hits else self.hits;
        const target_scrolls: []const views.ScrollRegion = if (on_panel) panel.scrolls else self.scrolls;
        switch (event.type) {
            sdl_c.SDL_EVENT_KEY_DOWN, sdl_c.SDL_EVENT_TEXT_INPUT, sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN => app.blink_epoch = sdl_c.SDL_GetTicks(),
            else => {},
        }
        switch (event.type) {
            // A quit handler may refuse (see `App.setQuitHandler`).
            sdl_c.SDL_EVENT_QUIT => app.hooks.requestQuit(self.running),
            // Clicking anywhere else dismisses the popover, like a native panel.
            sdl_c.SDL_EVENT_WINDOW_FOCUS_LOST => if (on_panel) panel.hide() else if (app.focus_handler) |handler| handler(false),
            sdl_c.SDL_EVENT_WINDOW_FOCUS_GAINED => if (event.window.windowID != panel.id) if (app.focus_handler) |handler| handler(true),
            // The flags are read as the event is handled, after a maximize's
            // own resize has set them, so only a restored frame is kept.
            sdl_c.SDL_EVENT_WINDOW_MOVED, sdl_c.SDL_EVENT_WINDOW_RESIZED => if (event.window.windowID != panel.id) if (app.window) |window| app.noteWindowFrame(window),
            // The close button: hide-to-tray when configured, else quit. (⌘Q still
            // sends SDL_EVENT_QUIT.)
            sdl_c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => if (on_panel) panel.hide() else if (app.hide_on_close) app.hideWindow() else {
                app.hooks.requestQuit(self.running);
            },
            sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const point = app.eventPoint(event.button.x, event.button.y);
                if (event.button.button == sdl_c.SDL_BUTTON_RIGHT) {
                    // Right-click pops the text context menu when over an editable
                    // field; elsewhere it just dismisses any open menu.
                    if (views.TextContextMenu.shared().fieldAt(target_hits, point)) |field| {
                        views.TextContextMenu.shared().open(field, point);
                    } else if (!views.PointerInput.shared().secondaryTap(target_hits, point)) {
                        views.TextContextMenu.shared().close();
                    }
                } else if (blk: {
                    const modifiers = sdl_c.SDL_GetModState();
                    views.PointerInput.shared().setClickModifiers((modifiers & sdl_c.SDL_KMOD_SHIFT) != 0, (modifiers & (sdl_c.SDL_KMOD_GUI | sdl_c.SDL_KMOD_CTRL)) != 0);
                    break :blk views.TextContextMenu.shared().isOpen();
                }) {
                    // A left-click while the menu is open routes to the menu (an item
                    // or the dismiss region) without disturbing focus.
                    _ = views.PointerInput.shared().tap(target_hits, point);
                } else {
                    views.Focus.shared().clear(); // a click defocuses; dispatch may refocus a field
                    views.PointerInput.shared().endDrag(); // reset any stale drag; dispatchTap re-arms over an editor
                    // In a text field, double-click selects the word and triple-click
                    // selects all; any other target falls back to a normal tap.
                    if (event.button.clicks >= 3 and views.PointerInput.shared().tripleClick(target_hits, point)) {} else if (event.button.clicks == 2 and views.PointerInput.shared().doubleClick(target_hits, point)) {} else {
                        views.PointerInput.shared().setTapCount(event.button.clicks);
                        defer views.PointerInput.shared().setTapCount(1);
                        _ = views.PointerInput.shared().tap(target_hits, point);
                    }
                }
            },
            // Drag the mouse with the left button held to extend a text selection.
            sdl_c.SDL_EVENT_MOUSE_MOTION => {
                const motion_point = app.eventPoint(event.motion.x, event.motion.y);
                if (on_panel) panel.hover = motion_point else {
                    // `onHover` callbacks fire on crossing a region's edge.
                    _ = views.PointerInput.shared().hover(app.hover_regions.items, app.hover_point, motion_point);
                    app.hover_point = motion_point; // drives Modifiers.hover_fill highlights
                }
                // Track the hovered context-menu item (the loop redraws after this
                // event, so the highlight follows the cursor).
                if (views.TextContextMenu.shared().isOpen()) views.TextContextMenu.shared().hover(target_hits, motion_point);
                if ((event.motion.state & sdl_c.SDL_BUTTON_LMASK) != 0) {
                    views.PointerInput.shared().drag(target_hits, motion_point);
                }
                app.setTextCursor(views.PointerInput.shared().textCursorAt(target_hits, motion_point));
            },
            sdl_c.SDL_EVENT_MOUSE_BUTTON_UP => views.PointerInput.shared().endDrag(),
            sdl_c.SDL_EVENT_WINDOW_MOUSE_LEAVE => if (on_panel) {
                panel.hover = null;
            } else {
                _ = views.PointerInput.shared().hover(app.hover_regions.items, app.hover_point, null);
                app.hover_point = null;
            },
            sdl_c.SDL_EVENT_KEY_UP => if (!on_panel) app.hooks.keyUp(event.key.key, @intCast(event.key.mod)),
            sdl_c.SDL_EVENT_DROP_FILE => {
                if (app.drop_handler) |handler| if (event.drop.data != null) handler(std.mem.span(event.drop.data));
            },
            sdl_c.SDL_EVENT_MOUSE_WHEEL => {
                const delta = Self.wheelDeltas(event.wheel.x, event.wheel.y, @intCast(sdl_c.SDL_GetModState()));
                _ = views.PointerInput.shared().scrollBoth(target_scrolls, app.eventPoint(event.wheel.mouse_x, event.wheel.mouse_y), delta.x, delta.y);
            },
            sdl_c.SDL_EVENT_TEXT_INPUT => {
                const typed = std.mem.span(event.text.text);
                if (app.text_handler) |handler| if (handler(typed)) return;
                if (views.Focus.shared().focused()) |field| {
                    field.insert(typed) catch |err| log.debug("typed text not inserted [{t}]", .{err});
                }
            },
            sdl_c.SDL_EVENT_KEY_DOWN => {
                // Escape dismisses the popover before anything else sees the key.
                if (on_panel and event.key.key == sdl_c.SDLK_ESCAPE) {
                    panel.hide();
                    return;
                }
                // App shortcuts/clipboard get first refusal; a true return consumes
                // the key so default editing below is skipped.
                if (app.key_handler) |handler| {
                    if (handler(event.key.key, @intCast(event.key.mod))) return;
                }
                // Escape closes an open context menu before anything else sees the key.
                if (views.TextContextMenu.shared().isOpen() and event.key.key == sdl_c.SDLK_ESCAPE) {
                    views.TextContextMenu.shared().close();
                    return;
                }
                // ⌘C with no field focused copies selected text (chat, code).
                if (views.Focus.shared().focused() == null and event.key.key == sdl_c.SDLK_C and (event.key.mod & (sdl_c.SDL_KMOD_GUI | sdl_c.SDL_KMOD_CTRL)) != 0) {
                    if (views.TextSelection.shared().selectedText()) |selected| mod.Clipboard.setText(std.heap.page_allocator, selected);
                    return;
                }
                if (views.Focus.shared().focused()) |field| {
                    // Clipboard shortcuts (⌘ on macOS, Ctrl elsewhere) take priority
                    // over plain editing. With the command/ctrl modifier held SDL does
                    // not emit a matching TEXT_INPUT, so consuming the key here is safe.
                    if ((event.key.mod & (sdl_c.SDL_KMOD_GUI | sdl_c.SDL_KMOD_CTRL)) != 0) {
                        switch (event.key.key) {
                            // A secure field's text never reaches the clipboard.
                            sdl_c.SDLK_C => {
                                if (!field.secure) mod.Clipboard.copySelection(field);
                                return;
                            },
                            sdl_c.SDLK_X => {
                                if (field.secure) return;
                                mod.Clipboard.copySelection(field);
                                _ = field.deleteSelection();
                                return;
                            },
                            sdl_c.SDLK_V => {
                                mod.Clipboard.paste(field);
                                return;
                            },
                            sdl_c.SDLK_A => {
                                field.selectAll();
                                return;
                            },
                            else => {},
                        }
                    }
                    const shift = (event.key.mod & sdl_c.SDL_KMOD_SHIFT) != 0;
                    // macOS: ⌘←/⌘→ go to the line's start and end (a one-line
                    // field's head and tail), ⌘↑/⌘↓ to the text's.
                    const command = mod.os_tag == .macos and (event.key.mod & sdl_c.SDL_KMOD_GUI) != 0;
                    switch (event.key.key) {
                        sdl_c.SDLK_BACKSPACE => field.backspace(),
                        sdl_c.SDLK_DELETE => field.deleteForward(),
                        sdl_c.SDLK_LEFT => if (command) field.home(shift) else field.moveLeft(shift),
                        sdl_c.SDLK_RIGHT => if (command) field.end(shift) else field.moveRight(shift),
                        sdl_c.SDLK_UP => if (command) field.moveToStart(shift) else field.moveUp(shift),
                        sdl_c.SDLK_DOWN => if (command) field.moveToEnd(shift) else field.moveDown(shift),
                        sdl_c.SDLK_HOME => field.home(shift),
                        sdl_c.SDLK_END => field.end(shift),
                        // Multi-line editors insert a newline; single-line fields submit.
                        sdl_c.SDLK_RETURN, sdl_c.SDLK_KP_ENTER => if (field.multiline) field.insert("\n") catch |err| log.debug("newline not inserted [{t}]", .{err}) else views.Focus.shared().submit(),
                        // Tab indents a multi-line editor (no focus traversal here).
                        sdl_c.SDLK_TAB => if (field.multiline) field.insert("    ") catch |err| log.debug("indent not inserted [{t}]", .{err}),
                        sdl_c.SDLK_ESCAPE => views.Focus.shared().clear(),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// A wheel event's deltas for `PointerInput.scrollBoth`. Off macOS, Shift
    /// turns the vertical wheel sideways (wheel away from the user scrolls
    /// left); macOS already does that itself, sending `wheel.x`, so it is not
    /// done twice.
    fn wheelDeltas(x: f32, y: f32, modifiers: u16) WheelDelta {
        if (mod.os_tag != .macos and x == 0 and (modifiers & sdl_c.SDL_KMOD_SHIFT) != 0) return .{ .x = -y, .y = 0 };
        return .{ .x = x, .y = y };
    }
};

/// The event loop for one app state type: SDL, the main window and its
/// renderer (GPU, else software), the optional popover panel, the fonts,
/// arenas and pixel buffers its frames reuse. `create` starts SDL and opens
/// the windows, `run` loops until a quit, and `destroy` tears everything down
/// in reverse.
///
/// - `AppState`: the app's state type, which the bodies build from.
/// - Returns: the event loop type.
pub fn EventLoop(comptime AppState: type) type {
    return struct {
        const Self = @This();

        /// Owns the loop and its resources.
        allocator: std.mem.Allocator,
        /// The app's state, handed to the bodies.
        state: *AppState,
        /// The window and rendering configuration.
        config: mod.AppConfig,
        /// Builds the main window's tree.
        body: *const fn (*AppState) views.View,
        /// The popover panel, or null for none.
        panel: ?mod.PanelSpecification(AppState),

        /// The main window.
        window: *sdl_c.SDL_Window = undefined,
        /// The GPU backend, or null for the software path.
        gpu_backend: ?mod.Gpu = null,
        /// The software path's renderer, or null on the GPU path.
        sdl_renderer: ?*sdl_c.SDL_Renderer = null,

        // The popover panel (a second, hidden window). It uses its own
        // SDL_Renderer + CPU raster path, so the main window's GPU backend and
        // swapchain stay untouched.
        panel_window: ?*sdl_c.SDL_Window = null,
        panel_renderer: ?*sdl_c.SDL_Renderer = null,
        panel_texture: ?*sdl_c.SDL_Texture = null,
        panel_texture_width: c_int = 0,
        panel_texture_height: c_int = 0,
        panel_framebuffer: renderer.Framebuffer = .empty,
        panel_rgba: []u8 = &.{},
        panel_arena: std.heap.ArenaAllocator = undefined,

        // Fonts. The bundled monochrome emoji font is wired as a fallback so
        // codepoints Inter lacks (emoji, etc.) still render; it lives for the
        // whole loop, so the `&emoji_font.face` pointer stays valid.
        font: renderer.Font = undefined,
        emoji_font: renderer.Font = undefined,
        cache: renderer.GlyphCache = undefined,
        icon_font: renderer.Font = undefined,
        icon_cache: renderer.GlyphCache = undefined,
        fonts: *renderer.FontSet = undefined,

        /// The main window's per-frame arena.
        frame_arena: std.heap.ArenaAllocator = undefined,

        /// Animations are driven here: the loop ticks the animator each frame
        /// while it is active, and view callbacks reach it via `App.animator`.
        animator: renderer.Animator = undefined,
        /// When the animator last ticked (SDL ticks).
        last_ms: u64 = 0,

        // The main window's software-path texture and pixel buffers (reused
        // across frames; freed at shutdown).
        texture: ?*sdl_c.SDL_Texture = null,
        texture_width: c_int = 0,
        texture_height: c_int = 0,
        framebuffer: renderer.Framebuffer = .empty,
        rgba: []u8 = &.{},
        perf_frequency: u64 = 0,
        statistics: FrameStatistics = .{},

        /// Caches wrapped-text layout across frames so a long, static
        /// transcript isn't re-wrapped on every redraw.
        wrap_cache: views.WrapCache = undefined,

        // A dedicated arena + scratch region lists for redraws issued from the
        // macOS live-resize event watch, so a watch-triggered frame never
        // aliases the main loop's arena (which is mid-use when the watch
        // fires). The lists are backed by `resize_arena` (their items hold
        // arena-allocated callbacks), so they are never deinit'd with the
        // allocator: `resize_arena.deinit()` reclaims everything.
        resize_arena: std.heap.ArenaAllocator = undefined,
        resize_hits: std.ArrayList(views.HitRegion) = .empty,
        resize_scrolls: std.ArrayList(views.ScrollRegion) = .empty,

        /// The loop runs while this holds.
        running: bool = true,

        /// The main window's frame.
        frame: WindowFrame(AppState) = undefined,
        /// The panel's frame, when there is a panel window.
        panel_frame: ?WindowFrame(AppState) = null,
        /// The panel's hit regions from its last frame.
        panel_hits: std.ArrayList(views.HitRegion) = .empty,
        /// The panel's scroll regions from its last frame.
        panel_scrolls: std.ArrayList(views.ScrollRegion) = .empty,

        /// Starts SDL, opens the main window (and the hidden panel window when
        /// `panel` is set), and readies the renderer, fonts and buffers. On
        /// failure everything started so far is torn down again.
        ///
        /// - `allocator`: owns the loop and its resources.
        /// - `state`: the app's state, handed to the bodies.
        /// - `config`: the window and rendering configuration.
        /// - `body`: builds the main window's tree.
        /// - `panel`: the popover panel, or null for none.
        /// - Returns: the loop, which `destroy` frees; propagates SDL start-up
        ///   and allocation failure.
        pub fn create(
            allocator: std.mem.Allocator,
            state: *AppState,
            config: mod.AppConfig,
            body: *const fn (*AppState) views.View,
            panel: ?mod.PanelSpecification(AppState),
        ) !*Self {
            log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);
            self.* = .{ .allocator = allocator, .state = state, .config = config, .body = body, .panel = panel };
            const app = mod.App.shared();

            // A hide-to-tray app must not quit when its last visible window is closed:
            // SDL would send SDL_EVENT_QUIT itself, before our close handler hides it.
            if (config.hide_on_close) _ = sdl_c.SDL_SetHint(sdl_c.SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE, "0");
            app.beforeSdlInit();
            if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) {
                std.log.err("SDL_Init failed: {s}", .{sdl_c.SDL_GetError()});
                return mod.AppError.SdlInit;
            }
            errdefer sdl_c.SDL_Quit();

            try self.openWindow();
            errdefer sdl_c.SDL_DestroyWindow(self.window);
            self.decorateWindow();

            // Prefer the GPU backend; when device/swapchain creation fails (no Vulkan
            // driver, headless CI, ZIGGUI_SOFTWARE set) fall back to the software
            // rasterizer presented through an SDL streaming texture.
            const want_gpu = config.gpu and sdl_c.SDL_getenv("ZIGGUI_SOFTWARE") == null;
            self.gpu_backend = if (want_gpu) mod.Gpu.init(allocator, self.window) else null;
            errdefer if (self.gpu_backend) |*gpu| gpu.deinit();
            if (self.gpu_backend) |*gpu| std.log.info("ziggui: rendering via SDL_GPU ({s})", .{gpu.driverName()});

            self.sdl_renderer = if (self.gpu_backend != null) null else sdl_c.SDL_CreateRenderer(self.window, null) orelse {
                std.log.err("SDL_CreateRenderer failed: {s}", .{sdl_c.SDL_GetError()});
                return mod.AppError.SdlInit;
            };
            errdefer if (self.sdl_renderer) |sdl_renderer| sdl_c.SDL_DestroyRenderer(sdl_renderer);

            self.panel_arena = std.heap.ArenaAllocator.init(allocator);
            errdefer self.closePanel();
            self.openPanel();

            _ = sdl_c.SDL_StartTextInput(self.window);

            self.font = renderer.Font.default();
            self.emoji_font = renderer.Font.emoji();
            self.emoji_font.face.fallback = config.fallback_font;
            self.font.face.fallback = &self.emoji_font.face;
            self.cache = renderer.GlyphCache.init(allocator, &self.font.face);
            errdefer self.cache.deinit();

            self.icon_font = renderer.Font.icons();
            self.icon_cache = renderer.GlyphCache.init(allocator, &self.icon_font.face);
            errdefer self.icon_cache.deinit();

            self.fonts = try renderer.FontSet.create(allocator);
            // Nothing below fails.
            if (config.fallback_font) |fallback| self.fonts.setFallback(fallback);
            app.fonts = self.fonts;

            self.frame_arena = std.heap.ArenaAllocator.init(allocator);

            self.animator = renderer.Animator.init(allocator);
            app.active_animator = &self.animator;
            self.last_ms = sdl_c.SDL_GetTicks();

            self.perf_frequency = sdl_c.SDL_GetPerformanceFrequency();
            // Opt-in frame profiling via an environment variable (in addition to `App.setFrameLog`).
            if (sdl_c.SDL_getenv("ZIGGUI_FRAME_LOG") != null) app.frame_log = true;

            // Let the (platform-free) context menu copy/paste via the SDL clipboard.
            views.TextContextMenu.shared().setClipboardOperations(.{ .copy = mod.Clipboard.copySelection, .paste = mod.Clipboard.paste });

            self.wrap_cache = views.WrapCache.init(allocator);
            views.BuildScope.shared().setWrapCache(&self.wrap_cache);

            self.resize_arena = std.heap.ArenaAllocator.init(allocator);

            self.running = true;
            // Expose the window/loop to tray callbacks and the close handler.
            app.window = self.window;
            app.running = &self.running;
            // A view's worker (a folder listing) wakes the loop when it is done.
            views.FrameClock.shared().setWakeHandler(Self.wakeApp);
            app.hide_on_close = config.hide_on_close;

            self.frame = .{
                .allocator = allocator,
                .window = self.window,
                .sdl_renderer = self.sdl_renderer,
                .gpu_backend = if (self.gpu_backend) |*gpu| gpu else null,
                .cache = &self.cache,
                .icon_cache = &self.icon_cache,
                .config = config,
                .state = state,
                .body = body,
                .hover = &app.hover_point,
                .hover_regions = &app.hover_regions,
                .texture = &self.texture,
                .texture_width = &self.texture_width,
                .texture_height = &self.texture_height,
                .framebuffer = &self.framebuffer,
                .rgba = &self.rgba,
                .perf_frequency = self.perf_frequency,
                .statistics = &self.statistics,
                .resize_arena = &self.resize_arena,
                .resize_hits = &self.resize_hits,
                .resize_scrolls = &self.resize_scrolls,
            };
            _ = sdl_c.SDL_AddEventWatch(WindowFrame(AppState).resizeWatch, &self.frame);

            if (panel) |panel_specification| {
                if (self.panel_window) |panel_window| self.panel_frame = .{
                    .allocator = allocator,
                    .window = panel_window,
                    .sdl_renderer = self.panel_renderer,
                    .gpu_backend = null,
                    .cache = &self.cache,
                    .icon_cache = &self.icon_cache,
                    .config = config,
                    .state = state,
                    .body = body,
                    .panel_body = panel_specification.body,
                    .hover = &mod.Panel.shared().hover,
                    .auto_height = true,
                    .transparent = true,
                    .texture = &self.panel_texture,
                    .texture_width = &self.panel_texture_width,
                    .texture_height = &self.panel_texture_height,
                    .framebuffer = &self.panel_framebuffer,
                    .rgba = &self.panel_rgba,
                    .perf_frequency = self.perf_frequency,
                    .statistics = &self.statistics,
                    .resize_arena = &self.resize_arena,
                    .resize_hits = &self.resize_hits,
                    .resize_scrolls = &self.resize_scrolls,
                };
            }
            return self;
        }

        /// Tears down everything `create` started, in reverse, and frees the loop.
        ///
        /// - `self`: the loop.
        pub fn destroy(self: *Self) void {
            const app = mod.App.shared();
            sdl_c.SDL_RemoveEventWatch(WindowFrame(AppState).resizeWatch, &self.frame);
            app.window = null;
            app.running = null;
            self.resize_arena.deinit();
            views.BuildScope.shared().setWrapCache(null);
            self.wrap_cache.deinit();
            if (self.rgba.len > 0) self.allocator.free(self.rgba);
            self.framebuffer.deinit();
            if (self.texture) |texture| sdl_c.SDL_DestroyTexture(texture);
            app.active_animator = null;
            self.animator.deinit();
            self.frame_arena.deinit();
            app.fonts = null;
            self.fonts.destroy();
            self.icon_cache.deinit();
            self.cache.deinit();
            self.closePanel();
            if (self.sdl_renderer) |sdl_renderer| sdl_c.SDL_DestroyRenderer(sdl_renderer);
            if (self.gpu_backend) |*gpu| gpu.deinit();
            views.FrameClock.shared().setWakeHandler(null);
            sdl_c.SDL_DestroyWindow(self.window);
            sdl_c.SDL_Quit();
            self.allocator.destroy(self);
        }

        /// Draws, waits and dispatches until a quit clears `running`.
        ///
        /// - `self`: the loop.
        pub fn run(self: *Self) void {
            const app = mod.App.shared();
            const panel = mod.Panel.shared();
            while (self.running) {
                // Per-frame hook (e.g. refresh the system-tray menu). Runs whether or not
                // the window is visible, so the tray tracks status even when hidden.
                if (app.frame_hook) |hook| hook();
                mod.StatusItem.shared().takeLinuxClick();

                // Fresh per-frame region lists (arena-backed via `draw`); discarded at
                // the next arena reset. The main window is skipped while
                // hidden-to-tray; the panel draws on its own arena/renderer whenever
                // it is shown.
                var hits: std.ArrayList(views.HitRegion) = .empty;
                var scrolls: std.ArrayList(views.ScrollRegion) = .empty;
                const main_hidden = (sdl_c.SDL_GetWindowFlags(self.window) & sdl_c.SDL_WINDOW_HIDDEN) != 0;
                const drew_main = if (main_hidden) false else self.frame.draw(&self.frame_arena, &hits, &scrolls);
                mod.WindowHitTest.shared().hits = if (drew_main) hits.items else &.{};

                self.panel_hits = .empty;
                self.panel_scrolls = .empty;
                const drew_panel = if (self.panel_frame != null and panel.shown)
                    self.panel_frame.?.draw(&self.panel_arena, &self.panel_hits, &self.panel_scrolls)
                else
                    false;
                panel.hits = if (drew_panel) self.panel_hits.items else &.{};
                panel.scrolls = if (drew_panel) self.panel_scrolls.items else &.{};

                // Event handling. Hit/scroll regions stay in design points
                // (renderScaled leaves them unscaled); SDL reports mouse coordinates
                // in logical window points, so the router converts via
                // `App.eventPoint` before dispatch (a no-op on macOS).
                const router = EventRouter{ .running = &self.running, .hits = hits.items, .scrolls = scrolls.items };
                if (!drew_main and !drew_panel) {
                    // Nothing drew: pump events and block efficiently. While a busy
                    // predicate is set (e.g. a generation in flight), wake on a ~60fps
                    // timeout so the frame hook keeps the tray status live. Cap the
                    // idle wait (`idle_wake_ms`): a hidden-to-tray window can't
                    // receive an event to observe a tray callback's `running = false`,
                    // so a blocking wait here hangs Quit forever.
                    const busy_ms = app.busyIntervalMs();
                    router.waitThenDrain(if (busy_ms != 0) @intCast(busy_ms) else mod.App.idle_wake_ms);
                    continue;
                }
                self.waitAfterFrame(&router);
            }
        }

        /// Waits for the next frame after one drew. While animating *or* while
        /// a busy predicate is set (e.g. a streaming request in flight), wakes
        /// on a ~60fps timeout and ticks the animator; otherwise blocks for
        /// input in idle slices.
        fn waitAfterFrame(self: *Self, router: *const EventRouter) void {
            const app = mod.App.shared();
            // UI animations keep their own ~60fps cadence; the app's requested
            // interval (e.g. a slow spinner repaint during a heavy GPU job) paces
            // the loop only when nothing is animating.
            const app_ms = app.busyIntervalMs();
            const animating = self.animator.active() or views.FrameClock.shared().scrollbarsAnimating(sdl_c.SDL_GetTicks());
            const busy_ms: u32 = if (animating) (if (app_ms == 0) 16 else @min(app_ms, 16)) else app_ms;
            if (busy_ms != 0) {
                router.waitThenDrain(@intCast(busy_ms));
                const now = sdl_c.SDL_GetTicks();
                const delta_seconds: f32 = @as(f32, @floatFromInt(now - self.last_ms)) / 1000.0;
                self.last_ms = now;
                self.animator.tick(delta_seconds);
            } else {
                self.waitIdle(router);
            }
        }

        /// Fully idle: waits for input. A blocking SDL_WaitEvent would only
        /// return on an SDL event, but a tray/menu callback flips `running`
        /// (tray Quit) or updates tray state while posting none, so a bare
        /// block leaves the app parked until the user's next mouse-over, and
        /// hangs forever when the window is hidden. Instead it waits in
        /// `idle_wake_ms` slices: on a timeout it re-runs the frame hook (keeps
        /// the tray live) and re-checks `running`, WITHOUT redrawing: nothing
        /// changed, so idle stays ~free (no 4 Hz repaint). Only a real event
        /// breaks out to the redraw at the top of the outer loop; it dispatches
        /// against the last frame's hit regions, still valid since no draw has
        /// reset the arena.
        fn waitIdle(self: *Self, router: *const EventRouter) void {
            const app = mod.App.shared();
            while (self.running) {
                if (router.waitForEvent(app.idleWaitMs())) break;
                if (app.frame_hook) |hook| hook();
                // Background work (a generation, playback) may have flipped the
                // busy cadence on: leave idle so the outer loop redraws at it.
                if (app.busyIntervalMs() != 0) break;
                // The caret's blink phase flipped: redraw just for it.
                if (views.Focus.shared().focused() != null and app.caretPhaseOn(sdl_c.SDL_GetTicks()) != app.caret_drawn) break;
            }
            self.last_ms = sdl_c.SDL_GetTicks();
        }

        /// Whether the window draws its own title bar (never on macOS).
        fn customTitlebar(self: *const Self) bool {
            return self.config.custom_titlebar and mod.os_tag != .macos;
        }

        /// Creates the main window.
        fn openWindow(self: *Self) !void {
            self.window = sdl_c.SDL_CreateWindow(
                self.config.title.ptr,
                // Clamped: a size read from a file may not fit a c_int.
                @intCast(@min(self.config.width, std.math.maxInt(c_int))),
                @intCast(@min(self.config.height, std.math.maxInt(c_int))),
                sdl_c.SDL_WINDOW_RESIZABLE | sdl_c.SDL_WINDOW_HIGH_PIXEL_DENSITY | (if (self.customTitlebar()) sdl_c.SDL_WINDOW_BORDERLESS else 0),
            ) orelse {
                std.log.err("SDL_CreateWindow failed: {s}", .{sdl_c.SDL_GetError()});
                return mod.AppError.SdlInit;
            };
        }

        /// Applies the minimum size, title bar, menu bar, hit test and icon.
        fn decorateWindow(self: *Self) void {
            const config = self.config;
            const window = self.window;
            const custom_titlebar = self.customTitlebar();
            if (config.min_width > 0 and config.min_height > 0)
                _ = sdl_c.SDL_SetWindowMinimumSize(window, @intCast(config.min_width), @intCast(config.min_height));
            // A remembered place, kept only while some display still shows the window.
            if (config.x) |x| if (config.y) |y| {
                const frame: mod.WindowFrame = .{ .x = x, .y = y, .width = config.width, .height = config.height };
                if (Self.onSomeDisplay(frame)) _ = sdl_c.SDL_SetWindowPosition(window, x, y);
            };
            // Before maximizing: the frame the window returns to when restored.
            mod.App.shared().noteWindowFrame(window);
            if (config.maximized) _ = sdl_c.SDL_MaximizeWindow(window);
            if (config.unified_titlebar and mod.os_tag == .macos) mod.Cocoa.unifyTitlebar(window);
            if ((config.menus.len > 0 or config.settings != null) and mod.os_tag == .macos) mod.Cocoa.shared().setMenuBar(config.menus, config.settings);
            if (config.drag_band > 0 or custom_titlebar) mod.WindowHitTest.shared().install(window, config.drag_band, custom_titlebar);

            // Window/taskbar icon (SDL copies the surface, so we free it immediately).
            if (config.icon) |icon| {
                if (icon.surface()) |surface| {
                    _ = sdl_c.SDL_SetWindowIcon(window, surface);
                    sdl_c.SDL_DestroySurface(surface);
                }
            } else if (config.icon_png) |bytes| {
                if (!mod.Win32.hasIconResource()) {
                    const io = sdl_c.SDL_IOFromConstMem(bytes.ptr, bytes.len);
                    if (sdl_c.SDL_LoadPNG_IO(io, true)) |surface| {
                        _ = sdl_c.SDL_SetWindowIcon(window, surface);
                        sdl_c.SDL_DestroySurface(surface);
                    } else std.log.info("ziggui: icon_png not loaded ({s})", .{sdl_c.SDL_GetError()});
                }
            }
        }

        /// `FrameClock.wake`'s handler: wakes the loop from any thread.
        fn wakeApp() void {
            mod.App.shared().wake();
        }

        /// Whether enough of `frame` falls inside some display's usable area to grab.
        ///
        /// - `frame`: the window's frame, in points.
        /// - Returns: true when a display shows it.
        fn onSomeDisplay(frame: mod.WindowFrame) bool {
            var count: c_int = 0;
            const displays = sdl_c.SDL_GetDisplays(&count) orelse return false;
            defer sdl_c.SDL_free(displays);
            for (displays[0..@intCast(count)]) |display| {
                var bounds: sdl_c.SDL_Rect = undefined;
                if (!sdl_c.SDL_GetDisplayUsableBounds(display, &bounds)) continue;
                const usable: mod.WindowFrame = .{ .x = bounds.x, .y = bounds.y, .width = @intCast(@max(bounds.w, 0)), .height = @intCast(@max(bounds.h, 0)) };
                if (frame.overlaps(usable, 100)) return true;
            }
            return false;
        }

        /// Creates the hidden panel window and its renderer, when there is a
        /// panel; a failure is logged and leaves the app without one.
        fn openPanel(self: *Self) void {
            const panel_specification = self.panel orelse return;
            const panel = mod.Panel.shared();
            // X11: compositors such as COSMIC place managed windows themselves and
            // ignore the position asked for; an override-redirect window goes
            // where `Panel.show` puts it. The window manager then never focuses
            // it, so `Panel.show` does.
            if (mod.os_tag == .linux) _ = sdl_c.SDL_SetHint(sdl_c.SDL_HINT_X11_FORCE_OVERRIDE_REDIRECT, "1");
            defer if (mod.os_tag == .linux) {
                _ = sdl_c.SDL_ResetHint(sdl_c.SDL_HINT_X11_FORCE_OVERRIDE_REDIRECT);
            };
            const window = sdl_c.SDL_CreateWindow(
                self.config.title.ptr,
                @intCast(panel_specification.width),
                @intCast(panel_specification.height),
                sdl_c.SDL_WINDOW_BORDERLESS | sdl_c.SDL_WINDOW_UTILITY | sdl_c.SDL_WINDOW_ALWAYS_ON_TOP | sdl_c.SDL_WINDOW_HIGH_PIXEL_DENSITY | sdl_c.SDL_WINDOW_TRANSPARENT,
            ) orelse {
                std.log.warn("ziggui: panel window failed: {s}", .{sdl_c.SDL_GetError()});
                return;
            };
            self.panel_window = window;
            panel.window = window;
            panel.id = sdl_c.SDL_GetWindowID(window);
            self.panel_renderer = sdl_c.SDL_CreateRenderer(window, null) orelse sdl_c.SDL_CreateRenderer(window, "software") orelse {
                std.log.warn("ziggui: panel renderer failed: {s}", .{sdl_c.SDL_GetError()});
                sdl_c.SDL_DestroyWindow(window);
                self.panel_window = null;
                panel.window = null;
                panel.id = 0;
                return;
            };
            // Debug: ZIGGUI_NO_FROST=1 leaves the glass off (for bisecting compositing artifacts).
            if (mod.os_tag == .macos and sdl_c.SDL_getenv("ZIGGUI_NO_FROST") == null) mod.Cocoa.frostWindow(window, 12);
            _ = sdl_c.SDL_HideWindow(window);
        }

        /// Panel teardown in dependency order: texture, renderer, window, then
        /// its buffers and arena.
        fn closePanel(self: *Self) void {
            if (self.panel_texture) |texture| sdl_c.SDL_DestroyTexture(texture);
            if (self.panel_renderer) |panel_renderer| sdl_c.SDL_DestroyRenderer(panel_renderer);
            if (self.panel_window) |window| {
                const panel = mod.Panel.shared();
                panel.window = null;
                panel.id = 0;
                panel.shown = false;
                sdl_c.SDL_DestroyWindow(window);
            }
            if (self.panel_rgba.len > 0) self.allocator.free(self.panel_rgba);
            self.panel_framebuffer.deinit();
            self.panel_arena.deinit();
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
