//! A find bar: a search field, where the find stands, and Previous, Next
//! and Done, as an editor or a table shows under ⌘F; optionally match-case
//! and whole-word toggles and a replace row.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_find_bar);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The search and replace fields' width when the bar has room for it.
const field_width: f32 = 300;

/// The least the fields shrink to in a bar too narrow for `field_width`.
const min_field_width: f32 = 120;

/// A toggle of the bar's search options, made in the build arena.
const FindOptionToggle = struct {
    const Self = @This();

    /// The option flipped.
    flag: *bool,

    /// Flips the option.
    ///
    /// - `self`: the toggle.
    fn flip(self: *Self) void {
        self.flag.* = !self.flag.*;
    }

    /// A toggle button: its label in a plain button while off, a prominent one while on.
    ///
    /// - `label`: the button's label ("Aa").
    /// - `help`: its hover hint.
    /// - `flag`: the option it flips.
    /// - Returns: the button.
    fn button(label: []const u8, help: []const u8, flag: *bool) mod.View {
        const toggle = mod.BuildScope.shared().allocator().create(Self) catch @panic("oom");
        toggle.* = .{ .flag = flag };
        const role: mod.ButtonRole = if (flag.*) .prominent else .plain;
        return mod.ButtonRoled(label, role, mod.Callback.init(Self, toggle, Self.flip))
            .help(help)
            .accessibilityAddTraits(.{ .is_button = true, .is_selected = flag.* });
    }
};

/// A find bar: a `SearchField` 300pt wide (narrower, down to 120pt, when the
/// bar is too narrow for it and the buttons: a find over a narrow pane), the
/// count ("3 of 40"), then Previous, Next and Done at the trailing edge, on
/// the bar ground. Pass the app's keys through `actions.handleKey(key, field)`
/// while it shows.
///
/// - `placeholder`: the field's hint while it is empty.
/// - `field`: the field's text; app-owned.
/// - `count`: where the find stands, or null before one has run.
/// - `actions`: what Enter, the buttons and the keys do; with
///   `search_options`, Aa and ab| toggles follow the field, and with
///   `replace`, a second row holds the replacement field (Enter replaces),
///   Replace and Replace All.
/// - Returns: the bar, as wide as it is given; narrower than its buttons
///   need, it keeps its leading edge and cuts what does not fit.
pub fn FindBar(placeholder: []const u8, field: *mod.TextFieldState, count: ?mod.FindCount, actions: mod.FindActions) mod.View {
    const scope = mod.BuildScope.shared();
    const tokens = scope.tokens();
    const status: []const u8 = if (count) |found| found.textAlloc(scope.allocator()) catch @panic("oom") else "";
    const search = mod.SearchField(placeholder, field, actions.on_submit, null).frameMaxWidth().frameCap(field_width).frameMinWidth(min_field_width);
    const words = mod.Text(status).font(.footnote).foregroundStyle(tokens.secondary_label);
    const find_row = if (actions.search_options) |options| mod.StackBuilder.make(.horizontal, 8, .center, .{
        search,
        mod.StackBuilder.make(.horizontal, 2, .center, .{
            FindOptionToggle.button("Aa", "Match Case", &options.case_sensitive),
            FindOptionToggle.button("ab|", "Whole Words", &options.whole_word),
        }),
        words,
        mod.Spacer(),
        mod.ButtonRoled("Previous", .normal, actions.on_previous),
        mod.ButtonRoled("Next", .normal, actions.on_next),
        mod.ButtonRoled("Done", .normal, actions.on_done),
    }) else mod.StackBuilder.make(.horizontal, 8, .center, .{
        search,
        words,
        mod.Spacer(),
        mod.ButtonRoled("Previous", .normal, actions.on_previous),
        mod.ButtonRoled("Next", .normal, actions.on_next),
        mod.ButtonRoled("Done", .normal, actions.on_done),
    });
    const rows: mod.View = if (actions.replace) |replace| mod.StackBuilder.make(.vertical, 6, .leading, .{
        find_row,
        mod.StackBuilder.make(.horizontal, 8, .center, .{
            mod.FieldChrome(mod.TextField("Replace", replace.field)
                .textFieldStyle(.plain)
                .onSubmit(replace.on_replace)
                .frameMaxWidth()
                .paddingInsets(.{ .top = 2, .leading = 8, .bottom = 2, .trailing = 8 })).frameMaxWidth().frameCap(field_width).frameMinWidth(min_field_width),
            mod.Spacer(),
            mod.ButtonRoled("Replace", .normal, replace.on_replace),
            mod.ButtonRoled("Replace All", .normal, replace.on_replace_all),
        }),
    }) else find_row;
    // Too narrow for even the shrunk fields, it keeps its leading edge and cuts the trailing buttons (their keys still work).
    return rows.paddingInsets(.{ .top = 6, .leading = 10, .bottom = 6, .trailing = 10 }).frameMaxWidth().frameAlign(.leading).clipped().background(tokens.bar_background);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a find bar shows the count and its Done button closes it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear();
    const Probe = struct {
        const Self = @This();

        /// How many times the bar was closed.
        done: usize = 0,

        /// Ignores a find.
        ///
        /// - `self`: the probe.
        fn ignore(self: *Self) void {
            _ = self;
        }

        /// Counts a close.
        ///
        /// - `self`: the probe.
        fn close(self: *Self) void {
            self.done += 1;
        }
    };
    var probe: Probe = .{};
    const ignore = mod.Callback.init(Probe, &probe, Probe.ignore);
    const actions = mod.FindActions{ .on_submit = ignore, .on_next = ignore, .on_previous = ignore, .on_done = mod.Callback.init(Probe, &probe, Probe.close) };

    window.begin(renderer.MacosTheme.light);
    const bar = FindBar("Find", &field, .{ .current = 2, .total = 40 }, actions);
    window.end();
    var frame = try window.render(bar, 800, 40);
    defer frame.deinit();
    // Done is the trailing button.
    var x: f32 = 796;
    while (x > 600 and probe.done == 0) : (x -= 2) _ = window.tap(.{ .x = x, .y = 20 });
    try std.testing.expectEqual(@as(usize, 1), probe.done);
}
