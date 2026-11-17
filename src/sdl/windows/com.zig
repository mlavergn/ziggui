//! The bits of COM the Windows web view and media player share: the
//! apartment, vtable slots called by index, `IUnknown`, and UTF-16 strings.
//! Windows only: every caller is behind `os_tag == .windows`.

const std = @import("std");
const log = std.log.scoped(.ziggui_com);
const renderer = @import("renderer");
const views = @import("views");

/// COM's `HRESULT`: negative is a failure.
pub const HRESULT = i32;

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, flags: u32) callconv(.winapi) HRESULT;
extern "ole32" fn CoCreateInstance(class: *const std.os.windows.GUID, outer: ?*anyopaque, context: u32, interface: *const std.os.windows.GUID, object: *?*anyopaque) callconv(.winapi) HRESULT;
extern "ole32" fn CoTaskMemFree(memory: ?*anyopaque) callconv(.winapi) void;

/// `IUnknown`'s vtable slots, the first three of every interface.
const UnknownSlot = struct {
    const Self = @This();

    /// `QueryInterface`.
    const query_interface = 0;
    /// `AddRef`.
    const add_ref = 1;
    /// `Release`.
    const release = 2;
};

/// COM as the Windows web view and media player call it.
pub const Com = struct {
    const Self = @This();

    /// `S_OK`.
    pub const ok: HRESULT = 0;
    /// `S_FALSE`: succeeded, with nothing done (`OnVideoStreamTick` with no new frame).
    pub const false_ok: HRESULT = 1;
    /// `E_NOINTERFACE`.
    pub const no_interface: HRESULT = @bitCast(@as(u32, 0x80004002));
    /// `E_POINTER`.
    pub const bad_pointer: HRESULT = @bitCast(@as(u32, 0x80004003));
    /// `E_FAIL`.
    pub const failed: HRESULT = @bitCast(@as(u32, 0x80004005));
    /// `RPC_E_CHANGED_MODE`: COM already runs multithreaded on this thread.
    const changed_mode: HRESULT = @bitCast(@as(u32, 0x80010106));
    /// `COINIT_APARTMENTTHREADED`, which WebView2 requires.
    const apartment_threaded: u32 = 0x2;
    /// `CLSCTX_INPROC_SERVER`.
    const in_process: u32 = 0x1;

    /// `IUnknown`'s identifier.
    pub const iid_unknown = std.os.windows.GUID.parse("{00000000-0000-0000-C000-000000000046}");

    /// The apartment has been entered on the UI thread.
    var apartment_entered: bool = false;

    /// Enters a single-threaded apartment on the calling (UI) thread once; a
    /// thread SDL already put in one keeps it.
    ///
    /// - Returns: false when COM runs multithreaded here, which WebView2 refuses.
    pub fn enterApartment() bool {
        if (apartment_entered) return true;
        const result = CoInitializeEx(null, Self.apartment_threaded);
        if (result == Self.changed_mode) {
            log.warn("COM is multithreaded on the UI thread", .{});
            return false;
        }
        apartment_entered = result >= 0;
        return apartment_entered;
    }

    /// Makes an in-process COM object.
    ///
    /// - `class`: its class identifier.
    /// - `interface`: the interface wanted.
    /// - Returns: the object, or null when COM refused.
    pub fn create(class: *const std.os.windows.GUID, interface: *const std.os.windows.GUID) ?*anyopaque {
        var object: ?*anyopaque = null;
        const result = CoCreateInstance(class, null, Self.in_process, interface, &object);
        if (result < 0) {
            log.warn("CoCreateInstance failed [0x{x}]", .{@as(u32, @bitCast(result))});
            return null;
        }
        return object;
    }

    /// The function in an object's vtable at `slot`, typed as `Function`.
    ///
    /// - `Function`: the method's function pointer type, `self` first.
    /// - `object`: the COM object.
    /// - `slot`: the method's index in the vtable, `IUnknown`'s three counted.
    /// - Returns: the method.
    pub fn method(comptime Function: type, object: *anyopaque, comptime slot: usize) Function {
        const table: *const [*]const ?*const anyopaque = @ptrCast(@alignCast(object));
        return @ptrCast(table.*[slot].?);
    }

    /// Asks an object for another of its interfaces.
    ///
    /// - `object`: the COM object.
    /// - `interface`: the interface wanted.
    /// - Returns: the interface (a reference the caller releases), or null.
    pub fn query(object: *anyopaque, interface: *const std.os.windows.GUID) ?*anyopaque {
        var found: ?*anyopaque = null;
        const result = Self.method(*const fn (*anyopaque, *const std.os.windows.GUID, *?*anyopaque) callconv(.winapi) HRESULT, object, UnknownSlot.query_interface)(object, interface, &found);
        return if (result < 0) null else found;
    }

    /// Takes a reference to an object.
    ///
    /// - `object`: the COM object.
    pub fn addRef(object: *anyopaque) void {
        _ = Self.method(*const fn (*anyopaque) callconv(.winapi) u32, object, UnknownSlot.add_ref)(object);
    }

    /// Drops a reference to an object, when there is one.
    ///
    /// - `object`: the COM object, or null.
    pub fn release(object: ?*anyopaque) void {
        const held = object orelse return;
        _ = Self.method(*const fn (*anyopaque) callconv(.winapi) u32, held, UnknownSlot.release)(held);
    }

    /// Frees a string or buffer COM handed over (`CoTaskMemAlloc`'d).
    ///
    /// - `memory`: the memory, or null.
    pub fn freeTask(memory: ?*anyopaque) void {
        CoTaskMemFree(memory);
    }

    /// Converts UTF-8 to a NUL-terminated UTF-16 string, each byte that does
    /// not decode replaced with U+FFFD and the text around it kept.
    ///
    /// - `allocator`: owns the result.
    /// - `text`: the UTF-8 text.
    /// - Returns: the UTF-16 copy; propagates allocation failure.
    pub fn wide(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![:0]u16 {
        return std.unicode.wtf8ToWtf16LeAllocZ(allocator, text) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => return Self.wideReplacing(allocator, text),
        };
    }

    /// Converts UTF-8 that does not all decode to UTF-16, stepping over it as
    /// every UTF-8 step in ziggui does (`TextLines.nextCodepointEnd`): a
    /// sequence that decodes is kept, a byte that does not is U+FFFD.
    ///
    /// - `allocator`: owns the result.
    /// - `text`: the UTF-8 text.
    /// - Returns: the UTF-16 copy; propagates allocation failure.
    fn wideReplacing(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![:0]u16 {
        var units: std.ArrayList(u16) = .empty;
        errdefer units.deinit(allocator);
        const lines = views.TextLines.init(text);
        var index: usize = 0;
        while (index < text.len) {
            const end = lines.nextCodepointEnd(index);
            // A lone byte past ASCII is one that did not decode.
            const codepoint: u21 = if (end - index == 1 and text[index] >= 0x80) 0xFFFD else renderer.TextShaper.decodeSequence(text[index..end]) catch 0xFFFD;
            if (codepoint < 0x10000) {
                try units.append(allocator, std.mem.nativeToLittle(u16, @intCast(codepoint)));
            } else {
                const offset = codepoint - 0x10000;
                try units.append(allocator, std.mem.nativeToLittle(u16, @intCast(0xD800 + (offset >> 10))));
                try units.append(allocator, std.mem.nativeToLittle(u16, @intCast(0xDC00 + (offset & 0x3FF))));
            }
            index = end;
        }
        return units.toOwnedSliceSentinel(allocator, 0);
    }

    /// Converts a NUL-terminated UTF-16 string to UTF-8.
    ///
    /// - `allocator`: owns the result.
    /// - `text`: the UTF-16 text, or null for an empty one.
    /// - Returns: the UTF-8 copy (unpaired surrogates replaced); propagates allocation failure.
    pub fn narrow(allocator: std.mem.Allocator, text: ?[*:0]const u16) std.mem.Allocator.Error![]u8 {
        const units = std.mem.span(text orelse return allocator.alloc(u8, 0));
        return std.unicode.utf16LeToUtf8Alloc(allocator, units) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                var buffer: std.ArrayList(u8) = .empty;
                errdefer buffer.deinit(allocator);
                var iterator = std.unicode.Wtf16LeIterator.init(units);
                while (iterator.nextCodepoint()) |codepoint| {
                    const scalar: u21 = if (codepoint >= 0xD800 and codepoint <= 0xDFFF) 0xFFFD else codepoint;
                    var encoded: [4]u8 = undefined;
                    const length = std.unicode.utf8Encode(scalar, &encoded) catch @panic("a scalar value with its surrogates replaced always encodes");
                    try buffer.appendSlice(allocator, encoded[0..length]);
                }
                return buffer.toOwnedSlice(allocator);
            },
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "com: text goes to UTF-16 and back unchanged" {
    const allocator = std.testing.allocator;
    const units = try Com.wide(allocator, "héllo ✓");
    defer allocator.free(units);
    const back = try Com.narrow(allocator, units.ptr);
    defer allocator.free(back);
    try std.testing.expectEqualStrings("héllo ✓", back);
}

test "com: a byte that does not decode becomes U+FFFD, the rest kept" {
    const allocator = std.testing.allocator;
    // "a", a stray continuation byte, "é", a cut lead byte, then "😀" (a pair).
    const converted = try Com.wide(allocator, "a\x80\xc3\xa9\xe2z\xf0\x9f\x98\x80");
    defer allocator.free(converted);
    const expected = [_]u16{ 'a', 0xFFFD, 0xE9, 0xFFFD, 'z', 0xD83D, 0xDE00 };
    for (expected, 0..) |unit, index| try std.testing.expectEqual(std.mem.nativeToLittle(u16, unit), converted[index]);
    try std.testing.expectEqual(expected.len, converted.len);
}
