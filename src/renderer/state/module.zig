//! Reactivity and animation: observers, observable state and bindings, and
//! the tween engine that drives state over time.

const std = @import("std");
const log = std.log.scoped(.ziggui_state_module);

/// Something notified when state it depends on changes.
pub const Observer = @import("observer.zig").Observer;
/// An observable value (`State(T)`).
pub const State = @import("state.zig").State;
/// A type-erased two-way handle into a value (`Binding(T)`).
pub const Binding = @import("binding.zig").Binding;
/// A timing curve.
pub const Easing = @import("easing.zig").Easing;
/// One value animation.
pub const Tween = @import("tween.zig").Tween;
/// The in-flight tweens of an app.
pub const Animator = @import("animator.zig").Animator;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("observer.zig");
    _ = @import("state.zig");
    _ = @import("binding.zig");
    _ = @import("easing.zig");
    _ = @import("tween.zig");
    _ = @import("animator.zig");
}
