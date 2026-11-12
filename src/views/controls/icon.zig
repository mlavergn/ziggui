//! Glyphs from the bundled icon font, plain and tappable.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_icon);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A glyph from the bundled icon set, laid out as a `size`×`size` square and
/// tinted `color` (pass `null` to inherit the surrounding `.foreground`). Call
/// sites lean on enum-literal inference: `Icon(.heart, 18, null)`.
///
/// - `icon`: the glyph.
/// - `size`: the square's side.
/// - `color`: the tint; null inherits the foreground.
/// - Returns: the view.
pub fn Icon(icon: renderer.Icon, size: f32, color: ?renderer.Color) mod.View {
    return .{ .kind = .{ .icon = .{ .icon = icon, .size = size, .color = color } } };
}

/// A tappable icon (toolbar/affordance style): the glyph centered in a square
/// control with a tap callback. The icon inherits the environment foreground;
/// compose `.foreground`/`.padding`/`.background` for styling.
///
/// - `icon`: the glyph.
/// - `size`: the glyph's side.
/// - `on_tap`: what a tap calls.
/// - Returns: the view.
pub fn IconButton(icon: renderer.Icon, size: f32, on_tap: mod.Callback) mod.View {
    return .{ .kind = .{ .iconButton = .{ .icon = icon, .size = size, .action = on_tap } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
