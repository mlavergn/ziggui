//! Text models: rich-text spans and their paragraph layout, and the editable
//! text state behind text fields and editors, with its UTF-8 line geometry and
//! tab-aware metrics.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_module);

/// One styled run of a `RichText`.
pub const Span = @import("span.zig").Span;
/// A run of a text's bytes, as `HighlightedText` marks them.
pub const TextRange = @import("text_range.zig").TextRange;
/// A laid-out piece of one span on one line.
pub const RichRun = @import("rich_run.zig").RichRun;
/// One laid-out line of a rich paragraph.
pub const RichLine = @import("rich_line.zig").RichLine;
/// A laid-out rich paragraph (`layOut` makes one).
pub const RichLayout = @import("rich_layout.zig").RichLayout;
/// The faces a rich paragraph's spans are measured and drawn in.
pub const RichFaces = @import("rich_faces.zig").RichFaces;
/// A text field's buffer, caret and selection.
pub const TextFieldState = @import("text_field_state.zig").TextFieldState;
/// Text made safe to draw: each invalid UTF-8 byte becomes U+FFFD.
pub const DisplayText = @import("display_text.zig").DisplayText;
/// The last thing an action said, kept for the notice strip.
pub const NoticeText = @import("notice_text.zig").NoticeText;
/// How a highlighted line's plain text, marked ranges and current range are drawn.
pub const HighlightStyle = @import("highlight_spans.zig").HighlightStyle;
/// A line with byte ranges marked, as preformatted spans.
pub const HighlightSpans = @import("highlight_spans.zig").HighlightSpans;
/// Line and column geometry over a UTF-8 buffer.
pub const TextLines = @import("text_lines.zig").TextLines;
/// Tab-aware widths of edited text.
pub const EditorMetrics = @import("editor_metrics.zig").EditorMetrics;
/// A text field's undo and redo steps.
pub const TextHistory = @import("text_history.zig").TextHistory;
/// What a recorded edit was, which decides whether it joins the step before it.
pub const TextEditKind = @import("text_history.zig").TextEditKind;
/// One recorded edit's removed and inserted bytes.
pub const TextEdit = @import("text_history.zig").TextEdit;
/// One undo step's edits.
pub const TextEditGroup = @import("text_history.zig").TextEditGroup;
/// An edit as a field reports it to its history.
pub const TextEditRecord = @import("text_history.zig").TextEditRecord;
/// How an editor indents: tabs or spaces, and the width of a level.
pub const TextIndentation = @import("text_indentation.zig").TextIndentation;
/// What Tab inserts: spaces or a tab character.
pub const IndentationStyle = @import("text_indentation.zig").IndentationStyle;
/// How a document's lines end on disk: LF or CRLF.
pub const LineEnding = @import("line_ending.zig").LineEnding;
/// Plain-text search over a buffer.
pub const TextSearch = @import("text_search.zig").TextSearch;
/// How a text search matches: case, whole words.
pub const TextSearchOptions = @import("text_search.zig").TextSearchOptions;

/// A type-erased tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// The keyboard focus (from the views module), which a freed field leaves.
pub const Focus = @import("../module.zig").Focus;
/// The text-field context menu (from the views module), which a freed field closes.
pub const TextContextMenu = @import("../module.zig").TextContextMenu;
/// The pointer's routing state (from the views module), whose text drag a freed field ends.
pub const PointerInput = @import("../module.zig").PointerInput;
/// The frame clock (from the views module), which times a typing run's undo step.
pub const FrameClock = @import("../module.zig").FrameClock;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("span.zig");
    _ = @import("highlight_spans.zig");
    _ = @import("rich_run.zig");
    _ = @import("rich_line.zig");
    _ = @import("rich_layout.zig");
    _ = @import("rich_faces.zig");
    _ = @import("text_field_state.zig");
    _ = @import("display_text.zig");
    _ = @import("notice_text.zig");
    _ = @import("text_lines.zig");
    _ = @import("editor_metrics.zig");
    _ = @import("text_history.zig");
    _ = @import("text_indentation.zig");
    _ = @import("line_ending.zig");
    _ = @import("text_search.zig");
}
