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
    /// Whether to select the ".." row once listed instead (a refresh while it
    /// was selected).
    select_parent: bool = false,
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

/// What a `FileBrowser` picks: a path and what it is.
pub const FilePick = struct {
    const Self = @This();

    /// The path; owned by the allocator `pickAlloc` was handed.
    path: []u8,
    /// A folder or a file.
    kind: FileNodeKind,
};

/// A `FileBrowser`'s folder, listed through `std.Io`: its path, its entries
/// (folders first, then files, each by name, case aside), the selected one,
/// whether hidden (dot) names show, and which files show (`shows_file`). Below
/// any folder but the root, the rows start with "..", the enclosing folder:
/// selected, moved onto and entered as an entry is, though it is not one of
/// `nodes`. App-owned, so it survives frames; keep it at a stable address,
/// since the browser's taps point back at it. Opening a folder that cannot be
/// read keeps the one on show and sets `failure`.
///
/// A folder is read off the UI thread when the `Io` can run work concurrently
/// (`Io.concurrent`), so a large or slow folder never stalls the window: the
/// browser shows the folder it had until the listing lands, which `poll`
/// (called by `FileBrowser` as it builds) adopts. A landed listing wakes the
/// window (`FrameClock.wake`), so the app needs no busy check for it. An `Io`
/// that cannot (`Io.Threaded.global_single_threaded`) lists in place, at once.
pub const FileBrowserState = struct {
    const Self = @This();

    /// The height of a browser row, in points: a `SelectableRow`'s.
    pub const row_height: f32 = 28;

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
    /// The selected entry, an index into `nodes`; null for none (and while
    /// the ".." row is selected).
    selection: ?usize = null,
    /// Whether the ".." row is selected; `selection` is null while it is.
    parent_selected: bool = false,
    /// Whether hidden names show; the browser's toggle binds to it.
    show_hidden: renderer.State(bool),
    /// Why the last `open` failed, or null when it listed.
    failure: ?anyerror = null,
    /// Which files show, by name (a document picker's types); null shows
    /// every file. Folders always show, so the user can reach the files.
    ///
    /// - `name`: the file's name.
    /// - Returns: true when it shows.
    shows_file: ?*const fn (name: []const u8) bool = null,
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
        try self.request(path, null, false);
    }

    /// Lists the folder on show again, keeping the selection on the same name
    /// (or on "..").
    ///
    /// - `self`: the state.
    /// - Returns: nothing; as `open`.
    pub fn refresh(self: *Self) std.mem.Allocator.Error!void {
        try self.request(self.path.items, if (self.selected()) |node| node.name else null, self.parent_selected);
    }

    /// Opens the folder above the one on show, selecting the one left.
    ///
    /// - `self`: the state.
    /// - Returns: nothing; a no-op at the root; as `open`.
    pub fn up(self: *Self) std.mem.Allocator.Error!void {
        const parent = std.Io.Dir.path.dirname(self.path.items) orelse return;
        try self.request(parent, std.Io.Dir.path.basename(self.path.items), false);
    }

    /// Opens the selected folder, or the enclosing one when ".." is selected.
    ///
    /// - `self`: the state.
    /// - Returns: whether a folder was selected (and so opened or refused); as `open`.
    pub fn enter(self: *Self) std.mem.Allocator.Error!bool {
        if (self.parent_selected) {
            try self.up();
            return true;
        }
        const node = self.selected() orelse return false;
        if (node.kind != .directory) return false;
        const target = try std.Io.Dir.path.join(self.allocator, &.{ self.path.items, node.name });
        defer self.allocator.free(target);
        try self.request(target, null, false);
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
        self.parent_selected = false;
    }

    /// Selects the ".." row; a no-op at the root, which has none.
    ///
    /// - `self`: the state.
    pub fn selectParent(self: *Self) void {
        if (!self.hasParent()) return;
        self.selection = null;
        self.parent_selected = true;
    }

    /// Whether the folder on show has an enclosing one, and so a ".." row.
    ///
    /// - `self`: the state.
    /// - Returns: false at the root and before a folder is listed.
    pub fn hasParent(self: *const Self) bool {
        return std.Io.Dir.path.dirname(self.path.items) != null;
    }

    /// Moves the selection by `delta` rows, the ".." row first, skipping the
    /// entries that do not show (`shows`), and scrolls it into view. With
    /// nothing selected, a move down starts at the first row, a move up at
    /// the last.
    ///
    /// - `self`: the state.
    /// - `delta`: rows to move; negative moves up.
    pub fn move(self: *Self, delta: isize) void {
        // Rows by entry index: -1 is "..", -2 before every row.
        const first: isize = if (self.hasParent()) -1 else 0;
        const count: isize = @intCast(self.nodes.len);
        if (count == 0 and first == 0) return;
        var index: isize = if (self.parent_selected) -1 else if (self.selection) |at| @intCast(at) else if (delta > 0) first - 1 else count;
        var steps = @abs(delta);
        const step: isize = if (delta < 0) -1 else 1;
        var landed: ?isize = if (self.parent_selected) -1 else if (self.selection) |at| @intCast(at) else null;
        while (steps > 0) {
            index += step;
            if (index < first or index >= count) break;
            if (index >= 0 and !self.shows(self.nodes[@intCast(index)])) continue;
            landed = index;
            steps -= 1;
        }
        const row = landed orelse return;
        if (row < 0) self.selectParent() else self.select(@intCast(row));
        if (self.selectedRow()) |position| self.scroll.reveal(position, row_height);
    }

    /// Handles a key pressed while the browser has the keyboard: ↑/↓ move,
    /// Page Up/Page Down move a page, Home/End go to the first and last rows,
    /// Return, → and ⌘↓ (Ctrl+↓ off macOS) open the selected folder (".."
    /// goes up), Backspace, ← and ⌘↑ (Ctrl+↑) open the enclosing folder, and
    /// a letter or digit selects the next entry starting with it. A key with
    /// any other modifier (Alt; Ctrl on macOS, where ⌃↑ is Mission Control;
    /// the Windows key elsewhere) is left to the app. The app forwards
    /// key-downs while the browser is focused and no text field is.
    ///
    /// - `self`: the state.
    /// - `keycode`: the key's `SDL_Keycode` (`SdlKey`).
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - `mac`: whether the command key is ⌘ (macOS) rather than Ctrl.
    /// - Returns: whether the browser used the key (Return on a file is left
    ///   to the app, which may take it as the pick); propagates allocation failure.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16, mac: bool) std.mem.Allocator.Error!bool {
        const command_mask = if (mac) mod.SdlKey.gui_mask else mod.SdlKey.ctrl_mask;
        const other_mask = mod.SdlKey.alt_mask | (if (mac) mod.SdlKey.ctrl_mask else mod.SdlKey.gui_mask);
        if (modifiers & other_mask != 0) return false;
        const command = modifiers & command_mask != 0;
        // More rows than there are, so Home and End reach the ends.
        const every_row: isize = @intCast(self.nodes.len + 1);
        switch (keycode) {
            mod.SdlKey.up_arrow => if (command) return self.leave() else self.move(-1),
            mod.SdlKey.down_arrow => if (command) return self.enter() else self.move(1),
            mod.SdlKey.page_up => self.move(-self.pageRows()),
            mod.SdlKey.page_down => self.move(self.pageRows()),
            mod.SdlKey.home => self.move(-every_row),
            mod.SdlKey.end => self.move(every_row),
            mod.SdlKey.enter, mod.SdlKey.keypad_enter, mod.SdlKey.right_arrow => return self.enter(),
            mod.SdlKey.backspace, mod.SdlKey.left_arrow => return self.leave(),
            else => {
                if (command or keycode > 0x7e or !std.ascii.isAlphanumeric(@intCast(keycode))) return false;
                return self.typeSelect(@intCast(keycode));
            },
        }
        return true;
    }

    /// Selects the next shown entry after the selection whose name starts
    /// with `character`, case aside, wrapping around to the first.
    ///
    /// - `self`: the state.
    /// - `character`: the letter or digit typed.
    /// - Returns: whether an entry starts with it.
    pub fn typeSelect(self: *Self, character: u8) bool {
        const count = self.nodes.len;
        const after: usize = if (self.selection) |at| at + 1 else 0;
        for (0..count) |step| {
            const index = (after + step) % count;
            const node = self.nodes[index];
            if (!self.shows(node) or node.name.len == 0) continue;
            if (std.ascii.toLower(node.name[0]) != std.ascii.toLower(character)) continue;
            self.select(index);
            if (self.selectedRow()) |row| self.scroll.reveal(row, row_height);
            return true;
        }
        return false;
    }

    /// The row the selection is drawn on, counting the ".." row and only the
    /// entries shown.
    ///
    /// - `self`: the state.
    /// - Returns: the row, or null when nothing shown is selected.
    pub fn selectedRow(self: *const Self) ?usize {
        if (self.parent_selected) return 0;
        const index = self.selection orelse return null;
        if (!self.shows(self.nodes[index])) return null;
        var row: usize = if (self.hasParent()) 1 else 0;
        for (self.nodes[0..index]) |node| {
            if (self.shows(node)) row += 1;
        }
        return row;
    }

    /// The selected entry.
    ///
    /// - `self`: the state.
    /// - Returns: the entry, or null when none is selected or it does not
    ///   show (hidden, or a file `shows_file` leaves out).
    pub fn selected(self: *const Self) ?FileNode {
        const index = self.selection orelse return null;
        const node = self.nodes[index];
        return if (self.shows(node)) node else null;
    }

    /// The selected entry's path, the enclosing folder's when ".." is
    /// selected, or the folder on show's when nothing is.
    ///
    /// A selection that does not show (`shows`) picks nothing, rather than
    /// the folder: a dotfile selected, then hidden, must not turn into the
    /// whole folder around it.
    ///
    /// - `self`: the state.
    /// - `allocator`: owns the result.
    /// - Returns: the pick, or null while the selection does not show;
    ///   propagates allocation failure.
    pub fn pickAlloc(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!?FilePick {
        if (self.parent_selected) {
            if (std.Io.Dir.path.dirname(self.path.items)) |parent| return .{ .path = try allocator.dupe(u8, parent), .kind = .directory };
        }
        const index = self.selection orelse return .{ .path = try allocator.dupe(u8, self.path.items), .kind = .directory };
        const node = self.nodes[index];
        if (!self.shows(node)) return null;
        return .{ .path = try std.Io.Dir.path.join(allocator, &.{ self.path.items, node.name }), .kind = node.kind };
    }

    /// Whether an entry shows under the hidden-names setting and, for a
    /// file, `shows_file`.
    ///
    /// - `self`: the state.
    /// - `node`: the entry.
    /// - Returns: true when it shows.
    pub fn shows(self: *const Self, node: FileNode) bool {
        if (node.hidden and !self.show_hidden.get()) return false;
        if (node.kind == .directory) return true;
        const shows_file = self.shows_file orelse return true;
        return shows_file(node.name);
    }

    /// Opens the enclosing folder, for a key.
    ///
    /// - `self`: the state.
    /// - Returns: whether it went up (not at the root, which has no
    ///   enclosing folder); propagates allocation failure.
    fn leave(self: *Self) std.mem.Allocator.Error!bool {
        if (!self.hasParent()) return false;
        try self.up();
        return true;
    }

    /// How many rows a Page Up or Page Down moves: a screenful less one, so
    /// the row moved from stays in view.
    ///
    /// - `self`: the state.
    /// - Returns: at least 1, and never more than the entries.
    fn pageRows(self: *const Self) isize {
        const screenful = self.scroll.viewport_height / row_height;
        // A height not yet laid out, or not finite, pages by one row.
        if (!std.math.isFinite(screenful) or screenful < 2) return 1;
        const limit: f32 = @floatFromInt(self.nodes.len + 1);
        const rows: isize = @intFromFloat(@min(@floor(screenful), limit));
        return @max(1, rows - 1);
    }

    /// Lists `path` next, selecting `selected_name` once listed: now, or once the
    /// listing under way lands (replacing any folder already waiting).
    ///
    /// - `self`: the state.
    /// - `path`: the folder; copied.
    /// - `selected_name`: the entry to select, by name; copied; null for none.
    /// - `select_parent`: whether to select the ".." row instead.
    /// - Returns: nothing; propagates allocation failure.
    fn request(self: *Self, path: []const u8, selected_name: ?[]const u8, select_parent: bool) std.mem.Allocator.Error!void {
        const listing = try FolderListing.create(self.allocator, self.io, path, selected_name);
        listing.select_parent = select_parent;
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
        self.parent_selected = false;
        // Only an entry that shows: a folder left with Hidden on, then hidden,
        // must not be a selection nothing draws.
        if (listing.selected_name) |name| {
            for (self.nodes, 0..) |node, index| {
                if (std.mem.eql(u8, node.name, name) and self.shows(node)) self.selection = index;
            }
        }
        if (listing.select_parent) self.selectParent();
        self.failure = null;
        self.scroll.offset = 0;
        // The folder left, selected after going up, may lie below the first screenful.
        if (self.selectedRow()) |row| self.scroll.reveal(row, row_height);
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

    // The ".." row comes first; hidden names are stepped over while hidden.
    try std.testing.expect(state.hasParent());
    state.move(1);
    try std.testing.expect(state.parent_selected);
    try std.testing.expect(state.selected() == null);
    try std.testing.expectEqual(@as(?usize, 0), state.selectedRow());
    state.move(1);
    try std.testing.expect(!state.parent_selected);
    try std.testing.expectEqualStrings("deep", state.selected().?.name);
    state.move(1);
    try std.testing.expectEqualStrings("A.txt", state.selected().?.name);
    try std.testing.expectEqual(@as(?usize, 2), state.selectedRow());
    state.show_hidden.set(true);
    state.move(-1);
    try std.testing.expectEqualStrings(".hidden", state.selected().?.name);

    // A file is not entered; a folder is, and up comes back to it.
    state.select(2);
    try std.testing.expect(!try state.enter());
    const file = (try state.pickAlloc(allocator)).?;
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

    // ".." picks the enclosing folder, and entering it goes up.
    state.move(-1);
    try std.testing.expect(state.parent_selected);
    const parent = (try state.pickAlloc(allocator)).?;
    defer allocator.free(parent.path);
    try std.testing.expectEqual(FileNodeKind.directory, parent.kind);
    try std.testing.expectEqualStrings(std.Io.Dir.path.dirname(root).?, parent.path);
    try std.testing.expect(try state.enter());
    state.wait();
    try std.testing.expectEqualStrings("photos", state.selected().?.name);
    try std.testing.expect(try state.enter());
    state.wait();
    try std.testing.expectEqualStrings(root, state.path.items);

    // A selection hidden after it was made picks nothing, never the folder around it.
    state.select(1);
    state.show_hidden.set(false);
    try std.testing.expect(try state.pickAlloc(allocator) == null);
    state.show_hidden.set(true);

    // A folder that cannot be read keeps the one on show.
    try state.open("does-not-exist-anywhere");
    state.wait();
    try std.testing.expect(state.failure != null);
    try std.testing.expectEqualStrings(root, state.path.items);
}

test "a file browser state takes the arrows, Return, Backspace, Home and End, and a letter" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "root/beta");
    try temporary.dir.createDirPath(io, "root/bravo");
    try temporary.dir.writeFile(io, .{ .sub_path = "root/alpha.txt", .data = "a" });
    try temporary.dir.writeFile(io, .{ .sub_path = "root/.hidden", .data = "h" });
    try temporary.dir.writeFile(io, .{ .sub_path = "root/zulu.txt", .data = "z" });
    const root = try temporary.dir.realPathFileAlloc(io, "root", allocator);
    defer allocator.free(root);

    // Listed in place: rows "..", beta, bravo, alpha.txt, zulu.txt.
    var state = FileBrowserState.init(allocator, io);
    defer state.deinit();
    try state.open(root);

    try std.testing.expect(try state.keyDown(mod.SdlKey.down_arrow, 0, false));
    try std.testing.expect(state.parent_selected);
    try std.testing.expect(try state.keyDown(mod.SdlKey.end, 0, false));
    try std.testing.expectEqualStrings("zulu.txt", state.selected().?.name);
    try std.testing.expect(try state.keyDown(mod.SdlKey.home, 0, false));
    try std.testing.expect(state.parent_selected);

    // A letter jumps to the next entry starting with it, wrapping; one none
    // starts with is left to the app, as is a shortcut.
    try std.testing.expect(try state.keyDown('b', 0, false));
    try std.testing.expectEqualStrings("beta", state.selected().?.name);
    try std.testing.expect(try state.keyDown('b', 0, false));
    try std.testing.expectEqualStrings("bravo", state.selected().?.name);
    try std.testing.expect(try state.keyDown('b', 0, false));
    try std.testing.expectEqualStrings("beta", state.selected().?.name);
    try std.testing.expect(!try state.keyDown('q', 0, false));
    try std.testing.expect(!try state.keyDown('a', mod.SdlKey.left_gui_mask, true));

    // Return opens a folder; Backspace comes back, selecting it; Return on a
    // file is the app's.
    try std.testing.expect(try state.keyDown(mod.SdlKey.enter, 0, false));
    try std.testing.expect(std.mem.endsWith(u8, state.path.items, "beta"));
    try std.testing.expect(try state.keyDown(mod.SdlKey.backspace, 0, false));
    try std.testing.expectEqualStrings(root, state.path.items);
    try std.testing.expectEqualStrings("beta", state.selected().?.name);
    try std.testing.expect(try state.keyDown('a', 0, false));
    try std.testing.expect(!try state.keyDown(mod.SdlKey.enter, 0, false));

    // Ctrl+↑ goes up off macOS; on macOS ⌃↑ is the system's, and ⌘↓
    // opens ".." as Return does.
    try std.testing.expect(!try state.keyDown(mod.SdlKey.up_arrow, mod.SdlKey.left_ctrl_mask, true));
    try std.testing.expect(!try state.keyDown(mod.SdlKey.up_arrow, mod.SdlKey.left_gui_mask, false));
    try std.testing.expect(try state.keyDown(mod.SdlKey.up_arrow, mod.SdlKey.left_ctrl_mask, false));
    try std.testing.expectEqualStrings("root", state.selected().?.name);
    try std.testing.expect(try state.keyDown(mod.SdlKey.down_arrow, mod.SdlKey.left_gui_mask, true));
    try std.testing.expectEqualStrings(root, state.path.items);

    // A refresh keeps ".." selected; going up out of a folder Hidden now
    // hides selects nothing rather than a row nothing draws.
    try std.testing.expect(try state.keyDown(mod.SdlKey.home, 0, false));
    try std.testing.expect(state.parent_selected);
    try state.refresh();
    try std.testing.expect(state.parent_selected);
    try temporary.dir.createDirPath(io, "root/.config");
    try state.refresh();
    state.show_hidden.set(true);
    try std.testing.expect(state.typeSelect('.'));
    try std.testing.expect(try state.enter());
    state.show_hidden.set(false);
    try std.testing.expect(try state.keyDown(mod.SdlKey.left_arrow, 0, false));
    try std.testing.expectEqualStrings(root, state.path.items);
    try std.testing.expect(state.selection == null);

    // Page Down never traps, laid out or not.
    state.scroll.viewport_height = std.math.inf(f32);
    try std.testing.expect(try state.keyDown(mod.SdlKey.page_down, 0, false));
    state.scroll.viewport_height = 0;
    try std.testing.expect(try state.keyDown(mod.SdlKey.page_up, 0, false));
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
        /// Counts a wake, from any thread.
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

test "a file browser state shows only the files its filter takes, and every folder" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "data/nested.txt");
    try temporary.dir.writeFile(io, .{ .sub_path = "data/notes.txt", .data = "n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "data/store.db", .data = "d" });
    try temporary.dir.writeFile(io, .{ .sub_path = "data/zebra.db", .data = "z" });
    const root = try temporary.dir.realPathFileAlloc(io, "data", allocator);
    defer allocator.free(root);

    const Filter = struct {
        const Self = @This();

        /// Takes database files.
        ///
        /// - `name`: the file's name.
        /// - Returns: true for a `.db`.
        fn databases(name: []const u8) bool {
            return std.mem.endsWith(u8, name, ".db");
        }
    };

    var state = FileBrowserState.init(allocator, io);
    defer state.deinit();
    state.shows_file = Filter.databases;
    try state.open(root);
    state.wait();
    try std.testing.expectEqual(@as(usize, 4), state.nodes.len);
    // A folder shows whatever its name; a file only when the filter takes it.
    try std.testing.expect(state.shows(state.nodes[0]));
    try std.testing.expectEqualStrings("notes.txt", state.nodes[1].name);
    try std.testing.expect(!state.shows(state.nodes[1]));

    // Moving steps over the files the filter leaves out, as over hidden ones.
    state.select(0);
    state.move(1);
    try std.testing.expectEqualStrings("store.db", state.selected().?.name);
    // Row 0 is "..", row 1 the folder: the filtered-out file takes no row.
    try std.testing.expectEqual(@as(?usize, 2), state.selectedRow());
    state.move(-1);
    try std.testing.expectEqualStrings("nested.txt", state.selected().?.name);

    // A filtered-out file selected directly is no pick.
    state.select(1);
    try std.testing.expect(state.selected() == null);
}
