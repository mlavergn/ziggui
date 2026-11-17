//! Origins of web addresses, the one rule every platform's web view applies
//! before a page's message reaches a bridge (`WkWebViewBackend`,
//! `WebKitGtkBackend`, `WebView2Backend`), so a page's bridges hear the same
//! pages everywhere.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_origin);

/// The origin rule the web views' bridges apply.
pub const WebOrigin = struct {
    const Self = @This();

    /// Whether two addresses share an origin: a scheme (case aside), then a
    /// host (case aside) and port; for an address with no host (`data:`,
    /// `about:`) the whole address, its origin its own alone, compared with
    /// `%XX` escapes decoded (a platform may report an inline page's address
    /// escaped); `file:` addresses one origin, the user's files. An address
    /// with no scheme, or a hosted one that does not parse, matches none.
    ///
    /// - `first_url`: one address.
    /// - `second_url`: the other.
    /// - Returns: true when their origins agree.
    pub fn same(first_url: []const u8, second_url: []const u8) bool {
        const first_scheme = Self.schemeOf(first_url) orelse return false;
        const second_scheme = Self.schemeOf(second_url) orelse return false;
        if (!std.ascii.eqlIgnoreCase(first_scheme, second_scheme)) return false;
        if (std.ascii.eqlIgnoreCase(first_scheme, "file")) return true;
        const first_hosted = Self.isHosted(first_url, first_scheme);
        if (first_hosted != Self.isHosted(second_url, second_scheme)) return false;
        // Without this any `data:` page would pass for the inline one, and a
        // site could navigate to a `data:` page of its own to reach a bridge.
        if (!first_hosted) return Self.sameDecoded(first_url, second_url);
        const first = std.Uri.parse(first_url) catch return false;
        const second = std.Uri.parse(second_url) catch return false;
        const first_host = Self.hostOf(first) orelse return false;
        const second_host = Self.hostOf(second) orelse return false;
        return std.ascii.eqlIgnoreCase(first_host, second_host) and first.port == second.port;
    }

    /// An address's scheme: the letters, digits, `+`, `-` and `.` before its
    /// first `:`, starting with a letter.
    ///
    /// - `url`: the address.
    /// - Returns: the scheme, or null when the address names none.
    fn schemeOf(url: []const u8) ?[]const u8 {
        const end = std.mem.findScalar(u8, url, ':') orelse return null;
        if (end == 0 or !std.ascii.isAlphabetic(url[0])) return null;
        for (url[0..end]) |byte| {
            if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '-' and byte != '.') return null;
        }
        return url[0..end];
    }

    /// Whether an address has an authority (`scheme://host…`).
    ///
    /// - `url`: the address.
    /// - `scheme`: its scheme.
    /// - Returns: true when `//` follows the scheme's colon.
    fn isHosted(url: []const u8, scheme: []const u8) bool {
        return std.mem.startsWith(u8, url[scheme.len + 1 ..], "//");
    }

    /// Whether two addresses are the same with their `%XX` escapes decoded.
    ///
    /// - `first_url`: one address.
    /// - `second_url`: the other.
    /// - Returns: true when they decode to the same bytes.
    fn sameDecoded(first_url: []const u8, second_url: []const u8) bool {
        var first_index: usize = 0;
        var second_index: usize = 0;
        while (first_index < first_url.len and second_index < second_url.len) {
            if (Self.decodedAt(first_url, &first_index) != Self.decodedAt(second_url, &second_index)) return false;
        }
        return first_index == first_url.len and second_index == second_url.len;
    }

    /// Reads one byte of an address, a `%XX` escape (two hex digits, no
    /// sign) decoded, and moves past it.
    ///
    /// - `url`: the address.
    /// - `index`: where to read; advanced past what was read.
    /// - Returns: the byte.
    fn decodedAt(url: []const u8, index: *usize) u8 {
        const at = index.*;
        if (url[at] == '%' and at + 2 < url.len) {
            const high = std.fmt.charToDigit(url[at + 1], 16) catch null;
            const low = std.fmt.charToDigit(url[at + 2], 16) catch null;
            if (high != null and low != null) {
                index.* = at + 3;
                return high.? * 16 + low.?;
            }
        }
        index.* = at + 1;
        return url[at];
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
    try std.testing.expect(WebOrigin.same("https://ziglang.org/learn/", "HTTPS://ZigLang.org/"));
    try std.testing.expect(!WebOrigin.same("https://ziglang.org/", "https://ziglang.org:8443/"));
    try std.testing.expect(!WebOrigin.same(console, "not an address"));
    try std.testing.expect(!WebOrigin.same("", console));
}

test "web origin keeps an inline page's origin its own, escapes aside" {
    const page = "data:text/html;base64,PHA+";
    try std.testing.expect(WebOrigin.same(page, "data:text/html;base64,PHA+"));
    try std.testing.expect(!WebOrigin.same(page, "data:text/html;base64,PGI+"));
    try std.testing.expect(!WebOrigin.same(page, "about:blank"));
    try std.testing.expect(!WebOrigin.same(page, "http://127.0.0.1:8080/console"));
    // Reported escaped (WebView2), or written raw with what a URL parser refuses.
    try std.testing.expect(WebOrigin.same("data:text/html,<p>a b</p>", "data:text/html,%3Cp%3Ea%20b%3C/p%3E"));
    try std.testing.expect(!WebOrigin.same("data:text/html,a", "data:text/html,b"));
    // An escape is two hex digits: `%+5` is three bytes, not one.
    try std.testing.expect(!WebOrigin.same("data:,\x05", "data:,%+5"));
}

test "web origin counts local files as one origin" {
    try std.testing.expect(WebOrigin.same("file:///tmp/site/index.html", "file:///tmp/site/other.html"));
    try std.testing.expect(!WebOrigin.same("file:///tmp/site/index.html", "http://localhost/index.html"));
}
