//! A size a parent proposes to a child during layout.

const std = @import("std");
const log = std.log.scoped(.ziggui_proposal);
const mod = @import("module.zig");

/// A proposed size. A null dimension means "unspecified" — the child should
/// report its ideal size on that axis (SwiftUI's `nil` proposal).
pub const Proposal = struct {
    const Self = @This();

    /// The proposed width, or null for the child's ideal.
    width: ?f32 = null,
    /// The proposed height, or null for the child's ideal.
    height: ?f32 = null,

    /// Both dimensions unspecified.
    pub const unspecified = Self{};

    /// A proposal of exactly `size`.
    ///
    /// - `size`: the proposed size.
    /// - Returns: the proposal.
    pub fn fixed(size: mod.Size) Self {
        return .{ .width = size.width, .height = size.height };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
