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

    /// The menu bar.
    menuBar,

    /// The app-drawn title bar and window buttons.
    titleBar,

    /// The status line of the keys that work now.
    statusLine,

    /// A row's details in a popover once the pointer rests on it.
    hover,

    /// Buttons, toggles, a slider, steppers, pickers, a radio group, a text field.
    controls,

    /// The type scale, wrapped text, a label, an icon grid.
    text,

    /// Shapes, a gradient, dividers, an image, a material.
    shapes,

    /// Stacks, grids, a list, a tab view over a scroll view.
    layout,

    /// A table with a header and selectable rows.
    table,

    /// The multi-line `TextEditor`.
    textEditor,

    /// Sheets, alerts, a menu, popovers, `onHover`, a custom title bar, quitting.
    overlays,

    /// Animation, liquid glass, opacity, border and corner radius.
    effects,

    /// A navigation stack and an inset split view.
    navigation,

    /// A `GeometryReader`.
    geometry,

    /// A plain-text editor: toolbar, find bar, status bar, path dialog.
    editor,

    /// Every section, as sidebar rows.
    pub const items = blk: {
        const values = @typeInfo(Self).@"enum".field_values;
        var rows: [values.len]ziggui.SidebarItem = undefined;
        for (values, 0..) |value, index| {
            const section: Self = @fromBackingInt(value);
            rows[index] = .{ .label = section.label(), .icon = section.icon() };
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
            .menuBar => "Menu Bar",
            .titleBar => "Title Bar",
            .statusLine => "Status Line",
            .hover => "Hover Popover",
            .controls => "Controls",
            .text => "Text & Icons",
            .shapes => "Shapes & Media",
            .layout => "Layout",
            .table => "Table",
            .textEditor => "Text Editor",
            .overlays => "Overlays",
            .effects => "Effects",
            .navigation => "Navigation",
            .geometry => "Geometry",
            .editor => "Editor",
        };
    }

    /// The section's sidebar icon.
    ///
    /// - `self`: the section.
    /// - Returns: the icon.
    pub fn icon(self: *const Self) ziggui.IconName {
        return switch (self.*) {
            .chat => .messageSquare,
            .panes => .table,
            .split => .layoutPanelLeft,
            .menuBar => .menu,
            .titleBar => .appWindow,
            .statusLine => .keyboard,
            .hover => .mousePointer,
            .controls => .settings,
            .text => .sparkles,
            .shapes => .image,
            .layout => .boxes,
            .table => .folder,
            .textEditor => .edit,
            .overlays => .layers,
            .effects => .zap,
            .navigation => .send,
            .geometry => .ruler,
            .editor => .fileText,
        };
    }

    /// Reports whether the section's panel fills the detail pane, titling and
    /// scrolling itself (or not scrolling at all), rather than being titled
    /// and scrolled as a whole by the gallery.
    ///
    /// - `self`: the section.
    /// - Returns: true for the panels that fill.
    pub fn fills(self: *const Self) bool {
        return switch (self.*) {
            .table, .textEditor, .navigation, .editor => true,
            else => false,
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
/// `ziggui.ThemeFamily.all` order.
const family_names = blk: {
    var names: [ziggui.ThemeFamily.all.len][]const u8 = undefined;
    for (ziggui.ThemeFamily.all, 0..) |family, index| names[index] = family.displayName();
    break :blk names;
};

/// The accent switcher's choices, in display order: null first, keeping each
/// theme's own accent (macOS uses distinct blues for accent and selection),
/// then every `ziggui.Accent`, as the apps draw it (`Accent.theme`).
const accents = blk: {
    var choices: [ziggui.Accent.all.len + 1]?ziggui.Accent = undefined;
    choices[0] = null;
    for (ziggui.Accent.all, 1..) |accent, index| choices[index] = accent;
    break :blk choices;
};

/// The width one accent swatch takes, in points: the nine fit the
/// sidebar's width in one row.
const swatch_size: f32 = 20;

/// The height of the accent switcher's row, in points.
const swatch_row_height: f32 = 22;

/// The Panes panel's table columns.
const file_columns = [_]ziggui.DataColumn{
    .{ .title = "Name" },
    .{ .title = "Kind", .width = 90 },
    .{ .title = "Size", .width = 70, .trailing = true },
};

/// How many rows the Panes panel's virtual list holds.
const file_count: usize = 10_000;

/// The height of one of the Panes panel's table rows, in points.
const file_row_height: f32 = 24;

/// How many of the sample diff's rows show at once; the rest scroll.
const diff_rows_shown: f32 = 10;

/// The Panes panel's sample diff: two files, three hunks, one line wider than
/// the pane (it scrolls sideways).
const sample_diff = [_]ziggui.DiffLine{
    .{ .kind = .fileHeader, .text = "src/split.zig" },
    .{ .kind = .hunkHeader, .text = "@@ -12,6 +12,8 @@ const View = ziggui.View;" },
    .{ .kind = .context, .text = "pub const SplitState = struct {", .old = 12, .new = 12 },
    .{ .kind = .context, .text = "\tconst Self = @This();", .old = 13, .new = 13 },
    .{ .kind = .removed, .text = "\tsize: f32 = 0,", .old = 14 },
    .{ .kind = .added, .text = "\tsize: f32 = -1,", .new = 14 },
    .{ .kind = .added, .text = "\tinitial_ratio: f32 = 0.5,", .new = 15 },
    .{ .kind = .added, .text = "\t// A line wider than the pane runs on: scroll sideways (trackpad, Shift+wheel, or the bar along the bottom) to read the rest of it.", .new = 16 },
    .{ .kind = .context, .text = "};", .old = 15, .new = 17 },
    .{ .kind = .hunkHeader, .text = "@@ -40,4 +42,4 @@ pub fn HSplitView(" },
    .{ .kind = .removed, .text = "\treturn SplitView(.horizontal, state, first, second);", .old = 40 },
    .{ .kind = .added, .text = "\treturn Split.view(.horizontal, state, first, second);", .new = 42 },
    .{ .kind = .fileHeader, .text = "src/chat.zig" },
    .{ .kind = .hunkHeader, .text = "@@ -60,3 +60,3 @@" },
    .{ .kind = .removed, .text = "pub fn Disclosure(header: View, expanded: bool) View {", .old = 60 },
    .{ .kind = .added, .text = "pub fn DisclosureGroup(header: View, expanded: bool) View {", .new = 60 },
    .{ .kind = .note, .text = "\\ No newline at end of file" },
};

/// A Menu Bar panel entry's choice: says which entry was chosen.
const BarChoice = struct {
    const Self = @This();

    /// The gallery the panel shows the choice in.
    gallery: *Gallery,

    /// The entry's title.
    title: []const u8,

    /// Records the choice.
    ///
    /// - `self`: the entry.
    fn choose(self: *Self) void {
        self.gallery.menu_choice = self.title;
    }
};

/// The Menu Bar panel's menus: titles and entries, `ctrl+` keys as off macOS.
const bar_menus = [_]struct { []const u8, []const ziggui.MenuBarItem }{
    .{ "File", &.{
        .{ .title = "New Window", .key_text = "ctrl+N" },
        .{ .title = "Open Folder…", .key_text = "ctrl+O" },
        .{},
        .{ .title = "Save", .key_text = "ctrl+S", .enabled = false },
        .{},
        .{ .title = "Settings…", .key_text = "ctrl+," },
        .{},
        .{ .title = "Quit", .key_text = "ctrl+Q" },
    } },
    .{ "Edit", &.{
        .{ .title = "Undo", .key_text = "ctrl+Z", .enabled = false },
        .{},
        .{ .title = "Cut", .key_text = "ctrl+X" },
        .{ .title = "Copy", .key_text = "ctrl+C" },
        .{ .title = "Paste", .key_text = "ctrl+V" },
    } },
    .{ "View", &.{
        .{ .title = "Zoom In", .key_text = "ctrl+=" },
        .{ .title = "Zoom Out", .key_text = "ctrl+-" },
        .{},
        .{ .title = "Next Pane", .key_text = "tab" },
    } },
    .{ "Help", &.{
        .{ .title = "Search" },
    } },
};

/// How many entries the Menu Bar panel's menus hold, separators included.
const bar_item_count = blk: {
    var count: usize = 0;
    for (bar_menus) |menu| count += menu[1].len;
    break :blk count;
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

    /// The theme family drawn, an index into `ziggui.ThemeFamily.all`.
    theme_family: ziggui.State(i64),

    /// The accent drawn, an index into the accent switcher's choices: 0 for
    /// the theme's own, then `ziggui.Accent.all` from 1.
    accent: ziggui.State(i64),

    /// The detail pane's scroll position.
    scroll: ziggui.ScrollState = .{},

    /// The sidebar's list's scroll position, for a window too short for every row.
    sidebar_scroll: ziggui.ScrollState = .{},

    /// The section the last frame showed, null before the first.
    shown_section: ?Section = null,

    /// The panels folded in from zigui's showcase, and their state.
    showcase: gallery.Showcase,

    /// The Editor panel's editor.
    editor: gallery.Editor,

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

    /// The Hover Popover panel's rows: which one the pointer rests on.
    hover: ziggui.HoverState = .{},

    /// The Menu Bar panel's bar.
    menu_bar: ziggui.MenuBarState = .{},

    /// The Menu Bar panel's last chosen entry.
    menu_choice: []const u8 = "Nothing chosen yet.",

    /// The Menu Bar panel's entries, their actions pointing at this gallery (`barMenus`).
    bar_items: [bar_item_count]ziggui.MenuBarItem = undefined,

    /// What each of `bar_items` does.
    bar_choices: [bar_item_count]BarChoice = undefined,

    /// The Menu Bar panel's menus, over `bar_items`.
    bar_menus: [bar_menus.len]ziggui.MenuBarMenu = undefined,

    /// The Title Bar panel's two bars' menus (the second one folded).
    title_menus: [2]ziggui.MenuBarState = .{ .{}, .{} },

    /// What the Title Bar panel's window buttons last did.
    window_said: []const u8 = "No window button pressed yet.",

    /// Constructs a gallery on its first section, light, in the first theme
    /// family with its own accent.
    ///
    /// - `allocator`: allocator for the state; must outlive the gallery.
    /// - Returns: the gallery; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var showcase = try gallery.Showcase.init(allocator);
        errdefer showcase.deinit();
        const editor = try gallery.Editor.init(allocator);
        const self = Self{
            .allocator = allocator,
            .section = ziggui.State(i64).init(allocator, 0),
            .dark = ziggui.State(bool).init(allocator, false),
            .theme_family = ziggui.State(i64).init(allocator, 0),
            .accent = ziggui.State(i64).init(allocator, 0),
            .showcase = showcase,
            .editor = editor,
        };
        return self;
    }

    /// Releases the gallery's state.
    ///
    /// - `self`: the gallery to tear down.
    pub fn deinit(self: *Self) void {
        self.editor.deinit();
        self.showcase.deinit();
        self.accent.deinit();
        self.theme_family.deinit();
        self.dark.deinit();
        self.section.deinit();
    }

    /// The theme the switchers select.
    ///
    /// - `self`: the gallery.
    /// - Returns: the theme family in its light or dark scheme, in the chosen
    ///   accent as the apps draw it (`ziggui.Accent.theme`), or its own.
    pub fn theme(self: *const Self) ziggui.Theme {
        const accent = accents[self.accentIndex()] orelse return self.ownTheme();
        return accent.theme(self.family(), self.dark.get());
    }

    /// Builds the window's view tree: the sidebar beside the selected panel.
    ///
    /// Called once per frame, inside `BuildScope.begin`/`end`.
    ///
    /// - `self`: the gallery supplying the state.
    /// - Returns: the root view.
    pub fn body(self: *Self) ziggui.View {
        self.track(Section.at(self.section.get()));
        const active_theme = self.theme();
        const root = ziggui.NavigationSplitView(
            self.sidebar(active_theme),
            self.detail(active_theme),
            active_theme.colors.sidebar_background orelse active_theme.colors.secondary_background,
        );
        return self.showcase.presentations(root, active_theme);
    }

    /// The Menu Bar panel's menus, each entry's action recording its title
    /// in `menu_choice`. Rebuilt in place on each call (no allocation), so
    /// the actions point at the gallery where it is now.
    ///
    /// - `self`: the gallery.
    /// - Returns: the menus, in `self`.
    pub fn barMenus(self: *Self) []const ziggui.MenuBarMenu {
        var at: usize = 0;
        for (bar_menus, 0..) |menu, index| {
            const first = at;
            for (menu[1]) |item| {
                self.bar_choices[at] = .{ .gallery = self, .title = item.title };
                self.bar_items[at] = item;
                if (item.title.len > 0) self.bar_items[at].action = ziggui.Callback.init(BarChoice, &self.bar_choices[at], BarChoice.choose);
                at += 1;
            }
            self.bar_menus[index] = .{ .title = menu[0], .items = self.bar_items[first..at], .width = 220 };
        }
        return &self.bar_menus;
    }

    /// A key went down (ziggui's raw event), for the Menu Bar panel's bar:
    /// `MenuBarState.appKeyDown`, live only while the panel shows with nothing
    /// modal over it (Alt may start a tap; the open menu's keys). Not live,
    /// the bar still learns Alt is down, so a held Alt's repeats start no tap.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when the menu used it.
    pub fn menuKeyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        const live = self.barLive();
        return self.menu_bar.appKeyDown(live, if (live) self.barMenus() else &.{}, keycode, modifiers);
    }

    /// A key went down (ziggui's raw event): the Menu Bar panel's keys, then
    /// the Editor panel's shortcuts while it shows with nothing modal over it.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a panel used it.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (self.menuKeyDown(keycode, modifiers)) return true;
        if (self.showcase.presentsModal()) return false;
        if (Section.at(self.section.get()) != .editor) return false;
        return self.editor.keyDown(keycode, modifiers);
    }

    /// A key came up (ziggui's raw event): the Menu Bar panel's Alt tap
    /// (`menuKeyUp`), and the Overlays panel's last key-up.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    pub fn keyUp(self: *Self, keycode: u32) void {
        self.menuKeyUp(keycode);
        self.showcase.keyUp(keycode);
    }

    /// A quit was asked for (the window's close button, ⌘Q): the Overlays
    /// panel's "Ask before quitting" may present a question instead.
    ///
    /// - `self`: the gallery.
    /// - Returns: true to let the quit end the loop.
    pub fn quitRequested(self: *Self) bool {
        return self.showcase.quitRequested();
    }

    /// A key came up (ziggui's raw event): Alt after a tap opens the Menu Bar
    /// panel's first menu, or closes the open one (`MenuBarState.appKeyUp`).
    /// Taken on every section and under a modal, where the bar is not live:
    /// it opens nothing there but learns Alt is up.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    pub fn menuKeyUp(self: *Self, keycode: u32) void {
        const live = self.barLive();
        _ = self.menu_bar.appKeyUp(live, if (live) self.barMenus() else &.{}, keycode);
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

    /// Reports whether a hover popover is about to open, so the loop stays awake.
    ///
    /// - `self`: the gallery.
    /// - Returns: true while the pointer rests on a row short of the delay.
    pub fn hoverWaiting(self: *const Self) bool {
        return self.hover.waiting(ziggui.FrameClock.shared().time());
    }

    /// The sidebar: the title, a row per section, then the switchers.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the sidebar view.
    fn sidebar(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Icon(.boxes, 20, active_theme.colors.accent),
                ziggui.Text("ziggui").font(.headline),
                ziggui.Spacer(),
            }).spacing(8).paddingInsets(.{ .top = 8, .leading = 10, .bottom = 4, .trailing = 8 }),
            // Scrolls when the window is too short for every row.
            ziggui.ScrollViewState(&self.sidebar_scroll, ziggui.Sidebar(&Section.items, self.section.binding()))
                .frameMaxWidth()
                .frameMaxHeight(),
            ziggui.Divider(),
            ziggui.VStack(.{
                Self.leading(ziggui.Text("Theme").font(.footnote).foreground(active_theme.colors.secondary_label)),
                ziggui.RadioGroup(self.theme_family.binding(), &family_names),
            }).spacing(6).padding(6),
            ziggui.HStack(.{ ziggui.Text("Dark mode"), ziggui.Spacer(), ziggui.Toggle("", self.dark.binding()) })
                .frameMaxWidth()
                .padding(6),
            ziggui.VStack(.{
                Self.leading(ziggui.Text("Accent").font(.footnote).foreground(active_theme.colors.secondary_label)),
                self.accentSwatches(active_theme),
            }).spacing(6).padding(6),
        }).spacing(4).padding(8).frameMaxHeight().backgroundMaterial(.thin);
    }

    /// The accent switcher: a row of tappable color dots, the chosen one
    /// ringed; the first shows the theme's own accent.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the row.
    fn accentSwatches(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const chosen = self.accentIndex();
        const own = self.ownTheme().colors.accent;
        // The stack copies its children into the frame's build arena.
        var dots: [accents.len + 1]ziggui.View = undefined;
        for (accents, 0..) |choice, index| {
            const swatch = if (choice) |accent| accent.color() else own;
            const dot = if (index == chosen) ziggui.ZStack(.{
                ziggui.Circle(active_theme.colors.label).frame(swatch_size, swatch_size),
                ziggui.Circle(active_theme.colors.window_background).frame(swatch_size - 4, swatch_size - 4),
                ziggui.Circle(swatch).frame(swatch_size - 8, swatch_size - 8),
            }) else ziggui.ZStack(.{
                ziggui.Circle(swatch).frame(swatch_size - 6, swatch_size - 6),
            });
            dots[index] = dot.frame(swatch_size, swatch_row_height).onTap(ziggui.Callback.select(self.accent.binding(), @intCast(index)));
        }
        dots[accents.len] = ziggui.Spacer();
        return ziggui.HStack(@as([]const ziggui.View, &dots)).spacing(1).frameMaxWidth();
    }

    /// The selected section's panel, titled and scrolled as a whole unless
    /// it fills the pane itself (`Section.fills`).
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the detail view.
    fn detail(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const section = Section.at(self.section.get());
        if (section.fills()) return self.panel(section, active_theme);
        const content = ziggui.VStack(.{
            Self.leading(ziggui.Text(section.label()).font(.largeTitle)),
            self.panel(section, active_theme),
        }).spacing(16);
        return ziggui.ScrollViewState(&self.scroll, content.padding(20).frameMaxWidth())
            .frameMaxWidth()
            .frameMaxHeight();
    }

    /// The body of `section`'s panel, below its title; for a panel that
    /// fills the pane, the whole panel.
    ///
    /// - `self`: the gallery.
    /// - `section`: the section to draw.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn panel(self: *Self, section: Section, active_theme: ziggui.Theme) ziggui.View {
        return switch (section) {
            .chat => self.chatPanel(active_theme),
            .panes => self.panesPanel(active_theme),
            .split => self.splitPanel(active_theme),
            .menuBar => self.menuBarPanel(active_theme),
            .titleBar => self.titleBarPanel(active_theme),
            .statusLine => Self.statusLinePanel(active_theme),
            .hover => self.hoverPanel(active_theme),
            .controls => self.showcase.controlsPanel(active_theme),
            .text => self.showcase.textPanel(active_theme),
            .shapes => self.showcase.shapesPanel(active_theme),
            .layout => self.showcase.layoutPanel(active_theme),
            .table => self.showcase.tablePanel(active_theme, section.label()),
            .textEditor => self.showcase.textEditorPanel(active_theme, section.label()),
            .overlays => self.showcase.overlaysPanel(active_theme),
            .effects => self.showcase.effectsPanel(active_theme),
            .navigation => self.showcase.navigationPanel(active_theme, section.label()),
            .geometry => self.showcase.geometryPanel(active_theme),
            .editor => self.editor.body(active_theme),
        };
    }

    /// Notes the section this frame shows. On a change, no field keeps the
    /// keyboard (keys must not reach a field not drawn), leaving Navigation
    /// empties its stack, and the Editor takes the keyboard as it comes in.
    ///
    /// - `self`: the gallery.
    /// - `section`: the section this frame shows.
    fn track(self: *Self, section: Section) void {
        if (self.shown_section == section) return;
        self.shown_section = section;
        ziggui.Focus.shared().clear();
        if (section != .navigation) self.showcase.clearNavigation();
        if (section == .editor) self.editor.focus();
    }

    /// The Chat panel: status marks, chips, and a transcript of blocks.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn chatPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const toggle = ziggui.Callback.init(Self, self, Self.toggleTool);
        return ziggui.VStack(.{
            Self.card(active_theme, "Status marks", ziggui.HStack(.{
                ziggui.StatusMark(.idle, 10),     ziggui.Text("idle").font(.footnote),
                ziggui.StatusMark(.busy, 10),     ziggui.Text("busy").font(.footnote),
                ziggui.StatusMark(.waiting, 10),  ziggui.Text("waiting").font(.footnote),
                ziggui.StatusMark(.starting, 10), ziggui.Text("starting").font(.footnote),
                ziggui.StatusMark(.stopped, 10),  ziggui.Text("stopped").font(.footnote),
                ziggui.Spacer(),
            }).spacing(6)),
            Self.card(active_theme, "Chips", ziggui.HStack(.{
                ziggui.Chip("Ask before edits", .shield, toggle),
                ziggui.Chip("Opus", .sparkles, toggle),
                ziggui.Chip("screenshot.png · 84 KB", .image, null),
                ziggui.Spacer(),
            }).spacing(8)),
            Self.card(active_theme, "Transcript", ziggui.VStack(.{
                Self.leading(ziggui.Bubble(ziggui.WrappedText("List the files and explain the build."), active_theme.colors.accent.withAlpha(0.16))),
                ziggui.DisclosureGroup(
                    ziggui.Text("ls -la").font(.footnote).mono(),
                    self.tool_open,
                    toggle,
                    ziggui.CodeBlock("build.zig\nbuild.zig.zon\nsrc/"),
                ),
                ziggui.WrappedText("The build is driven by build.zig:"),
                ziggui.CodeBlock("pub fn build(b: *std.Build) void {\n    // ...\n}"),
                ziggui.Quote(ziggui.WrappedText("Tip: run zig build test after every change.").foreground(active_theme.colors.secondary_label)),
            }).spacing(10).alignment(.leading)),
        }).spacing(16);
    }

    /// The Panes panel: a long table over a virtual list, and a diff.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn panesPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const on_hunk = ziggui.IndexCallback.init(Self, self, Self.selectHunk);
        return ziggui.VStack(.{
            Self.card(active_theme, "Table rows over a virtual list (10,000 rows)", ziggui.VStack(.{
                ziggui.TableHeader(&file_columns),
                ziggui.VirtualList(Self, self, file_count, file_row_height, &self.files_scroll, Self.fileRow).frameHeight(150),
            }).spacing(0)),
            Self.card(active_theme, "DiffView (tap a row to select its hunk; scroll sideways for long lines)", ziggui.VStack(.{
                ziggui.DiffView(&sample_diff, self.hunk_selected, &self.diff_scroll, on_hunk),
            }).spacing(0).frameHeight(diff_rows_shown * ziggui.diff_row_height)),
        }).spacing(16);
    }

    /// Row `index` of the Panes panel's table.
    ///
    /// - `self`: the gallery.
    /// - `index`: the row.
    /// - Returns: the row.
    fn fileRow(self: *const Self, index: usize) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const name = allocator.print("file-{d:0>5}.zig", .{index}) catch @panic("oom");
        const size = allocator.print("{d} KB", .{(index * 37) % 512 + 1}) catch @panic("oom");
        const kind = if (index % 3 == 0) "Test" else "Source";
        const cells = allocator.dupe(ziggui.View, &.{
            ziggui.Text(name).truncated(),
            ziggui.Text(kind).foreground(ziggui.BuildScope.shared().tokens().secondary_label),
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
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn splitPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const split = ziggui.HSplitView(
            &self.columns,
            Self.pane(active_theme, "Sidebar", "Drag the divider to resize."),
            ziggui.VSplitView(
                &self.rows,
                Self.pane(active_theme, "Top", "HSplitView and VSplitView, as SwiftUI names them."),
                Self.pane(active_theme, "Bottom", "Each pane is laid out at the size the split gives it."),
            ),
        );
        return Self.card(active_theme, "HSplitView over a VSplitView", split
            .frameMaxWidth()
            .frameHeight(260)
            .border(active_theme.colors.separator, 1));
    }

    /// The Menu Bar panel: a bar over a window's worth of space, and the last choice.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn menuBarPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        return Self.card(active_theme, "MenuBar (click a title, point at the next; Alt opens the first menu)", ziggui.VStack(.{
            ziggui.MenuBar(&self.menu_bar, self.barMenus(), .{}),
            ziggui.Divider(),
            ziggui.VStack(.{
                Self.leading(ziggui.Text(self.menu_choice).foreground(active_theme.colors.secondary_label)),
                ziggui.Spacer(),
            }).padding(12).frameHeight(260),
        }).spacing(0).border(active_theme.colors.separator, 1));
    }

    /// The Title Bar panel: a title bar with Windows' buttons, then a narrow
    /// one with GNOME's and its menus folded, both over the theme family's
    /// own bar; the buttons say what they would do.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn titleBarPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const foreground = active_theme.titleBarForeground();
        const actions: ziggui.WindowActions = .{
            .minimize = ziggui.Callback.init(Self, self, Self.minimizeTapped),
            .maximize = ziggui.Callback.init(Self, self, Self.maximizeTapped),
            .close = ziggui.Callback.init(Self, self, Self.closeTapped),
        };
        const folded = ziggui.MenuBarMenu.fold(ziggui.BuildScope.shared().allocator(), self.barMenus()) catch @panic("oom");
        return ziggui.VStack(.{
            Self.card(active_theme, "TitleBar with Windows' buttons (the theme colors the bar)", ziggui.TitleBar(
                ziggui.HStack(.{
                    ziggui.Icon(.boxes, 16, foreground).paddingInsets(.{ .leading = 10 }),
                    ziggui.MenuBar(&self.title_menus[0], self.barMenus(), .{ .foreground = foreground, .fill = false }),
                }).spacing(4),
                "~/src/mlavergn/ziggui",
                ziggui.WindowButtons(.windows, false, actions),
            ).border(active_theme.colors.separator, 1)),
            Self.card(active_theme, "Narrow, with GNOME's buttons and the menus folded", Self.leading(ziggui.TitleBar(
                ziggui.HStack(.{
                    ziggui.Icon(.boxes, 16, foreground).paddingInsets(.{ .leading = 10 }),
                    ziggui.MenuBar(&self.title_menus[1], folded, .{ .foreground = foreground, .fill = false }),
                }).spacing(4),
                "~/src/mlavergn/ziggui",
                ziggui.WindowButtons(.gnome, true, actions),
            ).frameWidth(360).border(active_theme.colors.separator, 1))),
            Self.leading(ziggui.Text(self.window_said).foreground(active_theme.colors.secondary_label)),
        }).spacing(16);
    }

    /// The Status Line panel: the keys a composer takes, then a list's, each
    /// under a notice row as a window's frame ends.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn statusLinePanel(active_theme: ziggui.Theme) ziggui.View {
        const typing = [_]ziggui.KeyHint{ .{ .key = "enter", .action = "send" }, .{ .key = "shift+enter", .action = "new line" }, .{ .key = "esc", .action = "stop" }, .{ .key = "/", .action = "commands" } };
        const listing = [_]ziggui.KeyHint{ .{ .key = "↑↓", .action = "rows" }, .{ .key = "space", .action = "stage" }, .{ .key = "ctrl+N", .action = "new" }, .{ .key = "alt", .action = "menus" } };
        return ziggui.VStack(.{
            Self.card(active_theme, "StatusLine while typing", ziggui.VStack(.{
                Self.leading(ziggui.Text("Sent to claude-ziggui.").font(.footnote).foreground(active_theme.colors.secondary_label)).padding(6),
                ziggui.StatusLine(&typing),
            }).spacing(0).border(active_theme.colors.separator, 1)),
            Self.card(active_theme, "StatusLine over a list", ziggui.StatusLine(&listing).border(active_theme.colors.separator, 1)),
        }).spacing(16);
    }

    /// The Hover Popover panel: rows whose details open after the pointer
    /// rests on one for half a second.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn hoverPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const names = [_][]const u8{ "ziggit", "ziggui", "zigui", "zigtui" };
        const branches = [_][]const u8{ "main", "main", "marc", "main" };
        const rows = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, names.len) catch @panic("oom");
        for (rows, names, branches, 0..) |*row, name, branch, index| {
            const details = if (self.hover.shows(index, ziggui.FrameClock.shared().time())) ziggui.VStack(.{
                ziggui.Text(name).font(.headline),
                ziggui.Text(ziggui.BuildScope.shared().allocator().print("~/src/mlavergn/{s} · {s}", .{ name, branch }) catch @panic("oom")).font(.footnote).foreground(active_theme.colors.secondary_label),
            }).spacing(4).alignment(.leading).padding(12) else ziggui.Empty();
            row.* = ziggui.HoverPopover(ziggui.VStack(.{
                ziggui.Text(name).font(.callout),
                ziggui.Text(branch).font(.caption).foreground(active_theme.colors.secondary_label),
            }).spacing(2).alignment(.leading).paddingInsets(.{ .top = 4, .leading = 10, .bottom = 4, .trailing = 10 }).frameMaxWidth().frameAlign(.leading), &self.hover, index, details);
        }
        return ziggui.VStack(.{
            Self.card(active_theme, "Rest the pointer on a row (HoverPopover over a HoverState)", Self.leading(ziggui.StackBuilder.fromSlice(.vertical, 0, .leading, rows).frameWidth(240).popoverPassthrough())),
        }).spacing(16);
    }

    /// The Title Bar panel's minimize button: says it was pressed.
    ///
    /// - `self`: the gallery.
    fn minimizeTapped(self: *Self) void {
        self.window_said = "Minimize";
    }

    /// The Title Bar panel's maximize or restore button: says it was pressed.
    ///
    /// - `self`: the gallery.
    fn maximizeTapped(self: *Self) void {
        self.window_said = "Maximize or restore";
    }

    /// The Title Bar panel's close button: says it was pressed.
    ///
    /// - `self`: the gallery.
    fn closeTapped(self: *Self) void {
        self.window_said = "Close";
    }

    /// A split view's sample pane: a title and a line of text, top-leading.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - `title`: the pane's title.
    /// - `text`: the pane's text.
    /// - Returns: the pane.
    fn pane(active_theme: ziggui.Theme, title: []const u8, text: []const u8) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            ziggui.WrappedText(text).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.Spacer(),
        }).spacing(6).padding(12).frameMaxWidth().frameMaxHeight();
    }

    /// A titled group: a headline above a rounded block in the secondary background.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - `title`: the group's headline.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(active_theme: ziggui.Theme, title: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            content.frameMaxWidth()
                .padding(14)
                .background(active_theme.colors.secondary_background)
                .cornerRadius(active_theme.metrics.corner_radius)
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

    /// Reports whether the Menu Bar panel's bar takes keys now: its panel
    /// shows, and no sheet or alert is presented over it.
    ///
    /// - `self`: the gallery.
    /// - Returns: true when the bar is live.
    fn barLive(self: *const Self) bool {
        return Section.at(self.section.get()) == .menuBar and !self.showcase.presentsModal();
    }

    /// The chosen theme family, clamped to the families there are.
    ///
    /// - `self`: the gallery.
    /// - Returns: the family.
    fn family(self: *const Self) ziggui.ThemeFamily {
        const last: i64 = ziggui.ThemeFamily.all.len - 1;
        return ziggui.ThemeFamily.all[@intCast(std.math.clamp(self.theme_family.get(), 0, last))];
    }

    /// The chosen theme family in the chosen scheme, in its own accent.
    ///
    /// - `self`: the gallery.
    /// - Returns: the theme.
    fn ownTheme(self: *const Self) ziggui.Theme {
        return self.family().forScheme(if (self.dark.get()) .dark else .light);
    }

    /// The chosen accent, clamped to the choices there are.
    ///
    /// - `self`: the gallery.
    /// - Returns: an index into the accent switcher's choices.
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
            const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
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
    const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
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

test "the Menu Bar panel's entries record the choice, and Alt opens the first menu there only" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    const down = ziggui.MenuBarKey.down.toKeycode();
    // Off its section, Alt is left alone.
    try std.testing.expect(!shown.menuKeyDown(ziggui.SdlKey.left_alt, 0));
    shown.menuKeyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());

    shown.section.set(@backingInt(Section.menuBar));
    try std.testing.expect(!shown.menuKeyDown(ziggui.SdlKey.left_alt, 0));
    shown.menuKeyUp(ziggui.SdlKey.left_alt);
    try std.testing.expectEqual(@as(?usize, 0), shown.menu_bar.menu);
    const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
    defer allocator.free(rgba);
    // Down past New Window to Open Folder…, then choose it.
    try std.testing.expect(shown.menuKeyDown(down, 0));
    try std.testing.expect(shown.menuKeyDown(ziggui.MenuBarKey.enter.toKeycode(), 0));
    try std.testing.expectEqualStrings("Open Folder…", shown.menu_choice);
    try std.testing.expect(!shown.menu_bar.isOpen());
    // Alt with another key between is not a tap.
    _ = shown.menuKeyDown(ziggui.SdlKey.left_alt, 0);
    _ = shown.menuKeyDown('x', 0);
    shown.menuKeyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());
}

test "an accent draws the theme as the apps do; the first keeps the theme's own" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    const own = shown.theme();
    try std.testing.expectEqual(ziggui.ThemeFamily.all[0].forScheme(.light).colors.accent, own.colors.accent);
    try std.testing.expectEqual(ziggui.ThemeFamily.all[0].forScheme(.light).colors.selection, own.colors.selection);

    // Index n is `ziggui.Accent.all[n - 1]`, as `--accent` documents.
    for (ziggui.Accent.all, 1..) |accent, index| {
        shown.accent.set(@intCast(index));
        const recolored = shown.theme();
        try std.testing.expectEqual(accent.color(), recolored.colors.accent);
        try std.testing.expectEqual(accent.color(), recolored.colors.selection);
        try std.testing.expectEqual(accent.onColor(), recolored.colors.on_accent);
    }

    // The macOS family's dark draws on true black, as the apps' does.
    shown.dark.set(true);
    shown.accent.set(1);
    try std.testing.expectEqual(ziggui.Accent.orange.theme(.macos, true), shown.theme());
    shown.accent.set(0);
    try std.testing.expectEqual(ziggui.ThemeFamily.macos.forScheme(.dark).colors.window_background, shown.theme().colors.window_background);

    shown.accent.set(99);
    try std.testing.expectEqual(ziggui.Accent.graphite.color(), shown.theme().colors.accent);
}

test "the folded-in sections keep the first seven sections' rows" {
    try std.testing.expectEqual(Section.hover, Section.at(6));
    try std.testing.expectEqual(Section.controls, Section.at(7));
    try std.testing.expectEqual(Section.editor, Section.at(17));
    try std.testing.expect(!Section.controls.fills());
    try std.testing.expect(Section.table.fills() and Section.textEditor.fills() and Section.navigation.fills() and Section.editor.fills());
}

test "the showcase and editor sections draw with every overlay presented" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.showcase.openSheet();
    shown.showcase.openAlert();
    shown.showcase.show_popover.set(true);
    shown.showcase.show_pass_popover.set(true);
    shown.showcase.menu_open.set(true);
    try shown.showcase.navigation.push(1);
    shown.editor.showMatch("greeting");
    shown.editor.openDialog();
    for (@backingInt(Section.controls)..Section.items.len) |index| {
        shown.section.set(@intCast(index));
        const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
        defer allocator.free(rgba);
        try std.testing.expectEqual(gallery.test_width * gallery.test_height * 4, rgba.len);
    }
}

/// Draws one headless frame of a gallery, for the tests that need its
/// `body` to have run (`Gallery.track`).
const Frame = struct {
    const Self = @This();

    /// Draws `shown` once, at the tests' size.
    ///
    /// - `shown`: the gallery to draw.
    /// - Returns: nothing; propagates allocation and rendering failure.
    fn draw(shown: *Gallery) !void {
        const rgba = try ziggui.Screenshot.render(std.testing.allocator, shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
        std.testing.allocator.free(rgba);
    }
};

test "the Editor section takes the keyboard and its shortcuts, and gives them up on leaving" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    // Elsewhere, ⌘F is not the editor's.
    try Frame.draw(&shown);
    try std.testing.expect(!shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(!shown.editor.show_find.get());

    shown.section.set(@backingInt(Section.editor));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &shown.editor.document), ziggui.Focus.shared().focused());
    try std.testing.expect(shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(shown.editor.show_find.get());

    shown.section.set(@backingInt(Section.chat));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, null), ziggui.Focus.shared().focused());
}

test "leaving Navigation empties its stack; key-ups and quits reach the Overlays panel" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.navigation));
    try Frame.draw(&shown);
    try shown.showcase.navigation.push(3);
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(usize, 1), shown.showcase.navigation.depth());
    shown.section.set(@backingInt(Section.overlays));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(usize, 0), shown.showcase.navigation.depth());

    shown.keyUp('q');
    try std.testing.expectEqual(@as(i64, 'q'), shown.showcase.last_key_up.get());
    try std.testing.expect(shown.quitRequested());
    shown.showcase.ask_quit.set(true);
    try std.testing.expect(!shown.quitRequested());
    try std.testing.expect(shown.showcase.show_quit.get());
}

test "under a sheet or alert an Alt tap opens no menu; once dismissed it does again" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.menuBar));
    shown.showcase.openSheet();
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.left_alt, 0));
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());
    shown.showcase.closeSheet();
    shown.showcase.openAlert();
    _ = shown.keyDown(ziggui.SdlKey.left_alt, 0);
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());

    // Alt pressed under the alert and still held once it is dismissed: no tap.
    _ = shown.keyDown(ziggui.SdlKey.left_alt, 0);
    shown.showcase.closeAlert();
    _ = shown.keyDown(ziggui.SdlKey.left_alt, ziggui.SdlKey.left_alt_mask);
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());

    // Nothing modal: the tap opens the first menu.
    _ = shown.keyDown(ziggui.SdlKey.left_alt, 0);
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expectEqual(@as(?usize, 0), shown.menu_bar.menu);
}

test "an Alt held from another section arms no tap on the Menu Bar section" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    _ = shown.keyDown(ziggui.SdlKey.left_alt, 0);
    shown.section.set(@backingInt(Section.menuBar));
    // The held key's repeats, then its release, on the Menu Bar section.
    _ = shown.keyDown(ziggui.SdlKey.left_alt, ziggui.SdlKey.left_alt_mask);
    _ = shown.keyDown(ziggui.SdlKey.left_alt, ziggui.SdlKey.left_alt_mask);
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());
}

test "the Editor's shortcuts reach nothing behind a presented sheet, alert or its own dialog" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.editor));
    try Frame.draw(&shown);
    shown.showcase.openAlert();
    try std.testing.expect(!shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(!shown.editor.show_find.get());
    shown.showcase.closeAlert();
    shown.showcase.openSheet();
    try std.testing.expect(!shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(!shown.editor.show_find.get());
    shown.showcase.closeSheet();

    shown.editor.openDialog();
    try std.testing.expect(!shown.keyDown('n', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(shown.editor.show_dialog.get());
    shown.editor.cancelDialog();
    try std.testing.expect(shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(shown.editor.show_find.get());
}
