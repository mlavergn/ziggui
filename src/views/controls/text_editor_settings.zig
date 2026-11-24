//! An editor's settings as one plain value an app keeps and saves: its
//! two faces and sizes, indentation, line ending, gutter, wrapping and colors.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_editor_settings);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A `TextEditor`'s settings. ziggui stores nothing: the app keeps this
/// value (ZON writes and reads it as it is) and applies it each frame with
/// `apply`, and to a document with `applyTo`.
pub const TextEditorSettings = struct {
    const Self = @This();

    /// The proportional face's family (`.font(.custom(...))`).
    proportional_font: []const u8 = renderer.FontRegistry.bundled_sans,

    /// The proportional face's size, in points.
    proportional_size: f32 = 13,

    /// The monospaced face's family.
    mono_font: []const u8 = renderer.FontRegistry.bundled_mono,

    /// The monospaced face's size, in points.
    mono_size: f32 = 13,

    /// Whether the editor draws in the monospaced face.
    mono: bool = false,

    /// What Tab inserts and where tabs stop.
    indentation: mod.TextIndentation = .{},

    /// The line ending a new document saves with.
    line_ending: mod.LineEnding = .lf,

    /// Whether the line-number gutter shows.
    line_numbers: bool = true,

    /// Whether long lines wrap to the editor's width.
    soft_wrap: bool = false,

    /// The text's color, or null for the theme's.
    foreground: ?renderer.Color = null,

    /// The editor's ground, or null for the theme's.
    background: ?renderer.Color = null,

    /// The caret's, selection's, gutter's and matches' colors.
    colors: mod.TextEditorColors = .{},

    /// The smallest size the editor takes.
    pub const min_size: f32 = 6;

    /// The largest size the editor takes.
    pub const max_size: f32 = 72;

    /// The face in use: the monospaced one while `mono`, else the proportional one.
    ///
    /// - `self`: the settings.
    /// - Returns: the family's name and its size, the size within `min_size` and `max_size`.
    pub fn face(self: *const Self) mod.CustomFont {
        const size = if (self.mono) self.mono_size else self.proportional_size;
        return .{
            .name = if (self.mono) self.mono_font else self.proportional_font,
            .size = Self.validSize(size),
        };
    }

    /// Changes the size of the face in use, within `min_size` and `max_size`.
    ///
    /// - `self`: the settings.
    /// - `delta`: the points to add; negative shrinks it.
    pub fn resize(self: *Self, delta: f32) void {
        const size = if (self.mono) &self.mono_size else &self.proportional_size;
        size.* = std.math.clamp(self.face().size + delta, min_size, max_size);
    }

    /// A copy safe to draw with whatever a saved file held: a size that is
    /// not finite back to its default and every size within range, the
    /// indentation's width within range, and a color with a channel that is
    /// not finite dropped (the theme's).
    ///
    /// - `self`: the settings.
    /// - Returns: the copy.
    pub fn validated(self: *const Self) Self {
        var copy = self.*;
        copy.proportional_size = Self.validSize(copy.proportional_size);
        copy.mono_size = Self.validSize(copy.mono_size);
        copy.indentation.width = @intCast(copy.indentation.columns());
        copy.foreground = Self.validColor(copy.foreground);
        copy.background = Self.validColor(copy.background);
        inline for (@typeInfo(mod.TextEditorColors).@"struct".field_names) |name| {
            @field(copy.colors, name) = Self.validColor(@field(copy.colors, name));
        }
        return copy;
    }

    /// Applies the settings to a `TextEditor`: its face and size, gutter,
    /// wrapping and colors. Any other view gets the font and colors only.
    ///
    /// - `self`: the settings.
    /// - `editor`: the editor's view.
    /// - Returns: the editor.
    pub fn apply(self: *const Self, editor: mod.View) mod.View {
        var view = editor;
        switch (view.kind) {
            .textEditor => |*data| data.line_numbers = self.line_numbers,
            else => {},
        }
        const chosen = self.face();
        view = view.font(.custom(chosen.name, chosen.size));
        if (self.mono) view = view.monospaced();
        if (self.soft_wrap) view = view.softWrap();
        if (self.foreground) |color| view = view.foregroundStyle(color);
        if (self.background) |color| view = view.background(color);
        if (!std.meta.eql(self.colors, mod.TextEditorColors{})) view = view.textEditorColors(self.colors);
        return view;
    }

    /// A size within range, 13 for one that is not finite.
    ///
    /// - `size`: the size read.
    /// - Returns: the size to draw at.
    fn validSize(size: f32) f32 {
        return if (std.math.isFinite(size)) std.math.clamp(size, min_size, max_size) else 13;
    }

    /// A color whose every channel is finite, else none.
    ///
    /// - `color`: the color read.
    /// - Returns: it, or null.
    fn validColor(color: ?renderer.Color) ?renderer.Color {
        const kept = color orelse return null;
        const finite = std.math.isFinite(kept.r) and std.math.isFinite(kept.g) and std.math.isFinite(kept.b) and std.math.isFinite(kept.a);
        return if (finite) kept else null;
    }

    /// Gives a document the settings' indentation and line ending (a new
    /// document; a loaded one keeps what `TextFieldState.loadDocument` found).
    ///
    /// - `self`: the settings.
    /// - `state`: the document.
    pub fn applyTo(self: *const Self, state: *mod.TextFieldState) void {
        state.indentation = self.indentation;
        state.setLineEnding(self.line_ending);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "editor settings apply their face, gutter and colors, and keep sizes in range" {
    var settings: TextEditorSettings = .{ .mono = true, .mono_size = 15, .line_numbers = false, .soft_wrap = true, .foreground = renderer.Color.white, .colors = .{ .caret = renderer.Color.black } };
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    var scroll: mod.ScrollState = .{};
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const view = settings.apply(mod.TextEditor(&field, &scroll, true));
    window.end();
    try std.testing.expect(!view.kind.textEditor.line_numbers);
    try std.testing.expectEqualStrings(renderer.FontRegistry.bundled_mono, view.modifiers.font_family.?);
    try std.testing.expectEqual(@as(?f32, 15), view.modifiers.size);
    try std.testing.expect(view.modifiers.mono and view.modifiers.soft_wrap);
    try std.testing.expect(view.modifiers.text_editor_colors != null);
    settings.resize(100);
    try std.testing.expectEqual(TextEditorSettings.max_size, settings.mono_size);
    settings.mono = false;
    settings.resize(-100);
    try std.testing.expectEqual(TextEditorSettings.min_size, settings.proportional_size);
    settings.indentation = .{ .style = .tabs, .width = 8 };
    settings.line_ending = .crlf;
    settings.applyTo(&field);
    try std.testing.expectEqual(mod.IndentationStyle.tabs, field.indentation.style);
    try std.testing.expectEqual(mod.LineEnding.crlf, field.line_ending);
}

test "editor settings read from a file are made safe to draw" {
    const read: TextEditorSettings = .{
        .proportional_size = std.math.nan(f32),
        .mono_size = 1000,
        .indentation = .{ .width = 0 },
        .foreground = .{ .r = std.math.inf(f32), .g = 0, .b = 0, .a = 1 },
        .colors = .{ .caret = .{ .r = 0, .g = std.math.nan(f32), .b = 0, .a = 1 }, .selection = renderer.Color.white },
    };
    const safe = read.validated();
    try std.testing.expectEqual(@as(f32, 13), safe.proportional_size);
    try std.testing.expectEqual(TextEditorSettings.max_size, safe.mono_size);
    try std.testing.expectEqual(@as(u8, 1), safe.indentation.width);
    try std.testing.expect(safe.foreground == null and safe.colors.caret == null);
    try std.testing.expectEqual(@as(?renderer.Color, renderer.Color.white), safe.colors.selection);
}
