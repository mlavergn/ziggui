//! A search field: a magnifying glass, the text, and a clear (×) button once
//! there is text, drawn as one field.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_search_field);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What the clear button does: the field, and what the app wants told, made
/// in the build arena, which outlives the frame until the next rebuild.
const SearchFieldClear = struct {
    const Self = @This();

    /// The field.
    state: *mod.TextFieldState,
    /// Called once the field is empty, or null.
    on_clear: ?mod.Callback,

    /// Empties the field, focuses it, then tells the app.
    ///
    /// - `self`: the clear.
    fn apply(self: *Self) void {
        self.state.setText("") catch |err| log.err("field not cleared [{any}]", .{err});
        mod.Focus.shared().set(self.state);
        if (self.on_clear) |callback| callback.call();
    }
};

/// A search field (SwiftUI's `.searchable` field): a magnifying glass, the
/// text, and, while there is text, a × that empties it, focuses it, and calls
/// `on_clear`. Drawn as one field: the `raised` ground, a `line_strong` border,
/// corner radius 6. Enter calls `on_submit`, as a `TextField`'s `.onSubmit`.
///
/// - `placeholder`: the hint while it is empty.
/// - `state`: the text; app-owned.
/// - `on_submit`: what Enter calls, or null.
/// - `on_clear`: what the × calls once the field is empty, or null.
/// - Returns: the field, as wide as it is given.
pub fn SearchField(placeholder: []const u8, state: *mod.TextFieldState, on_submit: ?mod.Callback, on_clear: ?mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    var input = mod.TextField(placeholder, state).chromeless(0).frameMaxWidth();
    if (on_submit) |callback| input = input.onSubmit(callback);
    const clear: mod.View = if (state.text().len == 0) mod.Empty() else blk: {
        const action = mod.BuildScope.shared().allocator().create(SearchFieldClear) catch @panic("oom");
        action.* = .{ .state = state, .on_clear = on_clear };
        break :blk mod.Icon(.circleX, 13, tokens.secondary_label)
            .paddingInsets(.{ .top = 4, .leading = 4, .bottom = 4, .trailing = 4 })
            .onTap(mod.Callback.init(SearchFieldClear, action, SearchFieldClear.apply))
            .accessibilityLabel("Clear");
    };
    return mod.FieldChrome(mod.StackBuilder.make(.horizontal, 4, .center, .{
        mod.Icon(.search, 13, tokens.secondary_label),
        input,
        clear,
    }).paddingInsets(.{ .top = 2, .leading = 8, .bottom = 2, .trailing = 4 })
        .frameMaxWidth());
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a search field shows its clear button only with text, and the button empties it and calls back" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state = mod.TextFieldState.init(std.testing.allocator);
    defer state.deinit();
    defer mod.Focus.shared().clear();
    const Probe = struct {
        const Self = @This();
        cleared: usize = 0,
        fn onClear(self: *Self) void {
            self.cleared += 1;
        }
    };
    var probe: Probe = .{};

    canvas.begin(renderer.MacosTheme.light);
    const empty = SearchField("Filter", &state, null, mod.Callback.init(Probe, &probe, Probe.onClear));
    canvas.end();
    try std.testing.expectEqual(@as(usize, 3), empty.kind.stack.children.len);
    try std.testing.expect(empty.kind.stack.children[2].kind == .empty);

    try state.setText("photos");
    canvas.begin(renderer.MacosTheme.light);
    const full = SearchField("Filter", &state, null, mod.Callback.init(Probe, &probe, Probe.onClear));
    canvas.end();
    var frame = try canvas.render(full, 300, 28);
    defer frame.deinit();
    // The × sits at the field's trailing end.
    var cleared = false;
    var x: f32 = 296;
    while (x > 240 and !cleared) : (x -= 2) {
        cleared = canvas.tap(.{ .x = x, .y = 14 }) and state.text().len == 0;
    }
    try std.testing.expect(cleared);
    try std.testing.expectEqual(@as(usize, 1), probe.cleared);
    try std.testing.expect(mod.Focus.shared().focused() == &state);
}
