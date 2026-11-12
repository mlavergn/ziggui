//! Values for a freedesktop desktop entry (`.desktop` file), escaped per the
//! Desktop Entry Specification, so a path with spaces, quotes, `$`, `%` or
//! backslashes in it means what it says. Pure; the SDL runtime's
//! `DesktopInstall.install` and `DesktopInstall.state` write and read with it.

const std = @import("std");
const log = std.log.scoped(.ziggui_desktop_entry);

/// Appends into a fixed buffer, remembering whether it ran out.
const BoundedWriter = struct {
    const Self = @This();

    /// Where the bytes go.
    buffer: []u8,

    /// How many bytes are written.
    length: usize = 0,

    /// Whether a write did not fit.
    full: bool = false,

    /// Appends `bytes`, or marks the writer full when they do not fit.
    ///
    /// - `self`: the writer.
    /// - `bytes`: what is appended.
    fn put(self: *Self, bytes: []const u8) void {
        if (self.full or self.length + bytes.len > self.buffer.len) {
            self.full = true;
            return;
        }
        @memcpy(self.buffer[self.length..][0..bytes.len], bytes);
        self.length += bytes.len;
    }

    /// What was written.
    ///
    /// - `self`: the writer.
    /// - Returns: the bytes, or null when a write did not fit.
    fn done(self: *const Self) ?[]const u8 {
        return if (self.full) null else self.buffer[0..self.length];
    }
};

/// The escaped values a desktop entry is written with.
pub const DesktopEntry = struct {
    const Self = @This();

    /// A value of type string: a backslash is written `\\`. Null when `text`
    /// holds a control character (a newline would end the line, and the entry
    /// with it).
    ///
    /// - `buffer`: where the value is written.
    /// - `text`: the raw value (a path, a name).
    /// - Returns: the escaped value, in `buffer`; null for a control character
    ///   or when `buffer` is too small.
    pub fn stringValue(buffer: []u8, text: []const u8) ?[]const u8 {
        var writer = BoundedWriter{ .buffer = buffer };
        for (text) |byte| {
            if (byte < 0x20 or byte == 0x7f) return null;
            if (byte == '\\') writer.put("\\\\") else writer.put(&.{byte});
        }
        return writer.done();
    }

    /// An `Exec` value that runs `program` with one argument, the file opened
    /// (`%f`), or none when `with_file` is false. The program is quoted, with
    /// the characters the spec reserves inside quotes (`"`, `` ` ``, `$`, `\`)
    /// escaped by a backslash, and then the string rule applied on top (each of
    /// those backslashes, and a literal one, doubled again: a backslash in the
    /// path becomes four). A `%` is written `%%`, so no field code is read in
    /// the path. Null when `program` holds a control character, which no
    /// escape represents inside quotes.
    ///
    /// - `buffer`: where the value is written.
    /// - `program`: the executable's absolute path.
    /// - `with_file`: add the `%f` field code, so a file or folder can be opened with it.
    /// - Returns: the value, in `buffer`; null for a control character or when
    ///   `buffer` is too small.
    pub fn execValue(buffer: []u8, program: []const u8, with_file: bool) ?[]const u8 {
        var writer = BoundedWriter{ .buffer = buffer };
        writer.put("\"");
        for (program) |byte| {
            if (byte < 0x20 or byte == 0x7f) return null;
            switch (byte) {
                // Quoting rule (`\x`), then the string rule doubles the backslash.
                '"', '`', '$' => {
                    writer.put("\\\\");
                    writer.put(&.{byte});
                },
                '\\' => writer.put("\\\\\\\\"),
                '%' => writer.put("%%"),
                else => writer.put(&.{byte}),
            }
        }
        writer.put("\"");
        if (with_file) writer.put(" %f");
        return writer.done();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a plain path is quoted and left alone" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("\"/opt/My App/bin/app\"", DesktopEntry.execValue(&buffer, "/opt/My App/bin/app", false).?);
    try std.testing.expectEqualStrings("\"/usr/bin/app\" %f", DesktopEntry.execValue(&buffer, "/usr/bin/app", true).?);
}

test "reserved characters are escaped twice, and % is doubled" {
    var buffer: [256]u8 = undefined;
    // In the file: a quote is \\" , a dollar \\$ , a backtick \\` , a backslash
    // \\\\ (four), and a percent %%.
    try std.testing.expectEqualStrings("\"/a\\\\\"b\\\\$c\\\\`d\\\\\\\\e%%f\"", DesktopEntry.execValue(&buffer, "/a\"b$c`d\\e%f", false).?);
}

test "a control character or a short buffer is refused" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqual(null, DesktopEntry.execValue(&buffer, "/a\nb", false));
    try std.testing.expectEqual(null, DesktopEntry.stringValue(&buffer, "x\ty"));
    var tiny: [4]u8 = undefined;
    try std.testing.expectEqual(null, DesktopEntry.execValue(&tiny, "/usr/bin/app", false));
}

test "a string value doubles its backslashes" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("C:\\\\icons\\\\app.png", DesktopEntry.stringValue(&buffer, "C:\\icons\\app.png").?);
    try std.testing.expectEqualStrings("/home/me/.local/share/icons/app.png", DesktopEntry.stringValue(&buffer, "/home/me/.local/share/icons/app.png").?);
}
