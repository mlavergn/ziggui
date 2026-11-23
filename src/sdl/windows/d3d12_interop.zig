//! SDL's Direct3D 12 backend put on WARP, the Direct3D 12 renderer Windows
//! runs on the CPU, through `d3d12_interop.c`, compiled into SDL in place of
//! its Direct3D 12 backend (`has_d3d12_interop`: Windows, SDL built from the
//! release).

const std = @import("std");
const log = std.log.scoped(.ziggui_d3d12_interop);
const mod = @import("module.zig");

/// The C side, `d3d12_interop.c`.
const Externs = struct {
    const Self = @This();

    /// `ziggui_d3d12_use_warp`.
    extern fn ziggui_d3d12_use_warp(warp: bool) void;
};

/// Which adapter SDL's next Direct3D 12 devices take.
pub const D3d12Interop = struct {
    const Self = @This();

    /// Whether this build can put Direct3D 12 on WARP.
    pub const available = mod.has_d3d12_interop;

    /// Puts SDL's next Direct3D 12 devices on WARP (true), or on the GPU
    /// DXGI lists first (false, as SDL does alone); a device already made
    /// keeps its adapter. Does nothing where the interop is not built.
    ///
    /// - `warp`: whether to use WARP.
    pub fn useWarp(warp: bool) void {
        if (comptime !Self.available) return;
        Externs.ziggui_d3d12_use_warp(warp);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
