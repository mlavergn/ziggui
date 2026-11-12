//! Per-call scratch storage for a stack's children.

const std = @import("std");
const log = std.log.scoped(.ziggui_scratch);

/// Per-call scratch for a stack's children: on the stack for ordinary stacks,
/// on the heap for a long list (a model table can hold hundreds of rows).
/// Use as `var scratch: Scratch(T) = .{}; defer scratch.deinit(); const items = scratch.get(count);`.
///
/// - `T`: the element type.
/// - Returns: the scratch type.
pub fn Scratch(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Storage for up to 256 elements, used before the heap.
        inline_items: [256]T = undefined,
        /// Heap storage when more than `inline_items` holds were asked for.
        heap_items: ?[]T = null,

        /// Free the heap storage, if any.
        ///
        /// - `self`: the scratch.
        pub fn deinit(self: *Self) void {
            if (self.heap_items) |items| std.heap.page_allocator.free(items);
        }

        /// A slice of `count` elements, valid until `deinit`.
        ///
        /// - `self`: the scratch.
        /// - `count`: how many elements.
        /// - Returns: the uninitialized elements.
        pub fn get(self: *Self, count: usize) []T {
            if (count <= self.inline_items.len) return self.inline_items[0..count];
            self.heap_items = std.heap.page_allocator.alloc(T, count) catch @panic("ziggui: out of memory laying out a stack");
            return self.heap_items.?;
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
