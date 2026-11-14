//! A badge: a short label on a soft ground in its tone's strong color.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_badge);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a `Badge` says about its subject: each tone has a soft ground and a
/// strong text color from the published `BuildTokens`.
pub const BadgeTone = enum {
    const Self = @This();

    /// Nothing in particular: a count, a kind, a version.
    neutral,
    /// It worked: connected, passed, saved.
    success,
    /// It failed: an error, a refusal.
    danger,
    /// It needs a look: a mismatch, a deprecation.
    warning,
    /// A notice: an era, a transport.
    info,
    /// The app's own emphasis: the active one, a new one.
    accent,

    /// The tone's soft ground.
    ///
    /// - `self`: the tone.
    /// - `tokens`: the published tokens.
    /// - Returns: the ground color.
    pub fn ground(self: *const Self, tokens: mod.BuildTokens) renderer.Color {
        return switch (self.*) {
            .neutral => tokens.neutral_soft,
            .success => tokens.success_soft,
            .danger => tokens.danger_soft,
            .warning => tokens.warning_soft,
            .info => tokens.info_soft,
            .accent => tokens.accent_soft,
        };
    }

    /// The tone's strong text color.
    ///
    /// - `self`: the tone.
    /// - `tokens`: the published tokens.
    /// - Returns: the text color.
    pub fn text(self: *const Self, tokens: mod.BuildTokens) renderer.Color {
        return switch (self.*) {
            .neutral => tokens.secondary_label,
            .success => tokens.added,
            .danger => tokens.removed,
            .warning => tokens.warning,
            .info => tokens.info,
            .accent => tokens.accent_text,
        };
    }
};

/// A short label on its tone's soft ground, in the tone's strong color:
/// 11pt medium, 6pt by 2pt of padding, corner radius 4. As wide as its text,
/// never stretched. Chain `.mono()` for codes (`-32601`, `HTTP 404`).
///
/// - `text`: the label.
/// - `tone`: what the badge says.
/// - Returns: the badge.
pub fn Badge(text: []const u8, tone: BadgeTone) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return mod.Text(text)
        .size(11)
        .weight(.medium)
        .foreground(tone.text(tokens))
        .paddingInsets(.{ .top = 2, .leading = 6, .bottom = 2, .trailing = 6 })
        .background(tone.ground(tokens))
        .cornerRadius(4);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a badge takes its tone's ground and text, and hugs its text" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const danger = Badge("failed", .danger);
    const code = Badge("-32601", .neutral).mono();
    const row = mod.HStack(.{ Badge("ok", .success), mod.Spacer() });
    canvas.end();
    try std.testing.expectEqual(tokens.danger_soft, danger.modifiers.background.?.color);
    try std.testing.expectEqual(tokens.removed, danger.modifiers.foreground.?);
    try std.testing.expect(code.modifiers.mono);

    var frame = try canvas.render(row, 200, 20);
    defer frame.deinit();
    // The ground is tinted green at the leading edge and absent far right.
    const inside = frame.at(2, 10);
    try std.testing.expect(inside.g > inside.r and inside.g > inside.b);
    try std.testing.expect(frame.at(190, 10).r > 0.99);
}
