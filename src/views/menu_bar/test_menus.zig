//! Two menus for the menu bar's unit tests, counting their choices (a test fixture).

const std = @import("std");
const log = std.log.scoped(.ziggui_test_menus);
const mod = @import("module.zig");

/// Two menus for the menu bar's unit tests, every entry counting its choice
/// in `chosen`: File (Open, a separator, Save disabled, Quit) and Edit (Undo
/// disabled, Copy).
pub const TestMenus = struct {
    const Self = @This();

    /// How many entries have been chosen; a test resets it first.
    pub var chosen: u32 = 0;

    /// The menus.
    pub const menus = [_]mod.MenuBarMenu{
        .{ .title = "File", .items = &.{
            .{ .title = "Open", .key_text = "ctrl+O", .action = .{ .function = Self.pick } },
            .{},
            .{ .title = "Save", .enabled = false, .action = .{ .function = Self.pick } },
            .{ .title = "Quit", .key_text = "ctrl+Q", .action = .{ .function = Self.pick } },
        } },
        .{ .title = "Edit", .items = &.{
            .{ .title = "Undo", .enabled = false, .action = .{ .function = Self.pick } },
            .{ .title = "Copy", .action = .{ .function = Self.pick } },
        } },
    };

    /// Every entry's action: counts the choice.
    ///
    /// - `context`: unused.
    fn pick(context: ?*anyopaque) void {
        _ = context;
        Self.chosen += 1;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
