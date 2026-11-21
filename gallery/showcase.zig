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

/// The Table panel's columns.
const table_columns = [_]ziggui.TableColumn{
    .{ .title = "Name" },
    .{ .title = "Role" },
    .{ .title = "Age", .width = 64 },
};

/// The Table panel's rows.
const table_rows = [_][]const []const u8{
    &.{ "Ada Lovelace", "Mathematician", "36" },
    &.{ "Alan Turing", "Computer Scientist", "41" },
    &.{ "Grace Hopper", "Rear Admiral", "45" },
    &.{ "Katherine Johnson", "Mathematician", "52" },
    &.{ "Margaret Hamilton", "Engineer", "33" },
};

/// The Controls panel's radio group's options.
const radio_options = [_][]const u8{ "Automatic", "On", "Off" };

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

    /// The Canvas card's week of readings, each a fraction of the plot's height.
    const chart_readings = [_]f32{ 0.35, 0.6, 0.45, 0.8, 0.55, 0.9, 0.7 };
    /// The Canvas card's day under each reading.
    const chart_days = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };

    /// The Picture card's picture width, in pixels.
    const picture_width = 2048;
    /// The Picture card's picture height, in pixels.
    const picture_height = 1536;

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

    // Controls

    /// The Controls panel's Wi‑Fi toggle.
    wifi: ziggui.State(bool),

    /// The Controls panel's Notifications toggle.
    notifications: ziggui.State(bool),

    /// The Controls panel's slider, and the progress bar under it.
    slider: ziggui.State(f32),

    /// The Controls panel's stepper.
    stepper: ziggui.State(i64),

    /// The Controls panel's radio group.
    radio: ziggui.State(i64),

    /// The Controls panel's text field.
    name: ziggui.TextFieldState,

    // Layout and table

    /// The Layout panel's selected tab.
    tab: ziggui.State(i64),

    /// The Table panel's selected row.
    table_selection: ziggui.State(i64),

    /// The Table panel's column widths, as the user dragged them.
    table_columns: ziggui.TableColumnCustomization = .{},

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

    /// The Layout panel's scroll indicator columns' scroll positions, one per
    /// `indicator_choices`.
    indicator_scrolls: [indicator_choices.len]ziggui.ScrollState = @splat(.{}),

    /// The sheet's list's scroll position.
    sheet_scroll: ziggui.ScrollState = .{},

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
            .wifi = ziggui.State(bool).init(allocator, true),
            .notifications = ziggui.State(bool).init(allocator, false),
            .slider = ziggui.State(f32).init(allocator, 0.5),
            .stepper = ziggui.State(i64).init(allocator, 2),
            .radio = ziggui.State(i64).init(allocator, 0),
            .name = ziggui.TextFieldState.init(allocator),
            .tab = ziggui.State(i64).init(allocator, 0),
            .table_selection = ziggui.State(i64).init(allocator, 0),
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
        Self.paintPattern(self.picture_pixels);
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
        self.table_selection.deinit();
        self.tab.deinit();
        self.name.deinit();
        self.radio.deinit();
        self.stepper.deinit();
        self.slider.deinit();
        self.notifications.deinit();
        self.wifi.deinit();
        self.chat_selection.deinit();
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
                .font(.footnote).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
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
        return gallery.Card.view(theme, "Buttons", "ziggui.Button · ziggui.ButtonRoled · ziggui.IconButton", ziggui.VStack(.{
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
        }).spacing(10));
    }

    /// The Toggles card: two switches in rows.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn togglesCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Toggles", "ziggui.Toggle", ziggui.VStack(.{
            Self.row("Wi‑Fi", ziggui.Toggle("", self.wifi.binding())),
            ziggui.Divider(),
            Self.row("Notifications", ziggui.Toggle("", self.notifications.binding())),
        }).spacing(8));
    }

    /// The Slider card: a slider and the progress bar it drives.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn sliderCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Slider & Progress", "ziggui.Slider · ziggui.ProgressView", ziggui.VStack(.{
            ziggui.Slider(self.slider.binding(), 0, 1).frameMaxWidth(),
            ziggui.ProgressView(self.slider.get()).frameMaxWidth(),
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
            ziggui.Text("Spinner").foreground(theme.colors.secondary_label),
            ziggui.LoadingDots(now, theme.colors.accent),
            ziggui.Text("LoadingDots").foreground(theme.colors.secondary_label),
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
                .font(.footnote).foreground(theme.colors.secondary_label),
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
            ziggui.Text("Footnote").font(.footnote).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
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
        ).foreground(theme.colors.label));
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

    /// The stacks card: an HStack with a Spacer, and a ZStack.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn stacksCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "HStack · Spacer · ZStack", "ziggui.HStack · ziggui.Spacer · ziggui.ZStack", ziggui.VStack(.{
            ziggui.HStack(.{ ziggui.Text("leading"), ziggui.Spacer(), ziggui.Text("trailing") }).frameMaxWidth(),
            ziggui.ZStack(.{
                ziggui.RoundedRectangle(swatches[7], 10).frameMaxWidth().frameHeight(60),
                ziggui.Text("ZStack overlay").foreground(ziggui.Color.white).font(.headline),
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
        return gallery.Card.view(theme, "TabView + ScrollView", "ziggui.TabView · ziggui.ScrollView", ziggui.TabView(self.tab.binding(), &tabs).frameMaxWidth().frameHeight(170));
    }

    /// The Scroll indicators card: one column per visibility.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn scrollIndicatorsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Scroll indicators: shown after a scroll, kept up while it overflows, never drawn", ".scrollIndicators · ziggui.ScrollIndicatorVisibility", self.indicatorColumns(theme));
    }

    /// The Table panel, title included: a table that fills the pane and
    /// scrolls itself, so the gallery does not scroll it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title.
    /// - Returns: the panel's view.
    pub fn tablePanel(self: *Self, theme: ziggui.Theme, title: []const u8) ziggui.View {
        return ziggui.VStack(.{
            Self.header(title),
            ziggui.Text("A multi-column table with a header and selectable rows; drag a column's edge in the header to resize it:")
                .foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            gallery.CardName.shared().view("ziggui.TableResizable · ziggui.TableColumnCustomization", theme.colors.secondary_label),
            ziggui.TableResizable(&table_columns, &table_rows, self.table_selection.binding(), &self.table_columns)
                .background(theme.colors.control_background)
                .cornerRadius(theme.metrics.corner_radius)
                .border(theme.colors.separator, theme.metrics.hairline)
                .frameMaxWidth()
                .frameMaxHeight(),
        }).spacing(12).padding(20).frameMaxWidth().frameMaxHeight();
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
            ziggui.Text(taps_text).foreground(theme.colors.secondary_label),
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
            ziggui.Text(if (self.hovering.get()) "Pointer inside" else "Point at the box").foreground(theme.colors.secondary_label),
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
            ziggui.Text(key_up_text).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
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
            ziggui.Text("Tap a row to push its view onto the stack; ‹ pops it.").foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            gallery.Card.view(theme, "Stack", "ziggui.NavigationLinkIcon · ziggui.NavigationPath", self.navigationList(&navigation_folders, 0)),
            gallery.Card.view(theme, "Inset split view (chat style)", "ziggui.NavigationSplitViewInset · ziggui.SidebarStyled", ziggui.NavigationSplitViewInset(
                ziggui.VStack(.{
                    ziggui.SidebarStyled(&chat_items, self.chat_selection.binding(), .prominent),
                    ziggui.Spacer(),
                    ziggui.ButtonIcon("New Chat", .plus, ziggui.Callback.init(Self, self, Self.noop)).frameMaxWidth(),
                }).spacing(8).padding(8).frameMaxHeight(),
                ziggui.VStack(.{
                    ziggui.Spacer(),
                    ziggui.Text("Select a chat").foreground(theme.colors.secondary_label),
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
            gallery.Card.view(theme, "Canvas: a view that draws itself", "ziggui.Canvas · GraphicsContext.verticalGradient · .line · .fill · .text", ziggui.Canvas(Self, self, Self.drawChart).frameMaxWidth().frameHeight(160).clipped().cornerRadius(8)),
            gallery.Card.view(theme, "Markers: point at one to light it", "CanvasMarkers.crosshair · .ring · .halo · .reticle · .pill · .chip · .callout · .nearest", ziggui.Canvas(Self, self, Self.drawMarkers).frameMaxWidth().frameHeight(220).clipped().cornerRadius(8)),
            gallery.Card.view(theme, "A large picture with markers (drag to pan, pinch or ⌘-scroll to zoom)", "ziggui.ZoomableImage · ZoomState · CanvasMarkers · .onDrag", self.pictureDemo(theme)),
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
                ziggui.Text("File").foreground(foreground),
                ziggui.Text("View").foreground(foreground),
                ziggui.Spacer(),
                ziggui.Text("~/src/ziggui").font(.footnote).foreground(foreground),
                ziggui.Spacer(),
                ziggui.Text("–").foreground(foreground).padding(6).onTap(ziggui.Callback.init(Self, self, Self.minimizeWindow)),
                ziggui.Text(if (self.platform.isMaximized()) "❐" else "□").foreground(foreground).padding(6).onTap(ziggui.Callback.init(Self, self, Self.maximizeWindow)),
                ziggui.Text("×").foreground(foreground).padding(6).onTap(ziggui.Callback.init(Self, self, Self.closeWindow)).modalPassthrough(),
            }).spacing(12).paddingInsets(.{ .leading = 10, .trailing = 4 }).frameHeight(32),
        }).frameMaxWidth().frameHeight(32);
    }

    /// Paints the Canvas card: a week of readings as bars over a tinted
    /// ground and a grid, a line through their tops, and the day under each,
    /// every measure taken from the frame, so it follows the card's width;
    /// a frame too small for the margins draws only the ground.
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `bounds`: the card's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn drawChart(self: *const Self, graphics: *ziggui.GraphicsContext, bounds: ziggui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        const colors = graphics.context.theme.colors;
        try graphics.verticalGradient(bounds, colors.accent.withAlpha(0.12), colors.accent.withAlpha(0.02));
        const label_size: f32 = 11;
        const label_height = graphics.lineHeight(label_size);
        const plot = ziggui.Rect{ .x = bounds.x + 16, .y = bounds.y + 14, .width = bounds.width - 32, .height = bounds.height - 26 - label_height };
        // A frame too small for its margins and labels has no plot to draw.
        if (plot.width <= 0 or plot.height <= 0) return;
        for (0..5) |step| {
            const y = plot.y + plot.height * @as(f32, @floatFromInt(step)) / 4;
            try graphics.line(.{ .x = plot.x, .y = y }, .{ .x = plot.maxX(), .y = y }, 1, colors.separator);
        }
        const slot = plot.width / @as(f32, @floatFromInt(chart_readings.len));
        var previous: ?ziggui.Point = null;
        for (chart_readings, chart_days, 0..) |reading, day, index| {
            const slot_x = plot.x + slot * @as(f32, @floatFromInt(index));
            const height = plot.height * reading;
            try graphics.fill(.{ .x = slot_x + slot * 0.2, .y = plot.maxY() - height, .width = slot * 0.6, .height = height }, 4, colors.accent.withAlpha(0.45));
            const top = ziggui.Point{ .x = slot_x + slot / 2, .y = plot.maxY() - height };
            if (previous) |from| try graphics.line(from, top, 2, colors.accent);
            previous = top;
            try graphics.text(day, label_size, colors.secondary_label, .{ .x = slot_x + (slot - graphics.textWidth(day, label_size)) / 2, .y = plot.maxY() + 8 });
        }
        // The dots go on last, over the line's joins.
        for (chart_readings, 0..) |reading, index| {
            const center = ziggui.Point{ .x = plot.x + slot * (@as(f32, @floatFromInt(index)) + 0.5), .y = plot.maxY() - plot.height * reading };
            try graphics.fill(.{ .x = center.x - 3.5, .y = center.y - 3.5, .width = 7, .height = 7 }, 3.5, colors.accent);
        }
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
                ziggui.Text(choice[1]).font(.caption).mono().foreground(theme.colors.secondary_label),
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
    /// ⌘-scroll (`Gallery.pictureZoom`, from the event loop).
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card's content.
    fn pictureDemo(self: *Self, theme: ziggui.Theme) ziggui.View {
        const zoom_text = ziggui.BuildScope.shared().allocator().print("{d:.0}%", .{self.picture_zoom.zoom * 100}) catch @panic("oom");
        const picture = ziggui.ZoomPicture{
            .image = .{ .width = picture_width, .height = picture_height, .pixels = self.picture_pixels },
            .key = @intFromPtr(self.picture_pixels.ptr),
            .fit_hint = "Fit to see it all",
        };
        return ziggui.VStack(.{
            ziggui.ZoomableImage(Self, self, Self.drawPictureMarkers, &self.picture_zoom, picture).frameHeight(180).cornerRadius(8)
                .onDrag(.{ .context = &self.picture_zoom, .function = ziggui.ZoomState.panDrag }),
            ziggui.HStack(.{
                ziggui.ButtonRoled("−", .normal, ziggui.Callback.init(Self, self, Self.zoomPictureOut)),
                ziggui.ButtonRoled("Fit", .normal, ziggui.Callback.init(Self, self, Self.fitPicture)),
                ziggui.ButtonRoled("+", .normal, ziggui.Callback.init(Self, self, Self.zoomPictureIn)),
                ziggui.Text(zoom_text).foreground(theme.colors.secondary_label),
                ziggui.Spacer(),
            }).spacing(8),
        }).spacing(8);
    }

    /// Marks the Picture card's picture: a crosshair and its label at the
    /// picture's centre and a ring on a grid corner, placed through the
    /// geometry so they stay on their pixels as it zooms and pans.
    ///
    /// - `self`: the showcase.
    /// - `graphics`: what it draws with.
    /// - `geometry`: the picture's layout.
    /// - Returns: nothing; propagates allocation failure.
    fn drawPictureMarkers(self: *const Self, graphics: *ziggui.GraphicsContext, geometry: ziggui.ZoomGeometry) std.mem.Allocator.Error!void {
        _ = self;
        const colors = graphics.context.theme.colors;
        const center = geometry.at(.{ .x = picture_width / 2, .y = picture_height / 2 });
        try ziggui.CanvasMarkers.ring(graphics, geometry.at(.{ .x = 512, .y = 384 }), 10, 2, colors.accent);
        try ziggui.CanvasMarkers.crosshair(graphics, center, 14, ziggui.Color.white, ziggui.Color.black);
        _ = try ziggui.CanvasMarkers.pill(graphics, .{ .x = center.x + 22, .y = center.y - 26 }, "1024, 768", colors.accent, ziggui.Color.white);
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

    /// Paints the Picture card's test pattern: hue across, light down, and a
    /// grid every 128 pixels, so zooming and panning are easy to follow.
    ///
    /// - `pixels`: `picture_width × picture_height` RGBA8.
    fn paintPattern(pixels: []u8) void {
        for (0..picture_height) |y| {
            for (0..picture_width) |x| {
                const index = (y * picture_width + x) * 4;
                const grid = x % 128 < 3 or y % 128 < 3;
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
                .foreground(theme.colors.secondary_label)
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
            4 => showcase.tablePanel(theme, "Table"),
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
