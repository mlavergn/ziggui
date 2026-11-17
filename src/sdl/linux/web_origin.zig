//! Origins of web addresses, compared as the macOS backend compares them, so
//! a page's bridges hear the same pages on every platform.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_origin);

/// The origin rule the Linux web view's bridges apply.
pub const WebOrigin = struct {
    const Self = @This();

    /// Whether two addresses share an origin: a scheme, host and port (as
    /// written, case aside); for an address with no host (`data:`, `about:`)
    /// the whole address, its origin its own alone; `file:` addresses one
    /// origin, the user's files. An address that does not parse matches none.
    ///
    /// - `first_url`: one address.
    /// - `second_url`: the other.
    /// - Returns: true when both parse and their origins agree.
    pub fn same(first_url: []const u8, second_url: []const u8) bool {
        const first = std.Uri.parse(first_url) catch return false;
        const second = std.Uri.parse(second_url) catch return false;
        if (!std.ascii.eqlIgnoreCase(first.scheme, second.scheme)) return false;
        if (std.ascii.eqlIgnoreCase(first.scheme, "file")) return true;
        const first_host = Self.hostOf(first) orelse {
            // Without this any `data:` page would pass for the inline one, and
            // a site could navigate to a `data:` page of its own to reach a bridge.
            return std.mem.eql(u8, first_url, second_url);
        };
        const second_host = Self.hostOf(second) orelse return false;
        return std.ascii.eqlIgnoreCase(first_host, second_host) and first.port == second.port;
    }

    /// An address's host as written, or null when it has none (or an empty one).
    ///
    /// - `uri`: the parsed address.
    /// - Returns: the host, or null.
    fn hostOf(uri: std.Uri) ?[]const u8 {
        const host = uri.host orelse return null;
        const text = switch (host) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };
        return if (text.len == 0) null else text;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "web origin matches scheme, host and port" {
    const console = "http://127.0.0.1:8080/console";
    try std.testing.expect(WebOrigin.same(console, "HTTP://127.0.0.1:8080/other#frag"));
    try std.testing.expect(!WebOrigin.same(console, "http://127.0.0.1:8081/console"));
    try std.testing.expect(!WebOrigin.same(console, "http://example.com:8080/console"));
    try std.testing.expect(!WebOrigin.same(console, "https://127.0.0.1:8080/console"));
    try std.testing.expect(WebOrigin.same("https://Example.com/a", "https://example.COM/b?c"));
    try std.testing.expect(!WebOrigin.same(console, "not an address"));
}

test "web origin keeps an inline page's origin its own" {
    const page = "data:text/html;base64,PHA+";
    try std.testing.expect(WebOrigin.same(page, "data:text/html;base64,PHA+"));
    try std.testing.expect(!WebOrigin.same(page, "data:text/html;base64,PGI+"));
    try std.testing.expect(!WebOrigin.same(page, "about:blank"));
    try std.testing.expect(!WebOrigin.same(page, "http://127.0.0.1:8080/console"));
}

test "web origin counts local files as one origin" {
    try std.testing.expect(WebOrigin.same("file:///tmp/site/index.html", "file:///tmp/site/other.html"));
    try std.testing.expect(!WebOrigin.same("file:///tmp/site/index.html", "http://localhost/index.html"));
}
