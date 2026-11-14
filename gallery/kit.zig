const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_kit);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The Badges & Keys panel's segmented controls' options.
const view_options = [_][]const u8{ "Request", "Response", "Headers" };

/// The Badges & Keys panel's stretched segmented control's options.
const appearance_options = [_][]const u8{ "Light", "Dark", "System" };

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

/// The design-kit panels: badges, key caps, keyed buttons, segmented
/// controls and the key-hint bar; setting rows and the form editors;
/// selectable rows and a pane header; reorderable rows, with the state
/// they bind to.
pub const Kit = struct {
    const Self = @This();

    /// Allocates the state the panels bind to.
    allocator: std.mem.Allocator,

    /// The compact segmented control's selection.
    view_segment: ziggui.State(i64),

    /// The stretched segmented control's selection.
    appearance_segment: ziggui.State(i64),

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
            .skip_initialize = ziggui.State(bool).init(allocator, false),
            .strip_auth = ziggui.State(bool).init(allocator, true),
            .headers = ziggui.KeyValueState.init(allocator),
            .toolsets = ziggui.TokenFieldState.init(allocator),
            .row_selection = ziggui.State(i64).init(allocator, 1),
            .reorder_selection = ziggui.State(i64).init(allocator, 0),
            .search = ziggui.TextFieldState.init(allocator),
            // The gallery has no `Io` of its own to hand down; the global one
            // cannot run work concurrently, so the fixture folder is listed in
            // place and shows in the first frame of a screenshot.
            .files = ziggui.FileBrowserState.init(allocator, std.Io.Threaded.global_single_threaded.io()),
        };
        errdefer self.deinit();
        try self.files.open(gallery.fixtures_path);
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
        self.reorder_selection.deinit();
        self.row_selection.deinit();
        self.toolsets.deinit();
        self.headers.deinit();
        self.strip_auth.deinit();
        self.skip_initialize.deinit();
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
            Self.card(theme, "Badge in each tone (.mono() for a code)", ziggui.HStack(.{
                ziggui.Badge("idle", .neutral),
                ziggui.Badge("connected", .success),
                ziggui.Badge("refused", .danger),
                ziggui.Badge("version mismatch", .warning),
                ziggui.Badge("2026-07-28", .info),
                ziggui.Badge("active", .accent),
                ziggui.Badge("-32601", .danger).mono(),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(theme, "KeyCap", ziggui.HStack(.{
                ziggui.KeyCap("⌘K"),
                ziggui.KeyCap("esc"),
                ziggui.KeyCap("↩"),
                ziggui.KeyCap("tab"),
                ziggui.KeyCap("↑↓"),
                ziggui.KeyCap("ctrl+S"),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(theme, "ButtonKeyed in each role", ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.ButtonKeyed("Save", "↩", .prominent, ziggui.Callback.init(Self, self, Self.saved)),
                    ziggui.ButtonKeyed("Cancel", "esc", .normal, ziggui.Callback.init(Self, self, Self.cancelled)),
                    ziggui.ButtonKeyed("Delete", "⌫", .destructive, ziggui.Callback.init(Self, self, Self.deleted)),
                    ziggui.ButtonKeyed("Find", "⌘F", .plain, ziggui.Callback.init(Self, self, Self.found)),
                    ziggui.Spacer(),
                }).spacing(8),
                Self.leading(ziggui.Text(self.pressed).font(.footnote).foreground(theme.colors.secondary_label)),
            }).spacing(10)),
            Self.card(theme, "SegmentedControl, compact and stretched", ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.Text("Pane"),
                    ziggui.Spacer(),
                    ziggui.SegmentedControl(self.view_segment.binding(), &view_options),
                }),
                ziggui.SegmentedControl(self.appearance_segment.binding(), &appearance_options).frameMaxWidth(),
            }).spacing(12)),
            Self.card(theme, "KeyHintBar (seven hints, six shown)", ziggui.KeyHintBar(&bar_hints).border(theme.colors.separator, 1)),
        }).spacing(16);
    }

    /// The Forms panel: setting rows, a key/value editor and a token field.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn formsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.card(theme, "SettingRow", ziggui.VStack(.{
                ziggui.SettingRow("Skip initialize", "Send standalone requests to a legacy server, without the initialize handshake or a session.", ziggui.Toggle("", self.skip_initialize.binding())),
                ziggui.Divider(),
                ziggui.SettingRow("Strip inbound auth", "", ziggui.Toggle("", self.strip_auth.binding())),
            }).spacing(10)),
            Self.card(theme, "KeyValueEditor", ziggui.KeyValueEditor(&self.headers, "Header", "Value")),
            Self.card(theme, "TokenField (Enter commits; commas split)", ziggui.TokenField(&self.toolsets, "Add toolsets")),
            Self.card(theme, "SearchField (× clears)", ziggui.SearchField("Filter this folder", &self.search, null, null)),
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
            Self.card(theme, "PaneHeader", ziggui.StackBuilder.make(.vertical, 0, .leading, .{ziggui.PaneHeader("deepwiki", "https://mcp.deepwiki.com/mcp · legacy, 2025-11-25", ziggui.HStack(.{
                ziggui.Badge("connected", .success),
                ziggui.Button("Disconnect", call),
                ziggui.ButtonKeyed("Call", "↩", .prominent, call),
            }).spacing(8))}).background(theme.colors.window_background).cornerRadius(theme.metrics.corner_radius)),
            Self.card(theme, "SelectableRow: a focused list, then an unfocused one", ziggui.HStack(.{
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
            Self.card(theme, "ReorderableRow: drag a row up or down", Self.sampleList(&self.reorder_order, &self.reorder_selection, true, &self.reorder)),
            Self.card(theme, "Mid-drag: the second row held two rows down", Self.sampleList(&reorder_start, &self.reorder_selection, true, &self.reorder_preview)),
        }).spacing(16);
    }

    /// The File Browser panel: a `FileBrowser` over the fixture folder, and what it would pick.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn filesPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const pick = self.files.pickAlloc(allocator) catch @panic("oom");
        const said = allocator.print("Picks the {s} {s}", .{ if (pick.kind == .directory) "folder" else "file", pick.path }) catch @panic("oom");
        return ziggui.VStack(.{
            Self.card(theme, "FileBrowser: a tap selects, a double-click opens a folder", ziggui.FileBrowser(&self.files, true).frameHeight(280)),
            Self.leading(ziggui.Text(said).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated()),
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
    /// background, the content wrapped so its own padding survives.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the group's headline.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(theme: ziggui.Theme, title: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            // Wrapped, so the card's padding does not replace the content's own.
            ziggui.StackBuilder.make(.vertical, 0, .leading, .{content})
                .frameMaxWidth()
                .padding(14)
                .background(theme.colors.secondary_background)
                .cornerRadius(theme.metrics.corner_radius)
                .frameMaxWidth(),
        }).spacing(8).frameMaxWidth();
    }

    /// Pins `view` to the leading edge of a full-width row.
    ///
    /// - `view`: the view to pin.
    /// - Returns: the row.
    fn leading(view: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ view, ziggui.Spacer() }).frameMaxWidth();
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
    const canvas = try ziggui.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const input = ziggui.PointerInput.shared();
    defer input.endDrag();

    canvas.begin(ziggui.MacosTheme.light);
    var list = Kit.sampleList(&kit.reorder_order, &kit.reorder_selection, true, &kit.reorder);
    canvas.end();
    var frame = try canvas.render(list, 300, 150);
    frame.deinit();
    // A tap selects the third row's item.
    try std.testing.expect(canvas.tap(.{ .x = 100, .y = 2 * reorder_pitch + 10 }));
    input.endDrag();
    try std.testing.expectEqual(@as(i64, 2), kit.reorder_selection.get());
    // Drag the first row three rows down: it lands fourth.
    try std.testing.expect(canvas.tap(.{ .x = 100, .y = 10 }));
    input.drag(canvas.hits.items, .{ .x = 100, .y = 10 + 3 * reorder_pitch });
    input.endDrag();

    canvas.begin(ziggui.MacosTheme.light);
    _ = kit.reorderPanel(ziggui.MacosTheme.light);
    list = Kit.sampleList(&kit.reorder_order, &kit.reorder_selection, true, &kit.reorder);
    canvas.end();
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3, 0, 4 }, &kit.reorder_order);
    // The selection follows its item, not its place.
    try std.testing.expectEqual(@as(i64, 0), kit.reorder_selection.get());
    frame = try canvas.render(list, 300, 150);
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
