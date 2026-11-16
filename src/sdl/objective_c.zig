//! A small typed bridge to the Objective-C runtime for frameworks SDL does
//! not wrap (AVFoundation, Core Animation): messages, classes, strings and
//! autorelease pools, plus the C geometry and time structs they pass by
//! value. macOS only; nothing here is analyzed on other targets.

const std = @import("std");
const log = std.log.scoped(.ziggui_objective_c);

/// An Objective-C object pointer (`id`), or nil.
pub const Id = ?*anyopaque;

/// Core Graphics' `CGPoint` (AppKit's `NSPoint`).
pub const CGPoint = extern struct {
    const Self = @This();

    /// The x coordinate.
    x: f64 = 0,
    /// The y coordinate.
    y: f64 = 0,
};

/// Core Graphics' `CGSize` (AppKit's `NSSize`).
pub const CGSize = extern struct {
    const Self = @This();

    /// The width.
    width: f64 = 0,
    /// The height.
    height: f64 = 0,
};

/// Core Graphics' `CGRect` (AppKit's `NSRect`).
pub const CGRect = extern struct {
    const Self = @This();

    /// The origin.
    origin: CGPoint = .{},
    /// The size.
    size: CGSize = .{},

    /// Reports whether two rects are the same, coordinate for coordinate.
    ///
    /// - `self`: the rect.
    /// - `other`: the other rect.
    /// - Returns: true when equal.
    pub fn eql(self: *const Self, other: Self) bool {
        return self.origin.x == other.origin.x and self.origin.y == other.origin.y and
            self.size.width == other.size.width and self.size.height == other.size.height;
    }
};

/// Core Media's `CMTime`: a rational time, `value / timescale` seconds.
pub const CMTime = extern struct {
    const Self = @This();

    /// The numerator.
    value: i64 = 0,
    /// The denominator, in units per second.
    timescale: i32 = 0,
    /// `kCMTimeFlags_Valid`, `_Indefinite` and the others.
    flags: u32 = 0,
    /// Distinguishes unrelated timelines; 0 for ordinary times.
    epoch: i64 = 0,
};

/// Core Media's `CMTimeRange`.
pub const CMTimeRange = extern struct {
    const Self = @This();

    /// Where the range starts.
    start: CMTime = .{},
    /// How long it lasts.
    duration: CMTime = .{},
};

/// The Objective-C runtime calls, as methods of one namespace.
pub const ObjectiveC = struct {
    const Self = @This();

    extern "objc" fn objc_getClass(name: [*:0]const u8) Id;
    extern "objc" fn sel_registerName(name: [*:0]const u8) Id;
    extern "objc" fn objc_msgSend() void;
    extern "objc" fn objc_autoreleasePoolPush() ?*anyopaque;
    extern "objc" fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;

    /// The class named `name`, or nil when no loaded framework defines it.
    ///
    /// - `name`: the class's name.
    /// - Returns: the class object.
    pub fn class(name: [*:0]const u8) Id {
        return objc_getClass(name);
    }

    /// Sends an Objective-C message with zero to four arguments, typed as the
    /// method's C prototype (structs by value, `BOOL` as `u8`).
    ///
    /// - `Result`: the method's return type.
    /// - `target`: the receiver; a message to nil returns zero.
    /// - `selector`: the method's selector.
    /// - `arguments`: its arguments, as a tuple.
    /// - Returns: what the method returns.
    pub fn send(comptime Result: type, target: Id, selector: [*:0]const u8, arguments: anytype) Result {
        const Function = switch (arguments.len) {
            0 => fn (Id, Id) callconv(.c) Result,
            1 => fn (Id, Id, @TypeOf(arguments[0])) callconv(.c) Result,
            2 => fn (Id, Id, @TypeOf(arguments[0]), @TypeOf(arguments[1])) callconv(.c) Result,
            3 => fn (Id, Id, @TypeOf(arguments[0]), @TypeOf(arguments[1]), @TypeOf(arguments[2])) callconv(.c) Result,
            4 => fn (Id, Id, @TypeOf(arguments[0]), @TypeOf(arguments[1]), @TypeOf(arguments[2]), @TypeOf(arguments[3])) callconv(.c) Result,
            else => @compileError("zero to four arguments"),
        };
        return @call(.auto, Self.messenger(Function), .{ target, Self.selectorNamed(selector) } ++ arguments);
    }

    /// The selector named `name`, for an action or a method a class adds.
    ///
    /// - `name`: the selector's name (`fire:`).
    /// - Returns: the selector.
    pub fn selectorNamed(name: [*:0]const u8) Id {
        return sel_registerName(name);
    }

    /// `objc_msgSend` typed as `Function`, for a method `send` cannot take
    /// (more than four arguments): the receiver, the selector, then its
    /// arguments, in the method's C prototype.
    ///
    /// - `Function`: the method's prototype, `callconv(.c)`.
    /// - Returns: the function to call.
    pub fn messenger(comptime Function: type) *const Function {
        return @ptrCast(&objc_msgSend);
    }

    /// A new, owned instance of `class_name` (`[[Class alloc] init]`); the
    /// caller releases it.
    ///
    /// - `class_name`: the class's name.
    /// - Returns: the object, or nil when the class is missing.
    pub fn new(class_name: [*:0]const u8) Id {
        const allocated = Self.send(Id, Self.class(class_name), "alloc", .{});
        return Self.send(Id, allocated, "init", .{});
    }

    /// Retains an object, so it lives until a matching `release`; nil is ignored.
    ///
    /// - `object`: the object.
    /// - Returns: the object.
    pub fn retain(object: Id) Id {
        if (object != null) _ = Self.send(Id, object, "retain", .{});
        return object;
    }

    /// Releases an owned object; nil is ignored.
    ///
    /// - `object`: the object.
    pub fn release(object: Id) void {
        if (object != null) Self.send(void, object, "release", .{});
    }

    /// An autoreleased `NSString` from UTF-8.
    ///
    /// - `text`: the string.
    /// - Returns: the string object.
    pub fn string(text: [*:0]const u8) Id {
        return Self.send(Id, Self.class("NSString"), "stringWithUTF8String:", .{text});
    }

    /// An `NSString`'s UTF-8 bytes, valid while the string (and the
    /// autorelease pool around the call) lives.
    ///
    /// - `object`: the string, or nil.
    /// - Returns: the bytes; empty for nil.
    pub fn utf8(object: Id) []const u8 {
        if (object == null) return "";
        const bytes = Self.send(?[*:0]const u8, object, "UTF8String", .{}) orelse return "";
        return std.mem.span(bytes);
    }

    /// Opens an autorelease pool: the objects frameworks hand back
    /// autoreleased are freed at the matching `popPool`. A loop with no
    /// `NSApplication` has no pool of its own outside SDL's event pump.
    ///
    /// - Returns: the pool token.
    pub fn pushPool() ?*anyopaque {
        return objc_autoreleasePoolPush();
    }

    /// Closes the pool `pushPool` opened, freeing what it collected.
    ///
    /// - `pool`: the token.
    pub fn popPool(pool: ?*anyopaque) void {
        objc_autoreleasePoolPop(pool);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "objective-c: the C structs keep their C sizes" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(CMTime));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(CMTimeRange));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(CGRect));
}
