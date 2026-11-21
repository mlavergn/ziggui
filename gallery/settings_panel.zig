const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_settings_panel);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// Where the General page opens files.
const open_options = [_][]const u8{ "New window", "Current window" };

/// The Editing page's indent widths.
const indent_options = [_][]const u8{ "2 spaces", "4 spaces", "Tabs" };

/// The Advanced page's log levels.
const log_options = [_][]const u8{ "Errors", "Warnings", "Info", "Debug" };

/// The Settings panel: an app's settings, as `ziggui.Settings` draws them,
/// shown in place and presented in a sheet, and the state its pages bind to.
pub const SettingsPanel = struct {
    const Self = @This();

    /// The selected page.
    tab: ziggui.State(i64),

    /// Whether the settings are presented in a sheet.
    show_sheet: ziggui.State(bool),

    /// General: reopen the last session's windows.
    reopen: ziggui.State(bool),

    /// General: check for updates.
    check_updates: ziggui.State(bool),

    /// General: include beta releases (only while checking for updates).
    beta_updates: ziggui.State(bool),

    /// General: the appearance, a `ziggui.Appearance`'s index.
    appearance: ziggui.State(i64),

    /// General: where files open (`open_options`).
    open_in: ziggui.State(i64),

    /// General: send anonymous crash reports.
    crash_reports: ziggui.State(bool),

    /// Editing: show line numbers.
    line_numbers: ziggui.State(bool),

    /// Editing: wrap long lines.
    wrap_lines: ziggui.State(bool),

    /// Editing: the indent width (`indent_options`).
    indent: ziggui.State(i64),

    /// Editing: trim trailing spaces on save.
    trim_spaces: ziggui.State(bool),

    /// Advanced: the log level (`log_options`).
    log_level: ziggui.State(i64),

    /// Advanced: draw with the GPU.
    gpu: ziggui.State(bool),

    /// Constructs the panel's state, on the General page.
    ///
    /// - `allocator`: allocator for the states.
    /// - Returns: the panel.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .tab = ziggui.State(i64).init(allocator, 0),
            .show_sheet = ziggui.State(bool).init(allocator, false),
            .reopen = ziggui.State(bool).init(allocator, true),
            .check_updates = ziggui.State(bool).init(allocator, true),
            .beta_updates = ziggui.State(bool).init(allocator, false),
            .appearance = ziggui.State(i64).init(allocator, 0),
            .open_in = ziggui.State(i64).init(allocator, 0),
            .crash_reports = ziggui.State(bool).init(allocator, false),
            .line_numbers = ziggui.State(bool).init(allocator, true),
            .wrap_lines = ziggui.State(bool).init(allocator, false),
            .indent = ziggui.State(i64).init(allocator, 1),
            .trim_spaces = ziggui.State(bool).init(allocator, true),
            .log_level = ziggui.State(i64).init(allocator, 1),
            .gpu = ziggui.State(bool).init(allocator, true),
        };
        return self;
    }

    /// Releases the panel's state.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.gpu.deinit();
        self.log_level.deinit();
        self.trim_spaces.deinit();
        self.indent.deinit();
        self.wrap_lines.deinit();
        self.line_numbers.deinit();
        self.crash_reports.deinit();
        self.open_in.deinit();
        self.appearance.deinit();
        self.beta_updates.deinit();
        self.check_updates.deinit();
        self.reopen.deinit();
        self.show_sheet.deinit();
        self.tab.deinit();
    }

    /// The Settings panel: the settings drawn as a window would show them,
    /// and a button that presents them in a sheet. Their theme and accent are
    /// the gallery's own, so a choice there redraws the whole window.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - `family`: the gallery's theme family, its index in `ziggui.ThemeFamily.all`.
    /// - `accent`: the gallery's accent, its choice index (`ziggui.Accent.atChoice`).
    /// - Returns: the panel's view.
    pub fn panel(self: *Self, theme: ziggui.Theme, family: ziggui.Binding(i64), accent: ziggui.Binding(i64)) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        const window = self.settings(family, accent)
            .frameWidth(500)
            .background(theme.colors.window_background)
            .cornerRadius(10)
            .border(theme.colors.separator, theme.metrics.hairline);
        // Built only while presented: the settings are a whole tree of forms.
        const sheet = if (self.show_sheet.get()) ziggui.VStack(.{
            self.settings(family, accent),
            ziggui.HStack(.{
                ziggui.Spacer(),
                ziggui.ButtonRoled("Done", .prominent, ziggui.Callback.init(Self, self, Self.closeSheet)),
            }).paddingInsets(.{ .leading = 20, .bottom = 16, .trailing = 20 }),
        }).spacing(0).frameWidth(500) else ziggui.Empty();
        return ziggui.VStack(.{
            ziggui.HStack(.{ ziggui.Spacer(), window, ziggui.Spacer() }).frameMaxWidth(),
            gallery.CardName.shared().view("ziggui.Settings · ziggui.Form · ziggui.Section · ziggui.LabeledContent · ziggui.Toggle · ziggui.AppearancePicker · ziggui.ThemePicker", tokens.secondary_label),
            ziggui.HStack(.{
                ziggui.Button("Present in a sheet", ziggui.Callback.init(Self, self, Self.openSheet)),
                ziggui.Spacer(),
            }).sheet(self.show_sheet.binding(), sheet),
        }).spacing(12);
    }

    /// The settings: General, Editing and Advanced pages.
    ///
    /// - `self`: the panel.
    /// - `family`: the theme family's index, for the General page's theme picker.
    /// - `accent`: the accent's choice index, for the same picker.
    /// - Returns: the settings view.
    fn settings(self: *Self, family: ziggui.Binding(i64), accent: ziggui.Binding(i64)) ziggui.View {
        const tabs = ziggui.BuildScope.shared().allocator().dupe(ziggui.Tab, &.{
            .{ .label = "General", .icon = .settings, .content = self.generalPage(family, accent) },
            .{ .label = "Editing", .icon = .pencilLine, .content = self.editingPage() },
            .{ .label = "Advanced", .icon = .slidersHorizontal, .content = self.advancedPage() },
        }) catch @panic("oom");
        return ziggui.Settings(self.tab.binding(), tabs);
    }

    /// The General page.
    ///
    /// - `self`: the panel.
    /// - `family`: the theme family's index, for the theme picker.
    /// - `accent`: the accent's choice index, for the theme picker.
    /// - Returns: the page.
    fn generalPage(self: *Self, family: ziggui.Binding(i64), accent: ziggui.Binding(i64)) ziggui.View {
        return ziggui.Form(.{
            ziggui.Section(.{
                ziggui.LabeledContent("Startup:", ziggui.VStack(.{
                    ziggui.Toggle("Reopen windows from the last session", self.reopen.binding()),
                    Self.help("Documents open when you quit open again, where they were."),
                }).spacing(4).alignment(.leading)),
                ziggui.LabeledContent("Updates:", ziggui.VStack(.{
                    ziggui.Toggle("Check for updates automatically", self.check_updates.binding()),
                    ziggui.Toggle("Include beta releases", self.beta_updates.binding()).disabled(!self.check_updates.get()),
                }).spacing(8).alignment(.leading)),
            }),
            ziggui.Section(.{
                ziggui.LabeledContent("Appearance:", ziggui.VStack(.{
                    ziggui.AppearancePicker(self.appearance.binding()),
                    Self.help(self.appearanceHelp()),
                }).spacing(4).alignment(.leading)),
                ziggui.LabeledContent("Theme:", ziggui.ThemePicker(family, accent)),
                ziggui.LabeledContent("Open files in:", ziggui.Picker(self.open_in.binding(), &open_options)),
            }),
            ziggui.Section(.{
                ziggui.LabeledContent("", ziggui.VStack(.{
                    ziggui.Toggle("Send anonymous crash reports", self.crash_reports.binding()),
                    Self.help("Reports hold no file names or contents."),
                }).spacing(4).alignment(.leading)),
            }),
        });
    }

    /// What the chosen appearance draws in (`Appearance.resolved`), the
    /// window's own scheme standing in for the system's.
    ///
    /// - `self`: the panel.
    /// - Returns: the help line, in the build arena.
    fn appearanceHelp(self: *const Self) []const u8 {
        const appearance = ziggui.Appearance.at(self.appearance.get());
        const system = ziggui.BuildScope.shared().theme().scheme;
        const scheme = appearance.resolved(system);
        const name = if (scheme == .dark) "dark" else "light";
        const allocator = ziggui.BuildScope.shared().allocator();
        return (if (appearance == .automatic)
            allocator.print("Follows the system: draws {s} now.", .{name})
        else
            allocator.print("Always draws {s}.", .{name})) catch @panic("oom");
    }

    /// The Editing page.
    ///
    /// - `self`: the panel.
    /// - Returns: the page.
    fn editingPage(self: *Self) ziggui.View {
        return ziggui.Form(.{
            ziggui.Section(.{
                ziggui.LabeledContent("Show:", ziggui.VStack(.{
                    ziggui.Toggle("Line numbers", self.line_numbers.binding()),
                    ziggui.Toggle("Wrap long lines", self.wrap_lines.binding()),
                }).spacing(8).alignment(.leading)),
                ziggui.LabeledContent("Indent with:", ziggui.Picker(self.indent.binding(), &indent_options)),
            }),
            ziggui.Section(.{
                ziggui.LabeledContent("On save:", ziggui.Toggle("Trim trailing spaces", self.trim_spaces.binding())),
            }),
        });
    }

    /// The Advanced page.
    ///
    /// - `self`: the panel.
    /// - Returns: the page.
    fn advancedPage(self: *Self) ziggui.View {
        return ziggui.Form(.{
            ziggui.Section(.{
                ziggui.LabeledContent("Log level:", ziggui.Picker(self.log_level.binding(), &log_options)),
                ziggui.LabeledContent("Rendering:", ziggui.VStack(.{
                    ziggui.Toggle("Draw with the GPU", self.gpu.binding()),
                    Self.help("Off, the window draws in software: slower, the same pixels."),
                }).spacing(4).alignment(.leading)),
            }),
        });
    }

    /// Presents the settings in a sheet.
    ///
    /// - `self`: the panel.
    fn openSheet(self: *Self) void {
        self.show_sheet.set(true);
    }

    /// Dismisses the sheet.
    ///
    /// - `self`: the panel.
    fn closeSheet(self: *Self) void {
        self.show_sheet.set(false);
    }

    /// A control's help: smaller and secondary, under it.
    ///
    /// - `text`: the help.
    /// - Returns: the view.
    fn help(text: []const u8) ziggui.View {
        return ziggui.Text(text).font(.callout).foreground(ziggui.BuildScope.shared().tokens().secondary_label);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}

test "settings panel: the sheet opens and closes" {
    var panel = SettingsPanel.init(std.testing.allocator);
    defer panel.deinit();
    panel.openSheet();
    try std.testing.expect(panel.show_sheet.get());
    panel.closeSheet();
    try std.testing.expect(!panel.show_sheet.get());
}

test "settings panel: beta releases are offered only while updates are checked" {
    var panel = SettingsPanel.init(std.testing.allocator);
    defer panel.deinit();
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var family = ziggui.State(i64).init(std.testing.allocator, 0);
    defer family.deinit();
    var accent = ziggui.State(i64).init(std.testing.allocator, 0);
    defer accent.deinit();
    for ([_]bool{ true, false }) |checking| {
        panel.check_updates.set(checking);
        window.begin(ziggui.MacosTheme.light);
        const view = panel.settings(family.binding(), accent.binding());
        window.end();
        var frame = try window.render(view, 500, 420);
        defer frame.deinit();
        // The General page's toggles in order: reopen, check, beta, crash reports.
        var toggles: usize = 0;
        for (window.hits.items) |hit| {
            if (hit.action != .toggle) continue;
            if (toggles == 2) try std.testing.expectEqual(!checking, hit.disabled);
            toggles += 1;
        }
        try std.testing.expectEqual(@as(usize, 4), toggles);
    }
}

test "settings panel: the appearance's help says what it draws in" {
    var panel = SettingsPanel.init(std.testing.allocator);
    defer panel.deinit();
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(ziggui.MacosTheme.dark);
    defer window.end();
    try std.testing.expectEqualStrings("Follows the system: draws dark now.", panel.appearanceHelp());
    panel.appearance.set(1);
    try std.testing.expectEqualStrings("Always draws light.", panel.appearanceHelp());
}
