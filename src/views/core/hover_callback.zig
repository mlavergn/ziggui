//! What `View.onHover` calls when the pointer enters or leaves a view.

const std = @import("std");
const log = std.log.scoped(.ziggui_hover_callback);

/// Called with `true` when the pointer enters a view's frame and `false` when
/// it leaves (see `View.onHover`).
pub const HoverCallback = struct {
    const Self = @This();

    /// What `function` gets back.
    context: ?*anyopaque = null,

    /// The handler.
    function: *const fn (?*anyopaque, inside: bool) void,

    /// Calls the handler.
    ///
    /// - `self`: the callback.
    /// - `inside`: true on entering, false on leaving.
    pub fn call(self: *const Self, inside: bool) void {
        self.function(self.context, inside);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
