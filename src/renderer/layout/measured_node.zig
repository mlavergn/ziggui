//! A layout leaf that measures itself against the live proposal.

const std = @import("std");
const log = std.log.scoped(.ziggui_measured_node);
const mod = @import("module.zig");

/// A leaf whose size depends on the proposed width (or height). `measure_fn`
/// answers the measure protocol directly given the live proposal — the escape
/// hatch for content like wrapped text whose height is only known once the width
/// is proposed, which the static `SizingHints` cannot express. `context` is an
/// opaque pointer to caller-owned measurement state (e.g. font + string).
pub const MeasuredNode = struct {
    const Self = @This();

    /// The caller-owned measurement state `measure_fn` receives.
    context: *const anyopaque,
    /// The leaf's size for a proposal.
    measure_fn: *const fn (*const anyopaque, mod.Proposal) mod.Size,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
