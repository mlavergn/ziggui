//! SDL3's cross-platform clipboard (NSPasteboard / Win32 / X11/Wayland) and
//! the OS URL handler.

const std = @import("std");
const log = std.log.scoped(.ziggui_clipboard);
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The system clipboard and the OS default handler for URLs. Stateless: every
/// call goes straight to SDL.
pub const Clipboard = struct {
    const Self = @This();

    /// Puts UTF-8 text on the system clipboard.
    ///
    /// - `allocator`: for a NUL-terminated copy, freed before returning.
    /// - `value`: the text; it need not be NUL-terminated.
    pub fn setText(allocator: std.mem.Allocator, value: []const u8) void {
        const terminated = allocator.dupeSentinel(u8, value, 0) catch |err| {
            log.err("clipboard text not set: {t}", .{err});
            return;
        };
        defer allocator.free(terminated);
        _ = sdl_c.SDL_SetClipboardText(terminated.ptr);
    }

    /// Reads UTF-8 text from the system clipboard. (SDL returns an empty
    /// string rather than null on failure; that is normalized to null.)
    ///
    /// - `allocator`: owns the returned copy.
    /// - Returns: the text, which the caller frees, or null when the clipboard
    ///   is empty.
    pub fn text(allocator: std.mem.Allocator) ?[]u8 {
        const pointer = sdl_c.SDL_GetClipboardText();
        defer sdl_c.SDL_free(pointer);
        if (pointer == null) return null;
        const span = std.mem.span(pointer);
        if (span.len == 0) return null;
        return allocator.dupe(u8, span) catch null;
    }

    /// Reads the clipboard's PNG image, if it holds one.
    ///
    /// - `allocator`: owns the returned copy.
    /// - Returns: the PNG bytes, which the caller frees, or null.
    pub fn png(allocator: std.mem.Allocator) ?[]u8 {
        if (!sdl_c.SDL_HasClipboardData("image/png")) return null;
        var size: usize = 0;
        const pointer = sdl_c.SDL_GetClipboardData("image/png", &size) orelse return null;
        defer sdl_c.SDL_free(pointer);
        if (size == 0) return null;
        const source: [*]const u8 = @ptrCast(pointer);
        return allocator.dupe(u8, source[0..size]) catch null;
    }

    /// Opens a URL (or `file://…` path) in the OS default handler: a folder in
    /// Finder/Explorer/the file manager, or a web URL in the browser.
    /// Cross-platform via SDL3 (`NSWorkspace` / `ShellExecute` / `xdg-open`).
    ///
    /// - `url`: the URL.
    /// - Returns: false on failure.
    pub fn openUrl(url: [*:0]const u8) bool {
        return sdl_c.SDL_OpenURL(url);
    }

    /// Copies a field's current selection to the clipboard (no-op if empty).
    ///
    /// - `field`: the focused field.
    pub fn copySelection(field: *views.TextFieldState) void {
        const selection = field.selectedText();
        if (selection.len == 0) return;
        Self.setText(field.allocator, selection);
    }

    /// Inserts clipboard text at a field's caret, replacing any selection.
    ///
    /// - `field`: the focused field.
    pub fn paste(field: *views.TextFieldState) void {
        const pasted = Self.text(field.allocator) orelse return;
        defer field.allocator.free(pasted);
        field.insert(pasted) catch |err| log.debug("clipboard text not pasted [{t}]", .{err});
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Clipboard);
}
