//! Paints the text views: rich and wrapped paragraphs, text fields and editors.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_view_painter);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A tapped link span's URL, in the frame arena.
const LinkTarget = struct {
    const Self = @This();

    /// The URL.
    url: []const u8,

    /// The link region's tap: hands the URL to the app's link handler.
    ///
    /// - `context`: the `LinkTarget`.
    fn open(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        mod.BuildScope.shared().openLink(self.url);
    }
};

/// Paints text views into their laid-out rects, and the carets, selections,
/// links and click regions that make them work.
pub const TextViewPainter = struct {
    const Self = @This();

    /// Paints a rich paragraph: each run in its span's face and color, with
    /// backgrounds, underlines, strikes, link regions and (when selectable) the
    /// selection.
    ///
    /// - `context`: the context.
    /// - `view`: the paragraph's view (its modifiers).
    /// - `rich`: the paragraph.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintRichText(context: *const mod.Context, view: mod.View, rich: mod.RichTextData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const pixel_size = context.resolvedFontSize(view);
        const faces = context.richFaces();
        const laid_out = try mod.BuildScope.shared().layoutRich(context.arena, rich.spans, faces, pixel_size, rich.line_multiple, rect.width, rich.preformatted);
        if (view.modifiers.selectable) {
            // Before the link regions, so a link still takes its own click.
            const hit = try context.arena.create(mod.SelectHit);
            hit.* = .{ .key = mod.TextSelection.keyFor(rich.spans, pixel_size, &view.modifiers), .origin = rect.origin(), .layout = laid_out, .spans = rich.spans, .faces = faces, .pixel_size = pixel_size, .scale = context.scale };
            try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .textSelect = hit }, .disabled = context.disabled });
            const selection = mod.TextSelection.shared();
            if (selection.current) |span| if (span.key == hit.key) try selection.paint(context, hit, span, canvas);
        }
        for (laid_out.lines) |line| {
            const baseline = rect.y + line.y + line.baseline;
            for (line.runs) |run| {
                const span = rich.spans[run.span];
                const face = faces.forSpan(span);
                const span_size = pixel_size * span.size_scale;
                const line_height = renderer.TextShaper.init(face).lineHeight(span_size);
                const ascent = renderer.TextShaper.init(face).ascentPixels(span_size);
                const x = rect.x + run.x;
                if (span.background) |background| try canvas.fillRoundedRect(.{ .x = x - 2, .y = baseline - ascent, .width = run.width + 4, .height = line_height }, 4, background.multiplyAlpha(opacity));
                const color = (span.color orelse if (span.link != null) context.theme.colors.accent else context.foreground).multiplyAlpha(opacity);
                const cache = faces.cacheFor(span) orelse context.cache;
                const piece = span.text[run.start..run.end];
                if (context.scale == 1) {
                    try renderer.TextPainter.shared().drawText(canvas, cache, piece, span_size, color, .{ .x = x, .y = baseline - ascent });
                } else {
                    try renderer.TextPainter.shared().drawTextScaled(canvas, cache, piece, span_size, context.scale, color, .{ .x = x, .y = baseline - ascent });
                }
                if (span.underline or span.link != null) try canvas.fillRect(.{ .x = x, .y = baseline + 1.5, .width = run.width, .height = 1 }, color);
                if (span.strike) try canvas.fillRect(.{ .x = x, .y = baseline - ascent * 0.35, .width = run.width, .height = 1 }, color);
                if (span.link) |url| {
                    const target = try context.arena.create(LinkTarget);
                    target.* = .{ .url = url };
                    try context.hit_regions.append(context.arena, .{
                        .rect = .{ .x = x, .y = baseline - ascent, .width = run.width, .height = line_height },
                        .action = .{ .callback = .{ .context = target, .function = LinkTarget.open } },
                        .disabled = context.disabled,
                    });
                }
            }
        }
    }

    /// Paints wrapped text: re-wraps to the laid-out rect width and draws each
    /// line, stacked by line height, top-aligned within `rect`.
    ///
    /// - `context`: the context.
    /// - `view`: the text's view (its modifiers).
    /// - `wrapped`: the text.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintWrappedText(context: *const mod.Context, view: mod.View, wrapped: mod.WrappedTextData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const pixel_size = context.resolvedFontSize(view);
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        const color = context.foreground.multiplyAlpha(opacity);
        const lines = mod.BuildScope.shared().wrapText(context.arena, context.cache.face, wrapped.string, pixel_size, rect.width);
        for (lines, 0..) |line, index| {
            const slice = wrapped.string[line.start..line.end];
            const y = rect.y + @as(f32, @floatFromInt(index)) * line_height;
            context.drawText(canvas, slice, pixel_size, color, .{ .x = rect.x, .y = y }) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
    }

    /// Paints a one-line text field: the theme's input surface, the selection,
    /// the text or placeholder, the caret, and a click region.
    ///
    /// - `context`: the context.
    /// - `view`: the field's view (its modifiers).
    /// - `field`: the field.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintTextField(context: *const mod.Context, view: mod.View, field: mod.TextFieldData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const metrics = context.theme.metrics;
        // Honor an explicit `.cornerRadius(...)` so fields can be pill-shaped; fall
        // back to the theme's control radius.
        const radius = if (view.modifiers.corner_radius > 0) view.modifiers.corner_radius else metrics.control_corner_radius;
        const focused = field.state.focused;
        // Keep the focused field's submit callback current so `Focus.submit` (fired
        // from the event loop on Enter) can reach it without the view tree.
        if (focused) field.state.on_submit = view.modifiers.on_submit;
        // The theme draws the input surface (background + border).
        if (!view.modifiers.chromeless) try context.theme.painter.field(context.surface(canvas), rect, radius, .{ .focused = focused });

        const pixel_size = context.theme.typography.body.size;
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        // Inset text past the corner curve (more for pills).
        const inset: f32 = @max(8, @min(radius, 14));
        const text_y = mod.ControlPainter.verticalCenter(rect, line_height);
        const real = field.state.text();
        var content = real;
        if (view.modifiers.secure) {
            const count = std.unicode.utf8CountCodepoints(real) catch real.len;
            const dots = try context.arena.alloc(u8, count * 3);
            for (0..count) |index| @memcpy(dots[index * 3 ..][0..3], "\u{2022}");
            content = dots;
        }
        const secure = view.modifiers.secure;

        // Selection highlight, drawn behind the text so the glyphs stay readable.
        if (focused and !secure) {
            if (field.state.selectionRange()) |selection| {
                const highlight_start = rect.x + inset + renderer.TextShaper.init(context.cache.face).measureLineWidth(content[0..selection.start], pixel_size);
                const highlight_end = rect.x + inset + renderer.TextShaper.init(context.cache.face).measureLineWidth(content[0..selection.end], pixel_size);
                try canvas.fillRect(.{ .x = highlight_start, .y = text_y, .width = @max(1, highlight_end - highlight_start), .height = line_height }, context.theme.colors.selection.multiplyAlpha(opacity));
            }
        }

        if (content.len == 0 and field.placeholder.len > 0) {
            context.drawText(canvas, field.placeholder, pixel_size, context.theme.colors.tertiary_label.multiplyAlpha(opacity), .{ .x = rect.x + inset, .y = text_y }) catch |err| log.debug("text not drawn [{t}]", .{err});
        } else {
            context.drawText(canvas, content, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x + inset, .y = text_y }) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
        // caret
        if (focused and mod.Focus.shared().caretVisible()) {
            const caret_at = if (secure) (std.unicode.utf8CountCodepoints(real[0..field.state.caret]) catch field.state.caret) * 3 else field.state.caret;
            const caret_x = rect.x + inset + renderer.TextShaper.init(context.cache.face).measureLineWidth(content[0..caret_at], pixel_size);
            try canvas.line(.{ .x = caret_x, .y = text_y + 2 }, .{ .x = caret_x, .y = text_y + line_height - 2 }, 1, context.theme.colors.accent.multiplyAlpha(opacity));
        }
        // A `textClick` region (not a bare `.focus`) so a single-line field also
        // supports click-to-place-caret, drag-selection, and double-click word
        // selection — its one line starts at the text origin with no scroll.
        try context.hit_regions.append(context.arena, .{
            .rect = rect,
            .action = if (secure) .{ .focus = field.state } else .{ .textClick = .{
                .state = field.state,
                .face = context.cache.face,
                .pixel_size = pixel_size,
                .origin = .{ .x = rect.x + inset, .y = text_y },
                .scroll_y = 0,
                .line_height = line_height,
            } },
            .disabled = context.disabled,
        });
    }

    /// Paints a multi-line editor: rounded background + focus border, a line-number
    /// gutter, selection highlight, the visible lines (vertically scrolled by the
    /// `ScrollState`), and the caret. Auto-scrolls to keep the caret visible only
    /// when it moved (so the wheel can scroll freely otherwise), registers a
    /// `ScrollRegion` for the wheel, and a `textClick` hit region for click-to-
    /// position-caret.
    ///
    /// - `context`: the context.
    /// - `view`: the editor's view (its modifiers).
    /// - `editor`: the editor.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintTextEditor(context: *const mod.Context, view: mod.View, editor: mod.TextEditorData, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const state = editor.state;
        state.multiline = true;
        const opacity = context.opacity;
        const metrics = context.theme.metrics;
        const pixel_size = context.resolvedFontSize(view);
        const face = context.cache.face;
        const line_height = renderer.TextShaper.init(face).lineHeight(pixel_size);
        const focused = state.focused;
        const caret_on = mod.Focus.shared().caretVisible();

        const radius = if (view.modifiers.corner_radius > 0) view.modifiers.corner_radius else metrics.control_corner_radius;
        // The theme draws the editor surface (background + border).
        if (!view.modifiers.chromeless) try context.theme.painter.field(context.surface(canvas), rect, radius, .{ .focused = focused });

        const text = state.text();
        const line_count = mod.TextLines.init(text).lineCount();

        const inset: f32 = view.modifiers.editor_padding orelse 8;
        const gutter_width: f32 = if (editor.line_numbers) Self.gutterWidth(face, pixel_size, line_count, inset) else inset;
        const text_x = rect.x + gutter_width + inset;
        const top = rect.y + inset;
        const view_height = @max(0, rect.height - 2 * inset);

        // Soft-wrap mode (prose/prompt inputs): render visual wrapped rows instead of
        // one row per logical line, so long text wraps to the width and stays visible
        // (no horizontal scroll). Disabled when line numbers are on (code editor).
        if (view.modifiers.soft_wrap and !editor.line_numbers) {
            const wrap_width = @max(1, rect.x + rect.width - inset - text_x);
            const rows = try Self.editorRows(context.arena, mod.BuildScope.shared().wrapText(context.arena, face, text, pixel_size, wrap_width), text);
            const row_count = rows.len;

            editor.scroll.content_height = @as(f32, @floatFromInt(row_count)) * line_height;
            editor.scroll.viewport_height = view_height;

            var caret_row: usize = if (row_count > 0) row_count - 1 else 0;
            for (rows, 0..) |row, index| {
                if (state.caret <= row.end) {
                    caret_row = index;
                    break;
                }
            }
            if (state.caret != state.last_caret) {
                const caret_y = @as(f32, @floatFromInt(caret_row)) * line_height;
                if (caret_y < editor.scroll.offset) {
                    editor.scroll.offset = caret_y;
                } else if (caret_y + line_height > editor.scroll.offset + view_height) {
                    editor.scroll.offset = caret_y + line_height - view_height;
                }
                state.last_caret = state.caret;
            }
            editor.scroll.offset = std.math.clamp(editor.scroll.offset, 0, editor.scroll.maxOffset());
            const offset = editor.scroll.offset;

            const foreground = context.foreground.multiplyAlpha(opacity);
            const selection_color = context.theme.colors.selection.multiplyAlpha(opacity);
            const selection = state.selectionRange();

            try canvas.pushClip(rect.insetBy(2, 2), 0);
            if (text.len == 0 and view.modifiers.editor_placeholder.len > 0) {
                const hint = view.modifiers.editor_placeholder;
                const hint_color = context.theme.colors.secondary_label.multiplyAlpha(opacity);
                for (mod.BuildScope.shared().wrapText(context.arena, face, hint, pixel_size, wrap_width), 0..) |row, index|
                    Self.drawEditorLine(context, canvas, hint[row.start..row.end], pixel_size, hint_color, .{ .x = text_x, .y = top + @as(f32, @floatFromInt(index)) * line_height });
            }
            for (rows, 0..) |row, index| {
                const y = top - offset + @as(f32, @floatFromInt(index)) * line_height;
                if (y + line_height < top or y > top + view_height) continue;
                if (selection) |range| {
                    if (range.start <= row.end and range.end >= row.start) {
                        const start = @max(range.start, row.start);
                        const end = @min(range.end, row.end);
                        const highlight_start = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[row.start..start]);
                        const highlight_end = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[row.start..end]);
                        try canvas.fillRect(.{ .x = highlight_start, .y = y, .width = @max(1, highlight_end - highlight_start), .height = line_height }, selection_color);
                    }
                }
                if (row.end > row.start) Self.drawEditorLine(context, canvas, text[row.start..row.end], pixel_size, foreground, .{ .x = text_x, .y = y });
                if (focused and caret_on and index == caret_row) {
                    const caret_position = std.math.clamp(state.caret, row.start, row.end);
                    const caret_x = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[row.start..caret_position]);
                    try canvas.line(.{ .x = caret_x, .y = y + 1 }, .{ .x = caret_x, .y = y + line_height - 1 }, 1, context.theme.colors.accent.multiplyAlpha(opacity));
                }
            }
            canvas.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});

            try context.hit_regions.append(context.arena, .{
                .rect = rect,
                .action = .{ .textClick = .{
                    .state = state,
                    .face = face,
                    .pixel_size = pixel_size,
                    .origin = .{ .x = text_x, .y = top },
                    .scroll_y = offset,
                    .line_height = line_height,
                    .rows = rows,
                } },
                .disabled = context.disabled,
            });
            if (context.scroll_regions) |regions| try regions.append(context.arena, .{ .rect = rect, .state = editor.scroll });
            return;
        }

        // Scroll geometry, then auto-follow the caret only when it actually moved.
        editor.scroll.content_height = @as(f32, @floatFromInt(line_count)) * line_height;
        editor.scroll.viewport_height = view_height;
        const caret_line = mod.TextLines.init(text).lineIndex(state.caret);
        if (state.caret != state.last_caret) {
            const caret_y = @as(f32, @floatFromInt(caret_line)) * line_height;
            if (caret_y < editor.scroll.offset) {
                editor.scroll.offset = caret_y;
            } else if (caret_y + line_height > editor.scroll.offset + view_height) {
                editor.scroll.offset = caret_y + line_height - view_height;
            }
            state.last_caret = state.caret;
        }
        editor.scroll.offset = std.math.clamp(editor.scroll.offset, 0, editor.scroll.maxOffset());
        const offset = editor.scroll.offset;

        const foreground = context.foreground.multiplyAlpha(opacity);
        const number_color = context.theme.colors.tertiary_label.multiplyAlpha(opacity);
        const selection_color = context.theme.colors.selection.multiplyAlpha(opacity);
        const selection = state.selectionRange();
        const space_width = renderer.TextShaper.init(face).measureLineWidth(" ", pixel_size);

        // Clip to the interior (inside the border/corners) while drawing content.
        try canvas.pushClip(rect.insetBy(2, 2), 0);
        if (text.len == 0 and view.modifiers.editor_placeholder.len > 0)
            Self.drawEditorLine(context, canvas, view.modifiers.editor_placeholder, pixel_size, context.theme.colors.secondary_label.multiplyAlpha(opacity), .{ .x = text_x, .y = top });

        if (editor.line_numbers) {
            const gutter_x = rect.x + gutter_width;
            try canvas.line(.{ .x = gutter_x, .y = rect.y }, .{ .x = gutter_x, .y = rect.y + rect.height }, metrics.hairline, context.theme.colors.separator.multiplyAlpha(opacity));
        }

        var line_number: usize = 0;
        var position: usize = 0;
        while (line_number < line_count) : (line_number += 1) {
            const line_start = position;
            const line_end = mod.TextLines.init(text).lineEnd(line_start);
            position = line_end + 1; // advance past the '\n' (or one past the end for the last line)
            const y = top - offset + @as(f32, @floatFromInt(line_number)) * line_height;
            if (y + line_height < top or y > top + view_height) continue; // fully offscreen

            // Selection highlight: the part of [selection.start, selection.end] inside this line.
            if (selection) |range| {
                if (range.start <= line_end and range.end >= line_start) {
                    const start = @max(range.start, line_start);
                    const end = @min(range.end, line_end);
                    const highlight_start = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[line_start..start]);
                    var highlight_end = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[line_start..end]);
                    if (range.end > line_end) highlight_end += space_width; // a selected line-break reads as a trailing sliver
                    try canvas.fillRect(.{ .x = highlight_start, .y = y, .width = @max(1, highlight_end - highlight_start), .height = line_height }, selection_color);
                }
            }

            if (editor.line_numbers) {
                var buffer: [20]u8 = undefined;
                // 20 bytes hold any usize in decimal.
                const number = buffer[0..std.fmt.printInt(&buffer, line_number + 1, 10, .lower, .{})];
                const number_width = renderer.TextShaper.init(face).measureLineWidth(number, pixel_size);
                context.drawText(canvas, number, pixel_size, number_color, .{ .x = rect.x + gutter_width - inset - number_width, .y = y }) catch |err| log.debug("text not drawn [{t}]", .{err});
            }

            if (line_end > line_start) Self.drawEditorLine(context, canvas, text[line_start..line_end], pixel_size, foreground, .{ .x = text_x, .y = y });

            if (focused and caret_on and line_number == caret_line) {
                const caret_x = text_x + mod.EditorMetrics.init(face, pixel_size).prefixWidth(text[line_start..state.caret]);
                try canvas.line(.{ .x = caret_x, .y = y + 1 }, .{ .x = caret_x, .y = y + line_height - 1 }, 1, context.theme.colors.accent.multiplyAlpha(opacity));
            }
        }

        canvas.popClip() catch |err| log.debug("clip not popped [{t}]", .{err});

        try context.hit_regions.append(context.arena, .{
            .rect = rect,
            .action = .{ .textClick = .{
                .state = state,
                .face = face,
                .pixel_size = pixel_size,
                .origin = .{ .x = text_x, .y = top },
                .scroll_y = offset,
                .line_height = line_height,
            } },
            .disabled = context.disabled,
        });
        if (context.scroll_regions) |regions| try regions.append(context.arena, .{ .rect = rect, .state = editor.scroll });
    }

    /// Draws a single editor line, rendering tabs as gaps to the next tab stop
    /// (drawing text between tabs run-by-run) so caret/selection x's line up with it.
    ///
    /// - `context`: the context.
    /// - `canvas`: where it draws.
    /// - `line`: the line's text.
    /// - `pixel_size`: its size.
    /// - `color`: its color.
    /// - `origin`: its top-left.
    fn drawEditorLine(context: *const mod.Context, canvas: *renderer.Canvas, line: []const u8, pixel_size: f32, color: renderer.Color, origin: renderer.Point) void {
        const tab_width = mod.EditorMetrics.init(context.cache.face, pixel_size).tabMetrics().tab;
        var x: f32 = 0;
        var segment_start: usize = 0;
        for (line, 0..) |character, index| {
            if (character != '\t') continue;
            const segment = line[segment_start..index];
            if (segment.len > 0) {
                context.drawText(canvas, segment, pixel_size, color, .{ .x = origin.x + x, .y = origin.y }) catch |err| log.debug("text not drawn [{t}]", .{err});
                x += renderer.TextShaper.init(context.cache.face).measureLineWidth(segment, pixel_size);
            }
            x = (@floor(x / tab_width) + 1) * tab_width;
            segment_start = index + 1;
        }
        const tail = line[segment_start..];
        if (tail.len > 0) context.drawText(canvas, tail, pixel_size, color, .{ .x = origin.x + x, .y = origin.y }) catch |err| log.debug("text not drawn [{t}]", .{err});
    }

    /// Width of the line-number gutter: enough for `line_count`'s digits plus padding.
    ///
    /// - `face`: the face the numbers are drawn in.
    /// - `pixel_size`: their size.
    /// - `line_count`: the document's lines.
    /// - `inset`: the padding on each side.
    /// - Returns: the width.
    fn gutterWidth(face: *const renderer.TtfFont, pixel_size: f32, line_count: usize, inset: f32) f32 {
        var digits: usize = 1;
        var remaining = line_count;
        while (remaining >= 10) : (remaining = remaining / 10) digits += 1;
        const zeros = "0000000000000000000"; // up to 19 digits
        const sample = zeros[0..@min(digits, zeros.len)];
        return renderer.TextShaper.init(face).measureLineWidth(sample, pixel_size) + 2 * inset;
    }

    /// A soft-wrap editor's visual rows: `wrapped`, plus the empty row after
    /// a final newline (which word-wrapping leaves out, as a paragraph ends
    /// there) so the caret can sit on it and a click reach it; at least one row.
    ///
    /// - `arena`: the frame arena, for the extended rows.
    /// - `wrapped`: `text` word-wrapped.
    /// - `text`: the editor's text.
    /// - Returns: the rows; propagates allocation failure.
    fn editorRows(arena: std.mem.Allocator, wrapped: []const renderer.WrappedLine, text: []const u8) std.mem.Allocator.Error![]const renderer.WrappedLine {
        const ends_open = text.len > 0 and text[text.len - 1] == '\n' and (wrapped.len == 0 or wrapped[wrapped.len - 1].start < text.len);
        if (wrapped.len > 0 and !ends_open) return wrapped;
        const rows = try arena.alloc(renderer.WrappedLine, wrapped.len + 1);
        @memcpy(rows[0..wrapped.len], wrapped);
        rows[wrapped.len] = .{ .start = text.len, .end = text.len, .width = 0 };
        return rows;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a soft-wrap editor's rows: an empty last line after a newline, never none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const ends = [_]renderer.WrappedLine{.{ .start = 0, .end = 3, .width = 20 }};
    const rows = try TextViewPainter.editorRows(allocator, &ends, "abc\n");
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(usize, 4), rows[1].start);
    try std.testing.expectEqual(@as(usize, 4), rows[1].end);
    // No newline at the end: the wrap is kept as is.
    try std.testing.expectEqual(@as(usize, 1), (try TextViewPainter.editorRows(allocator, &ends, "abc")).len);
    // Already closed (a wrapper that emits the empty row): not doubled.
    const closed = [_]renderer.WrappedLine{ .{ .start = 0, .end = 3, .width = 20 }, .{ .start = 4, .end = 4, .width = 0 } };
    try std.testing.expectEqual(@as(usize, 2), (try TextViewPainter.editorRows(allocator, &closed, "abc\n")).len);
    // Nothing wrapped: one empty row, so the caret has a row.
    try std.testing.expectEqual(@as(usize, 1), (try TextViewPainter.editorRows(allocator, &.{}, "")).len);
}
