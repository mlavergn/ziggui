//! A selectable rich-text view's geometry for one frame.

const std = @import("std");
const log = std.log.scoped(.ziggui_select_hit);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A selectable view's geometry this frame: enough to map a point to a text
/// offset without the `Context`.
pub const SelectHit = struct {
    const Self = @This();

    /// The view's identity: a hash of its text, size and build-order ordinal,
    /// or of its explicit id (see `TextSelection.keyFor`).
    key: u64,

    /// The paragraph's top-left.
    origin: renderer.Point,

    /// The paragraph's laid-out lines.
    layout: mod.RichLayout,

    /// The spans the lines index into.
    spans: []const mod.Span,

    /// The faces the spans are drawn in.
    faces: mod.RichFaces,

    /// The paragraph's base size.
    pixel_size: f32,

    /// The device-pixel scale it was painted at.
    scale: f32,

    /// Where span `span_index` starts in the concatenated text.
    ///
    /// - `self`: the geometry.
    /// - `span_index`: the span.
    /// - Returns: its byte offset.
    pub fn spanStart(self: *const Self, span_index: usize) usize {
        var offset: usize = 0;
        for (self.spans[0..span_index]) |span| offset += span.text.len;
        return offset;
    }

    /// The width of a run's text up to byte `end` of its span.
    ///
    /// - `self`: the geometry.
    /// - `run`: the run.
    /// - `end`: where to stop, in its span's text.
    /// - Returns: the width, in points.
    pub fn runWidth(self: *const Self, run: mod.RichRun, end: usize) f32 {
        const span = self.spans[run.span];
        return renderer.TextShaper.init(self.faces.forSpan(span)).measureLineWidth(span.text[run.start..end], self.pixel_size * span.size_scale);
    }

    /// The text offset nearest `point` (clamped into the view).
    ///
    /// - `self`: the geometry.
    /// - `point`: the pointer.
    /// - Returns: the byte offset in the concatenated text.
    pub fn indexAt(self: *const Self, point: renderer.Point) usize {
        const lines = self.layout.lines;
        if (lines.len == 0) return 0;
        const line_y = point.y - self.origin.y;
        if (line_y < 0) return 0;
        var line_index: usize = lines.len - 1;
        for (lines, 0..) |line, index| if (line_y < line.y + line.height) {
            line_index = index;
            break;
        };
        if (line_y >= lines[lines.len - 1].y + lines[lines.len - 1].height) return self.spanStart(self.spans.len);
        const line = lines[line_index];
        const line_x = point.x - self.origin.x;
        if (line.runs.len == 0) {
            // A blank line: just after the previous line's text (its newline).
            var previous = line_index;
            while (previous > 0) {
                previous -= 1;
                if (lines[previous].runs.len > 0) {
                    const run = lines[previous].runs[lines[previous].runs.len - 1];
                    return @min(self.spanStart(run.span) + run.end + 1, self.spanStart(self.spans.len));
                }
            }
            return 0;
        }
        for (line.runs) |run| {
            if (line_x < run.x) return self.spanStart(run.span) + run.start;
            if (line_x <= run.x + run.width) {
                // Nearest codepoint boundary inside the run.
                const text = self.spans[run.span].text;
                var at: usize = run.start;
                var index: usize = run.start;
                while (index < run.end) {
                    const next = @min(run.end, mod.TextLines.init(text).nextCodepointEnd(index));
                    const middle = run.x + (self.runWidth(run, index) + self.runWidth(run, next)) / 2;
                    if (line_x < middle) break;
                    at = next;
                    index = next;
                }
                return self.spanStart(run.span) + at;
            }
        }
        const last = line.runs[line.runs.len - 1];
        return self.spanStart(last.span) + last.end;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
