//! The strip along a window's bottom that says what the last action did: a
//! busy mark while something runs, the notice (in the removed color when it
//! is a refusal), and an optional action for it ("Show in Finder").

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_notice_bar);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The notice strip: the busy mark (or its room), the words, cut to one line
/// and cleaned for drawing, then the action's button when there is one. The
/// app sets its height and background (`.frameHeight`, `.background`).
///
/// - `busy`: something runs: a loader mark shows.
/// - `words`: the notice.
/// - `problem`: it is a refusal or failure, drawn in the removed color.
/// - `action`: what the notice's button does, or null for none.
/// - `action_label`: the button's title.
/// - Returns: the view, as wide as it is given.
pub fn NoticeBar(busy: bool, words: []const u8, problem: bool, action: ?mod.Callback, action_label: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.HStack(.{
        if (busy) mod.Icon(.loader, 12, tokens.accent_mark) else mod.Empty().frameWidth(12),
        mod.Text(mod.DisplayText.clean(allocator, words)).font(.footnote).foregroundStyle(if (problem) tokens.removed else tokens.secondary_label).truncated(),
        if (action) |on_tap| mod.Button(action_label, on_tap) else mod.Empty(),
        mod.Spacer(),
    }).spacing(8).paddingInsets(.{ .leading = 12, .trailing = 12 }).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "notice bar lays out its mark, words and action in a row, the action only when given" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const plain = NoticeBar(true, "Uploaded a.txt.", false, null, "");
    const acting = NoticeBar(false, "Archived.", false, .{ .function = TestNotice.nothing }, "Show in Finder");
    window.end();
    try std.testing.expect(plain.kind.stack.children[2].kind == .empty);
    try std.testing.expect(acting.kind.stack.children[2].kind == .button);
}

/// A notice action that does nothing, for the test.
const TestNotice = struct {
    const Self = @This();

    /// Does nothing.
    ///
    /// - `context`: unused.
    fn nothing(context: ?*anyopaque) void {
        _ = context;
    }
};
