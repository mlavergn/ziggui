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

/// The Text & Icons panel's icon grid.
const icon_gallery = [_]ziggui.IconName{
    .house, .search,      .settings,   .user,     .users,    .heart,
    .star,  .bell,        .mail,       .calendar, .clock,    .folder,
    .file,  .image,       .download,   .upload,   .trash,    .edit,
    .copy,  .share,       .lock,       .lockOpen, .eye,      .eyeOff,
    .play,  .pause,       .sun,        .moon,     .sparkles, .zap,
    .cpu,   .shieldCheck, .badgeCheck, .info,     .check,    .send,
};

/// The side, in pixels, of the generated image the Shapes & Media panel draws.
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

/// The Controls panel's pop-up picker's options.
const picker_options = [_][]const u8{ "Small", "Medium", "Large" };

/// The Controls panel's range picker's options.
const range_options = [_][]const u8{ "Day", "Week", "Month" };

/// The Controls panel's radio group's options.
const radio_options = [_][]const u8{ "Automatic", "On", "Off" };

/// The Navigation panel's inset split view's chats.
const chat_items = [_]ziggui.SidebarItem{
    .{ .label = "New Chat", .detail = "just now" },
    .{ .label = "what does this app do", .detail = "4h ago" },
    .{ .label = "GPU renderer plan", .detail = "Yesterday" },
};

/// The Text Editor panel's opening text.
const editor_sample =
    "// ziggui TextEditor\n" ++
    "fn greet(name: []const u8) void {\n" ++
    "    std.debug.print(\"Hello, {s}!\\n\", .{name});\n" ++
    "}\n\n" ++
    "Select with the mouse, use arrows + Shift,\n" ++
    "and scroll with the wheel.\n";

/// The panels folded in from zigui's showcase: controls, text and icons,
/// shapes and media, layout, a table, a text editor, overlays, effects, a
/// navigation stack and a geometry reader, with the state they bind to.
///
/// The gallery owns one and draws a panel per section; the sheet, the alert
/// and the quit question are presented over the whole window
/// (`presentations`).
pub const Showcase = struct {
    const Self = @This();

    /// Allocates the state the panels bind to.
    allocator: std.mem.Allocator,

    /// The window the title bar demo's buttons and the animation reach; empty headless.
    platform: gallery.Platform = .{},

    // Navigation

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

    /// The Controls panel's size picker.
    picker: ziggui.State(i64),

    /// The Controls panel's range picker.
    range: ziggui.State(i64),

    /// The Controls panel's radio group.
    radio: ziggui.State(i64),

    /// The Controls panel's text field.
    name: ziggui.TextFieldState,

    // Layout and table

    /// The Layout panel's selected tab.
    tab: ziggui.State(i64),

    /// The Table panel's selected row.
    table_selection: ziggui.State(i64),

    // Effects and overlays

    /// The Effects panel's animated progress.
    progress: ziggui.State(f32),

    /// Whether the sheet is presented.
    show_sheet: ziggui.State(bool),

    /// Whether the alert is presented.
    show_alert: ziggui.State(bool),

    /// Whether the Overlays panel's popover is presented.
    show_popover: ziggui.State(bool),

    /// Whether the Overlays panel's Options menu is open.
    menu_open: ziggui.State(bool),

    /// Whether the pointer is over the Overlays panel's `onHover` box.
    hovering: ziggui.State(bool),

    /// Whether the Overlays panel's passthrough popover is presented.
    show_pass_popover: ziggui.State(bool),

    /// The taps the passthrough button took.
    pass_taps: ziggui.State(i64),

    /// The last key-up's SDL keycode, 0 before the first.
    last_key_up: ziggui.State(i64),

    /// Whether a quit asks first (the quit handler demo).
    ask_quit: ziggui.State(bool),

    /// Whether the quit question is presented.
    show_quit: ziggui.State(bool),

    // Text editor

    /// The Text Editor panel's buffer, caret and selection.
    editor: ziggui.TextFieldState,

    /// The Text Editor panel's scroll position.
    editor_scroll: ziggui.ScrollState = .{},

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
            .picker = ziggui.State(i64).init(allocator, 1),
            .range = ziggui.State(i64).init(allocator, 0),
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
            .editor = ziggui.TextFieldState.init(allocator),
        };
        errdefer self.deinit();
        try self.editor.setText(editor_sample);
        return self;
    }

    /// Releases the panels' state, and the keyboard focus if one of its fields holds it.
    ///
    /// - `self`: the showcase to tear down.
    pub fn deinit(self: *Self) void {
        if (ziggui.Focus.shared().focused()) |field| {
            if (field == &self.name or field == &self.editor) ziggui.Focus.shared().clear();
        }
        self.editor.deinit();
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
        self.range.deinit();
        self.picker.deinit();
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

    /// The Controls panel: buttons, toggles, a slider, steppers and pickers,
    /// a radio group and a text field.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn controlsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const ignore = ziggui.Callback.init(Self, self, Self.noop);
        return ziggui.VStack(.{
            Self.card(theme, "Buttons", ziggui.VStack(.{
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
            }).spacing(10)),
            Self.card(theme, "Toggles", ziggui.VStack(.{
                Self.row("Wi‑Fi", ziggui.Toggle("", self.wifi.binding())),
                ziggui.Divider(),
                Self.row("Notifications", ziggui.Toggle("", self.notifications.binding())),
            }).spacing(8)),
            Self.card(theme, "Slider & Progress", ziggui.VStack(.{
                ziggui.Slider(self.slider.binding(), 0, 1).frameMaxWidth(),
                ziggui.ProgressView(self.slider.get()).frameMaxWidth(),
            }).spacing(12)),
            Self.card(theme, "Stepper & Pickers", ziggui.VStack(.{
                Self.row("Quantity", ziggui.Stepper("", self.stepper.binding(), 0, 10, 1)),
                ziggui.Divider(),
                Self.row("Size", ziggui.Picker(self.picker.binding(), &picker_options).frameWidth(220)),
                ziggui.Divider(),
                Self.row("Range", ziggui.Picker(self.range.binding(), &range_options).frameWidth(220)),
            }).spacing(8)),
            Self.card(theme, "Radio group", ziggui.RadioGroup(self.radio.binding(), &radio_options)),
            Self.card(theme, "Text field", ziggui.VStack(.{
                ziggui.TextField("Type your name…", &self.name).frameHeight(36).cornerRadius(8).frameMaxWidth(),
                ziggui.Text("Right-click for Cut / Copy / Paste / Select All.")
                    .font(.footnote).foreground(theme.colors.secondary_label),
            }).spacing(8)),
        }).spacing(16);
    }

    /// The Text & Icons panel: the type scale, a wrapped paragraph, a label
    /// and a grid of icons.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn textPanel(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return ziggui.VStack(.{
            Self.card(theme, "Type scale", ziggui.VStack(.{
                Self.leading(ziggui.Text("Large Title").font(.largeTitle)),
                Self.leading(ziggui.Text("Title").font(.title)),
                Self.leading(ziggui.Text("Headline").font(.headline)),
                Self.leading(ziggui.Text("Body — the quick brown fox.").font(.body)),
                Self.leading(ziggui.Text("Footnote").font(.footnote).foreground(theme.colors.secondary_label)),
            }).spacing(6)),
            Self.card(theme, "Wrapped paragraph", ziggui.WrappedText(
                "WrappedText word-wraps to the width it is given, growing taller as the " ++
                    "column narrows. Reach for it for paragraphs, descriptions, captions.",
            ).foreground(theme.colors.label)),
            Self.card(theme, "Label", Self.leading(ziggui.Label("Tagged item", theme.colors.accent))),
            Self.card(theme, "Icon gallery", ziggui.LazyVGrid(6, 10, &icon_gallery, Self.iconCell).frameMaxWidth()),
        }).spacing(16);
    }

    /// The Shapes & Media panel: the shape primitives, a gradient, dividers,
    /// a generated image and a material over a gradient.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn shapesPanel(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return ziggui.VStack(.{
            Self.card(theme, "Primitives", ziggui.HStack(.{
                ziggui.Rectangle(swatches[3]).frame(56, 56),
                ziggui.RoundedRectangle(swatches[2], 12).frame(56, 56),
                ziggui.Circle(swatches[0]).frame(56, 56),
                ziggui.Capsule(swatches[4]).frame(80, 36),
                ziggui.Ellipse(swatches[6]).frame(80, 56),
                ziggui.Spacer(),
            }).spacing(12)),
            Self.card(theme, "LinearGradient", ziggui.LinearGradient(
                swatches[5],
                swatches[1],
                .{ .x = 0, .y = 0 },
                .{ .x = 1, .y = 1 },
            ).frameMaxWidth().frameHeight(90).cornerRadius(12)),
            Self.card(theme, "Dividers", ziggui.VStack(.{
                Self.leading(ziggui.Text("above")),
                ziggui.Divider(),
                ziggui.HStack(.{
                    ziggui.Text("left"),
                    ziggui.VDivider().frameHeight(20),
                    ziggui.Text("right"),
                    ziggui.Spacer(),
                }).spacing(12),
            }).spacing(8)),
            Self.card(theme, "Image (generated)", ziggui.HStack(.{
                ziggui.Image(.{ .width = demo_image_side, .height = demo_image_side, .pixels = &demo_image }).frame(64, 64),
                ziggui.WrappedText("A 64×64 RGBA gradient built at comptime and drawn via the Image component."),
            }).spacing(12)),
            Self.card(theme, "Material (frosted over gradient)", ziggui.ZStack(.{
                ziggui.LinearGradient(theme.colors.accent, swatches[5], .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 })
                    .frameMaxWidth().frameHeight(120),
                ziggui.Text("Regular material").font(.headline)
                    .padding(16).backgroundMaterial(.regular).cornerRadius(12),
            })),
        }).spacing(16);
    }

    /// The Layout panel: stacks, grids, a list, and a tab view over a scroll view.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn layoutPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const tabs = [_]ziggui.Tab{
            .{ .label = "Scroll", .content = ziggui.ScrollView(ziggui.VStack(.{
                ziggui.ForEach(&scroll_labels, Self.scrollRow),
            }).spacing(6).padding(8)) },
            .{ .label = "Info", .content = ziggui.WrappedText(
                "TabView reuses Picker for its bar; the body switches on the bound " ++
                    "selection. The first tab nests a ScrollView with 20 rows.",
            ).padding(12) },
        };
        return ziggui.VStack(.{
            Self.card(theme, "HStack · Spacer · ZStack", ziggui.VStack(.{
                ziggui.HStack(.{ ziggui.Text("leading"), ziggui.Spacer(), ziggui.Text("trailing") }).frameMaxWidth(),
                ziggui.ZStack(.{
                    ziggui.RoundedRectangle(swatches[7], 10).frameMaxWidth().frameHeight(60),
                    ziggui.Text("ZStack overlay").foreground(ziggui.Color.white).font(.headline),
                }),
            }).spacing(10)),
            Self.card(theme, "LazyVGrid", ziggui.LazyVGrid(4, 8, &swatches, Self.swatchCell).frameMaxWidth()),
            Self.card(theme, "LazyHGrid", ziggui.LazyHGrid(2, 8, &swatches, Self.swatchCell).frameHeight(96)),
            Self.card(theme, "List", ziggui.VStack(.{
                Self.listRow(theme, .user, "Profile"),
                ziggui.Divider(),
                Self.listRow(theme, .bell, "Notifications"),
                ziggui.Divider(),
                Self.listRow(theme, .lock, "Privacy"),
            }).spacing(0)),
            Self.card(theme, "TabView + ScrollView", ziggui.TabView(self.tab.binding(), &tabs).frameMaxWidth().frameHeight(170)),
        }).spacing(16);
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
            ziggui.Text("A multi-column table with a header and selectable rows:")
                .foreground(theme.colors.secondary_label).frameMaxWidth(),
            ziggui.Table(&table_columns, &table_rows, self.table_selection.binding())
                .background(theme.colors.control_background)
                .cornerRadius(theme.metrics.corner_radius)
                .border(theme.colors.separator, theme.metrics.hairline)
                .frameMaxWidth()
                .frameMaxHeight(),
        }).spacing(12).padding(20).frameMaxWidth().frameMaxHeight();
    }

    /// The Text Editor panel, title included: a multi-line editor that fills
    /// the pane and scrolls itself, so the gallery does not scroll it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title.
    /// - Returns: the panel's view.
    pub fn textEditorPanel(self: *Self, theme: ziggui.Theme, title: []const u8) ziggui.View {
        return ziggui.VStack(.{
            Self.header(title),
            ziggui.Text("Multi-line editing with selection, line numbers, and mouse drag. Click in and type.")
                .font(.footnote).foreground(theme.colors.secondary_label).frameMaxWidth(),
            ziggui.TextEditor(&self.editor, &self.editor_scroll, true).frameMaxWidth().frameMaxHeight(),
        }).spacing(12).padding(20).frameMaxWidth().frameMaxHeight();
    }

    /// The Overlays panel: modal presentations, a menu, popovers, `onHover`,
    /// a custom title bar, key-ups and the quit question.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn overlaysPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const key_up_text = if (self.last_key_up.get() == 0)
            "Press and release a key."
        else
            ziggui.BuildScope.shared().allocator().print("Last key-up: keycode 0x{x}", .{self.last_key_up.get()}) catch @panic("oom");
        const taps_text = ziggui.BuildScope.shared().allocator().print("{d} taps", .{self.pass_taps.get()}) catch @panic("oom");
        return ziggui.VStack(.{
            Self.card(theme, "Modal presentations", ziggui.HStack(.{
                ziggui.Button("Show sheet", ziggui.Callback.init(Self, self, Self.openSheet)),
                ziggui.Button("Show alert", ziggui.Callback.init(Self, self, Self.openAlert)),
                ziggui.Spacer(),
            }).spacing(10)),
            Self.card(theme, "Menu", ziggui.HStack(.{
                ziggui.Menu("Options", &self.menu_open, .{
                    ziggui.Button("Animate", ziggui.Callback.init(Self, self, Self.animate)),
                    ziggui.Button("Show sheet", ziggui.Callback.init(Self, self, Self.openSheet)),
                }),
                ziggui.Spacer(),
            })),
            Self.card(theme, "Popover", ziggui.HStack(.{
                ziggui.Button("Toggle popover", ziggui.Callback.init(Self, self, Self.togglePopover))
                    .popover(self.show_popover.binding(), ziggui.VStack(.{
                    ziggui.Text("Popover").font(.headline),
                    ziggui.WrappedText("Anchored near its trigger; tap outside to dismiss."),
                }).spacing(8).padding(14).frameWidth(220)),
                ziggui.Spacer(),
            })),
            Self.card(theme, "Popover passthrough", ziggui.HStack(.{
                ziggui.Button("Open popover", ziggui.Callback.init(Self, self, Self.togglePassPopover))
                    .popover(self.show_pass_popover.binding(), ziggui.WrappedText("The button beside this trigger still takes taps; anywhere else closes it.").padding(14).frameWidth(220)),
                ziggui.Button("Tap me while it is open", ziggui.Callback.init(Self, self, Self.passTap)).popoverPassthrough(),
                ziggui.Text(taps_text).foreground(theme.colors.secondary_label),
                ziggui.Spacer(),
            }).spacing(10)),
            Self.card(theme, "onHover", ziggui.HStack(.{
                ziggui.RoundedRectangle(if (self.hovering.get()) theme.colors.accent else theme.colors.control_track, 8)
                    .frame(120, 44)
                    .onHover(.{ .context = self, .function = Self.hovered }),
                ziggui.Text(if (self.hovering.get()) "Pointer inside" else "Point at the box").foreground(theme.colors.secondary_label),
                ziggui.Spacer(),
            }).spacing(12)),
            Self.card(theme, "Custom title bar (Config.custom_titlebar)", self.titleBarDemo(theme)),
            Self.card(theme, "Key-ups and quitting", ziggui.VStack(.{
                Self.leading(ziggui.Text(key_up_text).foreground(theme.colors.secondary_label)),
                Self.row("Ask before quitting (close button, ⌘Q)", ziggui.Toggle("", self.ask_quit.binding())),
            }).spacing(10)),
        }).spacing(16);
    }

    /// The Effects panel: an animated value, a liquid glass toolbar over a
    /// gradient, and opacity, border and corner radius.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn effectsPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.card(theme, "Animation", ziggui.VStack(.{
                ziggui.ProgressView(self.progress.get()).frameMaxWidth(),
                ziggui.HStack(.{
                    ziggui.Button("Animate value", ziggui.Callback.init(Self, self, Self.animate)),
                    ziggui.Spacer(),
                }),
            }).spacing(10)),
            Self.card(theme, "Liquid glass toolbar", ziggui.ZStack(.{
                ziggui.LinearGradient(
                    ziggui.Color.fromRgb8(88, 86, 214),
                    ziggui.Color.fromRgb8(255, 45, 85),
                    .{ .x = 0, .y = 0 },
                    .{ .x = 1, .y = 1 },
                ).frameMaxWidth().frameHeight(110).cornerRadius(12),
                self.glassToolbar(),
            }).frameMaxWidth()),
            Self.card(theme, "Opacity · border · corner radius", ziggui.HStack(.{
                ziggui.RoundedRectangle(swatches[0], 10).frame(64, 64).opacity(0.4),
                ziggui.RoundedRectangle(swatches[2], 10).frame(64, 64).border(theme.colors.label, 2),
                ziggui.RoundedRectangle(swatches[3], 24).frame(64, 64),
                ziggui.Spacer(),
            }).spacing(12)),
        }).spacing(16);
    }

    /// The Navigation panel, title included: a stack of links whose detail
    /// replaces the panel while pushed, and an inset split view. It fills the
    /// pane, so the gallery does not scroll it.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title.
    /// - Returns: the panel's view.
    pub fn navigationPanel(self: *Self, theme: ziggui.Theme, title: []const u8) ziggui.View {
        if (self.navigation.top()) |route| {
            return ziggui.VStack(.{
                Self.leading(ziggui.NavigationBackButton("‹ Back", &self.navigation)),
                Self.header("Detail"),
                ziggui.WrappedText(ziggui.BuildScope.shared().allocator().print(
                    "You pushed route {d}. NavigationPath holds the route stack; NavigationBackButton pops it.",
                    .{route},
                ) catch @panic("oom")),
                ziggui.Spacer(),
            }).spacing(12).padding(20).frameMaxWidth().frameMaxHeight().padding(20);
        }
        return ziggui.VStack(.{
            Self.header(title),
            ziggui.Text("Tap a row to push a detail view onto the stack.")
                .foreground(theme.colors.secondary_label).frameMaxWidth(),
            Self.card(theme, "Stack", ziggui.VStack(.{
                ziggui.NavigationLink("Inbox", 1, &self.navigation).frameMaxWidth(),
                ziggui.NavigationLink("Archive", 2, &self.navigation).frameMaxWidth(),
                ziggui.NavigationLink("Trash", 3, &self.navigation).frameMaxWidth(),
            }).spacing(6)),
            Self.card(theme, "Inset split view (chat style)", ziggui.NavigationSplitViewInset(
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
            ).frameMaxWidth().frameHeight(240)),
            ziggui.Spacer(),
        }).spacing(16).frameMaxHeight().padding(20);
    }

    /// The Geometry panel: a `GeometryReader` whose content is built for the
    /// size it is given.
    ///
    /// - `self`: the showcase.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn geometryPanel(self: *const Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            Self.card(theme, "GeometryReader: content built for the size it is given", ziggui.GeometryReader(Self, self, Self.geometryContent)
                .frameMaxWidth()
                .frameHeight(96)),
        }).spacing(16);
    }

    /// Empties the Navigation panel's route stack (leaving the panel does).
    ///
    /// - `self`: the showcase.
    pub fn clearNavigation(self: *Self) void {
        while (self.navigation.depth() > 0) self.navigation.pop();
    }

    /// A key came up: the Overlays panel shows its keycode.
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

    /// Presents or dismisses the Overlays panel's popover.
    ///
    /// - `self`: the showcase.
    pub fn togglePopover(self: *Self) void {
        self.show_popover.set(!self.show_popover.get());
    }

    /// Presents or dismisses the Overlays panel's passthrough popover.
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
            ziggui.Drawing(Self, self, Self.drawTitleBar).frameMaxWidth().frameHeight(32),
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

    /// Paints the theme family's title bar (`Theme.drawTitleBar`).
    ///
    /// - `self`: the showcase.
    /// - `pen`: the paint context.
    /// - `bounds`: the bar's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn drawTitleBar(self: *const Self, pen: *ziggui.Pen, bounds: ziggui.Rect) std.mem.Allocator.Error!void {
        _ = self;
        try pen.context.theme.drawTitleBar(pen.context.surface(pen.canvas), bounds);
    }

    /// The Geometry panel's content: its own size, and bars a quarter and
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

    /// A panel's title, pinned to the leading edge, as the gallery titles its scrolled panels.
    ///
    /// - `title`: the title.
    /// - Returns: the title row.
    fn header(title: []const u8) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title).font(.largeTitle), ziggui.Spacer() }).frameMaxWidth();
    }

    /// A grouped-form section, macOS 26 style: a headline above a rounded
    /// block in the secondary background.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the section's headline.
    /// - `content`: the section's contents.
    /// - Returns: the section.
    fn card(theme: ziggui.Theme, title: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Text(title).font(.headline),
                ziggui.Spacer(),
            }).frameMaxWidth(),
            content.frameMaxWidth()
                .padding(14)
                .background(theme.colors.secondary_background)
                .cornerRadius(theme.metrics.corner_radius)
                .frameMaxWidth(),
        }).spacing(8)
            .frameMaxWidth();
    }

    /// A leading label with its control pushed to the trailing edge.
    ///
    /// - `title`: the label.
    /// - `control`: the control.
    /// - Returns: the row.
    fn row(title: []const u8, control: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title), ziggui.Spacer(), control }).frameMaxWidth();
    }

    /// Pins `content` to the leading edge of a full-width row.
    ///
    /// - `content`: the view to pin.
    /// - Returns: the row.
    fn leading(content: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ content, ziggui.Spacer() }).frameMaxWidth();
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

    /// One row of the Layout panel's list: an icon, a label and a chevron.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `icon`: the leading icon.
    /// - `label`: the row's text.
    /// - Returns: the row.
    fn listRow(theme: ziggui.Theme, icon: ziggui.IconName, label: []const u8) ziggui.View {
        return ziggui.HStack(.{
            ziggui.Icon(icon, 16, theme.colors.accent),
            ziggui.Text(label),
            ziggui.Spacer(),
            ziggui.Icon(.chevronRight, 14, theme.colors.tertiary_label),
        }).spacing(10).padding(8).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Showcase);
}

test "every showcase panel builds and draws headless" {
    const allocator = std.testing.allocator;

    var showcase = try Showcase.init(allocator);
    defer showcase.deinit();
    const canvas = try ziggui.TestCanvas.create(allocator);
    defer canvas.destroy();

    const theme = ziggui.ThemeFamily.all[0].forScheme(.light);
    for (0..10) |index| {
        canvas.begin(theme);
        const panel = switch (index) {
            0 => showcase.controlsPanel(theme),
            1 => showcase.textPanel(theme),
            2 => showcase.shapesPanel(theme),
            3 => showcase.layoutPanel(theme),
            4 => showcase.tablePanel(theme, "Table"),
            5 => showcase.textEditorPanel(theme, "Text Editor"),
            6 => showcase.overlaysPanel(theme),
            7 => showcase.effectsPanel(theme),
            8 => showcase.navigationPanel(theme, "Navigation"),
            else => showcase.geometryPanel(theme),
        };
        const root = showcase.presentations(panel, theme);
        canvas.end();
        var framebuffer = try canvas.render(root, gallery.test_width, gallery.test_height);
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
