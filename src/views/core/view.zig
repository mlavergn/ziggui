//! The declarative view: a `Kind` (its content) plus a `Modifiers` bundle
//! (padding, frame, background, foreground, on-tap, …) applied around it via
//! a fluent, chainable API, as in SwiftUI:
//!
//!     VStack(.{
//!         Text("Hello").font(.title).foreground(theme.accent),
//!         Button("Tap", on_tap).padding(8),
//!     })
//!
//! A view tree is lowered to a layout tree (`ViewLowering`), arranged by the
//! renderer's layout engine, then painted by co-walking the views with the
//! layout's frames (`ViewPainter`).

const std = @import("std");
const log = std.log.scoped(.ziggui_view);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The width or height a filling frame asks for.
const infinity = std.math.inf(f32);

/// A node of the view tree.
pub const View = struct {
    const Self = @This();

    /// What the view is.
    kind: mod.Kind,

    /// The modifiers applied around it.
    modifiers: mod.Modifiers = .{},

    /// Pads every side by `amount`.
    ///
    /// - `self`: the view.
    /// - `amount`: the padding, in points.
    /// - Returns: the padded view.
    pub fn padding(self: *const Self, amount: f32) Self {
        var view = self.*;
        view.modifiers.padding = renderer.EdgeInsets.all(amount);
        return view;
    }

    /// Pads each side by its own amount.
    ///
    /// - `self`: the view.
    /// - `insets`: the padding per side.
    /// - Returns: the padded view.
    pub fn paddingInsets(self: *const Self, insets: renderer.EdgeInsets) Self {
        var view = self.*;
        view.modifiers.padding = insets;
        return view;
    }

    /// Fixes the width and height.
    ///
    /// - `self`: the view.
    /// - `width`: the width.
    /// - `height`: the height.
    /// - Returns: the framed view.
    pub fn frame(self: *const Self, width: f32, height: f32) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.width = width;
        frame_specification.height = height;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Fixes the width.
    ///
    /// - `self`: the view.
    /// - `width`: the width.
    /// - Returns: the framed view.
    pub fn frameWidth(self: *const Self, width: f32) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.width = width;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Fixes the height.
    ///
    /// - `self`: the view.
    /// - `height`: the height.
    /// - Returns: the framed view.
    pub fn frameHeight(self: *const Self, height: f32) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.height = height;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Caps the width at `width` (SwiftUI `.frame(maxWidth: width)`): hugs its
    /// content up to `width`, then wraps.
    ///
    /// - `self`: the view.
    /// - `width`: the greatest width.
    /// - Returns: the framed view.
    pub fn frameCap(self: *const Self, width: f32) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.max_width = width;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Floors the width at `width` (SwiftUI `.frame(minWidth: width)`): never
    /// narrower than `width`, wider when its content or the proposal asks. A
    /// sheet or alert counts it in the least width it widens to.
    ///
    /// - `self`: the view.
    /// - `width`: the least width.
    /// - Returns: the framed view.
    pub fn frameMinWidth(self: *const Self, width: f32) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.min_width = width;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Keeps the view at its ideal width whatever it is offered (SwiftUI
    /// `.fixedSize(horizontal: true, vertical: false)`): a `Toggle` beside a
    /// `Spacer` keeps its switch by its label instead of sharing the slack.
    ///
    /// - `self`: the view.
    /// - Returns: the view, fixed at its ideal width.
    pub fn fixedSize(self: *const Self) Self {
        var view = self.*;
        view.modifiers.fixed_width = true;
        return view;
    }

    /// Expands to fill the available width (SwiftUI `.frame(maxWidth: .infinity)`).
    ///
    /// - `self`: the view.
    /// - Returns: the filling view.
    pub fn frameMaxWidth(self: *const Self) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.max_width = infinity;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Expands to fill the available height.
    ///
    /// - `self`: the view.
    /// - Returns: the filling view.
    pub fn frameMaxHeight(self: *const Self) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.max_height = infinity;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Places the child within its frame box at the given alignment (the frame
    /// otherwise centers it). Pair with `frameWidth`/`frameMaxWidth` to leading-
    /// or trailing-align a cell's content.
    ///
    /// - `self`: the view.
    /// - `alignment_in_frame`: where the child sits.
    /// - Returns: the aligned view.
    pub fn frameAlign(self: *const Self, alignment_in_frame: renderer.Alignment) Self {
        var view = self.*;
        var frame_specification = view.modifiers.frame orelse mod.FrameSpecification{};
        frame_specification.alignment = alignment_in_frame;
        view.modifiers.frame = frame_specification;
        return view;
    }

    /// Keeps a `Text` on one line, shrinking it to the width it's offered and
    /// adding a trailing ellipsis when it overflows (SwiftUI `.lineLimit(1)`).
    ///
    /// - `self`: the view.
    /// - Returns: the truncating view.
    pub fn truncated(self: *const Self) Self {
        var view = self.*;
        view.modifiers.truncate = true;
        return view;
    }

    /// Lets an `Image` scale to fill the frame it's given (pair with
    /// `frameMaxWidth`/`frameMaxHeight`), preserving aspect ratio and centering —
    /// instead of rendering at fixed native pixels and overflowing.
    ///
    /// - `self`: the view.
    /// - Returns: the scaling view.
    pub fn scaledToFit(self: *const Self) Self {
        var view = self.*;
        view.modifiers.scaled_to_fit = true;
        return view;
    }

    /// Word-wraps a `TextEditor` to its width (prose/prompt input). No effect on
    /// other views or on an editor with line numbers.
    ///
    /// - `self`: the view.
    /// - Returns: the wrapping view.
    pub fn softWrap(self: *const Self) Self {
        var view = self.*;
        view.modifiers.soft_wrap = true;
        return view;
    }

    /// Paints a color behind the view.
    ///
    /// - `self`: the view.
    /// - `color`: the background color.
    /// - Returns: the view with a background.
    pub fn background(self: *const Self, color: renderer.Color) Self {
        var view = self.*;
        view.modifiers.background = .{ .color = color };
        return view;
    }

    /// Paints a fill (color, gradient, material) behind the view.
    ///
    /// - `self`: the view.
    /// - `fill`: the background fill.
    /// - Returns: the view with a background.
    pub fn backgroundFill(self: *const Self, fill: mod.Fill) Self {
        var view = self.*;
        view.modifiers.background = fill;
        return view;
    }

    /// Uses a frosted `Material` (vibrancy) as the background — it blurs and tints
    /// whatever is drawn beneath this view.
    ///
    /// - `self`: the view.
    /// - `material`: the frost level.
    /// - Returns: the view with a material background.
    pub fn backgroundMaterial(self: *const Self, material: mod.Material) Self {
        var view = self.*;
        view.modifiers.background = .{ .material = material };
        return view;
    }

    /// Sets the text and glyph color the subtree inherits.
    ///
    /// - `self`: the view.
    /// - `color`: the foreground color.
    /// - Returns: the tinted view.
    pub fn foreground(self: *const Self, color: renderer.Color) Self {
        var view = self.*;
        view.modifiers.foreground = color;
        return view;
    }

    /// Sets the text style the subtree inherits.
    ///
    /// - `self`: the view.
    /// - `token`: the named style.
    /// - Returns: the styled view.
    pub fn font(self: *const Self, token: mod.FontToken) Self {
        var view = self.*;
        view.modifiers.font = token;
        return view;
    }

    /// Overrides the text weight.
    ///
    /// - `self`: the view.
    /// - `font_weight`: the weight.
    /// - Returns: the styled view.
    pub fn weight(self: *const Self, font_weight: renderer.FontWeight) Self {
        var view = self.*;
        view.modifiers.weight = font_weight;
        return view;
    }

    /// Italic text.
    ///
    /// - `self`: the view.
    /// - Returns: the styled view.
    pub fn italic(self: *const Self) Self {
        var view = self.*;
        view.modifiers.italic = true;
        return view;
    }

    /// Monospace face (JetBrains Mono).
    ///
    /// - `self`: the view.
    /// - Returns: the styled view.
    pub fn mono(self: *const Self) Self {
        var view = self.*;
        view.modifiers.mono = true;
        return view;
    }

    /// Point size override, independent of the font tokens.
    ///
    /// - `self`: the view.
    /// - `pixel_size`: the size, in points.
    /// - Returns: the styled view.
    pub fn size(self: *const Self, pixel_size: f32) Self {
        var view = self.*;
        view.modifiers.size = pixel_size;
        return view;
    }

    /// Rounds the background, border and clip.
    ///
    /// - `self`: the view.
    /// - `radius`: the corner radius.
    /// - Returns: the rounded view.
    pub fn cornerRadius(self: *const Self, radius: f32) Self {
        var view = self.*;
        view.modifiers.corner_radius = radius;
        return view;
    }

    /// Draws the theme's freestanding Liquid Glass surface behind this view
    /// (SwiftUI's `.glassEffect()`): frost + sheen + rim, as a capsule by
    /// default or rounded to `.cornerRadius(r)` when one is set. Use it for
    /// toolbar pill clusters, floating bars, and inset sidebar panels.
    ///
    /// - `self`: the view.
    /// - Returns: the glass-backed view.
    pub fn glassEffect(self: *const Self) Self {
        var view = self.*;
        view.modifiers.glass_effect = true;
        return view;
    }

    /// Draws a border in front of the view.
    ///
    /// - `self`: the view.
    /// - `color`: the border color.
    /// - `width`: the border width.
    /// - Returns: the bordered view.
    pub fn border(self: *const Self, color: renderer.Color, width: f32) Self {
        var view = self.*;
        view.modifiers.border_color = color;
        view.modifiers.border_width = width;
        return view;
    }

    /// A `TextField` that shows bullets instead of its text.
    ///
    /// - `self`: the view.
    /// - Returns: the secure field.
    pub fn secure(self: *const Self) Self {
        var view = self.*;
        view.modifiers.secure = true;
        return view;
    }

    /// The hint a `TextEditor` shows while empty, wrapped and placed exactly
    /// where typed text (and the caret) will start.
    ///
    /// - `self`: the view.
    /// - `hint`: the placeholder text.
    /// - Returns: the editor with a placeholder.
    pub fn placeholder(self: *const Self, hint: []const u8) Self {
        var view = self.*;
        view.modifiers.editor_placeholder = hint;
        return view;
    }

    /// A `TextEditor` or `TextField` without its own field chrome; `inner_padding`
    /// is the editor's inner padding (a field keeps its own).
    ///
    /// - `self`: the view.
    /// - `inner_padding`: the editor's inner padding.
    /// - Returns: the chromeless view.
    pub fn chromeless(self: *const Self, inner_padding: f32) Self {
        var view = self.*;
        view.modifiers.chromeless = true;
        view.modifiers.editor_padding = inner_padding;
        return view;
    }

    /// Lets the text of this rich-text view be selected with the mouse and
    /// copied (⌘C). Selection stays within the one view. The view is told
    /// apart from others by its text and, among views with the same text, by
    /// the order the frame builds them in; see `selectionId` where that order
    /// shifts.
    ///
    /// - `self`: the view.
    /// - Returns: the selectable view.
    pub fn selectable(self: *const Self) Self {
        var view = self.*;
        view.modifiers.selectable = true;
        if (view.kind == .richText) {
            view.modifiers.selection_ordinal = mod.BuildScope.shared().selectionOrdinal(mod.TextSelection.contentHash(view.kind.richText.spans));
        }
        return view;
    }

    /// Gives this selectable view an explicit selection identity, in place of
    /// its text and build order: for a row of a list that builds only the rows
    /// it shows (a `VirtualList`), where identical rows scrolling in and out
    /// would shift that order. Keep `id` the same for the same row across frames.
    ///
    /// - `self`: the view.
    /// - `id`: the identity, distinct among the frame's selectable views.
    /// - Returns: the view.
    pub fn selectionId(self: *const Self, id: u64) Self {
        var view = self.*;
        view.modifiers.selection_id = id;
        return view;
    }

    /// Makes this view a hover scope (see `revealOnHover`).
    ///
    /// - `self`: the view.
    /// - Returns: the hover scope.
    pub fn hoverScope(self: *const Self) Self {
        var view = self.*;
        view.modifiers.hover_scope = true;
        return view;
    }

    /// Draws (and hit-tests) this view only while the cursor is inside the
    /// nearest enclosing `hoverScope` — a row's delete button. Layout space is
    /// always reserved, so revealing never reflows the row.
    ///
    /// - `self`: the view.
    /// - Returns: the revealed-on-hover view.
    pub fn revealOnHover(self: *const Self) Self {
        var view = self.*;
        view.modifiers.reveal_on_hover = true;
        return view;
    }

    /// Sets the subtree's opacity.
    ///
    /// - `self`: the view.
    /// - `amount`: the opacity, 0 to 1.
    /// - Returns: the faded view.
    pub fn opacity(self: *const Self, amount: f32) Self {
        var view = self.*;
        view.modifiers.opacity = amount;
        return view;
    }

    /// Runs `callback` on a primary tap inside this view.
    ///
    /// - `self`: the view.
    /// - `callback`: the tap handler.
    /// - Returns: the tappable view.
    pub fn onTap(self: *const Self, callback: mod.Callback) Self {
        var view = self.*;
        view.modifiers.on_tap = callback;
        return view;
    }

    /// Runs `callback` on a right-click inside this view (a row's context menu).
    ///
    /// - `self`: the view.
    /// - `callback`: the right-click handler.
    /// - Returns: the view.
    pub fn onSecondaryTap(self: *const Self, callback: mod.Callback) Self {
        var view = self.*;
        view.modifiers.on_secondary = callback;
        return view;
    }

    /// Reports pointer movement while the button is held after a press here.
    ///
    /// - `self`: the view.
    /// - `callback`: the drag handler.
    /// - Returns: the draggable view.
    pub fn onDrag(self: *const Self, callback: mod.DragCallback) Self {
        var view = self.*;
        view.modifiers.on_drag = callback;
        return view;
    }

    /// Clips the content to this view's frame (rounded by its `cornerRadius`),
    /// like SwiftUI's `.clipped()`: nothing inside paints past the frame.
    ///
    /// - `self`: the view.
    /// - Returns: the clipped view.
    pub fn clipped(self: *const Self) Self {
        var view = self.*;
        view.modifiers.clipped = true;
        return view;
    }

    /// Paints `color` behind this view only while the cursor hovers it (honoring
    /// the view's `corner_radius`). Pair with `onTap` for menu/list rows.
    ///
    /// - `self`: the view.
    /// - `color`: the hover color.
    /// - Returns: the view.
    pub fn hoverFill(self: *const Self, color: renderer.Color) Self {
        var view = self.*;
        view.modifiers.hover_fill = color;
        return view;
    }

    /// Calls `callback(true)` when the pointer enters this view's frame and
    /// `callback(false)` when it leaves, like SwiftUI's `.onHover`. It fires on
    /// pointer movement only (a view appearing under a still pointer is not
    /// entered), skips a disabled view, and does not see overlays: a popover
    /// over this view does not count as leaving it.
    ///
    /// - `self`: the view.
    /// - `callback`: the hover handler.
    /// - Returns: the view.
    pub fn onHover(self: *const Self, callback: mod.HoverCallback) Self {
        var view = self.*;
        view.modifiers.on_hover = callback;
        return view;
    }

    /// Keeps this view's frame live while a popover is open: the popover's
    /// tap-to-dismiss region leaves it out, so a tap there reaches the view
    /// (and the popover stays up unless the view closes it). A menu bar's
    /// titles use it, so a tap on another title switches menus. Sheets and
    /// alerts are modal and ignore it.
    ///
    /// - `self`: the view.
    /// - Returns: the view.
    pub fn popoverPassthrough(self: *const Self) Self {
        var view = self.*;
        view.modifiers.popover_passthrough = true;
        return view;
    }

    /// Keeps this view's frame live while a sheet or alert is open: the
    /// modal's tap-to-dismiss region leaves it out, so a tap there reaches
    /// the view (the scrim is still drawn over it). Window buttons in a
    /// custom title bar use it, so minimize and close work under a dialog.
    ///
    /// - `self`: the view.
    /// - Returns: the view.
    pub fn modalPassthrough(self: *const Self) Self {
        var view = self.*;
        view.modifiers.modal_passthrough = true;
        return view;
    }

    /// Fires `callback` when this (focused) `TextField` is submitted with Enter.
    ///
    /// - `self`: the view.
    /// - `callback`: the submit handler.
    /// - Returns: the view.
    pub fn onSubmit(self: *const Self, callback: mod.Callback) Self {
        var view = self.*;
        view.modifiers.on_submit = callback;
        return view;
    }

    /// Dims the subtree and stops its input.
    ///
    /// - `self`: the view.
    /// - `is_disabled`: whether it is disabled.
    /// - Returns: the view.
    pub fn disabled(self: *const Self, is_disabled: bool) Self {
        var view = self.*;
        view.modifiers.disabled = is_disabled;
        return view;
    }

    /// Presents `content` as a window-modal sheet while `presented` is true.
    ///
    /// - `self`: the presenting view.
    /// - `presented`: whether the sheet shows.
    /// - `content`: what it shows.
    /// - Returns: the presenting view.
    pub fn sheet(self: *const Self, presented: mod.Binding(bool), content: Self) Self {
        return self.withOverlay(presented, content, .sheet);
    }

    /// Presents `content` as a centered alert dialog while `presented` is true.
    ///
    /// - `self`: the presenting view.
    /// - `presented`: whether the alert shows.
    /// - `content`: what it shows.
    /// - Returns: the presenting view.
    pub fn alert(self: *const Self, presented: mod.Binding(bool), content: Self) Self {
        return self.withOverlay(presented, content, .alert);
    }

    /// Presents `content` as a popover anchored to this view while `presented`.
    ///
    /// - `self`: the anchor.
    /// - `presented`: whether the popover shows.
    /// - `content`: what it shows.
    /// - Returns: the anchor.
    pub fn popover(self: *const Self, presented: mod.Binding(bool), content: Self) Self {
        return self.withOverlay(presented, content, .popover);
    }

    /// Overrides the accessibility label exposed for this view.
    ///
    /// - `self`: the view.
    /// - `label`: the label.
    /// - Returns: the view.
    pub fn accessibilityLabel(self: *const Self, label: []const u8) Self {
        var view = self.*;
        view.modifiers.a11y_label = label;
        return view;
    }

    /// Hides this view and its subtree from the accessibility tree.
    ///
    /// - `self`: the view.
    /// - `hidden`: whether it is hidden.
    /// - Returns: the view.
    pub fn accessibilityHidden(self: *const Self, hidden: bool) Self {
        var view = self.*;
        view.modifiers.a11y_hidden = hidden;
        return view;
    }

    /// Sets a stack's spacing (no-op on non-stacks).
    ///
    /// - `self`: the view.
    /// - `amount`: the space between children.
    /// - Returns: the view.
    pub fn spacing(self: *const Self, amount: f32) Self {
        var view = self.*;
        if (view.kind == .stack) view.kind.stack.spacing = amount;
        return view;
    }

    /// Overrides a stack's cross-axis alignment (default `.center`). For a
    /// `VStack` this controls horizontal alignment of its children, e.g.
    /// `.leading` to left-align them.
    ///
    /// - `self`: the view.
    /// - `cross_alignment`: the alignment.
    /// - Returns: the view.
    pub fn alignment(self: *const Self, cross_alignment: renderer.Alignment) Self {
        var view = self.*;
        if (view.kind == .stack) view.kind.stack.alignment = cross_alignment;
        return view;
    }

    /// Appends an overlay, so `.sheet(...).alert(...)` keeps both.
    ///
    /// - `self`: the presenting view.
    /// - `presented`: whether the overlay shows.
    /// - `content`: what it shows.
    /// - `style`: how it is drawn.
    /// - Returns: the presenting view.
    fn withOverlay(self: *const Self, presented: mod.Binding(bool), content: Self, style: mod.OverlayStyle) Self {
        const scope = mod.BuildScope.shared();
        const boxed = scope.allocator().create(Self) catch @panic("oom");
        boxed.* = content;
        // Append to any overlays already attached so `.sheet(...).alert(...)` keeps
        // both rather than the second clobbering the first.
        const old = self.modifiers.overlay;
        const list = scope.allocator().alloc(mod.OverlayModifier, old.len + 1) catch @panic("oom");
        @memcpy(list[0..old.len], old);
        list[old.len] = .{ .presented = presented, .content = boxed, .style = style };
        var view = self.*;
        view.modifiers.overlay = list;
        return view;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
