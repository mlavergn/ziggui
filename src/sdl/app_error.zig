//! The errors the SDL runtime's entry points return.

const std = @import("std");
const log = std.log.scoped(.ziggui_app_error);

/// Why the runtime could not start: SDL, its window or its renderer did not
/// come up (`SdlInit`), or the tray icon could not be created (`TrayInit`).
pub const AppError = error{ SdlInit, TrayInit };

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
