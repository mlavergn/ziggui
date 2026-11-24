//! One row of an outline: indented by its depth, a chevron that folds what
//! sits under it, then the app's content.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_outline_row);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One row of an outline (SwiftUI's `OutlineGroup`, row by row, so a long
/// tree goes in a `VirtualList` over `OutlineState.visible`): `depth` levels
/// of `OutlineState.indent`, the chevron's column (`chevronRight` collapsed,
/// `chevronDown` expanded; empty when the node cannot expand, so names line
/// up), then `content`. The row's selection, its tap and its look stay the
/// app's: wrap the row in a `SelectableRow`, say.
///
/// - `depth`: how deep the node sits (`OutlineNode.depth`).
/// - `expandable`: whether it can expand (`OutlineNode.has_children`).
/// - `expanded`: whether it shows as expanded (`OutlineState.isExpanded`).
/// - `tint`: the chevron's color; null for `secondary_label` (a row filled
///   with the selection takes `SelectableRowStyle.selectionText`).
/// - `on_toggle`: called when the chevron is tapped; null leaves the tap to
///   whatever the row does.
/// - `content`: the node's label.
/// - Returns: the row.
pub fn OutlineRow(depth: u16, expandable: bool, expanded: bool, tint: ?renderer.Color, on_toggle: ?mod.Callback, content: mod.View) mod.View {
    const color = tint orelse mod.BuildScope.shared().tokens().secondary_label;
    const glyph: mod.View = if (!expandable)
        mod.Empty().frameWidth(mod.OutlineState.chevron_width)
    else
        mod.Icon(if (expanded) .chevronDown else .chevronRight, 12, color).frameWidth(mod.OutlineState.chevron_width);
    const chevron = if (expandable and on_toggle != null) glyph.onTapGesture(on_toggle.?) else glyph;
    const label = mod.HStack(.{ chevron, content }).spacing(mod.OutlineState.chevron_gap);
    const indent = mod.OutlineState.indent * @as(f32, @floatFromInt(depth));
    return mod.HStack(.{ mod.Empty().frameWidth(indent), label }).spacing(0);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an outline row's chevron toggles its node, and the row's own tap is left to the row" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();

        /// The rows' fold state.
        state: mod.OutlineState,
        /// Taps on the row itself.
        rows: usize = 0,

        /// Folds or unfolds `src/`.
        ///
        /// - `self`: the probe.
        /// - Returns: nothing; propagates allocation failure.
        fn toggled(self: *Self) std.mem.Allocator.Error!void {
            try self.state.toggle("src/");
        }

        /// Counts a tap on the row.
        ///
        /// - `self`: the probe.
        fn rowTapped(self: *Self) void {
            self.rows += 1;
        }
    };
    var probe: Probe = .{ .state = .init(std.testing.allocator, false) };
    defer probe.state.deinit();

    window.begin(renderer.MacosTheme.light);
    const row = mod.SelectableRow(
        mod.OutlineRow(1, true, probe.state.isExpanded("src/"), null, mod.Callback.attempt(Probe, &probe, Probe.toggled, "cannot fold src/"), mod.Text("src")),
        false,
        true,
        mod.Callback.init(Probe, &probe, Probe.rowTapped),
    );
    window.end();
    var frame = try window.render(row, 300, 28);
    defer frame.deinit();
    // The chevron sits one indent in, past the row's padding.
    const chevron_x = mod.OutlineState.indent + mod.OutlineState.chevron_width / 2 + 8;
    try std.testing.expect(window.tap(.{ .x = chevron_x, .y = 14 }));
    try std.testing.expect(probe.state.isExpanded("src/"));
    try std.testing.expectEqual(0, probe.rows);
    try std.testing.expect(window.tap(.{ .x = 200, .y = 14 }));
    try std.testing.expectEqual(1, probe.rows);
}

test "an outline row that cannot expand keeps the chevron's column, and taps through to the row" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const leaf = mod.OutlineRow(2, false, false, null, null, mod.Text("list.zig"));
    const top = mod.OutlineRow(0, true, true, null, null, mod.Text("src"));
    const rows = mod.VStack(.{ leaf, top }).spacing(0);
    window.end();
    var frame = try window.render(rows, 300, 40);
    defer frame.deinit();
    // No chevron and no tap of its own: nothing answers a tap where it would be.
    try std.testing.expect(!window.tap(.{ .x = 2 * mod.OutlineState.indent + 7, .y = 8 }));
}
