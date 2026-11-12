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

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
