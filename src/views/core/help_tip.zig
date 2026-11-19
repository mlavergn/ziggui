//! The hover hint: a view's `.help(text)` shown in a small label once the
//! pointer has rested on it, as a native tooltip is.

const std = @import("std");
const log = std.log.scoped(.ziggui_help_tip);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A hint offered this frame: its text and the frame of the view it explains.
const Offer = struct {
    const Self = @This();

    /// The hint, in the frame arena.
    text: []const u8,
    /// The view's frame, in points.
    rect: renderer.Rect,
};

/// The hover hint, drawn by ziggui above everything as `ViewRenderer.render`'s
/// last step, so every app gets it from `View.help` alone.
///
/// The painter offers the innermost view under the pointer that has a hint
/// (`offer`); a view behind an open overlay offers nothing (`discard`). The
/// hint shows once the same view has stayed under the pointer for `delay_ms`,
/// asking the loop for that frame through `FrameClock.requestFrameAt` on every
/// frame until it shows, since a still pointer sends no events. It goes when
/// the pointer leaves the view or a button goes down, and never shows headless
/// (the clock reads 0).
pub const HelpTip = struct {
    const Self = @This();

    /// How long the pointer rests on a view before its hint shows, in ms.
    pub const delay_ms: u64 = 600;
    /// The hint's widest line, in points; a longer one is cut.
    const max_width: f32 = 280;
    /// How far below the pointer the hint sits, in points.
    const below_pointer: f32 = 20;

    /// This frame's offer: the innermost hinted view under the pointer.
    offer_now: ?Offer = null,
    /// What the pointer rests on: a hash of the last offer's text and frame.
    resting_key: u64 = 0,
    /// When it came to rest there, in the frame clock's ms.
    resting_since: u64 = 0,
    /// A button went down on it: hidden until the pointer moves to another view.
    pressed: bool = false,

    /// The process's hint.
    var shared_tip: Self = .{};

    /// The process's hover hint.
    ///
    /// - Returns: the shared hint.
    pub fn shared() *Self {
        return &shared_tip;
    }

    /// Forgets the last frame's offer; `ViewRenderer.render` calls it first.
    ///
    /// - `self`: the hint.
    pub fn begin(self: *Self) void {
        self.offer_now = null;
    }

    /// Offers a view's hint: the last offer of a frame (the innermost view) wins.
    ///
    /// - `self`: the hint.
    /// - `text`: the hint, in the frame arena.
    /// - `rect`: the view's frame.
    pub fn offer(self: *Self, text: []const u8, rect: renderer.Rect) void {
        self.offer_now = .{ .text = text, .rect = rect };
    }

    /// Drops this frame's offer: an overlay is drawn over the view that made it.
    ///
    /// - `self`: the hint.
    pub fn discard(self: *Self) void {
        self.offer_now = null;
    }

    /// Hides the hint until the pointer rests on another view: a button went down.
    ///
    /// - `self`: the hint.
    pub fn press(self: *Self) void {
        self.pressed = true;
    }

    /// Whether a hint shows now: what the last `draw` decided.
    ///
    /// - `self`: the hint.
    /// - `now_ms`: the frame clock now.
    /// - Returns: true when this frame's offer has rested long enough.
    pub fn showing(self: *const Self, now_ms: u64) bool {
        if (self.offer_now == null or self.pressed or now_ms == 0) return false;
        return now_ms -| self.resting_since >= delay_ms;
    }

    /// Draws this frame's offer when the pointer has rested on it long enough.
    ///
    /// - `self`: the hint.
    /// - `context`: the paint context; its `hover_point` places the hint.
    /// - `root`: the window's frame, which the hint stays inside.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn draw(self: *Self, context: *const mod.Context, root: renderer.Rect, display_list: *renderer.DisplayList) std.mem.Allocator.Error!void {
        const now = mod.FrameClock.shared().time();
        const found = self.offer_now orelse {
            self.resting_key = 0;
            self.pressed = false;
            return;
        };
        const key = Self.keyOf(found);
        if (key != self.resting_key) {
            self.resting_key = key;
            self.resting_since = now;
            self.pressed = false;
        }
        if (!self.showing(now)) {
            // Asked again every frame until it shows: a request made for another view that the pointer
            // left wakes the loop too early, and this one would then never be asked for.
            if (now != 0 and !self.pressed) mod.FrameClock.shared().requestFrameAt(self.resting_since + delay_ms);
            return;
        }
        const point = context.hover_point orelse return;

        // The build arena is closed by now: reopen it just long enough to make the label.
        const scope = mod.BuildScope.shared();
        const saved_arena = scope.swapAllocator(context.arena);
        defer _ = scope.swapAllocator(saved_arena);
        // Cleaned, and in the app's label color (its token provider), as every other view's text.
        const content = mod.Text(mod.DisplayText.clean(context.arena, found.text)).size(12).foreground(scope.tokens().label).truncated()
            .paddingInsets(.{ .top = 4, .leading = 8, .bottom = 4, .trailing = 8 });
        const size = mod.ViewRenderer.measure(context, content, .{ .width = null, .height = null }) catch |err| {
            log.warn("the hover hint was not drawn [{t}]", .{err});
            return;
        };
        // One line, cut at `max_width`: a hint is a few words.
        const width = @min(size.width, max_width);
        var x = point.x;
        if (x + width > root.maxX()) x = root.maxX() - width;
        if (x < root.x) x = root.x;
        // Below the pointer, or above it when it would run off the bottom.
        var y = point.y + below_pointer;
        if (y + size.height > root.maxY()) y = point.y - below_pointer / 2 - size.height;
        if (y < root.y) y = root.y;
        const target = renderer.Rect{ .x = x, .y = y, .width = width, .height = size.height };
        try context.theme.painter.panel(context.surface(display_list), target, @min(context.theme.metrics.corner_radius, 6), .popover);
        try mod.ViewRenderer.renderInto(context, content, target, display_list);
    }

    /// A hash of an offer's text and frame: the same view, offered frame after frame.
    ///
    /// - `found`: the offer.
    /// - Returns: its hash.
    fn keyOf(found: Offer) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(found.text);
        hasher.update(std.mem.asBytes(&found.rect));
        // Zero means "resting on nothing".
        return hasher.final() | 1;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(HelpTip);
}

test "help tip shows once the pointer rests on one view, and goes on a press or another view" {
    var tip: HelpTip = .{};
    const clock = mod.FrameClock.shared();
    const saved = clock.time();
    defer clock.setTime(saved);
    const rect = renderer.Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };

    // Headless, the clock reads 0: never.
    tip.offer("Upload…", rect);
    try std.testing.expect(!tip.showing(0));

    // `draw` notes when the pointer came to rest; without a context it is driven by hand here.
    clock.setTime(1000);
    tip.resting_key = HelpTip.keyOf(.{ .text = "Upload…", .rect = rect });
    tip.resting_since = 1000;
    try std.testing.expect(!tip.showing(1000 + HelpTip.delay_ms - 1));
    try std.testing.expect(tip.showing(1000 + HelpTip.delay_ms));
    tip.press();
    try std.testing.expect(!tip.showing(5000));
    tip.begin();
    try std.testing.expect(!tip.showing(5000));
    // Another view's text or frame is another rest.
    try std.testing.expect(HelpTip.keyOf(.{ .text = "Download…", .rect = rect }) != tip.resting_key);
}
