//! What a `FileBrowser` shows: one local folder's entries, the one selected,
//! and whether hidden names are shown.

const std = @import("std");
const log = std.log.scoped(.ziggui_file_browser_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a `FileNode` is.
pub const FileNodeKind = enum {
    const Self = @This();

    /// A folder, which `FileBrowserState.enter` opens.
    directory,
    /// A regular file.
    file,
};

/// One entry of the folder on show.
pub const FileNode = struct {
    const Self = @This();

    /// Its name in the folder; owned by the state's listing.
    name: []const u8,
    /// A folder or a file; a link counts as what it points at.
    kind: FileNodeKind,
    /// A file's size in bytes; zero for a folder.
    size: u64,
    /// Whether the name starts with a dot.
    hidden: bool,
};

/// One folder listing: run off the UI thread when the `Io` can run work
/// concurrently, in place otherwise. Everything it makes lives in its arena,
/// which the state adopts when the listing lands (`FileBrowserState.poll`).
const FolderListing = struct {
    const Self = @This();

    /// Allocates the listing itself and backs its arena.
    allocator: std.mem.Allocator,
    /// Owns the path, the name to select and the entries.
    arena: std.heap.ArenaAllocator,
    /// The IO interface the folder is read through.
    io: std.Io,
    /// The folder as asked for; made absolute as it is read.
    path: []const u8,
    /// The entry to select once listed, by name; null for none.
    selected_name: ?[]const u8,
    /// The folder, absolute, once read.
    absolute: []const u8 = "",
    /// The folder's entries, once read.
    nodes: []const FileNode = &.{},
    /// Why the folder could not be read, or null.
    failure: ?anyerror = null,
    /// Set, last, when the listing has finished: the UI thread reads the
    /// fields above only after it sees this.
    done: std.atomic.Value(bool) = .init(false),

    /// Makes a listing of `path`, selecting `selected_name` once listed.
    ///
    /// - `allocator`: allocates the listing and backs its arena.
    /// - `io`: the IO interface the folder is read through.
    /// - `path`: the folder; copied.
    /// - `selected_name`: the entry to select, by name; copied; null for none.
    /// - Returns: the listing, on the heap; propagates allocation failure.
    fn create(allocator: std.mem.Allocator, io: std.Io, path: []const u8, selected_name: ?[]const u8) std.mem.Allocator.Error!*Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.* = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .io = io, .path = "", .selected_name = null };
        errdefer self.arena.deinit();
        self.path = try self.arena.allocator().dupe(u8, path);
        if (selected_name) |name| self.selected_name = try self.arena.allocator().dupe(u8, name);
        return self;
    }

    /// Frees the listing and its arena.
    ///
    /// - `self`: the listing.
    fn destroy(self: *Self) void {
        self.arena.deinit();
        self.allocator.destroy(self);
    }

    /// Frees the listing but not its arena, which the state has adopted.
    ///
    /// - `self`: the listing.
    fn release(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Reads the folder, recording the entries or why it could not, then
    /// marks the listing done. The task a concurrent listing runs.
    ///
    /// - `self`: the listing.
    fn run(self: *Self) void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        self.read() catch |err| {
            self.failure = err;
        };
        self.done.store(true, .release);
        // An idle window draws nothing until an event: this one asks for the
        // frame whose `FileBrowser` adopts the listing.
        mod.FrameClock.shared().wake();
    }

    /// Resolves the folder and reads its entries into the arena.
    ///
    /// - `self`: the listing.
    /// - Returns: nothing; propagates an error resolving or reading the folder.
    fn read(self: *Self) !void {
        self.absolute = try std.Io.Dir.cwd().realPathFileAlloc(self.io, self.path, self.arena.allocator());
        self.nodes = try self.list();
    }

    /// Reads a folder's entries, folders first, each group by name; anything
    /// but a folder or a regular file, or an entry that cannot be read, is left
    /// out. Folders cost no stat, files and links one each.
    ///
    /// - `self`: the listing, its `absolute` folder resolved; the entries
    ///   and their names go in its arena.
    /// - Returns: the entries; propagates an error opening or reading the folder.
    fn list(self: *Self) ![]const FileNode {
        const arena = self.arena.allocator();
        var directory = try std.Io.Dir.cwd().openDir(self.io, self.absolute, .{ .iterate = true });
        defer directory.close(self.io);
        var nodes: std.ArrayList(FileNode) = .empty;
        var entries = directory.iterate();
        while (try entries.next(self.io)) |entry| {
            // The listing already says what most entries are: a folder needs no
            // stat at all, a file one for its size, and only a link (or an
            // entry the file system leaves unknown) one to learn what it is.
            if (entry.kind == .directory) {
                try nodes.append(arena, .{ .name = try arena.dupe(u8, entry.name), .kind = .directory, .size = 0, .hidden = Self.isHidden(entry.name) });
                continue;
            }
            if (entry.kind != .file and entry.kind != .sym_link and entry.kind != .unknown) continue;
            const stat = directory.statFile(self.io, entry.name, .{}) catch continue;
            const kind: FileNodeKind = switch (stat.kind) {
                .directory => .directory,
                .file => .file,
                else => continue,
            };
            try nodes.append(arena, .{
                .name = try arena.dupe(u8, entry.name),
                .kind = kind,
                .size = if (kind == .file) stat.size else 0,
                .hidden = Self.isHidden(entry.name),
            });
        }
        std.mem.sortUnstable(FileNode, nodes.items, {}, Self.before);
        return nodes.toOwnedSlice(arena);
    }

    /// Whether a name is hidden: it starts with a dot.
    ///
    /// - `name`: an entry's name.
    /// - Returns: true for a dot name.
    fn isHidden(name: []const u8) bool {
        return name.len > 0 and name[0] == '.';
    }

    /// Folders before files, then by name, case aside.
    ///
    /// - `left`: an entry.
    /// - `right`: another entry.
    /// - Returns: whether `left` lists before `right`.
    fn before(_: void, left: FileNode, right: FileNode) bool {
        if (left.kind != right.kind) return left.kind == .directory;
        return std.ascii.lessThanIgnoreCase(left.name, right.name);
    }
};

/// A `FileBrowser`'s folder, listed through `std.Io`: its path, its entries
/// (folders first, then files, each by name, case aside), the selected one,
/// and whether hidden (dot) names show. App-owned, so it survives frames; keep
/// it at a stable address, since the browser's taps point back at it. Opening
/// a folder that cannot be read keeps the one on show and sets `failure`.
///
/// A folder is read off the UI thread when the `Io` can run work concurrently
/// (`Io.concurrent`), so a large or slow folder never stalls the window: the
/// browser shows the folder it had until the listing lands, which `poll`
/// (called by `FileBrowser` as it builds) adopts. A landed listing wakes the
/// window (`FrameClock.wake`), so the app needs no busy check for it. An `Io`
/// that cannot (`Io.Threaded.global_single_threaded`) lists in place, at once.
pub const FileBrowserState = struct {
    const Self = @This();

    /// Where the path and the state live.
    allocator: std.mem.Allocator,
    /// The IO interface the folders are read through.
    io: std.Io,
    /// The folder on show, absolute; owned.
    path: std.ArrayList(u8) = .empty,
    /// Owns `nodes` and their names; replaced by every listing.
    arena: std.heap.ArenaAllocator,
    /// The folder's entries, in order.
    nodes: []const FileNode = &.{},
    /// The selected entry, an index into `nodes`; null for none.
    selection: ?usize = null,
    /// Whether hidden names show; the browser's toggle binds to it.
    show_hidden: renderer.State(bool),
    /// Why the last `open` failed, or null when it listed.
    failure: ?anyerror = null,
    /// The list's scroll offset.
    scroll: mod.ScrollState = .{},
    /// The listing under way, if any; adopted by `poll` when it lands.
    listing: ?*FolderListing = null,
    /// The listing's task while it runs concurrently; null when it ran in place.
    future: ?std.Io.Future(void) = null,
    /// A folder asked for while a listing ran: started, in its place, once
    /// that one lands.
    queued: ?*FolderListing = null,

    /// No folder yet: `open` lists one.
    ///
    /// - `allocator`: where the path and the listing live.
    /// - `io`: the IO interface folders are read through.
    /// - Returns: the state.
    pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator, .io = io, .arena = std.heap.ArenaAllocator.init(allocator), .show_hidden = renderer.State(bool).init(allocator, false) };
        return self;
    }

    /// Stops any listing under way, then frees the path and the listing.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        if (self.future) |*future| future.cancel(self.io);
        if (self.listing) |listing| listing.destroy();
        if (self.queued) |queued| queued.destroy();
        self.show_hidden.deinit();
        self.arena.deinit();
        self.path.deinit(self.allocator);
    }

    /// Lists `path` and shows it, with nothing selected: at once with an
    /// `Io` that cannot run work concurrently, else when the listing lands
    /// (`poll`). Asked while a listing runs, it lists next.
    ///
    /// - `self`: the state.
    /// - `path`: the folder; made absolute against the working directory.
    /// - Returns: nothing; on a folder that cannot be read the one on show
    /// stays and `failure` says why; propagates allocation failure.
    pub fn open(self: *Self, path: []const u8) std.mem.Allocator.Error!void {
        try self.request(path, null);
    }

    /// Lists the folder on show again, keeping the selection on the same name.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; as `open`.
    pub fn refresh(self: *Self) std.mem.Allocator.Error!void {
        try self.request(self.path.items, if (self.selected()) |node| node.name else null);
    }

    /// Opens the folder above the one on show, selecting the one left.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; a no-op at the root; as `open`.
    pub fn up(self: *Self) std.mem.Allocator.Error!void {
        const parent = std.Io.Dir.path.dirname(self.path.items) orelse return;
        try self.request(parent, std.Io.Dir.path.basename(self.path.items));
    }

    /// Opens the selected folder.
    ///
    /// - `self`: the state.
    /// - Returns: whether a folder was selected (and so opened or refused); as `open`.
    pub fn enter(self: *Self) std.mem.Allocator.Error!bool {
        const node = self.selected() orelse return false;
        if (node.kind != .directory) return false;
        const target = try std.Io.Dir.path.join(self.allocator, &.{ self.path.items, node.name });
        defer self.allocator.free(target);
        try self.request(target, null);
        return true;
    }

    /// Adopts a listing that has landed: its folder shows, or, if it could
    /// not be read, `failure` says why. `FileBrowser` calls it as it builds.
    ///
    /// - `self`: the state.
    /// - Returns: whether a listing landed.
    pub fn poll(self: *Self) bool {
        const listing = self.listing orelse return false;
        if (!listing.done.load(.acquire)) return false;
        if (self.future) |*future| future.await(self.io);
        self.future = null;
        self.listing = null;
        // A newer folder was asked for meanwhile: this one is out of date.
        if (self.queued) |next| {
            self.queued = null;
            listing.destroy();
            self.start(next);
            return true;
        }
        self.adopt(listing);
        return true;
    }

    /// Whether a folder is being listed (a "Loading…" an app may show).
    ///
    /// - `self`: the state.
    /// - Returns: true while a listing runs.
    pub fn loading(self: *const Self) bool {
        return self.listing != null;
    }

    /// Blocks until every listing asked for has landed, and adopts it: for
    /// tests, and for a first folder that must show in the first frame.
    ///
    /// - `self`: the state.
    pub fn wait(self: *Self) void {
        while (self.listing) |listing| {
            if (self.future) |*future| future.await(self.io);
            std.debug.assert(listing.done.load(.acquire));
            _ = self.poll();
        }
    }

    /// Selects entry `index`; out of range clears the selection.
    ///
    /// - `self`: the state.
    /// - `index`: an index into `nodes`.
    pub fn select(self: *Self, index: usize) void {
        self.selection = if (index < self.nodes.len) index else null;
    }

    /// Moves the selection by `delta` shown entries, skipping hidden ones while they are hidden.
    ///
    /// - `self`: the state.
    /// - `delta`: entries to move; negative moves up.
    pub fn move(self: *Self, delta: isize) void {
        if (self.nodes.len == 0) return;
        var index: isize = if (self.selection) |at| @intCast(at) else if (delta > 0) -1 else @intCast(self.nodes.len);
        var steps = @abs(delta);
        const step: isize = if (delta < 0) -1 else 1;
        var landed: ?usize = self.selection;
        while (steps > 0) {
            index += step;
            if (index < 0 or index >= @as(isize, @intCast(self.nodes.len))) break;
            if (!self.shows(self.nodes[@intCast(index)])) continue;
            landed = @intCast(index);
            steps -= 1;
        }
        self.selection = landed;
    }

    /// The selected entry.
    ///
    /// - `self`: the state.
    /// - Returns: the entry, or null when none is selected or it is hidden.
    pub fn selected(self: *const Self) ?FileNode {
        const index = self.selection orelse return null;
        const node = self.nodes[index];
        return if (self.shows(node)) node else null;
    }

    /// The selected entry's path, or the folder on show's when none is selected.
    ///
    /// - `self`: the state.
    /// - `allocator`: owns the result.
    /// - Returns: the path and what it is; propagates allocation failure.
    pub fn pickAlloc(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!struct { path: []u8, kind: FileNodeKind } {
        const node = self.selected() orelse return .{ .path = try allocator.dupe(u8, self.path.items), .kind = .directory };
        return .{ .path = try std.Io.Dir.path.join(allocator, &.{ self.path.items, node.name }), .kind = node.kind };
    }

    /// Whether an entry shows under the hidden-names setting.
    ///
    /// - `self`: the state.
    /// - `node`: the entry.
    /// - Returns: true when it shows.
    pub fn shows(self: *const Self, node: FileNode) bool {
        return !node.hidden or self.show_hidden.get();
    }

    /// Lists `path` next, selecting `selected_name` once listed: now, or once the
    /// listing under way lands (replacing any folder already waiting).
    ///
    /// - `self`: the state.
    /// - `path`: the folder; copied.
    /// - `selected_name`: the entry to select, by name; copied; null for none.
    /// - Returns: nothing; propagates allocation failure.
    fn request(self: *Self, path: []const u8, selected_name: ?[]const u8) std.mem.Allocator.Error!void {
        const listing = try FolderListing.create(self.allocator, self.io, path, selected_name);
        if (self.listing != null) {
            if (self.queued) |stale| stale.destroy();
            self.queued = listing;
            return;
        }
        self.start(listing);
    }

    /// Runs `listing`: concurrently when the `Io` can, else in place and
    /// adopted at once.
    ///
    /// - `self`: the state.
    /// - `listing`: the listing to run; the state owns it from here.
    fn start(self: *Self, listing: *FolderListing) void {
        self.listing = listing;
        self.future = self.io.concurrent(FolderListing.run, .{listing}) catch |err| switch (err) {
            error.ConcurrencyUnavailable => blk: {
                listing.run();
                break :blk null;
            },
        };
        if (self.future == null) _ = self.poll();
    }

    /// Shows a landed listing, or records why it could not be read and keeps
    /// the folder on show.
    ///
    /// - `self`: the state.
    /// - `listing`: the listing; freed, its arena kept when adopted.
    fn adopt(self: *Self, listing: *FolderListing) void {
        const failure: ?anyerror = listing.failure orelse failed: {
            self.path.ensureTotalCapacity(self.allocator, listing.absolute.len) catch |err| break :failed err;
            break :failed null;
        };
        if (failure) |err| {
            self.failure = err;
            listing.destroy();
            return;
        }
        self.path.clearRetainingCapacity();
        self.path.appendSliceAssumeCapacity(listing.absolute);
        self.arena.deinit();
        self.arena = listing.arena;
        self.nodes = listing.nodes;
        self.selection = null;
        if (listing.selected_name) |name| {
            for (self.nodes, 0..) |node, index| {
                if (std.mem.eql(u8, node.name, name)) self.selection = index;
            }
        }
        self.failure = null;
        self.scroll.offset = 0;
        listing.release();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(FileBrowserState);
}

test "a file browser state lists folders first, moves past hidden names, and opens and leaves folders" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "photos/deep");
    try temporary.dir.writeFile(io, .{ .sub_path = "photos/b.txt", .data = "bb" });
    try temporary.dir.writeFile(io, .{ .sub_path = "photos/A.txt", .data = "a" });
    try temporary.dir.writeFile(io, .{ .sub_path = "photos/.hidden", .data = "h" });
    try temporary.dir.writeFile(io, .{ .sub_path = "photos/deep/c.txt", .data = "ccc" });
    const root = try temporary.dir.realPathFileAlloc(io, "photos", allocator);
    defer allocator.free(root);

    var state = FileBrowserState.init(allocator, io);
    defer state.deinit();
    try state.open(root);
    // The testing `Io` runs work concurrently: the listing is under way, the
    // old (empty) folder still on show, until it lands.
    try std.testing.expect(state.loading());
    state.wait();
    try std.testing.expect(!state.loading());
    try std.testing.expectEqualStrings(root, state.path.items);
    try std.testing.expectEqual(@as(usize, 4), state.nodes.len);
    try std.testing.expectEqualStrings("deep", state.nodes[0].name);
    try std.testing.expectEqual(FileNodeKind.directory, state.nodes[0].kind);
    try std.testing.expectEqualStrings(".hidden", state.nodes[1].name);
    try std.testing.expectEqualStrings("A.txt", state.nodes[2].name);
    try std.testing.expectEqual(@as(u64, 2), state.nodes[3].size);

    // Hidden names are stepped over while hidden.
    state.move(1);
    try std.testing.expectEqualStrings("deep", state.selected().?.name);
    state.move(1);
    try std.testing.expectEqualStrings("A.txt", state.selected().?.name);
    state.show_hidden.set(true);
    state.move(-1);
    try std.testing.expectEqualStrings(".hidden", state.selected().?.name);

    // A file is not entered; a folder is, and up comes back to it.
    state.select(2);
    try std.testing.expect(!try state.enter());
    const file = try state.pickAlloc(allocator);
    defer allocator.free(file.path);
    try std.testing.expectEqual(FileNodeKind.file, file.kind);
    try std.testing.expect(std.mem.endsWith(u8, file.path, "A.txt"));
    state.select(0);
    try std.testing.expect(try state.enter());
    state.wait();
    try std.testing.expectEqual(@as(usize, 1), state.nodes.len);
    try state.up();
    state.wait();
    try std.testing.expectEqualStrings(root, state.path.items);
    try std.testing.expectEqualStrings("deep", state.selected().?.name);

    // A folder that cannot be read keeps the one on show.
    try state.open("does-not-exist-anywhere");
    state.wait();
    try std.testing.expect(state.failure != null);
    try std.testing.expectEqualStrings(root, state.path.items);
}

test "a folder asked for while another lists replaces it, and in-place listing needs no wait" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "first");
    try temporary.dir.createDirPath(io, "second/inner");
    const first = try temporary.dir.realPathFileAlloc(io, "first", allocator);
    defer allocator.free(first);
    const second = try temporary.dir.realPathFileAlloc(io, "second", allocator);
    defer allocator.free(second);

    var state = FileBrowserState.init(allocator, io);
    defer state.deinit();
    try state.open(first);
    try state.open(second);
    state.wait();
    try std.testing.expectEqualStrings(second, state.path.items);
    try std.testing.expectEqualStrings("inner", state.nodes[0].name);

    // An `Io` without concurrency lists in place: shown at once.
    var inline_state = FileBrowserState.init(allocator, std.Io.Threaded.global_single_threaded.io());
    defer inline_state.deinit();
    try inline_state.open(second);
    try std.testing.expect(!inline_state.loading());
    try std.testing.expectEqualStrings(second, inline_state.path.items);
}

test "a listing still running when the state goes is stopped and freed" {
    const allocator = std.testing.allocator;
    var state = FileBrowserState.init(allocator, std.testing.io);
    try state.open(".");
    state.deinit();
}

test "a listing that lands off the UI thread wakes the window" {
    const Waker = struct {
        const Self = @This();
        var wakes: std.atomic.Value(u32) = .init(0);
        fn wake() void {
            _ = wakes.fetchAdd(1, .monotonic);
        }
    };
    const clock = mod.FrameClock.shared();
    clock.setWakeHandler(Waker.wake);
    defer clock.setWakeHandler(null);
    var state = FileBrowserState.init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    try state.open(".");
    state.wait();
    try std.testing.expect(Waker.wakes.load(.monotonic) >= 1);
}
