const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_media);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The sample the Video panel plays: Apple's public HLS example (10 minutes,
/// fMP4, an English audio rendition and two subtitle ones). Fetched only when
/// "Load sample stream" is pressed.
const sample_url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8";

/// The Video panel: a `VideoPlayer` with controls drawn over the picture, the
/// buttons that load and clear its item, and what the player reports.
pub const Media = struct {
    const Self = @This();

    /// Owns the player and the subtitle lists a tap reads.
    allocator: std.mem.Allocator,

    /// The panel's player.
    player: ziggui.Player,

    /// The standard controls' state.
    controls: ziggui.VideoPlayerControlsState = .{},

    /// Whether the player fills the window alone (the controls' full-screen button).
    expanded: bool = false,

    /// Takes the window into full screen (true) or out of it; `main.zig`
    /// sets it, null headless.
    set_full_screen_fn: ?*const fn (bool) void = null,

    /// Reports whether the window is in full screen; `main.zig` sets it,
    /// null headless.
    is_full_screen_fn: ?*const fn () bool = null,

    /// Whether the window was in full screen before the player filled it,
    /// which it goes back to.
    full_screen_before: bool = false,

    /// Whether the window has been seen in full screen since the player
    /// filled it: the system's transition takes a moment to report.
    full_screen_seen: bool = false,

    /// The Native View panel's platform view: an `NSView` `main.zig` makes on
    /// macOS; null headless and elsewhere, where the panel shows the placeholder.
    native_sample: ?*anyopaque = null,

    /// Constructs the panel's player, with no item.
    ///
    /// - `allocator`: allocator for the player; must outlive the panel.
    /// - Returns: the panel.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator, .player = ziggui.Player.init(allocator) };
        return self;
    }

    /// Stops and frees the player.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.player.deinit();
    }

    /// The Video panel: the picture with the standard controls over it, the
    /// item's buttons, and the player's state.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn videoPanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const observation = self.player.observe();
        return ziggui.VStack(.{
            Self.card(theme, "VideoPlayer: the platform player draws the picture, ziggui the controls over it", "ziggui.VideoPlayer · ziggui.VideoPlayerControls · ziggui.Player", self.picture(8).frameHeight(300)),
            ziggui.HStack(.{
                ziggui.Button("Load sample stream", ziggui.Callback.init(Self, self, Self.loadSample)),
                ziggui.Button("Clear", ziggui.Callback.init(Self, self, Self.clear)),
                ziggui.Spacer(),
            }).spacing(8).frameMaxWidth(),
            Self.leading(ziggui.Text(Self.describe(observation)).foreground(ziggui.BuildScope.shared().tokens().secondary_label).truncated()),
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

    /// The Native View panel: an app-made platform view placed by layout,
    /// with ziggui text above and below it.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn nativePanel(self: *Self, theme: ziggui.Theme) ziggui.View {
        const secondary = ziggui.BuildScope.shared().tokens().secondary_label;
        return ziggui.VStack(.{
            Self.card(theme, "NativeView: the app's platform view, placed and clipped where layout puts it", "ziggui.NativeView", ziggui.NativeView(self.native_sample).cornerRadius(8).frameHeight(220)),
            Self.leading(ziggui.Text("It sits over the window's surface, so it hides while a sheet, alert, popover or menu is open.").foreground(secondary).truncated()),
            Self.leading(ziggui.Text("A view that takes the keyboard (a web view) gets it on a click; a click elsewhere gives it back.").foreground(secondary).truncated()),
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

    /// Plays the sample stream from its start.
    ///
    /// - `self`: the panel.
    fn loadSample(self: *Self) void {
        self.player.replaceCurrentItem(sample_url) catch |err| log.warn("sample not loaded [{t}]", .{err});
        self.player.play();
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
    /// - Returns: the line, in the build arena.
    fn describe(observation: ziggui.PlayerObservation) []const u8 {
        if (observation.status == .failed) {
            return ziggui.BuildScope.shared().allocator().print("Failed: {s}", .{observation.failure}) catch @panic("oom");
        }
        if (!observation.has_item) return "No item. Load sample stream plays Apple's HLS example (over the network).";
        return ziggui.BuildScope.shared().allocator().print("{t}, {t}{s}, {d:.1} s buffered, {d}x{d}", .{
            observation.status,
            observation.time_control,
            if (observation.seeking) " (seeking)" else "",
            observation.buffered_seconds,
            observation.presentation_width,
            observation.presentation_height,
        }) catch @panic("oom");
    }

    /// A titled group on the secondary background, the code names it shows
    /// under it, as the other panels draw.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the group's heading.
    /// - `names`: what it shows, as code names it (`ziggui.Table`), drawn under it.
    /// - `content`: the group's contents.
    /// - Returns: the group's view.
    fn card(theme: ziggui.Theme, title: []const u8, names: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            Self.leading(ziggui.Text(title).font(.headline)),
            ziggui.VStack(.{
                ziggui.StackBuilder.make(.vertical, 0, .leading, .{content})
                    .frameMaxWidth()
                    .padding(14)
                    .background(theme.colors.secondary_background)
                    .cornerRadius(theme.metrics.corner_radius)
                    .frameMaxWidth(),
                Self.leading(ziggui.Text(names).font(.caption).mono().foreground(theme.colors.secondary_label)),
            }).spacing(4).frameMaxWidth(),
        }).spacing(8).frameMaxWidth();
    }

    /// Pins `view` to the leading edge of a full-width row.
    ///
    /// - `view`: the view.
    /// - Returns: the row.
    fn leading(view: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ view, ziggui.Spacer() }).frameMaxWidth();
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
    try std.testing.expectEqualStrings("Failed: gone", Media.describe(.{ .status = .failed, .failure = "gone" }));
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
