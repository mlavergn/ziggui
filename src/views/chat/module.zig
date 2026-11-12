//! Pieces for a chat transcript: a status mark, a disclosure group, a chip, and the
//! blocks a Markdown reply is drawn with (a code block, a quote, a bubble).

const std = @import("std");
const log = std.log.scoped(.ziggui_chat_module);

/// Where the thing a `StatusMark` stands for is.
pub const StatusMarkState = @import("chat.zig").StatusMarkState;
/// A round mark for a row's state.
pub const StatusMark = @import("chat.zig").StatusMark;
/// A header that folds content away, like SwiftUI's `DisclosureGroup`.
pub const DisclosureGroup = @import("chat.zig").DisclosureGroup;
/// A small capsule: a mode, a model, an attachment.
pub const Chip = @import("chat.zig").Chip;
/// Preformatted text on a tinted panel.
pub const CodeBlock = @import("chat.zig").CodeBlock;
/// A quoted block behind a bar.
pub const Quote = @import("chat.zig").Quote;
/// A message bubble.
pub const Bubble = @import("chat.zig").Bubble;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// A filled circle (from the views module).
pub const Circle = @import("../module.zig").Circle;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// An icon from the icon font (from the views module).
pub const Icon = @import("../module.zig").Icon;
/// The icon font's glyph names (from the views module).
pub const IconName = @import("../module.zig").IconName;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// Text that wraps to the width it is given (from the views module).
pub const WrappedText = @import("../module.zig").WrappedText;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("chat.zig");
}
