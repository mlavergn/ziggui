//! Paints a laid-out view tree: co-walks the views with their layout frames,
//! applying modifiers and dispatching each kind to its painter.

const std = @import("std");
const log = std.log.scoped(.ziggui_view_painter);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Paints views into a canvas, registering their input regions, overlay
/// requests and accessibility nodes in the context's sinks.
pub const ViewPainter = struct {
    const Self = @This();

    /// Paints `view` and its subtree into the frames `layout` arranged.
    ///
    /// - `context`: the context the view inherits.
    /// - `view`: the view.
    /// - `layout`: its arranged frames.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paint(context: *const mod.Context, view: mod.View, layout: renderer.LayoutResult, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
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
        child_context.applyFontModifiers(view);
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
            const surface = child_context.surface(canvas);
            if (child_context.theme.painter.glass_surface) |glass_surface| {
                try glass_surface(surface, outer, glass_radius);
            } else {
                try surface.fill(outer, glass_radius, child_context.theme.colors.control_track);
                try surface.stroke(outer, glass_radius, child_context.theme.metrics.hairline, child_context.theme.colors.control_border);
            }
        }

        // Background fill (behind content, spanning the padded frame).
        if (view.modifiers.background) |fill| try Self.paintFill(canvas, outer, child_context.theme.metrics.radius(view.modifiers.corner_radius), fill, opacity, &child_context.theme.colors);

        // Hover highlight: painted over the background while the cursor is inside
        // this view (and it isn't disabled). Cheap point-in-rect test per frame.
        if (view.modifiers.hover_fill) |hover_color| {
            if (!child_context.disabled) {
                if (context.hover_point) |point| {
                    if (outer.contains(point))
                        try Self.paintFill(canvas, outer, child_context.theme.metrics.radius(view.modifiers.corner_radius), .{ .color = hover_color }, opacity, &child_context.theme.colors);
                }
            }
        }

        // Descend through the layout wrappers introduced by padding/frame.
        var content_layout = layout;
        if (view.modifiers.frame != null) content_layout = content_layout.children[0];
        if (view.modifiers.padding != null) content_layout = content_layout.children[0];

        // The view's own tap region goes in BEFORE its content: regions are tested
        // last-registered first, so a button inside a tappable row must win.
        if (view.modifiers.on_secondary) |callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .secondary = callback }, .disabled = child_context.disabled });
        }
        if (view.modifiers.on_tap) |callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .callback = callback }, .disabled = child_context.disabled });
        }
        if (view.modifiers.on_drag) |drag_callback| {
            try context.hit_regions.append(context.arena, .{ .rect = outer, .action = .{ .drag = drag_callback }, .disabled = child_context.disabled });
        }
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
            try canvas.pushClip(outer, view.modifiers.corner_radius);
            child_context.visible = if (context.visible) |visible| (visible.intersection(outer) orelse renderer.Rect{}) else outer;
        }
        try Self.paintContent(&child_context, view, content_layout, canvas);
        if (view.modifiers.clipped) {
            try canvas.popClip();
            context.clipInput(marks, outer);
        }

        // Border (in front of content).
        if (view.modifiers.border_color) |border_color| {
            if (child_context.theme.metrics.chiseled) {
                try child_context.surface(canvas).bevel(outer, false);
            } else try canvas.strokeRoundedRect(outer, view.modifiers.corner_radius, view.modifiers.border_width, border_color.multiplyAlpha(opacity));
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
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintContent(context: *const mod.Context, view: mod.View, content_layout: renderer.LayoutResult, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const opacity = context.opacity;
        const rect = content_layout.frame;
        switch (view.kind) {
            .empty, .spacer => {},
            .divider, .verticalDivider => try canvas.fillRect(rect, context.theme.colors.separator.multiplyAlpha(opacity)),
            .text => |text| {
                const pixel_size = context.resolvedFontSize(view);
                const string = if (view.modifiers.truncate) try context.truncateToWidth(text.string, pixel_size, rect.width) else text.string;
                context.drawText(canvas, string, pixel_size, context.foreground.multiplyAlpha(opacity), rect.origin()) catch |err| log.debug("text not drawn [{t}]", .{err});
                // Accessibility always exposes the full, untruncated string.
                try context.emitAccessibility(view, rect, .staticText, text.string, "");
            },
            .richText => |rich| mod.TextViewPainter.paintRichText(context, view, rich, rect, canvas) catch |err| log.debug("rich text not drawn [{t}]", .{err}),
            .wrappedText => |wrapped| {
                mod.TextViewPainter.paintWrappedText(context, view, wrapped, rect, canvas) catch |err| log.debug("wrapped text not drawn [{t}]", .{err});
                try context.emitAccessibility(view, rect, .staticText, wrapped.string, "");
            },
            .shape => |shape| try Self.paintShape(context, shape, rect, opacity, canvas),
            .drawing => |drawing| {
                var pen = mod.Pen{ .context = context, .canvas = canvas };
                try drawing.draw(drawing.context, &pen, rect);
            },
            .button => |button| {
                try mod.ControlPainter.paintButton(context, button, rect, canvas);
                try context.emitAccessibility(view, rect, .button, button.label, "");
            },
            .toggle => |toggle| {
                try mod.ControlPainter.paintToggle(context, toggle, rect, canvas);
                try context.emitAccessibility(view, rect, .toggle, toggle.label, if (toggle.value.get()) "on" else "off");
            },
            .slider => |slider| {
                try mod.ControlPainter.paintSlider(context, slider, rect, canvas);
                // The value is formatted only for an accessibility pass, not every paint.
                if (context.a11y != null) {
                    const value = try context.arena.print("{d:.2}", .{slider.value.get()});
                    try context.emitAccessibility(view, rect, .slider, "", value);
                }
            },
            .stepper => |stepper| try mod.ControlPainter.paintStepper(context, stepper, rect, canvas),
            .progress => |progress| try mod.ControlPainter.paintProgress(context, progress, rect, canvas),
            .image => |image| {
                const target = if (view.modifiers.scaled_to_fit) Self.aspectFitRect(rect, image.image.width, image.image.height) else rect;
                try canvas.drawImage(target, image.image);
                try context.emitAccessibility(view, rect, .image, "", "");
            },
            .icon => |icon| {
                try mod.ControlPainter.paintIcon(context, icon, rect, canvas);
                try context.emitAccessibility(view, rect, .image, "", "");
            },
            .iconButton => |icon_button| {
                try mod.ControlPainter.paintIconButton(context, icon_button, rect, canvas);
                try context.emitAccessibility(view, rect, .button, "", "");
            },
            .label => |label| {
                try mod.ControlPainter.paintLabel(context, label, view, rect, canvas);
                try context.emitAccessibility(view, rect, .staticText, label.title, "");
            },
            .scroll => |scroll| try Self.paintScroll(context, scroll, rect, canvas),
            .scrollState => |scroll| try Self.paintScrollState(context, scroll, rect, canvas),
            .geometry => |geometry| try Self.paintGeometry(context, geometry, rect, canvas),
            .textField => |field| {
                try mod.TextViewPainter.paintTextField(context, view, field, rect, canvas);
                // The buffer is copied only for an accessibility pass, not every paint.
                if (context.a11y != null) {
                    const value = try context.arena.dupe(u8, field.state.text());
                    try context.emitAccessibility(view, rect, .textField, field.placeholder, value);
                }
            },
            .textEditor => |editor| {
                try mod.TextViewPainter.paintTextEditor(context, view, editor, rect, canvas);
                if (context.a11y != null) {
                    const value = try context.arena.dupe(u8, editor.state.text());
                    try context.emitAccessibility(view, rect, .textField, "", value);
                }
            },
            .picker => |picker| try mod.ControlPainter.paintPicker(context, picker, rect, canvas),
            .stack => |stack| {
                for (stack.children, 0..) |child, index| {
                    try Self.paint(context, child, content_layout.children[index], canvas);
                }
            },
            .group => |group| {
                for (group, 0..) |child, index| {
                    try Self.paint(context, child, content_layout.children[index], canvas);
                }
            },
        }
    }

    /// Fills a rounded rect with a color, a gradient or a material.
    ///
    /// - `canvas`: where it is painted.
    /// - `rect`: the rect.
    /// - `radius`: its corner radius.
    /// - `fill`: what fills it.
    /// - `opacity`: the inherited opacity.
    /// - `palette`: the theme's colors (a material's glass tint).
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintFill(canvas: *renderer.Canvas, rect: renderer.Rect, radius: f32, fill: mod.Fill, opacity: f32, palette: *const renderer.Palette) !void {
        switch (fill) {
            .color => |color| try canvas.fillRoundedRect(rect, radius, color.multiplyAlpha(opacity)),
            .linearGradient => |gradient| {
                // gradient.start/end are unit points (0..1); resolve to the rect.
                const start = renderer.Point{ .x = rect.x + gradient.start.x * rect.width, .y = rect.y + gradient.start.y * rect.height };
                const end = renderer.Point{ .x = rect.x + gradient.end.x * rect.width, .y = rect.y + gradient.end.y * rect.height };
                try canvas.push(.{ .linearGradient = .{
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
                try canvas.blurRect(rect, radius, specification.sigma, tint.multiplyAlpha(opacity));
            },
        }
    }

    /// Paints a filled shape.
    ///
    /// - `context`: the context.
    /// - `shape`: the shape.
    /// - `rect`: its frame.
    /// - `opacity`: the inherited opacity.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintShape(context: *const mod.Context, shape: mod.ShapeData, rect: renderer.Rect, opacity: f32, canvas: *renderer.Canvas) !void {
        const palette = &context.theme.colors;
        switch (shape.shape) {
            .rect => try Self.paintFill(canvas, rect, 0, shape.fill, opacity, palette),
            .roundedRect => try Self.paintFill(canvas, rect, context.theme.metrics.radius(shape.corner_radius), shape.fill, opacity, palette),
            .capsule => try Self.paintFill(canvas, rect, @min(rect.width, rect.height) / 2, shape.fill, opacity, palette),
            .ellipse => try Self.paintFill(canvas, rect, @min(rect.width, rect.height) / 2, shape.fill, opacity, palette),
            .circle => {
                const radius = @min(rect.width, rect.height) / 2;
                const square = renderer.Rect{ .x = rect.midX() - radius, .y = rect.midY() - radius, .width = 2 * radius, .height = 2 * radius };
                try Self.paintFill(canvas, square, radius, shape.fill, opacity, palette);
            },
        }
    }

    /// Paints a fixed-offset scroll view: its content, clipped.
    ///
    /// - `context`: the context.
    /// - `scroll`: the scroll view.
    /// - `rect`: its viewport.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintScroll(context: *const mod.Context, scroll: mod.ScrollData, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        try canvas.pushClip(rect, 0);
        defer canvas.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});
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
        try mod.ViewRenderer.renderInto(context, scroll.content.*, content_rect, canvas);
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
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintScrollState(context: *const mod.Context, scroll: mod.ScrollStateData, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        try canvas.pushClip(rect, 0);
        defer canvas.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});
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
        try Self.paint(&inner, scroll.content.*, try renderer.LayoutEngine.shared().arrange(context.arena, node, content_rect), canvas);
        context.clipInput(marks, rect);
        if (context.scroll_regions) |regions| {
            try regions.append(context.arena, .{ .rect = rect, .state = state, .horizontal = scroll.horizontal });
        }
        state.viewport_y = rect.y;
        state.viewport_x = rect.x;
        // The scrollbar's strip takes clicks over the content's edge: press to grab
        // (or jump to) the thumb, then drag it.
        if (state.maxOffset() > 0.5) try context.hit_regions.append(context.arena, .{
            .rect = mod.Scrollbar.strip(rect),
            .action = .{ .callback = .{ .context = state, .function = mod.Scrollbar.press } },
            .disabled = false,
        });
        // The horizontal bar's strip along the bottom, registered after the
        // vertical one so it takes the corner the two share.
        if (scroll.horizontal and state.maxOffsetX() > 0.5) try context.hit_regions.append(context.arena, .{
            .rect = mod.Scrollbar.stripHorizontal(rect),
            .action = .{ .callback = .{ .context = state, .function = mod.Scrollbar.pressHorizontal } },
            .disabled = false,
        });
        try mod.Scrollbar.paint(context, state, rect, canvas);
        if (scroll.horizontal) try mod.Scrollbar.paintHorizontal(context, state, rect, canvas);
    }

    /// Builds a `GeometryReader`'s content for `rect`'s size, then lays it out and
    /// paints it there. Building needs an arena after the frame's build has ended,
    /// so the frame arena stands in for the build arena while the content builds.
    ///
    /// - `context`: the context.
    /// - `geometry`: the reader.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintGeometry(context: *const mod.Context, geometry: mod.GeometryData, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const scope = mod.BuildScope.shared();
        const saved = scope.swapAllocator(context.arena);
        defer _ = scope.swapAllocator(saved);
        const content = geometry.build(geometry.context, rect.size());
        const node = try mod.ViewLowering.buildNode(context, content);
        try Self.paint(context, content, try renderer.LayoutEngine.shared().arrange(context.arena, node, rect), canvas);
    }

    /// The largest centered sub-rect of `rect` with the image's aspect ratio
    /// (SwiftUI `.scaledToFit()` / `object-fit: contain`).
    ///
    /// - `rect`: the frame.
    /// - `image_width`: the image's width, in pixels.
    /// - `image_height`: its height.
    /// - Returns: where the image is drawn.
    fn aspectFitRect(rect: renderer.Rect, image_width: u32, image_height: u32) renderer.Rect {
        const width_float: f32 = @floatFromInt(image_width);
        const height_float: f32 = @floatFromInt(image_height);
        if (width_float <= 0 or height_float <= 0 or rect.width <= 0 or rect.height <= 0) return rect;
        const scale = @min(rect.width / width_float, rect.height / height_float);
        const width = width_float * scale;
        const height = height_float * scale;
        return .{
            .x = rect.x + (rect.width - width) / 2,
            .y = rect.y + (rect.height - height) / 2,
            .width = width,
            .height = height,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
