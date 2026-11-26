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
    \\    // ⌘F to find, ⌥⌘F to replace, ⌘Z to undo, ⌘S to save.
    \\    var total: usize = 0;
    \\    for (0..10) |i| total += i;
    \\}
;

/// A second document Open offers, as a Windows tool saves it: CRLF line
/// endings and tab indentation, which `loadDocument` finds as it loads.
const legacy_document = "/* legacy.c: saved on Windows, CRLF line endings and tab indentation */\r\n" ++
    "#include <stdio.h>\r\n" ++
    "\r\n" ++
    "int main(void)\r\n" ++
    "{\r\n" ++
    "\tint total = 0;\r\n" ++
    "\tfor (int i = 0; i < 10; i++) {\r\n" ++
    "\t\ttotal += i;\r\n" ++
    "\t}\r\n" ++
    "\tprintf(\"%d\\n\", total);\r\n" ++
    "\treturn 0;\r\n" ++
    "}\r\n";

/// The documents Open loads, by the dialog's sample menu.
const samples = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "edit.zig", .text = sample_document },
    .{ .name = "legacy.c", .text = legacy_document },
};

/// The dialog's sample menu, in `samples`' order.
const sample_options = [_][]const u8{ "edit.zig (LF, spaces)", "legacy.c (CRLF, tabs)" };

/// The longest status message kept, in bytes.
const status_capacity: usize = 256;

/// The indentation menu's choices, in `indentation_choices`' order.
const indentation_options = [_][]const u8{ "Spaces: 2", "Spaces: 4", "Spaces: 8", "Tabs: 4" };

/// What each indentation choice is.
const indentation_choices = [_]ziggui.TextIndentation{
    .{ .style = .spaces, .width = 2 },
    .{ .style = .spaces, .width = 4 },
    .{ .style = .spaces, .width = 8 },
    .{ .style = .tabs, .width = 4 },
};

/// The line-ending picker's choices, in `ziggui.LineEnding`'s order.
const line_ending_options = [_][]const u8{ "LF", "CRLF" };

/// The size ⌘0 puts the face in use back to, in points.
const default_size: f32 = 13;

/// The names line under the status bar, the find bar hidden.
const editor_names = "ziggui.TextEditor · ziggui.TextEditorSettings · ziggui.TextEditorColors · .font(.custom)";

/// The names line under the status bar while the find bar shows.
const find_names = "ziggui.TextEditor · .findNavigator · ziggui.TextFindState · ziggui.FindBar · ziggui.FindActions";

/// A toggle's binding to one of the editor's boolean settings.
const SettingBinding = struct {
    const Self = @This();

    /// A binding to `settings.<field>`.
    ///
    /// - `editor`: the editor.
    /// - `field`: the setting's name.
    /// - Returns: the binding.
    fn of(editor: *Editor, comptime field: []const u8) ziggui.Binding(bool) {
        const Access = struct {
            const Self = @This();

            /// Reads the setting.
            ///
            /// - `context`: the editor.
            /// - Returns: its value.
            fn get(context: *anyopaque) bool {
                const target: *Editor = @ptrCast(@alignCast(context));
                return @field(target.settings, field);
            }

            /// Writes the setting.
            ///
            /// - `context`: the editor.
            /// - `value`: the new value.
            fn set(context: *anyopaque, value: bool) void {
                const target: *Editor = @ptrCast(@alignCast(context));
                @field(target.settings, field) = value;
            }
        };
        return .{ .context = editor, .get_fn = Access.get, .set_fn = Access.set };
    }
};

/// A font menu's binding: a face's family as its place among the registry's.
const FontBinding = struct {
    const Self = @This();

    /// A binding to the proportional or the monospaced face's family.
    ///
    /// - `editor`: the editor.
    /// - `mono`: true for the monospaced face.
    /// - Returns: the binding.
    fn of(editor: *Editor, comptime mono: bool) ziggui.Binding(i64) {
        const Access = struct {
            const Self = @This();

            /// The face's place among the families, 0 when it is none of them.
            ///
            /// - `context`: the editor.
            /// - Returns: the index.
            fn get(context: *anyopaque) i64 {
                const target: *Editor = @ptrCast(@alignCast(context));
                const wanted = if (mono) target.settings.mono_font else target.settings.proportional_font;
                return @intCast(ziggui.FontRegistry.shared().familyIndex(wanted) orelse 0);
            }

            /// Chooses the family at a place.
            ///
            /// - `context`: the editor.
            /// - `value`: the index.
            fn set(context: *anyopaque, value: i64) void {
                const target: *Editor = @ptrCast(@alignCast(context));
                const family = ziggui.FontRegistry.shared().familyName(@intCast(@max(value, 0))) orelse return;
                if (mono) target.settings.mono_font = family else target.settings.proportional_font = family;
            }
        };
        return .{ .context = editor, .get_fn = Access.get, .set_fn = Access.set };
    }
};

/// The size stepper's binding: the face in use's size, in whole points.
const SizeBinding = struct {
    const Self = @This();

    /// A binding to the face in use's size.
    ///
    /// - `editor`: the editor.
    /// - Returns: the binding.
    fn of(editor: *Editor) ziggui.Binding(i64) {
        return .{ .context = editor, .get_fn = Self.get, .set_fn = Self.set };
    }

    /// Reads the size.
    ///
    /// - `context`: the editor.
    /// - Returns: the size, rounded.
    fn get(context: *anyopaque) i64 {
        const target: *Editor = @ptrCast(@alignCast(context));
        return @intFromFloat(@round(target.settings.face().size));
    }

    /// Sets the size.
    ///
    /// - `context`: the editor.
    /// - `value`: the new size.
    fn set(context: *anyopaque, value: i64) void {
        const target: *Editor = @ptrCast(@alignCast(context));
        target.settings.resize(@as(f32, @floatFromInt(value)) - target.settings.face().size);
    }
};

/// The indentation menu's binding: the settings' and the document's indentation.
const IndentationBinding = struct {
    const Self = @This();

    /// A binding to the indentation, as a place in `indentation_choices`.
    ///
    /// - `editor`: the editor.
    /// - Returns: the binding.
    fn of(editor: *Editor) ziggui.Binding(i64) {
        return .{ .context = editor, .get_fn = Self.get, .set_fn = Self.set };
    }

    /// The choice the settings' indentation is.
    ///
    /// - `context`: the editor.
    /// - Returns: its index, 1 (four spaces) when it is none of them.
    fn get(context: *anyopaque) i64 {
        const target: *Editor = @ptrCast(@alignCast(context));
        for (indentation_choices, 0..) |choice, index| {
            if (std.meta.eql(choice, target.settings.indentation)) return @intCast(index);
        }
        return 1;
    }

    /// Indents the settings and the document as chosen.
    ///
    /// - `context`: the editor.
    /// - `value`: the choice's index.
    fn set(context: *anyopaque, value: i64) void {
        const target: *Editor = @ptrCast(@alignCast(context));
        const choice = indentation_choices[@intCast(std.math.clamp(value, 0, indentation_choices.len - 1))];
        target.settings.indentation = choice;
        target.document.indentation = choice;
    }
};

/// The line-ending picker's binding: the document's ending, and the one new documents get.
const LineEndingBinding = struct {
    const Self = @This();

    /// A binding to the line ending, as its `ziggui.LineEnding` index.
    ///
    /// - `editor`: the editor.
    /// - Returns: the binding.
    fn of(editor: *Editor) ziggui.Binding(i64) {
        return .{ .context = editor, .get_fn = Self.get, .set_fn = Self.set };
    }

    /// The document's ending.
    ///
    /// - `context`: the editor.
    /// - Returns: its index.
    fn get(context: *anyopaque) i64 {
        const target: *Editor = @ptrCast(@alignCast(context));
        return @backingInt(target.document.line_ending);
    }

    /// Sets the document's ending, and the settings'.
    ///
    /// - `context`: the editor.
    /// - `value`: the ending's index.
    fn set(context: *anyopaque, value: i64) void {
        const target: *Editor = @ptrCast(@alignCast(context));
        const ending: ziggui.LineEnding = if (value == 1) .crlf else .lf;
        target.document.setLineEnding(ending);
        target.settings.line_ending = ending;
    }
};

/// What the colors bar's picker colors: the text, the ground, or one of
/// the `TextEditorColors`'s colors.
const ColorTarget = enum {
    const Self = @This();

    /// `TextEditorSettings.foreground`.
    text,
    /// `TextEditorSettings.background`.
    ground,
    /// `TextEditorColors.caret`.
    caret,
    /// `TextEditorColors.selection`.
    selection,
    /// `TextEditorColors.gutter_background`.
    gutter,
    /// `TextEditorColors.gutter_text`.
    lineNumbers,
    /// `TextEditorColors.current_line`.
    currentLine,
    /// `TextEditorColors.find_match`.
    matches,
    /// `TextEditorColors.find_current`.
    currentMatch,

    /// The menu's titles, in the enum's order.
    const labels = [_][]const u8{ "Text", "Ground", "Caret", "Selection", "Gutter", "Line numbers", "Current line", "Matches", "Current match" };

    /// The target at a menu index.
    ///
    /// - `index`: the index, clamped to the menu.
    /// - Returns: the target.
    fn at(index: i64) Self {
        return @fromBackingInt(@intCast(std.math.clamp(index, 0, labels.len - 1)));
    }

    /// Where the settings keep the target's color.
    ///
    /// - `self`: the target.
    /// - `settings`: the editor's settings.
    /// - Returns: the color, null while it is the theme's.
    fn slot(self: *const Self, settings: *ziggui.TextEditorSettings) *?ziggui.Color {
        return switch (self.*) {
            .text => &settings.foreground,
            .ground => &settings.background,
            .caret => &settings.colors.caret,
            .selection => &settings.colors.selection,
            .gutter => &settings.colors.gutter_background,
            .lineNumbers => &settings.colors.gutter_text,
            .currentLine => &settings.colors.current_line,
            .matches => &settings.colors.find_match,
            .currentMatch => &settings.colors.find_current,
        };
    }

    /// The color the editor draws the target in while the settings leave it
    /// to the theme, so the picker shows it (as a swatch of its own).
    ///
    /// - `self`: the target.
    /// - Returns: the theme's color for it.
    fn themeColor(self: *const Self) ziggui.Color {
        const scope = ziggui.BuildScope.shared();
        const colors = scope.theme().colors;
        return switch (self.*) {
            .text => colors.label,
            .ground, .gutter, .currentLine => colors.control_background,
            .caret, .currentMatch => colors.accent,
            .selection => colors.selection,
            .lineNumbers => colors.tertiary_label,
            .matches => scope.tokens().accent_soft,
        };
    }
};

/// The colors bar's picker binding: the color of what its menu names.
const ColorBinding = struct {
    const Self = @This();

    /// A binding to the color the menu names, the theme's while unset.
    ///
    /// - `editor`: the editor.
    /// - Returns: the binding.
    fn of(editor: *Editor) ziggui.Binding(ziggui.Color) {
        return .{ .context = editor, .get_fn = Self.get, .set_fn = Self.set };
    }

    /// Reads the color.
    ///
    /// - `context`: the editor.
    /// - Returns: the color.
    fn get(context: *anyopaque) ziggui.Color {
        const target: *Editor = @ptrCast(@alignCast(context));
        const chosen = ColorTarget.at(target.color_target.get());
        return chosen.slot(&target.settings).* orelse chosen.themeColor();
    }

    /// Picks the color.
    ///
    /// - `context`: the editor.
    /// - `value`: the color.
    fn set(context: *anyopaque, value: ziggui.Color) void {
        const target: *Editor = @ptrCast(@alignCast(context));
        ColorTarget.at(target.color_target.get()).slot(&target.settings).* = value;
    }
};

/// A plain-text editor in the spirit of TextEdit, gedit or Notepad, folded
/// in from zigui's edit example, grown toward a code editor: a toolbar, a
/// format bar (each face's family and the size, the indentation, the line
/// ending, undo and redo, colors), a `TextEditor` whose `.findNavigator`
/// finds and replaces (⌘F, ⌥⌘F), a status bar, and a path dialog for Open
/// and Save As. Its settings are one `ziggui.TextEditorSettings`, which the
/// gallery's window saves.
///
/// It edits text in memory: Open loads the sample document under the name
/// given, and Save keeps the text where it is and marks it saved.
pub const Editor = struct {
    const Self = @This();

    /// Allocates the editor's buffers.
    allocator: std.mem.Allocator,

    /// The document's buffer, caret, selection and undo history.
    document: ziggui.TextFieldState,

    /// The document's scroll position.
    document_scroll: ziggui.ScrollState = .{},

    /// The document's path, empty for a never-saved "Untitled".
    path: std.ArrayList(u8) = .empty,

    /// The document's revision when it was last saved or opened.
    saved_revision: u64 = 0,

    /// The faces, sizes, indentation, gutter, wrapping and colors.
    settings: ziggui.TextEditorSettings = .{},

    /// Whether the colors bar shows.
    show_colors: ziggui.State(bool),

    /// What the colors bar's picker colors, a `ColorTarget` index.
    color_target: ziggui.State(i64),

    /// Which sample Open loads, an index into `samples`.
    sample: ziggui.State(i64),

    /// Whether the path dialog is presented.
    show_dialog: ziggui.State(bool),

    /// Whether the path dialog saves (Save As) rather than opens.
    dialog_save: bool = false,

    /// The path dialog's field.
    path_field: ziggui.TextFieldState,

    /// Whether the find bar shows.
    show_find: ziggui.State(bool),

    /// The find and replace.
    find: ziggui.TextFindState,

    /// The status message's bytes ("Saved", "Replaced 2").
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
            .show_colors = ziggui.State(bool).init(allocator, false),
            .color_target = ziggui.State(i64).init(allocator, 0),
            .sample = ziggui.State(i64).init(allocator, 0),
            .show_dialog = ziggui.State(bool).init(allocator, false),
            .path_field = ziggui.TextFieldState.init(allocator),
            .show_find = ziggui.State(bool).init(allocator, false),
            .find = ziggui.TextFindState.init(allocator),
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
        self.find.deinit();
        self.show_find.deinit();
        self.path_field.deinit();
        self.show_dialog.deinit();
        self.sample.deinit();
        self.color_target.deinit();
        self.show_colors.deinit();
        self.path.deinit(self.allocator);
        self.document.deinit();
    }

    /// Builds the editor: the toolbar, the format bar, the colors while they
    /// show, the document with its find bar, and the status bar, with the
    /// path dialog presented over them.
    ///
    /// - `self`: the editor.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the editor's view, filling the space it is given.
    pub fn body(self: *Self, theme: ziggui.Theme) ziggui.View {
        const document = self.settings.apply(ziggui.TextEditor(&self.document, &self.document_scroll, self.settings.line_numbers))
            .findNavigator(self.show_find.binding(), &self.find)
            .frameMaxWidth()
            .frameMaxHeight()
            .paddingInsets(.{ .top = 8, .leading = 10, .bottom = 8, .trailing = 10 });

        // The column, with the colors spliced in only while they show.
        var rows: [9]ziggui.View = undefined;
        var count: usize = 0;
        for ([_]ziggui.View{ self.toolbar(), ziggui.Divider(), self.formatBar(), self.layoutBar() }) |row| {
            rows[count] = row;
            count += 1;
        }
        if (self.show_colors.get()) {
            rows[count] = self.colorBar();
            count += 1;
        }
        for ([_]ziggui.View{ ziggui.Divider(), document, ziggui.Divider(), self.statusBar(theme) }) |row| {
            rows[count] = row;
            count += 1;
        }
        return ziggui.VStack(rows[0..count])
            .spacing(0)
            .frameMaxWidth()
            .frameMaxHeight()
            .alert(self.show_dialog.binding(), self.dialogView(theme));
    }

    /// A key went down while the editor shows: the find's keys (⌘F, ⌥⌘F,
    /// ⌘E, and while it shows ⌘G, Shift-Enter, Esc; `ziggui.TextFindState.handleKey`),
    /// then the ⌘ (Ctrl off macOS) shortcuts. Copy, cut, paste, select all,
    /// undo and redo are left to the loop, which does them for the focused field.
    ///
    /// - `self`: the editor.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when the key was the find's or a shortcut, so no
    ///   field takes it; false for every key while the path dialog is up,
    ///   which is modal.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        if (self.show_dialog.get()) return false;
        if (ziggui.Key.fromSdl(keycode, modifiers, gallery.is_macos)) |key| {
            // The find opens from anywhere in the section, not only the document.
            self.attachFind();
            if (self.find.handleKey(key, gallery.is_macos)) return true;
        }
        if (modifiers & (ziggui.SdlKey.gui_mask | ziggui.SdlKey.ctrl_mask) == 0) return false;
        switch (keycode) {
            's' => self.save(),
            'o' => self.openDialog(),
            'n' => self.newDocument(),
            '=', '+' => self.settings.resize(1),
            '-' => self.settings.resize(-1),
            '0' => self.settings.resize(default_size - self.settings.face().size),
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
        if (field == &self.document or field == &self.path_field or field == &self.find.query or field == &self.find.replacement) ziggui.Focus.shared().clear();
    }

    /// Reports whether the document changed since it was last saved or
    /// opened (an undo back to that point reads unchanged).
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

    /// Takes saved settings: each face's family as the registry names it
    /// (a family no longer registered keeps the bundled one), and the rest
    /// as they were; the document takes the indentation.
    ///
    /// - `self`: the editor.
    /// - `saved`: the settings read back; its strings may be freed after.
    pub fn restoreSettings(self: *Self, saved: ziggui.TextEditorSettings) void {
        var restored = saved.validated();
        restored.proportional_font = Self.registeredName(saved.proportional_font) orelse ziggui.FontRegistry.bundled_sans;
        restored.mono_font = Self.registeredName(saved.mono_font) orelse ziggui.FontRegistry.bundled_mono;
        self.settings = restored;
        self.document.indentation = restored.indentation;
    }

    /// Starts an empty, untitled document in the settings' indentation and line ending.
    ///
    /// - `self`: the editor.
    pub fn newDocument(self: *Self) void {
        self.load("") catch |err| {
            self.setStatus("No new document [{t}]", .{err});
            return;
        };
        self.settings.applyTo(&self.document);
        self.saved_revision = self.document.revision;
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
        self.setStatus("Saved {s} (in memory, {s})", .{ self.name(), self.document.line_ending.label() });
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

    /// Takes back the document's last edit.
    ///
    /// - `self`: the editor.
    pub fn undo(self: *Self) void {
        _ = self.document.undo() catch |err| self.setStatus("Not undone [{t}]", .{err});
        ziggui.Focus.shared().set(&self.document);
    }

    /// Puts back the document's last edit undone.
    ///
    /// - `self`: the editor.
    pub fn redo(self: *Self) void {
        _ = self.document.redo() catch |err| self.setStatus("Not redone [{t}]", .{err});
        ziggui.Focus.shared().set(&self.document);
    }

    /// Re-indents the document's lines in the chosen indentation, as one
    /// undo step, from what its lines show now.
    ///
    /// - `self`: the editor.
    pub fn convertIndentation(self: *Self) void {
        if (ziggui.TextIndentation.detect(self.document.text())) |found| self.document.indentation = found;
        self.document.convertIndentation(self.settings.indentation) catch |err| {
            self.setStatus("Not converted [{t}]", .{err});
            return;
        };
        self.setStatus("Indentation converted", .{});
    }

    /// Puts the editor back on the theme's colors: text, ground and style.
    ///
    /// - `self`: the editor.
    pub fn themeColors(self: *Self) void {
        self.settings.foreground = null;
        self.settings.background = null;
        self.settings.colors = .{};
    }

    /// Dresses the editor in a dark style of its own: Noto Serif, light text
    /// on a dark ground, a gutter, a current-line band, a white caret and
    /// colored matches, with the colors bar open and `total` found (the
    /// `--editor-style` demo).
    ///
    /// - `self`: the editor.
    pub fn showStyle(self: *Self) void {
        self.settings.proportional_font = Self.registeredName("Noto Serif") orelse ziggui.FontRegistry.bundled_sans;
        self.settings.proportional_size = 15;
        self.settings.foreground = ziggui.Color.fromRgb8(0xE5, 0xE5, 0xEA);
        self.settings.background = ziggui.Color.fromRgb8(0x1C, 0x1C, 0x1E);
        self.settings.colors = .{
            .caret = ziggui.Color.fromRgb8(0xFF, 0xD6, 0x0A),
            .selection = ziggui.Color.fromRgb8(0x3A, 0x3A, 0x3C),
            .gutter_background = ziggui.Color.fromRgb8(0x2C, 0x2C, 0x2E),
            .gutter_text = ziggui.Color.fromRgb8(0x8E, 0x8E, 0x93),
            .current_line = ziggui.Color.fromRgb8(0x26, 0x26, 0x28),
            .find_match = ziggui.Color.fromRgb8(0x5E, 0x4B, 0x1A),
            .find_current = ziggui.Color.fromRgb8(0xFF, 0x9F, 0x0A),
        };
        self.show_colors.set(true);
        self.color_target.set(@backingInt(ColorTarget.caret));
        self.showMatch("total");
    }

    /// Shows or hides the color pickers.
    ///
    /// - `self`: the editor.
    pub fn toggleColors(self: *Self) void {
        self.show_colors.set(!self.show_colors.get());
    }

    /// Shows the find bar searching for `needle`, its first match after the
    /// caret selected (the `--find` demo).
    ///
    /// - `self`: the editor.
    /// - `needle`: the text to find.
    pub fn showMatch(self: *Self, needle: []const u8) void {
        self.attachFind();
        self.show_find.set(true);
        self.find.query.setText(needle) catch |err| {
            log.warn("the find field was not filled [{t}]", .{err});
            return;
        };
        self.find.found.followed_query = self.find.query.revision;
        self.find.findNext();
    }

    /// Shows the find bar with its replace row, `needle`'s first match
    /// selected and `replacement` typed (the `--replace` demo).
    ///
    /// - `self`: the editor.
    /// - `needle`: the text to find.
    /// - `replacement`: the text to replace it with.
    pub fn showReplace(self: *Self, needle: []const u8, replacement: []const u8) void {
        self.find.shows_replace = true;
        self.find.replacement.setText(replacement) catch |err| log.warn("the replace field was not filled [{t}]", .{err});
        self.showMatch(needle);
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

    /// Points the find at the document and the bar's flag, as a frame's
    /// `findNavigator` does, for a key or a demo before the next frame.
    ///
    /// - `self`: the editor, in its final place (the find keeps its addresses).
    fn attachFind(self: *Self) void {
        self.find.document = &self.document;
        self.find.is_presented = self.show_find.binding();
    }

    /// The registry's own copy of a family's name.
    ///
    /// - `wanted`: the name looked for.
    /// - Returns: the registry's name, or null when no family has it.
    fn registeredName(wanted: []const u8) ?[]const u8 {
        const registry = ziggui.FontRegistry.shared();
        return registry.familyName(registry.familyIndex(wanted) orelse return null);
    }

    /// Replaces the document with `text`, caret at the top, scrolled to the
    /// top, unmodified, with no undo history; its line ending and
    /// indentation are what the text shows (`loadDocument`).
    ///
    /// - `self`: the editor.
    /// - `text`: the new text.
    /// - Returns: nothing; propagates allocation failure.
    fn load(self: *Self, text: []const u8) !void {
        try self.document.loadDocument(text);
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

    /// Opens the sample the dialog's menu names, under the path typed (its
    /// own name when none is), its line ending and indentation found as it
    /// loads.
    ///
    /// - `self`: the editor.
    fn open(self: *Self) void {
        const chosen = samples[@intCast(std.math.clamp(self.sample.get(), 0, samples.len - 1))];
        const typed = self.path_field.text();
        self.setPath(if (typed.len > 0) typed else chosen.name);
        self.show_dialog.set(false);
        self.load(chosen.text) catch |err| {
            self.setStatus("Could not open {s} [{t}]", .{ self.name(), err });
            return;
        };
        ziggui.Focus.shared().set(&self.document);
        const indentation = self.document.indentation;
        self.setStatus("Opened {s}: {d} bytes, {s}, {s} {d}", .{
            self.name(),
            chosen.text.len,
            self.document.line_ending.label(),
            if (indentation.style == .tabs) "tabs of" else "spaces,",
            indentation.columns(),
        });
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
        self.setStatus("Saved {s} (in memory, {s})", .{ self.name(), self.document.line_ending.label() });
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

    /// The toolbar: the document's name, a dot while modified, and the file buttons.
    ///
    /// - `self`: the editor.
    /// - Returns: the toolbar.
    fn toolbar(self: *Self) ziggui.View {
        const title = ziggui.BuildScope.shared().allocator().print("{s}{s}", .{ self.name(), if (self.isDirty()) " •" else "" }) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Text(title).font(.headline).truncated(),
            ziggui.Spacer(),
            ziggui.ButtonRoled("New", .plain, ziggui.Callback.init(Self, self, Self.newDocument)),
            ziggui.ButtonRoled("Open", .plain, ziggui.Callback.init(Self, self, Self.openDialog)),
            ziggui.ButtonRoled("Save As", .plain, ziggui.Callback.init(Self, self, Self.saveAsDialog)),
            ziggui.Button("Save", ziggui.Callback.init(Self, self, Self.save)),
        }).spacing(12)
            .paddingInsets(.{ .top = 9, .leading = 14, .bottom = 9, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The format bar: each face's family (the registered ones), the size
    /// of the face in use, undo and redo, and the colors' toggle.
    ///
    /// - `self`: the editor.
    /// - Returns: the bar.
    fn formatBar(self: *Self) ziggui.View {
        const scope = ziggui.BuildScope.shared();
        const families = ziggui.FontRegistry.shared().namesAlloc(scope.allocator()) catch @panic("oom");
        const tokens = scope.tokens();
        return ziggui.HStack(.{
            ziggui.Text("Font").font(.footnote).foregroundStyle(tokens.secondary_label),
            ziggui.Picker(FontBinding.of(self, false), families).pickerStyle(.menu).help("The proportional face"),
            ziggui.Text("Mono").font(.footnote).foregroundStyle(tokens.secondary_label),
            ziggui.Picker(FontBinding.of(self, true), families).pickerStyle(.menu).help("The monospaced face"),
            ziggui.Stepper(scope.allocator().print("Size {d}", .{SizeBinding.get(self)}) catch @panic("oom"), SizeBinding.of(self), @intFromFloat(ziggui.TextEditorSettings.min_size), @intFromFloat(ziggui.TextEditorSettings.max_size), 1),
            ziggui.Spacer(),
            ziggui.ButtonRoled("Undo", .plain, ziggui.Callback.init(Self, self, Self.undo)).disabled(!self.document.canUndo()),
            ziggui.ButtonRoled("Redo", .plain, ziggui.Callback.init(Self, self, Self.redo)).disabled(!self.document.canRedo()),
            ziggui.ButtonRoled("Colors", if (self.show_colors.get()) .prominent else .plain, ziggui.Callback.init(Self, self, Self.toggleColors)),
        }).spacing(8)
            .paddingInsets(.{ .top = 0, .leading = 14, .bottom = 6, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The layout bar: the monospaced, line-number and wrap checkboxes, the
    /// indentation and its conversion, and the line ending.
    ///
    /// - `self`: the editor.
    /// - Returns: the bar.
    fn layoutBar(self: *Self) ziggui.View {
        return ziggui.HStack(.{
            ziggui.Toggle("Monospaced", SettingBinding.of(self, "mono")),
            ziggui.Toggle("Line numbers", SettingBinding.of(self, "line_numbers")),
            ziggui.Toggle("Wrap", SettingBinding.of(self, "soft_wrap")),
            ziggui.Spacer(),
            ziggui.Picker(IndentationBinding.of(self), &indentation_options).pickerStyle(.menu).help("What Tab inserts"),
            ziggui.ButtonRoled("Convert", .plain, ziggui.Callback.init(Self, self, Self.convertIndentation)).help("Re-indent every line this way"),
            ziggui.Picker(LineEndingBinding.of(self), &line_ending_options).pickerStyle(.segmented).help("How lines end on disk"),
        }).spacing(8)
            .toggleStyle(.checkbox)
            .paddingInsets(.{ .top = 0, .leading = 14, .bottom = 8, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The colors bar: a menu of what to color (the text, the ground and
    /// each of the `TextEditorColors`'s colors), a `ColorPicker` for it, and
    /// a return to the theme's colors.
    ///
    /// - `self`: the editor.
    /// - Returns: the bar.
    fn colorBar(self: *Self) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        return ziggui.HStack(.{
            ziggui.Text("Color").font(.footnote).foregroundStyle(tokens.secondary_label),
            ziggui.Picker(self.color_target.binding(), &ColorTarget.labels).pickerStyle(.menu).help("What the swatches color"),
            ziggui.ColorPicker("", ColorBinding.of(self)),
            ziggui.Spacer(),
            ziggui.ButtonRoled("Theme Colors", .plain, ziggui.Callback.init(Self, self, Self.themeColors)),
        }).spacing(12)
            .paddingInsets(.{ .top = 0, .leading = 14, .bottom = 8, .trailing = 14 })
            .frameMaxWidth();
    }

    /// The status bar: the caret's line and column, the document's
    /// characters and lines, its indentation and line ending, and the
    /// status message, over the code names the section shows.
    ///
    /// - `self`: the editor.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the status bar.
    fn statusBar(self: *Self, theme: ziggui.Theme) ziggui.View {
        const text = self.document.text();
        const caret = self.document.lineColumn();
        const characters = std.unicode.utf8CountCodepoints(text) catch text.len;
        const lines = std.mem.count(u8, text, "\n") + 1;
        const indentation = self.document.indentation;
        const counts = ziggui.BuildScope.shared().allocator().print("Ln {d}, Col {d}    {d} chars    {d} lines    {s}: {d}    {s}    UTF-8", .{
            caret.line,
            caret.column,
            characters,
            lines,
            if (indentation.style == .tabs) "Tab Size" else "Spaces",
            indentation.columns(),
            self.document.line_ending.label(),
        }) catch @panic("oom");
        return ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Text(counts).font(.footnote).foregroundStyle(theme.colors.secondary_label),
                ziggui.Spacer(),
                ziggui.Text(self.status()).font(.footnote).foregroundStyle(theme.colors.tertiary_label),
            }).spacing(14).frameMaxWidth(),
            gallery.CardName.shared().view(if (self.show_find.get()) find_names else editor_names, theme.colors.tertiary_label),
        }).spacing(4)
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
            ziggui.Text("File path:").font(.subheadline).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
            ziggui.TextField("/path/to/file.txt", &self.path_field)
                .frameMaxWidth()
                .onSubmit(confirm),
            if (self.dialog_save) ziggui.Empty() else ziggui.HStack(.{
                ziggui.Text("Sample:").font(.subheadline).foregroundStyle(theme.colors.secondary_label),
                ziggui.Picker(self.sample.binding(), &sample_options).pickerStyle(.menu),
                ziggui.Spacer(),
            }).spacing(8).frameMaxWidth(),
            ziggui.HStack(.{
                ziggui.Spacer(),
                ziggui.ButtonRoled("Cancel", .plain, ziggui.Callback.init(Self, self, Self.cancelDialog)),
                ziggui.Button(if (self.dialog_save) "Save" else "Open", confirm),
            }).frameMaxWidth(),
        }).spacing(14).padding(20).frameWidth(460);
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
    try std.testing.expectEqual(@as(u8, 4), editor.document.indentation.width);
}

test "⌘F opens the find from the section, ⌘G finds on, and Esc closes it back to the document" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();
    defer ziggui.Focus.shared().clear();

    try std.testing.expect(!editor.keyDown('f', 0));
    try std.testing.expect(editor.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(editor.show_find.get());
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &editor.find.query), ziggui.Focus.shared().focused());
    try editor.find.query.setText("greeting");
    editor.find.findNext();
    const first = std.mem.find(u8, sample_document, "greeting").?;
    try std.testing.expectEqual(@as(?usize, first), editor.document.selection_anchor);
    try std.testing.expect(editor.keyDown('g', ziggui.SdlKey.left_gui_mask));
    try std.testing.expectEqual(@as(?ziggui.FindCount, .{ .current = 1, .total = 2 }), editor.find.count());
    try std.testing.expect(editor.keyDown(ziggui.SdlKey.escape, 0));
    try std.testing.expect(!editor.show_find.get());
    try std.testing.expectEqual(@as(?*ziggui.TextFieldState, &editor.document), ziggui.Focus.shared().focused());
}

test "replace all is one undo step, and undoing it reads unmodified" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    editor.showReplace("greeting", "salutation");
    try std.testing.expectEqual(@as(usize, 2), editor.find.replaceAll());
    try std.testing.expect(std.mem.find(u8, editor.document.text(), "salutation") != null);
    try std.testing.expect(editor.isDirty());
    editor.undo();
    try std.testing.expectEqualStrings(sample_document, editor.document.text());
    try std.testing.expect(!editor.isDirty());
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

    editor.settings.line_ending = .crlf;
    editor.newDocument();
    try std.testing.expectEqualStrings("", editor.document.text());
    try std.testing.expectEqualStrings("Untitled", editor.name());
    try std.testing.expectEqual(ziggui.LineEnding.crlf, editor.document.line_ending);
    try std.testing.expect(!editor.isDirty());
}

test "the size shortcuts take ⌘ or Ctrl and stay in range" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    for (0..100) |_| _ = editor.keyDown('=', ziggui.SdlKey.left_ctrl_mask);
    try std.testing.expectEqual(ziggui.TextEditorSettings.max_size, editor.settings.face().size);
    _ = editor.keyDown('0', ziggui.SdlKey.left_ctrl_mask);
    try std.testing.expectEqual(default_size, editor.settings.face().size);
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
    // Dismissed, they work again.
    editor.cancelDialog();
    try std.testing.expect(editor.keyDown('f', ziggui.SdlKey.left_gui_mask));
    try std.testing.expect(editor.show_find.get());
}

test "the bindings change the settings and the document" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    IndentationBinding.of(&editor).set(3);
    try std.testing.expectEqual(ziggui.IndentationStyle.tabs, editor.document.indentation.style);
    LineEndingBinding.of(&editor).set(1);
    try std.testing.expectEqual(ziggui.LineEnding.crlf, editor.document.line_ending);
    try std.testing.expect(editor.isDirty());
    FontBinding.of(&editor, true).set(0);
    try std.testing.expectEqualStrings(ziggui.FontRegistry.bundled_sans, editor.settings.mono_font);
    ColorBinding.of(&editor).set(ziggui.Color.white);
    try std.testing.expectEqual(@as(?ziggui.Color, ziggui.Color.white), editor.settings.foreground);
    editor.color_target.set(@backingInt(ColorTarget.currentLine));
    ColorBinding.of(&editor).set(ziggui.Color.black);
    try std.testing.expectEqual(@as(?ziggui.Color, ziggui.Color.black), editor.settings.colors.current_line);
    editor.themeColors();
    try std.testing.expect(editor.settings.foreground == null and editor.settings.colors.current_line == null);
    // Saved settings come back with their families mapped to the registry's.
    editor.restoreSettings(.{ .proportional_font = "Gone", .mono = true, .indentation = .{ .width = 2 } });
    try std.testing.expectEqualStrings(ziggui.FontRegistry.bundled_sans, editor.settings.proportional_font);
    try std.testing.expectEqual(@as(u8, 2), editor.document.indentation.width);
}

test "Open's legacy sample loads with CRLF and tabs found, and saves as CRLF" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    editor.openDialog();
    editor.sample.set(1);
    try editor.path_field.setText("");
    editor.confirmDialog();
    try std.testing.expectEqualStrings("legacy.c", editor.name());
    try std.testing.expectEqual(ziggui.LineEnding.crlf, editor.document.line_ending);
    try std.testing.expectEqual(ziggui.IndentationStyle.tabs, editor.document.indentation.style);
    try std.testing.expect(std.mem.findScalar(u8, editor.document.text(), '\r') == null);
    try std.testing.expect(!editor.isDirty());
    const saved = try editor.document.encodedAlloc(allocator);
    defer allocator.free(saved);
    try std.testing.expectEqualStrings(legacy_document, saved);
}

test "the style demo draws its colors, font and find" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();

    editor.showStyle();
    try std.testing.expect(editor.show_find.get() and editor.show_colors.get());
    try std.testing.expect(editor.settings.colors.current_line != null);
    const theme = ziggui.ThemeFamily.all[0].forScheme(.light);
    window.begin(theme);
    const root = editor.body(theme);
    window.end();
    var framebuffer = try window.render(root, gallery.test_width, gallery.test_height);
    defer framebuffer.deinit();
}

test "the editor draws with the find bar, its replace row, the colors and the dialog" {
    const allocator = std.testing.allocator;

    var editor = try Editor.init(allocator);
    defer editor.deinit();
    const window = try ziggui.TestWindow.create(allocator);
    defer window.destroy();

    editor.showReplace("greeting", "salutation");
    editor.toggleColors();
    editor.openDialog();
    const theme = ziggui.ThemeFamily.all[0].forScheme(.dark);
    window.begin(theme);
    const root = editor.body(theme);
    window.end();
    var framebuffer = try window.render(root, gallery.test_width, gallery.test_height);
    defer framebuffer.deinit();
    try std.testing.expectEqual(@as(usize, 1), window.overlays.items.len);
}
