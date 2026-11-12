//! The modifiers a `View` carries around its content: padding, frame,
//! background, foreground, font, input handlers, overlays.

const std = @import("std");
const log = std.log.scoped(.ziggui_modifiers);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A `.sheet`/`.alert`/`.popover` modifier: present `content` over everything
/// while `presented` is true. `content` is heap-stored in the build arena.
pub const OverlayModifier = struct {
    const Self = @This();

    /// Whether the overlay shows; a tap outside it sets this false.
    presented: mod.Binding(bool),

    /// What the overlay shows.
    content: *const mod.View,

    /// How it is drawn.
    style: mod.OverlayStyle,
};

/// The modifiers applied around a view's content.
pub const Modifiers = struct {
    const Self = @This();

    /// Space around the content.
    padding: ?renderer.EdgeInsets = null,
    /// Fixed, minimum or maximum sizes.
    frame: ?mod.FrameSpecification = null,
    /// Takes its ideal width whatever it is offered (see `View.fixedSize`).
    fixed_width: bool = false,
    /// What is painted behind the content.
    background: ?mod.Fill = null,
    /// The corner radius of the background, border and clip.
    corner_radius: f32 = 0,
    /// The text and glyph color the subtree inherits.
    foreground: ?renderer.Color = null,
    /// The text style the subtree inherits.
    font: ?mod.FontToken = null,
    /// Overrides the weight a `.font()` token (or the inherited style) implies.
    weight: ?renderer.FontWeight = null,
    /// A point size, overriding the font token's.
    size: ?f32 = null,
    /// Italic text.
    italic: bool = false,
    /// Monospaced text.
    mono: bool = false,
    /// A border drawn in front of the content.
    border_color: ?renderer.Color = null,
    /// The border's width.
    border_width: f32 = 1,
    /// The subtree's opacity.
    opacity: f32 = 1,
    /// Called on a primary tap.
    on_tap: ?mod.Callback = null,
    /// Called as the pointer drags after a press here.
    on_drag: ?mod.DragCallback = null,
    /// Content is clipped to the view's frame (see `View.clipped`).
    clipped: bool = false,
    /// Right-click (see `View.onSecondaryTap`).
    on_secondary: ?mod.Callback = null,
    /// A background painted only while the cursor is within this view's frame
    /// (see `Context.hover_point`). Gives menu rows / list rows a live hover
    /// highlight without per-widget state.
    hover_fill: ?renderer.Color = null,
    /// Told when the pointer enters or leaves this view's frame (see `View.onHover`).
    on_hover: ?mod.HoverCallback = null,
    /// This view's frame stays live while a popover is open: the popover's
    /// tap-to-dismiss region leaves it out (see `View.popoverPassthrough`).
    popover_passthrough: bool = false,
    /// This view's frame stays live while a sheet or alert is open: the
    /// modal's tap-to-dismiss region leaves it out (see `View.modalPassthrough`).
    modal_passthrough: bool = false,
    /// Fired when a focused `TextField` is submitted (Enter). Stashed on the
    /// field's `TextFieldState` during paint; see `Focus.submit`.
    on_submit: ?mod.Callback = null,
    /// The subtree is drawn dimmed and takes no input.
    disabled: bool = false,
    /// Marks this view as a hover scope: descendants with `reveal_on_hover`
    /// paint (and take taps) only while the cursor is inside this view.
    hover_scope: bool = false,
    /// A rich-text view whose text can be drag-selected and copied (see `TextSelection`).
    selectable: bool = false,
    /// Which of the frame's selectable views with the same text this one is,
    /// in build order (see `BuildScope.selectionOrdinal`), so identical
    /// paragraphs select apart.
    selection_ordinal: u32 = 0,
    /// An explicit selection identity (`.selectionId`), in place of the text.
    selection_id: ?u64 = null,
    /// Painted only while the cursor is inside the nearest `hover_scope`.
    reveal_on_hover: bool = false,
    /// A `TextEditor` that draws no field surface of its own (its container
    /// supplies the chrome) and may override its inner padding.
    chromeless: bool = false,
    /// A chromeless `TextEditor`'s inner padding.
    editor_padding: ?f32 = null,
    /// A `TextEditor`'s hint while it is empty, drawn where its text starts.
    editor_placeholder: []const u8 = "",
    /// A `TextField` that shows bullets instead of its text (API keys).
    secure: bool = false,
    /// Overlays presented from this view (sheets/alerts/popovers). A slice so a
    /// view can stack more than one — chaining `.sheet(...).alert(...)` appends
    /// rather than overwriting.
    overlay: []const OverlayModifier = &.{},
    /// Overrides the auto-derived accessibility label for this view.
    a11y_label: ?[]const u8 = null,
    /// Hides this view (and its subtree) from the accessibility tree.
    a11y_hidden: bool = false,
    /// Draw the theme's freestanding Liquid Glass surface behind this view
    /// (SwiftUI's `.glassEffect()`): a capsule by default, or the view's
    /// `corner_radius` when one is set. See `Painter.glass_surface`.
    glass_effect: bool = false,
    /// Single-line text that shrinks to its proposed width and is tail-truncated
    /// with an ellipsis when it doesn't fit (SwiftUI `.lineLimit(1).truncationMode(.tail)`).
    /// Only meaningful on a `Text`. See `.truncated()`.
    truncate: bool = false,
    /// An `Image` that scales to fit its frame, preserving aspect ratio and
    /// centering (letterboxed) — instead of rendering at fixed native pixels.
    /// See `.scaledToFit()`.
    scaled_to_fit: bool = false,
    /// A `TextEditor` that word-wraps long lines to its width (no horizontal
    /// scroll) — for prose/prompt inputs. Ignored when line numbers are on (a
    /// code editor stays non-wrapping). See `.softWrap()`.
    soft_wrap: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
