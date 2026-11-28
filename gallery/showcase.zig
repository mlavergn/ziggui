const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_showcase);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The sample colors the shapes, grids and effects panels draw.
const swatches = [_]ziggui.Color{
    ziggui.Color.fromRgb8(255, 99, 71),   ziggui.Color.fromRgb8(255, 165, 0),
    ziggui.Color.fromRgb8(60, 179, 113),  ziggui.Color.fromRgb8(70, 130, 180),
    ziggui.Color.fromRgb8(147, 112, 219), ziggui.Color.fromRgb8(255, 105, 180),
    ziggui.Color.fromRgb8(0, 206, 209),   ziggui.Color.fromRgb8(154, 205, 50),
};

/// The Images & Drawing section's icon grid.
const icon_gallery = [_]ziggui.IconName{
    .house, .search,      .settings,   .user,     .users,    .heart,
    .star,  .bell,        .mail,       .calendar, .clock,    .folder,
    .file,  .image,       .download,   .upload,   .trash,    .edit,
    .copy,  .share,       .lock,       .lockOpen, .eye,      .eyeOff,
    .play,  .pause,       .sun,        .moon,     .sparkles, .zap,
    .cpu,   .shieldCheck, .badgeCheck, .info,     .check,    .send,
};

/// The side, in pixels, of the generated image the Images & Drawing section draws.
const demo_image_side: usize = 64;

/// A 64×64 RGBA gradient built at comptime, so the `Image` component has
/// something to show without shipping an asset.
const demo_image = blk: {
    @setEvalBranchQuota(200000);
    var pixels: [demo_image_side * demo_image_side * 4]u8 = undefined;
    for (0..demo_image_side) |row| {
        for (0..demo_image_side) |column| {
            const at = (row * demo_image_side + column) * 4;
            pixels[at + 0] = @intCast(column * 4);
            pixels[at + 1] = @intCast(row * 4);
            pixels[at + 2] = @intCast(255 - column * 3);
            pixels[at + 3] = 255;
        }
    }
    break :blk pixels;
};

/// The Layout panel's scrolling tab's rows.
const scroll_labels = blk: {
    var labels: [20][]const u8 = undefined;
    for (0..labels.len) |index| labels[index] = std.fmt.comptimePrint("Row {d}", .{index + 1});
    break :blk labels;
};

/// The Layout panel's scroll indicator columns: each visibility and its title.
const indicator_choices = [_]struct { ziggui.ScrollIndicatorVisibility, []const u8 }{
    .{ .automatic, ".automatic" },
    .{ .visible, ".visible" },
    .{ .hidden, ".hidden" },
};

/// The Markers card's markers: each one's place, as fractions of the card's
/// width and height, and its label.
const marker_spots = [_]struct { ziggui.Point, []const u8 }{
    .{ .{ .x = 0.2, .y = 0.6 }, "crosshair" },
    .{ .{ .x = 0.5, .y = 0.6 }, "ring" },
    .{ .{ .x = 0.8, .y = 0.6 }, "ring" },
};

/// How often the Progress indicators card asks for a frame while shown, in
/// milliseconds: the spinner moves a dot each 100.
const progress_frame_ms: u64 = 100;

/// The FlowStack card's tags, of every width.
const flow_tags = [_][]const u8{ "SwiftUI", "Zig", "layout", "wraps into rows", "tags", "chips", "a longer tag than most", "GPU", "macOS", "Windows", "Linux", "themes" };

/// The Table panel's columns: the name and role sharing what the age, from
/// its trailing edge, leaves.
const table_columns = [_]ziggui.TableColumn{
    .{ .title = "Name" },
    .{ .title = "Role" },
    .{ .title = "Age", .width = 64, .trailing = true },
};

/// The Table panel's rows.
const table_rows = [_][]const []const u8{
    &.{ "Ada Lovelace", "Mathematician", "36" },
    &.{ "Alan Turing", "Computer Scientist", "41" },
    &.{ "Grace Hopper", "Rear Admiral", "45" },
    &.{ "Katherine Johnson", "Mathematician", "52" },
    &.{ "Margaret Hamilton", "Engineer", "33" },
};

/// The Toggles card's checkbox rows: each explicit `CheckboxStyle`, its row's
/// title, the color its checkboxes are given with `.foregroundStyle()`, if any,
/// and the off and on checkboxes' labels.
const checkbox_styles = [_]struct { style: ziggui.CheckboxStyle, title: []const u8, tint: ?ziggui.Color, labels: [2][]const u8 = .{ "", "" } }{
    .{ .style = .rounded, .title = "Rounded", .tint = null },
    .{ .style = .square, .title = "Square", .tint = ziggui.Color.hex(0xDD4466) },
    .{ .style = .circular, .title = "Circular", .tint = null },
    .{ .style = .compact, .title = "Compact", .tint = null, .labels = .{ "Wrap", "Ignore whitespace" } },
};

/// The Controls panel's radio group's options.
const radio_options = [_][]const u8{ "Automatic", "On", "Off" };

/// The split view card's sidebar: mail folders, each with an icon.
const mail_items = [_]ziggui.SidebarItem{
    .{ .label = "Inbox", .icon = .inbox, .detail = "3" },
    .{ .label = "Drafts", .icon = .fileText },
    .{ .label = "Sent", .icon = .send },
    .{ .label = "Archive", .icon = .archive },
};

/// The Table section's filtered table's columns, each with a filter field
/// under its title: the name and role sharing what the year leaves.
const people_columns = [_]ziggui.TableColumn{
    .{ .title = "Name", .min_width = 120 },
    .{ .title = "Role", .min_width = 100 },
    .{ .title = "Born", .width = 80, .trailing = true },
};

/// The Table section's filtered table's rows.
const people_rows = [_][]const []const u8{
    &.{ "Ada Lovelace", "Mathematician", "1815" },
    &.{ "Alan Turing", "Computer Scientist", "1912" },
    &.{ "Grace Hopper", "Computer Scientist", "1906" },
    &.{ "Katherine Johnson", "Mathematician", "1918" },
    &.{ "Margaret Hamilton", "Engineer", "1936" },
    &.{ "Edsger Dijkstra", "Computer Scientist", "1930" },
    &.{ "Barbara Liskov", "Computer Scientist", "1939" },
    &.{ "Donald Knuth", "Computer Scientist", "1938" },
    &.{ "Frances Allen", "Computer Scientist", "1932" },
    &.{ "John von Neumann", "Mathematician", "1903" },
    &.{ "Dennis Ritchie", "Computer Scientist", "1941" },
    &.{ "Radia Perlman", "Engineer", "1951" },
};

/// Every row of `people_rows` by position, in order: the filtered table's
/// rows before a filter is typed.
const every_person = positions: {
    var all: [people_rows.len]usize = undefined;
    for (&all, 0..) |*position, index| position.* = index;
    break :positions all;
};

/// The Table section's fitted tables' columns: the name sharing what the
/// kind and size leave, the size from its trailing edge.
const plain_columns = [_]ziggui.TableColumn{
    .{ .title = "Name" },
    .{ .title = "Kind", .width = 90 },
    .{ .title = "Size", .width = 70, .trailing = true },
};

/// The Table section's fitted tables' rows: each row's cells, as text.
const plain_rows = [_][]const []const u8{
    &.{ "build.zig", "Zig", "12 KB" },
    &.{ "README.md", "Markdown", "8 KB" },
    &.{ "LICENSE", "Text", "1 KB" },
};

/// The Navigation panel's inset split view's chats.
const chat_items = [_]ziggui.SidebarItem{
    .{ .label = "New Chat", .detail = "just now" },
    .{ .label = "what does this app do", .detail = "4h ago" },
    .{ .label = "GPU renderer plan", .detail = "Yesterday" },
};

/// A row of the Navigation panel's stack: its title, its icon and the route it pushes.
const NavigationEntry = struct {
    const Self = @This();

    /// The row's title, and the pushed view's.
    title: []const u8,

    /// The row's leading symbol.
    icon: ziggui.IconName,

    /// The route the row pushes.
    route: i64,
};

/// The Navigation panel's first level: folders, routes 1 to 3.
const navigation_folders = [_]NavigationEntry{
    .{ .title = "Inbox", .icon = .inbox, .route = 1 },
    .{ .title = "Archive", .icon = .archive, .route = 2 },
    .{ .title = "Trash", .icon = .trash2, .route = 3 },
};

/// The Navigation panel's second level, the same in every folder: messages,
/// routes `folder * 10 + 1` to `folder * 10 + 3`.
const navigation_messages = [_]NavigationEntry{
    .{ .title = "Welcome to ziggui", .icon = .mail, .route = 1 },
    .{ .title = "Build passed", .icon = .mail, .route = 2 },
    .{ .title = "Weekly notes", .icon = .mail, .route = 3 },
};

/// The panels folded in from zigui's showcase: controls, text and icons,
/// shapes and media, layout, a table, a text editor, overlays, effects, a
/// navigation stack and a geometry reader, with the state they bind to.
///
/// The gallery owns one and draws a panel per section; the sheet, the alert
/// and the quit question are presented over the whole window
/// (`presentations`).
pub const Showcase = struct {
    const Self = @This();

    /// The time the Canvas card's clock shows, in seconds past twelve: 10:09:30,
    /// fixed, so every screenshot is the same.
    const clock_seconds: f32 = (10 * 60 + 9) * 60 + 30;
    /// The Canvas card's clock numerals and where each sits, in twelfths of a turn.
    const clock_numerals = [_]struct { []const u8, f32 }{ .{ "12", 0 }, .{ "3", 3 }, .{ "6", 6 }, .{ "9", 9 } };

    /// The Picture card's picture width, in pixels.
    const picture_width = 2048;
    /// The Picture card's picture height, in pixels.
    const picture_height = 1536;
    /// How many segments the Picture card keeps before the oldest gives way.
    const picture_segment_capacity = 8;
    /// How near, on screen, a press must be to a segment's end to take it, in points.
    const picture_grab_reach: f32 = 12;
    /// How far, in points, a press on the Picture card may pan before it is
    /// a pan rather than a click toward a segment.
    const picture_click_slop: f32 = 4;

    /// Allocates the state the panels bind to.
    allocator: std.mem.Allocator,

    /// The window the title bar demo's buttons and the animation reach; empty headless.
    platform: gallery.Platform = .{},

    // Navigation

    /// The Navigation panel's root page's scroll position: the page is taller
    /// than the pane, and the panel fills the pane rather than the gallery scrolling it.
    navigation_scroll: ziggui.ScrollState = .{},

    /// The Navigation panel's route stack.
    navigation: ziggui.NavigationPath,

    /// The Navigation panel's inset split view's selected chat.
    chat_selection: ziggui.State(i64),
    /// The split view card's selected sidebar row.
    mail_selection: ziggui.State(i64),
    /// Whether the context menu card's menu is open.
    context_open: ziggui.State(bool),
    /// The cell mode card's table: its cursor cell and widths.
    cell_table: ziggui.TableState,
    /// The filtered table: its scroll, widths and selection.
    people_table: ziggui.TableState,
    /// The filtered table's filter fields, one under each column's title.
    people_filters: [people_columns.len]ziggui.TextFieldState,
    /// Each filter field's revision when the rows shown were last chosen.
    people_revisions: [people_columns.len]u64 = @splat(0),
    /// The filtered table's rows, as positions in `people_rows`: the first
    /// `people_shown_count` of them, every row in order until a filter is typed.
    people_shown: [people_rows.len]usize = every_person,
    /// How many of `people_shown` the filters keep.
    people_shown_count: usize = people_rows.len,
    /// The highlighted table's current match, a row of `plain_rows`.
    match_row: usize = 0,

    // Controls

    /// The Controls panel's Wi‑Fi toggle.
    wifi: ziggui.State(bool),

    /// The Controls panel's Notifications toggle.
    notifications: ziggui.State(bool),

    /// The Toggles card's checkboxes, an off and an on one for each explicit
    /// `CheckboxStyle` in `checkbox_styles`' order.
    checkboxes: [2 * checkbox_styles.len]ziggui.State(bool),

    /// The Toggles card's labeled checkbox.
    remember: ziggui.State(bool),

    /// The Controls panel's slider, and the progress bar under it.
    slider: ziggui.State(f32),
    /// The Controls panel's stepped slider (`.sliderStep`).
    stepped_slider: ziggui.State(f32),
    /// Whether a press is changing the stepped slider (`.onEditingChanged`).
    stepped_editing: ziggui.State(bool),

    /// The Controls panel's stepper.
    stepper: ziggui.State(i64),

    /// The Controls panel's radio group.
    radio: ziggui.State(i64),

    /// The Controls panel's text field.
    name: ziggui.TextFieldState,
    /// The secure field card's password.
    password: ziggui.TextFieldState,

    // Layout and table

    /// The Layout panel's selected tab.
    tab: ziggui.State(i64),

    /// The Table panel's table: its scroll, widths and selection.
    table: ziggui.TableState,

    // Effects and overlays

    /// The Effects panel's animated progress.
    progress: ziggui.State(f32),

    /// Whether the sheet is presented.
    show_sheet: ziggui.State(bool),

    /// Whether the alert is presented.
    show_alert: ziggui.State(bool),

    /// Whether the Presentations section's popover is presented.
    show_popover: ziggui.State(bool),

    /// Whether the Presentations section's Options menu is open.
    menu_open: ziggui.State(bool),

    /// Whether the pointer is over the Presentations section's `onHover` box.
    hovering: ziggui.State(bool),

    /// Whether the Presentations section's passthrough popover is presented.
    show_pass_popover: ziggui.State(bool),

    /// The taps the passthrough button took.
    pass_taps: ziggui.State(i64),

    /// The last key-up's SDL keycode, 0 before the first.
    last_key_up: ziggui.State(i64),

    /// Whether a quit asks first (the quit handler demo).
    ask_quit: ziggui.State(bool),

    /// Whether the quit question is presented.
    show_quit: ziggui.State(bool),

    /// The Picture card's 2048 × 1536 test pattern, RGBA8.
    picture_pixels: []u8 = &.{},
    /// The Picture card's zoom and pan.
    picture_zoom: ziggui.ZoomState = .{},
    /// The Picture card's "Reverse ↕" toggle: `picture_zoom.invert_scroll_y`, set from it each frame.
    picture_invert_y: ziggui.State(bool),
    /// The Picture card's "Reverse ↔" toggle: `picture_zoom.invert_scroll_x`, set from it each frame.
    picture_invert_x: ziggui.State(bool),
    /// The Picture card's "Grid" toggle: whether the pattern shows its grid.
    picture_grid: ziggui.State(bool),
    /// Whether `picture_pixels` were last painted with the grid.
    picture_grid_painted: bool = true,
    /// The picture's pixels' generation, bumped as they are painted again, so its texture uploads afresh.
    picture_generation: u64 = 1,
    /// The Picture card's marking up: a segment's first click, the end a press holds.
    picture_annotation: ziggui.AnnotationState = .{},
    /// The Picture card's segments, in picture pixels; the first `picture_segment_count` are drawn.
    picture_segments: [picture_segment_capacity]ziggui.AnnotationSegment = @splat(.{ .start = .{ .x = 256, .y = 1280 }, .end = .{ .x = 896, .y = 1024 } }),
    /// How many segments the Picture card holds.
    picture_segment_count: usize = 1,
    /// Where the Picture card's press landed, in picture pixels, while it can
    /// still be a click toward a segment: it clicks on release, unless its
    /// drag panned past `picture_click_slop` first.
    picture_press: ?ziggui.Point = null,
    /// How far the Picture card's press has panned, in points.
    picture_press_travel: f32 = 0,
    /// Where the segment end a press holds would be, in picture pixels, had
    /// it no edge: the end is kept on the picture, and follows the pointer
    /// back from beyond it.
    picture_drag_point: ziggui.Point = .{ .x = 0, .y = 0 },

    /// The Layout panel's scroll indicator columns' scroll positions, one per
    /// `indicator_choices`.
    indicator_scrolls: [indicator_choices.len]ziggui.ScrollState = @splat(.{}),

    /// The sheet's list's scroll position.
    sheet_scroll: ziggui.ScrollState = .{},
    /// The scroll views card's vertical list, its position the app's.
    kept_scroll: ziggui.ScrollState = .{},
    /// The scroll views card's grid, scrolled both ways.
    both_scroll: ziggui.ScrollState = .{},

    /// Constructs the panels' state as the showcase opened.
    ///
    /// - `allocator`: allocator for the state; must outlive the showcase.
    /// - Returns: the showcase; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var self = Self{
            .allocator = allocator,
            .navigation = ziggui.NavigationPath.init(allocator),
            .chat_selection = ziggui.State(i64).init(allocator, 0),
            .table = ziggui.TableState.init(allocator),
            .mail_selection = ziggui.State(i64).init(allocator, 0),
            .context_open = ziggui.State(bool).init(allocator, false),
            .cell_table = ziggui.TableState.init(allocator),
            .people_table = ziggui.TableState.init(allocator),
            .people_filters = .{ ziggui.TextFieldState.init(allocator), ziggui.TextFieldState.init(allocator), ziggui.TextFieldState.init(allocator) },
            .wifi = ziggui.State(bool).init(allocator, true),
            .notifications = ziggui.State(bool).init(allocator, false),
            .checkboxes = .{
                ziggui.State(bool).init(allocator, false), ziggui.State(bool).init(allocator, true),
                ziggui.State(bool).init(allocator, false), ziggui.State(bool).init(allocator, true),
                ziggui.State(bool).init(allocator, false), ziggui.State(bool).init(allocator, true),
                ziggui.State(bool).init(allocator, false), ziggui.State(bool).init(allocator, true),
            },
            .remember = ziggui.State(bool).init(allocator, true),
            .picture_invert_y = ziggui.State(bool).init(allocator, false),
            .picture_invert_x = ziggui.State(bool).init(allocator, false),
            .picture_grid = ziggui.State(bool).init(allocator, true),
            .slider = ziggui.State(f32).init(allocator, 0.5),
            .stepped_slider = ziggui.State(f32).init(allocator, 50),
            .stepped_editing = ziggui.State(bool).init(allocator, false),
            .stepper = ziggui.State(i64).init(allocator, 2),
            .radio = ziggui.State(i64).init(allocator, 0),
            .name = ziggui.TextFieldState.init(allocator),
            .password = ziggui.TextFieldState.init(allocator),
            .tab = ziggui.State(i64).init(allocator, 0),
            .progress = ziggui.State(f32).init(allocator, 0.3),
            .show_sheet = ziggui.State(bool).init(allocator, false),
            .show_alert = ziggui.State(bool).init(allocator, false),
            .show_popover = ziggui.State(bool).init(allocator, false),
            .menu_open = ziggui.State(bool).init(allocator, false),
            .hovering = ziggui.State(bool).init(allocator, false),
            .show_pass_popover = ziggui.State(bool).init(allocator, false),
            .pass_taps = ziggui.State(i64).init(allocator, 0),
            .last_key_up = ziggui.State(i64).init(allocator, 0),
            .ask_quit = ziggui.State(bool).init(allocator, false),
            .show_quit = ziggui.State(bool).init(allocator, false),
        };
        errdefer self.deinit();
        self.picture_pixels = try allocator.alloc(u8, picture_width * picture_height * 4);
        Self.paintPattern(self.picture_pixels, true);
        // The first row selected, and in the cell mode card a cell, shown as
        // the cursor while that table has the keyboard.
        self.table.select(0);
        self.cell_table.selectCell(.{ .row = 1, .column = 1 });
        self.cell_table.focused = true;
        return self;
    }

    /// Releases the panels' state, and the keyboard focus if one of its fields holds it.
    ///
    /// - `self`: the showcase to tear down.
    pub fn deinit(self: *Self) void {
        if (ziggui.Focus.shared().focused()) |field| {
            if (field == &self.name) ziggui.Focus.shared().clear();
        }
        self.allocator.free(self.picture_pixels);
        self.show_quit.deinit();
        self.ask_quit.deinit();
        self.last_key_up.deinit();
        self.pass_taps.deinit();
        self.show_pass_popover.deinit();
        self.hovering.deinit();
        self.menu_open.deinit();
        self.show_popover.deinit();
        self.show_alert.deinit();
        self.show_sheet.deinit();
        self.progress.deinit();
        self.tab.deinit();
        self.password.deinit();
        self.name.deinit();
        self.radio.deinit();
        self.stepper.deinit();
        self.stepped_editing.deinit();
        self.stepped_slider.deinit();
        self.slider.deinit();
        self.remember.deinit();
        self.picture_grid.deinit();
        self.picture_invert_x.deinit();
        self.picture_invert_y.deinit();
        for (&self.checkboxes) |*checkbox| checkbox.deinit();
        self.notifications.deinit();
        self.wifi.deinit();
        self.chat_selection.deinit();
        self.table.deinit();
        self.mail_selection.deinit();
        self.context_open.deinit();
        self.cell_table.deinit();
        self.people_table.deinit();
        for (&self.people_filters) |*field| field.deinit();
        self.navigation.deinit();
    }

    /// Presents the sheet, the alert and the quit question over `content`,
    /// the window's root, while their states say so.
    ///
    /// - `self`: the showcase.
    /// - `content`: the window's root view.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: `content` with the three presentations attached.
    pub fn presentations(self: *Self, content: ziggui.View, theme: ziggui.Theme) ziggui.View {
        const sheet = ziggui.VStack(.{
            ziggui.Text("Sheet").font(.title),
            ziggui.WrappedText("A centered window-modal sheet over a dimming scrim. Tap outside or Done to dismiss."),
            ziggui.WrappedText("The wheel over the sheet scrolls only its list, never the page it covers.")
                .font(.footnote).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.ScrollViewState(&self.sheet_scroll, ziggui.VStack(.{
                ziggui.ForEach(&scroll_labels, Self.scrollRow),
            }).spacing(6).padding(8)).scrollIndicators(.visible).frameMaxWidth().frameHeight(90).background(theme.colors.secondary_background).cornerRadius(6),
            ziggui.HStack(.{
                ziggui.Spacer(),
                ziggui.ButtonRoled("Done", .prominent, ziggui.Callback.init(Self, self, Self.closeSheet)),
            }).frameMaxWidth(),
        }).spacing(12).padding(20).frameWidth(380);

        const quit = ziggui.VStack(.{
            ziggui.Text("Quit the gallery?").font(.headline),
            ziggui.WrappedText("The quit handler refused the quit and asked instead."),
            ziggui.HStack(.{
                ziggui.Spacer(),
                ziggui.Button("Cancel", ziggui.Callback.init(Self, self, Self.cancelQuit)),
                ziggui.ButtonRoled("Quit", .destructive, ziggui.Callback.init(Self, self, Self.confirmQuit)),
            }).spacing(8),
        }).spacing(12).padding(20).frameWidth(300);

        const alert = ziggui.VStack(.{
            ziggui.Icon(.info, 28, theme.colors.accent),
            ziggui.Text("Heads up").font(.headline),
            ziggui.WrappedText("A centered alert. Long unbreakable tokens wrap too: " ++
                "/Users/david/models/unsloth/FLUX.2-klein-4B-GGUF.safetensors"),
            ziggui.ButtonRoled("OK", .prominent, ziggui.Callback.init(Self, self, Self.closeAlert)).frameMaxWidth(),
        }).spacing(12).padding(20).frameWidth(300);

        return content
            .sheet(self.show_sheet.binding(), sheet)
            .alert(self.show_alert.binding(), alert)
            .alert(self.show_quit.binding(), quit);
    }

    /// The Buttons card: every role, disabled, and icon buttons.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn buttonsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        return gallery.Card.view(theme, "Buttons", "ziggui.Button · ziggui.ButtonRoled · ziggui.IconButton · ziggui.ButtonIcon · ziggui.ButtonIconRoled", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.ButtonRoled("Primary", .prominent, ziggui.Callback.init(Self, self, Self.animate)),
                ziggui.Button("Glass", ignore),
                ziggui.ButtonRoled("Delete", .destructive, ignore),
                ziggui.ButtonRoled("Plain", .plain, ignore),
                ziggui.Spacer(),
            }).spacing(10),
            ziggui.HStack(.{
                ziggui.Button("Disabled", ignore).disabled(true),
                ziggui.IconButton(.heart, 18, ignore),
                ziggui.IconButton(.trash, 18, ignore),
                ziggui.Spacer(),
            }).spacing(10),
            ziggui.HStack(.{
                ziggui.ButtonIcon("Share", .share, ignore),
                ziggui.ButtonIconRoled("Download", .download, .prominent, ignore),
                ziggui.ButtonIconRoled("Remove", .trash, .destructive, ignore),
                ziggui.Spacer(),
            }).spacing(10),
        }).spacing(10));
    }

    /// The Toggles card: two switches in rows, then a row of checkboxes per
    /// explicit `CheckboxStyle`, one off and one on, the square ones tinted
    /// with their own `.foregroundStyle()` and the compact ones labeled, and a
    /// labeled circular one.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn togglesCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Toggles", "ziggui.Toggle · .toggleStyle(.checkbox) · .checkboxStyle(.rounded) · .square · .circular · .compact", ziggui.VStack(.{
            Self.row("Wi‑Fi", ziggui.Toggle("", self.wifi.binding())),
            ziggui.Divider(),
            Self.row("Notifications", ziggui.Toggle("", self.notifications.binding())),
            ziggui.Divider(),
            ziggui.VStack(.{ self.checkboxRow(0), self.checkboxRow(1), self.checkboxRow(2), self.checkboxRow(3) }).spacing(10),
            ziggui.Toggle("Remember this choice", self.remember.binding()).toggleStyle(.checkbox).checkboxStyle(.circular).frameMaxWidth().frameAlign(.leading),
        }).spacing(8));
    }

    /// One of the Toggles card's checkbox rows: the style's title, then its
    /// off and on checkboxes, given the style's tint if it has one and its
    /// labels.
    ///
    /// - `self`: the showcase.
    /// - `index`: the row, an index into `checkbox_styles`.
    /// - Returns: the row.
    fn checkboxRow(self: *Self, index: usize) ziggui.View {
        const style = checkbox_styles[index];
        var pair: [2]ziggui.View = undefined;
        for (&pair, 0..) |*checkbox, column| {
            checkbox.* = ziggui.Toggle(style.labels[column], self.checkboxes[2 * index + column].binding());
            if (style.tint) |tint| checkbox.* = checkbox.foregroundStyle(tint);
        }
        return Self.row(style.title, ziggui.HStack(.{ pair[0], pair[1] }).spacing(14).toggleStyle(.checkbox).checkboxStyle(style.style));
    }

    /// The Slider card: a slider and the progress bar it drives, then a
    /// slider landing on steps of 10 that says while a press changes it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn sliderCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const editing = if (self.stepped_editing.get()) "editing" else "let go";
        const stepped = allocator.print("{d:.0} ({s})", .{ self.stepped_slider.get(), editing }) catch @panic("oom");
        return gallery.Card.view(theme, "Slider & Progress", "ziggui.Slider · .sliderStep · .onEditingChanged · ziggui.ProgressView", ziggui.VStack(.{
            ziggui.Slider(self.slider.binding(), 0, 1).frameMaxWidth(),
            ziggui.ProgressView(self.slider.get()).frameMaxWidth(),
            ziggui.HStack(.{
                ziggui.Slider(self.stepped_slider.binding(), 0, 100).sliderStep(10).onEditingChanged(self.stepped_editing.binding()).frameMaxWidth(),
                ziggui.Text(stepped).monospaced().foregroundStyle(theme.colors.secondary_label).frameWidth(110).frameAlign(.leading),
            }).spacing(12),
        }).spacing(12));
    }

    /// The Progress indicators card: a spinner and loading dots, turning with
    /// the frame clock, which they ask frames of while shown.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn progressCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const clock = ziggui.FrameClock.shared();
        const now = clock.time();
        clock.requestFrameAt(now + progress_frame_ms);
        return gallery.Card.view(theme, "Progress indicators", "ziggui.Spinner · ziggui.LoadingDots", ziggui.HStack(.{
            ziggui.Spinner(now, 18, theme.colors.secondary_label),
            ziggui.Text("Spinner").foregroundStyle(theme.colors.secondary_label),
            ziggui.LoadingDots(now, theme.colors.accent),
            ziggui.Text("LoadingDots").foregroundStyle(theme.colors.secondary_label),
            ziggui.Spacer(),
        }).spacing(10));
    }

    /// The FlowStack card: tags of every width wrapping into rows as the card
    /// narrows.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn flowStackCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const tags = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, flow_tags.len) catch @panic("oom");
        for (flow_tags, tags) |tag, *view| {
            view.* = ziggui.HStack(.{ziggui.Text(tag).font(.subheadline)})
                .paddingInsets(.{ .top = 3, .leading = 8, .bottom = 3, .trailing = 8 })
                .background(theme.colors.quaternary_fill)
                .cornerRadius(theme.metrics.radius(10));
        }
        return gallery.Card.view(theme, "FlowStack: tags wrapping into rows as the card narrows", "ziggui.FlowStack", ziggui.FlowStack(tags).spacing(6).frameMaxWidth().frameAlign(.leading));
    }

    /// The Stepper card: a stepper in a row.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn stepperCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Stepper", "ziggui.Stepper", Self.row("Quantity", ziggui.Stepper("", self.stepper.binding(), 0, 10, 1)));
    }

    /// The Radio group card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn radioGroupCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Radio group", "ziggui.RadioGroup", ziggui.RadioGroup(self.radio.binding(), &radio_options));
    }

    /// The Text field card: a field with its right-click menu.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn textFieldCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Text field", "ziggui.TextField", ziggui.VStack(.{
            ziggui.TextField("Type your name…", &self.name).frameHeight(36).cornerRadius(8).frameMaxWidth(),
            ziggui.Text("Right-click for Cut / Copy / Paste / Select All.")
                .font(.footnote).foregroundStyle(theme.colors.secondary_label),
        }).spacing(8));
    }

    /// The Secure field card: a password's field, a dot per character.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn secureFieldCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Secure field", "ziggui.SecureField", ziggui.VStack(.{
            ziggui.SecureField("Password", &self.password).frameHeight(36).cornerRadius(8).frameMaxWidth(),
            ziggui.Text("Shows a dot per character; its text is never copied, cut or read out.")
                .font(.footnote).foregroundStyle(theme.colors.secondary_label),
        }).spacing(8));
    }

    /// The Type scale card: every text style.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn typeScaleCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Type scale", "ziggui.Text", ziggui.VStack(.{
            ziggui.Text("Large Title").font(.largeTitle).frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Title").font(.title).frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Headline").font(.headline).frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Body — the quick brown fox.").font(.body).frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Footnote").font(.footnote).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(6));
    }

    /// The Wrapped paragraph card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn wrappedTextCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Wrapped paragraph", "ziggui.WrappedText", ziggui.WrappedText(
            "WrappedText word-wraps to the width it is given, growing taller as the " ++
                "column narrows. Reach for it for paragraphs, descriptions, captions.",
        ).foregroundStyle(theme.colors.label));
    }

    /// The Search results card: matches marked, the last cut by a narrow cell.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn highlightedTextCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Search results, matches marked (the last cut by a narrow cell)", "ziggui.HighlightedText · ziggui.TextRange", ziggui.VStack(.{
            ziggui.HStack(.{ ziggui.HighlightedText("FindBar: the find bar under Command-F", &.{ .{ .start = 0, .end = 4 }, .{ .start = 13, .end = 17 } }, .medium), ziggui.Spacer() }),
            ziggui.HStack(.{ ziggui.HighlightedText("FindCount says where a find stands", &.{ .{ .start = 0, .end = 4 }, .{ .start = 23, .end = 27 } }, null), ziggui.Spacer() }),
            ziggui.HStack(.{
                ziggui.HStack(.{ ziggui.HighlightedText("FindActions: the keys a find bar takes", &.{ .{ .start = 0, .end = 4 }, .{ .start = 24, .end = 28 } }, null), ziggui.Spacer() })
                    .frameWidth(160)
                    .border(theme.colors.separator, 1),
                ziggui.Spacer(),
            }),
        }).spacing(8));
    }

    /// The Label card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn labelCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Label", "ziggui.Label", ziggui.Label("Tagged item", theme.colors.accent).frameMaxWidth().frameAlign(.leading));
    }

    /// The RichText card: one paragraph of styled spans (bold, italic, mono,
    /// struck, an underlined accent), the same with its lines spaced wider,
    /// and preformatted code that keeps its line breaks.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn richTextCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const spans = ziggui.BuildScope.shared().allocator().dupe(ziggui.Span, &.{
            .{ .text = "Rich text mixes " },
            .{ .text = "bold", .weight = .bold },
            .{ .text = ", " },
            .{ .text = "italic", .italic = true },
            .{ .text = ", " },
            .{ .text = "mono", .mono = true },
            .{ .text = ", " },
            .{ .text = "struck", .strike = true },
            .{ .text = " and " },
            .{ .text = "accented", .color = theme.colors.accent, .underline = true },
            .{ .text = " runs in one paragraph that wraps to its width." },
        }) catch @panic("oom");
        const code = ziggui.BuildScope.shared().allocator().dupe(ziggui.Span, &.{
            .{ .text = "const answer = 42;\n", .mono = true },
            .{ .text = "// kept as typed, line by line", .mono = true, .color = theme.colors.secondary_label },
        }) catch @panic("oom");
        return gallery.Card.view(theme, "RichText: styled spans, wider line spacing, preformatted", "ziggui.RichText · ziggui.RichTextSpaced · ziggui.RichTextPreformatted", ziggui.VStack(.{
            // Narrow enough to wrap, so the spaced lines show their spacing.
            ziggui.RichText(spans).frameWidth(380),
            ziggui.RichTextSpaced(spans, 1.6).frameWidth(380),
            ziggui.RichTextPreformatted(code, 1.2).frameMaxWidth().frameAlign(.leading),
        }).spacing(12).alignment(.leading));
    }

    /// The scroll views card: a list whose position the app keeps, a grid
    /// that scrolls both ways, and a list held at a fixed offset.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn scrollViewsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ground = theme.colors.secondary_background;
        const grid = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, 6) catch @panic("oom");
        for (grid) |*grid_row| grid_row.* = ziggui.HStack(.{ziggui.ForEach(&swatches, Self.gridSwatch)}).spacing(8);
        return gallery.Card.view(theme, "Scroll views: its own position, the app's, both ways, a fixed offset", "ziggui.ScrollView · ziggui.ScrollViewState · ziggui.ScrollViewStateBoth · ziggui.ScrollViewOffset", ziggui.HStack(.{
            ziggui.ScrollView(ziggui.VStack(.{ziggui.ForEach(&scroll_labels, Self.scrollRow)}).spacing(6).padding(8))
                .frameMaxWidth().frameHeight(110).background(ground).cornerRadius(6),
            ziggui.ScrollViewState(&self.kept_scroll, ziggui.VStack(.{ziggui.ForEach(&scroll_labels, Self.scrollRow)}).spacing(6).padding(8))
                .frameMaxWidth().frameHeight(110).background(ground).cornerRadius(6),
            ziggui.ScrollViewStateBoth(&self.both_scroll, ziggui.StackBuilder.fromSlice(.vertical, 8, .leading, grid).padding(8))
                .frameMaxWidth().frameHeight(110).background(ground).cornerRadius(6),
            ziggui.ScrollViewOffset(.vertical, 60, ziggui.VStack(.{ziggui.ForEach(&scroll_labels, Self.scrollRow)}).spacing(6).padding(8))
                .frameMaxWidth().frameHeight(110).background(ground).cornerRadius(6),
        }).spacing(12));
    }

    /// The Icon gallery card: a grid of Lucide icons.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn iconGalleryCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Icon gallery", "ziggui.Icon · ziggui.LazyVGrid", ziggui.LazyVGrid(6, 10, &icon_gallery, Self.iconCell).frameMaxWidth());
    }

    /// The Shapes card: each primitive shape.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn shapesCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Primitives", "ziggui.Rectangle · ziggui.RoundedRectangle · ziggui.Circle · ziggui.Capsule · ziggui.Ellipse", ziggui.HStack(.{
            ziggui.Rectangle(swatches[3]).frame(56, 56),
            ziggui.RoundedRectangle(swatches[2], 12).frame(56, 56),
            ziggui.Circle(swatches[0]).frame(56, 56),
            ziggui.Capsule(swatches[4]).frame(80, 36),
            ziggui.Ellipse(swatches[6]).frame(80, 56),
            ziggui.Spacer(),
        }).spacing(12));
    }

    /// The LinearGradient card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn gradientCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "LinearGradient", "ziggui.LinearGradient", ziggui.LinearGradient(
            swatches[5],
            swatches[1],
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
        ).frameMaxWidth().frameHeight(90).cornerRadius(12));
    }

    /// The Dividers card: across and down.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn dividersCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Dividers", "ziggui.Divider · ziggui.VDivider", ziggui.VStack(.{
            ziggui.Text("above").frameMaxWidth().frameAlign(.leading),
            ziggui.Divider(),
            ziggui.HStack(.{
                ziggui.Text("left"),
                ziggui.VDivider().frameHeight(20),
                ziggui.Text("right"),
                ziggui.Spacer(),
            }).spacing(12),
        }).spacing(8));
    }

    /// The Material card: a frosted ground over a gradient.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn materialCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Material (frosted over gradient)", ".backgroundMaterial(.regular)", ziggui.ZStack(.{
            ziggui.LinearGradient(theme.colors.accent, swatches[5], .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 })
                .frameMaxWidth().frameHeight(120),
            ziggui.Text("Regular material").font(.headline)
                .padding(16).backgroundMaterial(.regular).cornerRadius(12),
        }));
    }

    /// The stacks card: an HStack with a Spacer, one whose MinSpacer keeps a
    /// least gap, a ForEach's rows with an Empty among them, and a ZStack,
    /// all in a VStack.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn stacksCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Stacks: HStack, VStack, ZStack, Spacer, MinSpacer, ForEach, Empty", "ziggui.HStack · ziggui.VStack · ziggui.ZStack · ziggui.Spacer · ziggui.MinSpacer · ziggui.ForEach · ziggui.Empty", ziggui.VStack(.{
            ziggui.HStack(.{ ziggui.Text("leading"), ziggui.Spacer(), ziggui.Text("trailing") }).frameMaxWidth(),
            ziggui.HStack(.{ ziggui.Text("MinSpacer"), ziggui.MinSpacer(48), ziggui.Text("keeps 48 pt at least"), ziggui.Spacer() }).spacing(0).frameMaxWidth(),
            ziggui.HStack(.{
                ziggui.ForEach(scroll_labels[0..3], Self.scrollRow),
                // An `Empty` stands in for a view not shown, taking no room.
                ziggui.Empty(),
            }).frameMaxWidth(),
            ziggui.ZStack(.{
                ziggui.RoundedRectangle(swatches[7], 10).frameMaxWidth().frameHeight(60),
                ziggui.Text("ZStack overlay").foregroundStyle(ziggui.Color.white).font(.headline),
            }),
        }).spacing(10));
    }

    /// The LazyVGrid card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn verticalGridCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "LazyVGrid", "ziggui.LazyVGrid", ziggui.LazyVGrid(4, 8, &swatches, Self.swatchCell).frameMaxWidth());
    }

    /// The LazyHGrid card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn horizontalGridCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "LazyHGrid", "ziggui.LazyHGrid", ziggui.LazyHGrid(2, 8, &swatches, Self.swatchCell).frameHeight(96));
    }

    /// The TabView card: a scrolling tab and an info tab.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn tabViewCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const tabs = [_]ziggui.Tab{
            .{ .label = "Scroll", .content = ziggui.ScrollView(ziggui.VStack(.{
                ziggui.ForEach(&scroll_labels, Self.scrollRow),
            }).spacing(6).padding(8)) },
            .{ .label = "Info", .content = ziggui.WrappedText(
                "TabView reuses Picker for its bar; the body switches on the bound " ++
                    "selection. The first tab nests a ScrollView with 20 rows, which keeps its own position.",
            ).padding(12) },
        };
        return gallery.Card.view(theme, "TabView", "ziggui.TabView", ziggui.TabView(self.tab.binding(), &tabs).frameMaxWidth().frameHeight(170));
    }

    /// The Scroll indicators card: one column per visibility.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn scrollIndicatorsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Scroll indicators: shown after a scroll, kept up while it overflows, never drawn", ".scrollIndicators · ziggui.ScrollIndicatorVisibility", self.indicatorColumns(theme));
    }

    /// The Table section's first card: rows of text, selected with a tap or
    /// the arrows, a column's edge dragged to resize it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn tableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const table = ziggui.TableRows.table(&table_rows, &table_columns, &self.table, .{});
        return gallery.Card.view(theme, "Rows of text: a tap or the arrows select, a column's edge drags to resize", "ziggui.Table · ziggui.TableColumn", table.frameHeight(170));
    }

    /// The filtered table card: a filter field under each column's title,
    /// the rows kept by every filled field, and the empty view once none is.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn filterTableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        self.filterPeople();
        const table = ziggui.Table(Self, self, &people_columns, self.people_shown_count, Self.personCell, Self.personId, &self.people_table, .{
            .header_accessory = Self.personFilter,
            .empty = ziggui.EmptyState("No matches", "Clear a filter to see everyone."),
        });
        return gallery.Card.view(theme, "Filter fields under the headers; with no match, the empty view", "TableOptions.header_accessory · .empty", table.frameHeight(240));
    }

    /// The highlighted table card: a find's current match marked beside the
    /// selection, stepped by a button, on rows taller than a table's own.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn highlightTableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const label = ziggui.BuildScope.shared().allocator().print("Match {d} of {d}", .{ self.match_row + 1, plain_rows.len }) catch @panic("oom");
        const table = ziggui.Table(Self, self, &plain_columns, plain_rows.len, Self.plainCell, null, null, .{ .row_height = 30, .highlighted = Self.isMatch });
        return gallery.Card.view(theme, "A find's current match marked; rows taller than a table's own", "TableOptions.highlighted · .row_height", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Button("Next Match", ziggui.Callback.init(Self, self, Self.nextMatch)),
                ziggui.Text(label).foregroundStyle(theme.colors.secondary_label),
                ziggui.Spacer(),
            }).spacing(10),
            table,
        }).spacing(10));
    }

    /// The Modal presentations card: buttons for the sheet and the alert.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn modalCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Modal presentations", ".sheet · .alert", ziggui.HStack(.{
            ziggui.Button("Show sheet", ziggui.Callback.init(Self, self, Self.openSheet)),
            ziggui.Button("Show alert", ziggui.Callback.init(Self, self, Self.openAlert)),
            ziggui.Spacer(),
        }).spacing(10));
    }

    /// The Menu card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn menuCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Menu", "ziggui.Menu", ziggui.HStack(.{
            ziggui.Menu("Options", &self.menu_open, .{
                ziggui.Button("Animate", ziggui.Callback.init(Self, self, Self.animate)),
                ziggui.Button("Show sheet", ziggui.Callback.init(Self, self, Self.openSheet)),
            }),
            ziggui.Spacer(),
        }));
    }

    /// The context menu card: a right-click (or Ctrl-click) on the label opens
    /// its menu.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn contextMenuCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        return gallery.Card.view(theme, "ContextMenu: right-click the label", "ziggui.ContextMenu", ziggui.HStack(.{
            ziggui.ContextMenu(ziggui.Label("report.pdf", theme.colors.accent), &self.context_open, .{
                ziggui.Button("Open", ignore),
                ziggui.Button("Rename…", ignore),
            }),
            ziggui.Spacer(),
        }));
    }

    /// The menu panel card: a right-click menu's entries and panel, drawn
    /// as an app shows one in its own `.popover`.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn menuListCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        const items = ziggui.BuildScope.shared().allocator().dupe(ziggui.View, &.{
            ziggui.MenuItem("Open", ignore),
            ziggui.MenuItem("Rename…", ignore),
            ziggui.MenuItem("Move to Trash", ignore),
        }) catch @panic("oom");
        return gallery.Card.view(theme, "A menu's entries and panel", "ziggui.MenuList · ziggui.MenuItem", ziggui.HStack(.{ ziggui.MenuList(items, 200), ziggui.Spacer() }));
    }

    /// The question card: the panel an app's yes-or-no question shows, the
    /// refusal first (Enter or y agrees, Esc or n refuses).
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn confirmAlertCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        // In the build arena: the alert keeps a pointer to its question.
        const question = ziggui.BuildScope.shared().allocator().create(ziggui.Confirm) catch @panic("oom");
        question.* = .{ .title = "Move “report.pdf” to the Trash?", .detail = "You can put it back from the Trash.", .yes_label = "Move to Trash", .on_yes = ignore };
        return gallery.Card.view(theme, "A question's panel", "ziggui.ConfirmAlert · ziggui.Confirm", ziggui.HStack(.{ ziggui.ConfirmAlert(question, "Cancel", ignore, ignore), ziggui.Spacer() }));
    }

    /// Whether a field is one of the filtered table's filter fields.
    ///
    /// - `self`: the showcase.
    /// - `field`: the field.
    /// - Returns: true for a filter field.
    pub fn ownsPeopleFilter(self: *const Self, field: *const ziggui.TextFieldState) bool {
        for (&self.people_filters) |*filter| {
            if (filter == field) return true;
        }
        return false;
    }

    /// Chooses the filtered table's rows again once a filter field changed.
    /// A typed key has the gallery invalidate the table first, between frames
    /// (`Gallery.tableKeyDown`), so a ⇧-range is kept by IDs; this call, during
    /// the build, is the fallback for a change no key made (a paste from the
    /// field's menu), which drops a range it can no longer read.
    ///
    /// - `self`: the showcase.
    fn filterPeople(self: *Self) void {
        var changed = false;
        for (&self.people_filters, &self.people_revisions) |*field, *revision| {
            if (field.revision == revision.*) continue;
            revision.* = field.revision;
            changed = true;
        }
        if (!changed) return;
        self.people_table.invalidate();
        self.people_shown_count = 0;
        for (people_rows, 0..) |person, index| {
            if (!self.keepsPerson(person)) continue;
            self.people_shown[self.people_shown_count] = index;
            self.people_shown_count += 1;
        }
    }

    /// Whether every filled filter field is found in its column's cell, case aside.
    ///
    /// - `self`: the showcase.
    /// - `person`: the row's cells.
    /// - Returns: true to keep the row.
    fn keepsPerson(self: *const Self, person: []const []const u8) bool {
        for (&self.people_filters, person) |*field, cell| {
            const wanted = field.text();
            if (wanted.len > 0 and std.ascii.findIgnoreCase(cell, wanted) == null) return false;
        }
        return true;
    }

    /// A cell of the filtered table.
    ///
    /// - `self`: the showcase.
    /// - `position`: the row's position among the rows kept.
    /// - `column`: the column.
    /// - Returns: the cell.
    fn personCell(self: *const Self, position: usize, column: usize) ziggui.View {
        return ziggui.Text(people_rows[self.people_shown[position]][column]).truncated();
    }

    /// A row's ID in the filtered table: its person's place in `people_rows`,
    /// so a selection keeps its people through a change of filter.
    ///
    /// - `self`: the showcase.
    /// - `position`: the row's position among the rows kept.
    /// - Returns: the ID.
    fn personId(self: *const Self, position: usize) u64 {
        return self.people_shown[position];
    }

    /// The filter field under a column's title.
    ///
    /// - `self`: the showcase.
    /// - `column`: the column.
    /// - Returns: the field.
    fn personFilter(self: *const Self, column: usize) ziggui.View {
        // The field's state is the showcase's; the table only reads the showcase.
        return ziggui.TextField("Filter", @constCast(&self.people_filters[column]));
    }

    /// A cell of the highlighted table.
    ///
    /// - `self`: the showcase.
    /// - `position`: the row.
    /// - `column`: the column.
    /// - Returns: the cell.
    fn plainCell(self: *const Self, position: usize, column: usize) ziggui.View {
        _ = self;
        return ziggui.Text(plain_rows[position][column]).truncated();
    }

    /// Whether a row of the highlighted table is the current match.
    ///
    /// - `self`: the showcase.
    /// - `position`: the row.
    /// - Returns: true for the match.
    fn isMatch(self: *const Self, position: usize) bool {
        return position == self.match_row;
    }

    /// Steps the highlighted table's match to the next row, the first after the last.
    ///
    /// - `self`: the showcase.
    fn nextMatch(self: *Self) void {
        self.match_row = (self.match_row + 1) % plain_rows.len;
    }

    /// The fitted table card: rows of text read through a `TableRows`, the
    /// table as tall as its rows inside the card, given no state, so it
    /// selects, sorts and resizes nothing.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn fittedTableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const table = ziggui.TableRows.table(&plain_rows, &plain_columns, null, .{});
        return gallery.Card.view(theme, "A table fitted to its rows of text, keeping no state", "ziggui.TableRows · ziggui.TableLayout", table);
    }

    /// The hidden headers card: the same rows with no header over them.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn headerlessTableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const table = ziggui.TableRows.table(&plain_rows, &plain_columns, null, .{ .column_headers = .hidden });
        return gallery.Card.view(theme, "Its headers hidden", "ziggui.Visibility · TableOptions.column_headers", table);
    }

    /// The cell mode card: a table that selects one cell, the cursor, by a
    /// tap (shown while the table has the keyboard).
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn cellTableCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const table = ziggui.TableRows.table(&plain_rows, &plain_columns, &self.cell_table, .{ .layout = .fitted, .selection_mode = .cell });
        return gallery.Card.view(theme, "Cell mode: a tap picks a cell", "ziggui.TableSelectionMode · ziggui.TableCell", table);
    }

    /// The Popover card.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn popoverCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Popover", ".popover", ziggui.HStack(.{
            ziggui.Button("Toggle popover", ziggui.Callback.init(Self, self, Self.togglePopover))
                .popover(self.show_popover.binding(), ziggui.VStack(.{
                ziggui.Text("Popover").font(.headline),
                ziggui.WrappedText("Anchored near its trigger; tap outside to dismiss."),
            }).spacing(8).padding(14).frameWidth(220)),
            ziggui.Spacer(),
        }));
    }

    /// The Popover passthrough card: a button that still takes taps beside an open popover.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn passthroughCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const taps_text = ziggui.BuildScope.shared().allocator().print("{d} taps", .{self.pass_taps.get()}) catch @panic("oom");
        return gallery.Card.view(theme, "Popover passthrough", ".popover · .popoverPassthrough", ziggui.HStack(.{
            ziggui.Button("Open popover", ziggui.Callback.init(Self, self, Self.togglePassPopover))
                .popover(self.show_pass_popover.binding(), ziggui.WrappedText("The button beside this trigger still takes taps; anywhere else closes it.").padding(14).frameWidth(220)),
            ziggui.Button("Tap me while it is open", ziggui.Callback.init(Self, self, Self.passTap)).popoverPassthrough(),
            ziggui.Text(taps_text).foregroundStyle(theme.colors.secondary_label),
            ziggui.Spacer(),
        }).spacing(10));
    }

    /// The onHover card: a box that lights while the pointer is in it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn onHoverCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "onHover", ".onHover", ziggui.HStack(.{
            ziggui.RoundedRectangle(if (self.hovering.get()) theme.colors.accent else theme.colors.control_track, 8)
                .frame(120, 44)
                .onHover(.{ .context = self, .function = Self.hovered }),
            ziggui.Text(if (self.hovering.get()) "Pointer inside" else "Point at the box").foregroundStyle(theme.colors.secondary_label),
            ziggui.Spacer(),
        }).spacing(12));
    }

    /// The Custom title bar card: the theme family's own title bar with working buttons.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn customTitleBarCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Custom title bar (Config.custom_titlebar)", "ziggui.Canvas · Theme.drawTitleBar · .modalPassthrough", self.titleBarDemo(theme));
    }

    /// The Key-ups and quitting card: the last key-up, and asking before a quit.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn keyUpsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const key_up_text = if (self.last_key_up.get() == 0)
            "Press and release a key."
        else
            ziggui.BuildScope.shared().allocator().print("Last key-up: keycode 0x{x}", .{self.last_key_up.get()}) catch @panic("oom");
        return gallery.Card.view(theme, "Key-ups and quitting", "ziggui.App.setKeyUpHandler · ziggui.Toggle", ziggui.VStack(.{
            ziggui.Text(key_up_text).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            Self.row("Ask before quitting (close button, ⌘Q)", ziggui.Toggle("", self.ask_quit.binding())),
        }).spacing(10));
    }

    /// The Effects panel: an animated value, a liquid glass toolbar over a
    /// gradient, and opacity, border and corner radius.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn effectsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            gallery.Card.view(theme, "Animation", "ziggui.Animator · ziggui.ProgressView", ziggui.VStack(.{
                ziggui.ProgressView(self.progress.get()).frameMaxWidth(),
                ziggui.HStack(.{
                    ziggui.Button("Animate value", ziggui.Callback.init(Self, self, Self.animate)),
                    ziggui.Spacer(),
                }),
            }).spacing(10)),
            gallery.Card.view(theme, "Liquid glass toolbar", ".glassEffect", ziggui.ZStack(.{
                ziggui.LinearGradient(
                    ziggui.Color.fromRgb8(88, 86, 214),
                    ziggui.Color.fromRgb8(255, 45, 85),
                    .{ .x = 0, .y = 0 },
                    .{ .x = 1, .y = 1 },
                ).frameMaxWidth().frameHeight(110).cornerRadius(12),
                self.glassToolbar(),
            }).frameMaxWidth()),
            gallery.Card.view(theme, "Opacity · border · corner radius", ".opacity · .border · .cornerRadius", ziggui.HStack(.{
                ziggui.RoundedRectangle(swatches[0], 10).frame(64, 64).opacity(0.4),
                ziggui.RoundedRectangle(swatches[2], 10).frame(64, 64).border(theme.colors.label, 2),
                ziggui.RoundedRectangle(swatches[3], 24).frame(64, 64),
                ziggui.Spacer(),
            }).spacing(12)),
        }).spacing(16);
    }

    /// The Navigation panel, title included: a list of links that push a
    /// view in place of the panel (folders, then their messages), each pushed
    /// view led by a back button that pops it, an inset split view and the
    /// gallery's `extra` cards. It fills the pane, so the gallery does not
    /// scroll it: a pushed view fills it, and the root page scrolls itself.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title.
    /// - `extra`: what follows the inset split view on the root page (the
    ///   gallery's tab view and split views).
    /// - Returns: the panel's view.
    pub fn navigationPanel(self: *Self, theme: ziggui.Theme, title: []const u8, extra: ziggui.View) ziggui.View {
        if (self.navigation.top()) |route| return self.navigationDetail(theme, title, route);
        const page = ziggui.VStack(.{
            Self.header(title),
            ziggui.Text("Tap a row to push its view onto the stack; ‹ pops it.").foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            gallery.Card.view(theme, "Stack", "ziggui.NavigationLinkIcon · ziggui.NavigationPath", self.navigationList(&navigation_folders, 0)),
            gallery.Card.view(theme, "A plain link, and the button that pops", "ziggui.NavigationLink · ziggui.NavigationBackButton", ziggui.VStack(.{
                ziggui.NavigationLink(navigation_folders[2].title, navigation_folders[2].route, &self.navigation),
                ziggui.Divider(),
                ziggui.NavigationBackButton("‹ Back (the stack is empty here)", &self.navigation).frameMaxWidth().frameAlign(.leading),
            }).spacing(0)),
            gallery.Card.view(theme, "Split view with a sidebar", "ziggui.NavigationSplitView · ziggui.Sidebar", ziggui.NavigationSplitView(
                ziggui.Sidebar(&mail_items, self.mail_selection.binding()),
                ziggui.VStack(.{
                    ziggui.Spacer(),
                    ziggui.Text(mail_items[@intCast(@max(0, @min(self.mail_selection.get(), mail_items.len - 1)))].label).font(.headline),
                    ziggui.Spacer(),
                }).frameMaxWidth().frameMaxHeight(),
                theme.colors.secondary_background,
            ).frameMaxWidth().frameHeight(170).cornerRadius(8)),
            gallery.Card.view(theme, "Inset split view (chat style)", "ziggui.NavigationSplitViewInset · ziggui.SidebarStyled", ziggui.NavigationSplitViewInset(
                ziggui.VStack(.{
                    ziggui.SidebarStyled(&chat_items, self.chat_selection.binding(), .prominent),
                    ziggui.Spacer(),
                    ziggui.ButtonIcon("New Chat", .plus, ziggui.Callback.init(Self, self, Self.noop)).frameMaxWidth(),
                }).spacing(8).padding(8).frameMaxHeight(),
                ziggui.VStack(.{
                    ziggui.Spacer(),
                    ziggui.Text("Select a chat").foregroundStyle(theme.colors.secondary_label),
                    ziggui.Spacer(),
                }).frameMaxWidth().frameMaxHeight(),
            ).frameMaxWidth()),
            extra,
        }).spacing(16).padding(20).frameMaxWidth();
        return ziggui.ScrollViewState(&self.navigation_scroll, page).frameMaxWidth().frameMaxHeight();
    }

    /// The Layout section's geometry card: a `GeometryReader` whose content is built for the
    /// size it is given.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn geometryPanel(self: *const Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            gallery.Card.view(theme, "GeometryReader: content built for the size it is given", "ziggui.GeometryReader", ziggui.GeometryReader(Self, self, Self.geometryContent)
                .frameMaxWidth()
                .frameHeight(96)),
        }).spacing(16);
    }

    /// The Images & Drawing section: an image at its own size and scaled to fit
    /// frames, a chart a `Canvas` draws through its `GraphicsContext`, and a large
    /// picture drawn from a texture of its own, panned and zoomed.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn canvasPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const image: ziggui.ImagePixels = .{ .width = demo_image_side, .height = demo_image_side, .pixels = &demo_image };
        return ziggui.VStack(.{
            gallery.Card.view(theme, "Image: its own size, and scaled to fit a frame", "ziggui.Image · .scaledToFit()", ziggui.HStack(.{
                ziggui.Image(image),
                ziggui.Image(image).scaledToFit().frame(160, 96).border(theme.colors.separator, 1),
                ziggui.Image(image).scaledToFit().frame(48, 96).border(theme.colors.separator, 1),
                ziggui.Spacer(),
            }).spacing(16)),
            gallery.Card.view(theme, "Canvas: a view that draws itself", "ziggui.Canvas · GraphicsContext.verticalGradient · .line · .fill · .text", ziggui.Canvas(Self, self, Self.drawClock).frameMaxWidth().frameHeight(160).clipped().cornerRadius(8)),
            gallery.Card.view(theme, "Markers: point at one to light it", "CanvasMarkers.crosshair · .ring · .halo · .reticle · .pill · .chip · .callout · .nearest", ziggui.Canvas(Self, self, Self.drawMarkers).frameMaxWidth().frameHeight(220).clipped().cornerRadius(8)),
            gallery.Card.view(theme, "A large picture marked up (click twice for a segment, drag an end; drag or scroll to pan, pinch or ⌘-scroll to zoom)", "ziggui.ZoomableImage · ZoomState (invert_scroll_y, invert_scroll_x) · AnnotationState · CanvasMarkers", self.pictureDemo(theme)),
        }).spacing(16);
    }

    /// Empties the Navigation panel's route stack (leaving the panel does).
    ///
    /// - `self`: the showcase.
    pub fn clearNavigation(self: *Self) void {
        while (self.navigation.depth() > 0) self.navigation.pop();
    }

    /// A key came up: the Presentations section shows its keycode.
    ///
    /// - `self`: the showcase.
    /// - `keycode`: the key's `SDL_Keycode`.
    pub fn keyUp(self: *Self, keycode: u32) void {
        self.last_key_up.set(keycode);
    }

    /// Reports whether a modal presentation (the sheet, the alert or the quit
    /// question) is up over whichever section shows, so keys must not reach
    /// what is behind it.
    ///
    /// - `self`: the showcase.
    /// - Returns: true while one is presented.
    pub fn presentsModal(self: *const Self) bool {
        return self.show_sheet.get() or self.show_alert.get() or self.show_quit.get();
    }

    /// A quit was asked for: with "Ask before quitting" on, the quit question
    /// is presented instead, and its Quit button ends the loop unasked.
    ///
    /// - `self`: the showcase.
    /// - Returns: true to let the quit end the loop.
    pub fn quitRequested(self: *Self) bool {
        if (!self.ask_quit.get()) return true;
        self.show_quit.set(true);
        return false;
    }

    /// Animates the progress toward whichever end it is farther from; set at
    /// once when no loop runs to animate it.
    ///
    /// - `self`: the showcase.
    pub fn animate(self: *Self) void {
        const target: f32 = if (self.progress.get() > 0.5) 0 else 1;
        const animator = self.platform.animator() orelse {
            self.progress.set(target);
            return;
        };
        animator.animateTo(&self.progress, target, 0.6, .easeInOut) catch |err| {
            log.warn("the progress was not animated [{t}]", .{err});
        };
    }

    /// Presents the sheet.
    ///
    /// - `self`: the showcase.
    pub fn openSheet(self: *Self) void {
        self.show_sheet.set(true);
    }

    /// Dismisses the sheet.
    ///
    /// - `self`: the showcase.
    pub fn closeSheet(self: *Self) void {
        self.show_sheet.set(false);
    }

    /// Presents the alert.
    ///
    /// - `self`: the showcase.
    pub fn openAlert(self: *Self) void {
        self.show_alert.set(true);
    }

    /// Dismisses the alert.
    ///
    /// - `self`: the showcase.
    pub fn closeAlert(self: *Self) void {
        self.show_alert.set(false);
    }

    /// Presents or dismisses the Presentations section's popover.
    ///
    /// - `self`: the showcase.
    pub fn togglePopover(self: *Self) void {
        self.show_popover.set(!self.show_popover.get());
    }

    /// Presents or dismisses the Presentations section's passthrough popover.
    ///
    /// - `self`: the showcase.
    pub fn togglePassPopover(self: *Self) void {
        self.show_pass_popover.set(!self.show_pass_popover.get());
    }

    /// Counts a tap on the passthrough button.
    ///
    /// - `self`: the showcase.
    pub fn passTap(self: *Self) void {
        self.pass_taps.set(self.pass_taps.get() + 1);
    }

    /// Dismisses the quit question, staying open.
    ///
    /// - `self`: the showcase.
    pub fn cancelQuit(self: *Self) void {
        self.show_quit.set(false);
    }

    /// Dismisses the quit question and ends the loop.
    ///
    /// - `self`: the showcase.
    pub fn confirmQuit(self: *Self) void {
        self.show_quit.set(false);
        self.platform.quit();
    }

    /// The `onHover` box's handler: records whether the pointer is inside.
    ///
    /// - `context`: the showcase.
    /// - `inside`: true on entering the box, false on leaving it.
    fn hovered(context: ?*anyopaque, inside: bool) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.hovering.set(inside);
    }

    /// The title bar demo's minimize button.
    ///
    /// - `self`: the showcase.
    fn minimizeWindow(self: *Self) void {
        self.platform.minimize();
    }

    /// The title bar demo's maximize or restore button.
    ///
    /// - `self`: the showcase.
    fn maximizeWindow(self: *Self) void {
        self.platform.toggleMaximized();
    }

    /// The title bar demo's close button.
    ///
    /// - `self`: the showcase.
    fn closeWindow(self: *Self) void {
        self.platform.requestClose();
    }

    /// A button that does nothing, for the controls that only show their look.
    ///
    /// - `self`: the showcase.
    fn noop(self: *Self) void {
        _ = self;
    }

    /// The macOS 26 toolbar pill cluster: glass icon buttons and icon-label
    /// pills inside one `.glassEffect()` capsule.
    ///
    /// - `self`: the showcase.
    /// - Returns: the toolbar.
    fn glassToolbar(self: *Self) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        return ziggui.HStack(.{
            ziggui.IconButton(.audioLines, 15, ignore),
            ziggui.IconButton(.settings, 15, ignore),
            ziggui.ButtonIcon("Think", .sparkles, ignore),
            ziggui.ButtonIcon("Agent", .wand, ignore),
            ziggui.ButtonIcon("MCP", .boxes, ignore),
            ziggui.Circle(ziggui.Color.fromRgb8(48, 209, 88)).frame(10, 10),
        }).spacing(7)
            .padding(7)
            .glassEffect();
    }

    /// The theme family's own title bar under its text color, with buttons
    /// that minimize, maximize and close the window. Close is
    /// `modalPassthrough`, so it works with the sheet or alert open.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the title bar.
    fn titleBarDemo(self: *Self, theme: ziggui.Theme) ziggui.View {
        const foreground = theme.titleBarForeground();
        return ziggui.ZStack(.{
            ziggui.Canvas(Self, self, Self.drawTitleBar).frameMaxWidth().frameHeight(32),
            ziggui.HStack(.{
                ziggui.Icon(.boxes, 16, foreground),
                ziggui.Text("File").foregroundStyle(foreground),
                ziggui.Text("View").foregroundStyle(foreground),
                ziggui.Spacer(),
                ziggui.Text("~/src/ziggui").font(.footnote).foregroundStyle(foreground),
                ziggui.Spacer(),
                ziggui.Text("–").foregroundStyle(foreground).padding(6).onTapGesture(ziggui.Callback.init(Self, self, Self.minimizeWindow)),
                ziggui.Text(if (self.platform.isMaximized()) "❐" else "□").foregroundStyle(foreground).padding(6).onTapGesture(ziggui.Callback.init(Self, self, Self.maximizeWindow)),
                ziggui.Text("×").foregroundStyle(foreground).padding(6).onTapGesture(ziggui.Callback.init(Self, self, Self.closeWindow)).modalPassthrough(),
            }).spacing(12).paddingInsets(.{ .leading = 10, .trailing = 4 }).frameHeight(32),
        }).frameMaxWidth().frameHeight(32);
    }

    /// Paints the Canvas card: a clock face on a tinted ground, its minute and
    /// hour ticks, four numerals, the hour, minute and second hands and a hub,
    /// every measure taken from the frame's shorter side, so it follows the
    /// card; a frame too small for a face draws only the ground.
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `bounds`: the card's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn drawClock(self: *const Self, graphics: *ziggui.GraphicsContext, bounds: ziggui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        const colors = graphics.context.theme.colors;
        try graphics.verticalGradient(bounds, colors.accent.withAlpha(0.12), colors.accent.withAlpha(0.02));
        const radius = @min(bounds.width, bounds.height) / 2 - 12;
        if (!(radius > 0)) return;
        const center = ziggui.Point{ .x = bounds.midX(), .y = bounds.midY() };
        try graphics.fill(.{ .x = center.x - radius, .y = center.y - radius, .width = 2 * radius, .height = 2 * radius }, radius, colors.control_background);
        for (0..60) |minute| {
            const turn = @as(f32, @floatFromInt(minute)) / 60;
            const hour_mark = minute % 5 == 0;
            const length: f32 = if (hour_mark) 0.12 else 0.05;
            try graphics.line(Self.clockPoint(center, turn, radius * (0.95 - length)), Self.clockPoint(center, turn, radius * 0.95), if (hour_mark) 2 else 1, if (hour_mark) colors.label else colors.secondary_label);
        }
        const numeral_size = @max(radius * 0.16, 8);
        for (clock_numerals) |numeral| {
            const at = Self.clockPoint(center, numeral[1] / 12, radius * 0.68);
            const width = graphics.textWidth(numeral[0], numeral_size);
            try graphics.text(numeral[0], numeral_size, colors.label, .{ .x = at.x - width / 2, .y = at.y - graphics.lineHeight(numeral_size) / 2 });
        }
        const hours = clock_seconds / 3600;
        const minutes = clock_seconds / 60;
        try graphics.line(center, Self.clockPoint(center, hours / 12, radius * 0.5), 4, colors.label);
        try graphics.line(center, Self.clockPoint(center, minutes / 60, radius * 0.78), 3, colors.label);
        try graphics.line(Self.clockPoint(center, clock_seconds / 60 + 0.5, radius * 0.15), Self.clockPoint(center, clock_seconds / 60, radius * 0.86), 1.5, colors.accent);
        try graphics.fill(.{ .x = center.x - 4, .y = center.y - 4, .width = 8, .height = 8 }, 4, colors.accent);
    }

    /// A point on the Canvas card's clock: `distance` from its center at
    /// `turn` of a revolution clockwise from twelve.
    ///
    /// - `center`: the clock's center.
    /// - `turn`: how far round, in turns (whole turns wrap).
    /// - `distance`: how far out, in points.
    /// - Returns: the point.
    fn clockPoint(center: ziggui.Point, turn: f32, distance: f32) ziggui.Point {
        const angle = 2 * std.math.pi * turn;
        return .{ .x = center.x + @sin(angle) * distance, .y = center.y - @cos(angle) * distance };
    }

    /// The Layout panel's scroll indicator columns: the same rows in three
    /// scroll views, one per `ScrollIndicatorVisibility`.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the columns.
    fn indicatorColumns(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const columns = allocator.alloc(ziggui.View, indicator_choices.len) catch @panic("oom");
        for (indicator_choices, &self.indicator_scrolls, columns) |choice, *scroll, *column| {
            column.* = ziggui.VStack(.{
                ziggui.Text(choice[1]).font(.caption).monospaced().foregroundStyle(theme.colors.secondary_label),
                ziggui.ScrollViewState(scroll, ziggui.VStack(.{
                    ziggui.ForEach(&scroll_labels, Self.scrollRow),
                }).spacing(6).padding(8)).scrollIndicators(choice[0])
                    .frameMaxWidth().frameHeight(110).background(theme.colors.window_background).cornerRadius(6),
            }).spacing(6).alignment(.leading).frameMaxWidth();
        }
        return ziggui.StackBuilder.fromSlice(.horizontal, 12, .top, columns).frameMaxWidth();
    }

    /// Paints the Markers card: every `CanvasMarkers` kind on a dark ground. A
    /// reticle and crosshair mark the first spot, rings the others, each
    /// labelled on a pill; the marker nearest the pointer (`nearest`), else
    /// the middle one, is lit by a halo and named on the chip at the foot,
    /// under a callout at the head.
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `bounds`: the card's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn drawMarkers(self: *const Self, graphics: *ziggui.GraphicsContext, bounds: ziggui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        const accent = graphics.context.theme.colors.accent;
        try graphics.verticalGradient(bounds, ziggui.Color.fromRgb8(36, 42, 54), ziggui.Color.fromRgb8(18, 21, 28));
        var spots: [marker_spots.len]ziggui.Point = undefined;
        for (marker_spots, &spots) |spot, *point| point.* = .{ .x = bounds.x + bounds.width * spot[0].x, .y = bounds.y + bounds.height * spot[0].y };
        const pointer = graphics.context.hover_point;
        const lit = if (pointer) |at| ziggui.CanvasMarkers.nearest(&spots, at, 40) orelse 1 else 1;
        try ziggui.CanvasMarkers.reticle(graphics, bounds, spots[0], 20, ziggui.Color.white.withAlpha(0.25));
        try ziggui.CanvasMarkers.halo(graphics, spots[lit], 22, accent.withAlpha(0.35));
        try ziggui.CanvasMarkers.crosshair(graphics, spots[0], 14, ziggui.Color.white, ziggui.Color.black);
        for (spots[1..]) |spot| try ziggui.CanvasMarkers.ring(graphics, spot, 10, 2, accent);
        for (marker_spots, spots) |spot, point| _ = try ziggui.CanvasMarkers.pill(graphics, .{ .x = point.x + 22, .y = point.y - 30 }, spot[1], ziggui.Color.black.withAlpha(0.6), ziggui.Color.white);
        _ = try ziggui.CanvasMarkers.callout(graphics, bounds, "Point at a marker", "nearest finds it; a halo lights it", accent, ziggui.Color.white);
        const chip_words = try graphics.print("Lit: {s} {d}", .{ marker_spots[lit][1], lit + 1 });
        _ = try ziggui.CanvasMarkers.chip(graphics, bounds, chip_words, ziggui.Color.black.withAlpha(0.6), ziggui.Color.white);
    }

    /// The Picture card: a 2048 × 1536 picture drawn from a texture of its own
    /// (`GraphicsContext.picture`, never the atlas) in a `ZoomableImage`, with
    /// markers over it, dragged to pan and zoomed with the buttons, a pinch or a
    /// ⌘-scroll (`Gallery.pictureZoom`, from the event loop); a scroll pans it, the
    /// other way on an axis its Reverse toggles turn around (`ZoomState.invert_scroll_y`,
    /// `invert_scroll_x`), and its Grid toggle paints the pattern again
    /// without or with its grid (a new `ZoomPicture.generation`, so its
    /// texture uploads afresh). Two clicks draw a
    /// segment, the second ending at the picture's edge when it lands off it,
    /// and a drag on a segment's end moves it (`AnnotationState`); a press that
    /// pans is no click. The tap is the picture's, the drag the stack's around
    /// it, so a press reaches both.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card's content.
    fn pictureDemo(self: *Self, theme: ziggui.Theme) ziggui.View {
        const zoom_text = ziggui.BuildScope.shared().allocator().print("{d:.0}%", .{self.picture_zoom.zoom * 100}) catch @panic("oom");
        // The toggles set the picture's scrolling for the events before the next frame.
        self.picture_zoom.invert_scroll_y = self.picture_invert_y.get();
        self.picture_zoom.invert_scroll_x = self.picture_invert_x.get();
        // The Grid toggle paints the pattern again, with or without its grid.
        const grid = self.picture_grid.get();
        if (grid != self.picture_grid_painted) {
            Self.paintPattern(self.picture_pixels, grid);
            self.picture_grid_painted = grid;
            self.picture_generation += 1;
        }
        const picture = ziggui.ZoomPicture{
            .image = .{ .width = picture_width, .height = picture_height, .pixels = self.picture_pixels },
            .key = @intFromPtr(self.picture_pixels.ptr),
            .generation = self.picture_generation,
            .fit_hint = "Fit to see it all",
        };
        return ziggui.VStack(.{
            ziggui.ZStack(.{
                ziggui.ZoomableImage(Self, self, Self.drawPictureMarkers, &self.picture_zoom, picture)
                    .onTapGesture(ziggui.Callback.init(Self, self, Self.pictureTapped))
                    .pointerStyle(.grabIdle),
            }).frameHeight(180).cornerRadius(8)
                .onDrag(.{ .context = self, .function = Self.pictureDragged, .end = Self.pictureReleased })
                .pointerStyle(.grabIdle),
            ziggui.HStack(.{
                ziggui.ButtonRoled("−", .normal, ziggui.Callback.init(Self, self, Self.zoomPictureOut)),
                ziggui.ButtonRoled("Fit", .normal, ziggui.Callback.init(Self, self, Self.fitPicture)),
                ziggui.ButtonRoled("+", .normal, ziggui.Callback.init(Self, self, Self.zoomPictureIn)),
                ziggui.Text(zoom_text).foregroundStyle(theme.colors.secondary_label),
                ziggui.Spacer(),
                ziggui.Toggle("Reverse ↕", self.picture_invert_y.binding()).toggleStyle(.checkbox).help("Scrolling up pans the picture down instead of up"),
                ziggui.Toggle("Reverse ↔", self.picture_invert_x.binding()).toggleStyle(.checkbox).help("Scrolling right pans the picture left instead of right"),
                ziggui.Toggle("Grid", self.picture_grid.binding()).toggleStyle(.checkbox).help("The pattern's grid, a line every 128 pixels"),
            }).spacing(8),
        }).spacing(8);
    }

    /// Marks the Picture card's picture: a crosshair and its label at the
    /// picture's centre, a ring on a grid corner, the segments with a ring on
    /// each end, and the rubber band from a first click to the pointer, placed
    /// through the geometry so they stay on their pixels as it zooms and pans.
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `geometry`: the picture's layout.
    /// - Returns: nothing; propagates allocation failure.
    fn drawPictureMarkers(self: *const Self, graphics: *ziggui.GraphicsContext, geometry: ziggui.ZoomGeometry) std.mem.Allocator.Error!void {
        const colors = graphics.context.theme.colors;
        for (self.picture_segments[0..self.picture_segment_count]) |segment| {
            try graphics.line(geometry.at(segment.start), geometry.at(segment.end), 2, colors.accent);
            try ziggui.CanvasMarkers.ring(graphics, geometry.at(segment.start), 6, 2, colors.accent);
            try ziggui.CanvasMarkers.ring(graphics, geometry.at(segment.end), 6, 2, colors.accent);
        }
        if (graphics.context.hover_point) |pointer| try self.picture_annotation.drawBand(graphics, &geometry, pointer, 2, colors.accent.withAlpha(0.6));
        const center = geometry.at(.{ .x = picture_width / 2, .y = picture_height / 2 });
        try ziggui.CanvasMarkers.ring(graphics, geometry.at(.{ .x = 512, .y = 384 }), 10, 2, colors.accent);
        try ziggui.CanvasMarkers.crosshair(graphics, center, 14, ziggui.Color.white, ziggui.Color.black);
        _ = try ziggui.CanvasMarkers.pill(graphics, .{ .x = center.x + 22, .y = center.y - 26 }, "1024, 768", colors.accent, ziggui.Color.white);
    }

    /// A press on the Picture card's picture: the fit chip fits it; a press on
    /// a segment's end takes hold of it, for the drag; elsewhere it may be a
    /// click toward a segment, which `pictureReleased` makes unless the drag
    /// pans first. A second click off the picture ends the segment at its
    /// edge (`ZoomGeometry.clipToContent`).
    ///
    /// - `self`: the showcase.
    fn pictureTapped(self: *Self) void {
        self.picture_press = null;
        self.picture_press_travel = 0;
        const press = ziggui.PointerInput.shared().press_point;
        if (self.picture_zoom.chipContains(press)) return self.picture_zoom.fit();
        const geometry = &self.picture_zoom.geometry;
        if (geometry.contentAt(press)) |at| {
            var ends: [picture_segment_capacity * 2]ziggui.Point = undefined;
            for (self.picture_segments[0..self.picture_segment_count], 0..) |segment, index| {
                ends[index * 2] = segment.start;
                ends[index * 2 + 1] = segment.end;
            }
            if (self.picture_annotation.grab(geometry, ends[0 .. self.picture_segment_count * 2], at, picture_grab_reach)) |index| {
                self.picture_drag_point = self.segmentEnd(index).*;
                return;
            }
            self.picture_press = at;
        } else if (self.picture_annotation.pending) |start| {
            self.picture_press = geometry.clipToContent(start, press);
        }
    }

    /// A drag on the Picture card: moves the segment end a press holds, kept
    /// on the picture, or pans (and a press that pans past
    /// `picture_click_slop` clicks no more).
    ///
    /// - `context`: the showcase.
    /// - `delta_x`: the movement across, in points.
    /// - `delta_y`: the movement down, in points.
    fn pictureDragged(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (self.picture_annotation.drag(&self.picture_zoom.geometry, delta_x, delta_y)) |by| {
            const index = self.picture_annotation.grabbed orelse return;
            self.picture_drag_point.x += by.x;
            self.picture_drag_point.y += by.y;
            self.segmentEnd(index).* = Self.onPicture(self.picture_drag_point);
            return;
        }
        self.picture_zoom.panBy(delta_x, delta_y);
        self.picture_press_travel += @abs(delta_x) + @abs(delta_y);
        if (self.picture_press_travel > picture_click_slop) self.picture_press = null;
    }

    /// The Picture card's press ended: lets go of the end it held, or makes
    /// the click it was: a segment's first click, or its second, which adds
    /// the segment (the oldest giving way when full).
    ///
    /// - `context`: the showcase.
    fn pictureReleased(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        _ = self.picture_annotation.release();
        const at = self.picture_press orelse return;
        self.picture_press = null;
        const segment = self.picture_annotation.click(at) orelse return;
        if (self.picture_segment_count == picture_segment_capacity) {
            @memmove(self.picture_segments[0 .. picture_segment_capacity - 1], self.picture_segments[1..]);
            self.picture_segment_count -= 1;
        }
        self.picture_segments[self.picture_segment_count] = segment;
        self.picture_segment_count += 1;
    }

    /// One end of one of the Picture card's segments.
    ///
    /// - `self`: the showcase.
    /// - `index`: the end: `segment * 2`, plus 1 for its second end.
    /// - Returns: the end.
    fn segmentEnd(self: *Self, index: usize) *ziggui.Point {
        const segment = &self.picture_segments[index / 2];
        return if (index % 2 == 0) &segment.start else &segment.end;
    }

    /// A point kept on the Picture card's picture, half a pixel inside its
    /// edges, as `ZoomGeometry.clipToContent` keeps one.
    ///
    /// - `point`: the point, in picture pixels.
    /// - Returns: the nearest point on the picture.
    fn onPicture(point: ziggui.Point) ziggui.Point {
        return .{
            .x = std.math.clamp(point.x, 0.5, picture_width - 0.5),
            .y = std.math.clamp(point.y, 0.5, picture_height - 0.5),
        };
    }

    /// Zooms the Picture card in by half again.
    ///
    /// - `self`: the showcase.
    fn zoomPictureIn(self: *Self) void {
        self.picture_zoom.zoomBy(1.5);
    }

    /// Zooms the Picture card out by a third.
    ///
    /// - `self`: the showcase.
    fn zoomPictureOut(self: *Self) void {
        self.picture_zoom.zoomBy(2.0 / 3.0);
    }

    /// Fits the Picture card's picture to the card again.
    ///
    /// - `self`: the showcase.
    fn fitPicture(self: *Self) void {
        self.picture_zoom.fit();
    }

    /// Paints the Picture card's test pattern: hue across, light down, and,
    /// when asked, a grid every 128 pixels, so zooming and panning are easy
    /// to follow.
    ///
    /// - `pixels`: `picture_width × picture_height` RGBA8.
    /// - `with_grid`: whether to draw the grid's white lines.
    fn paintPattern(pixels: []u8, with_grid: bool) void {
        for (0..picture_height) |y| {
            for (0..picture_width) |x| {
                const index = (y * picture_width + x) * 4;
                const grid = with_grid and (x % 128 < 3 or y % 128 < 3);
                const across: f32 = @as(f32, @floatFromInt(x)) / picture_width;
                const down: f32 = @as(f32, @floatFromInt(y)) / picture_height;
                pixels[index] = if (grid) 255 else @intFromFloat(255 * across);
                pixels[index + 1] = if (grid) 255 else @intFromFloat(255 * (1 - down));
                pixels[index + 2] = if (grid) 255 else @intFromFloat(255 * down * (1 - across));
                pixels[index + 3] = 255;
            }
        }
    }

    /// Paints the theme family's title bar (`Theme.drawTitleBar`).
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `bounds`: the bar's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn drawTitleBar(self: *const Self, graphics: *ziggui.GraphicsContext, bounds: ziggui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        try graphics.context.theme.drawTitleBar(graphics.context.surface(graphics.display_list), bounds);
    }

    /// The Layout section's geometry card's content: its own size, and bars a quarter and
    /// half as wide as it is.
    ///
    /// - `self`: the showcase.
    /// - `size`: the size the reader is laid out at.
    /// - Returns: the content.
    fn geometryContent(self: *const Self, size: ziggui.Size) ziggui.View {
        _ = self;
        const tokens = ziggui.BuildScope.shared().tokens();
        const label = ziggui.BuildScope.shared().allocator().print("{d:.0} × {d:.0} pt", .{ size.width, size.height }) catch @panic("oom");
        return ziggui.VStack(.{
            ziggui.Text(label).font(.headline),
            ziggui.RoundedRectangle(tokens.accent, 6).frame(size.width / 4, 20),
            ziggui.RoundedRectangle(tokens.accent.withAlpha(0.5), 6).frame(size.width / 2, 20),
        }).spacing(8).alignment(.leading).frameMaxWidth().frameAlign(.leading);
    }

    /// A view pushed on the Navigation panel's stack: a back button named
    /// for the view under it, the pushed view's title, then a folder's
    /// messages to push further, or a message's text.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title, the view under a folder.
    /// - `route`: the pushed route.
    /// - Returns: the pushed view.
    fn navigationDetail(self: *Self, theme: ziggui.Theme, title: []const u8, route: i64) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const folder = route < 10;
        const under = if (folder) title else Self.navigationTitle(@divTrunc(route, 10));
        const back = allocator.print("‹ {s}", .{under}) catch @panic("oom");
        const content = if (folder)
            gallery.Card.view(theme, "Messages", "ziggui.NavigationLinkIcon", self.navigationList(&navigation_messages, route * 10))
        else
            ziggui.WrappedText(allocator.print("Two views deep. ‹ {s} pops back one; leaving the section empties the stack.", .{under}) catch @panic("oom"))
                .foregroundStyle(theme.colors.secondary_label)
                .frameMaxWidth()
                .frameAlign(.leading);
        return ziggui.VStack(.{
            ziggui.NavigationBackButton(back, &self.navigation).frameMaxWidth().frameAlign(.leading),
            Self.header(Self.navigationTitle(route)),
            content,
            ziggui.Spacer(),
        }).spacing(12).frameMaxHeight().padding(20);
    }

    /// The Navigation panel's link rows, a divider between each two.
    ///
    /// - `self`: the showcase.
    /// - `entries`: the rows.
    /// - `base`: added to each entry's route (the folder's, times 10, for its messages).
    /// - Returns: the list.
    fn navigationList(self: *Self, entries: []const NavigationEntry, base: i64) ziggui.View {
        const rows = ziggui.BuildScope.shared().allocator().alloc(ziggui.View, entries.len * 2 - 1) catch @panic("oom");
        for (entries, 0..) |entry, index| {
            if (index > 0) rows[index * 2 - 1] = ziggui.Divider();
            rows[index * 2] = ziggui.NavigationLinkIcon(entry.title, entry.icon, base + entry.route, &self.navigation);
        }
        return ziggui.VStack(rows).spacing(0);
    }

    /// The title of a Navigation panel route: a folder (1 to 3) or one of
    /// its messages (`folder * 10 + 1` to `+ 3`).
    ///
    /// - `route`: the route.
    /// - Returns: its title.
    fn navigationTitle(route: i64) []const u8 {
        const entries: []const NavigationEntry = if (route < 10) &navigation_folders else &navigation_messages;
        const index: usize = @intCast(@mod(route, 10) - 1);
        return entries[index].title;
    }

    /// A panel's title, pinned to the leading edge, as the gallery titles its scrolled panels.
    ///
    /// - `title`: the title.
    /// - Returns: the title row.
    fn header(title: []const u8) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title).font(.largeTitle), ziggui.Spacer() }).frameMaxWidth();
    }

    /// A leading label with its control pushed to the trailing edge.
    ///
    /// - `title`: the label.
    /// - `control`: the control.
    /// - Returns: the row.
    fn row(title: []const u8, control: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title), ziggui.Spacer(), control }).frameMaxWidth();
    }

    /// One cell of the icon grid.
    ///
    /// - `icon`: the icon.
    /// - Returns: the cell.
    fn iconCell(icon: ziggui.IconName) ziggui.View {
        return ziggui.Icon(icon, 22, ziggui.BuildScope.shared().tokens().label).frameHeight(34).frameMaxWidth();
    }

    /// One square swatch of the scroll views card's grid, 44 points a side.
    ///
    /// - `fill`: the swatch's color.
    /// - Returns: the swatch.
    fn gridSwatch(fill: ziggui.Color) ziggui.View {
        return ziggui.RoundedRectangle(fill, 8).frame(44, 44);
    }

    /// One cell of the color grids.
    ///
    /// - `fill`: the cell's color.
    /// - Returns: the cell.
    fn swatchCell(fill: ziggui.Color) ziggui.View {
        return ziggui.RoundedRectangle(fill, 8).frameHeight(44);
    }

    /// One row of the scrolling tab.
    ///
    /// - `label`: the row's text.
    /// - Returns: the row.
    fn scrollRow(label: []const u8) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(label), ziggui.Spacer() }).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Showcase);
}

test "every showcase panel and card builds and draws headless" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();

    const theme = ziggui.ThemeFamily.all[0].forScheme(.light);
    for (0..9) |index| {
        window.begin(theme);
        const panel = switch (index) {
            0 => ziggui.VStack(.{ showcase.buttonsCard(theme), showcase.togglesCard(theme), showcase.sliderCard(theme), showcase.progressCard(theme), showcase.stepperCard(theme), showcase.radioGroupCard(theme), showcase.textFieldCard(theme) }),
            1 => ziggui.VStack(.{ showcase.typeScaleCard(theme), showcase.wrappedTextCard(theme), showcase.highlightedTextCard(theme), showcase.labelCard(theme), showcase.iconGalleryCard(theme) }),
            2 => ziggui.VStack(.{ showcase.shapesCard(theme), showcase.gradientCard(theme), showcase.dividersCard(theme), showcase.materialCard(theme) }),
            3 => ziggui.VStack(.{ showcase.stacksCard(theme), showcase.flowStackCard(theme), showcase.verticalGridCard(theme), showcase.horizontalGridCard(theme), showcase.tabViewCard(theme), showcase.scrollIndicatorsCard(theme) }),
            4 => ziggui.VStack(.{ showcase.tableCard(theme), showcase.filterTableCard(theme), showcase.highlightTableCard(theme), showcase.fittedTableCard(theme), showcase.headerlessTableCard(theme), showcase.cellTableCard(theme) }),
            5 => ziggui.VStack(.{ showcase.modalCard(theme), showcase.menuCard(theme), showcase.popoverCard(theme), showcase.passthroughCard(theme), showcase.onHoverCard(theme), showcase.customTitleBarCard(theme), showcase.keyUpsCard(theme) }),
            6 => showcase.effectsPanel(theme),
            7 => showcase.navigationPanel(theme, "Navigation", ziggui.Empty()),
            else => showcase.geometryPanel(theme),
        };
        const root = showcase.presentations(panel, theme);
        window.end();
        var framebuffer = try window.render(root, gallery.test_width, gallery.test_height);
        defer framebuffer.deinit();
        try std.testing.expectEqual(gallery.test_width, framebuffer.width);
    }
}

test "the overlay callbacks present and dismiss, and count passthrough taps" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();

    try std.testing.expect(!showcase.presentsModal());
    showcase.openSheet();
    try std.testing.expect(showcase.show_sheet.get() and showcase.presentsModal());
    showcase.closeSheet();
    try std.testing.expect(!showcase.show_sheet.get());
    showcase.openAlert();
    try std.testing.expect(showcase.show_alert.get() and showcase.presentsModal());
    showcase.closeAlert();
    try std.testing.expect(!showcase.show_alert.get());
    // A popover is not modal.
    showcase.togglePopover();
    try std.testing.expect(showcase.show_popover.get() and !showcase.presentsModal());
    showcase.togglePassPopover();
    showcase.passTap();
    showcase.passTap();
    try std.testing.expectEqual(@as(i64, 2), showcase.pass_taps.get());
    Showcase.hovered(&showcase, true);
    try std.testing.expect(showcase.hovering.get());
}

test "with no loop, animate sets the progress at once, toward the farther end" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();

    showcase.animate();
    try std.testing.expectEqual(@as(f32, 1), showcase.progress.get());
    showcase.animate();
    try std.testing.expectEqual(@as(f32, 0), showcase.progress.get());
}

test "a quit asks first only while Ask before quitting is on" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();

    try std.testing.expect(showcase.quitRequested());
    try std.testing.expect(!showcase.show_quit.get());
    showcase.ask_quit.set(true);
    try std.testing.expect(!showcase.quitRequested());
    try std.testing.expect(showcase.show_quit.get() and showcase.presentsModal());
    showcase.cancelQuit();
    try std.testing.expect(!showcase.show_quit.get());
    showcase.keyUp(0x61);
    try std.testing.expectEqual(@as(i64, 0x61), showcase.last_key_up.get());
}

test "a pushed route shows its detail until the stack is cleared" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();

    try showcase.navigation.push(2);
    try std.testing.expectEqual(@as(?i64, 2), showcase.navigation.top());
    showcase.clearNavigation();
    try std.testing.expectEqual(@as(usize, 0), showcase.navigation.depth());
}

test "the TabView card's scrolling tab scrolls under the wheel" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();

    const theme = ziggui.ThemeFamily.all[0].forScheme(.light);
    window.begin(theme);
    const card = showcase.tabViewCard(theme);
    window.end();
    var frame = try window.render(card, 400, 240);
    defer frame.deinit();
    // Twenty rows overflow the tab: a wheel turn over them moves them up. The
    // tab's stateless ScrollView, the frame's first, keeps its position in
    // `ScrollMemory` under its place: key 0.
    const scroll = ziggui.ScrollMemory.shared().state(0, ziggui.BuildScope.shared().frame_number);
    try std.testing.expect(scroll.maxOffset() > 0);
    try std.testing.expect(window.scroll(.{ .x = scroll.viewport_x + 20, .y = scroll.viewport_y + 20 }, 0, -3));
    try std.testing.expect(scroll.offset > 0);
}

test "the Picture card clicks on release, never on a press that pans, and keeps segments on the picture" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    const input = ziggui.PointerInput.shared();
    const saved = input.press_point;
    defer input.press_point = saved;
    // The 2048 × 1536 picture fitted into 512 × 384: four pixels a point.
    const frame = ziggui.Rect{ .x = 0, .y = 0, .width = 512, .height = 384 };
    _ = showcase.picture_zoom.layout(frame, Showcase.picture_width, Showcase.picture_height);

    // A press that pans is no click.
    input.press_point = .{ .x = 300, .y = 100 };
    showcase.pictureTapped();
    Showcase.pictureDragged(&showcase, 20, 0);
    Showcase.pictureReleased(&showcase);
    try std.testing.expect(!showcase.picture_annotation.isPending());
    showcase.picture_zoom.fit();
    _ = showcase.picture_zoom.layout(frame, Showcase.picture_width, Showcase.picture_height);

    // Two still clicks make a segment.
    input.press_point = .{ .x = 100, .y = 100 };
    showcase.pictureTapped();
    Showcase.pictureReleased(&showcase);
    try std.testing.expect(showcase.picture_annotation.isPending());
    input.press_point = .{ .x = 200, .y = 150 };
    showcase.pictureTapped();
    Showcase.pictureReleased(&showcase);
    try std.testing.expectEqual(@as(usize, 2), showcase.picture_segment_count);
    try std.testing.expectApproxEqAbs(@as(f32, 800), showcase.picture_segments[1].end.x, 1e-3);

    // A second click off the picture ends the segment at its edge (the first
    // clear of the ends above, which a press would take hold of).
    input.press_point = .{ .x = 100, .y = 200 };
    showcase.pictureTapped();
    Showcase.pictureReleased(&showcase);
    input.press_point = .{ .x = 600, .y = 100 };
    showcase.pictureTapped();
    Showcase.pictureReleased(&showcase);
    try std.testing.expectEqual(@as(usize, 3), showcase.picture_segment_count);
    try std.testing.expectApproxEqAbs(@as(f32, 2047.5), showcase.picture_segments[2].end.x, 1e-3);

    // A dragged end stays on the picture and follows the pointer back.
    input.press_point = .{ .x = 64, .y = 320 };
    showcase.pictureTapped();
    try std.testing.expectEqual(@as(?usize, 0), showcase.picture_annotation.grabbed);
    Showcase.pictureDragged(&showcase, -100, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), showcase.picture_segments[0].start.x, 1e-3);
    Showcase.pictureDragged(&showcase, 100, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 256), showcase.picture_segments[0].start.x, 1e-3);
    Showcase.pictureReleased(&showcase);
    try std.testing.expectEqual(@as(usize, 3), showcase.picture_segment_count);
}

test "the filtered table keeps the rows every filled filter finds" {
    const allocator = std.testing.allocator;
    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    try std.testing.expectEqual(people_rows.len, showcase.people_shown_count);

    // Only the engineers kept, case aside, in their order.
    try showcase.people_filters[1].setText("engineer");
    showcase.filterPeople();
    try std.testing.expectEqual(@as(usize, 2), showcase.people_shown_count);
    try std.testing.expectEqualStrings("Margaret Hamilton", people_rows[showcase.people_shown[0]][0]);
    try std.testing.expectEqualStrings("Radia Perlman", people_rows[showcase.people_shown[1]][0]);

    // A second field narrows further; a filter that finds nothing keeps no row.
    try showcase.people_filters[2].setText("195");
    showcase.filterPeople();
    try std.testing.expectEqual(@as(usize, 1), showcase.people_shown_count);
    try showcase.people_filters[0].setText("nobody");
    showcase.filterPeople();
    try std.testing.expectEqual(@as(usize, 0), showcase.people_shown_count);
}

test "the highlighted table's match steps through its rows and back to the first" {
    const allocator = std.testing.allocator;
    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    try std.testing.expect(showcase.isMatch(0) and !showcase.isMatch(1));
    for (0..plain_rows.len) |_| showcase.nextMatch();
    try std.testing.expect(showcase.isMatch(0));
}

test "the Picture card's Grid toggle paints the pattern again without its grid, and back" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();
    const theme = ziggui.ThemeFamily.all[0].forScheme(.light);

    // The first pixel is on the grid's corner: white while the grid shows.
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, showcase.picture_pixels[0..4]);
    const first = showcase.picture_generation;
    showcase.picture_grid.set(false);
    window.begin(theme);
    _ = showcase.pictureDemo(theme);
    window.end();
    try std.testing.expect(!std.mem.eql(u8, &.{ 255, 255, 255 }, showcase.picture_pixels[0..3]));
    try std.testing.expect(showcase.picture_generation > first);
    // Unchanged, the next frame paints nothing.
    const painted = showcase.picture_generation;
    window.begin(theme);
    _ = showcase.pictureDemo(theme);
    window.end();
    try std.testing.expectEqual(painted, showcase.picture_generation);
    showcase.picture_grid.set(true);
    window.begin(theme);
    _ = showcase.pictureDemo(theme);
    window.end();
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, showcase.picture_pixels[0..4]);
}
