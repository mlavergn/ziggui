//! The one live text selection in selectable rich text, and the text ⌘C copies.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_selection);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A byte range in the concatenated span text of the selectable view whose
/// identity is `key`. Views are rebuilt every frame, so the key (the text, its
/// size and its build-order ordinal among views with that text, or an explicit
/// `.selectionId`) is what identifies "the same paragraph".
pub const SelectionSpan = struct {
    const Self = @This();

    /// The selected view's identity (see `TextSelection.keyFor`).
    key: u64,

    /// Where the selection started.
    anchor: usize,

    /// Where it ends now.
    head: usize,

    /// The pointer is still pressed.
    dragging: bool,
};

/// The one live selection in selectable rich text, and the selected text,
/// refreshed whenever its view paints (what ⌘C copies).
pub const TextSelection = struct {
    const Self = @This();

    /// The selection, if any.
    current: ?SelectionSpan = null,

    /// The selected text, as last painted.
    selected_text: std.ArrayList(u8) = .empty,

    /// The process's selection.
    var shared_selection: Self = .{};

    /// The process's text selection.
    ///
    /// - Returns: the shared selection.
    pub fn shared() *Self {
        return &shared_selection;
    }

    /// The text a selectable view shows, hashed: what `BuildScope.selectionOrdinal`
    /// counts views by.
    ///
    /// - `spans`: the view's spans.
    /// - Returns: the hash.
    pub fn contentHash(spans: []const mod.Span) u64 {
        var hasher = std.hash.Wyhash.init(0x5e1);
        for (spans) |span| hasher.update(span.text);
        return hasher.final();
    }

    /// The identity of a selectable view: its explicit `.selectionId` when it
    /// has one, else its text, its size and which of the frame's views with
    /// that text it is, so two identical paragraphs never share a selection.
    ///
    /// - `spans`: the view's spans.
    /// - `pixel_size`: its base size.
    /// - `modifiers`: its modifiers (the ordinal and any explicit id).
    /// - Returns: the hash.
    pub fn keyFor(spans: []const mod.Span, pixel_size: f32, modifiers: *const mod.Modifiers) u64 {
        if (modifiers.selection_id) |id| {
            var hasher = std.hash.Wyhash.init(0x1d5e1);
            hasher.update(std.mem.asBytes(&id));
            return hasher.final();
        }
        var hasher = std.hash.Wyhash.init(0x5e1);
        for (spans) |span| hasher.update(span.text);
        hasher.update(std.mem.asBytes(&pixel_size));
        hasher.update(std.mem.asBytes(&modifiers.selection_ordinal));
        return hasher.final();
    }

    /// The selected text (⌘C), or null when nothing is selected.
    ///
    /// - `self`: the selection.
    /// - Returns: the text, valid until the selected view paints again.
    pub fn selectedText(self: *const Self) ?[]const u8 {
        const span = self.current orelse return null;
        if (span.anchor == span.head or self.selected_text.items.len == 0) return null;
        return self.selected_text.items;
    }

    /// Paints `span`'s highlight over the view `hit` describes and refreshes
    /// the copyable text.
    ///
    /// - `self`: the selection.
    /// - `context`: the paint context.
    /// - `hit`: the selected view's geometry.
    /// - `span`: the selection.
    /// - `canvas`: where it draws.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paint(self: *Self, context: *const mod.Context, hit: *const mod.SelectHit, span: SelectionSpan, canvas: *renderer.Canvas) !void {
        const low = @min(span.anchor, span.head);
        const high = @max(span.anchor, span.head);
        if (low == high) return;
        const color = context.theme.colors.selection.withAlpha(0.35 * context.opacity);
        for (hit.layout.lines) |line| for (line.runs) |run| {
            const base = hit.spanStart(run.span);
            const start = @max(low, base + run.start);
            const end = @min(high, base + run.end);
            if (start >= end) continue;
            const left = hit.origin.x + run.x + hit.runWidth(run, start - base);
            const right = hit.origin.x + run.x + hit.runWidth(run, end - base);
            try canvas.fillRect(.{ .x = left, .y = hit.origin.y + line.y, .width = right - left, .height = line.height }, color);
        };
        // Keep the copyable text current.
        self.selected_text.clearRetainingCapacity();
        var at: usize = 0;
        for (hit.spans) |text_span| {
            const start = std.math.clamp(low, at, at + text_span.text.len);
            const end = std.math.clamp(high, at, at + text_span.text.len);
            if (end > start) self.selected_text.appendSlice(std.heap.page_allocator, text_span.text[start - at .. end - at]) catch |err| log.debug("selection text not copied [{t}]", .{err});
            at += text_span.text.len;
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
