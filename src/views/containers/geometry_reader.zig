//! A view whose content is built from the size it is laid out at.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_geometry_reader);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A view whose content depends on its own size, like SwiftUI's
/// `GeometryReader`: `build(context, size)` builds the content once layout knows
/// the size the reader is given, and the content is laid out in that rect. Fills
/// the space it is offered, so give it a frame or a flexible parent.
///
/// The content is built at paint time, in the frame arena, so `build` may call
/// any view constructor (and `BuildScope.allocator`/`tokens`) as a body does.
/// `context` must outlive the frame (the build arena does).
///
/// - `T`: the context's type.
/// - `context`: what `build` gets back.
/// - `build`: makes the content for a size.
/// - Returns: the view.
pub fn GeometryReader(comptime T: type, context: *const T, comptime build: fn (*const T, renderer.Size) mod.View) mod.View {
    return .{ .kind = .{ .geometry = .{ .context = context, .build = struct {
        const Self = @This();

        fn call(pointer: *const anyopaque, size: renderer.Size) mod.View {
            return build(@ptrCast(@alignCast(pointer)), size);
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
