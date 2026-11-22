//! Paints a laid-out view tree: co-walks the views with their layout frames,
//! applying modifiers and dispatching each kind to its painter.

const std = @import("std");
const log = std.log.scoped(.ziggui_view_painter);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Paints views into a display list, registering their input regions, overlay
/// requests and accessibility nodes in the context's sinks.
pub const ViewPainter = struct {
    const Self = @This();

    /// Paints `view` and its subtree into the frames `layout` arranged.
    ///
    /// - `context`: the context the view inherits.
    /// - `view`: the view.
    /// - `layout`: its arranged frames.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paint(context: *const mod.Context, view: mod.View, layout: renderer.LayoutResult, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const outer = layout.frame;
        if (view.modifiers.reveal_on_hover and !context.in_hover_scope) return;
        // Scrolled out of view: nothing of it can show (a long transcript paints
        // only the screenful it shows). A view that presents an overlay still
        // paints, so the overlay request is not lost.
        if (context.visible) |visible| if (!outer.intersects(visible) and view.modifiers.overlay.len == 0) return;

        // Resolve inherited environment for this subtree.
        var child_context = context.*;
        child_context.opacity = context.opacity * view.modifiers.opacity;
        if (view.modifiers.disabled) child_context.disabled = true;
        if (view.modifiers.foreground) |foreground| child_context.foreground = foreground;
        // The tint is this view's own `.foreground()`, never an ancestor's, so
        // a color set on a pane or a row leaves its plain buttons as they are.
        child_context.tint = view.modifiers.foreground;
        child_context.applyFontModifiers(view);
        child_context.applyEnvironment(view);
        // A form's label column, for content laid out again as it paints (a
        // scroll view's), which lowering's own context never reaches.
        if (view.modifiers.form_columns) child_context.form_label_width = mod.ViewLowering.widestFormLabel(&child_context, view);
        // An accessibility-hidden view drops itself and its whole subtree from the
        // a11y tree by clearing the sink for this branch.
        if (view.modifiers.a11y_hidden) child_context.a11y = null;
        if (view.modifiers.hover_scope) child_context.in_hover_scope = if (context.hover_point) |point| outer.contains(point) else false;

        const opacity = child_context.opacity;

        // Liquid Glass surface (behind any background fill): a capsule unless the
        // view set an explicit corner radius. Themes without a glass identity fall
        // back to a translucent track fill with a hairline ring.
        if (view.modifiers.glass_effect) {
            const glass_radius = if (view.modifiers.corner_radius > 0) view.modifiers.corner_radius else outer.height / 2;
            const surface = child_context.surface(display_list);
            if (child_context.theme.painter.glass_surface) |glass_surface| {
                try glass_surface(surface, outer, glass_radius);
            } else {
                try surface.fill(outer, glass_radius, child_context.theme.colors.control_track);
                try surface.stroke(outer, glass_radius, child_context.theme.metrics.hairline, child_context.theme.colors.control_border);
            }
        }

        // Background fill (behind content, spanning the padded frame).
        if (view.modifiers.background) |fill| try Self.paintFill(display_list, outer, child_context.theme.metrics.radius(view.modifiers.corner_radius), fill, opacity, &child_context.theme.colors);

        // Hover highlight: painted over the background while the cursor is inside
        // this view (and it isn't disabled). Cheap point-in-rect test per frame.
        if (view.modifiers.hover_fill) |hover_color| {
            if (!child_context.disabled) {
                if (context.hover_point) |point| {
                    if (outer.contains(point))
                        try Self.paintFill(display_list, outer, child_context.theme.metrics.radius(view.modifiers.corner_radius), .{ .color = hover_color }, opacity, &child_context.theme.colors);
                }
            }
        }

        // Descend through the layout wrappers introduced by padding/frame.
        var content_layout = layout;
        if (view.modifiers.fixed_width) content_layout = content_layout.children[0];
        if (view.modifiers.frame != null) content_layout = content_layout.children[0];
        if (view.modifiers.padding != null) content_layout = content_layout.children[0];
        // A form label's column frame, innermost (`ViewLowering.buildNode`).
        if (view.modifiers.form_label) content_layout = content_layout.children[0];

        // The view's own tap region goes in BEFORE its content: regions are tested
        // last-registered first, so a button inside a tappable row must win.
        if (view.modifiers.on_secondary) |callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .secondary = callback }, .disabled = child_context.disabled, .pointer_style = view.modifiers.pointer_style });
        }
        if (view.modifiers.on_tap) |callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .callback = callback }, .disabled = child_context.disabled, .id = view.modifiers.id, .pointer_style = view.modifiers.pointer_style });
        }
        if (view.modifiers.on_drag) |drag_callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .drag = drag_callback }, .disabled = child_context.disabled, .pointer_style = view.modifiers.pointer_style });
        }
        // The hover hint: the innermost hinted view under the pointer, and on screen, offers its text.
        if (view.modifiers.help.len > 0) if (context.hover_point) |point| {
            const on_screen = if (context.visible) |visible| visible.contains(point) else true;
            if (on_screen and outer.contains(point)) mod.HelpTip.shared().offer(view.modifiers.help, outer);
        };
        if (view.modifiers.on_hover) |hover_callback| if (context.hover_regions) |list| {
            try list.append(context.arena, .{ .rect = outer, .callback = hover_callback, .disabled = child_context.disabled });
        };
        if (view.modifiers.popover_passthrough) if (context.passthrough) |list| try list.append(context.arena, outer);
        if (view.modifiers.modal_passthrough) if (context.modal_passthrough) |list| try list.append(context.arena, outer);

        // `.clipped()`: content (not the background or border) is cut to the
        // frame, anything wholly outside it skips painting, and its input regions
        // are cut to the frame too.
        const marks = context.markInput();
        if (view.modifiers.clipped) {
            try display_list.pushClip(outer, view.modifiers.corner_radius);
            child_context.visible = if (context.visible) |visible| (visible.intersection(outer) orelse renderer.Rect{}) else outer;
        }
        try Self.paintContent(&child_context, view, content_layout, display_list);
        if (view.modifiers.clipped) {
            try display_list.popClip();
            context.clipInput(marks, outer);
        }

        // Border (in front of content).
        if (view.modifiers.border_color) |border_color| {
            if (child_context.theme.metrics.chiseled) {
                try child_context.surface(display_list).bevel(outer, false);
            } else try display_list.strokeRoundedRect(outer, view.modifiers.corner_radius, view.modifiers.border_width, border_color.multiplyAlpha(opacity));
        }

        // A presented overlay is not drawn inline — it is enqueued for the drain
        // pass in `ViewRenderer.render`, anchored to this view's frame. A view can
        // carry several (e.g. both `.sheet` and `.alert`); each is enqueued when its
        // binding is on.
        if (context.overlays) |overlays| {
            for (view.modifiers.overlay) |overlay| {
                if (overlay.presented.get()) {
                    try overlays.append(context.arena, .{
                        .content = overlay.content.*,
                        .style = overlay.style,
                        .anchor = outer,
                        .dismiss = overlay.presented,
                    });
                }
            }
        }
    }

    /// Paints a view's content (its modifiers already applied).
    ///
    /// - `context`: the context, the view's environment applied.
    /// - `view`: the view.
    /// - `content_layout`: its content's arranged frames.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintContent(context: *const mod.Context, view: mod.View, content_layout: renderer.LayoutResult, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const opacity = context.opacity;
        const rect = content_layout.frame;
        switch (view.kind) {
            .empty, .spacer => {},
            .divider, .verticalDivider => try display_list.fillRect(rect, context.theme.colors.separator.multiplyAlpha(opacity)),
            .text => |text| {
                const pixel_size = context.resolvedFontSize(view);
                const string = if (view.modifiers.truncate) try context.truncateToWidth(text.string, pixel_size, rect.width) else text.string;
                context.drawText(display_list, string, pixel_size, context.foreground.multiplyAlpha(opacity), rect.origin()) catch |err| log.debug("text not drawn [{t}]", .{err});
                // Accessibility always exposes the full, untruncated string.
                try context.emitAccessibility(view, rect, .staticText, text.string, "");
            },
            .richText => |rich| mod.TextViewPainter.paintRichText(context, view, rich, rect, display_list) catch |err| log.debug("rich text not drawn [{t}]", .{err}),
            .wrappedText => |wrapped| {
                mod.TextViewPainter.paintWrappedText(context, view, wrapped, rect, display_list) catch |err| log.debug("wrapped text not drawn [{t}]", .{err});
                try context.emitAccessibility(view, rect, .staticText, wrapped.string, "");
            },
            .shape => |shape| try Self.paintShape(context, shape, rect, opacity, display_list),
            .canvas => |drawn| {
                var graphics = mod.GraphicsContext{ .context = context, .display_list = display_list };
                try drawn.draw(drawn.context, &graphics, rect);
            },
            .button => |button| {
                try mod.ControlPainter.paintButton(context, button, rect, display_list);
                try context.emitAccessibility(view, rect, .button, button.label, "");
            },
            .toggle => |toggle| {
                try mod.ControlPainter.paintToggle(context, toggle, rect, display_list);
                try context.emitAccessibility(view, rect, .toggle, toggle.label, if (toggle.value.get()) "on" else "off");
            },
            .slider => |slider| {
                try mod.ControlPainter.paintSlider(context, slider, rect, display_list);
                // The value is formatted only for an accessibility pass, not every paint.
                if (context.a11y != null) {
                    const value = try context.arena.print("{d:.2}", .{slider.value.get()});
                    try context.emitAccessibility(view, rect, .slider, "", value);
                }
            },
            .stepper => |stepper| try mod.ControlPainter.paintStepper(context, stepper, rect, display_list),
            .progress => |progress| try mod.ControlPainter.paintProgress(context, progress, rect, display_list),
            .image => |image| {
                const target = if (view.modifiers.scaled_to_fit) rect.aspectFit(image.image.width, image.image.height) else rect;
                try display_list.drawImage(target, image.image);
                try context.emitAccessibility(view, rect, .image, "", "");
            },
            .icon => |icon| {
                try mod.ControlPainter.paintIcon(context, icon, rect, display_list);
                try context.emitAccessibility(view, rect, .image, "", "");
            },
            .iconButton => |icon_button| {
                try mod.ControlPainter.paintIconButton(context, icon_button, rect, display_list);
                try context.emitAccessibility(view, rect, .button, "", "");
            },
            .label => |label| {
                try mod.ControlPainter.paintLabel(context, label, view, rect, display_list);
                try context.emitAccessibility(view, rect, .staticText, label.title, "");
            },
            .scroll => |scroll| try Self.paintScroll(context, scroll, rect, display_list),
            .scrollState => |scroll| try Self.paintScrollState(context, scroll, rect, display_list),
            .geometry => |geometry| try Self.paintGeometry(context, geometry, rect, display_list),
            .videoPlayer => |video| try Self.paintVideoPlayer(context, view, video, rect, display_list),
            .nativeView => |native| try Self.paintNativeView(context, view, native, rect, display_list),
            .sceneView => |scene_view| try Self.paintSceneView(context, view, scene_view, rect, display_list),
            .textField => |field| {
                try mod.TextViewPainter.paintTextField(context, view, field, rect, display_list);
                // The buffer is copied only for an accessibility pass, not every paint.
                if (context.a11y != null) {
                    // A secure field's value is never exposed.
                    const value = if (field.state.secure) "" else try context.arena.dupe(u8, field.state.text());
                    try context.emitAccessibility(view, rect, .textField, field.placeholder, value);
                }
            },
            .textEditor => |editor| {
                try mod.TextViewPainter.paintTextEditor(context, view, editor, rect, display_list);
                if (context.a11y != null) {
                    const value = try context.arena.dupe(u8, editor.state.text());
                    try context.emitAccessibility(view, rect, .textField, "", value);
                }
            },
            .picker => |picker| switch (context.resolvedPickerStyle()) {
                .menu => try mod.ControlPainter.paintMenuPicker(context, picker, rect, display_list),
                else => try mod.ControlPainter.paintPicker(context, picker, rect, display_list),
            },
            .stack => |stack| {
                for (stack.children, 0..) |child, index| {
                    try Self.paint(context, child, content_layout.children[index], display_list);
                }
            },
            .group => |group| {
                for (group, 0..) |child, index| {
                    try Self.paint(context, child, content_layout.children[index], display_list);
                }
            },
        }
    }

    /// Fills a rounded rect with a color, a gradient or a material.
    ///
    /// - `display_list`: where it is painted.
    /// - `rect`: the rect.
    /// - `radius`: its corner radius.
    /// - `fill`: what fills it.
    /// - `opacity`: the inherited opacity.
    /// - `palette`: the theme's colors (a material's glass tint).
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintFill(display_list: *renderer.DisplayList, rect: renderer.Rect, radius: f32, fill: mod.Fill, opacity: f32, palette: *const renderer.Palette) !void {
        switch (fill) {
            .color => |color| try display_list.fillRoundedRect(rect, radius, color.multiplyAlpha(opacity)),
            .linearGradient => |gradient| {
                // gradient.start/end are unit points (0..1); resolve to the rect.
                const start = renderer.Point{ .x = rect.x + gradient.start.x * rect.width, .y = rect.y + gradient.start.y * rect.height };
                const end = renderer.Point{ .x = rect.x + gradient.end.x * rect.width, .y = rect.y + gradient.end.y * rect.height };
                try display_list.push(.{ .linearGradient = .{
                    .rect = rect,
                    .radius = radius,
                    .start = start,
                    .end = end,
                    .start_color = gradient.start_color.multiplyAlpha(opacity),
                    .end_color = gradient.end_color.multiplyAlpha(opacity),
                } });
            },
            .material => |material| {
                const specification = material.specification();
                // The frost tint comes from the active theme's (scheme-correct) glass
                // role, scaled per material level.
                const tint = palette.glass.multiplyAlpha(specification.alpha_scale);
                try display_list.blurRect(rect, radius, specification.sigma, tint.multiplyAlpha(opacity));
            },
        }
    }

    /// Paints a filled shape.
    ///
    /// - `context`: the context.
    /// - `shape`: the shape.
    /// - `rect`: its frame.
    /// - `opacity`: the inherited opacity.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintShape(context: *const mod.Context, shape: mod.ShapeData, rect: renderer.Rect, opacity: f32, display_list: *renderer.DisplayList) !void {
        const palette = &context.theme.colors;
        switch (shape.shape) {
            .rect => try Self.paintFill(display_list, rect, 0, shape.fill, opacity, palette),
            .roundedRect => try Self.paintFill(display_list, rect, context.theme.metrics.radius(shape.corner_radius), shape.fill, opacity, palette),
            .capsule => try Self.paintFill(display_list, rect, @min(rect.width, rect.height) / 2, shape.fill, opacity, palette),
            .ellipse => try Self.paintFill(display_list, rect, @min(rect.width, rect.height) / 2, shape.fill, opacity, palette),
            .circle => {
                const radius = @min(rect.width, rect.height) / 2;
                const square = renderer.Rect{ .x = rect.midX() - radius, .y = rect.midY() - radius, .width = 2 * radius, .height = 2 * radius };
                try Self.paintFill(display_list, square, radius, shape.fill, opacity, palette);
            },
        }
    }

    /// Paints a fixed-offset scroll view: its content, clipped.
    ///
    /// - `context`: the context.
    /// - `scroll`: the scroll view.
    /// - `rect`: its viewport.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintScroll(context: *const mod.Context, scroll: mod.ScrollData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        try display_list.pushClip(rect, 0);
        defer display_list.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});
        const content_proposal: renderer.Proposal = if (scroll.axis == .vertical)
            .{ .width = rect.width, .height = null }
        else
            .{ .width = null, .height = rect.height };
        const content_size = try mod.ViewRenderer.measure(context, scroll.content.*, content_proposal);
        const content_rect = if (scroll.axis == .vertical)
            renderer.Rect{ .x = rect.x, .y = rect.y - scroll.offset, .width = rect.width, .height = content_size.height }
        else
            renderer.Rect{ .x = rect.x - scroll.offset, .y = rect.y, .width = content_size.width, .height = rect.height };
        // renderInto (not render): overlays are drained once, by the top-level render.
        const marks = context.markInput();
        try mod.ViewRenderer.renderInto(context, scroll.content.*, content_rect, display_list);
        context.clipInput(marks, rect);
    }

    /// Paints a `ScrollViewState`: a vertical viewport scrolled by the app-owned
    /// `state.offset`. Writes back the measured content/viewport heights, clamps
    /// the offset, draws the clipped content, and (when the sink is set) registers
    /// a `ScrollRegion` for wheel routing. A `ScrollViewStateBoth` measures the
    /// content at its own width and does the same across, with `offset_x`.
    ///
    /// - `context`: the context.
    /// - `scroll`: the scroll view.
    /// - `rect`: its viewport.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintScrollState(context: *const mod.Context, scroll: mod.ScrollStateData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        try display_list.pushClip(rect, 0);
        defer display_list.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});
        // Lower once: measuring and arranging the same nodes lets the frame's
        // measure memo serve both.
        const node = try mod.ViewLowering.buildNode(context, scroll.content.*);
        const content_size = renderer.LayoutEngine.shared().measure(node, .{ .width = if (scroll.horizontal) null else rect.width, .height = null });
        // Record geometry so maxOffset()/atBottom() are accurate, then clamp.
        const state = scroll.state;
        state.content_height = content_size.height;
        state.viewport_height = rect.height;
        state.offset = std.math.clamp(state.offset, 0, state.maxOffset());
        var content_rect = renderer.Rect{ .x = rect.x, .y = rect.y - state.offset, .width = rect.width, .height = content_size.height };
        if (scroll.horizontal) {
            // At least the viewport's width, so rows that fill their width still do.
            state.content_width = @max(content_size.width, rect.width);
            state.viewport_width = rect.width;
            state.offset_x = std.math.clamp(state.offset_x, 0, state.maxOffsetX());
            content_rect.x = rect.x - state.offset_x;
            content_rect.width = state.content_width;
        }
        // Paint (not render): overlays are drained once, by the top-level render.
        var inner = context.*;
        inner.visible = if (context.visible) |visible| (visible.intersection(rect) orelse renderer.Rect{}) else rect;
        const marks = context.markInput();
        try Self.paint(&inner, scroll.content.*, try renderer.LayoutEngine.shared().arrange(context.arena, node, content_rect), display_list);
        context.clipInput(marks, rect);
        if (context.scroll_regions) |regions| {
            try regions.append(context.arena, .{ .rect = rect, .state = state, .horizontal = scroll.horizontal, .vertical_target = scroll.vertical_target });
        }
        state.viewport_y = rect.y;
        state.viewport_x = rect.x;
        // The scrollbar's strip takes clicks over the content's edge: press to grab
        // (or jump to) the thumb, then drag it. A hidden bar has no strip, so
        // nothing unseen takes the content's taps there.
        const bars = context.scroll_indicators.draws();
        if (bars and state.maxOffset() > 0.5) try context.hit_regions.append(context.arena, .{
            .rect = mod.Scrollbar.strip(rect),
            .action = .{ .callback = .{ .context = state, .function = mod.Scrollbar.press } },
            .disabled = false,
        });
        // The horizontal bar's strip along the bottom, registered after the
        // vertical one so it takes the corner the two share.
        if (bars and scroll.horizontal and state.maxOffsetX() > 0.5) try context.hit_regions.append(context.arena, .{
            .rect = mod.Scrollbar.stripHorizontal(rect),
            .action = .{ .callback = .{ .context = state, .function = mod.Scrollbar.pressHorizontal } },
            .disabled = false,
        });
        try mod.Scrollbar.paint(context, state, rect, display_list);
        if (scroll.horizontal) try mod.Scrollbar.paintHorizontal(context, state, rect, display_list);
    }

    /// Builds a `GeometryReader`'s content for `rect`'s size, then lays it out and
    /// paints it there. Building needs an arena after the frame's build has ended,
    /// so the frame arena stands in for the build arena while the content builds.
    ///
    /// - `context`: the context.
    /// - `geometry`: the reader.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintGeometry(context: *const mod.Context, geometry: mod.GeometryData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const scope = mod.BuildScope.shared();
        const saved = scope.swapAllocator(context.arena);
        defer _ = scope.swapAllocator(saved);
        const content = geometry.build(geometry.context, rect.size());
        const node = try mod.ViewLowering.buildNode(context, content);
        try Self.paint(context, content, try renderer.LayoutEngine.shared().arrange(context.arena, node, rect), display_list);
    }

    /// Paints a `VideoPlayer`. Where the runtime collects video regions it
    /// erases the frame, so the platform player's picture behind the window's
    /// surface shows through and views painted later draw over it, and
    /// registers the frame; where the platform hands its frames over
    /// (`Player.currentFrame`) it draws the latest, aspect-fit on black;
    /// elsewhere it fills it black with a video glyph.
    /// While the player plays or waits it asks for frames, so labels drawn
    /// from `Player.observe` keep up with it.
    ///
    /// - `context`: the context.
    /// - `view`: the view (its corner radius).
    /// - `video`: the player shown.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintVideoPlayer(context: *const mod.Context, view: mod.View, video: mod.VideoPlayerData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const radius = view.modifiers.corner_radius;
        if (context.video_regions) |regions| {
            try display_list.eraseRect(rect, radius);
            const visible = if (context.visible) |shown| (shown.intersection(rect) orelse renderer.Rect{}) else rect;
            try regions.append(context.arena, .{ .player = video.player, .rect = rect, .visible = visible, .corner_radius = radius });
        } else if (video.player.currentFrame()) |picture| {
            // The platform hands its frames over: drawn here, in the surface,
            // so what is stacked over the player still draws on top.
            try display_list.fillRoundedRect(rect, radius, renderer.Color.black.multiplyAlpha(context.opacity));
            try display_list.pushClip(rect, radius);
            try display_list.drawVideoFrame(rect.aspectFit(picture.image.width, picture.image.height), picture.image, @intFromPtr(video.player), picture.generation);
            try display_list.popClip();
        } else {
            try display_list.fillRoundedRect(rect, radius, renderer.Color.black.multiplyAlpha(context.opacity));
            const side = @min(32, @min(rect.width, rect.height));
            const glyph = renderer.Rect{ .x = rect.midX() - side / 2, .y = rect.midY() - side / 2, .width = side, .height = side };
            try mod.ControlPainter.paintIcon(context, .{ .icon = .video, .size = side, .color = renderer.Color.white.withAlpha(0.35) }, glyph, display_list);
        }
        // The frame's sample: the app's own `observe` this frame took it.
        const observation = video.player.observe();
        const loading = observation.has_item and observation.status == .unknown;
        if (observation.time_control != .paused or observation.seeking or loading) {
            const clock = mod.FrameClock.shared();
            clock.requestFrameAt(clock.time() + mod.Player.refresh_interval_ms);
        }
        try context.emitAccessibility(view, rect, .image, "Video", "");
    }

    /// Paints a `NativeView`. Where the runtime collects native regions it
    /// registers the frame and paints nothing, since the platform view sits
    /// over the window's surface there; elsewhere, or with no handle, it draws
    /// a placeholder frame with a window glyph.
    ///
    /// - `context`: the context.
    /// - `view`: the view (its corner radius).
    /// - `native`: the platform view shown.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintNativeView(context: *const mod.Context, view: mod.View, native: mod.NativeViewData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const radius = view.modifiers.corner_radius;
        if (context.native_regions) |regions| if (native.handle) |handle| {
            const visible = if (context.visible) |shown| (shown.intersection(rect) orelse renderer.Rect{}) else rect;
            try regions.append(context.arena, .{ .handle = handle, .rect = rect, .visible = visible, .corner_radius = radius });
            return;
        };
        const colors = context.theme.colors;
        try display_list.fillRoundedRect(rect, radius, colors.control_background.multiplyAlpha(context.opacity));
        try display_list.strokeRoundedRect(rect, radius, 1, colors.control_border.multiplyAlpha(context.opacity));
        const side = @min(32, @min(rect.width, rect.height));
        const glyph = renderer.Rect{ .x = rect.midX() - side / 2, .y = rect.midY() - side / 2, .width = side, .height = side };
        try mod.ControlPainter.paintIcon(context, .{ .icon = native.placeholder, .size = side, .color = colors.tertiary_label }, glyph, display_list);
    }

    /// Paints a `SceneView`: its scene's background, then the command the GPU
    /// draws the scene for (its placeholder, the frame and a cube, where it
    /// cannot), after noting in the scene where it drew it, for the camera
    /// gestures; while the scene animates, it asks for the next frame. It
    /// ignores `.opacity()`.
    ///
    /// - `context`: the context.
    /// - `view`: the view (its accessibility identifier).
    /// - `scene_view`: the scene and options.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintSceneView(context: *const mod.Context, view: mod.View, scene_view: mod.SceneViewData, rect: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const visible = if (context.visible) |shown| (shown.intersection(rect) orelse renderer.Rect{}) else rect;
        const stamp = mod.BuildScope.shared().stamp();
        scene_view.scene.viewport = .{
            .rect = .{ rect.x, rect.y, rect.width, rect.height },
            .visible = .{ visible.x, visible.y, visible.width, visible.height },
            .frame_number = stamp.number,
            .popover_window = stamp.popover_window,
            .camera_control = scene_view.options.allows_camera_control,
        };
        // `.opacity()` is not applied: the 3D content could only fade as a whole
        // through an offscreen layer, so the background and placeholder do not
        // fade either (a node fades with `SceneNode.opacity`).
        const colors = context.theme.colors;
        if (scene_view.scene.background) |background| try display_list.fillRect(rect, background);
        // The cube's ink laid over the ground first, so its edges, meeting, blend once.
        const ground = colors.control_background;
        try display_list.drawScene(rect, scene_view.scene, ground, colors.tertiary_label.over(ground));
        if (scene_view.options.animating) {
            const clock = mod.FrameClock.shared();
            clock.requestFrameAt(clock.time() + 16);
        }
        try context.emitAccessibility(view, rect, .image, scene_view.options.label, "");
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
