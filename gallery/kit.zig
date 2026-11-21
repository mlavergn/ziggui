const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_kit);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The Pickers section's segmented controls' options.
const view_options = [_][]const u8{ "Request", "Response", "Headers" };

/// The Pickers section's stretched segmented control's options.
const appearance_options = [_][]const u8{ "Light", "Dark", "System" };

/// The Pickers section's icon segmented control's segments.
const mode_segments = [_]ziggui.IconSegment{ .{ .icon = .gitBranch, .title = "Git" }, .{ .icon = .code, .title = "Files" } };

/// The Menus & Commands section's key-hint bar: seven hints, of which six show.
const bar_hints = [_]ziggui.KeyHint{
    .{ .key = "↑↓", .action = "move" },
    .{ .key = "↩", .action = "open" },
    .{ .key = "⌘K", .action = "palette" },
    .{ .key = "esc", .action = "back" },
    .{ .key = "tab", .action = "pane" },
    .{ .key = "/", .action = "find" },
    .{ .key = "q", .action = "quit" },
};

/// The sample lists' items, a glyph and a name: the Lists section's reorder cards shows them
/// all, the Lists section's rows card the first four (`rows_order`).
const sample_items = [_]struct { ziggui.IconName, []const u8 }{
    .{ .globe, "deepwiki" },
    .{ .terminal, "zigmcp serve" },
    .{ .server, "localhost:8480" },
    .{ .database, "archive" },
    .{ .cloud, "staging" },
};

/// The Lists section's rows card's rows, as indices into `sample_items`.
const rows_order = [_]usize{ 0, 1, 2, 3 };

/// The Lists section's reorder cards's rows in their first order.
const reorder_start = [sample_items.len]usize{ 0, 1, 2, 3, 4 };

/// The space between the sample lists' rows.
const row_spacing: f32 = 2;

/// The Lists section's labeled rows: an icon or none, a title, and its value.
const labeled_rows = [_]struct { ?ziggui.IconName, []const u8, []const u8 }{
    .{ .mapPin, "Pole 12", "app capture" },
    .{ .camera, "Site photos", "3 photos" },
    .{ .fileText, "Survey notes", "" },
    .{ null, "Untitled", "draft" },
};

/// The distance from one Reorder row's top to the next's: a 28pt
/// `SelectableRow` and the rows' spacing.
const reorder_pitch: f32 = 28 + row_spacing;

/// The Lists section's reorder cards's frozen drag: the second row held 50pt down, over
/// the gap above the last row.
const reorder_frozen = ziggui.ReorderState{ .pressed = 1, .dragging = 1, .offset = 50, .row_height = reorder_pitch, .count = sample_items.len };

/// The CheckList card's options: a network's name and what it says under it.
const check_options = [_]struct { []const u8, []const u8 }{
    .{ "Home", "Secured · strong signal" },
    .{ "Office", "Secured" },
    .{ "Café", "Open network" },
};

/// The Lists section's rename card's rows: each one's icon and its name at start.
const rename_start = [_]struct { ziggui.IconName, []const u8 }{
    .{ .folder, "Documents" },
    .{ .fileText, "Notes.txt" },
    .{ .fileText, "Plans.md" },
    .{ .image, "Photo.png" },
};

/// The Lists section's outline's tree, in pre-order: folders first, then files.
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

    /// The Forms & Settings section's first setting.
    skip_initialize: ziggui.State(bool),

    /// The Forms & Settings section's second setting.
    strip_auth: ziggui.State(bool),

    /// The Forms & Settings section's header rows.
    headers: ziggui.KeyValueState,

    /// The Forms & Settings section's toolsets.
    toolsets: ziggui.TokenFieldState,

    /// The Lists section's rows card's selected row.
    row_selection: ziggui.State(i64),
    /// The Lists section's labeled rows card's selected row.
    labeled_selected: usize = 0,

    /// The Lists section's reorder cards's selected row, by item, so it follows a moved row.
    reorder_selection: ziggui.State(i64),

    /// The Lists section's reorder cards's rows, as indices into `sample_items`, in the order shown.
    reorder_order: [sample_items.len]usize = reorder_start,

    /// The Lists section's reorder cards's live list's drag.
    reorder: ziggui.ReorderState = .init(),

    /// The Lists section's reorder cards's frozen list's drag, reset to `reorder_frozen` each frame.
    reorder_preview: ziggui.ReorderState = reorder_frozen,

    /// The Lists section's outline's folds: collapsed at first, `src/` opened.
    outline: ziggui.OutlineState,

    /// The Lists section's outline's selected node, by index into `outline_nodes`; kept
    /// while folded away, shown on the folder holding it until that opens.
    outline_selection: ziggui.State(i64),

    /// What the last keyed button did.
    pressed: []const u8 = "No button pressed yet.",

    /// The Forms & Settings section's search field.
    search: ziggui.TextFieldState,

    /// The Lists section's rename card's rows' names, renamed in place.
    rename_items: [rename_start.len]ziggui.EditableTextState,

    /// The Lists section's rename card's selected row.
    rename_selection: ziggui.State(i64),

    /// The CheckList card's chosen option.
    check_choice: ziggui.State(i64),

    /// The Lists section's rename card's row renamed last, or null before any.
    renamed_last: ?usize = null,

    /// A row the Lists section's rename card starts renaming as it next builds
    /// (`--rename`): after the frame's section change, which drops the keyboard.
    rename_on_show: ?usize = null,

    /// Whether the Lists section's first disclosure group shows its content.
    disclosure_open: bool = true,

    /// Whether the Lists section's disclosure group with an accessory shows its content.
    accessory_open: bool = false,

    /// The Files section's folder: `fixtures/file_browser` at start.
    files: ziggui.FileBrowserState,

    /// Whether the File Browser's list holds the arrow keys: a press on it gives
    /// them to it, a tap on a sidebar row or a change of section takes them
    /// back (`Gallery.pointerDown`, `Gallery.selectRow`, `Gallery.track`). It
    /// draws focused while it does.
    files_have_keys: bool = false,

    /// Whether the Files section shows only text files (`FileBrowserState.shows_file`).
    text_only: ziggui.State(bool),

    /// The window the Files section's Open and Save buttons show the
    /// system's panels over; `main.zig` fills it, and headless it stays empty.
    platform: gallery.Platform = .{},

    /// Where the dialog on show started, held until its outcome is taken (SDL
    /// may read it until then); null with none on show.
    dialog_location: ?[:0]u8 = null,

    /// What the last dialog left, in words; null before one finished.
    dialog_said: ?[]u8 = null,

    /// Constructs the panels' state with sample rows and tokens.
    ///
    /// - `allocator`: allocator for the state; must outlive the kit.
    /// - Returns: the kit; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        // The only part that can fail before the rest exists, so it cleans up after itself.
        const rename_items = try Self.renameItems(allocator);
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
            .text_only = ziggui.State(bool).init(allocator, false),
            .rename_items = rename_items,
            .rename_selection = ziggui.State(i64).init(allocator, 0),
            .check_choice = ziggui.State(i64).init(allocator, 0),
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
        self.check_choice.deinit();
        self.rename_selection.deinit();
        if (self.dialog_said) |said| self.allocator.free(said);
        if (self.dialog_location) |location| self.allocator.free(location);
        self.text_only.deinit();
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
        for (&self.rename_items) |*item| item.deinit();
    }

    /// The Badge card: every tone.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn badgeCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Badge in each tone (.mono() for a code)", "ziggui.Badge", ziggui.HStack(.{
            ziggui.Badge("idle", .neutral),
            ziggui.Badge("connected", .success),
            ziggui.Badge("refused", .danger),
            ziggui.Badge("version mismatch", .warning),
            ziggui.Badge("2026-07-28", .info),
            ziggui.Badge("active", .accent),
            ziggui.Badge("-32601", .danger).mono(),
            ziggui.Spacer(),
        }).spacing(6));
    }

    /// The KeyCap card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn keyCapCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "KeyCap", "ziggui.KeyCap", ziggui.HStack(.{
            ziggui.KeyCap("⌘K"),
            ziggui.KeyCap("esc"),
            ziggui.KeyCap("↩"),
            ziggui.KeyCap("tab"),
            ziggui.KeyCap("↑↓"),
            ziggui.KeyCap("ctrl+S"),
            ziggui.Spacer(),
        }).spacing(6));
    }

    /// The ButtonKeyed card: each role, and what was pressed.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn buttonKeyedCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "ButtonKeyed in each role", "ziggui.ButtonKeyed", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.ButtonKeyed("Save", "↩", .prominent, ziggui.Callback.init(Self, self, Self.saved)),
                ziggui.ButtonKeyed("Cancel", "esc", .normal, ziggui.Callback.init(Self, self, Self.cancelled)),
                ziggui.ButtonKeyed("Delete", "⌫", .destructive, ziggui.Callback.init(Self, self, Self.deleted)),
                ziggui.ButtonKeyed("Find", "⌘F", .plain, ziggui.Callback.init(Self, self, Self.found)),
                ziggui.Spacer(),
            }).spacing(8),
            ziggui.Text(self.pressed).font(.footnote).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(10));
    }

    /// The SegmentedControl card: compact and stretched.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn segmentedControlCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "SegmentedControl, compact and stretched", "ziggui.SegmentedControl", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Text("Pane"),
                ziggui.Spacer(),
                ziggui.SegmentedControl(self.view_segment.binding(), &view_options),
            }),
            ziggui.SegmentedControl(self.appearance_segment.binding(), &appearance_options).frameMaxWidth(),
        }).spacing(12));
    }

    /// The IconSegmentedControl card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn iconSegmentedControlCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "IconSegmentedControl", "ziggui.IconSegmentedControl", ziggui.HStack(.{
            ziggui.Text("Mode"),
            ziggui.Spacer(),
            ziggui.IconSegmentedControl(self.mode_segment.binding(), &mode_segments),
        }));
    }

    /// The KeyHintBar card: seven hints, six shown.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn keyHintBarCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "KeyHintBar (seven hints, six shown)", "ziggui.KeyHintBar", ziggui.KeyHintBar(&bar_hints).border(theme.colors.separator, 1));
    }

    /// The SettingRow card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn settingRowCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "SettingRow", "ziggui.SettingRow", ziggui.VStack(.{
            ziggui.SettingRow("Skip initialize", "Send standalone requests to a legacy server, without the initialize handshake or a session.", ziggui.Toggle("", self.skip_initialize.binding())),
            ziggui.Divider(),
            ziggui.SettingRow("Strip inbound auth", "", ziggui.Toggle("", self.strip_auth.binding())),
        }).spacing(10));
    }

    /// The KeyValueEditor card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn keyValueEditorCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "KeyValueEditor", "ziggui.KeyValueEditor", ziggui.KeyValueEditor(&self.headers, "Header", "Value"));
    }

    /// The TokenField card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn tokenFieldCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "TokenField (Enter commits; commas split)", "ziggui.TokenField", ziggui.TokenField(&self.toolsets, "Add toolsets"));
    }

    /// The SearchField card.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn searchFieldCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "SearchField (× clears)", "ziggui.SearchField", ziggui.SearchField("Filter this folder", &self.search, null, null));
    }

    /// The Lists section's rows card: a pane header with its accessory, and
    /// selectable rows in a focused and an unfocused list.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn rowsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const call = ziggui.Callback.init(Self, self, Self.saved);
        return ziggui.VStack(.{
            gallery.Card.view(theme, "PaneHeader", "ziggui.PaneHeader", ziggui.StackBuilder.make(.vertical, 0, .leading, .{ziggui.PaneHeader("deepwiki", "https://mcp.deepwiki.com/mcp · legacy, 2025-11-25", ziggui.HStack(.{
                ziggui.Badge("connected", .success),
                ziggui.Button("Disconnect", call),
                ziggui.ButtonRoled("Call", .prominent, call),
            }).spacing(8))}).background(theme.colors.window_background).cornerRadius(theme.metrics.corner_radius)),
            gallery.Card.view(theme, "SelectableRow: a focused list, then an unfocused one", "ziggui.SelectableRow", ziggui.HStack(.{
                Self.sampleList(&rows_order, &self.row_selection, true, null),
                Self.sampleList(&rows_order, &self.row_selection, false, null),
            }).spacing(16).alignment(.top)),
            gallery.Card.view(theme, "SelectableLabeledRow: a title with its value at the trailing edge", "ziggui.SelectableLabeledRow", self.labeledList()),
        }).spacing(16);
    }

    /// The labeled rows card's list: each row's icon and title, its value
    /// at the trailing edge, the selected row in a focused list.
    ///
    /// - `self`: the kit.
    /// - Returns: the list.
    fn labeledList(self: *Self) ziggui.View {
        const rows = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, labeled_rows.len) catch @panic("oom");
        for (labeled_rows, rows, 0..) |entry, *row, index| {
            const tapped = ziggui.Callback.tagged(Self, self, Self.labeledTapped, index);
            row.* = ziggui.SelectableLabeledRow(entry[0], entry[1], entry[2], index == self.labeled_selected, true, tapped);
        }
        return ziggui.StackBuilder.fromSlice(.vertical, row_spacing, .leading, rows).frameMaxWidth();
    }

    /// The labeled field card: a label over a field drawn in the chrome a
    /// composed field draws around itself, with help under it.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn labeledFieldCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const field = ziggui.FieldChrome(ziggui.Text("https://mcp.deepwiki.com/mcp").truncated().padding(6).frameMaxWidth().frameAlign(.leading));
        return gallery.Card.view(theme, "LabeledField, around a field drawn in FieldChrome", "ziggui.LabeledField · ziggui.FieldChrome", ziggui.LabeledField("Server", field, "Where the client connects; only https is allowed.").frameMaxWidth());
    }

    /// The List card: rows in a scrolling list with hairlines between them.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn listCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "List: rows with hairlines between them", "ziggui.List", ziggui.List(.{
            ziggui.Text("Wi-Fi").frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Bluetooth").frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Network").frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Notifications").frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Sound").frameMaxWidth().frameAlign(.leading),
        }).frameMaxWidth().frameHeight(150));
    }

    /// The pane card: a pane's title over a divider, accented while the pane
    /// has the focus, with a trailing action, over what the empty pane says.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn paneCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const call = ziggui.Callback.init(Self, self, Self.saved);
        return gallery.Card.view(theme, "A pane's title, and what an empty pane says", "ziggui.PaneTitle · ziggui.EmptyState", ziggui.VStack(.{
            ziggui.PaneTitle("Inbox", true, ziggui.Button("Refresh", call)),
            ziggui.EmptyState("No messages", "New mail shows up here."),
        }).spacing(0).frameMaxWidth().frameHeight(170).background(theme.colors.window_background).cornerRadius(theme.metrics.corner_radius));
    }

    /// A click on a row of the Lists section's labeled rows card: selects it.
    ///
    /// - `self`: the kit.
    /// - `index`: the row.
    fn labeledTapped(self: *Self, index: usize) void {
        self.labeled_selected = index;
    }

    /// The Lists section's reorder cards: a list whose rows drag up and down, and one held
    /// mid-drag. The live list's finished drag reorders it here.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn reorderPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        if (self.reorder.takeMove()) |move| move.apply(usize, &self.reorder_order);
        self.reorder_preview = reorder_frozen;
        return ziggui.VStack(.{
            gallery.Card.view(theme, "ReorderableRow: drag a row up or down", "ziggui.ReorderableRow", Self.sampleList(&self.reorder_order, &self.reorder_selection, true, &self.reorder)),
            gallery.Card.view(theme, "Mid-drag: the second row held two rows down", "ziggui.ReorderableRow", Self.sampleList(&reorder_start, &self.reorder_selection, true, &self.reorder_preview)),
        }).spacing(16);
    }

    /// The Lists section's outline: a folder tree whose folders fold (a tap on a
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
            gallery.Card.view(theme, "OutlineRow: tap a folder to fold or unfold it", "ziggui.OutlineState · ziggui.OutlineRow", ziggui.VStack(.{ buttons, list }).spacing(10).frameMaxWidth()),
        }).spacing(16);
    }

    /// The Files section: a `FileBrowser` over the fixture folder with a
    /// text-files-only filter, what it would pick, and the system's open and
    /// save panels (`FileDialog`) started in the folder on show.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn filesPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const secondary = ziggui.BuildScope.shared().tokens().secondary_label;
        self.takeDialog() catch @panic("oom");
        self.files.shows_file = if (self.text_only.get()) Self.isText else null;
        const said = if (self.files.pickAlloc(allocator) catch @panic("oom")) |pick|
            allocator.print("Picks the {s} {s}", .{ if (pick.kind == .directory) "folder" else "file", pick.path }) catch @panic("oom")
        else
            "Picks nothing: the selection does not show (hidden, or filtered out).";
        return ziggui.VStack(.{
            gallery.Card.view(theme, "FileBrowser: a tap selects and gives it the arrow keys, a double-click or Return opens a folder", "ziggui.FileBrowser · FileBrowserState.shows_file", ziggui.VStack(.{
                ziggui.FileBrowser(&self.files, self.files_have_keys).frameHeight(200),
                ziggui.Toggle("Only .txt and .md files (folders always show)", self.text_only.binding()).toggleStyle(.checkbox),
            }).spacing(10).alignment(.leading)),
            ziggui.Text(said).foreground(secondary).truncated().frameMaxWidth().frameAlign(.leading),
            gallery.Card.view(theme, "FileDialog: the system's open and save panels, started in the folder on show", "ziggui.FileDialog.openFile · .saveFile · .takeResult", ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.Button("Open File…", ziggui.Callback.attempt(Self, self, Self.openFile, "open panel not shown")),
                    ziggui.Button("Save As…", ziggui.Callback.attempt(Self, self, Self.saveFile, "save panel not shown")),
                    ziggui.Spacer(),
                }).spacing(10),
                ziggui.Text(self.dialog_said orelse "No panel shown yet.").foreground(secondary).truncated().frameMaxWidth().frameAlign(.leading),
            }).spacing(10).alignment(.leading)),
        }).spacing(16);
    }

    /// The Lists section's rename card: rows selected by a click, each name renamed
    /// in place by a further click on it, and what was renamed last.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn editablePanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const rows = allocator.alloc(ziggui.View, rename_start.len) catch @panic("oom");
        if (self.rename_on_show) |index| {
            self.rename_on_show = null;
            self.rename_selection.set(@intCast(index));
            self.rename_items[index].beginEditing() catch @panic("oom");
        }
        for (rename_start, &self.rename_items, rows, 0..) |start, *item, *row, index| {
            const selected = self.rename_selection.get() == @as(i64, @intCast(index));
            const color = ziggui.SelectableRowStyle.selectionText(selected, true);
            const tapped = ziggui.Callback.tagged(Self, self, Self.renameTapped, index);
            const name = ziggui.EditableText(item, selected, tapped, ziggui.Callback.tagged(Self, self, Self.renamed, index));
            // Editing, the field keeps its own colors on the selection's accent
            // and takes the rest of the row.
            const content = if (item.editing)
                ziggui.HStack(.{ ziggui.Icon(start[0], 13, color), name })
            else
                ziggui.HStack(.{ ziggui.Icon(start[0], 13, color), name.foreground(color), ziggui.Spacer() });
            row.* = ziggui.SelectableRow(content.spacing(6), selected, true, tapped);
        }
        const said = if (self.renamed_last) |index|
            allocator.print("Renamed “{s}” to “{s}”.", .{ rename_start[index][1], self.rename_items[index].text() }) catch @panic("oom")
        else
            "Select a row, then click its name again to rename it. Enter saves, Esc cancels.";
        return ziggui.VStack(.{
            gallery.Card.view(theme, "EditableText: a selected row's name renamed in place, as Finder renames", "ziggui.EditableText · ziggui.EditableTextState", ziggui.VStack(.{
                ziggui.StackBuilder.fromSlice(.vertical, row_spacing, .leading, rows).frameMaxWidth(),
                ziggui.Text(said).foreground(theme.colors.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            }).spacing(10).frameMaxWidth()),
        }).spacing(16);
    }

    /// The DisclosureGroup card: a header whose chevron folds its content
    /// away, and one with an accessory (a count) at its trailing edge.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn disclosureCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const secondary = theme.colors.secondary_label;
        return gallery.Card.view(theme, "DisclosureGroup: tap a header to fold its content away", "ziggui.DisclosureGroup · ziggui.DisclosureGroupAccessory", ziggui.VStack(.{
            ziggui.DisclosureGroup(
                ziggui.Text("Advanced"),
                self.disclosure_open,
                ziggui.Callback.init(Self, self, Self.toggleDisclosure),
                ziggui.WrappedText("Content shown while the group is open, folded away under its header otherwise.").foreground(secondary),
            ),
            ziggui.DisclosureGroupAccessory(
                ziggui.Text("Downloads"),
                ziggui.Badge("3", .neutral),
                self.accessory_open,
                ziggui.Callback.init(Self, self, Self.toggleAccessory),
                ziggui.VStack(.{ ziggui.Text("report.pdf"), ziggui.Text("photo.jpg"), ziggui.Text("notes.txt") }).spacing(4).alignment(.leading),
            ),
        }).spacing(10).alignment(.leading));
    }

    /// Opens or folds the DisclosureGroup card's first group.
    ///
    /// - `self`: the kit.
    fn toggleDisclosure(self: *Self) void {
        self.disclosure_open = !self.disclosure_open;
    }

    /// Opens or folds the DisclosureGroup card's group with an accessory.
    ///
    /// - `self`: the kit.
    fn toggleAccessory(self: *Self) void {
        self.accessory_open = !self.accessory_open;
    }

    /// The CheckList card: a choice as macOS lists one, the chosen row checked;
    /// a tap anywhere on a row chooses it.
    ///
    /// - `self`: the kit.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn checkListCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const rows = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, check_options.len) catch @panic("oom");
        for (check_options, rows, 0..) |option, *row, index| {
            const content = ziggui.VStack(.{
                ziggui.Text(option[0]),
                ziggui.Text(option[1]).font(.footnote).foreground(theme.colors.secondary_label),
            }).spacing(2).alignment(.leading);
            row.* = ziggui.CheckRow(content, self.check_choice.get() == @as(i64, @intCast(index)), ziggui.Callback.tagged(Self, self, Self.checkChosen, index));
        }
        return gallery.Card.view(theme, "CheckList: a choice in a grouped list, the chosen row checked", "ziggui.CheckList · ziggui.CheckRow", ziggui.CheckList(rows));
    }

    /// Gives a key to the Lists section's rename card's row being renamed: Esc cancels it.
    ///
    /// - `self`: the kit.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a row took it.
    pub fn editableKeyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        for (&self.rename_items) |*item| {
            if (item.keyDown(keycode, modifiers)) return true;
        }
        return false;
    }

    /// The Lists section's rename card's rows' states, with their names at start;
    /// those made are released again when one fails.
    ///
    /// - `allocator`: owns the names.
    /// - Returns: the states; propagates allocation failure.
    fn renameItems(allocator: std.mem.Allocator) std.mem.Allocator.Error![rename_start.len]ziggui.EditableTextState {
        var items: [rename_start.len]ziggui.EditableTextState = undefined;
        var made: usize = 0;
        errdefer for (items[0..made]) |*item| item.deinit();
        for (rename_start, &items) |start, *item| {
            item.* = try ziggui.EditableTextState.init(allocator, start[1]);
            made += 1;
        }
        return items;
    }

    /// A tap on a CheckList row: chooses it.
    ///
    /// - `self`: the kit.
    /// - `index`: the row.
    fn checkChosen(self: *Self, index: usize) void {
        self.check_choice.set(@intCast(index));
    }

    /// A click on a row of the Lists section's rename card, or on its name: selects it.
    ///
    /// - `self`: the kit.
    /// - `index`: the row.
    fn renameTapped(self: *Self, index: usize) void {
        self.rename_selection.set(@intCast(index));
    }

    /// A row of the Lists section's rename card had its name committed changed.
    ///
    /// - `self`: the kit.
    /// - `index`: the row.
    fn renamed(self: *Self, index: usize) void {
        self.renamed_last = index;
    }

    /// Whether the Files section's filter shows a file: a `.txt` or `.md` one.
    ///
    /// - `name`: the file's name.
    /// - Returns: true for a text file.
    fn isText(name: []const u8) bool {
        return std.mem.endsWith(u8, name, ".txt") or std.mem.endsWith(u8, name, ".md");
    }

    /// Shows the system's open-file panel in the folder on show.
    ///
    /// - `self`: the kit.
    /// - Returns: nothing; propagates allocation failure.
    fn openFile(self: *Self) std.mem.Allocator.Error!void {
        const location = try self.allocator.dupeSentinel(u8, self.files.path.items, 0);
        try self.showDialog(location, self.platform.openFile(location));
    }

    /// Shows the system's save panel in the folder on show, its name "Untitled.txt".
    ///
    /// - `self`: the kit.
    /// - Returns: nothing; propagates allocation failure.
    fn saveFile(self: *Self) std.mem.Allocator.Error!void {
        const location = try std.fs.path.joinZ(self.allocator, &.{ self.files.path.items, "Untitled.txt" });
        try self.showDialog(location, self.platform.saveFile(location));
    }

    /// Keeps a shown dialog's starting place until its outcome is taken, or
    /// says why none showed.
    ///
    /// - `self`: the kit.
    /// - `location`: where it was asked to start, owned by `self.allocator`.
    /// - `shown`: whether the platform showed it.
    /// - Returns: nothing; propagates allocation failure.
    fn showDialog(self: *Self, location: [:0]u8, shown: bool) std.mem.Allocator.Error!void {
        if (!shown) {
            self.allocator.free(location);
            try self.say(if (self.dialog_location == null) "No window to show a panel over." else "A panel is already up.");
            return;
        }
        self.dialog_location = location;
    }

    /// Takes a finished dialog's outcome into `dialog_said`, and lets its
    /// starting place go.
    ///
    /// - `self`: the kit.
    /// - Returns: nothing; propagates allocation failure.
    fn takeDialog(self: *Self) std.mem.Allocator.Error!void {
        switch (self.platform.takeFile(self.allocator)) {
            .none => return,
            .canceled => try self.say("Cancelled."),
            .picked => |path| {
                defer self.allocator.free(path);
                const words = try self.allocator.print("Picked {s}", .{path});
                defer self.allocator.free(words);
                try self.say(words);
            },
        }
        if (self.dialog_location) |location| self.allocator.free(location);
        self.dialog_location = null;
    }

    /// Replaces what the Files section says about its dialogs.
    ///
    /// - `self`: the kit.
    /// - `words`: the new words, copied.
    /// - Returns: nothing; propagates allocation failure.
    fn say(self: *Self, words: []const u8) std.mem.Allocator.Error!void {
        const copy = try self.allocator.dupe(u8, words);
        if (self.dialog_said) |said| self.allocator.free(said);
        self.dialog_said = copy;
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

test "the File Browser panel's filter keeps folders and text files, and its panels say what they left" {
    const Probe = struct {
        const Self = @This();

        /// Whether the last panel was asked to start at the name "Untitled.txt".
        var asked_untitled = false;

        /// Shows a panel: notes whether it starts at "Untitled.txt".
        ///
        /// - `location`: where it starts.
        /// - Returns: true.
        fn show(location: [:0]const u8) bool {
            Self.asked_untitled = std.mem.endsWith(u8, location, "Untitled.txt");
            return true;
        }

        /// The panel picked a file.
        ///
        /// - `allocator`: owns the path.
        /// - Returns: a picked path.
        fn picked(allocator: std.mem.Allocator) gallery.FileDialogOutcome {
            return .{ .picked = allocator.dupe(u8, "/tmp/notes.txt") catch @panic("oom") };
        }
    };
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    // Headless, the buttons show nothing and say so.
    try kit.openFile();
    try std.testing.expectEqualStrings("No window to show a panel over.", kit.dialog_said.?);
    try std.testing.expect(kit.dialog_location == null);

    kit.text_only.set(true);
    window.begin(ziggui.MacosTheme.light);
    _ = kit.filesPanel(ziggui.MacosTheme.light);
    window.end();
    for (kit.files.nodes) |node| {
        const shown = (node.kind == .directory and !node.hidden) or std.mem.eql(u8, node.name, "readme.txt");
        try std.testing.expectEqual(shown, kit.files.shows(node));
    }

    // A panel starts in the folder on show and keeps that place until its outcome is taken.
    kit.platform = .{ .save_file_fn = Probe.show, .take_file_fn = Probe.picked };
    try kit.saveFile();
    try std.testing.expect(Probe.asked_untitled);
    try std.testing.expect(kit.dialog_location != null);
    window.begin(ziggui.MacosTheme.light);
    _ = kit.filesPanel(ziggui.MacosTheme.light);
    window.end();
    try std.testing.expectEqualStrings("Picked /tmp/notes.txt", kit.dialog_said.?);
    try std.testing.expect(kit.dialog_location == null);
}

test "the Lists section's rename card selects a row on a click, renames it on a later one, and Esc cancels" {
    var kit = try Kit.init(std.testing.allocator);
    defer kit.deinit();
    defer ziggui.Focus.shared().clear();
    const clock = ziggui.FrameClock.shared();
    defer clock.setTime(0);
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    // A click on the second row's name selects it and arms nothing.
    kit.rename_items[1].press();
    try std.testing.expect(kit.rename_items[1].armed_at == null);
    kit.renameTapped(1);

    // Drawn selected, a later click with the pointer resting arms the edit, which starts after the delay.
    clock.setTime(500);
    window.begin(ziggui.MacosTheme.light);
    _ = kit.editablePanel(ziggui.MacosTheme.light);
    window.end();
    ziggui.EditableTextState.hoverChanged(&kit.rename_items[1], true);
    kit.rename_items[1].press();
    clock.setTime(500 + ziggui.EditableTextState.edit_delay_ms);
    window.begin(ziggui.MacosTheme.light);
    _ = kit.editablePanel(ziggui.MacosTheme.light);
    window.end();
    try std.testing.expect(kit.rename_items[1].editing);

    // Esc, through the panel's keys, puts the name back.
    try kit.rename_items[1].field.setText("Draft.txt");
    try std.testing.expect(kit.editableKeyDown(ziggui.SdlKey.escape, 0));
    try std.testing.expectEqualStrings("Notes.txt", kit.rename_items[1].text());

    // A committed change is what the panel reports.
    try kit.rename_items[1].beginEditing();
    try kit.rename_items[1].field.setText("Ideas.txt");
    kit.rename_items[1].commit();
    try std.testing.expectEqual(@as(?usize, 1), kit.renamed_last);
    try std.testing.expectEqualStrings("Ideas.txt", kit.rename_items[1].text());
}
