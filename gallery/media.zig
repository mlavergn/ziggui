const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_media);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The sample the Media Video panel plays: Apple's public HLS example (10 minutes,
/// fMP4, an English audio rendition and two subtitle ones). Fetched only when
/// "Load sample stream" is pressed.
const sample_url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8";

/// The sample the Media Audio panel plays: the audio-only variant of Apple's
/// public HLS example (AAC). Fetched only when "Load sample audio" is pressed.
const audio_sample_url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear0/prog_index.m3u8";

/// Which half of the system report an info card shows.
const InfoHalf = enum {
    const Self = @This();

    /// How the window draws and the media player (the Media Video panel).
    video,
    /// Both halves at once: drawing, the player and the audio outputs.
    system,
    /// The audio outputs (the Media Audio panel).
    audio,
};

/// The Media Video panel: a `VideoPlayer` with controls drawn over the picture, the
/// buttons that load and clear its item, and what the player reports.
pub const Media = struct {
    const Self = @This();

    /// Owns the player and the subtitle lists a tap reads.
    allocator: std.mem.Allocator,

    /// The panel's player.
    player: ziggui.Player,

    /// The standard controls' state.
    controls: ziggui.VideoPlayerControlsState = .{},

    /// Whether the audio output menu is shown.
    output_menu: ziggui.State(bool),

    /// The controls card's state, beside the standard controls' own.
    accessory_controls: ziggui.VideoPlayerControlsState = .{},

    /// Whether the controls card's chapter menu is shown.
    chapter_menu: ziggui.State(bool),

    /// Owns `report` and its strings.
    report_arena: std.heap.ArenaAllocator,

    /// What the Media Video and Media Audio panels' info and output menus show
    /// (the menus list its `audio_outputs`): read as either panel first
    /// shows (`showPanel`), and again from Refresh Info or a menu's Refresh.
    report: ?ziggui.SystemReport = null,

    /// `report` has been read, or tried: a failed read is not tried again
    /// each frame.
    report_read: bool = false,

    /// The Media Audio panel's player.
    audio_player: ziggui.Player,

    /// The audio bar's state.
    audio_controls: ziggui.AudioPlayerControlsState = .{},

    /// Whether the Media Audio panel's output menu is shown.
    audio_output_menu: ziggui.State(bool),

    /// Whether the player fills the window alone (the controls' full-screen button).
    expanded: bool = false,

    /// Takes the window into full screen (true) or out of it; `main.zig`
    /// sets it, null headless.
    set_full_screen_fn: ?*const fn (bool) void = null,

    /// Reports whether the window is in full screen; `main.zig` sets it,
    /// null headless.
    ///
    /// - Returns: true while the window is full screen.
    is_full_screen_fn: ?*const fn () bool = null,

    /// Whether the window was in full screen before the player filled it,
    /// which it goes back to.
    full_screen_before: bool = false,

    /// Whether the window has been seen in full screen since the player
    /// filled it: the system's transition takes a moment to report.
    full_screen_seen: bool = false,

    /// What "Load sample stream" plays: `sample_url`, or what `--video` named.
    sample: [:0]const u8 = sample_url,

    /// The Media Native section's platform view: an `NSView` `main.zig` makes on
    /// macOS; null headless and elsewhere, where the panel shows the placeholder.
    native_sample: ?*anyopaque = null,

    /// Constructs the panel's player, with no item.
    ///
    /// - `allocator`: allocator for the player; must outlive the panel.
    /// - Returns: the panel.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .allocator = allocator,
            .player = ziggui.Player.init(allocator),
            .output_menu = ziggui.State(bool).init(allocator, false),
            .chapter_menu = ziggui.State(bool).init(allocator, false),
            .report_arena = std.heap.ArenaAllocator.init(allocator),
            .audio_player = ziggui.Player.init(allocator),
            .audio_output_menu = ziggui.State(bool).init(allocator, false),
        };
        return self;
    }

    /// Stops and frees the player.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.player.deinit();
        self.output_menu.deinit();
        self.chapter_menu.deinit();
        self.report_arena.deinit();
        self.audio_player.deinit();
        self.audio_output_menu.deinit();
    }

    /// The Media Video panel: the picture with the standard controls over it, the
    /// item's buttons, and the player's state.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn videoPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const observation = self.player.observe();
        const buttons = self.itemButtons("Load sample stream", ziggui.Callback.init(Self, self, Self.loadSample), ziggui.Callback.init(Self, self, Self.clear), &self.player, &self.output_menu, Self.chooseOutput);
        return ziggui.VStack(.{
            gallery.Card.view(theme, "VideoPlayer: the platform player draws the picture, ziggui the controls over it", "ziggui.VideoPlayer · ziggui.VideoPlayerControls · ziggui.Player", self.picture(8).frameHeight(300)),
            buttons,
            ziggui.Text(Self.describe(observation, "No item. Load sample stream plays Apple's HLS example (over the network).")).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            self.accessoriesCard(theme),
            self.infoCard(theme, "VideoInfoView: how the window draws and the media player", "ziggui.VideoInfoView · ziggui.SystemInfo", .video),
            self.infoCard(theme, "SystemInfoView: drawing, the player and the audio outputs, an app's System Info sheet", "ziggui.SystemInfoView · ziggui.SystemReport", .system),
        }).spacing(16);
    }

    /// The controls card: the same player's standard controls with an app's
    /// own buttons among them, a bookmark button at the top trailing corner
    /// and a chapter menu in the transport bar, over a plain ground (one
    /// `VideoPlayer` a player: the picture shows in the card above).
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    fn accessoriesCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const ignore = ziggui.Callback.init(Self, self, Self.noted);
        const chapters = allocator.dupe(ziggui.View, &.{
            ziggui.MenuItem("Opening", ignore),
            ziggui.MenuItem("The middle", ignore),
            ziggui.MenuItem("Credits", ignore),
        }) catch @panic("oom");
        const accessories: ziggui.VideoPlayerControlsAccessories = .{
            .top_trailing = allocator.dupe(ziggui.View, &.{ziggui.VideoPlayerControlButton(.bookmark, ignore)}) catch @panic("oom"),
            .transport = allocator.dupe(ziggui.View, &.{ziggui.VideoPlayerControlMenu(.listVideo, &self.chapter_menu, chapters)}) catch @panic("oom"),
        };
        return gallery.Card.view(theme, "VideoPlayerControlsWith: an app's own buttons among the standard controls", "ziggui.VideoPlayerControlsWith · ziggui.VideoPlayerControlButton · ziggui.VideoPlayerControlMenu", ziggui.ZStack(.{
            ziggui.RoundedRectangle(ziggui.Color.black, 8).frameMaxWidth().frameMaxHeight(),
            ziggui.VideoPlayerControlsWith(&self.player, &self.accessory_controls, accessories),
        }).frameHeight(170));
    }

    /// A tap on one of the controls card's own buttons, which do nothing here.
    ///
    /// - `self`: the panel.
    fn noted(self: *Self) void {
        _ = self;
    }

    /// The Media Audio panel: the audio bar over its own `Player`, the
    /// item's buttons (and the output menu where outputs are listed), what
    /// the player reports, and the audio outputs.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn audioPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const observation = self.audio_player.observe();
        const title = if (observation.has_item) "Apple's HLS example (audio)" else "";
        const buttons = self.itemButtons("Load sample audio", ziggui.Callback.init(Self, self, Self.loadAudioSample), ziggui.Callback.init(Self, self, Self.clearAudio), &self.audio_player, &self.audio_output_menu, Self.chooseAudioOutput);
        return ziggui.VStack(.{
            gallery.Card.view(theme, "AudioPlayerControls: a podcast player's bar over a Player with no picture", "ziggui.AudioPlayerControls · ziggui.AudioPlayerControlsState · ziggui.Player", ziggui.AudioPlayerControls(&self.audio_player, &self.audio_controls, title)),
            buttons,
            ziggui.Text(Self.describe(observation, "No item. Load sample audio plays the audio of Apple's HLS example (over the network).")).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            self.infoCard(theme, "AudioInfoView: the output the player plays through, and the devices", "ziggui.AudioInfoView · ziggui.AudioOutputs", .audio),
        }).spacing(16);
    }

    /// The player alone, filling the window, while the controls' full-screen
    /// button holds it there.
    ///
    /// - `self`: the panel.
    /// - Returns: the view.
    pub fn expandedView(self: *Self) ziggui.View {
        return self.picture(0).background(ziggui.Color.black).frameMaxWidth().frameMaxHeight();
    }

    /// Shows the player alone, filling the window, and takes the window full
    /// screen; or puts the player back in the panel and the window back as
    /// it was before.
    ///
    /// - `self`: the panel.
    pub fn toggleExpanded(self: *Self) void {
        if (self.expanded) {
            self.expanded = false;
            if (self.set_full_screen_fn) |hook| hook(self.full_screen_before);
            return;
        }
        self.full_screen_before = if (self.is_full_screen_fn) |hook| hook() else false;
        self.full_screen_seen = false;
        self.expanded = true;
        if (self.set_full_screen_fn) |hook| hook(true);
    }

    /// Puts the player back in the panel once the window has left full
    /// screen some other way (the green button, ⌃⌘F): called each frame.
    ///
    /// - `self`: the panel.
    pub fn syncFullScreen(self: *Self) void {
        if (!self.expanded) return;
        const hook = self.is_full_screen_fn orelse return;
        if (hook()) {
            self.full_screen_seen = true;
        } else if (self.full_screen_seen) {
            self.expanded = false;
        }
    }

    /// The Media Native section: an app-made platform view placed by layout,
    /// with ziggui text above and below it.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn nativePanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const secondary = ziggui.BuildScope.shared().tokens().secondary_label;
        return ziggui.VStack(.{
            gallery.Card.view(theme, "NativeView: the app's platform view, placed and clipped where layout puts it", "ziggui.NativeView", ziggui.NativeView(self.native_sample).cornerRadius(8).frameHeight(220)),
            ziggui.Text("It sits over the window's surface, so it hides while a sheet, alert, popover or menu is open.").foreground(secondary).truncated().frameMaxWidth().frameAlign(.leading),
            ziggui.Text("A view that takes the keyboard (a web view) gets it on a click; a click elsewhere gives it back.").foreground(secondary).truncated().frameMaxWidth().frameAlign(.leading),
        }).spacing(16);
    }

    /// The picture with the standard controls over it, the full-screen
    /// button wired to `toggleExpanded`.
    ///
    /// - `self`: the panel.
    /// - `corner_radius`: the picture's corners (the `VideoPlayer`'s own, which
    ///   its erase and the platform's picture follow).
    /// - Returns: the view.
    fn picture(self: *Self, corner_radius: f32) ziggui.View {
        self.controls.on_full_screen = ziggui.Callback.init(Self, self, Self.toggleExpanded);
        self.controls.full_screen = self.expanded;
        return ziggui.ZStack(.{
            ziggui.VideoPlayer(&self.player).cornerRadius(corner_radius),
            ziggui.VideoPlayerControls(&self.player, &self.controls),
        });
    }

    /// Reads the system the first time the Media Video or Media Audio panel shows,
    /// so their views only draw what was read; the gallery calls it as the
    /// section opens. GStreamer starts and the devices are probed here, once.
    ///
    /// - `self`: the panel.
    pub fn showPanel(self: *Self) void {
        if (!self.report_read) self.readReport();
    }

    /// Plays the sample stream from its start.
    ///
    /// - `self`: the panel.
    fn loadSample(self: *Self) void {
        self.player.replaceCurrentItem(self.sample) catch |err| log.warn("sample not loaded [{t}]", .{err});
        self.player.play();
    }

    /// A panel's system info: the video or the audio half of the report,
    /// with Refresh Info under it (headless: no window, no player, no devices).
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the card's heading.
    /// - `names`: what it shows, as code names it.
    /// - `half`: the video or the audio half.
    /// - Returns: the card and its button.
    fn infoCard(self: *Self, theme: ziggui.Theme, title: []const u8, names: []const u8, half: InfoHalf) ziggui.View {
        const body = if (self.report) |*report| switch (half) {
            .video => ziggui.VideoInfoView(report),
            .audio => ziggui.AudioInfoView(report, self.audio_player.audioOutput()),
            .system => ziggui.SystemInfoView(report, self.player.audioOutput()),
        } else ziggui.Text("The system could not be read.");
        return ziggui.VStack(.{
            gallery.Card.view(theme, title, names, body),
            ziggui.HStack(.{
                ziggui.Button("Refresh Info", ziggui.Callback.init(Self, self, Self.readReport)),
                ziggui.Spacer(),
            }).frameMaxWidth(),
        }).spacing(8);
    }

    /// Reads the system again (a panel's first show, Refresh Info, and the
    /// output menus' Refresh).
    ///
    /// - `self`: the panel.
    fn readReport(self: *Self) void {
        self.report_read = true;
        _ = self.report_arena.reset(.retain_capacity);
        self.report = ziggui.SystemInfo.shared().report(self.report_arena.allocator()) catch |err| blk: {
            log.warn("system not read [{t}]", .{err});
            break :blk null;
        };
    }

    /// A panel's item buttons: load and clear, then the audio output menu
    /// only where the platform lists outputs, so a headless screenshot (no
    /// outputs) keeps the row it had.
    ///
    /// - `self`: the panel.
    /// - `load_title`: the load button's title.
    /// - `on_load`: what the load button does.
    /// - `on_clear`: what the Clear button does.
    /// - `player`: the player whose output the menu ticks.
    /// - `open`: whether the menu is shown.
    /// - `choose`: what a menu entry's tap calls (`outputMenu`).
    /// - Returns: the row.
    fn itemButtons(self: *Self, load_title: []const u8, on_load: ziggui.Callback, on_clear: ziggui.Callback, player: *ziggui.Player, open: *ziggui.State(bool), comptime choose: fn (*Self, usize) void) ziggui.View {
        const menu = if (ziggui.AudioOutputs.available()) self.outputMenu(player, open, choose) else ziggui.Empty();
        return ziggui.HStack(.{
            ziggui.Button(load_title, on_load),
            ziggui.Button("Clear", on_clear),
            menu,
            ziggui.Spacer(),
        }).spacing(8).frameMaxWidth();
    }

    /// The audio output menu: the system default, each output (the
    /// system's default marked, the player's ticked), and Refresh.
    ///
    /// - `self`: the panel.
    /// - `player`: the player whose output the menu ticks.
    /// - `open`: whether the menu is shown.
    /// - `choose`: what an entry's tap calls, given its tag (0 the system
    ///   default, else the output one before it).
    /// - Returns: the menu's button.
    fn outputMenu(self: *Self, player: *ziggui.Player, open: *ziggui.State(bool), comptime choose: fn (*Self, usize) void) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const listed = self.outputs();
        const chosen = ziggui.AudioOutputs.indexOf(listed, player.audioOutput());
        var items: std.ArrayList(ziggui.View) = .empty;
        const default_title = if (chosen == null) "✓ System default" else "   System default";
        items.append(allocator, ziggui.MenuItem(default_title, ziggui.Callback.tagged(Self, self, choose, 0))) catch @panic("oom");
        for (listed, 0..) |output, index| {
            // A device's name is whatever it calls itself (a Bluetooth one's
            // is anyone's to set): cleaned, as `SystemInfoView` cleans it.
            const name = ziggui.DisplayText.clean(allocator, output.name);
            const title = allocator.print("{s}{s}{s}", .{ if (chosen == index) "✓ " else "   ", name, output.defaultMark() }) catch @panic("oom");
            items.append(allocator, ziggui.MenuItem(title, ziggui.Callback.tagged(Self, self, choose, index + 1))) catch @panic("oom");
        }
        items.append(allocator, ziggui.MenuItem("Refresh", ziggui.Callback.init(Self, self, Self.readReport))) catch @panic("oom");
        const label = if (chosen) |index| allocator.print("Audio: {s}", .{ziggui.DisplayText.clean(allocator, listed[index].name)}) catch @panic("oom") else "Audio: System default";
        return ziggui.Menu(label, open, items.items);
    }

    /// The audio outputs the menus list: the report's.
    ///
    /// - `self`: the panel.
    /// - Returns: the outputs, none before a report is read or where none are listed.
    fn outputs(self: *const Self) []const ziggui.AudioOutput {
        const report = self.report orelse return &.{};
        return report.audio_outputs;
    }

    /// The id of the output a menu's `tag` names.
    ///
    /// - `self`: the panel.
    /// - `tag`: the entry chosen: 0 the system default, else the output one before it.
    /// - Returns: the id, or null for the system default (or an entry gone).
    fn outputId(self: *const Self, tag: usize) ?[]const u8 {
        const listed = self.outputs();
        if (tag == 0 or tag > listed.len) return null;
        return listed[tag - 1].id;
    }

    /// Routes the video player's sound to the output a menu entry names.
    ///
    /// - `self`: the panel.
    /// - `tag`: the entry chosen (`outputId`).
    fn chooseOutput(self: *Self, tag: usize) void {
        self.route(&self.player, &self.output_menu, tag);
    }

    /// Routes the audio player's sound to the output a menu entry names.
    ///
    /// - `self`: the panel.
    /// - `tag`: the entry chosen (`outputId`).
    fn chooseAudioOutput(self: *Self, tag: usize) void {
        self.route(&self.audio_player, &self.audio_output_menu, tag);
    }

    /// Closes an output menu and routes its player's sound to the output
    /// the entry names.
    ///
    /// - `self`: the panel.
    /// - `player`: the menu's player.
    /// - `open`: whether the menu is shown.
    /// - `tag`: the entry chosen (`outputId`).
    fn route(self: *Self, player: *ziggui.Player, open: *ziggui.State(bool), tag: usize) void {
        open.set(false);
        player.setAudioOutput(self.outputId(tag)) catch |err| log.warn("audio output not set [{t}]", .{err});
    }

    /// Plays the sample audio from its start.
    ///
    /// - `self`: the panel.
    fn loadAudioSample(self: *Self) void {
        self.audio_player.replaceCurrentItem(audio_sample_url) catch |err| log.warn("sample audio not loaded [{t}]", .{err});
        self.audio_player.play();
    }

    /// Stops the audio player and removes its item.
    ///
    /// - `self`: the panel.
    fn clearAudio(self: *Self) void {
        self.audio_player.pause();
        self.audio_player.replaceCurrentItem(null) catch |err| log.warn("audio item not cleared [{t}]", .{err});
    }

    /// Stops and removes the item.
    ///
    /// - `self`: the panel.
    fn clear(self: *Self) void {
        self.player.pause();
        self.player.replaceCurrentItem(null) catch |err| log.warn("item not cleared [{t}]", .{err});
    }

    /// What the player reports, in a line.
    ///
    /// - `observation`: the player's state.
    /// - `idle`: what to say with no item.
    /// - Returns: the line, in the build arena.
    fn describe(observation: ziggui.PlayerObservation, idle: []const u8) []const u8 {
        if (observation.status == .failed) {
            return ziggui.BuildScope.shared().allocator().print("Failed: {s}", .{observation.failure}) catch @panic("oom");
        }
        if (!observation.has_item) return idle;
        return ziggui.BuildScope.shared().allocator().print("{t}, {t}{s}, {d:.1} s buffered, {d}x{d}", .{
            observation.status,
            observation.time_control,
            if (observation.seeking) " (seeking)" else "",
            observation.buffered_seconds,
            observation.presentation_width,
            observation.presentation_height,
        }) catch @panic("oom");
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}

test "media: the state line names a failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();
    try std.testing.expectEqualStrings("Failed: gone", Media.describe(.{ .status = .failed, .failure = "gone" }, "idle"));
}

test "media: the full-screen button fills the window with the player, and puts it back as it was" {
    var media = Media.init(std.testing.allocator);
    defer media.deinit();
    const Window = struct {
        const Self = @This();

        /// Whether the simulated window is in full screen.
        var full_screen: bool = false;

        /// Sets the simulated window's state.
        ///
        /// - `on`: true for full screen.
        fn set(on: bool) void {
            full_screen = on;
        }

        /// Reads the simulated window's state.
        ///
        /// - Returns: true in full screen.
        fn get() bool {
            return full_screen;
        }
    };
    media.set_full_screen_fn = Window.set;
    media.is_full_screen_fn = Window.get;
    media.toggleExpanded();
    try std.testing.expect(media.expanded and Window.full_screen);
    media.syncFullScreen();
    media.toggleExpanded();
    try std.testing.expect(!media.expanded and !Window.full_screen);

    // Left full screen another way (the green button): the player goes back too.
    media.toggleExpanded();
    media.syncFullScreen();
    Window.full_screen = false;
    media.syncFullScreen();
    try std.testing.expect(!media.expanded);

    // Already full screen before: putting the player back keeps it so.
    Window.full_screen = true;
    media.toggleExpanded();
    media.toggleExpanded();
    try std.testing.expect(!media.expanded and Window.full_screen);
}
