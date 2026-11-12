//! Text models: rich-text spans and their paragraph layout, and the editable
//! text state behind text fields and editors, with its UTF-8 line geometry and
//! tab-aware metrics.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_module);

/// One styled run of a `RichText`.
pub const Span = @import("span.zig").Span;
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
/// Line and column geometry over a UTF-8 buffer.
pub const TextLines = @import("text_lines.zig").TextLines;
/// Tab-aware widths of edited text.
pub const EditorMetrics = @import("editor_metrics.zig").EditorMetrics;

/// A type-erased tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// The keyboard focus (from the views module), which a freed field leaves.
pub const Focus = @import("../module.zig").Focus;
/// The text-field context menu (from the views module), which a freed field closes.
pub const TextContextMenu = @import("../module.zig").TextContextMenu;
/// The pointer's routing state (from the views module), whose text drag a freed field ends.
pub const PointerInput = @import("../module.zig").PointerInput;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("span.zig");
    _ = @import("rich_run.zig");
    _ = @import("rich_line.zig");
    _ = @import("rich_layout.zig");
    _ = @import("rich_faces.zig");
    _ = @import("text_field_state.zig");
    _ = @import("text_lines.zig");
    _ = @import("editor_metrics.zig");
}
