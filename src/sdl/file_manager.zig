//! Showing a local file in the system's file manager: Finder selects it,
//! Explorer selects it, and elsewhere the folder holding it opens.

const std = @import("std");
const log = std.log.scoped(.ziggui_file_manager);
const mod = @import("module.zig");

/// The system's file manager, asked to show a file.
pub const FileManager = struct {
    const Self = @This();

    /// Shows a local file: `open -R` on macOS, `explorer /select,` on Windows,
    /// and the holding folder through the desktop's URL handler (`xdg-open`) elsewhere.
    ///
    /// Only an absolute path is taken, so nothing in it can read as an option.
    /// The macOS and Windows tools are found by absolute path (`/usr/bin/open`,
    /// `%SystemRoot%\explorer.exe`), never by a PATH search, get the path as one
    /// argument, never through a shell, and are waited for so no child is left
    /// unreaped; both return at once, handing the request to Finder or the shell.
    /// Explorer splits its command line at commas itself, so a path holding one
    /// opens its folder through a `file:` URL instead of being selected.
    ///
    /// - `io`: IO for the child process.
    /// - `allocator`: scratch for the argument or the URL.
    /// - `environ`: the process's environment (`std.process.Init.environ_map`): Windows' `SystemRoot`.
    /// - `path`: the file, absolute.
    /// - Returns: false when nothing could be asked to show it (logged).
    pub fn reveal(io: std.Io, allocator: std.mem.Allocator, environ: *const std.process.Environ.Map, path: []const u8) bool {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        if (!std.Io.Dir.path.isAbsolute(path)) {
            log.warn("the file manager was not asked: the path is not absolute", .{});
            return false;
        }
        switch (mod.os_tag) {
            .macos => return Self.run(io, &.{ "/usr/bin/open", "-R", path }),
            .windows => {
                if (std.mem.findScalar(u8, path, ',') != null) return Self.openFolder(allocator, path, true);
                const root = environ.get("SystemRoot") orelse {
                    log.warn("the file manager was not found: no SystemRoot", .{});
                    return false;
                };
                const explorer = std.Io.Dir.path.join(allocator, &.{ root, "explorer.exe" }) catch |err| {
                    log.warn("the file manager's path was not made [{t}]", .{err});
                    return false;
                };
                defer allocator.free(explorer);
                const select = std.mem.concat(allocator, u8, &.{ "/select,", path }) catch |err| {
                    log.warn("the file manager's argument was not made [{t}]", .{err});
                    return false;
                };
                defer allocator.free(select);
                return Self.run(io, &.{ explorer, select });
            },
            else => return Self.openFolder(allocator, path, false),
        }
    }

    /// The `file:` URL of the folder holding `path`, each byte outside RFC 3986's
    /// unreserved set and `/` percent-encoded; a Windows path's `\` become `/`
    /// and its drive letter keeps its colon (`file:///C:/Users/…`).
    ///
    /// - `allocator`: owns the URL.
    /// - `path`: the file, absolute.
    /// - `windows`: whether it is a Windows path.
    /// - Returns: the URL, NUL-terminated; propagates allocation failure.
    pub fn folderUrlAlloc(allocator: std.mem.Allocator, path: []const u8, windows: bool) ![:0]u8 {
        const cut = if (windows) std.mem.findLastAny(u8, path, "\\/") else std.mem.findScalarLast(u8, path, '/');
        // A root keeps its separator: `/`, and a drive's `C:\` (`C:` alone
        // is that drive's working folder).
        const drive = windows and path.len >= 3 and path[1] == ':';
        const root_length: usize = if (drive) 3 else 1;
        const folder = if (cut) |at| path[0..@max(at, root_length)] else path;
        var url: std.Io.Writer.Allocating = .init(allocator);
        defer url.deinit();
        try url.writer.writeAll(if (windows) "file:///" else "file://");
        for (folder, 0..) |byte, index| {
            const shown: u8 = if (windows and byte == '\\') '/' else byte;
            const drive_colon = windows and byte == ':' and index == 1;
            const plain = drive_colon or std.ascii.isAlphanumeric(shown) or std.mem.findScalar(u8, "/-._~", shown) != null;
            if (plain) try url.writer.writeByte(shown) else try url.writer.print("%{X:0>2}", .{shown});
        }
        return allocator.dupeSentinel(u8, url.written(), 0);
    }

    /// Opens the folder holding `path` through the desktop's URL handler.
    ///
    /// - `allocator`: scratch for the URL.
    /// - `path`: the file, absolute.
    /// - `windows`: whether it is a Windows path.
    /// - Returns: false when the URL could not be made or opened (logged).
    fn openFolder(allocator: std.mem.Allocator, path: []const u8, windows: bool) bool {
        const url = Self.folderUrlAlloc(allocator, path, windows) catch |err| {
            log.warn("the folder's URL was not made [{t}]", .{err});
            return false;
        };
        defer allocator.free(url);
        return mod.Clipboard.openUrl(url.ptr);
    }

    /// Runs a tool that returns at once, and reaps it; its exit is not judged (Explorer answers 1 when it shows the file).
    ///
    /// - `io`: IO for the child process.
    /// - `argv`: the tool's absolute path, then its arguments.
    /// - Returns: false when it could not be started (logged).
    fn run(io: std.Io, argv: []const []const u8) bool {
        var child = std.process.spawn(io, .{ .argv = argv }) catch |err| {
            log.warn("the file manager did not open [{t}]", .{err});
            return false;
        };
        _ = child.wait(io) catch |err| log.warn("the file manager was not waited for [{t}]", .{err});
        return true;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(FileManager);
}

test "file manager makes the holding folder's URL, percent-encoding what is not plain, on POSIX and Windows" {
    const allocator = std.testing.allocator;
    const posix = try FileManager.folderUrlAlloc(allocator, "/home/a b/café/x.tar", false);
    defer allocator.free(posix);
    try std.testing.expectEqualStrings("file:///home/a%20b/caf%C3%A9", posix);
    const windows = try FileManager.folderUrlAlloc(allocator, "C:\\Users\\a,b\\x.tar", true);
    defer allocator.free(windows);
    try std.testing.expectEqualStrings("file:///C:/Users/a%2Cb", windows);
    const drive_root = try FileManager.folderUrlAlloc(allocator, "C:\\a,b.txt", true);
    defer allocator.free(drive_root);
    try std.testing.expectEqualStrings("file:///C:/", drive_root);
    const posix_root = try FileManager.folderUrlAlloc(allocator, "/x.tar", false);
    defer allocator.free(posix_root);
    try std.testing.expectEqualStrings("file:///", posix_root);
}
