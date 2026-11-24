//! What a pane shows when it has nothing to show: a quiet title, and a line
//! saying what would fill it, centered in the space.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_empty_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// An empty pane's message: `title`, and below it a wrapped `detail`, centered
/// and in the secondary label color; both cleaned for drawing.
///
/// - `title`: what is missing ("No changes.").
/// - `detail`: what would fill it, or empty for none.
/// - Returns: the view, filling the space it is given.
pub fn EmptyState(title: []const u8, detail: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.VStack(.{
        mod.Spacer(),
        mod.Text(mod.DisplayText.clean(allocator, title)).foregroundStyle(tokens.secondary_label),
        if (detail.len > 0) mod.WrappedText(mod.DisplayText.clean(allocator, detail)).font(.footnote).foregroundStyle(tokens.secondary_label).frameCap(420) else mod.Empty(),
        mod.Spacer(),
    }).spacing(6).padding(16).frameMaxWidth().frameMaxHeight();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "empty state centers its title over its detail, and drops an empty detail" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const full = EmptyState("Nothing here.", "Drop files to add some.");
    const bare = EmptyState("Nothing here.", "");
    window.end();
    // Spacer, title, detail, spacer; an empty detail is an `Empty`, which takes no room.
    try std.testing.expectEqual(@as(usize, 4), full.kind.stack.children.len);
    try std.testing.expect(bare.kind.stack.children[2].kind == .empty);
}
