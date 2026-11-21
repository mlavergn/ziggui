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

    /// Text and the fields that take it: the type scale, a wrapped paragraph, marked search
    /// results, a label, a text field and a search field.
    text,

    /// A plain-text editor with line numbers, a find bar, and open and save dialogs
    /// (`TextEditor`, `FindBar`).
    textEditor,

    /// Buttons in every role and with a key, toggles, a slider, progress indicators, a stepper,
    /// badges and key caps.
    controls,

    /// Pickers in a `Form` and outside one, a radio group, and segmented controls of words and
    /// of icons.
    pickers,

    /// Images at their size and scaled, a `Canvas` chart, canvas markers, a large picture zoomed
    /// and panned, shapes, a gradient and the icon set.
    images,

    /// Stacks, a stack that wraps into rows, grids, dividers, a `GeometryReader`, and scroll
    /// indicators.
    layout,

    /// Rows: headers, selectable rows, rows dragged to reorder, a folding outline, names renamed in
    /// place, a check list, and table rows over a virtual list.
    lists,

    /// A table whose columns resize, filling the pane.
    table,

    /// A navigation stack of list rows, an inset split view, a `TabView`, and split views,
    /// filling the pane.
    navigation,

    /// Sheets, alerts, menus, popovers, a popover on hover, and `.onHover`.
    presentations,

    /// The drawn menu bar, a key-hint bar, and key-ups and quitting.
    menus,

    /// Title bars as each platform draws them, macOS's top band, the theme's own title bar, and
    /// status lines.
    windows,

    /// Animation, liquid glass, materials, opacity, borders and corners.
    effects,

    /// Setting rows, a key/value editor, a token field, and an app's settings window (`Settings`,
    /// `Form`, `AppearancePicker`, `ThemePicker`).
    forms,

    /// A `FileBrowser` over the fixture folder with a filter, and the system's open and save
    /// panels (`FileDialog`).
    files,

    /// An audio player's bar over its own `Player`, and the audio outputs.
    mediaAudio,

    /// A `VideoPlayer` with the standard controls over the picture, and how the window draws.
    mediaVideo,

    /// A `WebPage` under a browser's toolbar, filling the pane.
    mediaWeb,

    /// An app-made platform view placed by layout (`NativeView`).
    mediaNative,

    /// Status marks, chips, and a transcript of bubbles, disclosure groups, code and a quote.
    chat,

    /// A selectable diff with links on its hunk headers.
    diffs,

    /// Every section, as sidebar rows, in the enum's order: a section's index
    /// (`--section`, the screenshots) is its place here.
    pub const items = blk: {
        const values = @typeInfo(Self).@"enum".field_values;
        var rows: [values.len]ziggui.SidebarItem = undefined;
        for (values, 0..) |value, index| {
            const section: Self = @fromBackingInt(value);
            rows[index] = .{ .label = section.label(), .icon = section.icon() };
        }
        break :blk rows;
    };

    /// Every section in the order the sidebar lists them: by label,
    /// alphabetically, case aside.
    pub const sorted = blk: {
        const values = @typeInfo(Self).@"enum".field_values;
        var order: [values.len]Self = undefined;
        for (values, 0..) |value, index| order[index] = @fromBackingInt(value);
        // Insertion sort: a few dozen labels, at compile time.
        @setEvalBranchQuota(100_000);
        for (1..order.len) |index| {
            var place = index;
            while (place > 0 and std.ascii.lessThanIgnoreCase(order[place].label(), order[place - 1].label())) : (place -= 1) {
                const held = order[place];
                order[place] = order[place - 1];
                order[place - 1] = held;
            }
        }
        break :blk order;
    };

    /// The section's name in the sidebar and as its panel's title.
    ///
    /// - `self`: the section.
    /// - Returns: the name.
    pub fn label(self: *const Self) []const u8 {
        return switch (self.*) {
            .text => "Text",
            .textEditor => "Text Editor",
            .controls => "Controls",
            .pickers => "Pickers",
            .images => "Images & Drawing",
            .layout => "Layout",
            .lists => "Lists",
            .table => "Table",
            .navigation => "Navigation",
            .presentations => "Presentations",
            .menus => "Menus & Commands",
            .windows => "Windows",
            .effects => "Effects & Animation",
            .forms => "Forms & Settings",
            .files => "Files",
            .mediaAudio => "Media Audio",
            .mediaVideo => "Media Video",
            .mediaWeb => "Media Web",
            .mediaNative => "Media Native",
            .chat => "Chat",
            .diffs => "Diffs",
        };
    }

    /// The section's sidebar icon.
    ///
    /// - `self`: the section.
    /// - Returns: the icon.
    pub fn icon(self: *const Self) ziggui.IconName {
        return switch (self.*) {
            .text => .sparkles,
            .textEditor => .fileText,
            .controls => .settings,
            .pickers => .chevronsUpDown,
            .images => .image,
            .layout => .boxes,
            .lists => .list,
            .table => .folder,
            .navigation => .send,
            .presentations => .layers,
            .menus => .menu,
            .windows => .appWindow,
            .effects => .zap,
            .forms => .listChecks,
            .files => .folderOpen,
            .mediaAudio => .audioLines,
            .mediaVideo => .monitorPlay,
            .mediaWeb => .globe,
            .mediaNative => .pictureInPicture2,
            .chat => .messageSquare,
            .diffs => .table,
        };
    }

    /// The names lines its cards draw (`CardName`), as written: what the
    /// sidebar's search looks through (`SectionSearch`). A test draws every
    /// section and fails on a line missing here; the Editor's find bar's line
    /// is listed though it shows only while the bar is open.
    ///
    /// - `self`: the section.
    /// - Returns: its lines, each names separated by ` · `.
    pub fn names(self: *const Self) []const []const u8 {
        return switch (self.*) {
            .text => &.{ "ziggui.Text", "ziggui.WrappedText", "ziggui.HighlightedText · ziggui.TextRange", "ziggui.Label", "ziggui.TextField", "ziggui.SearchField" },
            .textEditor => &.{ "ziggui.TextEditor", "ziggui.TextEditor · ziggui.FindBar · ziggui.FindCount · ziggui.FindActions" },
            .controls => &.{ "ziggui.Button · ziggui.ButtonRoled · ziggui.IconButton", "ziggui.ButtonKeyed", "ziggui.Toggle", "ziggui.Slider · ziggui.ProgressView", "ziggui.Spinner · ziggui.LoadingDots", "ziggui.Stepper", "ziggui.Badge", "ziggui.KeyCap" },
            .pickers => &.{ "ziggui.Picker · ziggui.Form · .pickerStyle(.automatic)", "ziggui.Picker · .pickerStyle(.segmented) · .pickerStyle(.menu)", "ziggui.RadioGroup", "ziggui.SegmentedControl", "ziggui.IconSegmentedControl" },
            .images => &.{ "ziggui.Image · .scaledToFit()", "ziggui.Canvas · GraphicsContext.verticalGradient · .line · .fill · .text", "CanvasMarkers.crosshair · .ring · .halo · .reticle · .pill · .chip · .callout · .nearest", "ziggui.ZoomableImage · ZoomState · CanvasMarkers · .onDrag", "ziggui.Rectangle · ziggui.RoundedRectangle · ziggui.Circle · ziggui.Capsule · ziggui.Ellipse", "ziggui.LinearGradient", "ziggui.Icon · ziggui.LazyVGrid" },
            .layout => &.{ "ziggui.HStack · ziggui.Spacer · ziggui.ZStack", "ziggui.FlowStack", "ziggui.LazyVGrid", "ziggui.LazyHGrid", "ziggui.Divider · ziggui.VDivider", "ziggui.GeometryReader", ".scrollIndicators · ziggui.ScrollIndicatorVisibility" },
            .lists => &.{ "ziggui.PaneHeader", "ziggui.SelectableRow", "ziggui.ReorderableRow", "ziggui.OutlineState · ziggui.OutlineRow", "ziggui.EditableText · ziggui.EditableTextState", "ziggui.CheckList · ziggui.CheckRow", "ziggui.TableHeader · ziggui.TableRow · ziggui.VirtualList" },
            .table => &.{"ziggui.TableResizable · ziggui.TableColumnCustomization"},
            .navigation => &.{ "ziggui.TabView · ziggui.ScrollView", "ziggui.HSplitView · ziggui.VSplitView", "ziggui.NavigationLinkIcon · ziggui.NavigationPath", "ziggui.NavigationSplitViewInset · ziggui.SidebarStyled" },
            .presentations => &.{ ".sheet · .alert", "ziggui.Menu", ".popover", ".popover · .popoverPassthrough", ".onHover", "ziggui.HoverPopover" },
            .menus => &.{ "ziggui.MenuBar", "ziggui.KeyHintBar", "ziggui.App.setKeyUpHandler · ziggui.Toggle" },
            .windows => &.{ "ziggui.TitleBar · ziggui.MenuBar · ziggui.WindowButtons", "ziggui.WindowChrome.topBar", "ziggui.WindowChrome.topBarLeading · ziggui.IconSegmentedControl", "ziggui.WindowChrome.topBarLeading", "ziggui.Canvas · Theme.drawTitleBar · .modalPassthrough", "ziggui.StatusLine" },
            .effects => &.{ "ziggui.Animator · ziggui.ProgressView", ".glassEffect", ".opacity · .border · .cornerRadius", ".backgroundMaterial(.regular)" },
            .forms => &.{ "ziggui.SettingRow", "ziggui.KeyValueEditor", "ziggui.TokenField", "ziggui.Settings · ziggui.Form · ziggui.Section · ziggui.LabeledContent · ziggui.Toggle · ziggui.AppearancePicker · ziggui.ThemePicker" },
            .files => &.{ "ziggui.FileBrowser · FileBrowserState.shows_file", "ziggui.FileDialog.openFile · .saveFile · .takeResult" },
            .mediaAudio => &.{ "ziggui.AudioPlayerControls · ziggui.AudioPlayerControlsState · ziggui.Player", "ziggui.AudioInfoView · ziggui.AudioOutputs" },
            .mediaVideo => &.{ "ziggui.VideoPlayer · ziggui.VideoPlayerControls · ziggui.Player", "ziggui.VideoInfoView · ziggui.SystemInfo" },
            .mediaWeb => &.{"ziggui.WebView · ziggui.WebPage · ziggui.WebPageMessageCallback"},
            .mediaNative => &.{"ziggui.NativeView"},
            .chat => &.{ "ziggui.StatusMark", "ziggui.Chip", "ziggui.Bubble · ziggui.DisclosureGroup · ziggui.DisclosureGroupAccessory · ziggui.CodeBlock · ziggui.Quote" },
            .diffs => &.{"ziggui.SelectableDiffViewWithActions · ziggui.HunkAction · ziggui.DiffSelection"},
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
            .table, .textEditor, .navigation, .mediaWeb => true,
            else => false,
        };
    }

    /// The section at index `index` (its place in the enum, as `--section`
    /// names it), clamped to the sections there are.
    ///
    /// - `index`: a section's index.
    /// - Returns: the section.
    pub fn at(index: i64) Self {
        const last: i64 = Self.items.len - 1;
        return @fromBackingInt(@intCast(std.math.clamp(index, 0, last)));
    }
};

/// The Windows section's top band's segmented control's segments, as ziggit's switch has them.
const top_bar_segments = [_]ziggui.IconSegment{
    .{ .icon = .gitBranch, .title = "Git" },
    .{ .icon = .code, .title = "Files" },
    .{ .icon = .package, .title = "Deps" },
};

/// The accent switcher's choices, in display order, as `ziggui.Accent.atChoice`
/// names them (so the sidebar and the Settings `ThemePicker` agree): null
/// first, keeping each theme's own accent (macOS uses distinct blues for
/// accent and selection), then every `ziggui.Accent`, as the apps draw it
/// (`Accent.theme`).
const accents = blk: {
    var choices: [ziggui.Accent.all.len + 1]?ziggui.Accent = undefined;
    for (&choices, 0..) |*choice, index| choice.* = ziggui.Accent.atChoice(index);
    break :blk choices;
};

/// The width one accent swatch takes, in points: the nine fit the
/// sidebar's width in one row with the dark-mode button.
const swatch_size: f32 = 18;

/// The side of the sidebar's dark-mode button, in points.
const dark_button_size: f32 = 22;

/// The corner radius of the sidebar's dark-mode button, in points.
const dark_button_radius: f32 = 6;

/// The height of the accent switcher's row, in points.
const swatch_row_height: f32 = 22;

/// The gap `ziggui.Sidebar` leaves between its rows, in points: the sidebar's
/// arrow keys reveal a row from the list's height (`Gallery.revealSidebarRow`).
const sidebar_row_spacing: f32 = 2;

/// The Lists section's table rows' columns.
const file_columns = [_]ziggui.DataColumn{
    .{ .title = "Name" },
    .{ .title = "Kind", .width = 90 },
    .{ .title = "Size", .width = 70, .trailing = true },
};

/// How many rows the Lists section's virtual list holds.
const file_count: usize = 10_000;

/// The height of one of the Lists section's table rows, in points.
const file_row_height: f32 = 24;

/// How many of the sample diff's rows show at once; the rest scroll.
const diff_rows_shown: f32 = 10;

/// The Diffs section's sample diff: two files, three hunks, one line wider than
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

/// A Menus & Commands section entry's choice: says which entry was chosen.
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

/// The Menus & Commands section's menus: titles and entries, `ctrl+` keys as off macOS.
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

/// How many entries the Menus & Commands section's menus hold, separators included.
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

    /// The section shown, its index (an index into `Section.items`, not its
    /// sidebar row: `sidebarSelection` maps the two).
    section: ziggui.State(i64),

    /// The Windows section's top band's segmented control's selection.
    top_bar_mode: ziggui.State(i64),

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

    /// Whether the sidebar's arrow keys brought the section on show in, so it
    /// takes no keyboard focus as it comes in (`track`) and the next arrow
    /// still walks the sidebar.
    entered_by_keys: bool = false,

    /// The section the last frame showed, null before the first.
    shown_section: ?Section = null,

    /// The sidebar's search: its field, and the rows it leaves the list.
    search: gallery.SectionSearch,

    /// How the sidebar's list looked when last painted (`SectionSearch.layoutKey`):
    /// a row is scrolled into view only once the list measured is the one shown.
    painted_list: u64 = 0,

    /// Whether the shown section's row waits to be scrolled into view: at
    /// launch (`--section` may pick one below the fold), and after the list
    /// changes (a search, or its end).
    reveal_pending: bool = true,

    /// The panels folded in from zigui's showcase, and their state.
    showcase: gallery.Showcase,

    /// The Text Editor section's editor.
    editor: gallery.Editor,

    /// The design-kit cards and panels (in Controls, Pickers, Lists, Forms &
    /// Settings, Files) and their state.
    kit: gallery.Kit,

    /// The Media Video panel and its player.
    media: gallery.Media,

    /// The Pickers panel and its choices.
    pickers: gallery.Pickers,

    /// The Settings panel and its state.
    settings: gallery.SettingsPanel,

    /// The Media Web panel: its page and bookmarks.
    web: gallery.WebPanel,

    /// Whether the Chat panel's tool call is unfolded.
    tool_open: bool = false,

    /// Whether the Chat panel's thought is unfolded: open at first, so the
    /// card shows a group both folded and unfolded.
    thought_open: bool = true,

    /// The Lists section's virtual list position.
    files_scroll: ziggui.ScrollState = .{},

    /// The Lists section's selected table row.
    file_selected: usize = 2,

    /// The Diffs section's diff position.
    diff_scroll: ziggui.ScrollState = .{},
    /// The Diffs section's selected lines.
    diff_selection: ziggui.DiffSelection = .{},

    /// The Diffs section's selected hunk.
    hunk_selected: usize = 0,

    /// The Navigation section's split views''s column divider.
    columns: ziggui.SplitState = .{ .initial_ratio = 0.35, .min_first = 120, .min_second = 160 },

    /// The Navigation section's split views''s row divider.
    rows: ziggui.SplitState = .{ .initial_ratio = 0.5, .min_first = 60, .min_second = 60 },

    /// The Presentations section's hover popover's rows: which one the pointer rests on.
    hover: ziggui.HoverState = .{},

    /// The Menus & Commands section's bar.
    menu_bar: ziggui.MenuBarState = .{},

    /// The Menus & Commands section's last chosen entry.
    menu_choice: []const u8 = "Nothing chosen yet.",

    /// The Menus & Commands section's entries, their actions pointing at this gallery (`barMenus`).
    bar_items: [bar_item_count]ziggui.MenuBarItem = undefined,

    /// What each of `bar_items` does.
    bar_choices: [bar_item_count]BarChoice = undefined,

    /// The Menus & Commands section's menus, over `bar_items`.
    bar_menus: [bar_menus.len]ziggui.MenuBarMenu = undefined,

    /// The Windows section's title-bar card's two bars' menus (the second one folded).
    title_menus: [2]ziggui.MenuBarState = .{ .{}, .{} },

    /// What the Windows section's title-bar card's window buttons last did.
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
        var editor = try gallery.Editor.init(allocator);
        errdefer editor.deinit();
        var kit = try gallery.Kit.init(allocator);
        errdefer kit.deinit();
        const web = try gallery.WebPanel.init(allocator);
        const self = Self{
            .allocator = allocator,
            .section = ziggui.State(i64).init(allocator, 0),
            .dark = ziggui.State(bool).init(allocator, false),
            .theme_family = ziggui.State(i64).init(allocator, 0),
            .accent = ziggui.State(i64).init(allocator, 0),
            .top_bar_mode = ziggui.State(i64).init(allocator, 0),
            .showcase = showcase,
            .editor = editor,
            .kit = kit,
            .media = gallery.Media.init(allocator),
            .pickers = gallery.Pickers.init(allocator),
            .settings = gallery.SettingsPanel.init(allocator),
            .web = web,
            .search = gallery.SectionSearch.init(allocator),
        };
        return self;
    }

    /// Releases the gallery's state.
    ///
    /// - `self`: the gallery to tear down.
    pub fn deinit(self: *Self) void {
        self.search.deinit();
        self.web.deinit();
        self.settings.deinit();
        self.pickers.deinit();
        self.media.deinit();
        self.kit.deinit();
        self.editor.deinit();
        self.showcase.deinit();
        self.top_bar_mode.deinit();
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

    /// Builds the window's view tree: the sidebar beside the selected panel,
    /// or the Media Video panel's player alone while it is full screen.
    ///
    /// Called once per frame, inside `BuildScope.begin`/`end`.
    ///
    /// - `self`: the gallery supplying the state.
    /// - Returns: the root view.
    pub fn body(self: *Self) ziggui.View {
        self.followSearch();
        self.track(Section.at(self.section.get()));
        const active_theme = self.theme();
        // The Media Video panel's player, full screen: nothing else shows but the
        // sheet and alerts (the quit question).
        self.media.syncFullScreen();
        if (self.media.expanded) return self.showcase.presentations(self.media.expandedView(), active_theme);
        const root = ziggui.NavigationSplitView(
            self.sidebar(active_theme),
            self.detail(active_theme),
            active_theme.colors.sidebar_background orelse active_theme.colors.secondary_background,
        );
        return self.showcase.presentations(root, active_theme);
    }

    /// The Menus & Commands section's menus, each entry's action recording its title
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

    /// A key went down (ziggui's raw event), for the Menus & Commands section's bar:
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

    /// A key went down (ziggui's raw event): Esc takes the Media Video panel's
    /// player out of full screen, unless a sheet or alert is up; then the Menu
    /// Bar panel's keys, then, with nothing modal up, the sidebar search's
    /// keys while its field has the keyboard (`searchKeyDown`), else the
    /// Text Editor section's shortcuts or the File Browser's keys while its list
    /// holds them, and last ↑ and ↓ walk the sidebar's rows (`sidebarKeyDown`).
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a panel used it.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        // Not under a sheet or alert (the quit question): Esc is theirs then.
        if (self.media.expanded and keycode == ziggui.SdlKey.escape and !self.presentsModal()) {
            self.media.toggleExpanded();
            return true;
        }
        if (self.menuKeyDown(keycode, modifiers)) return true;
        if (self.presentsModal()) return false;
        if (ziggui.Focus.shared().focused() == &self.search.field) return self.searchKeyDown(keycode, modifiers);
        return switch (Section.at(self.section.get())) {
            .textEditor => self.editor.keyDown(keycode, modifiers) or self.sidebarKeyDown(keycode, modifiers),
            .files => if (ziggui.Focus.shared().focused() != null)
                false
            else if (self.kit.files_have_keys) self.kit.files.keyDown(keycode, modifiers, gallery.is_macos) catch |err| {
                log.err("file browser key not handled [{t}]", .{err});
                return false;
            } else self.sidebarKeyDown(keycode, modifiers),
            .lists => self.kit.editableKeyDown(keycode, modifiers) or self.sidebarKeyDown(keycode, modifiers),
            else => self.sidebarKeyDown(keycode, modifiers),
        };
    }

    /// A left mouse button went down in the window: on the File Browser's list
    /// it gives that list the arrow keys (a tap on a sidebar row takes them
    /// back, `selectRow`); anywhere else it leaves them where they are.
    ///
    /// - `self`: the gallery.
    /// - `point`: where it went down, in window points.
    pub fn pointerDown(self: *Self, point: ziggui.Point) void {
        // A press on a modal's scrim lands on nothing behind it.
        if (self.presentsModal()) return;
        if (Section.at(self.section.get()) == .files and Self.listContains(&self.kit.files.scroll, point)) self.kit.files_have_keys = true;
    }

    /// The Images & Drawing section's picture zoom, for the event loop's pinches
    /// and ⌘-scrolls, while that panel shows with nothing modal over it.
    ///
    /// - `self`: the gallery.
    /// - Returns: the zoom, or null when the picture is not showing.
    pub fn pictureZoom(self: *Self) ?*ziggui.ZoomState {
        if (self.presentsModal()) return null;
        if (Section.at(self.section.get()) != .images) return null;
        return &self.showcase.picture_zoom;
    }

    /// A key came up (ziggui's raw event): the Menus & Commands section's Alt tap
    /// (`menuKeyUp`), and the Presentations section's last key-up.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the event's `SDL_Keycode`.
    pub fn keyUp(self: *Self, keycode: u32) void {
        self.menuKeyUp(keycode);
        self.showcase.keyUp(keycode);
    }

    /// A quit was asked for (the window's close button, ⌘Q): the Menus &
    /// Commands section's "Ask before quitting" may present a question instead.
    ///
    /// - `self`: the gallery.
    /// - Returns: true to let the quit end the loop.
    pub fn quitRequested(self: *Self) bool {
        return self.showcase.quitRequested();
    }

    /// A key came up (ziggui's raw event): Alt after a tap opens the Menus &
    /// Commands section's first menu, or closes the open one (`MenuBarState.appKeyUp`).
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

    /// Folds or unfolds the Chat panel's thought.
    ///
    /// - `self`: the gallery.
    pub fn toggleThought(self: *Self) void {
        self.thought_open = !self.thought_open;
    }

    /// Selects a row of the Diffs section's table.
    ///
    /// - `self`: the gallery.
    /// - `index`: the row.
    pub fn selectFile(self: *Self, index: usize) void {
        self.file_selected = index;
    }

    /// Selects a hunk of the Diffs section's diff.
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
            ziggui.HStack(.{
                ziggui.SearchField("Search components", &self.search.field, ziggui.Callback.init(Self, self, Self.searchSubmitted), null),
            }).paddingInsets(.{ .leading = 2, .bottom = 4, .trailing = 2 }),
            self.sidebarList(active_theme),
            ziggui.Divider(),
            ziggui.VStack(.{
                ziggui.ThemeFamilyPicker(self.theme_family.binding(), self.accent.binding()),
                self.accentSwatches(active_theme),
            }).spacing(8).alignment(.leading).padding(4),
        }).spacing(4).padding(8).frameMaxHeight().backgroundMaterial(.thin);
    }

    /// The sidebar's dark-mode button: a moon on the accent while the window
    /// draws dark, a sun otherwise; a tap flips it.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the button.
    fn darkModeButton(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const colors = active_theme.colors;
        const dark = self.dark.get();
        return ziggui.ZStack(.{
            ziggui.Icon(if (dark) .moon else .sun, 13, if (dark) colors.on_accent else colors.label),
        }).frame(dark_button_size, dark_button_size)
            .background(if (dark) colors.accent else colors.quaternary_fill)
            .cornerRadius(active_theme.metrics.radius(dark_button_radius))
            .onTap(ziggui.Callback.init(Self, self, Self.toggleDark))
            .help(if (dark) "Dark mode: on" else "Dark mode: off")
            .accessibilityLabel("Dark mode")
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = dark });
    }

    /// Flips the window between its light and dark appearance (the sidebar's dark-mode button).
    ///
    /// - `self`: the gallery.
    fn toggleDark(self: *Self) void {
        self.dark.set(!self.dark.get());
    }

    /// The accent switcher: a row of tappable color dots, the chosen one
    /// ringed; the first shows the theme's own accent; the dark-mode button
    /// ends the row.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the row.
    fn accentSwatches(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const chosen = self.accentIndex();
        const own = self.ownTheme().colors.accent;
        // The stack copies its children into the frame's build arena.
        var dots: [accents.len + 2]ziggui.View = undefined;
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
        dots[accents.len + 1] = self.darkModeButton(active_theme);
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
            ziggui.Text(section.label()).font(.largeTitle).frameMaxWidth().frameAlign(.leading),
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
            .text => Self.cards(.{ self.showcase.typeScaleCard(active_theme), self.showcase.wrappedTextCard(active_theme), self.showcase.highlightedTextCard(active_theme), self.showcase.labelCard(active_theme), self.showcase.textFieldCard(active_theme), self.kit.searchFieldCard(active_theme) }),
            .textEditor => self.editor.body(active_theme),
            .controls => Self.cards(.{ self.showcase.buttonsCard(active_theme), self.kit.buttonKeyedCard(active_theme), self.showcase.togglesCard(active_theme), self.showcase.sliderCard(active_theme), self.showcase.progressCard(active_theme), self.showcase.stepperCard(active_theme), self.kit.badgeCard(active_theme), self.kit.keyCapCard(active_theme) }),
            .pickers => Self.cards(.{ self.pickers.panel(active_theme), self.showcase.radioGroupCard(active_theme), self.kit.segmentedControlCard(active_theme), self.kit.iconSegmentedControlCard(active_theme) }),
            .images => Self.cards(.{ self.showcase.canvasPanel(active_theme), self.showcase.shapesCard(active_theme), self.showcase.gradientCard(active_theme), self.showcase.iconGalleryCard(active_theme) }),
            .layout => Self.cards(.{ self.showcase.stacksCard(active_theme), self.showcase.flowStackCard(active_theme), self.showcase.verticalGridCard(active_theme), self.showcase.horizontalGridCard(active_theme), self.showcase.dividersCard(active_theme), self.showcase.geometryPanel(active_theme), self.showcase.scrollIndicatorsCard(active_theme) }),
            .lists => Self.cards(.{ self.kit.rowsPanel(active_theme), self.kit.reorderPanel(active_theme), self.kit.outlinePanel(active_theme), self.kit.editablePanel(active_theme), self.kit.checkListCard(active_theme), self.tableRowsCard(active_theme) }),
            .table => self.showcase.tablePanel(active_theme, section.label()),
            .navigation => self.showcase.navigationPanel(active_theme, section.label(), Self.cards(.{ self.showcase.tabViewCard(active_theme), self.splitPanel(active_theme) })),
            .presentations => Self.cards(.{ self.showcase.modalCard(active_theme), self.showcase.menuCard(active_theme), self.showcase.popoverCard(active_theme), self.showcase.passthroughCard(active_theme), self.showcase.onHoverCard(active_theme), self.hoverPanel(active_theme) }),
            .menus => Self.cards(.{ self.menuBarPanel(active_theme), self.kit.keyHintBarCard(active_theme), self.showcase.keyUpsCard(active_theme) }),
            .windows => Self.cards(.{ self.titleBarPanel(active_theme), self.topBarPanel(active_theme), self.showcase.customTitleBarCard(active_theme), Self.statusLinePanel(active_theme) }),
            .effects => Self.cards(.{ self.showcase.effectsPanel(active_theme), self.showcase.materialCard(active_theme) }),
            .forms => Self.cards(.{ self.kit.settingRowCard(active_theme), self.kit.keyValueEditorCard(active_theme), self.kit.tokenFieldCard(active_theme), self.settings.panel(active_theme, self.theme_family.binding(), self.accent.binding()) }),
            .files => self.kit.filesPanel(active_theme),
            .mediaAudio => self.media.audioPanel(active_theme),
            .mediaVideo => self.media.videoPanel(active_theme),
            .mediaWeb => self.web.panel(active_theme, section.label()),
            .mediaNative => self.media.nativePanel(active_theme),
            .chat => self.chatPanel(active_theme),
            .diffs => self.diffCard(active_theme),
        };
    }

    /// A section's cards, top to bottom, 16 points apart, as every panel stacks them.
    ///
    /// - `views`: the cards (or whole panels), a tuple literal.
    /// - Returns: the stack.
    fn cards(views: anytype) ziggui.View {
        return ziggui.VStack(views).spacing(16);
    }

    /// Notes the section this frame shows. On a change, no field or list but
    /// the sidebar's search keeps the keyboard (keys must not reach one not drawn), leaving
    /// Navigation empties its stack, the Editor takes the keyboard as it comes
    /// in unless the sidebar's arrow keys brought it, and the Video and Audio
    /// Player panels read the system the first time.
    ///
    /// - `self`: the gallery.
    /// - `section`: the section this frame shows.
    fn track(self: *Self, section: Section) void {
        if (self.shown_section == section) return;
        self.shown_section = section;
        const by_keys = self.entered_by_keys;
        self.entered_by_keys = false;
        // The search field keeps the keyboard while what is typed changes the section.
        if (ziggui.Focus.shared().focused() != &self.search.field) ziggui.Focus.shared().clear();
        self.kit.files_have_keys = false;
        if (section != .navigation) self.showcase.clearNavigation();
        if (section == .textEditor and !by_keys) self.editor.focus();
        if (section == .mediaVideo or section == .mediaAudio) self.media.showPanel();
    }

    /// The Chat panel: status marks, chips, and a transcript of blocks.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn chatPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const toggle = ziggui.Callback.init(Self, self, Self.toggleTool);
        return ziggui.VStack(.{
            gallery.Card.view(active_theme, "Status marks", "ziggui.StatusMark", ziggui.HStack(.{
                ziggui.StatusMark(.idle, 10),     ziggui.Text("idle").font(.footnote),
                ziggui.StatusMark(.busy, 10),     ziggui.Text("busy").font(.footnote),
                ziggui.StatusMark(.waiting, 10),  ziggui.Text("waiting").font(.footnote),
                ziggui.StatusMark(.starting, 10), ziggui.Text("starting").font(.footnote),
                ziggui.StatusMark(.stopped, 10),  ziggui.Text("stopped").font(.footnote),
                ziggui.Spacer(),
            }).spacing(6)),
            gallery.Card.view(active_theme, "Chips", "ziggui.Chip", ziggui.HStack(.{
                ziggui.Chip("Ask before edits", .shield, toggle),
                ziggui.Chip("Opus", .sparkles, toggle),
                ziggui.Chip("screenshot.png · 84 KB", .image, null),
                ziggui.Spacer(),
            }).spacing(8)),
            gallery.Card.view(active_theme, "Transcript", "ziggui.Bubble · ziggui.DisclosureGroup · ziggui.DisclosureGroupAccessory · ziggui.CodeBlock · ziggui.Quote", ziggui.VStack(.{
                Self.leading(ziggui.Bubble(ziggui.WrappedText("List the files and explain the build."), active_theme.colors.accent.withAlpha(0.16))),
                ziggui.DisclosureGroup(
                    ziggui.Text("Thought for 4 seconds").font(.footnote).foreground(active_theme.colors.secondary_label),
                    self.thought_open,
                    ziggui.Callback.init(Self, self, Self.toggleThought),
                    ziggui.WrappedText("The build file names every step; list the folder first.").font(.footnote).foreground(active_theme.colors.secondary_label),
                ),
                ziggui.DisclosureGroupAccessory(
                    ziggui.Text("ls -la").font(.footnote).mono(),
                    ziggui.Badge("3 files", .neutral),
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

    /// The table rows card: a header over a virtual list of 10,000 rows.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn tableRowsCard(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(active_theme, "Table rows over a virtual list (10,000 rows)", "ziggui.TableHeader · ziggui.TableRow · ziggui.VirtualList", ziggui.VStack(.{
            ziggui.TableHeader(&file_columns),
            ziggui.VirtualList(Self, self, file_count, file_row_height, &self.files_scroll, Self.fileRow).frameHeight(150),
        }).spacing(0));
    }

    /// The diff card: a selectable diff with links on its hunk headers.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn diffCard(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const on_hunk = ziggui.IndexCallback.init(Self, self, Self.selectHunk);
        const actions = ziggui.BuildScope.shared().allocator().dupe(ziggui.HunkAction, &.{
            .{ .label = "Select", .callback = on_hunk },
            .{ .label = "Disabled", .callback = on_hunk, .disabled = true },
        }) catch @panic("oom");
        return gallery.Card.view(active_theme, "SelectableDiffView with hunk links (tap a row for its hunk and line, drag for more, ⌘C copies)", "ziggui.SelectableDiffViewWithActions · ziggui.HunkAction · ziggui.DiffSelection", ziggui.VStack(.{
            ziggui.SelectableDiffViewWithActions(&sample_diff, self.hunk_selected, &self.diff_scroll, on_hunk, &self.diff_selection, actions),
        }).spacing(0).frameHeight(diff_rows_shown * ziggui.diff_row_height));
    }

    /// Row `index` of the Diffs section's table.
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

    /// The Navigation section's split views': an `HSplitView` whose trailing pane is a `VSplitView`.
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
        return gallery.Card.view(active_theme, "HSplitView over a VSplitView", "ziggui.HSplitView · ziggui.VSplitView", split
            .frameMaxWidth()
            .frameHeight(260)
            .border(active_theme.colors.separator, 1));
    }

    /// The Menus & Commands section: a bar over a window's worth of space, and the last choice.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn menuBarPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(active_theme, "MenuBar (click a title, point at the next; Alt opens the first menu)", "ziggui.MenuBar", ziggui.VStack(.{
            ziggui.MenuBar(&self.menu_bar, self.barMenus(), .{}),
            ziggui.Divider(),
            ziggui.VStack(.{
                ziggui.Text(self.menu_choice).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
                ziggui.Spacer(),
            }).padding(12).frameHeight(260),
        }).spacing(0).border(active_theme.colors.separator, 1));
    }

    /// The Windows section's title-bar card: a title bar with Windows' buttons, then a narrow
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
            gallery.Card.view(active_theme, "TitleBar with Windows' buttons (the theme colors the bar)", "ziggui.TitleBar · ziggui.MenuBar · ziggui.WindowButtons", ziggui.TitleBar(
                ziggui.HStack(.{
                    ziggui.Icon(.boxes, 16, foreground).paddingInsets(.{ .leading = 10 }),
                    ziggui.MenuBar(&self.title_menus[0], self.barMenus(), .{ .foreground = foreground, .fill = false }),
                }).spacing(4),
                "~/src/mlavergn/ziggui",
                ziggui.WindowButtons(.windows, false, actions),
            ).border(active_theme.colors.separator, 1)),
            gallery.Card.view(active_theme, "Narrow, with GNOME's buttons and the menus folded", "ziggui.TitleBar · ziggui.MenuBar · ziggui.WindowButtons", Self.leading(ziggui.TitleBar(
                ziggui.HStack(.{
                    ziggui.Icon(.boxes, 16, foreground).paddingInsets(.{ .leading = 10 }),
                    ziggui.MenuBar(&self.title_menus[1], folded, .{ .foreground = foreground, .fill = false }),
                }).spacing(4),
                "~/src/mlavergn/ziggui",
                ziggui.WindowButtons(.gnome, true, actions),
            ).frameWidth(360).border(active_theme.colors.separator, 1))),
            ziggui.Text(self.window_said).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(16);
    }

    /// The sidebar's selection: the shown section's row in the sidebar's
    /// alphabetical order, setting the section a row lists.
    ///
    /// - `self`: the gallery.
    /// - Returns: the binding.
    fn sidebarSelection(self: *Self) ziggui.Binding(i64) {
        return .{ .context = self, .get_fn = Self.selectedRow, .set_fn = Self.selectRow };
    }

    /// Walks the sidebar's rows (those the search leaves) on a plain ↑ or ↓, stopping at its ends, and
    /// scrolls the row reached into view. A modal (`presentsModal`), a
    /// focused text field, an open text menu and the full-screen player keep
    /// the keys.
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when it took the key.
    fn sidebarKeyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (modifiers & ziggui.SdlKey.modifier_mask != 0 or self.presentsModal()) return false;
        if (self.media.expanded or ziggui.Focus.shared().focused() != null or ziggui.TextContextMenu.shared().isOpen()) return false;
        const step: i64 = switch (keycode) {
            ziggui.SdlKey.up_arrow => -1,
            ziggui.SdlKey.down_arrow => 1,
            else => return false,
        };
        self.stepRow(step);
        return true;
    }

    /// The sidebar's list: the rows the search leaves (every section with
    /// nothing typed, each match's component under it otherwise), scrolling
    /// when the window is too short for them, or a line saying nothing
    /// matched. Scrolls the shown row into view once the list it measures is
    /// the one painted, asking for a frame until then.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the list.
    fn sidebarList(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const rows = self.search.shown();
        if (rows.len == 0) {
            return ziggui.VStack(.{
                ziggui.Text("No component matches.").font(.footnote).foreground(active_theme.colors.secondary_label).padding(10),
                ziggui.Spacer(),
            }).frameMaxWidth().frameMaxHeight();
        }
        const key = self.search.layoutKey();
        if (self.reveal_pending) {
            if (key == self.painted_list) {
                self.reveal_pending = false;
                if (self.search.rowOf(Section.at(self.section.get()))) |row| self.revealSidebarRow(row);
            } else {
                const clock = ziggui.FrameClock.shared();
                clock.requestFrameAt(clock.time());
            }
        }
        self.painted_list = key;
        const items = ziggui.BuildScope.shared().allocator().alloc(ziggui.SidebarItem, rows.len) catch @panic("oom");
        for (rows, items) |row, *item| item.* = .{ .label = row.section.label(), .icon = row.section.icon(), .detail = row.detail };
        // Scrolls when the window is too short for every row.
        return ziggui.ScrollViewState(&self.sidebar_scroll, ziggui.Sidebar(items, self.sidebarSelection()))
            .frameMaxWidth()
            .frameMaxHeight();
    }

    /// Takes in what was typed in the sidebar's search: makes its rows again
    /// and, when the section shown is not among them, shows the first, as the
    /// sidebar's keys would (the Editor not taking the keyboard from the
    /// search); either way its row is scrolled into view once drawn.
    ///
    /// - `self`: the gallery.
    fn followSearch(self: *Self) void {
        if (!self.search.refresh()) return;
        const rows = self.search.shown();
        if (rows.len > 0 and self.search.rowOf(Section.at(self.section.get())) == null) {
            self.section.set(@backingInt(rows[0].section));
            self.entered_by_keys = true;
        }
        self.reveal_pending = true;
    }

    /// Gives the sidebar's search field its keys: ↑ and ↓ walk the rows it
    /// leaves, and Esc empties it and hands the keyboard back to the list, the
    /// section found still shown. Enter is the field's (`searchSubmitted`).
    ///
    /// - `self`: the gallery.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when the search took the key; else the field types it.
    fn searchKeyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (modifiers & ziggui.SdlKey.modifier_mask != 0) return false;
        switch (keycode) {
            ziggui.SdlKey.up_arrow => self.stepRow(-1),
            ziggui.SdlKey.down_arrow => self.stepRow(1),
            ziggui.SdlKey.escape => {
                self.search.clear();
                ziggui.Focus.shared().clear();
            },
            else => return false,
        }
        return true;
    }

    /// Enter in the sidebar's search: the keyboard goes back to the list, the
    /// rows found still showing, so ↑ and ↓ walk them.
    ///
    /// - `self`: the gallery.
    fn searchSubmitted(self: *Self) void {
        if (ziggui.Focus.shared().focused() == &self.search.field) ziggui.Focus.shared().clear();
    }

    /// Shows the section a row away from the one shown among the rows the
    /// search leaves, stopping at the ends, and scrolls its row into view.
    ///
    /// - `self`: the gallery.
    /// - `step`: -1 for the row above, 1 for the one below.
    fn stepRow(self: *Self, step: i64) void {
        const rows = self.search.shown();
        if (rows.len == 0) return;
        const shown = Section.at(self.section.get());
        const position: i64 = if (self.search.rowOf(shown)) |row| @intCast(row) else -1;
        const row: usize = @intCast(std.math.clamp(position + step, 0, @as(i64, @intCast(rows.len - 1))));
        if (rows[row].section != shown) {
            self.section.set(@backingInt(rows[row].section));
            self.entered_by_keys = true;
        }
        self.revealSidebarRow(row);
    }

    /// Reports whether anything modal covers the window: the Presentations section's
    /// sheet, alert or quit question, the Settings sheet, or the Editor's
    /// Open dialog. Under one, the menu bar, the sidebar's keys and the panel
    /// behind take nothing.
    ///
    /// - `self`: the gallery.
    /// - Returns: true while one is presented.
    fn presentsModal(self: *const Self) bool {
        return self.showcase.presentsModal() or self.settings.show_sheet.get() or self.editor.show_dialog.get();
    }

    /// Scrolls the sidebar's list just enough to show a row, once a frame has
    /// laid it out (its rows are as tall as its content over their count).
    ///
    /// - `self`: the gallery.
    /// - `row`: the row.
    fn revealSidebarRow(self: *Self, row: usize) void {
        const scroll = &self.sidebar_scroll;
        if (scroll.content_height <= 0) return;
        const count: f32 = @floatFromInt(self.search.shown().len);
        scroll.reveal(row, (scroll.content_height + sidebar_row_spacing) / count);
    }

    /// Whether a point lies on a vertical list in the detail pane, as the last
    /// frame showed it: between its top and bottom, right of its left edge
    /// (the painter notes no width for a list that only scrolls down, and
    /// nothing else in the pane shares its rows).
    ///
    /// - `scroll`: the list's scroll position, its viewport noted as it painted.
    /// - `point`: the point, in window points.
    /// - Returns: true on the list; false before it was ever drawn.
    fn listContains(scroll: *const ziggui.ScrollState, point: ziggui.Point) bool {
        if (scroll.viewport_height <= 0) return false;
        return point.x >= scroll.viewport_x and point.y >= scroll.viewport_y and point.y < scroll.viewport_y + scroll.viewport_height;
    }

    /// The sidebar row of the section shown (`sidebarSelection`'s reader).
    ///
    /// - `context`: the gallery.
    /// - Returns: the row.
    fn selectedRow(context: *anyopaque) i64 {
        const self: *Self = @ptrCast(@alignCast(context));
        const row = self.search.rowOf(Section.at(self.section.get())) orelse return -1;
        return @intCast(row);
    }

    /// Shows the section sidebar row `index` lists (`sidebarSelection`'s
    /// writer, called by a tap on the row), and gives the sidebar back the
    /// arrow keys.
    ///
    /// - `context`: the gallery.
    /// - `index`: the row chosen.
    fn selectRow(context: *anyopaque, index: i64) void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.kit.files_have_keys = false;
        const rows = self.search.shown();
        if (rows.len == 0) return;
        const row: usize = @intCast(std.math.clamp(index, 0, @as(i64, @intCast(rows.len - 1))));
        self.section.set(@backingInt(rows[row].section));
    }

    /// The Windows section's top band: macOS's top band as a window draws it, its traffic
    /// lights drawn in, first with the title alone, then with an icon
    /// segmented control after the lights, wide and narrow.
    ///
    /// - `self`: the gallery.
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn topBarPanel(self: *Self, active_theme: ziggui.Theme) ziggui.View {
        const width = ziggui.IconSegment.controlWidth(top_bar_segments.len);
        return ziggui.VStack(.{
            gallery.Card.view(active_theme, "The top band: the title centered, clear of the traffic lights", "ziggui.WindowChrome.topBar", Self.macWindowBand(active_theme, ziggui.WindowChrome.topBar(Self.topBarTitle(active_theme), true))),
            gallery.Card.view(active_theme, "A segmented control after the lights; the title still centered in the window", "ziggui.WindowChrome.topBarLeading · ziggui.IconSegmentedControl", Self.macWindowBand(active_theme, ziggui.WindowChrome.topBarLeading(
                ziggui.IconSegmentedControl(self.top_bar_mode.binding(), &top_bar_segments),
                width,
                Self.topBarTitle(active_theme),
                true,
            ))),
            gallery.Card.view(active_theme, "Narrow: the title truncates before it reaches the control", "ziggui.WindowChrome.topBarLeading", Self.leading(Self.macWindowBand(active_theme, ziggui.WindowChrome.topBarLeading(
                ziggui.IconSegmentedControl(self.top_bar_mode.binding(), &top_bar_segments),
                width,
                Self.topBarTitle(active_theme),
                true,
            )).frameWidth(560))),
            ziggui.Text(ziggui.BuildScope.shared().print("Mode: {s}", .{top_bar_segments[@intCast(std.math.clamp(self.top_bar_mode.get(), 0, top_bar_segments.len - 1))].title})).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(16);
    }

    /// The Windows section's top band's title: a path, as ziggit shows its repository's.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the title.
    fn topBarTitle(active_theme: ziggui.Theme) ziggui.View {
        return ziggui.Text("~/src/mlavergn/ziggui/gallery").font(.footnote).mono().foreground(active_theme.colors.secondary_label).truncated();
    }

    /// A macOS window's top band, its traffic lights drawn over it where
    /// macOS puts them in a unified compact titlebar (12pt in, 14pt across,
    /// 9pt apart, centred in the band), on the window's ground.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - `band`: the band (`WindowChrome.topBar` or `topBarLeading`).
    /// - Returns: the band with its lights.
    fn macWindowBand(active_theme: ziggui.Theme, band: ziggui.View) ziggui.View {
        const lights = ziggui.HStack(.{
            ziggui.Circle(ziggui.Color.fromRgb8(255, 95, 87)).frame(14, 14),
            ziggui.Circle(ziggui.Color.fromRgb8(254, 188, 46)).frame(14, 14),
            ziggui.Circle(ziggui.Color.fromRgb8(40, 200, 64)).frame(14, 14),
            ziggui.Spacer(),
        }).spacing(9).paddingInsets(.{ .leading = 12 }).frameHeight(ziggui.WindowChrome.top_bar_height).frameMaxWidth();
        return ziggui.ZStack(.{ band, lights })
            .frameHeight(ziggui.WindowChrome.top_bar_height)
            .frameMaxWidth()
            .background(active_theme.colors.window_background)
            .border(active_theme.colors.separator, 1);
    }

    /// The Windows section's status lines: the keys a composer takes, then a list's, each
    /// under a notice row as a window's frame ends.
    ///
    /// - `active_theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    fn statusLinePanel(active_theme: ziggui.Theme) ziggui.View {
        const typing = [_]ziggui.KeyHint{ .{ .key = "enter", .action = "send" }, .{ .key = "shift+enter", .action = "new line" }, .{ .key = "esc", .action = "stop" }, .{ .key = "/", .action = "commands" } };
        const listing = [_]ziggui.KeyHint{ .{ .key = "↑↓", .action = "rows" }, .{ .key = "space", .action = "stage" }, .{ .key = "ctrl+N", .action = "new" }, .{ .key = "alt", .action = "menus" } };
        return ziggui.VStack(.{
            gallery.Card.view(active_theme, "StatusLine while typing", "ziggui.StatusLine", ziggui.VStack(.{
                ziggui.Text("Sent to claude-ziggui.").font(.footnote).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading).padding(6),
                ziggui.StatusLine(&typing),
            }).spacing(0).border(active_theme.colors.separator, 1)),
            gallery.Card.view(active_theme, "StatusLine over a list", "ziggui.StatusLine", ziggui.StatusLine(&listing).border(active_theme.colors.separator, 1)),
        }).spacing(16);
    }

    /// The Presentations section's hover popover: rows whose details open after the pointer
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
            gallery.Card.view(active_theme, "Rest the pointer on a row (HoverPopover over a HoverState)", "ziggui.HoverPopover", Self.leading(ziggui.StackBuilder.fromSlice(.vertical, 0, .leading, rows).frameWidth(240).popoverPassthrough())),
        }).spacing(16);
    }

    /// The Windows section's title-bar card's minimize button: says it was pressed.
    ///
    /// - `self`: the gallery.
    fn minimizeTapped(self: *Self) void {
        self.window_said = "Minimize";
    }

    /// The Windows section's title-bar card's maximize or restore button: says it was pressed.
    ///
    /// - `self`: the gallery.
    fn maximizeTapped(self: *Self) void {
        self.window_said = "Maximize or restore";
    }

    /// The Windows section's title-bar card's close button: says it was pressed.
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
            ziggui.Text(title).font(.headline).frameMaxWidth().frameAlign(.leading),
            ziggui.WrappedText(text).foreground(active_theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.Spacer(),
        }).spacing(6).padding(12).frameMaxWidth().frameMaxHeight();
    }

    /// Pins `view` to the leading edge of a full-width row, in a stack of its
    /// own: for a view whose own frame, padding or ground must stay its own (a
    /// bubble, a fixed-width bar, a card's content). Any other view takes
    /// `.frameMaxWidth().frameAlign(.leading)`, which changes its own frame.
    ///
    /// - `view`: the view to pin.
    /// - Returns: the row.
    fn leading(view: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ view, ziggui.Spacer() }).frameMaxWidth();
    }

    /// Reports whether the Menus & Commands section's bar takes keys now: its panel
    /// shows, and no sheet or alert is presented over it.
    ///
    /// - `self`: the gallery.
    /// - Returns: true when the bar is live.
    fn barLive(self: *const Self) bool {
        return Section.at(self.section.get()) == .menus and !self.presentsModal();
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
    try std.testing.expectEqualStrings("Text", Section.items[0].label);
}

test "a selection past the last row shows the last section" {
    try std.testing.expectEqual(Section.text, Section.at(-1));
    try std.testing.expectEqual(@as(Section, @fromBackingInt(@intCast(Section.items.len - 1))), Section.at(99));
}

test "the sidebar lists the sections by label; each keeps its index" {
    for (1..Section.sorted.len) |row| {
        try std.testing.expect(!std.ascii.lessThanIgnoreCase(Section.sorted[row].label(), Section.sorted[row - 1].label()));
    }
    // With nothing searched, the sidebar's rows are the sections in that order.
    var search = gallery.SectionSearch.init(std.testing.allocator);
    defer search.deinit();
    for (Section.sorted, search.shown()) |section, row| try std.testing.expectEqual(section, row.section);
    // Indices are the enum's, whatever the rows: Text first, Diffs last.
    try std.testing.expectEqual(Section.text, Section.at(0));
    try std.testing.expectEqual(Section.diffs, Section.at(@intCast(Section.items.len - 1)));
    try std.testing.expectEqualStrings("Chat", Section.sorted[0].label());
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

    // They end the Navigation section's page: scrolled to its foot (the
    // first frame clamps the offset), they are drawn.
    shown.section.set(@backingInt(Section.navigation));
    shown.showcase.navigation_scroll.offset = std.math.floatMax(f32);
    const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
    defer allocator.free(rgba);
    try std.testing.expect(shown.columns.total > 0 and shown.columns.resolved(shown.columns.total) > 0);
    try std.testing.expect(shown.rows.total > 0 and shown.rows.resolved(shown.rows.total) > 0);
    try std.testing.expectEqual(ziggui.Axis.vertical, shown.rows.axis);
}

test "the picture zooms under a pinch only while the Images & Drawing section shows" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    try std.testing.expectEqual(null, shown.pictureZoom());
    shown.section.set(@backingInt(Section.images));
    // Tall enough to show the picture card, below the image, chart and markers cards.
    const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = 980, .height = 1200, .theme = shown.theme() });
    defer allocator.free(rgba);
    const zoom = shown.pictureZoom().?;
    const frame = zoom.geometry.frame;
    try std.testing.expect(frame.width > 0);
    // Over the picture a pinch zooms it; beside it, nothing.
    try std.testing.expect(!zoom.pinch(.{ .x = frame.x - 4, .y = frame.y }, 2));
    try std.testing.expect(zoom.pinch(.{ .x = frame.x + frame.width / 2, .y = frame.y + frame.height / 2 }, 2));
    try std.testing.expectApproxEqAbs(@as(f32, 2), zoom.zoom, 1e-5);

    // At the test size the card is scrolled out of sight: never drawn, it takes no pinch.
    shown.showcase.picture_zoom = .{};
    const small = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
    defer allocator.free(small);
    try std.testing.expect(!shown.pictureZoom().?.pinch(.{ .x = gallery.test_width / 2, .y = gallery.test_height / 2 }, 2));
}

test "the panel callbacks fold the tool call and select a row and a hunk" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.toggleTool();
    try std.testing.expect(shown.tool_open);
    shown.toggleThought();
    try std.testing.expect(!shown.thought_open);
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

    shown.section.set(@backingInt(Section.menus));
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

test "the panels that fill the pane are the table, the text editor, navigation and the web view" {
    try std.testing.expect(!Section.controls.fills());
    try std.testing.expect(Section.table.fills() and Section.textEditor.fills() and Section.navigation.fills() and Section.mediaWeb.fills());
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
    for (0..Section.items.len) |index| {
        shown.section.set(@intCast(index));
        const rgba = try ziggui.Screenshot.render(allocator, &shown, Gallery.body, .{ .width = gallery.test_width, .height = gallery.test_height, .theme = shown.theme() });
        defer allocator.free(rgba);
        try std.testing.expectEqual(gallery.test_width * gallery.test_height * 4, rgba.len);
    }
}

/// Draws one headless frame of a gallery, for the tests that need its
/// `body` to have run (`Gallery.track`).
/// The sidebar's rows with nothing searched (`Section.sorted`), for the tests.
const Rows = struct {
    const Self = @This();

    /// The row a section shows on.
    ///
    /// - `section`: the section.
    /// - Returns: its row.
    fn of(section: Section) i64 {
        for (Section.sorted, 0..) |each, index| {
            if (each == section) return @intCast(index);
        }
        unreachable;
    }

    /// The section a row shows.
    ///
    /// - `row`: the row.
    /// - Returns: the section.
    fn at(row: i64) Section {
        return Section.sorted[@intCast(row)];
    }
};

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

    shown.section.set(@backingInt(Section.textEditor));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &shown.editor.document), ziggui.Focus.shared().focused());
    try std.testing.expect(shown.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(shown.editor.show_find.get());

    shown.section.set(@backingInt(Section.chat));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, null), ziggui.Focus.shared().focused());
}

test "Esc takes the expanded video back to its panel, unless an alert is up" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.media.expanded = true;
    shown.showcase.openAlert();
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.escape, 0));
    try std.testing.expect(shown.media.expanded);
    shown.showcase.closeAlert();
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.escape, 0));
    try std.testing.expect(!shown.media.expanded);
}

test "leaving Navigation empties its stack; key-ups and quits reach the Menus & Commands section's card" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.navigation));
    try Frame.draw(&shown);
    try shown.showcase.navigation.push(3);
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(usize, 1), shown.showcase.navigation.depth());
    shown.section.set(@backingInt(Section.presentations));
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

    shown.section.set(@backingInt(Section.menus));
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
    shown.section.set(@backingInt(Section.menus));
    // The held key's repeats, then its release, on the Menus & Commands section.
    _ = shown.keyDown(ziggui.SdlKey.left_alt, ziggui.SdlKey.left_alt_mask);
    _ = shown.keyDown(ziggui.SdlKey.left_alt, ziggui.SdlKey.left_alt_mask);
    shown.keyUp(ziggui.SdlKey.left_alt);
    try std.testing.expect(!shown.menu_bar.isOpen());
}

test "the Editor's shortcuts reach nothing behind a presented sheet, alert or its own dialog" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    shown.section.set(@backingInt(Section.textEditor));
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

test "the arrow keys walk the sidebar's rows, unless a field, the File Browser's list or a modal holds them" {
    const allocator = std.testing.allocator;

    var shown = try Gallery.init(allocator);
    defer shown.deinit();

    // The first row stays the first; ↓ goes to the next row, a modifier does nothing.
    shown.section.set(@backingInt(Rows.at(0)));
    try Frame.draw(&shown);
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.up_arrow, 0));
    try std.testing.expectEqual(@as(i64, 0), Rows.of(Section.at(shown.section.get())));
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(@as(i64, 1), Rows.of(Section.at(shown.section.get())));
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.down_arrow, ziggui.SdlKey.left_shift_mask));
    try std.testing.expectEqual(@as(i64, 1), Rows.of(Section.at(shown.section.get())));

    // The last row stays the last, scrolled into view.
    shown.section.set(@backingInt(Rows.at(@intCast(Section.sorted.len - 1))));
    try Frame.draw(&shown);
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(@as(i64, @intCast(Section.sorted.len - 1)), Rows.of(Section.at(shown.section.get())));

    // Reached by the keys, the Editor leaves them to the sidebar; the next ↓ walks on.
    shown.section.set(@backingInt(Rows.at(Rows.of(.textEditor) - 1)));
    try Frame.draw(&shown);
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try Frame.draw(&shown);
    try std.testing.expectEqual(Section.textEditor, Section.at(shown.section.get()));
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, null), ziggui.Focus.shared().focused());
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(Rows.of(.textEditor) + 1, Rows.of(Section.at(shown.section.get())));

    // A focused field keeps them.
    ziggui.Focus.shared().set(&shown.kit.search);
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    ziggui.Focus.shared().clear();

    // A press on the File Browser's list gives them to it, one beside it does
    // not; a tap on a sidebar row takes them back.
    shown.section.set(@backingInt(Section.files));
    try Frame.draw(&shown);
    const list = &shown.kit.files.scroll;
    shown.pointerDown(.{ .x = list.viewport_x - 20, .y = list.viewport_y + 4 });
    try std.testing.expect(!shown.kit.files_have_keys);
    shown.pointerDown(.{ .x = list.viewport_x + 40, .y = list.viewport_y + 4 });
    try std.testing.expect(shown.kit.files_have_keys);
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(Section.files, Section.at(shown.section.get()));
    shown.sidebarSelection().set(Rows.of(.files));
    try std.testing.expect(!shown.kit.files_have_keys);
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(Rows.of(.files) + 1, Rows.of(Section.at(shown.section.get())));

    // Under a sheet, the Presentations section's or the Settings panel's, the sidebar keeps still.
    shown.settings.show_sheet.set(true);
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(Rows.of(.files) + 1, Rows.of(Section.at(shown.section.get())));
    shown.settings.show_sheet.set(false);
    shown.showcase.openSheet();
    try std.testing.expect(!shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(Rows.of(.files) + 1, Rows.of(Section.at(shown.section.get())));
}

test "every names line a section draws is in its search index" {
    const allocator = std.testing.allocator;
    var shown = try Gallery.init(allocator);
    defer shown.deinit();
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    gallery.CardName.shared().recording = .{ .lines = &lines, .allocator = allocator };
    defer gallery.CardName.shared().recording = null;
    for (0..Section.items.len) |index| {
        const section = Section.at(@intCast(index));
        shown.section.set(@intCast(index));
        lines.clearRetainingCapacity();
        try Frame.draw(&shown);
        try std.testing.expect(lines.items.len > 0);
        for (lines.items) |line| {
            const listed = for (section.names()) |name| {
                if (std.mem.eql(u8, name, line)) break true;
            } else false;
            if (!listed) std.debug.print("{s} draws \"{s}\", missing from Section.names\n", .{ section.label(), line });
            try std.testing.expect(listed);
        }
    }
}

test "typing in the sidebar's search shows the first match and keeps the field's keyboard; Esc ends it" {
    const allocator = std.testing.allocator;
    var shown = try Gallery.init(allocator);
    defer shown.deinit();
    defer ziggui.Focus.shared().clear();
    try Frame.draw(&shown);

    ziggui.Focus.shared().set(&shown.search.field);
    try shown.search.field.setText("webview");
    try Frame.draw(&shown);
    try std.testing.expectEqual(Section.mediaWeb, Section.at(shown.section.get()));
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &shown.search.field), ziggui.Focus.shared().focused());

    // A query matching several: ↓ in the field walks them, the field keeping the keyboard.
    try shown.search.field.setText("ziggui.Toggle");
    try Frame.draw(&shown);
    const rows = shown.search.shown();
    try std.testing.expect(rows.len >= 2);
    try std.testing.expectEqual(rows[0].section, Section.at(shown.section.get()));
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.down_arrow, 0));
    try std.testing.expectEqual(rows[1].section, Section.at(shown.section.get()));
    try Frame.draw(&shown);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &shown.search.field), ziggui.Focus.shared().focused());

    // Esc empties it and lets go of the keyboard; the section found stays.
    const found = Section.at(shown.section.get());
    try std.testing.expect(shown.keyDown(ziggui.SdlKey.escape, 0));
    try Frame.draw(&shown);
    try std.testing.expectEqual(found, Section.at(shown.section.get()));
    try std.testing.expectEqual(Section.sorted.len, shown.search.shown().len);
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, null), ziggui.Focus.shared().focused());
}
