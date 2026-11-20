const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_kit);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The Badges & Keys panel's segmented controls' options.
const view_options = [_][]const u8{ "Request", "Response", "Headers" };

/// The Badges & Keys panel's stretched segmented control's options.
const appearance_options = [_][]const u8{ "Light", "Dark", "System" };

/// The Badges & Keys panel's icon segmented control's segments.
const mode_segments = [_]ziggui.IconSegment{ .{ .icon = .gitBranch, .title = "Git" }, .{ .icon = .code, .title = "Files" } };

/// The Badges & Keys panel's key-hint bar: seven hints, of which six show.
const bar_hints = [_]ziggui.KeyHint{
    .{ .key = "↑↓", .action = "move" },
    .{ .key = "↩", .action = "open" },
    .{ .key = "⌘K", .action = "palette" },
    .{ .key = "esc", .action = "back" },
    .{ .key = "tab", .action = "pane" },
    .{ .key = "/", .action = "find" },
    .{ .key = "q", .action = "quit" },
};

/// The sample lists' items, a glyph and a name: the Reorder panel shows them
/// all, the Rows & Headers panel the first four (`rows_order`).
const sample_items = [_]struct { ziggui.IconName, []const u8 }{
    .{ .globe, "deepwiki" },
    .{ .terminal, "zigmcp serve" },
    .{ .server, "localhost:8480" },
    .{ .database, "archive" },
    .{ .cloud, "staging" },
};

/// The Rows & Headers panel's rows, as indices into `sample_items`.
const rows_order = [_]usize{ 0, 1, 2, 3 };

/// The Reorder panel's rows in their first order.
const reorder_start = [sample_items.len]usize{ 0, 1, 2, 3, 4 };

/// The space between the sample lists' rows.
const row_spacing: f32 = 2;

/// The distance from one Reorder row's top to the next's: a 28pt
/// `SelectableRow` and the rows' spacing.
const reorder_pitch: f32 = 28 + row_spacing;

/// The Reorder panel's frozen drag: the second row held 50pt down, over
/// the gap above the last row.
const reorder_frozen = ziggui.ReorderState{ .pressed = 1, .dragging = 1, .offset = 50, .row_height = reorder_pitch, .count = sample_items.len };

/// The Outline panel's tree, in pre-order: folders first, then files.
const outline_nodes = [_]ziggui.OutlineNode{
    .{ .key = ".zig-cache/", .has_children = true },
    .{ .key = ".zig-cache/h/", .depth = 1, .has_children = true },
    .{ .key = ".zig-cache/h/timestamp", .depth = 2 },
    .{ .key = "cli/", .has_children = true },
    .{ .key = "cli/main.zig", .depth = 1 },
    .{ .key = "src/", .has_children = true },
    .{ .key = "src/flowable/", .depth = 1, .has_children = true },
    .{ .key = "src/flowable/flowable.zig", .depth = 2 },
    .{ .key = "src/operators/", .depth = 1, .has_children = true },
    .{ .key = "src/operators/map.zig", .depth = 2 },
    .{ .key = "src/operators/filter.zig", .depth = 2 },
    .{ .key = "src/schedulers/", .depth = 1, .has_children = true },
    .{ .key = "src/schedulers/queue.zig", .depth = 2 },
    .{ .key = "src/callback.zig", .depth = 1 },
    .{ .key = "src/disposable.zig", .depth = 1 },
    .{ .key = "src/emitter.zig", .depth = 1 },
    .{ .key = "build.zig" },
    .{ .key = "README.md" },
};

/// The design-kit panels: badges, key caps, keyed buttons, segmented
/// controls and the key-hint bar; setting rows and the form editors;
/// selectable rows and a pane header; reorderable rows; the file browser;
/// an outline's folding rows, with the state they bind to.
pub const Kit = struct {
    const Self = @This();

    /// Allocates the state the panels bind to.
    allocator: std.mem.Allocator,

    /// The compact segmented control's selection.
    view_segment: ziggui.State(i64),

    /// The stretched segmented control's selection.
    appearance_segment: ziggui.State(i64),
    /// The icon segmented control's selection.
    mode_segment: ziggui.State(i64),

    /// The Forms panel's first setting.
    skip_initialize: ziggui.State(bool),

    /// The Forms panel's second setting.
    strip_auth: ziggui.State(bool),

    /// The Forms panel's header rows.
    headers: ziggui.KeyValueState,

    /// The Forms panel's toolsets.
    toolsets: ziggui.TokenFieldState,

    /// The Rows & Headers panel's selected row.
    row_selection: ziggui.State(i64),

    /// The Reorder panel's selected row, by item, so it follows a moved row.
    reorder_selection: ziggui.State(i64),

    /// The Reorder panel's rows, as indices into `sample_items`, in the order shown.
    reorder_order: [sample_items.len]usize = reorder_start,

    /// The Reorder panel's live list's drag.
    reorder: ziggui.ReorderState = .init(),

    /// The Reorder panel's frozen list's drag, reset to `reorder_frozen` each frame.
    reorder_preview: ziggui.ReorderState = reorder_frozen,

    /// The Outline panel's folds: collapsed at first, `src/` opened.
    outline: ziggui.OutlineState,

    /// The Outline panel's selected node, by index into `outline_nodes`; kept
    /// while folded away, shown on the folder holding it until that opens.
    outline_selection: ziggui.State(i64),

    /// What the last keyed button did.
    pressed: []const u8 = "No button pressed yet.",

    /// The Forms panel's search field.
    search: ziggui.TextFieldState,

    /// The File Browser panel's folder: `fixtures/file_browser` at start.
    files: ziggui.FileBrowserState,

    /// Constructs the panels' state with sample rows and tokens.
    ///
    /// - `allocator`: allocator for the state; must outlive the kit.
    /// - Returns: the kit; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var self = Self{
            .allocator = allocator,
            .view_segment = ziggui.State(i64).init(allocator, 1),
            .appearance_segment = ziggui.State(i64).init(allocator, 2),
            .mode_segment = ziggui.State(i64).init(allocator, 0),
            .skip_initialize = ziggui.State(bool).init(allocator, false),
            .strip_auth = ziggui.State(bool).init(allocator, true),
            .headers = ziggui.KeyValueState.init(allocator),
            .toolsets = ziggui.TokenFieldState.init(allocator),
            .row_selection = ziggui.State(i64).init(allocator, 1),
            .reorder_selection = ziggui.State(i64).init(allocator, 0),
            .outline = .init(allocator, false),
            .outline_selection = ziggui.State(i64).init(allocator, 5),
            .search = ziggui.TextFieldState.init(allocator),
            // The gallery has no `Io` of its own to hand down; the global one
            // cannot run work concurrently, so the fixture folder is listed in
            // place and shows in the first frame of a screenshot.
            .files = ziggui.FileBrowserState.init(allocator, std.Io.Threaded.global_single_threaded.io()),
        };
        errdefer self.deinit();
        try self.files.open(gallery.fixtures_path);
        try self.outline.setExpanded("src/", true);
        try self.search.setText("releases");
        try self.headers.setPairs(&.{ .{ "Accept", "application/json" }, .{ "X-Trace-Id", "7f3a" } });
        try self.toolsets.setTokens(&.{ "repos", "issues", "pull_requests" });
        return self;
    }

    /// Releases the panels' state; the fields leave the focus as they go.
    ///
    /// - `self`: the kit to tear down.
    pub fn deinit(self: *Self) void {
        self.files.deinit();
        self.search.deinit();
        self.outline_selection.deinit();
        self.outline.deinit();
        self.reorder_selection.deinit();
        self.row_selection.deinit();
        self.toolsets.deinit();
        self.headers.deinit();
        self.strip_auth.deinit();
        self.skip_initialize.deinit();
        self.mode_segment.deinit();
        self.appearance_segment.deinit();
        self.view_segment.deinit();
    }

    /// The Badges & Keys panel: badges in every tone, key caps, keyed
    /// buttons in every role, segmented controls and a key-hint bar.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn badgesPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.card(theme, "Badge in each tone (.mono() for a code)", "ziggui.Badge", ziggui.HStack(.{
                ziggui.Badge("idle", .neutral),
                ziggui.Badge("connected", .success),
                ziggui.Badge("refused", .danger),
                ziggui.Badge("version mismatch", .warning),
                ziggui.Badge("2026-07-28", .info),
                ziggui.Badge("active", .accent),
                ziggui.Badge("-32601", .danger).mono(),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(theme, "KeyCap", "ziggui.KeyCap", ziggui.HStack(.{
                ziggui.KeyCap("⌘K"),
                ziggui.KeyCap("esc"),
                ziggui.KeyCap("↩"),
                ziggui.KeyCap("tab"),
                ziggui.KeyCap("↑↓"),
                ziggui.KeyCap("ctrl+S"),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(theme, "ButtonKeyed in each role", "ziggui.ButtonKeyed", ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.ButtonKeyed("Save", "↩", .prominent, ziggui.Callback.init(Self, self, Self.saved)),
                    ziggui.ButtonKeyed("Cancel", "esc", .normal, ziggui.Callback.init(Self, self, Self.cancelled)),
                    ziggui.ButtonKeyed("Delete", "⌫", .destructive, ziggui.Callback.init(Self, self, Self.deleted)),
                    ziggui.ButtonKeyed("Find", "⌘F", .plain, ziggui.Callback.init(Self, self, Self.found)),
                    ziggui.Spacer(),
                }).spacing(8),
                ziggui.Text(self.pressed).font(.footnote).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            }).spacing(10)),
            Self.card(theme, "SegmentedControl, compact and stretched", "ziggui.SegmentedControl", ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.Text("Pane"),
                    ziggui.Spacer(),
                    ziggui.SegmentedControl(self.view_segment.binding(), &view_options),
                }),
                ziggui.SegmentedControl(self.appearance_segment.binding(), &appearance_options).frameMaxWidth(),
            }).spacing(12)),
            Self.card(theme, "IconSegmentedControl", "ziggui.IconSegmentedControl", ziggui.HStack(.{
                ziggui.Text("Mode"),
                ziggui.Spacer(),
                ziggui.IconSegmentedControl(self.mode_segment.binding(), &mode_segments),
            })),
            Self.card(theme, "KeyHintBar (seven hints, six shown)", "ziggui.KeyHintBar", ziggui.KeyHintBar(&bar_hints).border(theme.colors.separator, 1)),
        }).spacing(16);
    }

    /// The Forms panel: setting rows, a key/value editor and a token field.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn formsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.card(theme, "SettingRow", "ziggui.SettingRow", ziggui.VStack(.{
                ziggui.SettingRow("Skip initialize", "Send standalone requests to a legacy server, without the initialize handshake or a session.", ziggui.Toggle("", self.skip_initialize.binding())),
                ziggui.Divider(),
                ziggui.SettingRow("Strip inbound auth", "", ziggui.Toggle("", self.strip_auth.binding())),
            }).spacing(10)),
            Self.card(theme, "KeyValueEditor", "ziggui.KeyValueEditor", ziggui.KeyValueEditor(&self.headers, "Header", "Value")),
            Self.card(theme, "TokenField (Enter commits; commas split)", "ziggui.TokenField", ziggui.TokenField(&self.toolsets, "Add toolsets")),
            Self.card(theme, "SearchField (× clears)", "ziggui.SearchField", ziggui.SearchField("Filter this folder", &self.search, null, null)),
        }).spacing(16);
    }

    /// The Rows & Headers panel: a pane header with its accessory, and
    /// selectable rows in a focused and an unfocused list.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn rowsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const call = ziggui.Callback.init(Self, self, Self.saved);
        return ziggui.VStack(.{
            Self.card(theme, "PaneHeader", "ziggui.PaneHeader", ziggui.StackBuilder.make(.vertical, 0, .leading, .{ziggui.PaneHeader("deepwiki", "https://mcp.deepwiki.com/mcp · legacy, 2025-11-25", ziggui.HStack(.{
                ziggui.Badge("connected", .success),
                ziggui.Button("Disconnect", call),
                ziggui.ButtonRoled("Call", .prominent, call),
            }).spacing(8))}).background(theme.colors.window_background).cornerRadius(theme.metrics.corner_radius)),
            Self.card(theme, "SelectableRow: a focused list, then an unfocused one", "ziggui.SelectableRow", ziggui.HStack(.{
                Self.sampleList(&rows_order, &self.row_selection, true, null),
                Self.sampleList(&rows_order, &self.row_selection, false, null),
            }).spacing(16).alignment(.top)),
        }).spacing(16);
    }

    /// The Reorder panel: a list whose rows drag up and down, and one held
    /// mid-drag. The live list's finished drag reorders it here.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn reorderPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        if (self.reorder.takeMove()) |move| move.apply(usize, &self.reorder_order);
        self.reorder_preview = reorder_frozen;
        return ziggui.VStack(.{
            Self.card(theme, "ReorderableRow: drag a row up or down", "ziggui.ReorderableRow", Self.sampleList(&self.reorder_order, &self.reorder_selection, true, &self.reorder)),
            Self.card(theme, "Mid-drag: the second row held two rows down", "ziggui.ReorderableRow", Self.sampleList(&reorder_start, &self.reorder_selection, true, &self.reorder_preview)),
        }).spacing(16);
    }

    /// The Outline panel: a folder tree whose folders fold (a tap on a
    /// folder's row), collapsed at first, with expand all and collapse all.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn outlinePanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const shown = self.outline.visible(allocator, &outline_nodes) catch @panic("oom");
        const rows = allocator.alloc(ziggui.View, shown.len) catch @panic("oom");
        const selected_node = self.outline.shownNode(&outline_nodes, @intCast(self.outline_selection.get()));
        for (rows, shown) |*row, index| row.* = self.outlineRow(index, index == selected_node);
        const list = ziggui.StackBuilder.fromSlice(.vertical, 0, .leading, rows).frameMaxWidth();
        const buttons = ziggui.HStack(.{
            ziggui.Button("Expand All", ziggui.Callback.init(Self, self, Self.expandedAll)),
            ziggui.Button("Collapse All", ziggui.Callback.init(Self, self, Self.collapsedAll)),
            ziggui.Spacer(),
        }).spacing(8);
        return ziggui.VStack(.{
            Self.card(theme, "OutlineRow: tap a folder to fold or unfold it", "ziggui.OutlineState, ziggui.OutlineRow", ziggui.VStack(.{ buttons, list }).spacing(10).frameMaxWidth()),
        }).spacing(16);
    }

    /// The File Browser panel: a `FileBrowser` over the fixture folder, and what it would pick.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn filesPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const said = if (self.files.pickAlloc(allocator) catch @panic("oom")) |pick|
            allocator.print("Picks the {s} {s}", .{ if (pick.kind == .directory) "folder" else "file", pick.path }) catch @panic("oom")
        else
            "Picks nothing: the selection is hidden.";
        return ziggui.VStack(.{
            Self.card(theme, "FileBrowser: a tap selects, a double-click opens a folder", "ziggui.FileBrowser", ziggui.FileBrowser(&self.files, true).frameHeight(280)),
            ziggui.Text(said).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
        }).spacing(16);
    }

    /// One sample list: a row for each of `order`'s items, the one `selection`
    /// names selected (by item, so it follows a moved row), each row dragged
    /// up and down when `reorder` is given.
    ///
    /// - `order`: the rows, as indices into `sample_items`.
    /// - `selection`: the selected item.
    /// - `focused`: whether the list draws as focused.
    /// - `reorder`: the list's drag; null for a list that does not reorder.
    /// - Returns: the list.
    fn sampleList(order: []const usize, selection: *ziggui.State(i64), focused: bool, reorder: ?*ziggui.ReorderState) ziggui.View {
        const rows = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, order.len) catch @panic("oom");
        for (rows, order, 0..) |*row, item, index| {
            const selected = selection.get() == @as(i64, @intCast(item));
            const color = ziggui.SelectableRowStyle.selectionText(selected, focused);
            const glyph = ziggui.Icon(sample_items[item][0], 14, color);
            const name = ziggui.Text(sample_items[item][1]).foreground(color);
            const tapped = ziggui.Callback.select(selection.binding(), @intCast(item));
            if (reorder) |state| {
                const label = ziggui.HStack(.{ ziggui.Icon(.gripVertical, 14, color), glyph, name }).spacing(8);
                row.* = ziggui.ReorderableRow(ziggui.SelectableRow(label, selected, focused, tapped), state, index, order.len, reorder_pitch);
            } else {
                row.* = ziggui.SelectableRow(ziggui.HStack(.{ glyph, name }).spacing(8), selected, focused, tapped);
            }
        }
        return ziggui.StackBuilder.fromSlice(.vertical, row_spacing, .leading, rows).frameMaxWidth();
    }

    /// One Outline row: the node's name, a folder or file glyph, selected by a
    /// tap, a folder's tap folding it too.
    ///
    /// - `self`: the kit.
    /// - `index`: the node, by index into `outline_nodes`.
    /// - `selected`: whether it shows the selection (`OutlineState.shownNode`).
    /// - Returns: the row.
    fn outlineRow(self: *Self, index: usize, selected: bool) ziggui.View {
        const node = outline_nodes[index];
        const color = ziggui.SelectableRowStyle.selectionText(selected, true);
        const expanded = self.outline.isExpanded(node.key);
        const trimmed = std.mem.trimEnd(u8, node.key, "/");
        const name = if (std.mem.findScalarLast(u8, trimmed, '/')) |slash| trimmed[slash + 1 ..] else trimmed;
        const glyph: ziggui.IconName = if (!node.has_children) .fileText else if (expanded) .folderOpen else .folder;
        const label = ziggui.HStack(.{ ziggui.Icon(glyph, 13, color), ziggui.Text(name).foreground(color) }).spacing(6);
        const tapped = ziggui.Callback.tagged(Self, self, Self.outlineTapped, index);
        // Its key is what the row is: rows move under the pointer as folders fold.
        const identity = std.hash.Wyhash.hash(0, node.key);
        return ziggui.SelectableRow(ziggui.OutlineRow(node.depth, node.has_children, expanded, color, null, label), selected, true, tapped).id(identity);
    }

    /// A tap on an Outline row: selects it, and folds or unfolds a folder.
    ///
    /// - `self`: the kit.
    /// - `index`: the node, by index into `outline_nodes`.
    fn outlineTapped(self: *Self, index: usize) void {
        self.outline_selection.set(@intCast(index));
        if (!outline_nodes[index].has_children) return;
        self.outline.toggle(outline_nodes[index].key) catch |err| log.warn("cannot fold the outline: {s}", .{@errorName(err)});
    }

    /// Expand All: every folder opens.
    ///
    /// - `self`: the kit.
    fn expandedAll(self: *Self) void {
        self.outline.expandAll();
    }

    /// Collapse All: every folder closes.
    ///
    /// - `self`: the kit.
    fn collapsedAll(self: *Self) void {
        self.outline.collapseAll();
    }

    /// The Save button: says it was pressed.
    ///
    /// - `self`: the kit.
    fn saved(self: *Self) void {
        self.pressed = "Save (or Call)";
    }

    /// The Cancel button: says it was pressed.
    ///
    /// - `self`: the kit.
    fn cancelled(self: *Self) void {
        self.pressed = "Cancel";
    }

    /// The Delete button: says it was pressed.
    ///
    /// - `self`: the kit.
    fn deleted(self: *Self) void {
        self.pressed = "Delete";
    }

    /// The Find button: says it was pressed.
    ///
    /// - `self`: the kit.
    fn found(self: *Self) void {
        self.pressed = "Find";
    }

    /// A titled group: a headline above a rounded block in the secondary
    /// background, the content wrapped so its own padding survives, the code
    /// names it shows under it.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the group's headline.
    /// - `names`: what it shows, as code names it (`ziggui.Table`), drawn under it.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(theme: ziggui.Theme, title: []const u8, names: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            ziggui.Text(title).font(.headline).frameMaxWidth().frameAlign(.leading),
            ziggui.VStack(.{
                // Wrapped, so the card's padding does not replace the content's own.
                ziggui.StackBuilder.make(.vertical, 0, .leading, .{content})
                    .frameMaxWidth()
                    .padding(14)
                    .background(theme.colors.secondary_background)
                    .cornerRadius(theme.metrics.corner_radius)
                    .frameMaxWidth(),
                ziggui.Text(names).font(.caption).mono().foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            }).spacing(4).frameMaxWidth(),
        }).spacing(8).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Kit);
}

test "the kit's buttons say what they did" {
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    kit.saved();
    try std.testing.expectEqualStrings("Save (or Call)", kit.pressed);
    kit.found();
    try std.testing.expectEqualStrings("Find", kit.pressed);
    try std.testing.expectEqual(@as(usize, 2), kit.headers.count());
    try std.testing.expectEqual(@as(usize, 3), kit.toolsets.tokens().len);
}

test "the Reorder panel's list reorders on a drag and selects on a tap" {
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const input = ziggui.PointerInput.shared();
    defer input.endDrag();

    window.begin(ziggui.MacosTheme.light);
    var list = Kit.sampleList(&kit.reorder_order, &kit.reorder_selection, true, &kit.reorder);
    window.end();
    var frame = try window.render(list, 300, 150);
    frame.deinit();
    // A tap selects the third row's item.
    try std.testing.expect(window.tap(.{ .x = 100, .y = 2 * reorder_pitch + 10 }));
    input.endDrag();
    try std.testing.expectEqual(@as(i64, 2), kit.reorder_selection.get());
    // Drag the first row three rows down: it lands fourth.
    try std.testing.expect(window.tap(.{ .x = 100, .y = 10 }));
    input.drag(window.hits.items, .{ .x = 100, .y = 10 + 3 * reorder_pitch });
    input.endDrag();

    window.begin(ziggui.MacosTheme.light);
    _ = kit.reorderPanel(ziggui.MacosTheme.light);
    list = Kit.sampleList(&kit.reorder_order, &kit.reorder_selection, true, &kit.reorder);
    window.end();
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3, 0, 4 }, &kit.reorder_order);
    // The selection follows its item, not its place.
    try std.testing.expectEqual(@as(i64, 0), kit.reorder_selection.get());
    frame = try window.render(list, 300, 150);
    frame.deinit();
}

test "the Outline panel starts collapsed but for src/, folds on a tap, and expands and collapses all" {
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    const top = try kit.outline.visible(std.testing.allocator, &outline_nodes);
    defer std.testing.allocator.free(top);
    // .zig-cache/, cli/, src/ and its six, build.zig, README.md.
    try std.testing.expectEqual(11, top.len);

    kit.outlineTapped(3);
    try std.testing.expect(kit.outline.isExpanded("cli/"));
    try std.testing.expectEqual(@as(i64, 3), kit.outline_selection.get());
    kit.outlineTapped(4);
    try std.testing.expect(kit.outline.isExpanded("cli/"));
    kit.expandedAll();
    const all = try kit.outline.visible(std.testing.allocator, &outline_nodes);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(outline_nodes.len, all.len);
    // A file folded away keeps the selection, shown on its top folder.
    kit.outlineTapped(9);
    kit.collapsedAll();
    const none = try kit.outline.visible(std.testing.allocator, &outline_nodes);
    defer std.testing.allocator.free(none);
    try std.testing.expectEqual(5, none.len);
    try std.testing.expectEqual(@as(i64, 9), kit.outline_selection.get());
    try std.testing.expectEqual(5, kit.outline.shownNode(&outline_nodes, 9));

    window.begin(ziggui.MacosTheme.light);
    const panel = kit.outlinePanel(ziggui.MacosTheme.light);
    window.end();
    var frame = try window.render(panel, 400, 400);
    frame.deinit();
}

test "the File Browser panel opens the fixture folder, listed at once" {
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    try std.testing.expect(!kit.files.loading());
    try std.testing.expect(kit.files.failure == null);
    try std.testing.expect(std.mem.endsWith(u8, kit.files.path.items, "file_browser"));
    // Folders first, by name; the hidden `.settings` listed but not shown.
    try std.testing.expectEqualStrings("Documents", kit.files.nodes[0].name);
    try std.testing.expectEqualStrings("Photos", kit.files.nodes[1].name);
    try std.testing.expectEqualStrings("Projects", kit.files.nodes[2].name);
    try std.testing.expectEqualStrings(".settings", kit.files.nodes[3].name);
    try std.testing.expect(!kit.files.shows(kit.files.nodes[3]));
}
