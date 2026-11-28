//! Cards for view modifiers no component's card shows on its own: text
//! weight and slant, fields and editors drawn plain on a ground of their
//! own, the frame modifiers, rows that react to the pointer, selectable rows
//! of a list built only where it shows, fills behind a view, and the names
//! accessibility reads. Each goes in the section SwiftUI's documentation
//! files it under (`Gallery.panel`).

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_modifiers_demo);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The hover rows' names.
const hover_rows = [_][]const u8{ "Inbox", "Drafts", "Sent", "Archive" };

/// What the log card's lines say: few, so many lines read alike, which is
/// what `.selectionId` tells apart.
const log_lines = [_][]const u8{ "GET /health 200", "GET /health 200", "POST /orders 201", "GET /health 200", "GET /orders/17 404" };

/// The state behind the modifier cards: the plain field and editor, the
/// hover rows, the log's scroll and the frames card's toggles.
pub const ModifiersDemo = struct {
    const Self = @This();

    /// How many lines the log card's list holds.
    const log_count = 1000;
    /// A log line's height.
    const log_row_height: f32 = 22;
    /// Added to a log line's index to make its selection identity, so it
    /// never meets another list's row numbers ("log" in its top bytes).
    const log_selection_base: u64 = 0x6c6f_6700_0000_0000;

    /// The plain field's text.
    plain_field: ziggui.TextFieldState,
    /// The plain editor's text.
    notes: ziggui.TextFieldState,
    /// The plain editor's scroll.
    notes_scroll: ziggui.ScrollState = .{},
    /// Which hover rows were deleted.
    removed: [hover_rows.len]bool = @splat(false),
    /// The hover row last right-clicked, or null.
    right_clicked: ?usize = null,
    /// The log card's scroll.
    log_scroll: ziggui.ScrollState = .{},
    /// The frames card's toggle kept at its ideal width.
    fixed_toggle: ziggui.State(bool),
    /// The frames card's toggle left to share the row.
    shared_toggle: ziggui.State(bool),

    /// Makes the demo's state.
    ///
    /// - `allocator`: what the fields and toggles keep their state with.
    /// - Returns: the demo.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .plain_field = ziggui.TextFieldState.init(allocator),
            .notes = ziggui.TextFieldState.init(allocator),
            .fixed_toggle = ziggui.State(bool).init(allocator, true),
            .shared_toggle = ziggui.State(bool).init(allocator, true),
        };
        return self;
    }

    /// Frees the demo's state.
    ///
    /// - `self`: the demo.
    pub fn deinit(self: *Self) void {
        self.shared_toggle.deinit();
        self.fixed_toggle.deinit();
        self.notes.deinit();
        self.plain_field.deinit();
    }

    /// The Text section's styling card: weights, italic and monospaced.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn textStyleCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Weight, slant and fixed width", "ziggui.Text · .fontWeight · .italic · .monospaced", ziggui.VStack(.{
            ziggui.Text("Regular: the quick brown fox"),
            ziggui.Text("Semibold: the quick brown fox").fontWeight(.semibold),
            ziggui.Text("Bold: the quick brown fox").fontWeight(.bold),
            ziggui.Text("Italic: the quick brown fox").italic(),
            ziggui.Text("Bold italic: the quick brown fox").fontWeight(.bold).italic(),
            ziggui.Text("Monospaced: let width = 640;").monospaced(),
        }).spacing(6).alignment(.leading).frameMaxWidth().frameAlign(.leading));
    }

    /// The Text section's plain fields card: a field and an editor drawn
    /// without the theme's field, on a ground their container draws, the
    /// editor with wider margins, a placeholder, soft wrapping and colors of
    /// its own.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn plainFieldsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        const ground = tokens.accent_soft;
        return gallery.Card.view(
            theme,
            "Plain fields on a ground of their own",
            ".textFieldStyle(.plain) · .textEditorStyle(.plain) · .contentMargins · .placeholder · .softWrap · .textEditorColors",
            ziggui.VStack(.{
                ziggui.HStack(.{
                    ziggui.Icon(.atSign, 14, tokens.accent),
                    ziggui.TextField("Email address", &self.plain_field).textFieldStyle(.plain).frameMaxWidth(),
                }).spacing(8).padding(10).background(ground).cornerRadius(10).frameMaxWidth(),
                ziggui.TextEditor(&self.notes, &self.notes_scroll, false)
                    .textEditorStyle(.plain)
                    .contentMargins(14)
                    .placeholder("Notes: long lines wrap to the width, the caret and selection drawn in the accent.")
                    .softWrap()
                    .textEditorColors(.{ .caret = tokens.accent, .selection = tokens.accent.withAlpha(0.25) })
                    .background(ground).cornerRadius(10).frameMaxWidth().frameHeight(110),
            }).spacing(10),
        );
    }

    /// The Layout section's frames card: a least width, a greatest width
    /// that wraps past it, and a toggle kept at its ideal width beside one
    /// that shares the row.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn framesCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        return gallery.Card.view(theme, "Least, greatest and ideal widths", ".frameMinWidth · .frameCap · .fixedSize", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Text("OK").padding(8).frameMinWidth(140).background(tokens.accent_soft).cornerRadius(6),
                ziggui.Text("never narrower than 140pt").font(.footnote).foregroundStyle(theme.colors.secondary_label),
            }).spacing(12),
            ziggui.HStack(.{
                ziggui.WrappedText("A caption that hugs its words up to 220pt, then wraps onto another line.").padding(8).frameCap(236).background(tokens.accent_soft).cornerRadius(6),
                ziggui.Text("at most 220pt").font(.footnote).foregroundStyle(theme.colors.secondary_label),
            }).spacing(12),
            ziggui.HStack(.{ ziggui.Toggle("Fixed size", self.fixed_toggle.binding()).fixedSize(), ziggui.Spacer() }).frameMaxWidth(),
            ziggui.HStack(.{ ziggui.Toggle("Shares the row", self.shared_toggle.binding()), ziggui.Spacer() }).frameMaxWidth(),
        }).spacing(10).alignment(.leading).frameMaxWidth().frameAlign(.leading));
    }

    /// The Lists section's hover rows card: each row filled while the
    /// pointer is over it, its delete button shown only then, and a
    /// right-click noted.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn hoverRowsCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const tokens = ziggui.BuildScope.shared().tokens();
        var rows: std.ArrayList(ziggui.View) = .empty;
        for (hover_rows, 0..) |name, index| {
            if (self.removed[index]) continue;
            const row = ziggui.HStack(.{
                ziggui.Icon(.folder, 14, tokens.accent),
                ziggui.Text(name),
                ziggui.Spacer(),
                ziggui.IconButton(.trash2, 13, ziggui.Callback.tagged(Self, self, Self.remove, index)).help("Delete").revealOnHover(),
            }).spacing(8).padding(6).hoverFill(tokens.hover).cornerRadius(6).hoverScope()
                .onSecondaryTap(ziggui.Callback.tagged(Self, self, Self.noteRightClick, index));
            rows.append(allocator, row) catch @panic("oom");
        }
        const status = if (self.right_clicked) |index|
            allocator.print("Right-clicked: {s}", .{hover_rows[index]}) catch @panic("oom")
        else
            "Hover a row to show its delete button; right-click one.";
        return gallery.Card.view(theme, "Rows that answer the pointer", ".hoverFill · .hoverScope · .revealOnHover · .onSecondaryTap", ziggui.VStack(.{
            ziggui.VStack(rows.items).spacing(2).frameMaxWidth(),
            ziggui.HStack(.{
                ziggui.Text(status).font(.footnote).foregroundStyle(theme.colors.secondary_label),
                ziggui.Spacer(),
                ziggui.Button("Restore", ziggui.Callback.init(Self, self, Self.restore)),
            }).spacing(8),
        }).spacing(8));
    }

    /// The Lists section's log card: a thousand lines, many alike, in a list
    /// that builds only those in view, each selectable by its own identity.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn logCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "Selectable lines in a virtual list", "ziggui.VirtualList · .textSelection(.enabled) · .selectionId", ziggui.VStack(.{
            ziggui.VirtualList(Self, self, log_count, log_row_height, &self.log_scroll, Self.logRow).frameHeight(132),
            ziggui.Text("Drag across a line to select it: alike lines select apart, scrolled or not.")
                .font(.footnote).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(8));
    }

    /// The Effects section's fills card: a gradient and a flat color behind
    /// text, as a `Fill`.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn fillCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        const tokens = ziggui.BuildScope.shared().tokens();
        const gradient = ziggui.Fill{ .linearGradient = .{ .start_color = tokens.accent, .end_color = theme.colors.accent.withAlpha(0.35), .start = .{ .x = 0, .y = 0 }, .end = .{ .x = 1, .y = 1 } } };
        return gallery.Card.view(theme, "Fills behind a view", ".backgroundFill · ziggui.Fill · ziggui.GradientFill", ziggui.HStack(.{
            ziggui.Text("Gradient").font(.headline).foregroundStyle(tokens.on_accent).padding(16).backgroundFill(gradient).cornerRadius(10),
            ziggui.Text("Color").font(.headline).padding(16).backgroundFill(.{ .color = tokens.accent_soft }).cornerRadius(10),
        }).spacing(12).frameMaxWidth().frameAlign(.leading));
    }

    /// The Controls section's accessibility card: a button tests find by a
    /// stable identifier, and a decorative icon left out of the tree.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn accessibilityCard(self: *const Self, theme: ziggui.Theme) ziggui.View {
        _ = self;
        return gallery.Card.view(theme, "Accessibility names", ".accessibilityIdentifier · .accessibilityHidden · ziggui.A11yNode", ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Icon(.sparkles, 16, theme.colors.accent).accessibilityHidden(true),
                ziggui.Button("Share…", ziggui.Callback.action(Self.share)).accessibilityIdentifier("gallery.share"),
            }).spacing(10),
            ziggui.WrappedText("The button is \"gallery.share\" to UI tests (A11yNode.find) in every language; the sparkles are decoration, hidden from screen readers.")
                .font(.footnote).foregroundStyle(theme.colors.secondary_label),
        }).spacing(8).alignment(.leading).frameMaxWidth().frameAlign(.leading));
    }

    /// A log line: its number and its text, selectable by its index.
    ///
    /// - `self`: the demo.
    /// - `index`: the line.
    /// - Returns: the row.
    fn logRow(self: *const Self, index: usize) ziggui.View {
        _ = self;
        const allocator = ziggui.BuildScope.shared().allocator();
        const number = allocator.print("{d:>4}", .{index + 1}) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Text(number).monospaced().foregroundStyle(ziggui.BuildScope.shared().tokens().secondary_label),
            ziggui.Text(log_lines[index % log_lines.len]).monospaced().textSelection(.enabled).selectionId(log_selection_base + index),
            ziggui.Spacer(),
        }).spacing(10).frameHeight(log_row_height);
    }

    /// Deletes a hover row.
    ///
    /// - `self`: the demo.
    /// - `index`: the row.
    fn remove(self: *Self, index: usize) void {
        self.removed[index] = true;
    }

    /// Notes the hover row right-clicked.
    ///
    /// - `self`: the demo.
    /// - `index`: the row.
    fn noteRightClick(self: *Self, index: usize) void {
        self.right_clicked = index;
    }

    /// Brings every hover row back.
    ///
    /// - `self`: the demo.
    fn restore(self: *Self) void {
        self.removed = @splat(false);
        self.right_clicked = null;
    }

    /// What the Share button does: nothing but log, being a demo.
    fn share() void {
        log.info("share", .{});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the hover rows delete and come back, and a right-click is noted" {
    var demo = ModifiersDemo.init(std.testing.allocator);
    defer demo.deinit();
    demo.remove(1);
    demo.noteRightClick(2);
    try std.testing.expect(demo.removed[1]);
    try std.testing.expectEqual(@as(?usize, 2), demo.right_clicked);
    demo.restore();
    try std.testing.expect(!demo.removed[1]);
    try std.testing.expectEqual(@as(?usize, null), demo.right_clicked);
}
