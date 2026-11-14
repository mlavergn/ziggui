//! A field of short tokens: capsules for the committed ones, then an input.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_token_field);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A token field: the committed tokens as small capsules, each with a
/// trailing × that removes it, in a row followed by the input; Enter in the
/// input commits it (`TokenFieldState.commit`: comma-separated, trimmed,
/// no repeats). Drawn as one field: the `raised` ground, a `line_strong`
/// border, corner radius 6.
///
/// - `state`: the tokens and the input; app-owned.
/// - `placeholder`: the input's hint.
/// - Returns: the field, as wide as it is given.
pub fn TokenField(state: *mod.TokenFieldState, placeholder: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    const committed = state.tokens();
    const items = allocator.alloc(mod.View, committed.len + 1) catch @panic("oom");
    for (committed, 0..) |token, index| {
        items[index] = mod.StackBuilder.make(.horizontal, 2, .center, .{
            mod.Text(token).size(11).weight(.medium).foreground(tokens.label),
            mod.Icon(.x, 10, tokens.secondary_label)
                .paddingInsets(.{ .top = 4, .leading = 3, .bottom = 4, .trailing = 6 })
                .onTap(mod.Callback.tagged(mod.TokenFieldState, state, mod.TokenFieldState.remove, index))
                .accessibilityLabel("Remove"),
        }).paddingInsets(.{ .leading = 8 })
            .background(tokens.neutral_soft)
            .cornerRadius(9);
    }
    items[committed.len] = mod.TextField(placeholder, &state.input)
        .chromeless(0)
        .onSubmit(mod.Callback.attempt(mod.TokenFieldState, state, mod.TokenFieldState.commit, "tokens not committed"))
        .frameMaxWidth();
    return mod.FieldChrome(mod.StackBuilder.fromSlice(.horizontal, 4, .center, items)
        .paddingInsets(.{ .top = 2, .leading = 4, .bottom = 2, .trailing = 4 })
        .frameMaxWidth());
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a token field draws a capsule per token, removes on ×, commits on submit" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state = mod.TokenFieldState.init(std.testing.allocator);
    defer state.deinit();
    defer mod.Focus.shared().clear();
    try state.setTokens(&.{ "repos", "issues" });

    canvas.begin(renderer.MacosTheme.light);
    const field = TokenField(&state, "Add a toolset");
    canvas.end();
    try std.testing.expectEqual(@as(usize, 3), field.kind.stack.children.len);
    var frame = try canvas.render(field, 400, 30);
    defer frame.deinit();
    // The first capsule's × is the first tap target from the left that removes.
    var removed = false;
    var x: f32 = 4;
    while (x < 120 and !removed) : (x += 2) {
        removed = canvas.tap(.{ .x = x, .y = 15 }) and state.tokens().len == 1;
    }
    try std.testing.expect(removed);
    try std.testing.expectEqualStrings("issues", state.tokens()[0]);

    // Enter in the focused input commits it.
    mod.Focus.shared().set(&state.input);
    try state.input.setText("actions, issues");
    canvas.begin(renderer.MacosTheme.light);
    const again = TokenField(&state, "Add a toolset");
    canvas.end();
    var second = try canvas.render(again, 400, 30);
    defer second.deinit();
    mod.Focus.shared().submit();
    try std.testing.expectEqual(@as(usize, 2), state.tokens().len);
    try std.testing.expectEqualStrings("actions", state.tokens()[1]);
}
