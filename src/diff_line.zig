const std = @import("std");
const log = std.log.scoped(.ziggui_diff_line);
const zigui = @import("zigui");

/// The height of one diff row, in points.
pub const diff_row_h: f32 = 18;

/// What a `DiffLine` is.
pub const DiffLineKind = enum {
    const Self = @This();

    /// An unchanged line.
    context,

    /// A line only the new side has.
    added,

    /// A line only the old side has.
    removed,

    /// A hunk's `@@` header.
    hunkHeader,

    /// A file's header.
    fileHeader,

    /// Any other line (`\ No newline at end of file`).
    note,
};

/// One row of a `DiffView`: a diff line without its `+`, `-` or space, and
/// its line numbers on each side. Knows nothing of any version-control tool.
pub const DiffLine = struct {
    const Self = @This();

    /// What the line is.
    kind: DiffLineKind,

    /// The line's text.
    text: []const u8,

    /// Its number on the old side, if it has one.
    old: ?u32 = null,

    /// Its number on the new side, if it has one.
    new: ?u32 = null,

    /// How many hunks a diff holds.
    ///
    /// - `lines`: the diff.
    /// - Returns: the hunk count.
    pub fn hunkCount(lines: []const Self) usize {
        var n: usize = 0;
        for (lines) |line| n += @intFromBool(line.kind == .hunkHeader);
        return n;
    }

    /// The row of a hunk's header.
    ///
    /// - `lines`: the diff.
    /// - `index`: the hunk.
    /// - Returns: the header's row, or null when there is no such hunk.
    pub fn hunkRow(lines: []const Self, index: usize) ?usize {
        var n: usize = 0;
        for (lines, 0..) |line, at| {
            if (line.kind != .hunkHeader) continue;
            if (n == index) return at;
            n += 1;
        }
        return null;
    }

    /// Scrolls a `DiffView` so a hunk sits at its top, header first.
    ///
    /// - `scroll`: the diff's scroll position.
    /// - `lines`: the diff.
    /// - `index`: the hunk.
    pub fn revealHunk(scroll: *zigui.ScrollState, lines: []const Self, index: usize) void {
        const at = Self.hunkRow(lines, index) orelse return;
        scroll.offset = @as(f32, @floatFromInt(at)) * diff_row_h;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "diff hunks are counted and located across files" {
    const lines = [_]DiffLine{
        .{ .kind = .fileHeader, .text = "a" },
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" },
        .{ .kind = .removed, .text = "x", .old = 1 },
        .{ .kind = .added, .text = "y", .new = 1 },
        .{ .kind = .fileHeader, .text = "b" },
        .{ .kind = .hunkHeader, .text = "@@ -3 +3 @@" },
        .{ .kind = .context, .text = "z", .old = 3, .new = 3 },
    };
    try std.testing.expectEqual(@as(usize, 2), DiffLine.hunkCount(&lines));
    try std.testing.expectEqual(@as(?usize, 5), DiffLine.hunkRow(&lines, 1));
    try std.testing.expectEqual(@as(?usize, null), DiffLine.hunkRow(&lines, 2));
    var scroll: zigui.ScrollState = .{};
    DiffLine.revealHunk(&scroll, &lines, 1);
    try std.testing.expectEqual(5 * diff_row_h, scroll.offset);
}
