//! A local file and folder picker, drawn in the window: one folder's entries,
//! a path bar above them, and a toggle for hidden names.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_file_browser);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The height of a browser row, in points: a `SelectableRow`'s.
const row_height: f32 = 28;

/// What the browser's rows are built from: only the rows in view are built
/// (`VirtualList`), so a folder of thousands costs what a screenful does.
const FileRows = struct {
    const Self = @This();

    /// The browser.
    state: *mod.FileBrowserState,

    /// The entries shown, as indices into the state's nodes (hidden names
    /// left out while they are hidden).
    shown: []const usize,

    /// Whether the list has the keyboard focus (the selection's fill).
    focused: bool,

    /// The published tokens.
    tokens: mod.BuildTokens,

    /// The row of shown entry `position`: its glyph, name and, for a file, size.
    ///
    /// - `self`: the rows.
    /// - `position`: the row's place among the shown entries.
    /// - Returns: the row.
    fn row(self: *const Self, position: usize) mod.View {
        const index = self.shown[position];
        const node = self.state.nodes[index];
        const selected = self.state.selection == index;
        const text = mod.SelectableRowStyle.selectionText(selected, self.focused);
        const glyph: renderer.Icon = if (node.kind == .directory) .folder else .file;
        const detail: []const u8 = if (node.kind == .directory) "" else FileBrowserActions.size(node.size);
        const content = mod.StackBuilder.make(.horizontal, 8, .center, .{
            mod.Icon(glyph, 14, if (selected and self.focused) text else self.tokens.secondary_label),
            mod.Text(node.name).size(13).foreground(text).truncated(),
            mod.Spacer(),
            mod.Text(detail).size(11).foreground(if (selected and self.focused) text else self.tokens.tertiary_label),
        });
        return mod.SelectableRow(content, selected, self.focused, mod.Callback.tagged(mod.FileBrowserState, self.state, FileBrowserActions.tap, index));
    }
};

/// The browser's own actions.
const FileBrowserActions = struct {
    const Self = @This();

    /// Selects entry `index`; a double-click on a folder opens it.
    ///
    /// - `state`: the browser.
    /// - `index`: the entry tapped, an index into its nodes.
    fn tap(state: *mod.FileBrowserState, index: usize) void {
        state.select(index);
        if (mod.PointerInput.shared().tapCount() < 2) return;
        _ = state.enter() catch |err| log.err("folder not opened [{any}]", .{err});
    }

    /// A byte count the way `ls -h` writes it, in the build arena.
    ///
    /// - `bytes`: the count.
    /// - Returns: the text ("512 B", "1.5 KiB").
    fn size(bytes: u64) []const u8 {
        const allocator = mod.BuildScope.shared().allocator();
        if (bytes < 1024) return allocator.print("{d} B", .{bytes}) catch @panic("oom");
        const units = [_][]const u8{ "KiB", "MiB", "GiB", "TiB" };
        var value = @as(f64, @floatFromInt(bytes)) / 1024;
        var unit: usize = 0;
        while (value >= 1024 and unit < units.len - 1) : (unit += 1) value /= 1024;
        return allocator.print("{d:.1} {s}", .{ value, units[unit] }) catch @panic("oom");
    }
};

/// A file browser: a path bar (an up button, the folder's path, a "Hidden"
/// toggle), then the folder's entries as selectable rows, folders first, each
/// with its glyph and a file's size. Only the rows in view are built, so a
/// large folder stays cheap, and folders are read off the UI thread when the
/// state's `Io` allows (`FileBrowserState.poll`, called here, adopts a
/// landed listing, which wakes the window when it lands). A tap selects a row, a double-click on a folder
/// opens it; the app routes keys to the state (`move`, `enter`, `up`, then
/// `scroll.reveal` to follow the selection) and reads the pick with
/// `pickAlloc`, a file or a folder alike. A folder that cannot be read is said
/// under the path bar. One picker for both kinds, which the native dialogs on
/// Windows and Linux cannot offer.
///
/// - `state`: the folder and selection; app-owned, at a stable address.
/// - `focused`: whether the list has the keyboard focus (the selection's fill).
/// - Returns: the browser, filling what it is given.
pub fn FileBrowser(state: *mod.FileBrowserState, focused: bool) mod.View {
    // A listing that landed since the last frame shows in this one.
    _ = state.poll();
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();

    // Indices only: the rows themselves are built for the ones in view.
    var shown: std.ArrayList(usize) = .empty;
    shown.ensureTotalCapacity(allocator, state.nodes.len) catch @panic("oom");
    for (state.nodes, 0..) |node, index| {
        if (state.shows(node)) shown.appendAssumeCapacity(index);
    }

    const bar = mod.StackBuilder.make(.horizontal, 6, .center, .{
        mod.IconButton(.arrowUp, 14, mod.Callback.attempt(mod.FileBrowserState, state, mod.FileBrowserState.up, "folder not opened")).accessibilityLabel("Enclosing folder"),
        mod.Text(state.path.items).size(12).foreground(tokens.secondary_label).truncated(),
        mod.Spacer(),
        mod.Toggle("Hidden", state.show_hidden.binding()),
    }).paddingInsets(.{ .top = 4, .leading = 8, .bottom = 4, .trailing = 8 });

    const failure: mod.View = if (state.failure) |err|
        mod.Text(allocator.print("That folder cannot be read ({t}).", .{err}) catch @panic("oom")).size(11).foreground(tokens.removed).paddingInsets(.{ .leading = 8, .bottom = 4 })
    else
        mod.Empty();

    const rows = FileRows{ .state = state, .shown = shown.items, .focused = focused, .tokens = tokens };
    const list: mod.View = if (shown.items.len == 0)
        mod.Text("This folder is empty.").size(12).foreground(tokens.tertiary_label).padding(8).frameMaxWidth().frameAlign(.leading)
    else
        mod.VirtualList(FileRows, &rows, shown.items.len, row_height, &state.scroll, FileRows.row).padding(4);
    return mod.FieldChrome(mod.StackBuilder.make(.vertical, 0, .leading, .{
        bar,
        failure,
        mod.Divider(),
        list.frameMaxWidth().frameMaxHeight(),
    }).frameMaxWidth().frameMaxHeight());
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a file browser draws a row per shown entry, selects on tap, and goes up" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "root/inner");
    try temporary.dir.writeFile(io, .{ .sub_path = "root/a.txt", .data = "a" });
    try temporary.dir.writeFile(io, .{ .sub_path = "root/.hidden", .data = "h" });
    const root = try temporary.dir.realPathFileAlloc(io, "root", allocator);
    defer allocator.free(root);

    var state = mod.FileBrowserState.init(allocator, io);
    defer state.deinit();
    try state.open(root);
    state.wait();

    const canvas = try mod.TestCanvas.create(allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const browser = FileBrowser(&state, true);
    canvas.end();
    var frame = try canvas.render(browser, 400, 300);
    defer frame.deinit();

    // Below the path bar, the first row is the folder; a tap selects it.
    var tapped = false;
    var y: f32 = 30;
    while (y < 90 and !tapped) : (y += 2) {
        tapped = canvas.tap(.{ .x = 200, .y = y }) and state.selection != null;
    }
    try std.testing.expect(tapped);
    try std.testing.expectEqualStrings("inner", state.selected().?.name);

    // The up button opens the enclosing folder, selecting the one left.
    try std.testing.expect(canvas.tap(.{ .x = 15, .y = 14 }));
    state.wait();
    try std.testing.expectEqualStrings("root", state.selected().?.name);
}
