//! Form editors: name/value rows (`KeyValueEditor` over `KeyValueState`) and
//! token fields (`TokenField` over `TokenFieldState`), and a local file and
//! folder picker (`FileBrowser` over `FileBrowserState`), and a search field
//! with a clear button (`SearchField`), composed from text
//! fields, buttons, rows and stacks.

const std = @import("std");
const log = std.log.scoped(.ziggui_forms_module);

/// One row of a `KeyValueEditor`: its name and value fields, on the heap.
pub const KeyValueRow = @import("key_value_state.zig").KeyValueRow;
/// What a `KeyValueEditor` edits: name/value rows (`setPairs`, `pairs`, `add`, `remove`, `count`).
pub const KeyValueState = @import("key_value_state.zig").KeyValueState;
/// An editor of name/value rows with an Add button.
pub const KeyValueEditor = @import("key_value_editor.zig").KeyValueEditor;
/// What a `TokenField` edits: the tokens and their input (`setTokens`, `tokens`, `commit`, `remove`).
pub const TokenFieldState = @import("token_field_state.zig").TokenFieldState;
/// A field of short tokens: capsules, then an input that commits on Enter.
pub const TokenField = @import("token_field.zig").TokenField;
/// What a `FileNode` is: a folder or a file.
pub const FileNodeKind = @import("file_browser_state.zig").FileNodeKind;
/// One entry of a `FileBrowser`'s folder.
pub const FileNode = @import("file_browser_state.zig").FileNode;
/// What a `FileBrowser` shows (`open`, `up`, `enter`, `move`, `select`, `pickAlloc`).
pub const FileBrowserState = @import("file_browser_state.zig").FileBrowserState;
/// A local file and folder picker drawn in the window.
pub const FileBrowser = @import("file_browser.zig").FileBrowser;
/// A search field: a magnifying glass, the text, and a clear button.
pub const SearchField = @import("search_field.zig").SearchField;
/// A composed field's look: the raised ground, a strong hairline border, a 6pt corner.
pub const FieldChrome = @import("field_chrome.zig").FieldChrome;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// The frame clock, and the wake a worker asks for a frame with (`FrameClock.shared()`), from the views module.
pub const FrameClock = @import("../module.zig").FrameClock;
/// The keyboard focus (`Focus.shared()`), from the views module.
pub const Focus = @import("../module.zig").Focus;
/// A push button with a leading glyph and a role (from the views module).
pub const ButtonIconRoled = @import("../module.zig").ButtonIconRoled;
/// A borderless tappable glyph (from the views module).
pub const IconButton = @import("../module.zig").IconButton;
/// A glyph from the icon font (from the views module).
pub const Icon = @import("../module.zig").Icon;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (`fromSlice` keeps its slice), from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// A one-line text field (from the views module).
pub const TextField = @import("../module.zig").TextField;
/// A text field's buffer, caret and selection (from the views module).
pub const TextFieldState = @import("../module.zig").TextFieldState;
/// Nothing, taking no room (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// A full-width rule (from the views module).
pub const Divider = @import("../module.zig").Divider;
/// Taps, drags and the click count of the tap being dispatched (`PointerInput.shared()`), from the views module.
pub const PointerInput = @import("../module.zig").PointerInput;
/// A scroll offset kept across frames (from the views module).
pub const ScrollState = @import("../module.zig").ScrollState;
/// A vertical list of equal rows that builds only the rows in view (from the views module).
pub const VirtualList = @import("../module.zig").VirtualList;
/// The build-time theme colors (from the views module).
pub const BuildTokens = @import("../module.zig").BuildTokens;
/// A list row that shows its selection (from the views module).
pub const SelectableRow = @import("../module.zig").SelectableRow;
/// The colors a `SelectableRow`'s content is drawn in (from the views module).
pub const SelectableRowStyle = @import("../module.zig").SelectableRowStyle;
/// A switch over a `Binding(bool)` (from the views module).
pub const Toggle = @import("../module.zig").Toggle;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("key_value_state.zig");
    _ = @import("key_value_editor.zig");
    _ = @import("token_field_state.zig");
    _ = @import("token_field.zig");
    _ = @import("file_browser_state.zig");
    _ = @import("file_browser.zig");
    _ = @import("search_field.zig");
    _ = @import("field_chrome.zig");
}
