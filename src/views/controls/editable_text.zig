//! A label renamed in place, as Finder renames a file: a click while it is
//! selected, slower than a double click, turns it into a field.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_editable_text);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The space inside the editing field around its text, in points.
const field_inset: f32 = 2;

/// The editing field's corner radius, in points.
const field_radius: f32 = 4;

/// The editing field's focus ring width, in points.
const field_ring: f32 = 1.5;

/// A label that edits in place (`EditableTextState` has the rules): its text,
/// or, while editing, a chromeless field in its place with all its text
/// selected, on the raised ground with a focus ring, so it reads on a
/// selected row's accent. A click on it calls `on_tap` (a list row's select,
/// so a click on the name selects the row as a click beside it does); a
/// further click once it is selected starts the edit
/// `EditableTextState.edit_delay_ms` later. Enter or a press elsewhere
/// commits and calls `on_commit` when the text changed; the app's key handler
/// gives Esc to `state.keyDown` to cancel.
///
/// - `state`: its text and edit; app-owned, its address kept while it edits.
/// - `selected`: whether it draws selected now (its row's selection).
/// - `on_tap`: what a click on it also calls, or null.
/// - `on_commit`: what a commit of a changed text calls; it reads `state.text()`.
/// - Returns: the label, or its field while editing.
pub fn EditableText(state: *mod.EditableTextState, selected: bool, on_tap: ?mod.Callback, on_commit: mod.Callback) mod.View {
    state.update(selected, on_tap, on_commit, mod.FrameClock.shared().time()) catch @panic("oom");
    if (state.editing) {
        const tokens = mod.BuildScope.shared().tokens();
        return mod.TextField("", &state.field)
            .chromeless(field_inset)
            .foreground(tokens.label)
            .background(tokens.raised)
            .cornerRadius(field_radius)
            .border(tokens.focus_ring, field_ring)
            .onSubmit(mod.Callback.init(mod.EditableTextState, state, mod.EditableTextState.commit));
    }
    return mod.Text(state.text())
        .truncated()
        .onTap(mod.Callback.init(mod.EditableTextState, state, mod.EditableTextState.press))
        .onHover(.{ .context = state, .function = mod.EditableTextState.hoverChanged });
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an editable text is a tappable label, then a field while editing" {
    const Probe = struct {
        const Self = @This();

        /// A commit that does nothing.
        fn ignore() void {}
    };
    var state = try mod.EditableTextState.init(std.testing.allocator, "notes.txt");
    defer state.deinit();
    defer mod.Focus.shared().clear();
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    window.begin(renderer.MacosTheme.light);
    const label = EditableText(&state, true, null, mod.Callback.action(Probe.ignore));
    window.end();
    try std.testing.expect(label.kind == .text);
    var frame = try window.render(label, 200, 30);
    frame.deinit();
    try std.testing.expectEqual(@as(usize, 1), window.hits.items.len);

    try state.beginEditing();
    window.begin(renderer.MacosTheme.light);
    const field = EditableText(&state, true, null, mod.Callback.action(Probe.ignore));
    window.end();
    try std.testing.expect(field.kind == .textField);
}
