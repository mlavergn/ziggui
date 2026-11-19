//! A settings form in columns, as SwiftUI's `Form` with `.formStyle(.columns)`
//! draws it on macOS: each row's label right-aligned in one column, its
//! controls in the next, and a divider between sections.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_form);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A form of `sections` (a tuple or slice of `Section`s), a divider between
/// each two, as a macOS settings pane: every `LabeledContent` label inside it
/// shares one column as wide as the widest of them (measured as layout
/// reaches the form), and its toggles are checkboxes unless a
/// `.toggleStyle()` says otherwise.
///
/// - `sections`: the sections.
/// - Returns: the form.
pub fn Form(sections: anytype) mod.View {
    // Flat first, so the sections a `ForEach` makes get dividers too.
    const views = mod.StackBuilder.flattenGroups(mod.StackBuilder.toViews(sections));
    const rows = mod.BuildScope.shared().allocator().alloc(mod.View, if (views.len == 0) 0 else views.len * 2 - 1) catch @panic("oom");
    for (views, 0..) |section, index| {
        if (index > 0) rows[index * 2 - 1] = mod.Divider();
        rows[index * 2] = section;
    }
    var form = mod.StackBuilder.fromSlice(.vertical, 12, .leading, rows).frameMaxWidth();
    form.modifiers.form_columns = true;
    return form;
}

/// A group of a form's rows, the dividers of its `Form` around it.
///
/// - `rows`: the rows (a tuple or slice), most of them `LabeledContent`.
/// - Returns: the section.
pub fn Section(rows: anytype) mod.View {
    return mod.StackBuilder.make(.vertical, 10, .leading, rows).frameMaxWidth();
}

/// A form row: `label` right-aligned in its `Form`'s label column, `content`
/// beside it (a control, or a stack of controls and their help). An empty
/// label leaves the column blank, so the content lines up under the others'.
/// Outside a `Form` the label is as wide as its text.
///
/// - `label`: the row's label, its colon included ("Startup:").
/// - `content`: the row's controls.
/// - Returns: the row.
pub fn LabeledContent(label: []const u8, content: mod.View) mod.View {
    var title = mod.Text(label);
    title.modifiers.form_label = true;
    return mod.HStack(.{ title, content, mod.Spacer() }).spacing(8).alignment(.top).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// Records the frames a form's controls were painted at, for the tests.
const FormProbe = struct {
    const Self = @This();

    /// Whether the option is on.
    on: renderer.State(bool),

    /// A form of two sections: a short label and a long one.
    ///
    /// - `self`: the probe.
    /// - Returns: the form.
    fn form(self: *Self) mod.View {
        return Form(.{
            Section(.{LabeledContent("A:", mod.Toggle("First", self.on.binding()))}),
            Section(.{LabeledContent("A longer label:", mod.Toggle("Second", self.on.binding()))}),
        });
    }
};

/// The labels the `ForEach` test's sections show.
const for_each_labels = [_][]const u8{ "One:", "Two:", "Three:" };

/// Builds the `ForEach` test's sections.
const ForEachProbe = struct {
    const Self = @This();

    /// One section, of one row.
    ///
    /// - `label`: the row's label.
    /// - Returns: the section.
    fn section(label: []const u8) mod.View {
        return Section(.{LabeledContent(label, mod.Text("value"))});
    }
};

test "a form divides the sections a ForEach makes" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const view = Form(.{mod.ForEach(&for_each_labels, ForEachProbe.section)});
    window.end();
    // Three sections, two dividers between them.
    try std.testing.expectEqual(@as(usize, 5), view.kind.stack.children.len);
    try std.testing.expect(view.kind.stack.children[1].kind == .divider);
    try std.testing.expect(view.kind.stack.children[3].kind == .divider);
}

test "a form's label column holds inside a scroll view" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var on = renderer.State(bool).init(std.testing.allocator, false);
    defer on.deinit();
    window.begin(renderer.MacosTheme.light);
    const view = Form(.{
        Section(.{LabeledContent("A longer label:", mod.Toggle("Outside", on.binding()))}),
        mod.ScrollView(Section(.{LabeledContent("A:", mod.Toggle("Inside", on.binding()))})).frameHeight(40),
    });
    window.end();
    var frame = try window.render(view, 400, 160);
    defer frame.deinit();
    // The toggle in the scroll view starts where the one outside it does.
    var starts: [2]f32 = undefined;
    var found: usize = 0;
    for (window.hits.items) |hit| {
        if (hit.action == .toggle and found < 2) {
            starts[found] = hit.rect.x;
            found += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), found);
    try std.testing.expectEqual(starts[0], starts[1]);
}

test "a form's labels share the widest one's column, and its toggles are checkboxes" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var probe: FormProbe = .{ .on = renderer.State(bool).init(std.testing.allocator, false) };
    defer probe.on.deinit();
    window.begin(renderer.MacosTheme.light);
    const view = probe.form();
    window.end();
    var frame = try window.render(view, 400, 120);
    defer frame.deinit();
    // Both toggles start at the same x, past the longer label: the column is shared.
    var starts: [2]f32 = undefined;
    var first_middle: f32 = 0;
    var found: usize = 0;
    for (window.hits.items) |hit| {
        if (hit.action == .toggle and found < 2) {
            if (found == 0) first_middle = hit.rect.midY();
            starts[found] = hit.rect.x;
            found += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), found);
    try std.testing.expectEqual(starts[0], starts[1]);
    try std.testing.expect(starts[0] > 60);
    // A checkbox hugs its label: the toggle's region ends well short of the row.
    for (window.hits.items) |hit| if (hit.action == .toggle) try std.testing.expect(hit.rect.maxX() < 300);
    // A tap on the first checkbox turns it on.
    try std.testing.expect(window.tap(.{ .x = starts[0] + 4, .y = first_middle }));
    try std.testing.expect(probe.on.get());
}
