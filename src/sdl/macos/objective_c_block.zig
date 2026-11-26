//! An Objective-C block a framework calls back through (a completion
//! handler, `LAContext`'s reply), laid out by hand as clang lays out a
//! block literal that captures one pointer: `isa`, flags, `invoke`, a
//! descriptor, then the captured `context`. It is a stack block
//! (`_NSConcreteStackBlock`), as clang makes for `^{ … }` capturing a
//! variable: a framework that keeps it copies it with `Block_copy` into
//! memory of its own, which it frees with `Block_release` when it is done,
//! so the block itself may go as soon as the call taking it returns. What
//! `context` points at must outlive the block's last call; `invoke` gets the
//! copy, and reaches it through `context`. macOS only.

const std = @import("std");
const log = std.log.scoped(.ziggui_objective_c_block);
const mod = @import("module.zig");

/// The descriptor every block points at: its size, nothing to copy or dispose.
pub const ObjectiveCBlockDescriptor = extern struct {
    const Self = @This();

    /// Always 0.
    reserved: c_ulong = 0,
    /// The block's size in bytes, its captured `context` included: what `Block_copy` copies.
    size: c_ulong,
};

/// A stack block whose `invoke` is a C function of the type `Invoke`,
/// taking the block (a framework's copy) first, then the block's arguments.
///
/// - `Invoke`: the function's prototype, `callconv(.c)`.
/// - Returns: the block's type.
pub fn ObjectiveCBlock(comptime Invoke: type) type {
    return extern struct {
        const Self = @This();

        /// No flags: no copy or dispose helper, nothing captured that needs one.
        const no_flags: c_int = 0;
        /// The descriptor blocks of this type share.
        const shared_descriptor: ObjectiveCBlockDescriptor = .{ .size = @sizeOf(Self) };

        /// libclosure's class for blocks on the stack, which `Block_copy` copies to the heap.
        extern "c" const _NSConcreteStackBlock: anyopaque;

        /// The block's class, as an object's `isa`.
        isa: *const anyopaque,
        /// Its flags.
        flags: c_int,
        /// Unused.
        reserved: c_int = 0,
        /// What a call runs.
        invoke: *const Invoke,
        /// Its descriptor.
        descriptor: *const ObjectiveCBlockDescriptor,
        /// The captured pointer, copied with the block.
        context: ?*anyopaque,

        /// A block that runs `invoke` with `context` captured.
        ///
        /// - `invoke`: the function, given the block first.
        /// - `context`: what `invoke` reaches through the block; must outlive its last call.
        /// - Returns: the block, valid until the call that takes it returns.
        pub fn init(invoke: *const Invoke, context: ?*anyopaque) Self {
            const self = Self{
                .isa = &_NSConcreteStackBlock,
                .flags = no_flags,
                .invoke = invoke,
                .descriptor = &shared_descriptor,
                .context = context,
            };
            return self;
        }

        /// The captured pointer of the block `invoke` was given.
        ///
        /// - `block`: the block, as `invoke` receives it (a copy, or this one).
        /// - Returns: its `context`.
        pub fn contextOf(block: *anyopaque) ?*anyopaque {
            const self: *Self = @ptrCast(@alignCast(block));
            return self.context;
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a block keeps clang's block literal layout" {
    const Block = ObjectiveCBlock(fn (*anyopaque) callconv(.c) void);
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(Block));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Block, "invoke"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Block, "descriptor"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Block, "context"));
}

test "Block_copy copies a block to the heap with its context, and the copy runs" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const Probe = struct {
        const Self = @This();

        extern "c" fn _Block_copy(block: *const anyopaque) ?*anyopaque;
        extern "c" fn _Block_release(block: *const anyopaque) void;

        /// Counts a call through the block's context.
        ///
        /// - `block`: the block called.
        fn invoke(block: *anyopaque) callconv(.c) void {
            const counter: *u32 = @ptrCast(@alignCast(ObjectiveCBlock(fn (*anyopaque) callconv(.c) void).contextOf(block).?));
            counter.* += 1;
        }
    };
    const Block = ObjectiveCBlock(fn (*anyopaque) callconv(.c) void);
    var calls: u32 = 0;
    var block = Block.init(&Probe.invoke, &calls);
    const copy = Probe._Block_copy(&block) orelse return error.NotCopied;
    // The copy is the runtime's own, so the original may go at once.
    try std.testing.expect(copy != @as(*anyopaque, @ptrCast(&block)));
    block = undefined;
    const copied: *Block = @ptrCast(@alignCast(copy));
    copied.invoke(copy);
    try std.testing.expectEqual(@as(u32, 1), calls);
    Probe._Block_release(copy);
}
