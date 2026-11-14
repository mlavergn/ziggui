//! Push buttons: a title, a role, an optional leading glyph.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_button);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A push button.
///
/// - `label`: its title.
/// - `on_tap`: what a tap calls.
/// - Returns: the view.
pub fn Button(label: []const u8, on_tap: mod.Callback) mod.View {
    return .{ .kind = .{ .button = .{ .label = label, .action = on_tap } } };
}

/// A push button with a role (default, cancel, destructive).
///
/// - `label`: its title.
/// - `role`: its semantic appearance.
/// - `on_tap`: what a tap calls.
/// - Returns: the view.
pub fn ButtonRoled(label: []const u8, role: mod.ButtonRole, on_tap: mod.Callback) mod.View {
    return .{ .kind = .{ .button = .{ .label = label, .action = on_tap, .role = role } } };
}

/// A button with a leading glyph before the label — the macOS toolbar-pill
/// style (`Button { Label("Think", systemImage: …) }`). Neutral glass chrome;
/// use `ButtonIconRoled` for a tinted role.
///
/// - `label`: its title.
/// - `icon`: its glyph.
/// - `on_tap`: what a tap calls.
/// - Returns: the view.
pub fn ButtonIcon(label: []const u8, icon: renderer.Icon, on_tap: mod.Callback) mod.View {
    return .{ .kind = .{ .button = .{ .label = label, .action = on_tap, .icon = icon } } };
}

/// A push button with a leading glyph and a role.
///
/// - `label`: its title.
/// - `icon`: its glyph.
/// - `role`: its semantic appearance.
/// - `on_tap`: what a tap calls.
/// - Returns: the view.
pub fn ButtonIconRoled(label: []const u8, icon: renderer.Icon, role: mod.ButtonRole, on_tap: mod.Callback) mod.View {
    return .{ .kind = .{ .button = .{ .label = label, .action = on_tap, .role = role, .icon = icon } } };
}

/// A push button with its keyboard shortcut drawn as a key cap after the
/// label ("Save ↩", "Cancel esc"), in the role's chrome: the same height,
/// padding and corner radius as `ButtonRoled`, the cap tinted with the
/// role's label color (on the accent for `.prominent`).
///
/// - `label`: its title.
/// - `shortcut`: the key's text, drawn in a key cap.
/// - `role`: its semantic appearance.
/// - `action`: what a tap calls.
/// - Returns: the view.
pub fn ButtonKeyed(label: []const u8, shortcut: []const u8, role: mod.ButtonRole, action: mod.Callback) mod.View {
    return .{ .kind = .{ .button = .{ .label = label, .action = action, .role = role, .shortcut = shortcut } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a keyed button is wider than its plain twin, and taps" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Probe = struct {
        const Self = @This();
        tapped: bool = false,
        fn onTap(self: *Self) void {
            self.tapped = true;
        }
    };
    var probe: Probe = .{};
    const callback = mod.Callback.init(Probe, &probe, Probe.onTap);
    canvas.begin(renderer.MacosTheme.light);
    const plain = mod.HStack(.{ ButtonRoled("Save", .prominent, callback), mod.Spacer() });
    const keyed = mod.HStack(.{ ButtonKeyed("Save", "↩", .prominent, callback), mod.Spacer() });
    canvas.end();
    var plain_frame = try canvas.render(plain, 200, 30);
    defer plain_frame.deinit();
    var keyed_frame = try canvas.render(keyed, 200, 30);
    defer keyed_frame.deinit();
    // The accent fill runs further right with the key cap in it.
    var plain_right: u32 = 0;
    var keyed_right: u32 = 0;
    for (0..200) |x| {
        const column: u32 = @intCast(x);
        if (plain_frame.at(column, 15).b > plain_frame.at(column, 15).r + 0.3) plain_right = column;
        if (keyed_frame.at(column, 15).b > keyed_frame.at(column, 15).r + 0.3) keyed_right = column;
    }
    try std.testing.expect(keyed_right > plain_right + 10);
    try std.testing.expect(canvas.tap(.{ .x = 10, .y = 15 }));
    try std.testing.expect(probe.tapped);
}

test "a plain button takes its own foreground, never an ancestor's" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Idle = struct {
        const Self = @This();
        fn nothing() void {}
    };
    const red = renderer.Color.fromRgb8(255, 0, 0);
    canvas.begin(renderer.MacosTheme.light);
    const own = mod.HStack(.{ ButtonRoled("Delete", .plain, mod.Callback.action(Idle.nothing)).foreground(red), mod.Spacer() });
    const inherited = mod.HStack(.{ ButtonRoled("Delete", .plain, mod.Callback.action(Idle.nothing)), mod.Spacer() }).foreground(red);
    canvas.end();
    var own_frame = try canvas.render(own, 200, 30);
    defer own_frame.deinit();
    var inherited_frame = try canvas.render(inherited, 200, 30);
    defer inherited_frame.deinit();
    // The reddest label pixel: strongly red with its own tint, not with the stack's.
    var own_red: f32 = 0;
    var inherited_red: f32 = 0;
    for (0..80) |x| {
        const column: u32 = @intCast(x);
        own_red = @max(own_red, own_frame.at(column, 15).r - own_frame.at(column, 15).b);
        inherited_red = @max(inherited_red, inherited_frame.at(column, 15).r - inherited_frame.at(column, 15).b);
    }
    try std.testing.expect(own_red > 0.3);
    try std.testing.expect(inherited_red < 0.1);
}
