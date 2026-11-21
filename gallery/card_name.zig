//! The line under each gallery card naming what it shows (`ziggui.KeyCap`):
//! selectable, with a button after it that copies the names to the clipboard.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_card_name);
const ziggui = @import("ziggui");

/// What one names line's copy button copies: its names, and the gallery's
/// card names state that copies them.
const CopyRequest = struct {
    const Self = @This();

    /// The card names state that does the copying.
    card_name: *CardName,
    /// The names to copy; kept by the frame that drew the button.
    names: []const u8,

    /// Copies the names (a tap on the copy button).
    ///
    /// - `self`: the request.
    fn copy(self: *Self) void {
        self.card_name.copy(self.names);
    }
};

/// Where names lines are collected while the gallery's tests check its
/// search index against what each section draws.
pub const CardNameRecording = struct {
    const Self = @This();

    /// The lines drawn, each as written (`"ziggui.Badge · .mono()"`); they
    /// live as long as the frame that drew them.
    lines: *std.ArrayList([]const u8),
    /// Owns the list's growth.
    allocator: std.mem.Allocator,
};

/// The card names lines and their copy buttons. One per process (`shared`):
/// every panel draws its cards' names through it, and `main.zig` gives it the
/// clipboard.
pub const CardName = struct {
    const Self = @This();

    /// The copy icon's size, in points: a caption's.
    const icon_size: f32 = 11;

    /// Puts text on the system clipboard; `main.zig` fills it from
    /// `ziggui.Clipboard`, and headless it stays null.
    ///
    /// - `text`: the text to copy.
    copy_fn: ?*const fn (text: []const u8) void = null,

    /// A hash of the names copied last, so their button shows a check; 0
    /// before any copy.
    copied: u64 = 0,

    /// Collects every names line drawn while set (the gallery's tests); null otherwise.
    recording: ?CardNameRecording = null,

    /// The process's card names state.
    var shared_card_name: Self = .{};

    /// The process's card names state.
    ///
    /// - Returns: the shared state.
    pub fn shared() *Self {
        return &shared_card_name;
    }

    /// A names line: the names in caption mono, selectable (so a drag picks a
    /// part of them and ⌘C copies it), and a copy button after them that
    /// copies them all, showing a check once it has.
    ///
    /// - `self`: the card names state.
    /// - `names`: the names, as code writes them; kept until the frame renders.
    /// - `color`: the names' color.
    /// - Returns: the line, as wide as it is offered, the names at its leading edge.
    pub fn view(self: *Self, names: []const u8, color: ziggui.Color) ziggui.View {
        if (self.recording) |recording| recording.lines.append(recording.allocator, names) catch @panic("oom");
        const request = ziggui.BuildScope.shared().allocator().create(CopyRequest) catch @panic("oom");
        request.* = .{ .card_name = self, .names = names };
        const copied = self.copied != 0 and self.copied == Self.hash(names);
        return ziggui.HStack(.{
            ziggui.WrappedText(names).font(.caption).mono().foreground(color).selectable(),
            ziggui.Icon(if (copied) .copyCheck else .copy, icon_size, color)
                .padding(2)
                .onTap(ziggui.Callback.init(CopyRequest, request, CopyRequest.copy))
                .help(if (copied) "Copied" else "Copy")
                .accessibilityLabel("Copy names")
                .accessibilityAddTraits(.{ .is_button = true }),
            ziggui.Spacer(),
        }).spacing(4).frameMaxWidth();
    }

    /// Copies names to the clipboard, if there is one, and notes them so
    /// their button shows a check.
    ///
    /// - `self`: the card names state.
    /// - `names`: the names.
    pub fn copy(self: *Self, names: []const u8) void {
        if (self.copy_fn) |hook| hook(names);
        self.copied = Self.hash(names);
    }

    /// The hash names are noted by.
    ///
    /// - `names`: the names.
    /// - Returns: their hash, never 0.
    fn hash(names: []const u8) u64 {
        return std.hash.Wyhash.hash(0, names) | 1;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(CardName);
    // Nothing here does I/O to trace.
    _ = log;
}

test "a names line's button copies its names and then shows a check" {
    const Probe = struct {
        const Self = @This();

        /// Whether the clipboard was handed "ziggui.KeyCap".
        var copied_key_cap = false;

        /// Notes what the clipboard was handed.
        ///
        /// - `text`: the text.
        fn copy(text: []const u8) void {
            Self.copied_key_cap = std.mem.eql(u8, text, "ziggui.KeyCap");
        }
    };
    var card_name: CardName = .{ .copy_fn = Probe.copy };
    const window = try ziggui.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(ziggui.MacosTheme.light);
    const line = card_name.view("ziggui.KeyCap", ziggui.Color.black);
    window.end();
    var frame = try window.render(line, 300, 30);
    defer frame.deinit();

    // The copy button is the line's one tap region.
    try std.testing.expectEqual(@as(usize, 1), window.hits.items.len);
    const button = window.hits.items[0].rect;
    try std.testing.expect(window.tap(.{ .x = button.midX(), .y = button.midY() }));
    try std.testing.expect(Probe.copied_key_cap);
    try std.testing.expectEqual(CardName.hash("ziggui.KeyCap"), card_name.copied);

    // Headless, a copy still marks the names as copied.
    var headless: CardName = .{};
    headless.copy("ziggui.Badge");
    try std.testing.expectEqual(CardName.hash("ziggui.Badge"), headless.copied);
}
