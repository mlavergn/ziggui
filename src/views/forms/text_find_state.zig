//! A text editor's find and replace: the query and replacement fields, the
//! search options, the matches in the document, and the keys a find
//! navigator answers. `View.findNavigator` attaches it to a `TextEditor`.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_find_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Every find state a frame attached to an editor, so the event loop can
/// offer it the keys while its editor or its fields hold the keyboard.
const Navigators = struct {
    const Self = @This();

    /// The most find states kept; one attached past them takes no keys.
    const capacity = 8;

    /// The find states, newest last.
    items: [capacity]*TextFindState = undefined,

    /// How many of `items` are kept.
    count: usize = 0,

    /// Whether the list was found full, so it says so once.
    warned: bool = false,

    /// The process's list.
    var shared_navigators: Self = .{};

    /// Keeps a find state, once.
    ///
    /// - `self`: the list.
    /// - `find`: the find state.
    fn note(self: *Self, find: *TextFindState) void {
        for (self.items[0..self.count]) |kept| if (kept == find) return;
        // Full: drop the finds no frame of their window has attached since.
        if (self.count == capacity) self.dropStale();
        if (self.count == capacity) {
            if (!self.warned) log.warn("more than {d} find navigators on show; the rest take no keys", .{capacity});
            self.warned = true;
            return;
        }
        self.items[self.count] = find;
        self.count += 1;
    }

    /// Drops the finds whose last attaching frame is no longer their window's latest.
    ///
    /// - `self`: the list.
    fn dropStale(self: *Self) void {
        const scope = mod.BuildScope.shared();
        var index: usize = 0;
        while (index < self.count) {
            const stamp = self.items[index].attached_in;
            if (stamp == null or !scope.isLatest(stamp.?)) {
                self.items[index] = self.items[self.count - 1];
                self.count -= 1;
            } else index += 1;
        }
    }

    /// Drops a find state, as it is freed.
    ///
    /// - `self`: the list.
    /// - `find`: the find state.
    fn forget(self: *Self, find: *const TextFindState) void {
        var index: usize = 0;
        while (index < self.count) {
            if (self.items[index] == find) {
                self.items[index] = self.items[self.count - 1];
                self.count -= 1;
            } else index += 1;
        }
    }
};

/// The find and replace of one `TextEditor`, app-owned like its
/// `TextFieldState`. `View.findNavigator(is_presented, &find)` attaches it
/// each frame: the editor then marks its matches, a `FindBar` (with its
/// replace row once asked for) shows above it while `is_presented` is true,
/// and the event loop offers it the keys first while the editor or its
/// fields hold the keyboard (`keyDown`): ⌘F opens it, ⌥⌘F (Ctrl+H off
/// macOS) opens it with the replace row, ⌘E finds the selection, and while
/// it shows ⌘G, ⌘⇧G, Shift-Enter, ⌘⌥Enter (replace all) and Esc. Once
/// attached it must stay at one address until `deinit` (the event loop keeps
/// a pointer to it), as must its editor's `TextFieldState`.
pub const TextFindState = struct {
    const Self = @This();

    /// The most matches counted and marked.
    pub const max_matches: usize = 10_000;

    /// What the fields and the match list come from.
    allocator: std.mem.Allocator,

    /// The text looked for.
    query: mod.TextFieldState,

    /// The text a replace puts in.
    replacement: mod.TextFieldState,

    /// How the query matches.
    options: mod.TextSearchOptions = .{},

    /// Whether the bar shows the replace row.
    shows_replace: bool = false,

    /// The editor's text, as the last frame attached it.
    document: ?*mod.TextFieldState = null,

    /// Whether the bar shows, as the last frame attached it.
    is_presented: ?mod.Binding(bool) = null,

    /// The frame that last attached it, so keys reach only a find on show.
    attached_in: ?mod.FrameStamp = null,

    /// The matches, kept until the text, the query or the options change.
    matches: std.ArrayList(mod.TextRange) = .empty,

    /// Whether `matches` stopped at `max_matches`.
    more: bool = false,

    /// What `matches` was found for: the document, its revision, the
    /// query's revision and the options.
    matched: ?struct { document: *const mod.TextFieldState, revision: u64, query: u64, options: mod.TextSearchOptions } = null,

    /// The query's revision the last time a match was chosen for it, so
    /// typing in the field finds as it goes.
    followed_query: u64 = 0,

    /// Where the caret was when the find opened: typing finds from there.
    origin: usize = 0,

    /// An empty find.
    ///
    /// - `allocator`: where the fields and matches are kept.
    /// - Returns: the find.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .allocator = allocator,
            .query = mod.TextFieldState.init(allocator),
            .replacement = mod.TextFieldState.init(allocator),
        };
        return self;
    }

    /// Frees the fields and matches, and stops taking keys.
    ///
    /// - `self`: the find.
    pub fn deinit(self: *Self) void {
        Navigators.shared_navigators.forget(self);
        self.matches.deinit(self.allocator);
        self.replacement.deinit();
        self.query.deinit();
    }

    /// Attaches the find to an editor for this frame (what
    /// `View.findNavigator` does): the editor marks the matches, and while
    /// `is_presented` is true a `FindBar` shows above it.
    ///
    /// - `self`: the find.
    /// - `editor`: the `TextEditor`'s view (any other view is returned as it is).
    /// - `is_presented`: whether the bar shows; the find sets it as it opens and closes.
    /// - Returns: the editor, with the bar above it while it shows.
    pub fn navigate(self: *Self, editor: mod.View, is_presented: mod.Binding(bool)) mod.View {
        var view = editor;
        switch (view.kind) {
            .textEditor => |*data| {
                self.document = data.state;
                if (is_presented.get()) data.find = self;
            },
            else => return editor,
        }
        self.is_presented = is_presented;
        self.attached_in = mod.BuildScope.shared().stamp();
        Navigators.shared_navigators.note(self);
        if (!is_presented.get()) return view;
        self.follow();
        const bar = mod.FindBar("Find", &self.query, self.count(), self.actions());
        return mod.StackBuilder.make(.vertical, 0, .leading, .{ bar, view });
    }

    /// Opens the bar, the query taken from a selection on one line and
    /// selected, the keyboard in the query.
    ///
    /// - `self`: the find.
    /// - `with_replace`: whether the replace row shows too.
    pub fn open(self: *Self, with_replace: bool) void {
        if (with_replace) self.shows_replace = true;
        if (self.document) |document| {
            self.origin = if (document.selectionRange()) |range| range.start else document.caret;
            const selected = document.selectedText();
            if (selected.len > 0 and std.mem.findScalar(u8, selected, '\n') == null) {
                self.query.setText(selected) catch |err| log.warn("the find was not seeded: {s}", .{@errorName(err)});
                self.followed_query = self.query.revision;
            }
        }
        if (self.is_presented) |presented| presented.set(true);
        self.query.selectAll();
        mod.Focus.shared().set(&self.query);
    }

    /// Closes the bar, the replace row with it, and gives the keyboard back to the editor.
    ///
    /// - `self`: the find.
    pub fn close(self: *Self) void {
        self.shows_replace = false;
        if (self.is_presented) |presented| presented.set(false);
        if (self.document) |document| mod.Focus.shared().set(document);
    }

    /// Finds the selection (⌘E): the query becomes it, and the next match is chosen.
    ///
    /// - `self`: the find.
    pub fn useSelection(self: *Self) void {
        const document = self.document orelse return;
        const selected = document.selectedText();
        if (selected.len == 0) return;
        self.query.setText(selected) catch |err| {
            log.warn("the selection was not taken: {s}", .{@errorName(err)});
            return;
        };
        self.followed_query = self.query.revision;
    }

    /// The matches in the document, found again if the text, query or options changed.
    ///
    /// - `self`: the find.
    /// - Returns: the matches, valid until the next change.
    pub fn matchList(self: *Self) []const mod.TextRange {
        const document = self.document orelse return &.{};
        if (self.matched) |key| {
            if (key.document == document and key.revision == document.revision and key.query == self.query.revision and std.meta.eql(key.options, self.options)) return self.matches.items;
        }
        self.matches.clearRetainingCapacity();
        self.more = false;
        self.matched = .{ .document = document, .revision = document.revision, .query = self.query.revision, .options = self.options };
        const search = mod.TextSearch.init(document.text(), self.query.text(), self.options);
        var from: usize = 0;
        while (search.next(from)) |range| {
            if (self.matches.items.len == max_matches) {
                self.more = true;
                break;
            }
            self.matches.append(self.allocator, range) catch |err| {
                log.warn("matches cut short: {s}", .{@errorName(err)});
                self.more = true;
                break;
            };
            from = range.end;
        }
        return self.matches.items;
    }

    /// The match the document's selection is, if it is one.
    ///
    /// - `self`: the find.
    /// - Returns: its index in `matchList`, or null.
    pub fn currentIndex(self: *Self) ?usize {
        const document = self.document orelse return null;
        const selection = document.selectionRange() orelse return null;
        const found = self.matchList();
        const index = Self.firstEndingAfter(found, selection.start);
        if (index < found.len and found[index].start == selection.start and found[index].end == selection.end) return index;
        return null;
    }

    /// Where the find stands, for the bar.
    ///
    /// - `self`: the find.
    /// - Returns: the count, or null while the query is empty.
    pub fn count(self: *Self) ?mod.FindCount {
        if (self.query.text().len == 0) return null;
        const found = self.matchList();
        return .{ .current = self.currentIndex(), .total = found.len, .more = self.more };
    }

    /// Selects the next match after the selection or caret, wrapping to the first.
    ///
    /// - `self`: the find.
    pub fn findNext(self: *Self) void {
        const document = self.document orelse return;
        const from = if (document.selectionRange()) |range| range.end else document.caret;
        self.selectFrom(from);
    }

    /// Selects the match before the selection or caret, wrapping to the last.
    ///
    /// - `self`: the find.
    pub fn findPrevious(self: *Self) void {
        const document = self.document orelse return;
        const found = self.matchList();
        if (found.len == 0) return;
        const before = if (document.selectionRange()) |range| range.start else document.caret;
        // The last match starting before `before`.
        var index = Self.firstEndingAfter(found, before);
        while (index < found.len and found[index].start < before) index += 1;
        self.select(found[if (index == 0) found.len - 1 else index - 1]);
    }

    /// Replaces the match the selection is with the replacement, then
    /// selects the next one; with no match selected, only selects the next.
    ///
    /// - `self`: the find.
    pub fn replaceCurrent(self: *Self) void {
        const document = self.document orelse return;
        const index = self.currentIndex() orelse return self.findNext();
        const range = self.matches.items[index];
        document.replaceRange(range.start, range.end, self.replacement.text()) catch |err| {
            log.warn("not replaced: {s}", .{@errorName(err)});
            return;
        };
        self.selectFrom(document.caret);
    }

    /// Replaces every match, as one undo step, from the last back to the first.
    ///
    /// - `self`: the find.
    /// - Returns: how many were replaced.
    pub fn replaceAll(self: *Self) usize {
        const document = self.document orelse return 0;
        const found = self.allocator.dupe(mod.TextRange, self.matchList()) catch |err| {
            log.warn("nothing replaced: {s}", .{@errorName(err)});
            return 0;
        };
        defer self.allocator.free(found);
        if (found.len == 0) return 0;
        const replacement = self.replacement.text();
        document.beginUndoGrouping();
        defer document.endUndoGrouping();
        var replaced: usize = 0;
        var index = found.len;
        while (index > 0) {
            index -= 1;
            document.replaceRange(found[index].start, found[index].end, replacement) catch |err| {
                log.warn("replace all stopped: {s}", .{@errorName(err)});
                break;
            };
            replaced += 1;
        }
        return replaced;
    }

    /// Replace All as a tap's callback.
    ///
    /// - `self`: the find.
    pub fn replaceEvery(self: *Self) void {
        _ = self.replaceAll();
    }

    /// What the bar's field, buttons, toggles and replace row do.
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
            .replace = if (self.shows_replace) .{
                .field = &self.replacement,
                .on_replace = mod.Callback.init(Self, self, Self.replaceCurrent),
                .on_replace_all = mod.Callback.init(Self, self, Self.replaceEvery),
            } else null,
        };
    }

    /// Offers a key to the find of the editor holding the keyboard: the
    /// event loop calls it before a field takes the key.
    ///
    /// - `key`: the key.
    /// - `mac`: whether this is macOS (⌥⌘F there, Ctrl+H elsewhere).
    /// - Returns: whether a find took it.
    pub fn keyDown(key: mod.Key, mac: bool) bool {
        const focused = mod.Focus.shared().focused() orelse return false;
        const scope = mod.BuildScope.shared();
        for (Navigators.shared_navigators.items[0..Navigators.shared_navigators.count]) |find| {
            const stamp = find.attached_in orelse continue;
            if (!scope.isLatest(stamp)) continue;
            if (focused != find.document and focused != &find.query and focused != &find.replacement) continue;
            return find.handleKey(key, mac);
        }
        return false;
    }

    /// Handles a key while its editor or fields hold the keyboard.
    ///
    /// - `self`: the find.
    /// - `key`: the key.
    /// - `mac`: whether this is macOS.
    /// - Returns: whether it took the key.
    pub fn handleKey(self: *Self, key: mod.Key, mac: bool) bool {
        // Only ASCII letters are the find's shortcuts; an app may hand any character.
        const letter: ?u21 = if (key.char) |char| (if (char < 0x80) std.ascii.toLower(@intCast(char)) else null) else null;
        if (key.command and letter != null) {
            if (letter.? == 'f' and !key.shift) {
                self.open(mac and key.alt);
                return true;
            }
            if (letter.? == 'h' and !mac) {
                self.open(true);
                return true;
            }
            if (letter.? == 'e' and mac) {
                self.useSelection();
                self.findNext();
                return true;
            }
        }
        const presented = if (self.is_presented) |binding| binding.get() else false;
        if (!presented) return false;
        if (key.isNamed(.escape) and !mod.TextContextMenu.shared().isOpen()) {
            self.close();
            return true;
        }
        if (key.isNamed(.enter) and key.command and key.alt) {
            _ = self.replaceAll();
            return true;
        }
        return self.actions().handleKey(key, &self.query);
    }

    /// The first match ending after a byte (the matches are in order and
    /// apart): where a row's matches start.
    ///
    /// - `found`: the matches.
    /// - `at`: the byte.
    /// - Returns: its index, or `found.len`.
    pub fn firstEndingAfter(found: []const mod.TextRange, at: usize) usize {
        var low: usize = 0;
        var high: usize = found.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (found[middle].end <= at) low = middle + 1 else high = middle;
        }
        return low;
    }

    /// Chooses a match for a query that changed as it was typed: the first
    /// at or after where the find opened, so the editor shows it.
    ///
    /// - `self`: the find.
    fn follow(self: *Self) void {
        if (self.query.revision == self.followed_query) return;
        self.followed_query = self.query.revision;
        if (self.query.text().len == 0) return;
        self.selectFrom(self.origin);
    }

    /// Selects the first match at or after a byte, wrapping to the first.
    ///
    /// - `self`: the find.
    /// - `from`: the byte.
    fn selectFrom(self: *Self, from: usize) void {
        const found = self.matchList();
        if (found.len == 0) return;
        var index = Self.firstEndingAfter(found, from);
        while (index < found.len and found[index].start < from) index += 1;
        self.select(found[if (index == found.len) 0 else index]);
    }

    /// Selects a match in the document, which scrolls it into view.
    ///
    /// - `self`: the find.
    /// - `range`: the match.
    fn select(self: *Self, range: mod.TextRange) void {
        const document = self.document orelse return;
        const length = document.text().len;
        document.selection_anchor = @min(range.start, length);
        document.caret = @min(range.end, length);
        document.preferred_column = null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

/// A find over a document, with a presented flag, for the tests.
const FindFixture = struct {
    const Self = @This();

    /// The document.
    document: mod.TextFieldState,
    /// The find.
    find: TextFindState,
    /// Whether the bar shows.
    presented: renderer.State(bool),

    /// Makes the fixture over a text and attaches the find.
    ///
    /// - `self`: where the fixture goes.
    /// - `text`: the document's text.
    /// - Returns: nothing; propagates allocation failure.
    fn setUp(self: *Self, text: []const u8) !void {
        self.* = .{
            .document = mod.TextFieldState.init(std.testing.allocator),
            .find = TextFindState.init(std.testing.allocator),
            .presented = renderer.State(bool).init(std.testing.allocator, false),
        };
        try self.document.setText(text);
        self.document.caret = 0;
        self.find.document = &self.document;
        self.find.is_presented = self.presented.binding();
    }

    /// Frees the fixture.
    ///
    /// - `self`: the fixture.
    fn tearDown(self: *Self) void {
        mod.Focus.shared().clear();
        self.presented.deinit();
        self.find.deinit();
        self.document.deinit();
    }
};

test "find: next and previous wrap, and the count names the selected match" {
    var fixture: FindFixture = undefined;
    try fixture.setUp("one two one three one");
    defer fixture.tearDown();
    const find = &fixture.find;
    try find.query.setText("one");
    try std.testing.expectEqual(@as(?mod.FindCount, .{ .total = 3 }), find.count());
    find.findNext(); // the match at the caret
    try std.testing.expectEqual(@as(?mod.FindCount, .{ .current = 0, .total = 3 }), find.count());
    find.findNext();
    find.findNext();
    try std.testing.expectEqual(@as(?usize, 2), find.currentIndex());
    find.findNext(); // wraps to the first
    try std.testing.expectEqual(@as(?usize, 0), find.currentIndex());
    find.findPrevious(); // wraps to the last
    try std.testing.expectEqual(@as(?usize, 2), find.currentIndex());
    find.findPrevious();
    try std.testing.expectEqual(@as(?usize, 1), find.currentIndex());
}

test "find: replace takes the current match then selects the next; replace all is one undo step" {
    var fixture: FindFixture = undefined;
    try fixture.setUp("cat cat dog cat");
    defer fixture.tearDown();
    const find = &fixture.find;
    try find.query.setText("cat");
    try find.replacement.setText("bird");
    find.replaceCurrent(); // nothing selected: selects the first
    try std.testing.expectEqualStrings("cat cat dog cat", fixture.document.text());
    find.replaceCurrent();
    try std.testing.expectEqualStrings("bird cat dog cat", fixture.document.text());
    try std.testing.expectEqual(@as(?usize, 0), find.currentIndex()); // the next "cat"
    try std.testing.expectEqual(@as(usize, 2), find.replaceAll());
    try std.testing.expectEqualStrings("bird bird dog bird", fixture.document.text());
    _ = try fixture.document.undo();
    try std.testing.expectEqualStrings("bird cat dog cat", fixture.document.text());
}

test "find: the keys open it from the editor, Esc closes it, and the selection seeds it" {
    var fixture: FindFixture = undefined;
    try fixture.setUp("alpha beta alpha");
    defer fixture.tearDown();
    const find = &fixture.find;
    fixture.document.selection_anchor = 0;
    fixture.document.caret = 5; // "alpha"
    try std.testing.expect(find.handleKey(.{ .char = 'f', .command = true }, true));
    try std.testing.expect(fixture.presented.get());
    try std.testing.expectEqualStrings("alpha", find.query.text());
    try std.testing.expect(mod.Focus.shared().focused() == &find.query);
    try std.testing.expect(!find.shows_replace);
    try std.testing.expect(find.handleKey(.{ .char = 'f', .command = true, .alt = true }, true));
    try std.testing.expect(find.shows_replace);
    try std.testing.expect(find.handleKey(.{ .char = 'g', .command = true }, true));
    try std.testing.expectEqual(@as(?usize, 1), find.currentIndex());
    try std.testing.expect(find.handleKey(.{ .name = .escape }, true));
    try std.testing.expect(!fixture.presented.get());
    try std.testing.expect(mod.Focus.shared().focused() == &fixture.document);
    // Off macOS, Ctrl+H opens it with the replace row.
    try std.testing.expect(find.handleKey(.{ .char = 'h', .command = true }, false));
    try std.testing.expect(find.shows_replace and fixture.presented.get());
    // Closed, ⌘G is not the find's, nor a character past ASCII.
    find.close();
    try std.testing.expect(!find.handleKey(.{ .char = 'g', .command = true }, true));
    try std.testing.expect(!find.handleKey(.{ .char = 0x00E9, .command = true }, true));
}

test "find: an editor with a navigator shows the bar while presented, and its keys reach it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var fixture: FindFixture = undefined;
    try fixture.setUp("needle in a haystack, needle");
    defer fixture.tearDown();
    var scroll: mod.ScrollState = .{};
    mod.Focus.shared().set(&fixture.document);
    window.begin(renderer.MacosTheme.light);
    _ = mod.TextEditor(&fixture.document, &scroll, false).findNavigator(fixture.presented.binding(), &fixture.find);
    window.end();
    try std.testing.expect(TextFindState.keyDown(.{ .char = 'f', .command = true }, true));
    try std.testing.expect(fixture.presented.get());
    try fixture.find.query.setText("needle");
    window.begin(renderer.MacosTheme.light);
    const view = mod.TextEditor(&fixture.document, &scroll, false).findNavigator(fixture.presented.binding(), &fixture.find);
    window.end();
    // Typing the query chose the first match.
    try std.testing.expectEqual(@as(?usize, 0), fixture.find.currentIndex());
    var frame = try window.render(view, 600, 300);
    defer frame.deinit();
    try std.testing.expectEqual(@as(?mod.FindCount, .{ .current = 0, .total = 2 }), fixture.find.count());
}
