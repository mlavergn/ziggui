//! A platform view the app owns, in the view tree.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_native_view);
const mod = @import("module.zig");

/// Shows a platform view the app made (a web view, a map) where layout puts
/// it. It fills what it is offered (size it with `.frame`). In a window the
/// view sits over the window's surface, so ziggui draws nothing over it: the
/// runtime hides it while a sheet, alert, popover or menu is open. Headless,
/// or with a null handle, it is a placeholder frame.
///
/// - `handle`: the platform view (an `NSView` on macOS), or null; it must outlive the frames that show it.
/// - Returns: the view.
pub fn NativeView(handle: ?*anyopaque) mod.View {
    return .{ .kind = .{ .nativeView = .{ .handle = handle } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "NativeView carries its handle" {
    var marker: u8 = 0;
    const view = NativeView(&marker);
    try std.testing.expect(view.kind.nativeView.handle == @as(?*anyopaque, &marker));
    try std.testing.expect(NativeView(null).kind.nativeView.handle == null);
}
