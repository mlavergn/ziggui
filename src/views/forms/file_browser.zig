//! A local file and folder picker, drawn in the window: one folder's entries,
//! a path bar above them, and a toggle for hidden names.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_file_browser);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What the browser's rows are built from: only the rows in view are built
/// (`VirtualList`), so a folder of thousands costs what a screenful does.
const FileRows = struct {
    const Self = @This();

    /// What a row adds to its own 8pt trailing padding beside the scroll bar:
    /// the grabbed thumb (7pt) and its inset (2pt) take 9pt, so 1pt clears
    /// it, and 3pt more keeps the sizes off it.
    const bar_gap: f32 = 4;

    /// The browser.
    state: *mod.FileBrowserState,

    /// The entries shown, as indices into the state's nodes (those
    /// `FileBrowserState.shows` refuses left out).
    shown: []const usize,

    /// Whether the rows start with "..", the enclosing folder.
    parent: bool,

    /// Whether the list has the keyboard focus (the selection's fill).
    focused: bool,

    /// The published tokens.
    tokens: mod.BuildTokens,

    /// How many rows the list has: "..", then the shown entries, or a line
    /// saying the folder is empty.
    ///
    /// - `self`: the rows.
    /// - Returns: the count.
    fn count(self: *const Self) usize {
        return @intFromBool(self.parent) + @max(self.shown.len, 1);
    }

    /// Row `position`: "..", a shown entry (its glyph, name and, for a file,
    /// size), or the line saying the folder is empty.
    ///
    /// - `self`: the rows.
    /// - `position`: the row's place in the list.
    /// - Returns: the row.
    fn row(self: *const Self, position: usize) mod.View {
        if (self.parent and position == 0) return self.parentRow();
        if (self.shown.len == 0) return mod.Text("This folder is empty.").size(12).foreground(self.tokens.tertiary_label).paddingInsets(.{ .leading = 8 }).frameMaxWidth().frameHeight(mod.FileBrowserState.row_height).frameAlign(.leading);
        const index = self.shown[position - @intFromBool(self.parent)];
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
        }).paddingInsets(.{ .trailing = self.barGap() });
        // Its path is what the row is: a double click never opens what the
        // previous one's folder put under the pointer.
        var identity = std.hash.Wyhash.init(0);
        identity.update(self.state.path.items);
        identity.update("/");
        identity.update(node.name);
        return mod.SelectableRow(content, selected, self.focused, mod.Callback.tagged(mod.FileBrowserState, self.state, FileBrowserActions.tap, index)).id(identity.final());
    }

    /// The room a row leaves on its trailing edge for the scroll bar, which
    /// shows while this frame's rows overflow the list.
    ///
    /// - `self`: the rows.
    /// - Returns: the gap, in points.
    fn barGap(self: *const Self) f32 {
        // This frame's rows against the list's height, which changes only
        // with the window: the last frame's content height would be the
        // folder before, for the one frame a landed listing draws.
        const viewport_height = self.state.scroll.viewport_height;
        const content_height = @as(f32, @floatFromInt(self.count())) * mod.FileBrowserState.row_height;
        return if (viewport_height > 0 and content_height > viewport_height + 0.5) bar_gap else 0;
    }

    /// The ".." row: the enclosing folder, selected by a tap and opened by a
    /// double click.
    ///
    /// - `self`: the rows.
    /// - Returns: the row.
    fn parentRow(self: *const Self) mod.View {
        const selected = self.state.parent_selected;
        const text = mod.SelectableRowStyle.selectionText(selected, self.focused);
        const content = mod.StackBuilder.make(.horizontal, 8, .center, .{
            mod.Icon(.folderUp, 14, if (selected and self.focused) text else self.tokens.secondary_label),
            mod.Text("..").size(13).foreground(text),
            mod.Spacer(),
        });
        var identity = std.hash.Wyhash.init(0);
        identity.update(self.state.path.items);
        identity.update("/..");
        return mod.SelectableRow(content, selected, self.focused, mod.Callback.init(mod.FileBrowserState, self.state, FileBrowserActions.tapParent)).accessibilityLabel("Enclosing folder").id(identity.final());
    }
};

/// The browser's own actions.
const FileBrowserActions = struct {
    const Self = @This();

    /// Selects entry `index`; a double click opens a folder, or picks a
    /// file (`FileBrowserState.on_pick`).
    ///
    /// - `state`: the browser.
    /// - `index`: the entry tapped, an index into its nodes.
    fn tap(state: *mod.FileBrowserState, index: usize) void {
        state.select(index);
        if (!mod.PointerInput.shared().isDoubleClick()) return;
        const entered = state.enter() catch |err| {
            log.err("folder not opened [{any}]", .{err});
            return;
        };
        if (!entered) _ = state.pick();
    }

    /// Selects the ".." row; a double click opens the enclosing folder.
    ///
    /// - `state`: the browser.
    fn tapParent(state: *mod.FileBrowserState) void {
        state.selectParent();
        if (!mod.PointerInput.shared().isDoubleClick()) return;
        // `enter` goes up while ".." is selected.
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

/// The path bar's path: a label that a click (or ⌘⇧G, or "/" in the list)
/// turns into a field a path is typed into, gone to on Enter, drawn as
/// `EditableText`'s field (`ControlMetrics.inline_field_*`).
const FilePathBar = struct {
    const Self = @This();

    /// The folder's path as a label, or the field while one is typed.
    ///
    /// - `state`: the browser's state.
    /// - `tokens`: the frame's colors.
    /// - Returns: the label or the field.
    fn view(state: *mod.FileBrowserState, tokens: mod.BuildTokens) mod.View {
        if (state.editing_path) {
            return mod.TextField("Type a folder's path", &state.path_field)
                .chromeless(mod.ControlMetrics.inline_field_inset)
                .size(12)
                .foreground(tokens.label)
                .background(tokens.raised)
                .cornerRadius(mod.ControlMetrics.inline_field_radius)
                .border(tokens.focus_ring, mod.ControlMetrics.inline_field_ring)
                .onSubmit(mod.Callback.attempt(mod.FileBrowserState, state, mod.FileBrowserState.goToTypedPath, "typed path not opened"))
                .frameMaxWidth();
        }
        return mod.Text(state.path.items)
            .size(12)
            .foreground(tokens.secondary_label)
            .truncated()
            .onTap(mod.Callback.attempt(mod.FileBrowserState, state, mod.FileBrowserState.beginPathEntry, "path bar not edited"))
            .pointerStyle(.horizontalText)
            .help("Click to type a folder's path");
    }
};

/// A file browser: a path bar (the folder's path, a "Show hidden" toggle), then
/// the folder's entries as selectable rows, folders first, each with its
/// glyph and a file's size, under a ".." row for the enclosing folder (none
/// at the root), with a scroll bar kept up while they overflow. Only the rows
/// in view are built, so a large folder stays cheap, and folders are read off
/// the UI thread when the state's `Io` allows (`FileBrowserState.poll`,
/// called here, adopts a landed listing, which wakes the window when it
/// lands). A tap selects a row, a double-click on a folder opens it; the app
/// forwards key-downs to the state while the browser has the keyboard
/// (`FileBrowserState.keyDown`: arrows, pages, Home/End, Return, Backspace, a
/// letter to jump) and reads the pick with `pickAlloc`, a file or a folder
/// alike. A click on the path (or ⌘⇧G, or "/" in the list) turns it into a
/// field: a path typed there (absolute, relative to the folder, or under
/// `FileBrowserState.home` with `~`) opens on Enter, a file's folder with
/// the file selected; Esc or a press elsewhere drops it. A folder that
/// cannot be read is said under the path bar. One picker
/// for both kinds, which the native dialogs on Windows and Linux cannot offer.
///
/// - `state`: the folder and selection; app-owned, at a stable address.
/// - `focused`: whether the list has the keyboard focus (the selection's fill).
/// - Returns: the browser, filling what it is given.
pub fn FileBrowser(state: *mod.FileBrowserState, focused: bool) mod.View {
    // A listing that landed since the last frame shows in this one; a path
    // field that lost the keyboard (Esc, a press elsewhere) is a label again.
    _ = state.poll();
    state.syncPathEntry();
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();

    // Indices only: the rows themselves are built for the ones in view.
    var shown: std.ArrayList(usize) = .empty;
    shown.ensureTotalCapacity(allocator, state.nodes.len) catch @panic("oom");
    for (state.nodes, 0..) |node, index| {
        if (state.shows(node)) shown.appendAssumeCapacity(index);
    }

    // The toggle keeps its own size, its label beside its switch at the bar's
    // trailing edge; while a path is typed, the field takes the bar up to it.
    const hidden = mod.Toggle("Show hidden", state.show_hidden.binding()).fixedSize();
    const bar = (if (state.editing_path)
        mod.StackBuilder.make(.horizontal, 12, .center, .{ FilePathBar.view(state, tokens), hidden })
    else
        mod.StackBuilder.make(.horizontal, 6, .center, .{ FilePathBar.view(state, tokens), mod.Spacer(), hidden })).paddingInsets(.{ .top = 4, .leading = 8, .bottom = 4, .trailing = 8 });

    const failure: mod.View = if (state.failure) |err|
        mod.Text(allocator.print("That folder cannot be read ({t}).", .{err}) catch @panic("oom")).size(11).foreground(tokens.removed).paddingInsets(.{ .leading = 8, .bottom = 4 })
    else
        mod.Empty();

    const rows = FileRows{ .state = state, .shown = shown.items, .parent = state.hasParent(), .focused = focused, .tokens = tokens };
    // Never empty: ".." or the line saying the folder is empty is always a row.
    const list = mod.VirtualList(FileRows, &rows, rows.count(), mod.FileBrowserState.row_height, &state.scroll, FileRows.row).scrollIndicators(.visible).padding(4);
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

test "a file browser draws a row per shown entry under a \"..\" row that goes up" {
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

    const window = try mod.TestWindow.create(allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const browser = FileBrowser(&state, true);
    window.end();
    var frame = try window.render(browser, 400, 300);
    defer frame.deinit();

    // Below the path bar the first row is "..", the second the folder; a tap
    // on the folder selects it.
    var y: f32 = 30;
    while (y < 120 and !state.parent_selected) : (y += 2) _ = window.tap(.{ .x = 200, .y = y });
    try std.testing.expect(state.parent_selected);
    const parent_y = y - 2;
    const folder_y = parent_y + mod.FileBrowserState.row_height;
    try std.testing.expect(window.tap(.{ .x = 200, .y = folder_y }));
    try std.testing.expectEqualStrings("inner", state.selected().?.name);
    try std.testing.expectEqual(@as(?usize, 1), state.selectedRow());

    // A double click on ".." opens the enclosing folder, selecting the one left.
    const input = mod.PointerInput.shared();
    try std.testing.expect(window.tap(.{ .x = 200, .y = parent_y }));
    input.setTapCount(2);
    defer input.setTapCount(1);
    try std.testing.expect(window.tap(.{ .x = 200, .y = parent_y }));
    state.wait();
    try std.testing.expectEqualStrings("root", state.selected().?.name);
}
