//! Lays out and paints a view tree, then the overlays it presented: the
//! entry points a frame is rendered through.

const std = @import("std");
const log = std.log.scoped(.ziggui_view_renderer);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Space kept between a popover and the window edge.
const popover_margin: f32 = 8;

/// Measures, renders and HiDPI-renders view trees. Overlay requests a tree
/// collects are drained once, by the top-level `render`.
pub const ViewRenderer = struct {
    const Self = @This();

    /// Scroll position of a popover too tall for the window (see `drawOverlay`).
    var popover_scroll: mod.ScrollState = .{};

    /// The anchor of the popover `popover_scroll` belongs to.
    var popover_anchor: renderer.Rect = .{};

    /// Measures the intrinsic size of a view given a proposal.
    ///
    /// - `context`: the context.
    /// - `view`: the view.
    /// - `proposal`: the proposed size.
    /// - Returns: the size; propagates allocation failure.
    pub fn measure(context: *const mod.Context, view: mod.View, proposal: renderer.Proposal) !renderer.Size {
        const node = try mod.ViewLowering.buildNode(context, view);
        return renderer.LayoutEngine.shared().measure(node, proposal);
    }

    /// Lays out `view` into `rect` and paints it into `canvas`, *collecting*
    /// overlay requests and accessibility nodes into `context`'s sinks but NOT
    /// drawing overlays. This is the recursion-safe entry point: `ScrollView`
    /// content and overlay content call `renderInto` (never `render`) so overlays
    /// are drained exactly once, by the top-level `render`.
    ///
    /// - `context`: the context.
    /// - `view`: the view.
    /// - `rect`: where it is laid out.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn renderInto(context: *const mod.Context, view: mod.View, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const node = try mod.ViewLowering.buildNode(context, view);
        const layout = try renderer.LayoutEngine.shared().arrange(context.arena, node, rect);
        try mod.ViewPainter.paint(context, view, layout, canvas);
    }

    /// The top-level render orchestrator: paints `view` into `rect`, then drains
    /// any overlay requests it produced — each as a full-screen scrim plus its
    /// content positioned by style. Overlay regions are appended last, so the
    /// back-to-front `PointerInput.tap` gives them priority automatically. Hit
    /// regions for tappable elements are appended to `context.hit_regions`.
    ///
    /// - `context`: the context.
    /// - `view`: the root view.
    /// - `rect`: the frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn render(context: *const mod.Context, view: mod.View, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        // Memoize layout measurement for this frame (see `LayoutEngine.beginMeasureCache`).
        const owns_cache = renderer.LayoutEngine.shared().beginMeasureCache();
        defer if (owns_cache) renderer.LayoutEngine.shared().endMeasureCache();
        // Popover dismiss regions leave out `popoverPassthrough` frames: collect
        // them here unless the caller already does.
        var passthrough: std.ArrayList(renderer.Rect) = .empty;
        var modal_passthrough: std.ArrayList(renderer.Rect) = .empty;
        var render_context = context.*;
        if (render_context.passthrough == null) render_context.passthrough = &passthrough;
        if (render_context.modal_passthrough == null) render_context.modal_passthrough = &modal_passthrough;
        try Self.renderInto(&render_context, view, rect, canvas);
        if (render_context.overlays) |overlays| {
            // Index-based loop: overlay content rendered below may enqueue *more*
            // overlays (nesting); appending keeps the list growing and we process
            // each exactly once — no double-drain, no recursion.
            var index: usize = 0;
            while (index < overlays.items.len) : (index += 1) {
                const request = overlays.items[index]; // copy: drawing may reallocate the list
                try Self.drawOverlay(&render_context, request, rect, canvas);
            }
        }
        // The text-field context menu sits above everything, including app overlays.
        try mod.TextContextMenu.shared().draw(&render_context, rect, canvas);
    }

    /// Renders `view` for a HiDPI display: lays out and paints in logical *points*
    /// (so all layout math, theme metrics, and hit regions stay in points), then
    /// uniformly scales the produced command list to device pixels. Glyphs are
    /// rasterized at `point_size * scale` so text is crisp rather than an
    /// upscaled blur.
    ///
    /// Note: `context.hit_regions` are left in point space — `PointerInput.tap`
    /// therefore operates in points, and the app must convert device mouse
    /// coordinates back to points (divide by `scale`) before dispatching.
    ///
    /// - `context`: the context.
    /// - `view`: the root view.
    /// - `point_rect`: the frame, in points.
    /// - `scale`: device pixels per point.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn renderScaled(context: *const mod.Context, view: mod.View, point_rect: renderer.Rect, scale: f32, canvas: *renderer.Canvas) !void {
        var scaled_context = context.*;
        scaled_context.scale = scale;
        const start = canvas.commands.items.len;
        try Self.render(&scaled_context, view, point_rect, canvas);
        if (scale != 1) Self.scaleCommands(canvas.commands.items[start..], scale);
    }

    /// A rect scaled by `factor`.
    ///
    /// - `rect`: the rect.
    /// - `factor`: the scale.
    /// - Returns: the scaled rect.
    fn scaleRect(rect: renderer.Rect, factor: f32) renderer.Rect {
        return .{ .x = rect.x * factor, .y = rect.y * factor, .width = rect.width * factor, .height = rect.height * factor };
    }

    /// A point scaled by `factor`.
    ///
    /// - `point`: the point.
    /// - `factor`: the scale.
    /// - Returns: the scaled point.
    fn scalePoint(point: renderer.Point, factor: f32) renderer.Point {
        return .{ .x = point.x * factor, .y = point.y * factor };
    }

    /// Multiplies every command's geometry (rects/points/radii/widths/blur sigma)
    /// by `factor`. Glyph/image coverage bitmaps are untouched — glyphs were
    /// already rasterized at device resolution, so the scaled quad maps to them 1:1.
    ///
    /// - `commands`: the commands, scaled in place.
    /// - `factor`: the scale.
    fn scaleCommands(commands: []renderer.DrawCommand, factor: f32) void {
        for (commands) |*command| {
            switch (command.*) {
                .fillRoundedRect => |*fill| {
                    fill.rect = Self.scaleRect(fill.rect, factor);
                    fill.radius *= factor;
                },
                .strokeRoundedRect => |*stroke| {
                    stroke.rect = Self.scaleRect(stroke.rect, factor);
                    stroke.radius *= factor;
                    stroke.width *= factor;
                },
                .linearGradient => |*gradient| {
                    gradient.rect = Self.scaleRect(gradient.rect, factor);
                    gradient.radius *= factor;
                    gradient.start = Self.scalePoint(gradient.start, factor);
                    gradient.end = Self.scalePoint(gradient.end, factor);
                },
                .line => |*line| {
                    line.start = Self.scalePoint(line.start, factor);
                    line.end = Self.scalePoint(line.end, factor);
                    line.width *= factor;
                },
                .glyph => |*glyph| glyph.rect = Self.scaleRect(glyph.rect, factor),
                .image => |*image| image.rect = Self.scaleRect(image.rect, factor),
                .blurRect => |*blur| {
                    blur.rect = Self.scaleRect(blur.rect, factor);
                    blur.radius *= factor;
                    blur.sigma *= factor;
                },
                .pushClip => |*clip| {
                    clip.rect = Self.scaleRect(clip.rect, factor);
                    clip.radius *= factor;
                },
                .popClip => {},
            }
        }
    }

    /// Draws one overlay request: a dimming scrim across `root`, a tap-to-dismiss
    /// region, a panel background, then the content positioned by style.
    ///
    /// - `context`: the context.
    /// - `request`: the overlay.
    /// - `root`: the frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn drawOverlay(context: *const mod.Context, request: mod.OverlayRequest, root: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        // 1. Dimming scrim over the whole frame (theme-tinted; native macOS dims
        //    by ~20% black under modals). Popovers are light-dismiss but do NOT
        //    dim the window behind them.
        if (request.style != .popover) {
            try canvas.fillRect(root, context.theme.colors.scrim);
        }
        // 2. Tap-to-dismiss region beneath the content (appended before content's
        //    own regions, so a tap on the content hits the content first). A
        //    popover's leaves out the `popoverPassthrough` frames, a sheet's or
        //    alert's the `modalPassthrough` ones.
        if (request.dismiss) |dismiss| {
            const list = if (request.style == .popover) context.passthrough else context.modal_passthrough;
            const holes: []const renderer.Rect = if (list) |frames| frames.items else &.{};
            try Self.appendDismiss(context, root, holes, dismiss);
        }

        // 3. Measure & position the content. macOS sheets are *centered* window
        //    modals (they don't hug the bottom edge like iOS).
        var proposal: renderer.Proposal = switch (request.style) {
            .sheet => .{ .width = @min(root.width - 160, 480), .height = null },
            .alert => .{ .width = @min(root.width - 80, 320), .height = null },
            .popover => .unspecified,
        };
        // A sheet or alert whose content cannot be narrower than its usual width
        // (a wide segmented `Picker`) widens to it, as far as the window allows,
        // rather than being clipped at both edges.
        const node = try mod.ViewLowering.buildNode(context, request.content);
        if (proposal.width) |usual| {
            const least = renderer.LayoutEngine.shared().minWidth(node);
            if (least > usual) proposal.width = @max(usual, @min(least, root.width - 2 * popover_margin));
        }
        var size = renderer.LayoutEngine.shared().measure(node, proposal);
        // A popover wider than the window is narrowed to fit (its rows truncate),
        // not pushed past the edge.
        const max_width = root.width - 2 * popover_margin;
        if (request.style == .popover and size.width > max_width) size = renderer.LayoutEngine.shared().measure(node, .{ .width = max_width, .height = null });
        const target = switch (request.style) {
            .sheet, .alert => Self.centerRect(root, size),
            .popover => Self.anchoredRect(root, request.anchor, size),
        };

        // 4. Panel frame (theme-drawn), then the content on top, clipped to the
        //    panel so rigid children (e.g. an unwrappable Text) can't paint past
        //    the rounded edge. Modals round more than popovers and use a different
        //    material (opaque vs frosted) on macOS.
        const kind: renderer.PanelKind = switch (request.style) {
            .sheet, .alert => .modal,
            .popover => .popover,
        };
        const radius = switch (kind) {
            .modal => context.theme.metrics.panel_corner_radius,
            .popover => context.theme.metrics.corner_radius,
        };
        try context.theme.painter.panel(context.surface(canvas), target, radius, kind);
        try canvas.pushClip(target, radius);
        if (request.style == .popover and target.height + 0.5 < size.height) {
            // Cut to fit the window: the content scrolls inside the panel. One
            // popover is open at a time; a new anchor starts it at the top.
            if (!std.meta.eql(popover_anchor, request.anchor)) {
                popover_scroll = .{};
                popover_anchor = request.anchor;
            }
            // Painting runs after the build arena is gone: box the content in the frame's.
            const content = try context.arena.create(mod.View);
            content.* = request.content;
            const scroller = mod.View{ .kind = .{ .scrollState = .{ .state = &popover_scroll, .content = content } } };
            try Self.renderInto(context, scroller, target, canvas);
        } else {
            // Lay out the node measured above: building it again would miss the
            // frame's measure memo.
            try mod.ViewPainter.paint(context, request.content, try renderer.LayoutEngine.shared().arrange(context.arena, node, target), canvas);
        }
        try canvas.popClip();
    }

    /// Appends tap-to-dismiss regions covering `area` minus every rect in `holes`:
    /// the first hole that meets `area` splits it into the bands above and below
    /// it and the strips beside it, and each piece goes on with the rest.
    ///
    /// - `context`: the context.
    /// - `area`: what the regions cover.
    /// - `holes`: frames left out.
    /// - `dismiss`: the overlay's binding.
    /// - Returns: nothing; propagates allocation failure.
    fn appendDismiss(context: *const mod.Context, area: renderer.Rect, holes: []const renderer.Rect, dismiss: mod.Binding(bool)) std.mem.Allocator.Error!void {
        if (area.width <= 0 or area.height <= 0) return;
        for (holes, 0..) |hole, index| {
            const cut = area.intersection(hole) orelse continue;
            if (cut.width <= 0 or cut.height <= 0) continue;
            const rest = holes[index + 1 ..];
            try Self.appendDismiss(context, .{ .x = area.x, .y = area.y, .width = area.width, .height = cut.y - area.y }, rest, dismiss);
            try Self.appendDismiss(context, .{ .x = area.x, .y = cut.maxY(), .width = area.width, .height = area.maxY() - cut.maxY() }, rest, dismiss);
            try Self.appendDismiss(context, .{ .x = area.x, .y = cut.y, .width = cut.x - area.x, .height = cut.height }, rest, dismiss);
            try Self.appendDismiss(context, .{ .x = cut.maxX(), .y = cut.y, .width = area.maxX() - cut.maxX(), .height = cut.height }, rest, dismiss);
            return;
        }
        try context.hit_regions.append(context.arena, .{ .rect = area, .action = .{ .dismiss = dismiss }, .disabled = false });
    }

    /// A rect of `size` centered in `root`.
    ///
    /// - `root`: the frame.
    /// - `size`: the size.
    /// - Returns: the centered rect.
    fn centerRect(root: renderer.Rect, size: renderer.Size) renderer.Rect {
        return .{
            .x = root.x + (root.width - size.width) / 2,
            .y = root.y + (root.height - size.height) / 2,
            .width = size.width,
            .height = size.height,
        };
    }

    /// Positions an overlay just below its `anchor`, or above it when it fits
    /// there and not below. When it fits neither side it takes the roomier one and
    /// is cut to the space left (the caller scrolls it): it never covers its anchor
    /// or leaves `root`.
    ///
    /// - `root`: the frame.
    /// - `anchor`: the presenting view's frame.
    /// - `size`: the overlay's size.
    /// - Returns: where it goes.
    fn anchoredRect(root: renderer.Rect, anchor: renderer.Rect, size: renderer.Size) renderer.Rect {
        const gap: f32 = 4;
        const margin = popover_margin;
        var x = anchor.x;
        if (x + size.width > root.maxX() - margin) x = root.maxX() - margin - size.width;
        if (x < root.x + margin) x = root.x + margin;
        const below = root.maxY() - margin - (anchor.maxY() + gap);
        const above = anchor.y - gap - (root.y + margin);
        var height = size.height;
        var y: f32 = undefined;
        if (height <= below) {
            y = anchor.maxY() + gap;
        } else if (height <= above) {
            y = anchor.y - gap - height;
        } else if (below >= above) {
            height = @max(0, below);
            y = anchor.maxY() + gap;
        } else {
            height = @max(0, above);
            y = anchor.y - gap - height;
        }
        return .{ .x = x, .y = y, .width = size.width, .height = height };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "popover: kept inside the window's side margins" {
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 340, .height = 600 };
    const rect = ViewRenderer.anchoredRect(root, .{ .x = 14, .y = 100, .width = 300, .height = 30 }, .{ .width = 324, .height = 100 });
    try std.testing.expectEqual(@as(f32, 8), rect.x);
    try std.testing.expect(rect.maxX() <= 332);
}

test "popover: below when it fits, above when only that fits, else cut to the roomier side" {
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 800, .height = 600 };
    const low = renderer.Rect{ .x = 100, .y = 500, .width = 80, .height = 20 }; // near the bottom
    // Fits below a high anchor.
    try std.testing.expectEqual(@as(f32, 124), ViewRenderer.anchoredRect(root, .{ .x = 100, .y = 100, .width = 80, .height = 20 }, .{ .width = 200, .height = 100 }).y);
    // Flips above a low anchor, ending above it.
    const up = ViewRenderer.anchoredRect(root, low, .{ .width = 200, .height = 300 });
    try std.testing.expectEqual(@as(f32, 496), up.maxY());
    // Too tall for either side: cut to the room above, never over the anchor.
    const cut = ViewRenderer.anchoredRect(root, low, .{ .width = 200, .height = 2000 });
    try std.testing.expect(cut.y >= 8 and cut.maxY() <= 496);
    try std.testing.expectEqual(@as(f32, 488), cut.height);
}
