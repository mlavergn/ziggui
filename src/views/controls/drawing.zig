//! A view that paints itself through a callback.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_drawing);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A view that paints itself: `draw(context, pen, frame)` runs at paint time, for
/// charts and other one-off graphics. It fills the space it is offered, so
/// give it a frame. `context` must outlive the frame (the build arena does).
///
/// - `T`: the context's type.
/// - `context`: what `draw` gets back.
/// - `draw`: paints the view into its frame.
/// - Returns: the view.
pub fn Drawing(comptime T: type, context: *const T, comptime draw: fn (*const T, *mod.Pen, renderer.Rect) std.mem.Allocator.Error!void) mod.View {
    return .{ .kind = .{ .drawing = .{ .context = context, .draw = struct {
        const Self = @This();

        fn call(pointer: *const anyopaque, pen: *mod.Pen, rect: renderer.Rect) std.mem.Allocator.Error!void {
            try draw(@ptrCast(@alignCast(pointer)), pen, rect);
        }
    }.call } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
