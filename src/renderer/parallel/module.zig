//! Concurrency: a pool of persistent worker threads, and the row bands an
//! image splits into so workers can each fill their own part of it.

const std = @import("std");
const log = std.log.scoped(.ziggui_parallel_module);

/// Persistent worker threads that split a job's tasks between them and the caller.
pub const WorkerPool = @import("worker_pool.zig").WorkerPool;
/// A range of whole rows of an image.
pub const RowBand = @import("row_band.zig").RowBand;
/// An image's rows split into bands for a number of workers.
pub const RowBands = @import("row_bands.zig").RowBands;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("worker_pool.zig");
    _ = @import("row_band.zig");
    _ = @import("row_bands.zig");
}
