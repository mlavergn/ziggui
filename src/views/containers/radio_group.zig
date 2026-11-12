//! A vertical group of radio buttons over a selected index.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_radio_group);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The 16×16 radio dot.
const RadioIndicator = struct {
    const Self = @This();

    /// An accent-filled disc with a white center when selected, or a hollow
    /// ring when not. Built from layered `Circle`s (which fill, centered,
    /// inside a `ZStack`).
    ///
    /// - `selected`: whether the option is selected.
    /// - Returns: the dot.
    fn view(selected: bool) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        if (selected) {
            return mod.ZStack(.{
                mod.Circle(tokens.selection).frame(14, 14),
                mod.Circle(tokens.on_accent).frame(5, 5),
            }).frame(14, 14);
        }
        return mod.ZStack(.{
            mod.Circle(renderer.Color.black.withAlpha(0.22)).frame(14, 14),
            mod.Circle(renderer.Color.white).frame(12, 12),
        }).frame(14, 14);
    }
};

/// A vertical radio-button group bound to a selected index (SwiftUI's
/// `.pickerStyle(.radioGroup)`). Pure composition: each option is a row with a
/// concentric-circle indicator (a filled accent dot when selected) and a tap that
/// sets `selection`.
///
/// - `selection`: the selected option's index.
/// - `options`: the options' titles.
/// - Returns: the group.
pub fn RadioGroup(selection: mod.Binding(i64), options: []const []const u8) mod.View {
    const rows = mod.BuildScope.shared().allocator().alloc(mod.View, options.len) catch @panic("oom");
    for (options, 0..) |option, index| {
        const is_selected = selection.get() == @as(i64, @intCast(index));
        rows[index] = mod.HStack(.{
            RadioIndicator.view(is_selected),
            mod.Text(option),
            mod.Spacer(),
        }).spacing(8)
            .frameMaxWidth()
            .onTap(mod.Callback.select(selection, @intCast(index)));
    }
    return mod.StackBuilder.fromSlice(.vertical, 8, .leading, rows).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
