//! Lowers a view tree to the renderer's layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_view_lowering);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The width or height a filling leaf may grow to.
const infinity = std.math.inf(f32);

/// The width a measured paragraph wraps to when the proposal leaves it open.
const unbounded_width: f32 = 1_000_000;

/// Measurement state captured for a `WrappedText` when it is lowered to a
/// measured node. Allocated in the frame arena, so the engine can call
/// `measure` during both the measure and arrange passes. The wrap uses the
/// live proposed width.
const WrappedTextMeasure = struct {
    const Self = @This();

    /// The face the text is measured in.
    face: *const renderer.TtfFont,

    /// The frame arena.
    arena: std.mem.Allocator,

    /// The text.
    string: []const u8,

    /// Its size.
    pixel_size: f32,

    /// The text's size wrapped to the proposed width.
    ///
    /// - `pointer`: the `WrappedTextMeasure`.
    /// - `proposal`: the proposed size.
    /// - Returns: the wrapped size.
    fn measure(pointer: *const anyopaque, proposal: renderer.Proposal) renderer.Size {
        const self: *const Self = @ptrCast(@alignCast(pointer));
        const line_height = renderer.TextShaper.init(self.face).lineHeight(self.pixel_size);
        const max_width = proposal.width orelse unbounded_width;
        const lines = mod.BuildScope.shared().wrapText(self.arena, self.face, self.string, self.pixel_size, max_width);
        var width: f32 = 0;
        for (lines) |line| width = @max(width, line.width);
        return .{
            .width = @min(width, max_width),
            .height = @as(f32, @floatFromInt(lines.len)) * line_height,
        };
    }
};

/// Measurement state captured for a `RichText` when it is lowered to a
/// measured node.
const RichTextMeasure = struct {
    const Self = @This();

    /// The frame arena.
    arena: std.mem.Allocator,

    /// The paragraph.
    spans: []const mod.Span,

    /// The faces its spans are drawn in.
    faces: mod.RichFaces,

    /// Its base size.
    pixel_size: f32,

    /// Line height as a multiple of the size.
    line_multiple: f32,

    /// Preformatted (no wrapping).
    preformatted: bool,

    /// The paragraph's size laid out at the proposed width.
    ///
    /// - `pointer`: the `RichTextMeasure`.
    /// - `proposal`: the proposed size.
    /// - Returns: the laid-out size.
    fn measure(pointer: *const anyopaque, proposal: renderer.Proposal) renderer.Size {
        const self: *const Self = @ptrCast(@alignCast(pointer));
        const max_width = proposal.width orelse unbounded_width;
        const laid_out = mod.BuildScope.shared().layoutRich(self.arena, self.spans, self.faces, self.pixel_size, self.line_multiple, max_width, self.preformatted) catch return .{};
        return .{ .width = @min(laid_out.width, max_width), .height = laid_out.height };
    }
};

/// Turns views into layout nodes: each view's content becomes a leaf, stack
/// or measured node, wrapped in padding and frame nodes for its modifiers.
pub const ViewLowering = struct {
    const Self = @This();

    /// The layout node for `view` and its modifiers.
    ///
    /// - `parent_context`: the context the view inherits.
    /// - `view`: the view.
    /// - Returns: the node, in the frame arena; propagates allocation failure.
    pub fn buildNode(parent_context: *const mod.Context, view: mod.View) std.mem.Allocator.Error!renderer.Node {
        var styled = parent_context.*;
        styled.applyFontModifiers(view);
        const context = &styled;
        var node = try Self.buildContentNode(context, view);
        if (view.modifiers.padding) |insets| {
            const child = try context.arena.create(renderer.Node);
            child.* = node;
            node = .{ .padding = .{ .insets = insets, .child = child } };
        }
        if (view.modifiers.frame) |frame| {
            const child = try context.arena.create(renderer.Node);
            child.* = node;
            node = .{ .frame = .{
                .width = frame.width,
                .height = frame.height,
                .min_width = frame.min_width,
                .max_width = frame.max_width,
                .min_height = frame.min_height,
                .max_height = frame.max_height,
                .alignment = frame.alignment,
                .child = child,
            } };
        }
        if (view.modifiers.fixed_width) {
            const child = try context.arena.create(renderer.Node);
            child.* = node;
            node = .{ .frame = .{ .width = renderer.LayoutEngine.shared().measure(child.*, .unspecified).width, .child = child } };
        }
        return node;
    }

    /// The layout node for `view`'s content alone.
    ///
    /// - `context`: the context, the view's font modifiers applied.
    /// - `view`: the view.
    /// - Returns: the node; propagates allocation failure.
    pub fn buildContentNode(context: *const mod.Context, view: mod.View) std.mem.Allocator.Error!renderer.Node {
        switch (view.kind) {
            .empty => return .{ .leaf = renderer.SizingHints.fixedSize(.{}) },
            .spacer => |spacer| return .{ .spacer = .{ .min_length = spacer.min_length } },
            .divider => {
                const hair = context.theme.metrics.hairline;
                return .{ .leaf = .{
                    .min = .{ .width = 0, .height = hair },
                    .ideal = .{ .width = 10, .height = hair },
                    .max = .{ .width = infinity, .height = hair },
                } };
            },
            .verticalDivider => {
                const hair = context.theme.metrics.hairline;
                return .{ .leaf = .{
                    .min = .{ .width = hair, .height = 0 },
                    .ideal = .{ .width = hair, .height = 10 },
                    .max = .{ .width = hair, .height = infinity },
                } };
            },
            .text => |text| {
                const pixel_size = context.resolvedFontSize(view);
                const text_width = renderer.TextShaper.init(context.cache.face).measureLineWidth(text.string, pixel_size);
                const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
                // A truncating Text may shrink below its natural width (down to an
                // ellipsis) so the layout can fit it to a narrow cell; it's painted
                // tail-truncated. A normal Text is rigid at its measured width.
                if (view.modifiers.truncate) {
                    const ellipsis_width = renderer.TextShaper.init(context.cache.face).measureLineWidth("…", pixel_size);
                    return .{ .leaf = .{
                        .min = .{ .width = @min(ellipsis_width, text_width), .height = line_height },
                        .ideal = .{ .width = text_width, .height = line_height },
                        .max = .{ .width = text_width, .height = line_height },
                    } };
                }
                return .{ .leaf = renderer.SizingHints.fixedSize(.{ .width = text_width, .height = line_height }) };
            },
            .wrappedText => |wrapped| {
                const pixel_size = context.resolvedFontSize(view);
                const measure = try context.arena.create(WrappedTextMeasure);
                measure.* = .{ .face = context.cache.face, .arena = context.arena, .string = wrapped.string, .pixel_size = pixel_size };
                return .{ .measured = .{ .context = measure, .measure_fn = WrappedTextMeasure.measure } };
            },
            .richText => |rich| {
                const measure = try context.arena.create(RichTextMeasure);
                measure.* = .{ .arena = context.arena, .spans = rich.spans, .faces = context.richFaces(), .pixel_size = context.resolvedFontSize(view), .line_multiple = rich.line_multiple, .preformatted = rich.preformatted };
                return .{ .measured = .{ .context = measure, .measure_fn = RichTextMeasure.measure } };
            },
            .shape, .drawing => return .{ .leaf = .{
                .min = .{},
                .ideal = .{ .width = 10, .height = 10 },
                .max = .{ .width = infinity, .height = infinity },
            } },
            .button => |button| return .{ .leaf = renderer.SizingHints.fixedSize(Self.buttonSize(context, button)) },
            .toggle => |toggle| {
                const pixel_size = context.theme.typography.body.size;
                const label_width: f32 = if (toggle.label.len > 0) renderer.TextShaper.init(context.cache.face).measureLineWidth(toggle.label, pixel_size) else 0;
                const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
                const gap: f32 = if (toggle.label.len > 0) 8 else 0;
                const height = @max(line_height, mod.ControlMetrics.switch_height);
                return .{ .leaf = .{
                    .min = .{ .width = label_width + gap + mod.ControlMetrics.switch_width, .height = height },
                    .ideal = .{ .width = label_width + gap + mod.ControlMetrics.switch_width, .height = height },
                    .max = .{ .width = infinity, .height = height },
                } };
            },
            .slider => return .{ .leaf = .{
                .min = .{ .width = 60, .height = mod.ControlMetrics.slider_height },
                .ideal = .{ .width = 140, .height = mod.ControlMetrics.slider_height },
                .max = .{ .width = infinity, .height = mod.ControlMetrics.slider_height },
            } },
            .stepper => |stepper| {
                const pixel_size = context.theme.typography.body.size;
                const label_width: f32 = if (stepper.label.len > 0) renderer.TextShaper.init(context.cache.face).measureLineWidth(stepper.label, pixel_size) else 0;
                const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
                const gap: f32 = if (stepper.label.len > 0) 8 else 0;
                const height = @max(line_height, context.theme.metrics.control_height);
                return .{ .leaf = .{
                    .min = .{ .width = label_width + gap + mod.ControlMetrics.stepper_width, .height = height },
                    .ideal = .{ .width = label_width + gap + mod.ControlMetrics.stepper_width, .height = height },
                    .max = .{ .width = infinity, .height = height },
                } };
            },
            .progress => return .{ .leaf = .{
                .min = .{ .width = 60, .height = mod.ControlMetrics.progress_height },
                .ideal = .{ .width = 140, .height = mod.ControlMetrics.progress_height },
                .max = .{ .width = infinity, .height = mod.ControlMetrics.progress_height },
            } },
            .image => |image| {
                const image_width: f32 = @floatFromInt(image.image.width);
                const image_height: f32 = @floatFromInt(image.image.height);
                // A scaled-to-fit image may shrink to 0 or grow to fill whatever frame
                // it's offered (it's drawn aspect-fit). A plain image is rigid at its
                // native pixel size.
                if (view.modifiers.scaled_to_fit) {
                    return .{ .leaf = .{
                        .min = .{},
                        .ideal = .{ .width = image_width, .height = image_height },
                        .max = .{ .width = infinity, .height = infinity },
                    } };
                }
                return .{ .leaf = renderer.SizingHints.fixedSize(.{ .width = image_width, .height = image_height }) };
            },
            .icon => |icon| return .{ .leaf = renderer.SizingHints.fixedSize(.{ .width = icon.size, .height = icon.size }) },
            .iconButton => |icon_button| {
                return .{ .leaf = renderer.SizingHints.fixedSize(.{
                    .width = icon_button.size + 2 * mod.ControlMetrics.icon_button_padding_x,
                    .height = icon_button.size + 2 * mod.ControlMetrics.icon_button_padding_y,
                }) };
            },
            .label => |label| {
                const pixel_size = context.resolvedFontSize(view);
                const text_width = renderer.TextShaper.init(context.cache.face).measureLineWidth(label.title, pixel_size);
                const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
                return .{ .leaf = renderer.SizingHints.fixedSize(.{
                    .width = mod.ControlMetrics.label_icon_size + mod.ControlMetrics.label_gap + text_width,
                    .height = @max(line_height, mod.ControlMetrics.label_icon_size),
                }) };
            },
            .scroll, .scrollState, .geometry => return .{ .leaf = .{
                .min = .{},
                .ideal = .{ .width = 200, .height = 200 },
                .max = .{ .width = infinity, .height = infinity },
            } },
            .textField => return .{ .leaf = .{
                .min = .{ .width = 80, .height = context.theme.metrics.control_height },
                .ideal = .{ .width = 180, .height = context.theme.metrics.control_height },
                .max = .{ .width = infinity, .height = context.theme.metrics.control_height },
            } },
            // The editor fills the space it is offered (the gutter/scroll live inside).
            // At least one line plus its padding, so a frame can make a
            // single-line editor (a composer) exactly as tall as it asks.
            .textEditor => return .{ .leaf = .{
                .min = .{ .width = 120, .height = renderer.TextShaper.init(context.cache.face).lineHeight(context.resolvedFontSize(view)) + 2 * (view.modifiers.editor_padding orelse 8) },
                .ideal = .{ .width = 360, .height = 220 },
                .max = .{ .width = infinity, .height = infinity },
            } },
            .picker => |picker| {
                const pixel_size = context.theme.typography.body.size;
                var width: f32 = 0;
                // Per-segment horizontal padding (each side gets half) so labels have
                // breathing room and don't crowd the segment dividers.
                for (picker.options) |option| width += renderer.TextShaper.init(context.cache.face).measureLineWidth(option, pixel_size) + 40;
                const height = context.theme.metrics.control_height;
                return .{ .leaf = .{
                    .min = .{ .width = width, .height = height },
                    .ideal = .{ .width = width, .height = height },
                    .max = .{ .width = infinity, .height = height },
                } };
            },
            .stack => |stack| {
                const nodes = try context.arena.alloc(renderer.Node, stack.children.len);
                for (stack.children, 0..) |child, index| nodes[index] = try Self.buildNode(context, child);
                return .{ .stack = .{
                    .direction = stack.direction,
                    .spacing = stack.spacing,
                    .alignment = stack.alignment,
                    .children = nodes,
                } };
            },
            .group => |group| {
                // A bare group (not inside a stack) behaves like a VStack.
                const nodes = try context.arena.alloc(renderer.Node, group.len);
                for (group, 0..) |child, index| nodes[index] = try Self.buildNode(context, child);
                return .{ .stack = .{ .direction = .vertical, .spacing = 8, .alignment = .center, .children = nodes } };
            },
        }
    }

    /// A button's size: its label (and glyph) plus padding, at least a control tall.
    ///
    /// - `context`: the context.
    /// - `button`: the button.
    /// - Returns: the size.
    pub fn buttonSize(context: *const mod.Context, button: mod.ButtonData) renderer.Size {
        const pixel_size = context.theme.typography.body.size;
        const label_width = renderer.TextShaper.init(context.cache.face).measureLineWidth(button.label, pixel_size);
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        const icon_width: f32 = if (button.icon != null) mod.ControlMetrics.button_icon_size + mod.ControlMetrics.button_icon_gap else 0;
        return .{
            .width = icon_width + label_width + 2 * mod.ControlMetrics.control_horizontal_padding,
            .height = @max(line_height, context.theme.metrics.control_height),
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
