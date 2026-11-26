//! A diff's find: the query field, the search options, the matches in the
//! rows a `FindableDiffView` draws, which one is current, and the keys a
//! find bar answers. The diff counterpart of `TextFindState`, read-only (a
//! diff is not edited, so there is no replace).

const std = @import("std");
const log = std.log.scoped(.ziggui_diff_find_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One match of a diff find: a row and a byte range of its text (as the
/// row holds it, tabs unexpanded).
pub const DiffMatch = struct {
    const Self = @This();

    /// The row, in the rows the view draws.
    row: usize,
    /// The match's first byte in the row's text.
    start: usize,
    /// One past its last byte.
    end: usize,

    /// Whether the match lies before a row, for a binary search.
    ///
    /// - `row`: the row.
    /// - `found`: a match.
    /// - Returns: true when the match's row is before `row`.
    fn before(row: usize, found: Self) bool {
        return found.row < row;
    }

    /// The match a range found in a row's text is.
    ///
    /// - `range`: the range, in the row's text.
    /// - `row`: the row.
    /// - Returns: the match.
    fn at(range: mod.TextRange, row: usize) Self {
        const self = Self{ .row = row, .start = range.start, .end = range.end };
        return self;
    }
};

/// The find of one diff pane, app-owned like its `ScrollState`.
/// `FindableDiffView(..., &find, is_presented)` attaches it each frame: the
/// rows then mark every match on the accent's soft ground and the current one
/// on the accent, and a `FindBar` (no replace row) shows above the diff while
/// `is_presented` is true. A diff has no field of its own, so the app offers
/// it the keys (`handleKey`) while its pane or the query has them: ⌘F
/// (Ctrl+F) opens it, and while it shows ⌘G, ⌘⇧G, Shift-Enter in the query
/// and Esc. Next and Previous scroll the match into view, sideways too. With
/// wrapped rows a match is found within a row, so one split by the wrap is
/// not found. Once attached it must stay at one address until `deinit`.
pub const DiffFindState = struct {
    const Self = @This();

    /// The most matches counted and marked (`FindMatches.limit`).
    pub const max_matches: usize = mod.FindMatches(DiffMatch).limit;

    /// Points kept between a match revealed sideways and the pane's edge.
    const reveal_margin: f32 = 24;

    /// What the field and the match list come from.
    allocator: std.mem.Allocator,

    /// The text looked for.
    query: mod.TextFieldState,

    /// How the query matches.
    options: mod.TextSearchOptions = .{},

    /// Whether the bar shows, as the last frame attached it.
    is_presented: ?mod.Binding(bool) = null,

    /// The rows the last frame drew; borrowed until the next frame, and read
    /// only while that frame is its window's latest (`attached`).
    lines: []const mod.DiffLine = &.{},

    /// The diff's scroll, as the last frame attached it; read only while `attached`.
    scroll: ?*mod.ScrollState = null,

    /// How much of the pane's right edge a hunk header's action links cover
    /// (`HunkAction.groupWidth`, set by the view before it attaches): a match
    /// on a header is revealed clear of them.
    header_reserve: f32 = 0,

    /// The frame that last attached the rows: a find no frame drew since (the
    /// diff gone, its rows freed) reads neither them nor the scroll.
    attached_in: ?mod.FrameStamp = null,

    /// The widest line number's digits, for where a numbered row's text starts.
    digits: usize = 1,

    /// The matches, in row order, kept until the rows (their key), the query
    /// or the options change, and the query a match was last chosen for.
    found: mod.FindMatches(DiffMatch),

    /// The rows' key as the last frame attached them.
    diff_key: u64 = 0,

    /// The current match's index in `matches`, if one is chosen.
    current: ?usize = null,

    /// The first row in view when the find opened: typing finds from there.
    origin_row: usize = 0,

    /// An empty find.
    ///
    /// - `allocator`: where the field and matches are kept.
    /// - Returns: the find.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator, .query = mod.TextFieldState.init(allocator), .found = mod.FindMatches(DiffMatch).init(allocator) };
        return self;
    }

    /// Frees the field and the matches.
    ///
    /// - `self`: the find.
    pub fn deinit(self: *Self) void {
        self.found.deinit();
        self.query.deinit();
    }

    /// Attaches the find to the rows a diff draws this frame (what
    /// `FindableDiffView` does), then, while it shows, chooses a match for a
    /// query typed since the last frame.
    ///
    /// - `self`: the find.
    /// - `lines`: the rows drawn.
    /// - `diff_key`: the rows' key (the diff view's hash of them).
    /// - `digits`: the widest line number's digits.
    /// - `scroll`: the diff's scroll.
    /// - `is_presented`: whether the bar shows.
    pub fn attach(self: *Self, lines: []const mod.DiffLine, diff_key: u64, digits: usize, scroll: *mod.ScrollState, is_presented: mod.Binding(bool)) void {
        self.lines = lines;
        self.diff_key = diff_key;
        self.digits = digits;
        self.scroll = scroll;
        self.is_presented = is_presented;
        self.attached_in = mod.BuildScope.shared().stamp();
        if (is_presented.get()) self.follow();
    }

    /// Opens the bar, the keyboard in its query, its text selected.
    ///
    /// - `self`: the find.
    pub fn open(self: *Self) void {
        if (self.attached()) {
            if (self.scroll) |scroll| self.origin_row = Self.topRow(scroll);
        }
        if (self.is_presented) |presented| presented.set(true);
        self.query.selectAll();
        mod.Focus.shared().set(&self.query);
    }

    /// Closes the bar; the query gives the keyboard up (the app gives the
    /// pane its keys back).
    ///
    /// - `self`: the find.
    pub fn close(self: *Self) void {
        if (self.is_presented) |presented| presented.set(false);
        if (mod.Focus.shared().focused() == &self.query) mod.Focus.shared().clear();
    }

    /// Reports whether the bar shows.
    ///
    /// - `self`: the find.
    /// - Returns: true while it does.
    pub fn shown(self: *const Self) bool {
        const presented = self.is_presented orelse return false;
        return presented.get();
    }

    /// The matches in the rows, found again if the rows, query or options changed.
    ///
    /// - `self`: the find.
    /// - Returns: the matches, valid until the next change.
    pub fn matchList(self: *Self) []const DiffMatch {
        // Rows no frame drew since may be freed: keep what was found.
        if (!self.attached()) return self.found.items.items;
        const key: mod.FindMatchesKey = .{ .source = self.diff_key, .query = self.query.revision, .options = self.options };
        // The current match's row, kept when only the options changed (Aa, ab|).
        const kept_row: ?usize = self.keptRow(key);
        if (self.found.holds(key)) return self.found.items.items;
        // Other rows, or another query: no match is current any more.
        self.current = null;
        for (self.lines, 0..) |line, row| {
            if (!self.found.collect(line.text, self.query.text(), self.options, row, DiffMatch.at)) break;
        }
        if (kept_row) |row| {
            const at = std.sort.partitionPoint(DiffMatch, self.found.items.items, row, DiffMatch.before);
            if (at < self.found.items.items.len) self.current = at;
        }
        return self.found.items.items;
    }

    /// The matches on one row, for its marks.
    ///
    /// - `self`: the find.
    /// - `row`: the row.
    /// - Returns: its matches, in order; the first's index in `matchList` is `firstOn(row)`.
    pub fn matchesOn(self: *Self, row: usize) []const DiffMatch {
        const found = self.matchList();
        const first = self.firstOn(row);
        var last = first;
        while (last < found.len and found[last].row == row) last += 1;
        return found[first..last];
    }

    /// The index of the first match on or after a row.
    ///
    /// - `self`: the find.
    /// - `row`: the row.
    /// - Returns: its index in `matchList`, or its length.
    pub fn firstOn(self: *Self, row: usize) usize {
        return std.sort.partitionPoint(DiffMatch, self.matchList(), row, DiffMatch.before);
    }

    /// Where the find stands, for the bar.
    ///
    /// - `self`: the find.
    /// - Returns: the count, or null while the query is empty.
    pub fn count(self: *Self) ?mod.FindCount {
        if (self.query.text().len == 0) return null;
        _ = self.matchList();
        return self.found.count(self.current);
    }

    /// Chooses the next match (from the first row in view when none is
    /// current), wrapping to the first, and scrolls it into view.
    ///
    /// - `self`: the find.
    pub fn findNext(self: *Self) void {
        if (!self.attached()) return;
        const found = self.matchList();
        if (found.len == 0) return;
        const next = if (self.current) |at| (at + 1) % found.len else blk: {
            const top = if (self.scroll) |scroll| Self.topRow(scroll) else 0;
            const at = self.firstOn(top);
            break :blk if (at == found.len) 0 else at;
        };
        self.choose(next);
    }

    /// Chooses the previous match (the last before the first row in view
    /// when none is current), wrapping to the last, and scrolls it into view.
    ///
    /// - `self`: the find.
    pub fn findPrevious(self: *Self) void {
        if (!self.attached()) return;
        const found = self.matchList();
        if (found.len == 0) return;
        const previous = if (self.current) |at| (if (at == 0) found.len - 1 else at - 1) else blk: {
            const top = if (self.scroll) |scroll| Self.topRow(scroll) else 0;
            const at = self.firstOn(top);
            break :blk if (at == 0) found.len - 1 else at - 1;
        };
        self.choose(previous);
    }

    /// What the bar's field, buttons and toggles do.
    ///
    /// - `self`: the find.
    /// - Returns: the actions, pointing at the find.
    pub fn actions(self: *Self) mod.FindActions {
        return .{
            .on_submit = mod.Callback.init(Self, self, Self.findNext),
            .on_next = mod.Callback.init(Self, self, Self.findNext),
            .on_previous = mod.Callback.init(Self, self, Self.findPrevious),
            .on_done = mod.Callback.init(Self, self, Self.close),
            .search_options = &self.options,
        };
    }

    /// Handles a key while the diff's pane or the query has the keyboard:
    /// ⌘F (Ctrl+F) opens the bar; while it shows, `FindActions.handleKey`'s
    /// (⌘G, ⌘⇧G, Shift-Enter in the query, Esc).
    ///
    /// - `self`: the find.
    /// - `key`: the key.
    /// - Returns: whether it took the key.
    pub fn handleKey(self: *Self, key: mod.Key) bool {
        if (!key.alt and !key.shift and mod.FindActions.commandLetter(key) == 'f') {
            self.open();
            return true;
        }
        if (!self.shown()) return false;
        // A diff the last frame did not draw (no frame yet, or its rows gone)
        // has nothing to step through: only Esc, which reads no row, is the bar's.
        if (!self.attached() and !key.isNamed(.escape)) return false;
        return self.actions().handleKey(key, &self.query);
    }

    /// The current match's row, when a search for `key` differs from the
    /// last only in its options, so the match on that row stays current.
    ///
    /// - `self`: the find.
    /// - `key`: the search about to be made.
    /// - Returns: the row, or null.
    fn keptRow(self: *const Self, key: mod.FindMatchesKey) ?usize {
        const held = self.found.key orelse return null;
        const at = self.current orelse return null;
        if (held.source != key.source or held.query != key.query or at >= self.found.items.items.len) return null;
        return self.found.items.items[at].row;
    }

    /// Whether the rows and scroll are the latest frame's, so safe to read.
    ///
    /// - `self`: the find.
    /// - Returns: true while the frame that attached them is its window's latest.
    fn attached(self: *const Self) bool {
        const stamp = self.attached_in orelse return false;
        return mod.BuildScope.shared().isLatest(stamp);
    }

    /// The first row in view.
    ///
    /// - `scroll`: the diff's scroll.
    /// - Returns: the row.
    fn topRow(scroll: *const mod.ScrollState) usize {
        return @intFromFloat(@max(0, @floor(scroll.offset / mod.diff_row_height)));
    }

    /// Chooses a match for a query that changed as it was typed: the first
    /// on or after the row in view when the find opened.
    ///
    /// - `self`: the find.
    fn follow(self: *Self) void {
        if (!self.found.takeQueryChange(self.query.revision)) return;
        const found = self.matchList();
        if (found.len == 0) return;
        const at = self.firstOn(self.origin_row);
        self.choose(if (at == found.len) 0 else at);
    }

    /// Makes a match current and scrolls it into view: its row, then its
    /// text sideways, as the row lays it out (`DiffLayout`).
    ///
    /// - `self`: the find.
    /// - `index`: the match, in `matchList`.
    fn choose(self: *Self, index: usize) void {
        if (!self.attached()) return;
        self.current = index;
        const scroll = self.scroll orelse return;
        const found = self.found.items.items[index];
        if (found.row >= self.lines.len) return;
        // Again once this frame's viewport is measured: the bar may have just appeared above the rows.
        scroll.revealAfterLayout(found.row, mod.diff_row_height);
        if (scroll.viewport_width <= 0) return;
        const line = self.lines[found.row];
        const end = @min(found.end, line.text.len);
        const start = @min(found.start, end);
        const inset = switch (line.kind) {
            .hunkHeader, .fileHeader, .note => mod.DiffLayout.bar_width + mod.DiffLayout.bar_spacing,
            else => mod.DiffLayout.textInset(self.digits),
        };
        const left = inset + @as(f32, @floatFromInt(mod.DiffLayout.columns(line.text[0..start]))) * mod.DiffLayout.cell_width;
        const right = inset + @as(f32, @floatFromInt(mod.DiffLayout.columns(line.text[0..end]))) * mod.DiffLayout.cell_width;
        const trailing = reveal_margin + if (line.kind == .hunkHeader) self.header_reserve else 0;
        if (right + trailing > scroll.offset_x + scroll.viewport_width) scroll.offset_x = right + trailing - scroll.viewport_width;
        if (left - reveal_margin < scroll.offset_x) scroll.offset_x = @max(0, left - reveal_margin);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

/// A find over a few diff rows, with a presented flag, for the tests.
const FindFixture = struct {
    const Self = @This();

    /// The rows.
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1,3 +1,3 @@ fn main" },
        .{ .kind = .context, .text = "const a = 1;", .old = 1, .new = 1 },
        .{ .kind = .removed, .text = "const b = a;", .old = 2 },
        .{ .kind = .added, .text = "const b = a + a;", .new = 2 },
    };

    /// The find.
    find: DiffFindState,
    /// Whether the bar shows.
    presented: renderer.State(bool),
    /// The diff's scroll.
    scroll: mod.ScrollState = .{ .viewport_height = 400, .viewport_width = 600 },

    /// Makes the fixture and attaches the find.
    ///
    /// - `self`: where the fixture goes.
    fn setUp(self: *Self) void {
        self.* = .{
            .find = DiffFindState.init(std.testing.allocator),
            .presented = renderer.State(bool).init(std.testing.allocator, false),
        };
        self.find.attach(&lines, 1, 1, &self.scroll, self.presented.binding());
    }

    /// Frees the fixture.
    ///
    /// - `self`: the fixture.
    fn tearDown(self: *Self) void {
        mod.Focus.shared().clear();
        self.presented.deinit();
        self.find.deinit();
    }
};

test "diff find: the matches by row, next and previous wrap, and the count names the current one" {
    var fixture: FindFixture = undefined;
    fixture.setUp();
    defer fixture.tearDown();
    const find = &fixture.find;
    try find.query.setText("a");
    // "main" in the header too, case aside; "const" holds no "a".
    try std.testing.expectEqual(@as(usize, 1 + 1 + 1 + 2), find.matchList().len);
    try std.testing.expectEqual(@as(usize, 2), find.matchesOn(3).len);
    try std.testing.expectEqual(@as(usize, 3), find.firstOn(3));
    try std.testing.expectEqual(@as(?mod.FindCount, .{ .total = 5 }), find.count());
    find.findNext();
    try std.testing.expectEqual(@as(?mod.FindCount, .{ .current = 0, .total = 5 }), find.count());
    find.findPrevious();
    try std.testing.expectEqual(@as(?usize, 4), find.current);
    find.findNext();
    try std.testing.expectEqual(@as(?usize, 0), find.current);
    find.options.whole_word = true;
    // Whole words: "a" alone, in rows 1 to 3; the current match (row 0's) moves to the first from its row on.
    try std.testing.expectEqual(@as(usize, 4), find.matchList().len);
    try std.testing.expectEqual(@as(?usize, 0), find.current);
    // Another query: no match is current.
    try find.query.setText("b");
    _ = find.matchList();
    try std.testing.expectEqual(@as(?usize, null), find.current);
    try find.query.setText("a");
    // Other rows (a new key) are searched afresh.
    fixture.find.attach(FindFixture.lines[0..2], 2, 1, &fixture.scroll, fixture.presented.binding());
    try std.testing.expectEqual(@as(usize, 1), find.matchList().len);
}

test "diff find: the keys open it, typing finds from the row in view, and Esc closes it" {
    var fixture: FindFixture = undefined;
    fixture.setUp();
    defer fixture.tearDown();
    const find = &fixture.find;
    try std.testing.expect(!find.handleKey(.{ .char = 'g', .command = true }));
    try std.testing.expect(find.handleKey(.{ .char = 'f', .command = true }));
    try std.testing.expect(fixture.presented.get());
    try std.testing.expect(mod.Focus.shared().focused() == &find.query);
    try find.query.setText("b =");
    fixture.find.attach(&FindFixture.lines, 1, 1, &fixture.scroll, fixture.presented.binding());
    try std.testing.expectEqual(@as(?usize, 0), find.current);
    try std.testing.expect(find.handleKey(.{ .char = 'g', .command = true }));
    try std.testing.expectEqual(@as(?usize, 1), find.current);
    try std.testing.expect(find.handleKey(.{ .name = .escape }));
    try std.testing.expect(!fixture.presented.get());
    try std.testing.expect(mod.Focus.shared().focused() == null);
}

test "diff find: a match past the pane's right edge scrolls it sideways into view" {
    var fixture: FindFixture = undefined;
    fixture.setUp();
    defer fixture.tearDown();
    const long = [_]mod.DiffLine{.{ .kind = .added, .text = &(@as([200]u8, @splat('x')) ++ "needle".*), .new = 1 }};
    fixture.scroll.viewport_width = 300;
    fixture.find.attach(&long, 3, 1, &fixture.scroll, fixture.presented.binding());
    try fixture.find.query.setText("needle");
    fixture.find.findNext();
    try std.testing.expect(fixture.scroll.offset_x > 0);
    const right = mod.DiffLayout.textInset(1) + 206 * mod.DiffLayout.cell_width;
    try std.testing.expect(right <= fixture.scroll.offset_x + fixture.scroll.viewport_width);
}

test "diff find: a match on a hunk header is revealed clear of its action links" {
    var fixture: FindFixture = undefined;
    fixture.setUp();
    defer fixture.tearDown();
    const long = [_]mod.DiffLine{.{ .kind = .hunkHeader, .text = &(@as([200]u8, @splat('x')) ++ "needle".*) }};
    fixture.scroll.viewport_width = 300;
    fixture.find.header_reserve = 90;
    fixture.find.attach(&long, 4, 1, &fixture.scroll, fixture.presented.binding());
    try fixture.find.query.setText("needle");
    fixture.find.findNext();
    const right = mod.DiffLayout.bar_width + mod.DiffLayout.bar_spacing + 206 * mod.DiffLayout.cell_width;
    try std.testing.expect(right + 90 <= fixture.scroll.offset_x + fixture.scroll.viewport_width);
}

test "diff find: once a frame draws without the diff, its keys and next read nothing" {
    var fixture: FindFixture = undefined;
    fixture.setUp();
    defer fixture.tearDown();
    const find = &fixture.find;
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    // A frame that attaches the rows, as the view does.
    window.begin(renderer.Theme.default);
    find.attach(&FindFixture.lines, 1, 1, &fixture.scroll, fixture.presented.binding());
    window.end();
    try find.query.setText("a");
    find.findNext();
    try std.testing.expectEqual(@as(?usize, 0), find.current);
    // A frame that does not: the rows may be freed, so nothing reads them.
    window.begin(renderer.Theme.default);
    window.end();
    try find.query.setText("const");
    try std.testing.expect(!find.handleKey(.{ .char = 'g', .command = true }));
    find.findNext();
    try std.testing.expectEqual(@as(?usize, 0), find.current);
    try std.testing.expectEqual(@as(usize, 5), find.matchList().len);
}
