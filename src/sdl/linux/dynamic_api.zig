//! Loads a C library's entry points at run time, so an app links none of
//! them: `Gtk` and `Gstreamer` each describe theirs as a struct of function
//! pointers named for the C functions, and the libraries that define them.

const std = @import("std");
const log = std.log.scoped(.ziggui_dynamic_api);

/// The loader the run-time-loaded toolkits share.
pub const DynamicApi = struct {
    const Self = @This();

    /// Opens every library and fills each field of `api` with the entry point
    /// of its name from the library `libraryOf` names for it; a missing
    /// library or entry point is logged as what becomes unavailable.
    ///
    /// - `Api`: the struct of function pointers, each field a C function's name.
    /// - `api`: the struct to fill.
    /// - `libraries`: the libraries' sonames.
    /// - `libraryOf`: which of `libraries` defines a field, by its name.
    /// - `unavailable`: what the app goes without when one is missing ("video").
    /// - Returns: false when a library or an entry point is missing.
    pub fn load(
        comptime Api: type,
        api: *Api,
        comptime libraries: []const [:0]const u8,
        comptime libraryOf: fn (comptime []const u8) usize,
        unavailable: []const u8,
    ) bool {
        var handles: [libraries.len]*anyopaque = undefined;
        for (libraries, &handles) |name, *handle| {
            handle.* = std.c.dlopen(name, .{ .LAZY = true }) orelse {
                log.warn("{s} unavailable: {s} is missing", .{ unavailable, name });
                return false;
            };
        }
        inline for (@typeInfo(Api).@"struct".field_names) |name| {
            const library = comptime libraryOf(name);
            const pointer = std.c.dlsym(handles[library], name) orelse {
                log.warn("{s} unavailable: {s} has no {s}", .{ unavailable, libraries[library], name });
                return false;
            };
            @field(api, name) = @ptrCast(@alignCast(pointer));
        }
        return true;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
