const std = @import("std");
const log = std.log.scoped(.ziggui_gallery);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// One page of the gallery, in sidebar order.
///
/// Adding a component to the gallery means a variant here, its `label` and
/// `icon`, and a panel in `Gallery.panel`.
pub const Section = enum {
    const Self = @This();

    /// The chat pieces: status marks, chips, a disclosure group, blocks.
    chat,

    /// The list | detail panes: table rows over a virtual list, a diff.
    panes,

    /// The split views.
    split,

    /// Every section, as sidebar rows.
    pub const items = blk: {
        const values = @typeInfo(Self).@"enum".field_values;
        var rows: [values.len]ziggui.SidebarItem = undefined;
        for (values, 0..) |value, i| {
            const section: Self = @fromBackingInt(value);
            rows[i] = .{ .label = section.label(), .icon = section.icon() };
        }
        break :blk rows;
    };

    /// The section's name in the sidebar and as its panel's title.
    ///
    /// - `self`: the section.
    /// - Returns: the name.
    pub fn label(self: *const Self) []const u8 {
        return switch (self.*) {
            .chat => "Chat",
            .panes => "Panes",
            .split => "Split Views",
        };
    }

    /// The section's sidebar icon.
    ///
    /// - `self`: the section.
    /// - Returns: the icon.
    pub fn icon(self: *const Self) ziggui.IconName {
        return switch (self.*) {
            .chat => .message_square,
            .panes => .table,
            .split => .layout_panel_left,
        };
    }

    /// The section at sidebar row `index`, clamped to the rows there are.
    ///
    /// - `index`: a sidebar selection.
    /// - Returns: the section.
    pub fn at(index: i64) Self {
        const last: i64 = Self.items.len - 1;
        return @fromBackingInt(@intCast(std.math.clamp(index, 0, last)));
    }
};

/// The theme families' display names, for the switcher's radio list, in
/// `ziggui.theme_registry.all` order.
const family_names = blk: {
    var names: [ziggui.theme_registry.all.len][]const u8 = undefined;
    for (ziggui.theme_registry.all, 0..) |family, i| names[i] = family.displayName();
    break :blk names;
};

/// One color the accent switcher offers.
const Accent = struct {
    const Self = @This();

    /// The color's name.
    name: []const u8,

    /// The color drawn as the accent and selection; null keeps the theme's own.
    color: ?ziggui.Color,

    /// The color the swatch shows.
    swatch: ziggui.Color,
};

/// The accent switcher's colors, in display order. The first keeps each
/// theme's own accent (macOS uses distinct blues for accent and selection).
const accents = [_]Accent{
    .{ .name = "Theme", .color = null, .swatch = ziggui.Color.fromRgb8(0, 122, 255) },
    .{ .name = "Purple", .color = ziggui.Color.fromRgb8(147, 112, 219), .swatch = ziggui.Color.fromRgb8(147, 112, 219) },
    .{ .name = "Pink", .color = ziggui.Color.fromRgb8(255, 55, 95), .swatch = ziggui.Color.fromRgb8(255, 55, 95) },
    .{ .name = "Green", .color = ziggui.Color.fromRgb8(40, 180, 99), .swatch = ziggui.Color.fromRgb8(40, 180, 99) },
    .{ .name = "Orange", .color = ziggui.Color.fromRgb8(255, 149, 0), .swatch = ziggui.Color.fromRgb8(255, 149, 0) },
};

/// The Panes panel's table columns.
const file_columns = [_]ziggui.DataColumn{
    .{ .title = "Name" },
    .{ .title = "Kind", .width = 90 },
    .{ .title = "Size", .width = 70, .trailing = true },
};

/// How many rows the Panes panel's virtual list holds.
const file_count: usize = 10_000;

/// The height of one of the Panes panel's table rows, in points.
const file_row_h: f32 = 24;

/// How many of the sample diff's rows show at once; the rest scroll.
const diff_rows_shown: f32 = 10;

/// The Panes panel's sample diff: two files, three hunks.
const sample_diff = [_]ziggui.DiffLine{
    .{ .kind = .fileHeader, .text = "src/split.zig" },
    .{ .kind = .hunkHeader, .text = "@@ -12,6 +12,7 @@ const View = zigui.View;" },
    .{ .kind = .context, .text = "pub const SplitState = struct {", .old = 12, .new = 12 },
    .{ .kind = .context, .text = "\tconst Self = @This();", .old = 13, .new = 13 },
    .{ .kind = .removed, .text = "\tsize: f32 = 0,", .old = 14 },
    .{ .kind = .added, .text = "\tsize: f32 = -1,", .new = 14 },
    .{ .kind = .added, .text = "\tinitial_ratio: f32 = 0.5,", .new = 15 },
    .{ .kind = .context, .text = "};", .old = 15, .new = 16 },
    .{ .kind = .hunkHeader, .text = "@@ -40,4 +41,4 @@ pub fn HSplitView(" },
    .{ .kind = .removed, .text = "\treturn SplitView(.horizontal, state, first, second);", .old = 40 },
    .{ .kind = .added, .text = "\treturn Split.view(.horizontal, state, first, second);", .new = 41 },
    .{ .kind = .fileHeader, .text = "src/chat.zig" },
    .{ .kind = .hunkHeader, .text = "@@ -60,3 +60,3 @@" },
    .{ .kind = .removed, .text = "pub fn Disclosure(header: View, expanded: bool) View {", .old = 60 },
    .{ .kind = .added, .text = "pub fn DisclosureGroup(header: View, expanded: bool) View {", .new = 60 },
    .{ .kind = .note, .text = "\\ No newline at end of file" },
};

/// The ziggui component gallery: a sidebar of sections, one panel per
/// section, and theme and appearance switchers that recolor it live.
///
/// Holds every piece of state the panels bind to, so the window and the
/// headless screenshot draw the same thing from the same value.
pub const Gallery = struct {
    const Self = @This();

    /// Allocates the state the panels bind to.
    allocator: std.mem.Allocator,

    /// The sidebar row shown, an index into `Section.items`.
    section: ziggui.State(i64),

    /// Whether the window draws in its dark appearance.
    dark: ziggui.State(bool),

    /// The theme family drawn, an index into `ziggui.theme_registry.all`.
    theme_family: ziggui.State(i64),

    /// The accent drawn, an index into the accent switcher's colors.
    accent: ziggui.State(i64),

    /// The detail pane's scroll position.
    scroll: ziggui.ScrollState = .{},

    /// Whether the Chat panel's tool call is unfolded.
    tool_open: bool = false,

    /// The Panes panel's virtual list position.
    files_scroll: ziggui.ScrollState = .{},

    /// The Panes panel's selected table row.
    file_selected: usize = 2,

    /// The Panes panel's diff position.
    diff_scroll: ziggui.ScrollState = .{},

    /// The Panes panel's selected hunk.
    hunk_selected: usize = 0,

    /// The Split Views panel's column divider.
    columns: ziggui.SplitState = .{ .initial_ratio = 0.35, .min_first = 120, .min_second = 160 },

    /// The Split Views panel's row divider.
    rows: ziggui.SplitState = .{ .initial_ratio = 0.5, .min_first = 60, .min_second = 60 },

    /// Constructs a gallery on its first section, light, in the first theme
    /// family with its own accent.
    ///
    /// - `allocator`: allocator for the state; must outlive the gallery.
    /// - Returns: the gallery; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const self = Self{
            .allocator = allocator,
            .section = ziggui.State(i64).init(allocator, 0),
            .dark = ziggui.State(bool).init(allocator, false),
            .theme_family = ziggui.State(i64).init(allocator, 0),
            .accent = ziggui.State(i64).init(allocator, 0),
        };
        return self;
    }

    /// Releases the gallery's state.
    ///
    /// - `self`: the gallery to tear down.
    pub fn deinit(self: *Self) void {
        self.accent.deinit();
        self.theme_family.deinit();
        self.dark.deinit();
        self.section.deinit();
    }

    /// The theme the switchers select.
    ///
    /// - `self`: the gallery.
    /// - Returns: the theme family in its light or dark scheme, recolored with
    ///   the chosen accent.
    pub fn theme(self: *const Self) ziggui.Theme {
        const last_family: i64 = ziggui.theme_registry.all.len - 1;
        const family = ziggui.theme_registry.all[@intCast(std.math.clamp(self.theme_family.get(), 0, last_family))];
        const scheme: ziggui.ColorScheme = if (self.dark.get()) .dark else .light;
        var th = ziggui.themeForScheme(family, scheme);
        if (accents[self.accentIndex()].color) |color| {
            th.colors.accent = color;
            th.colors.selection = color;
        }
        return th;
    }

    /// Builds the window's view tree: the sidebar beside the selected panel.
    ///
    /// Called once per frame, inside zigui's `beginBuild`/`endBuild`.
    ///
    /// - `self`: the gallery supplying the state.
    /// - Returns: the root view.
    pub fn body(self: *Self) ziggui.View {
        const th = self.theme();
        return ziggui.NavigationSplitView(
            self.sidebar(th),
            self.detail(th),
            th.colors.sidebar_background orelse th.colors.secondary_background,
        );
    }

    /// Folds or unfolds the Chat panel's tool call.
    ///
    /// - `self`: the gallery.
    pub fn toggleTool(self: *Self) void {
        self.tool_open = !self.tool_open;
    }

    /// Selects a row of the Panes panel's table.
    ///
    /// - `self`: the gallery.
    /// - `index`: the row.
    pub fn selectFile(self: *Self, index: usize) void {
        self.file_selected = index;
    }

    /// Selects a hunk of the Panes panel's diff.
    ///
    /// - `self`: the gallery.
    /// - `index`: the hunk.
    pub fn selectHunk(self: *Self, index: usize) void {
        self.hunk_selected = index;
    }

    /// The sidebar: the title, a row per section, then the switchers.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the sidebar view.
    fn sidebar(self: *Self, th: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Icon(.boxes, 20, th.colors.accent),
                ziggui.Text("ziggui").font(.headline),
                ziggui.Spacer(),
            }).spacing(8).paddingInsets(.{ .top = 8, .leading = 10, .bottom = 4, .trailing = 8 }),
            ziggui.Sidebar(&Section.items, self.section.binding()),
            ziggui.Spacer(),
            ziggui.Divider(),
            ziggui.VStack(.{
                Self.leading(ziggui.Text("Theme").font(.footnote).foreground(th.colors.secondary_label)),
                ziggui.RadioGroup(self.theme_family.binding(), &family_names),
            }).spacing(6).padding(6),
            ziggui.HStack(.{ ziggui.Text("Dark mode"), ziggui.Spacer(), ziggui.Toggle("", self.dark.binding()) })
                .frameMaxWidth()
                .padding(6),
            ziggui.VStack(.{
                Self.leading(ziggui.Text("Accent").font(.footnote).foreground(th.colors.secondary_label)),
                self.accentSwatches(th),
            }).spacing(6).padding(6),
        }).spacing(4).padding(8).frameMaxHeight().backgroundMaterial(.thin);
    }

    /// The accent switcher: a row of tappable color dots, the chosen one ringed.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the row.
    fn accentSwatches(self: *Self, th: ziggui.Theme) ziggui.View {
        const chosen = self.accentIndex();
        // The stack copies its children into the frame's build arena.
        var dots: [accents.len + 1]ziggui.View = undefined;
        for (accents, 0..) |accent, i| {
            const dot = if (i == chosen) ziggui.ZStack(.{
                ziggui.Circle(th.colors.label).frame(22, 22),
                ziggui.Circle(th.colors.window_background).frame(18, 18),
                ziggui.Circle(accent.swatch).frame(14, 14),
            }) else ziggui.ZStack(.{
                ziggui.Circle(accent.swatch).frame(16, 16),
            });
            dots[i] = dot.frame(22, 22).onTap(ziggui.selectAction(self.accent.binding(), @intCast(i)));
        }
        dots[accents.len] = ziggui.Spacer();
        return ziggui.HStack(@as([]const ziggui.View, &dots)).spacing(10).frameMaxWidth();
    }

    /// The selected section's panel, scrolled as a whole.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the detail view.
    fn detail(self: *Self, th: ziggui.Theme) ziggui.View {
        const section = Section.at(self.section.get());
        const content = ziggui.VStack(.{
            Self.leading(ziggui.Text(section.label()).font(.large_title)),
            self.panel(section, th),
        }).spacing(16);
        return ziggui.ScrollViewState(&self.scroll, content.padding(20).frameMaxWidth())
            .frameMaxWidth()
            .frameMaxHeight();
    }

    /// The body of `section`'s panel, below its title.
    ///
    /// - `self`: the gallery.
    /// - `section`: the section to draw.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn panel(self: *Self, section: Section, th: ziggui.Theme) ziggui.View {
        return switch (section) {
            .chat => self.chatPanel(th),
            .panes => self.panesPanel(th),
            .split => self.splitPanel(th),
        };
    }

    /// The Chat panel: status marks, chips, and a transcript of blocks.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn chatPanel(self: *Self, th: ziggui.Theme) ziggui.View {
        const toggle = ziggui.actionCtx(Self, self, Self.toggleTool);
        return ziggui.VStack(.{
            Self.card(th, "Status marks", ziggui.HStack(.{
                ziggui.StatusMark(.idle, 10),     ziggui.Text("idle").font(.footnote),
                ziggui.StatusMark(.busy, 10),     ziggui.Text("busy").font(.footnote),
                ziggui.StatusMark(.waiting, 10),  ziggui.Text("waiting").font(.footnote),
                ziggui.StatusMark(.starting, 10), ziggui.Text("starting").font(.footnote),
                ziggui.StatusMark(.stopped, 10),  ziggui.Text("stopped").font(.footnote),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(th, "Chips", ziggui.HStack(.{
                ziggui.Chip("Ask before edits", .shield, toggle),
                ziggui.Chip("Opus", .sparkles, toggle),
                ziggui.Chip("screenshot.png · 84 KB", .image, null),
                ziggui.Spacer(),
            }).spacing(8)),
            Self.card(th, "Transcript", ziggui.VStack(.{
                Self.leading(ziggui.Bubble(ziggui.WrappedText("List the files and explain the build."), th.colors.accent.withAlpha(0.16))),
                ziggui.DisclosureGroup(
                    ziggui.Text("ls -la").font(.footnote).mono(),
                    self.tool_open,
                    toggle,
                    ziggui.CodeBlock("build.zig\nbuild.zig.zon\nsrc/"),
                ),
                ziggui.WrappedText("The build is driven by build.zig:"),
                ziggui.CodeBlock("pub fn build(b: *std.Build) void {\n    // ...\n}"),
                ziggui.Quote(ziggui.WrappedText("Tip: run zig build test after every change.").foreground(th.colors.secondary_label)),
            }).spacing(10).alignment(.leading)),
        }).spacing(16);
    }

    /// The Panes panel: a long table over a virtual list, and a diff.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn panesPanel(self: *Self, th: ziggui.Theme) ziggui.View {
        const on_hunk = ziggui.IndexCallback.init(Self, self, Self.selectHunk);
        return ziggui.VStack(.{
            Self.card(th, "Table rows over a virtual list (10,000 rows)", ziggui.VStack(.{
                ziggui.TableHeader(&file_columns),
                ziggui.VirtualList(Self, self, file_count, file_row_h, &self.files_scroll, Self.fileRow).frameHeight(150),
            }).spacing(0)),
            Self.card(th, "DiffView (tap a row to select its hunk)", ziggui.VStack(.{
                ziggui.DiffView(&sample_diff, self.hunk_selected, &self.diff_scroll, on_hunk),
            }).spacing(0).frameHeight(diff_rows_shown * ziggui.diff_row_h)),
        }).spacing(16);
    }

    /// Row `index` of the Panes panel's table.
    ///
    /// - `self`: the gallery.
    /// - `index`: the row.
    /// - Returns: the row.
    fn fileRow(self: *const Self, index: usize) ziggui.View {
        const alloc = ziggui.buildAlloc();
        const name = alloc.print("file-{d:0>5}.zig", .{index}) catch @panic("oom");
        const size = alloc.print("{d} KB", .{(index * 37) % 512 + 1}) catch @panic("oom");
        const kind = if (index % 3 == 0) "Test" else "Source";
        const cells = alloc.dupe(ziggui.View, &.{
            ziggui.Text(name).truncated(),
            ziggui.Text(kind).foreground(ziggui.buildTokens().secondary_label),
            ziggui.Text(size).mono(),
        }) catch @panic("oom");
        // `select` takes `*Self`; the list's rows only read the gallery.
        const select = ziggui.IndexCallback.init(Self, @constCast(self), Self.selectFile);
        return ziggui.TableRow(&file_columns, cells, index, index == self.file_selected)
            .onTap(select.bind(index));
    }

    /// The Split Views panel: an `HSplitView` whose trailing pane is a `VSplitView`.
    ///
    /// - `self`: the gallery.
    /// - `th`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn splitPanel(self: *Self, th: ziggui.Theme) ziggui.View {
        const split = ziggui.HSplitView(
            &self.columns,
            Self.pane(th, "Sidebar", "Drag the divider to resize."),
            ziggui.VSplitView(
                &self.rows,
                Self.pane(th, "Top", "HSplitView and VSplitView, as SwiftUI names them."),
                Self.pane(th, "Bottom", "Each pane is laid out at the size the split gives it."),
            ),
        );
        return Self.card(th, "HSplitView over a VSplitView", split
            .frameMaxWidth()
            .frameHeight(260)
            .border(th.colors.separator, 1));
    }

    /// A split view's sample pane: a title and a line of text, top-leading.
    ///
    /// - `th`: the theme this frame draws with.
    /// - `title`: the pane's title.
    /// - `text`: the pane's text.
    /// - Returns: the pane.
    fn pane(th: ziggui.Theme, title: []const u8, text: []const u8) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            ziggui.WrappedText(text).foreground(th.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.Spacer(),
        }).spacing(6).padding(12).frameMaxWidth().frameMaxHeight();
    }

    /// A titled group: a headline above a rounded block in the secondary background.
    ///
    /// - `th`: the theme this frame draws with.
    /// - `title`: the group's headline.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(th: ziggui.Theme, title: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            content.frameMaxWidth()
                .padding(14)
                .background(th.colors.secondary_background)
                .cornerRadius(th.metrics.corner_radius)
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

    /// The chosen accent, clamped to the colors there are.
    ///
    /// - `self`: the gallery.
    /// - Returns: an index into the accent switcher's colors.
    fn accentIndex(self: *const Self) usize {
        const last: i64 = accents.len - 1;
        return @intCast(std.math.clamp(self.accent.get(), 0, last));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Gallery);
}

test "every section has a sidebar row" {
    try std.testing.expectEqual(@typeInfo(Section).@"enum".field_values.len, Section.items.len);
    try std.testing.expectEqualStrings("Chat", Section.items[0].label);
}

test "a selection past the last row shows the last section" {
    try std.testing.expectEqual(Section.chat, Section.at(-1));
    try std.testing.expectEqual(@as(Section, @fromBackingInt(@intCast(Section.items.len - 1))), Section.at(99));
}

test "the gallery draws every section, light and dark" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    for (0..Section.items.len) |index| {
        for ([_]bool{ false, true }) |dark| {
            shown.section.set(@intCast(index));
            shown.dark.set(dark);
            const rgba = try gallery.Screenshot.render(allocator, &shown, gallery.test_width, gallery.test_height);
            defer allocator.free(rgba);
            try std.testing.expectEqual(gallery.test_width * gallery.test_height * 4, rgba.len);
        }
    }
}

test "the split views resolve their dividers when drawn" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.split));
    const rgba = try gallery.Screenshot.render(allocator, &shown, gallery.test_width, gallery.test_height);
    defer allocator.free(rgba);
    try std.testing.expect(shown.columns.total > 0 and shown.columns.resolved(shown.columns.total) > 0);
    try std.testing.expect(shown.rows.total > 0 and shown.rows.resolved(shown.rows.total) > 0);
    try std.testing.expectEqual(ziggui.Axis.vertical, shown.rows.axis);
}

test "the panel callbacks fold the tool call and select a row and a hunk" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.toggleTool();
    try std.testing.expect(shown.tool_open);
    shown.selectFile(7);
    try std.testing.expectEqual(@as(usize, 7), shown.file_selected);
    shown.selectHunk(2);
    try std.testing.expectEqual(@as(usize, 2), shown.hunk_selected);
}

test "an accent recolors the accent and selection; the first keeps the theme's own" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    const own = shown.theme();
    try std.testing.expectEqual(ziggui.themeForScheme(ziggui.theme_registry.all[0], .light).colors.accent, own.colors.accent);

    shown.accent.set(1);
    const recolored = shown.theme();
    try std.testing.expectEqual(accents[1].color.?, recolored.colors.accent);
    try std.testing.expectEqual(accents[1].color.?, recolored.colors.selection);

    shown.accent.set(99);
    try std.testing.expectEqual(accents[accents.len - 1].color.?, shown.theme().colors.accent);
}
