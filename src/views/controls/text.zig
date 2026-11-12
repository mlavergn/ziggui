//! Text views: one line, a wrapped paragraph, and styled rich text.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_text);
const mod = @import("module.zig");

/// One line of text.
///
/// - `string`: the text.
/// - Returns: the view.
pub fn Text(string: []const u8) mod.View {
    return .{ .kind = .{ .text = .{ .string = string } } };
}

/// Multi-line text: word-wraps to the width it is proposed, growing taller as it
/// wraps. Use this (rather than `Text`) for paragraphs and chat bubbles.
///
/// - `string`: the text.
/// - Returns: the view.
pub fn WrappedText(string: []const u8) mod.View {
    return .{ .kind = .{ .wrappedText = .{ .string = string } } };
}

/// A wrapped paragraph of styled spans (bold/italic/mono/link/background...).
///
/// - `spans`: the spans, copied into the build arena.
/// - Returns: the view.
pub fn RichText(spans: []const mod.Span) mod.View {
    return RichTextSpaced(spans, 1.25);
}

/// Preformatted spans (code): leading spaces survive and lines do not wrap.
///
/// - `spans`: the spans, copied into the build arena.
/// - `line_multiple`: line height as a multiple of the font size.
/// - Returns: the view.
pub fn RichTextPreformatted(spans: []const mod.Span, line_multiple: f32) mod.View {
    var view = RichTextSpaced(spans, line_multiple);
    view.kind.richText.preformatted = true;
    return view;
}

/// A wrapped paragraph of styled spans at a given line height.
///
/// - `spans`: the spans, copied into the build arena.
/// - `line_multiple`: line height as a multiple of the font size.
/// - Returns: the view.
pub fn RichTextSpaced(spans: []const mod.Span, line_multiple: f32) mod.View {
    // Copied into the build arena: the caller's slice is usually a stack array.
    const owned = mod.BuildScope.shared().allocator().dupe(mod.Span, spans) catch @panic("oom");
    return .{ .kind = .{ .richText = .{ .spans = owned, .line_multiple = line_multiple } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
