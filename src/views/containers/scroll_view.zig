//! Scrolling viewports: at a fixed offset, or driven by an app-owned `ScrollState`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_view);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds the fixed-offset scroll views.
const FixedScroll = struct {
    const Self = @This();

    /// A scroll view along `axis` at `offset`.
    ///
    /// - `axis`: the direction it scrolls.
    /// - `offset`: how far the content is scrolled.
    /// - `content`: what scrolls.
    /// - Returns: the view.
    fn view(axis: renderer.Direction, offset: f32, content: mod.View) mod.View {
        const child = mod.BuildScope.shared().allocator().create(mod.View) catch @panic("oom");
        child.* = content;
        return .{ .kind = .{ .scroll = .{ .axis = axis, .offset = offset, .content = child } } };
    }
};

/// A vertical scroll view at the top.
///
/// - `content`: what scrolls.
/// - Returns: the view.
pub fn ScrollView(content: mod.View) mod.View {
    return FixedScroll.view(.vertical, 0, content);
}

/// A scroll view at a fixed offset along `axis`.
///
/// - `axis`: the direction it scrolls.
/// - `offset`: how far the content is scrolled.
/// - `content`: what scrolls.
/// - Returns: the view.
pub fn ScrollViewOffset(axis: renderer.Direction, offset: f32, content: mod.View) mod.View {
    return FixedScroll.view(axis, offset, content);
}

/// A vertical scroll view driven by an app-owned `ScrollState`. Like
/// `ScrollView`, but the offset persists across frames in `scroll_state`, so it
/// can be moved by the mouse wheel (`PointerInput.scroll`) or pinned to the
/// bottom (`scroll_state.scrollToBottom()` for a streaming transcript).
///
/// - `scroll_state`: the position; app-owned.
/// - `content`: what scrolls.
/// - Returns: the view.
pub fn ScrollViewState(scroll_state: *mod.ScrollState, content: mod.View) mod.View {
    const child = mod.BuildScope.shared().allocator().create(mod.View) catch @panic("oom");
    child.* = content;
    return .{ .kind = .{ .scrollState = .{ .state = scroll_state, .content = child } } };
}

/// A scroll view that scrolls both ways, like SwiftUI's
/// `ScrollView([.horizontal, .vertical])`, driven by an app-owned
/// `ScrollState` (`offset` down, `offset_x` across). The content is laid out
/// at its own width (at least the viewport's), so a line wider than the
/// viewport runs on instead of being cut; a horizontal overlay bar along the
/// bottom edge shows and drags the sideways position.
///
/// - `scroll_state`: the position, both ways; app-owned.
/// - `content`: what scrolls.
/// - Returns: the scroll view.
pub fn ScrollViewStateBoth(scroll_state: *mod.ScrollState, content: mod.View) mod.View {
    const child = mod.BuildScope.shared().allocator().create(mod.View) catch @panic("oom");
    child.* = content;
    return .{ .kind = .{ .scrollState = .{ .state = scroll_state, .content = child, .horizontal = true } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
