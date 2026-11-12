//! The semantic appearance of a control.

const std = @import("std");
const log = std.log.scoped(.ziggui_role);

/// The semantic appearance of a control, used by buttons (and reusable by other
/// roled controls). `normal` is the theme's everyday button; `prominent` is the
/// emphasized/default action (accent-tinted on most themes); `plain` is a
/// borderless, label-only button.
pub const Role = enum {
    const Self = @This();

    /// The everyday button.
    normal,
    /// The emphasized/default action.
    prominent,
    /// A destructive action.
    destructive,
    /// A borderless, label-only button.
    plain,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
