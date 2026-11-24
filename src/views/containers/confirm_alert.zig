//! A yes-or-no question as an alert's content: the question, a second line,
//! and two buttons, the refusal first.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_confirm_alert);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The question's panel: `title`, `detail`, then the refusal and the agreement (destructive unless `Confirm.destructive` is false), plain buttons.
///
/// The keys are the app's to route: Enter (or `y`) agrees and Esc (or `n`) refuses in every app on ziggui.
///
/// - `question`: the question; its strings are cleaned for drawing.
/// - `no_label`: the refusing button's title ("No", "Cancel").
/// - `on_no`: what refusing does: the app closes the question.
/// - `on_yes`: what agreeing does: the app closes the question, then calls `question.on_yes`.
/// - Returns: the panel, for the app's `.alert`.
pub fn ConfirmAlert(question: *const mod.Confirm, no_label: []const u8, on_no: mod.Callback, on_yes: mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.VStack(.{
        mod.WrappedText(mod.DisplayText.clean(allocator, question.title)).font(.system(15)).fontWeight(.semibold).frameMaxWidth().frameAlign(.leading),
        if (question.detail.len > 0) mod.WrappedText(mod.DisplayText.clean(allocator, question.detail)).font(.system(12)).foregroundStyle(tokens.secondary_label).frameMaxWidth().frameAlign(.leading) else mod.Empty(),
        mod.HStack(.{
            mod.Spacer(),
            mod.ButtonRoled(no_label, .normal, on_no),
            mod.ButtonRoled(question.yes_label, if (question.destructive) .destructive else .prominent, on_yes),
        }).spacing(8),
    }).spacing(12).alignment(.leading).padding(20).frameMinWidth(400);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "confirm alert sets the question over its two buttons, and drops an empty detail" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const question = mod.Confirm{ .title = "Delete a.txt?", .yes_label = "Delete", .on_yes = .{ .function = TestConfirm.nothing } };
    const view = ConfirmAlert(&question, "No", .{ .function = TestConfirm.nothing }, .{ .function = TestConfirm.nothing });
    window.end();
    try std.testing.expectEqual(@as(usize, 3), view.kind.stack.children.len);
    try std.testing.expect(view.kind.stack.children[1].kind == .empty);
}

test "confirm alert draws a question that destroys nothing with a prominent agreement" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const question = mod.Confirm{ .title = "Restart?", .yes_label = "Restart", .destructive = false, .on_yes = .{ .function = TestConfirm.nothing } };
    const view = ConfirmAlert(&question, "Cancel", .{ .function = TestConfirm.nothing }, .{ .function = TestConfirm.nothing });
    window.end();
    const buttons = view.kind.stack.children[2].kind.stack.children;
    try std.testing.expect(buttons[2].kind.button.role == .prominent);
}

/// A callback that does nothing, for the test.
const TestConfirm = struct {
    const Self = @This();

    /// Does nothing.
    ///
    /// - `context`: unused.
    fn nothing(context: ?*anyopaque) void {
        _ = context;
    }
};
