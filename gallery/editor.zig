const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_editor);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The document the editor opens on, and what Open loads (it reads no files).
const sample_document =
    \\// edit.zig — a ziggui text editor
    \\const std = @import("std");
    \\
    \\pub fn main() void {
    \\    const greeting = "Hello, ziggui!";
    \\    std.debug.print("{s}\n", .{greeting});
    \\
    \\    // Click to place the caret, drag to select (or Shift+arrows),
    \\    // ⌘F to find, ⌘S to save.
    \\    var total: usize = 0;
    \\    for (0..10) |i| total += i;
    \\}
;

/// The zoom ladder's step that draws the body size.
const zoom_body: i64 = 3;

/// The zoom ladder's largest step.
const zoom_largest: i64 = 6;

/// The longest status message kept, in bytes.
const status_capacity: usize = 256;

/// A small plain-text editor in the spirit of TextEdit, gedit or Notepad,
/// folded in from zigui's edit example: a toolbar, a multi-line
/// `TextEditor` with line numbers, a `FindBar` (⌘F) with wrap-around and
/// its match count, zoom
/// (⌘+, ⌘-, ⌘0), a status bar, and a path dialog for Open and Save As.
///
/// It edits text in memory: Open loads the sample document under the name
/// given, and Save keeps the text where it is and marks it saved.
pub const Editor = struct {
    const Self = @This();

    /// Allocates the editor's buffers.
    allocator: std.mem.Allocator,

    /// The document's buffer, caret and selection.
    document: ziggui.TextFieldState,

    /// The document's scroll position.
    document_scroll: ziggui.ScrollState = .{},

    /// The document's path, empty for a never-saved "Untitled".
    path: std.ArrayList(u8) = .empty,

    /// The document's revision when it was last saved or opened.
    saved_revision: u64 = 0,

    /// Whether the editor shows line numbers.
    line_numbers: ziggui.State(bool),

    /// Whether the editor draws in the fixed-width face (`TextEditor.mono()`).
    monospaced: ziggui.State(bool),

    /// The zoom, a step of the font-size ladder (`zoom_body` is the body size).
    zoom: ziggui.State(i64),

    /// Whether the path dialog is presented.
    show_dialog: ziggui.State(bool),

    /// Whether the path dialog saves (Save As) rather than opens.
    dialog_save: bool = false,

    /// The path dialog's field.
    path_field: ziggui.TextFieldState,

    /// Whether the find bar shows.
    show_find: ziggui.State(bool),

    /// The find bar's field.
    find_field: ziggui.TextFieldState,

    /// The status message's bytes ("Saved", "Not found").
    status_buffer: [status_capacity]u8 = undefined,

    /// How many of `status_buffer`'s bytes are the message.
    status_length: usize = 0,

    /// Constructs an editor on the sample document, unmodified, with line numbers.
    ///
    /// - `allocator`: allocator for the buffers; must outlive the editor.
    /// - Returns: the editor; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        var self = Self{
            .allocator = allocator,
            .document = ziggui.TextFieldState.init(allocator),
            .line_numbers = ziggui.State(bool).init(allocator, true),
            .monospaced = ziggui.State(bool).init(allocator, false),
            .zoom = ziggui.State(i64).init(allocator, zoom_body),
            .show_dialog = ziggui.State(bool).init(allocator, false),
            .path_field = ziggui.TextFieldState.init(allocator),
            .show_find = ziggui.State(bool).init(allocator, false),
            .find_field = ziggui.TextFieldState.init(allocator),
        };
        errdefer self.deinit();
        self.document.multiline = true;
        try self.load(sample_document);
        self.setStatus("Ready", .{});
        return self;
    }

    /// Releases the editor's buffers, and the keyboard focus if one of its fields holds it.
    ///
    /// - `self`: the editor to tear down.
    pub fn deinit(self: *Self) void {
        self.releaseFocus();
        self.find_field.deinit();
        self.show_find.deinit();
        self.path_field.deinit();
        self.show_dialog.deinit();
        self.zoom.deinit();
        self.monospaced.deinit();
        self.line_numbers.deinit();
        self.path.deinit(self.allocator);
        self.document.deinit();
    }

    /// Builds the editor: the toolbar, the document, the find bar while it
    /// shows, and the status bar, with the path dialog presented over them.
    ///
    /// - `self`: the editor.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the editor's view, filling the space it is given.
    pub fn body(self: *Self, theme: ziggui.Theme) ziggui.View {
        const document = ziggui.TextEditor(&self.document, &self.document_scroll, self.line_numbers.get());
        const editor = Self.zoomed(if (self.monospaced.get()) document.mono() else document, self.zoom.get())
            .frameMaxWidth()
            .frameMaxHeight()
            .paddingInsets(.{ .top = 8, .leading = 10, .bottom = 8, .trailing = 10 });

        // The column, with the find bar spliced in only while it shows.
        var rows: [6]ziggui.View = undefined;
        var count: usize = 0;
        rows[count] = self.toolbar();
        count += 1;
        rows[count] = ziggui.Divider();
        count += 1;
        rows[count] = editor;
        count += 1;
        if (self.show_find.get()) {
            rows[count] = ziggui.FindBar("Find", &self.find_field, self.findCount(), self.findActions());
            count += 1;
        }
        rows[count] = ziggui.Divider();
        count += 1;
        rows[count] = self.statusBar(theme);
        count += 1;

        return ziggui.VStack(rows[0..count])
            .spacing(0)
            .frameMaxWidth()
            .frameMaxHeight()
            .alert(self.show_dialog.binding(), self.dialogView(theme));
    }

    /// A key went down while the editor shows: the find bar's keys while it
    /// shows (`ziggui.FindActions.handleKey`: Esc, Shift-Enter, ⌘G), then
    /// the ⌘ (Ctrl off macOS) shortcuts. Copy, cut, paste and select all are
    /// left to the loop, which does them for the focused field.
    ///
    /// - `self`: the editor.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when the key was the find bar's or a shortcut, so no
    ///   field takes it; false for every key while the path dialog is up,
    ///   which is modal.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (self.show_dialog.get()) return false;
        if (self.show_find.get()) {
            if (ziggui.Key.fromSdl(keycode, modifiers, gallery.is_macos)) |key| {
                if (self.findActions().handleKey(key, &self.find_field)) return true;
            }
        }
        if (modifiers & (ziggui.SdlKey.gui_mask | ziggui.SdlKey.ctrl_mask) == 0) return false;
        switch (keycode) {
            's' => self.save(),
            'o' => self.openDialog(),
            'n' => self.newDocument(),
            'f' => self.toggleFind(),
            '=', '+' => self.zoomBy(1),
            '-' => self.zoomBy(-1),
            '0' => self.zoom.set(zoom_body),
            else => return false,
        }
        return true;
    }

    /// Takes the keyboard focus, as the editor comes into view: the path
    /// dialog's field while it is presented, else the document.
    ///
    /// - `self`: the editor.
    pub fn focus(self: *Self) void {
        ziggui.Focus.shared().set(if (self.show_dialog.get()) &self.path_field else &self.document);
    }

    /// Gives up the keyboard focus if one of the editor's fields holds it, as
    /// the editor leaves view (keys must not reach a field not drawn).
    ///
    /// - `self`: the editor.
    pub fn releaseFocus(self: *Self) void {
        const field = ziggui.Focus.shared().focused() orelse return;
        if (field == &self.document or field == &self.path_field or field == &self.find_field) ziggui.Focus.shared().clear();
    }

    /// Reports whether the document changed since it was last saved or opened.
    ///
    /// - `self`: the editor.
    /// - Returns: true when it has unsaved changes.
    pub fn isDirty(self: *const Self) bool {
        return self.document.revision != self.saved_revision;
    }

    /// The document's name: its path's last component, or "Untitled".
    ///
    /// - `self`: the editor.
    /// - Returns: the name, borrowed from the editor.
    pub fn name(self: *const Self) []const u8 {
        const path = self.path.items;
        if (path.len == 0) return "Untitled";
        const slash = std.mem.findScalarLast(u8, path, '/') orelse return path;
        return path[slash + 1 ..];
    }

    /// The status message.
    ///
    /// - `self`: the editor.
    /// - Returns: the message, borrowed from the editor.
    pub fn status(self: *const Self) []const u8 {
        return self.status_buffer[0..self.status_length];
    }

    /// Starts an empty, untitled document.
    ///
    /// - `self`: the editor.
    pub fn newDocument(self: *Self) void {
        self.load("") catch |err| {
            self.setStatus("No new document [{t}]", .{err});
            return;
        };
        self.path.clearRetainingCapacity();
        ziggui.Focus.shared().set(&self.document);
        self.setStatus("New document", .{});
    }

    /// Presents the path dialog to open a document.
    ///
    /// - `self`: the editor.
    pub fn openDialog(self: *Self) void {
        self.presentDialog(false);
    }

    /// Presents the path dialog to save the document under a new path.
    ///
    /// - `self`: the editor.
    pub fn saveAsDialog(self: *Self) void {
        self.presentDialog(true);
    }

    /// Saves the document: marks it saved under its path, or asks for one
    /// first when it has none.
    ///
    /// - `self`: the editor.
    pub fn save(self: *Self) void {
        if (self.path.items.len == 0) return self.saveAsDialog();
        self.saved_revision = self.document.revision;
        self.setStatus("Saved {s} (in memory)", .{self.name()});
    }

    /// The path dialog's confirm button (and Enter in its field): opens or
    /// saves as, by the dialog's mode.
    ///
    /// - `self`: the editor.
    pub fn confirmDialog(self: *Self) void {
        if (self.dialog_save) self.saveAs() else self.open();
    }

    /// Dismisses the path dialog, back to the document.
    ///
    /// - `self`: the editor.
    pub fn cancelDialog(self: *Self) void {
        self.show_dialog.set(false);
        ziggui.Focus.shared().set(&self.document);
    }

    /// Shows or hides the find bar, focusing its field or the document.
    ///
    /// - `self`: the editor.
    pub fn toggleFind(self: *Self) void {
        const showing = !self.show_find.get();
        self.show_find.set(showing);
        ziggui.Focus.shared().set(if (showing) &self.find_field else &self.document);
    }

    /// Selects the next match of the find field's text after the caret,
    /// wrapping to the top.
    ///
    /// - `self`: the editor.
    pub fn findNext(self: *Self) void {
        const needle = self.find_field.text();
        if (needle.len == 0) return;
        const haystack = self.document.text();
        const from = @min(self.document.caret, haystack.len);
        const hit = std.mem.findPos(u8, haystack, from, needle) orelse std.mem.find(u8, haystack, needle);
        if (hit) |index| self.selectMatch(index, needle.len) else self.setStatus("Not found", .{});
    }

    /// Selects the previous match of the find field's text before the
    /// selection, wrapping to the bottom.
    ///
    /// - `self`: the editor.
    pub fn findPrevious(self: *Self) void {
        const needle = self.find_field.text();
        if (needle.len == 0) return;
        const haystack = self.document.text();
        const before = if (self.document.selectionRange()) |selection| selection.start else self.document.caret;
        const earlier = if (before > 0) std.mem.findLast(u8, haystack[0..before], needle) else null;
        const hit = earlier orelse std.mem.findLast(u8, haystack, needle);
        if (hit) |index| self.selectMatch(index, needle.len) else self.setStatus("Not found", .{});
    }

    /// What the find bar's field, buttons and keys do: Enter and Next find
    /// the next match, Previous the one before, Done closes the bar.
    ///
    /// - `self`: the editor.
    /// - Returns: the actions, pointing at the editor.
    pub fn findActions(self: *Self) ziggui.FindActions {
        return .{
            .on_submit = ziggui.Callback.init(Self, self, Self.findNext),
            .on_next = ziggui.Callback.init(Self, self, Self.findNext),
            .on_previous = ziggui.Callback.init(Self, self, Self.findPrevious),
            .on_done = ziggui.Callback.init(Self, self, Self.toggleFind),
        };
    }

    /// Where the find stands: the find field's matches in the document
    /// (each found past the one before it, as Next steps), and which is
    /// selected.
    ///
    /// - `self`: the editor.
    /// - Returns: the count, or null while the field is empty.
    pub fn findCount(self: *const Self) ?ziggui.FindCount {
        const needle = self.find_field.text();
        if (needle.len == 0) return null;
        const haystack = self.document.text();
        const selected = self.document.selectionRange();
        var count: ziggui.FindCount = .{ .total = 0 };
        var from: usize = 0;
        while (std.mem.findPos(u8, haystack, from, needle)) |index| {
            if (selected) |range| {
                if (range.start == index and range.end == index + needle.len) count.current = count.total;
            }
            count.total += 1;
            from = index + needle.len;
        }
        return count;
    }

    /// Shows the find bar searching for `needle`, its first match after the
    /// caret selected (the `--find` demo).
    ///
    /// - `self`: the editor.
    /// - `needle`: the text to find.
    pub fn showMatch(self: *Self, needle: []const u8) void {
        self.show_find.set(true);
        self.find_field.setText(needle) catch |err| {
            log.warn("the find field was not filled [{t}]", .{err});
            return;
        };
        self.findNext();
    }

    /// Selects from the first `from` to the first `to` after it (the `--select` demo).
    ///
    /// - `self`: the editor.
    /// - `from`: the text the selection starts at.
    /// - `to`: the text the selection ends before.
    pub fn selectBetween(self: *Self, from: []const u8, to: []const u8) void {
        const text = self.document.text();
        const start = std.mem.find(u8, text, from) orelse return;
        self.document.selection_anchor = start;
        self.document.caret = std.mem.findPos(u8, text, start, to) orelse text.len;
    }

    /// Moves the zoom `delta` steps along the font-size ladder, within it.
    ///
    /// - `self`: the editor.
    /// - `delta`: the steps; negative zooms out.
    pub fn zoomBy(self: *Self, delta: i64) void {
        self.zoom.set(std.math.clamp(self.zoom.get() + delta, 0, zoom_largest));
    }

    /// Replaces the document with `text`, caret at the top, scrolled to the
    /// top, and unmodified.
    ///
    /// - `self`: the editor.
    /// - `text`: the new text.
    /// - Returns: nothing; propagates allocation failure.
    fn load(self: *Self, text: []const u8) !void {
        try self.document.setText(text);
        // `setText` leaves the caret at the end; a document opens at the top.
        self.document.caret = 0;
        self.document.last_caret = 0;
        self.document_scroll.offset = 0;
        self.saved_revision = self.document.revision;
    }

    /// Presents the path dialog, prefilled with the document's path.
    ///
    /// - `self`: the editor.
    /// - `saving`: true for Save As, false for Open.
    fn presentDialog(self: *Self, saving: bool) void {
        self.dialog_save = saving;
        self.path_field.setText(self.path.items) catch |err| {
            log.warn("the path field was not prefilled [{t}]", .{err});
        };
        self.show_dialog.set(true);
        ziggui.Focus.shared().set(&self.path_field);
    }

    /// Opens the dialog's path: loads the sample document under its name.
    ///
    /// - `self`: the editor.
    fn open(self: *Self) void {
        if (self.path_field.text().len == 0) return;
        self.setPath(self.path_field.text());
        self.show_dialog.set(false);
        self.load(sample_document) catch |err| {
            self.setStatus("Could not open {s} [{t}]", .{ self.name(), err });
            return;
        };
        ziggui.Focus.shared().set(&self.document);
        self.setStatus("Opened {s} ({d} bytes)", .{ self.name(), sample_document.len });
    }

    /// Saves the document under the dialog's path.
    ///
    /// - `self`: the editor.
    fn saveAs(self: *Self) void {
        if (self.path_field.text().len == 0) return;
        self.setPath(self.path_field.text());
        self.show_dialog.set(false);
        self.saved_revision = self.document.revision;
        ziggui.Focus.shared().set(&self.document);
        self.setStatus("Saved {s} (in memory)", .{self.name()});
    }

    /// Selects a match, which scrolls it into view (the editor follows the caret).
    ///
    /// - `self`: the editor.
    /// - `index`: the match's first byte.
    /// - `length`: the match's length, in bytes.
    fn selectMatch(self: *Self, index: usize, length: usize) void {
        self.document.selection_anchor = index;
        self.document.caret = index + length;
        self.setStatus("Match at byte {d}", .{index});
    }

    /// Sets the document's path.
    ///
    /// - `self`: the editor.
    /// - `path`: the new path; copied.
    fn setPath(self: *Self, path: []const u8) void {
        self.path.clearRetainingCapacity();
        self.path.appendSlice(self.allocator, path) catch |err| {
            log.warn("the path was not kept [{t}]", .{err});
        };
    }

    /// Sets the status message, cut short at `status_capacity` bytes.
    ///
    /// - `self`: the editor.
    /// - `format`: the message's format.
    /// - `args`: the format's arguments.
    fn setStatus(self: *Self, comptime format: []const u8, args: anytype) void {
        var writer: std.Io.Writer = .fixed(&self.status_buffer);
        // A full buffer keeps the message's start.
        writer.print(format, args) catch |err| log.debug("status cut short [{t}]", .{err});
        self.status_length = writer.end;
    }

    /// The toolbar: the document's name, a dot while modified, and the
    /// monospaced and line-number toggles and the file buttons.
    ///
    /// - `self`: the editor.
    /// - Returns: the toolbar.
    fn toolbar(self: *Self) ziggui.View {
        const title = ziggui.BuildScope.shared().allocator().print("{s}{s}", .{ self.name(), if (self.isDirty()) " •" else "" }) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Text(title).font(.headline),
            ziggui.Spacer(),
            ziggui.Toggle("Monospaced", self.monospaced.binding()),
            ziggui.Toggle("Line numbers", self.line_numbers.binding()),
            ziggui.ButtonRoled("New", .plain, ziggui.Callback.init(Self, self, Self.newDocument)),
            ziggui.ButtonRoled("Open", .plain, ziggui.Callback.init(Self, self, Self.openDialog)),
            ziggui.ButtonRoled("Save As", .plain, ziggui.Callback.init(Self, self, Self.saveAsDialog)),
            ziggui.Button("Save", ziggui.Callback.init(Self, self, Self.save)),
        }).spacing(12)
            .paddingInsets(.{ .top = 9, .leading = 14, .bottom = 9, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The status bar: the caret's line and column, the document's
    /// characters and lines, the code name it shows, and the status message.
    ///
    /// - `self`: the editor.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the status bar.
    fn statusBar(self: *Self, theme: ziggui.Theme) ziggui.View {
        const text = self.document.text();
        const caret = self.document.lineColumn();
        const characters = std.unicode.utf8CountCodepoints(text) catch text.len;
        const lines = std.mem.count(u8, text, "\n") + 1;
        const counts = ziggui.BuildScope.shared().allocator().print("Ln {d}, Col {d}    {d} chars    {d} lines", .{ caret.line, caret.column, characters, lines }) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Text(counts).font(.footnote).foreground(theme.colors.secondary_label),
            ziggui.Spacer(),
            gallery.CardName.shared().view(if (self.show_find.get()) "ziggui.TextEditor · ziggui.FindBar · ziggui.FindCount · ziggui.FindActions" else "ziggui.TextEditor", theme.colors.tertiary_label),
            ziggui.Text(self.status()).font(.footnote).foreground(theme.colors.tertiary_label),
        }).spacing(14)
            .paddingInsets(.{ .top = 6, .leading = 14, .bottom = 6, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The path dialog: a title, the path field, Cancel and the confirm button.
    ///
    /// - `self`: the editor.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the dialog's content.
    fn dialogView(self: *Self, theme: ziggui.Theme) ziggui.View {
        const confirm = ziggui.Callback.init(Self, self, Self.confirmDialog);
        return ziggui.VStack(.{
            ziggui.Text(if (self.dialog_save) "Save As" else "Open").font(.title3).frameMaxWidth().frameAlign(.leading),
            ziggui.Text("File path:").font(.subheadline).foreground(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.TextField("/path/to/file.txt", &self.path_field)
                .frameMaxWidth()
                .onSubmit(confirm),
            ziggui.HStack(.{
                ziggui.Spacer(),
                ziggui.ButtonRoled("Cancel", .plain, ziggui.Callback.init(Self, self, Self.cancelDialog)),
                ziggui.Button(if (self.dialog_save) "Save" else "Open", confirm),
            }).frameMaxWidth(),
        }).spacing(14).padding(20).frameWidth(460);
    }

    /// Draws `content` at the zoom's step of the font-size ladder.
    ///
    /// - `content`: the view to size.
    /// - `zoom`: the step, 0 (smallest) to `zoom_largest`.
    /// - Returns: the sized view.
    fn zoomed(content: ziggui.View, zoom: i64) ziggui.View {
        return switch (zoom) {
            0 => content.font(.caption2),
            1 => content.font(.footnote),
            2 => content.font(.callout),
            4 => content.font(.headline),
            5 => content.font(.title3),
            6 => content.font(.title2),
            else => content.font(.body),
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Editor);
}

test "the editor opens on the sample document, unmodified and untitled" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try std.testing.expectEqualStrings(sample_document, editor.document.text());
    try std.testing.expect(!editor.isDirty());
    try std.testing.expectEqualStrings("Untitled", editor.name());
    try std.testing.expectEqualStrings("Ready", editor.status());
    try std.testing.expectEqual(@as(usize, 0), editor.document.caret);
}

test "find selects the next match, wraps, and says when there is none" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.find_field.setText("greeting");
    editor.findNext();
    const first = std.mem.find(u8, sample_document, "greeting").?;
    try std.testing.expectEqual(@as(?usize, first), editor.document.selection_anchor);
    editor.findNext();
    const second = std.mem.findPos(u8, sample_document, first + 1, "greeting").?;
    try std.testing.expectEqual(@as(?usize, second), editor.document.selection_anchor);
    // Past the last, the next wraps to the first; before the first, the previous wraps to the last.
    editor.findNext();
    try std.testing.expectEqual(@as(?usize, first), editor.document.selection_anchor);
    editor.findPrevious();
    try std.testing.expectEqual(@as(?usize, second), editor.document.selection_anchor);

    try editor.find_field.setText("absent");
    editor.findNext();
    try std.testing.expectEqualStrings("Not found", editor.status());
}

test "the find count says which match is selected, of how many" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try std.testing.expectEqual(@as(?ziggui.FindCount, null), editor.findCount());
    try editor.find_field.setText("greeting");
    try std.testing.expectEqual(@as(?ziggui.FindCount, .{ .total = 2 }), editor.findCount());
    editor.findNext();
    try std.testing.expectEqual(@as(?ziggui.FindCount, .{ .current = 0, .total = 2 }), editor.findCount());
    editor.findNext();
    try std.testing.expectEqual(@as(?ziggui.FindCount, .{ .current = 1, .total = 2 }), editor.findCount());
    try editor.find_field.setText("absent");
    try std.testing.expectEqual(@as(?ziggui.FindCount, .{ .total = 0 }), editor.findCount());
}

test "the find bar takes Shift-Enter in its field and Esc, and leaves Shift-Enter to the document" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    editor.showMatch("greeting");
    editor.findNext();
    const second = editor.document.selection_anchor;
    // In the document, Shift-Enter is the document's newline.
    ziggui.Focus.shared().set(&editor.document);
    try std.testing.expect(!editor.keyDown(ziggui.SdlKey.enter, ziggui.SdlKey.left_shift_mask));
    try std.testing.expectEqual(second, editor.document.selection_anchor);
    // In the find field, it goes to the previous match.
    ziggui.Focus.shared().set(&editor.find_field);
    try std.testing.expect(editor.keyDown(ziggui.SdlKey.enter, ziggui.SdlKey.left_shift_mask));
    try std.testing.expect(editor.document.selection_anchor != second);
    // Esc closes the bar, back to the document.
    try std.testing.expect(editor.keyDown(ziggui.SdlKey.escape, 0));
    try std.testing.expect(!editor.show_find.get());
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &editor.document), ziggui.Focus.shared().focused());
}

test "Save As names the document and marks it saved; New empties it" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.document.insert("x");
    try std.testing.expect(editor.isDirty());
    // Untitled, Save asks for a path.
    editor.save();
    try std.testing.expect(editor.show_dialog.get() and editor.dialog_save);
    try editor.path_field.setText("/tmp/notes.txt");
    editor.confirmDialog();
    try std.testing.expect(!editor.show_dialog.get());
    try std.testing.expectEqualStrings("notes.txt", editor.name());
    try std.testing.expect(!editor.isDirty());

    editor.newDocument();
    try std.testing.expectEqualStrings("", editor.document.text());
    try std.testing.expectEqualStrings("Untitled", editor.name());
}

test "the shortcuts take ⌘ or Ctrl, and zoom stays on its ladder" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try std.testing.expect(!editor.keyDown('f', 0));
    try std.testing.expect(editor.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(editor.show_find.get());
    try std.testing.expect(editor.keyDown('f', ziggui.SdlKey.left_ctrl_mask));
    try std.testing.expect(!editor.show_find.get());
    for (0..10) |_| _ = editor.keyDown('=', ziggui.SdlKey.left_ctrl_mask);
    try std.testing.expectEqual(zoom_largest, editor.zoom.get());
    _ = editor.keyDown('0', ziggui.SdlKey.left_ctrl_mask);
    try std.testing.expectEqual(zoom_body, editor.zoom.get());
    // Copy is the loop's to do.
    try std.testing.expect(!editor.keyDown('c', ziggui.SdlKey.left_ctrl_mask));
}

test "behind the path dialog the shortcuts do nothing" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.document.insert("x");
    editor.openDialog();
    try std.testing.expect(!editor.keyDown('n', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(!editor.keyDown('f', ziggui.SdlKey.left_ctrl_mask));
    try std.testing.expect(!editor.keyDown('=', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(!editor.show_find.get());
    try std.testing.expect(editor.isDirty());
    try std.testing.expectEqual(zoom_body, editor.zoom.get());
    // Dismissed, they work again.
    editor.cancelDialog();
    try std.testing.expect(editor.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(editor.show_find.get());
}

test "the editor draws with the find bar and the dialog" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();

    editor.toggleFind();
    editor.openDialog();
    const theme = ziggui.ThemeFamily.all[0].forScheme(.dark);
    window.begin(theme);
    const root = editor.body(theme);
    window.end();
    var framebuffer = try window.render(root, gallery.test_width, gallery.test_height);
    defer framebuffer.deinit();
    try std.testing.expectEqual(@as(usize, 1), window.overlays.items.len);
}
