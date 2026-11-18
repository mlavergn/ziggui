//! A link drawn on every hunk header of a `SelectableDiffViewWithActions`.

const std = @import("std");
const log = std.log.scoped(.ziggui_hunk_action);
const mod = @import("module.zig");

/// A link on each hunk header row, pinned to the pane's right edge: borderless
/// text in the accent color that calls `callback` with its hunk's index.
pub const HunkAction = struct {
    const Self = @This();

    /// The space on each side of a label, inside its tap area.
    pub const padding: f32 = 4;

    /// The space between two labels' tap areas.
    pub const spacing: f32 = 4;

    /// The space kept free right of the last label, for the scroll bar.
    pub const trailing: f32 = 6;

    /// The link's text.
    label: []const u8,

    /// What a tap calls, with the index of the hunk whose header was tapped.
    callback: mod.IndexCallback,

    /// Drawn in the secondary label color, and a tap passes to the row beneath.
    disabled: bool = false,

    /// How wide the links are laid out side by side, `trailing` included:
    /// each label's cells (the diff's mono advance) and padding, and the
    /// spacing between them. Text cannot be measured while views are built;
    /// the labels are drawn in the diff's mono face, so they are counted.
    ///
    /// - `actions`: the links.
    /// - Returns: their width, in points; 0 for none.
    pub fn groupWidth(actions: []const Self) f32 {
        if (actions.len == 0) return 0;
        var width: f32 = trailing + spacing * @as(f32, @floatFromInt(actions.len - 1));
        for (actions) |action| {
            width += @as(f32, @floatFromInt(mod.DiffLayout.columns(action.label))) * mod.DiffLayout.cell_width + 2 * padding;
        }
        return width;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a group of hunk actions is as wide as its labels' cells, padding and spacing" {
    const Probe = struct {
        const Self = @This();
        /// Does nothing.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onAction(self: *Self, index: usize) void {
            _ = self;
            _ = index;
        }
    };
    var probe: Probe = .{};
    const callback = mod.IndexCallback.init(Probe, &probe, Probe.onAction);
    const actions = [_]HunkAction{ .{ .label = "Stage", .callback = callback }, .{ .label = "Discard", .callback = callback } };
    const cells: f32 = 12 * mod.DiffLayout.cell_width;
    try std.testing.expectEqual(cells + 4 * HunkAction.padding + HunkAction.spacing + HunkAction.trailing, HunkAction.groupWidth(&actions));
    try std.testing.expectEqual(@as(f32, 0), HunkAction.groupWidth(&.{}));
}
