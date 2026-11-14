//! An editor of name/value rows (headers, environment variables).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_key_value_editor);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Name/value rows, each [name field][value field][remove ×], in mono, 6pt
/// apart, then an "Add" button that appends a row and focuses its name. With
/// no rows it shows only the Add button.
///
/// - `state`: the rows; app-owned.
/// - `key_placeholder`: the name fields' hint.
/// - `value_placeholder`: the value fields' hint.
/// - Returns: the editor, as wide as it is given.
pub fn KeyValueEditor(state: *mod.KeyValueState, key_placeholder: []const u8, value_placeholder: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const items = mod.BuildScope.shared().allocator().alloc(mod.View, state.count() + 1) catch @panic("oom");
    for (state.rows.items, 0..) |row, index| {
        items[index] = mod.StackBuilder.make(.horizontal, 6, .center, .{
            mod.TextField(key_placeholder, &row.key).mono().frameMaxWidth(),
            mod.TextField(value_placeholder, &row.value).mono().frameMaxWidth(),
            mod.IconButton(.x, 12, mod.Callback.tagged(mod.KeyValueState, state, mod.KeyValueState.remove, index))
                .foreground(tokens.secondary_label)
                .accessibilityLabel("Remove"),
        }).frameMaxWidth();
    }
    items[state.count()] = mod.StackBuilder.make(.horizontal, 0, .center, .{
        mod.ButtonIconRoled("Add", .plus, .plain, mod.Callback.attempt(mod.KeyValueState, state, mod.KeyValueState.add, "key/value row not added")),
        mod.Spacer(),
    }).frameMaxWidth();
    return mod.StackBuilder.fromSlice(.vertical, 6, .leading, items).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a key/value editor draws a row per pair, adds on Add, removes on ×" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state = mod.KeyValueState.init(std.testing.allocator);
    defer state.deinit();
    defer mod.Focus.shared().clear();

    canvas.begin(renderer.MacosTheme.light);
    const empty = mod.VStack(.{ KeyValueEditor(&state, "Name", "Value"), mod.Spacer() });
    canvas.end();
    try std.testing.expectEqual(@as(usize, 1), empty.kind.stack.children[0].kind.stack.children.len);
    var first = try canvas.render(empty, 400, 120);
    first.deinit();
    // The Add button sits at the leading edge.
    try std.testing.expect(canvas.tap(.{ .x = 20, .y = 11 }));
    try std.testing.expectEqual(@as(usize, 1), state.count());
    try std.testing.expect(mod.Focus.shared().focused() == &state.rows.items[0].key);

    try state.setPairs(&.{ .{ "Accept", "application/json" }, .{ "X-Trace", "1" } });
    canvas.begin(renderer.MacosTheme.light);
    const two = mod.VStack(.{ KeyValueEditor(&state, "Name", "Value"), mod.Spacer() });
    canvas.end();
    var frame = try canvas.render(two, 400, 120);
    defer frame.deinit();
    // The first row's remove button is at the trailing edge of the top row.
    var removed = false;
    var x: f32 = 399;
    while (x > 300 and !removed) : (x -= 2) {
        removed = canvas.tap(.{ .x = x, .y = 11 }) and state.count() == 1;
    }
    try std.testing.expect(removed);
    try std.testing.expectEqualStrings("X-Trace", state.rows.items[0].key.text());
}
