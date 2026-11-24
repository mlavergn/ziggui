//! One running copy of an app: an OS file lock, and a way for a second
//! launch to bring the first forward.

const std = @import("std");
const log = std.log.scoped(.ziggui_app_instance);
const mod = @import("module.zig");

/// What `AppInstance.claim` found.
pub const AppInstanceClaim = union(enum) {
    const Self = @This();

    /// This process is the app's running copy, until `release`.
    claimed,
    /// Another process is: its id, or null when it cannot be read (it has
    /// not written it yet, or, on Windows, its lock covers the file).
    running: ?i32,
};

/// One running copy of an app, however it was launched: from the Dock, a
/// terminal, or another copy of the bundle. The lock is an exclusive OS lock
/// (`flock`, `LockFileEx`) on `<directory>/<name>.lock`, holding the owner's
/// process id; the OS lets it go when the process ends, a crash included,
/// so nothing is ever stale. Claim it before the app does its own start-up
/// (opening files, `App.run`); on `.running`, `activate` the other and exit.
///
/// `directory` is the app's choice, read from the environment in `main`. Use
/// a folder only this user can write: `TMPDIR` on macOS (per user), and on
/// Linux `XDG_RUNTIME_DIR` (per user, `0700`) before `TMPDIR`. In a shared
/// `/tmp` another user could hold the lock and keep the app from starting.
/// A lock file that cannot be opened (another user's in a shared `/tmp`),
/// or that is a symbolic link (never followed: the id written would land in
/// whatever it points at), claims, logged, rather than keep the app from
/// starting.
pub const AppInstance = struct {
    const Self = @This();

    /// The signal `activate` sends (POSIX). Its default action is to be
    /// ignored, so a process that is not this app (a reused id) is never
    /// killed by it. Windows has no such signal.
    pub const activation_signal = if (mod.os_tag == .windows) {} else std.posix.SIG.URG;

    /// Allocator for the path; outlives the value.
    allocator: std.mem.Allocator,
    /// IO interface for the lock file.
    io: std.Io,
    /// The lock file, owned.
    path: []u8,
    /// The lock file, open and locked while this process holds it.
    file: ?std.Io.File = null,

    /// Names the lock; nothing is opened yet.
    ///
    /// - `allocator`: allocator for the path.
    /// - `io`: IO interface for the lock file.
    /// - `directory`: the directory the lock goes in, absolute (the temporary directory).
    /// - `name`: the app's name for its lock (its executable's, say).
    /// - Returns: the instance, unclaimed; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, name: []const u8) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const path = try allocator.print("{s}/{s}.lock", .{ std.mem.trimEnd(u8, directory, "/\\"), name });
        const self = Self{ .allocator = allocator, .io = io, .path = path };
        return self;
    }

    /// Lets the lock go, if held, and frees the path.
    ///
    /// - `self`: the instance.
    pub fn deinit(self: *Self) void {
        self.release();
        self.allocator.free(self.path);
    }

    /// Takes the lock, unless another process holds it. Holding it, this
    /// process writes its id into the file and catches `activation_signal`,
    /// which sets `App.activation_requested`, so the loop shows the window.
    ///
    /// - `self`: the instance.
    /// - Returns: `.claimed`, or `.running` with the other process's id.
    pub fn claim(self: *Self) AppInstanceClaim {
        if (self.file != null) return .claimed;
        if (std.Io.Dir.path.dirname(self.path)) |directory| std.Io.Dir.cwd().createDirPath(self.io, directory) catch |err| {
            log.info("cannot create {s} [{t}]", .{ directory, err });
        };
        // A link planted where the lock goes would have `writeId` overwrite
        // its target; the check and the open are not one step, so a folder
        // only this user writes (see above) is what keeps it out.
        if (std.Io.Dir.cwd().statFile(self.io, self.path, .{ .follow_symlinks = false })) |stat| {
            if (stat.kind == .sym_link) {
                log.warn("{s} is a link, so another copy may run", .{self.path});
                return .claimed;
            }
        } else |err| if (err != error.FileNotFound) log.info("cannot inspect {s} [{t}]", .{ self.path, err });
        const file = std.Io.Dir.createFileAbsolute(self.io, self.path, .{ .read = true, .truncate = false }) catch |err| {
            log.warn("cannot open {s}, so another copy may run [{t}]", .{ self.path, err });
            return .claimed;
        };
        const locked = file.tryLock(self.io, .exclusive) catch |err| {
            log.warn("cannot lock {s}, so another copy may run [{t}]", .{ self.path, err });
            file.close(self.io);
            return .claimed;
        };
        if (!locked) {
            defer file.close(self.io);
            return .{ .running = self.holder(file) };
        }

        self.file = file;
        self.writeId(file);
        Self.catchActivation();
        return .claimed;
    }

    /// Lets the lock go, if held, emptied first, so a launch that locks it
    /// next never reads this process's id as its own holder's. The file
    /// stays: removed, a launch that had opened it could lock the old file
    /// while the next locks a new one.
    ///
    /// - `self`: the instance.
    pub fn release(self: *Self) void {
        const file = self.file orelse return;
        self.file = null;
        file.setLength(self.io, 0) catch |err| log.info("cannot empty {s} [{t}]", .{ self.path, err });
        file.unlock(self.io);
        file.close(self.io);
    }

    /// Brings the app's running copy forward: on macOS AppKit activates it
    /// (`Cocoa.activateProcess`), and on POSIX it is sent
    /// `activation_signal`, so it shows a window hidden to the tray too.
    /// Windows does nothing yet.
    ///
    /// - `pid`: the running copy (`AppInstanceClaim.running`).
    pub fn activate(pid: i32) void {
        if (pid <= 0 or mod.os_tag == .windows) return;
        if (mod.os_tag == .macos and !mod.Cocoa.activateProcess(pid)) log.info("AppKit did not activate process {d}", .{pid});
        std.posix.kill(pid, activation_signal) catch |err| log.info("cannot signal process {d} [{t}]", .{ pid, err });
    }

    /// This process's id.
    ///
    /// - Returns: the id.
    pub fn processId() i32 {
        if (mod.os_tag == .windows) return @intCast(std.os.windows.GetCurrentProcessId());
        return @intCast(std.c.getpid());
    }

    /// The process id a lock file holds; a failed read is logged.
    ///
    /// - `self`: the instance.
    /// - `file`: the lock file, open for reading.
    /// - Returns: the id, or null when there is none to read (always on
    ///   Windows, whose lock covers the file's bytes).
    fn holder(self: *const Self, file: std.Io.File) ?i32 {
        if (mod.os_tag == .windows) return null;
        var buffer: [32]u8 = undefined;
        const length = file.readPositionalAll(self.io, &buffer, 0) catch |err| {
            log.info("cannot read {s} [{t}]", .{ self.path, err });
            return null;
        };
        const id = std.fmt.parseInt(i32, std.mem.trim(u8, buffer[0..length], " \r\n"), 10) catch return null;
        return if (id > 0) id else null;
    }

    /// Writes this process's id over the lock file's contents; a failure is
    /// logged, since the lock holds without it.
    ///
    /// - `self`: the instance.
    /// - `file`: the lock file, locked.
    fn writeId(self: *const Self, file: std.Io.File) void {
        var buffer: [16]u8 = undefined;
        const text = std.mem.print(&buffer, "{d}\n", .{Self.processId()}) catch |err| return log.info("cannot write {s} [{t}]", .{ self.path, err });
        file.setLength(self.io, 0) catch |err| return log.info("cannot empty {s} [{t}]", .{ self.path, err });
        file.writePositionalAll(self.io, text, 0) catch |err| log.info("cannot write {s} [{t}]", .{ self.path, err });
    }

    /// Catches `activation_signal` (POSIX), setting `App.activation_requested`;
    /// a system call the signal lands in restarts (`SA_RESTART`) rather than
    /// failing with `EINTR` in code that does not retry (C libraries).
    fn catchActivation() void {
        if (mod.os_tag == .windows) return;
        const action: std.posix.Sigaction = .{ .handler = .{ .handler = Self.onActivationSignal }, .mask = std.posix.sigemptyset(), .flags = std.posix.SA.RESTART };
        std.posix.sigaction(activation_signal, &action, null);
    }

    /// The signal handler: only sets the flag, which is all a handler may safely do.
    ///
    /// - `signal`: the signal caught.
    fn onActivationSignal(signal: std.posix.SIG) callconv(.c) void {
        _ = signal;
        mod.App.shared().activation_requested.store(true, .release);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(AppInstance);
}

test "app instance claims once, names its holder, and lets go" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(directory);

    var first = try AppInstance.init(allocator, io, directory, "probe");
    defer first.deinit();
    try std.testing.expectEqual(AppInstanceClaim.claimed, first.claim());
    // Claiming what it holds is no change.
    try std.testing.expectEqual(AppInstanceClaim.claimed, first.claim());

    // A second lock on the file (as another launch would take) is refused,
    // and reads the holder's id where the platform lets it.
    var second = try AppInstance.init(allocator, io, directory, "probe");
    defer second.deinit();
    const found = second.claim();
    try std.testing.expect(found == .running);
    if (mod.os_tag != .windows) try std.testing.expectEqual(@as(?i32, AppInstance.processId()), found.running);
    // Another name is another app.
    var other = try AppInstance.init(allocator, io, directory, "other");
    defer other.deinit();
    try std.testing.expectEqual(AppInstanceClaim.claimed, other.claim());

    first.release();
    try std.testing.expectEqual(AppInstanceClaim.claimed, second.claim());
}

test "app instance never follows a link where its lock goes, and empties the lock as it lets go" {
    if (mod.os_tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(directory);
    try temporary.dir.writeFile(io, .{ .sub_path = "victim", .data = "keep me" });
    try temporary.dir.symLink(io, "victim", "linked.lock", .{});

    var linked = try AppInstance.init(allocator, io, directory, "linked");
    defer linked.deinit();
    try std.testing.expectEqual(AppInstanceClaim.claimed, linked.claim());
    try std.testing.expect(linked.file == null);
    const victim = try temporary.dir.readFileAlloc(io, "victim", allocator, .limited(64));
    defer allocator.free(victim);
    try std.testing.expectEqualStrings("keep me", victim);

    var held = try AppInstance.init(allocator, io, directory, "held");
    defer held.deinit();
    try std.testing.expectEqual(AppInstanceClaim.claimed, held.claim());
    held.release();
    const left = try temporary.dir.readFileAlloc(io, "held.lock", allocator, .limited(64));
    defer allocator.free(left);
    try std.testing.expectEqualStrings("", left);
}

test "app instance activating a gone process does nothing" {
    // No process has an id this large on macOS or Linux.
    AppInstance.activate(99999999);
    AppInstance.activate(0);
}
