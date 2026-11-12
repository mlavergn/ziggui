//! State(T): the observable-value primitive behind ziggui's reactivity.
//! `State(T)` owns a value and a list of subscribed observers; mutating it (to
//! a different value) marks every subscriber dirty. Its `binding` is the
//! type-erased two-way handle (`Binding(T)`) controls like TextField, Toggle,
//! and Slider take.

const std = @import("std");
const log = std.log.scoped(.ziggui_state);
const mod = @import("module.zig");

/// An observable value. Mirrors SwiftUI's `@State`.
///
/// - `T`: the value's type.
/// - Returns: the state type.
pub fn State(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The current value.
        value: T,
        /// The observers marked dirty when the value changes.
        subscribers: std.ArrayList(*mod.Observer) = .empty,
        /// The allocator the subscriber list grows with.
        allocator: std.mem.Allocator,

        /// A state holding `initial`, with no subscribers.
        ///
        /// - `allocator`: allocator for the subscriber list.
        /// - `initial`: the starting value.
        /// - Returns: the state.
        pub fn init(allocator: std.mem.Allocator, initial: T) Self {
            const self = Self{ .value = initial, .allocator = allocator };
            return self;
        }

        /// Free the subscriber list.
        ///
        /// - `self`: the state.
        pub fn deinit(self: *Self) void {
            self.subscribers.deinit(self.allocator);
        }

        /// The current value.
        ///
        /// - `self`: the state.
        /// - Returns: the value.
        pub fn get(self: *const Self) T {
            return self.value;
        }

        /// Pointer to the underlying value for in-place mutation. Callers that
        /// mutate through this pointer must call `notify()` afterwards.
        ///
        /// - `self`: the state.
        /// - Returns: the value's address.
        pub fn pointer(self: *Self) *T {
            return &self.value;
        }

        /// Assign a new value. If it differs from the current value (by
        /// `std.meta.eql`), all subscribers are marked dirty. For slice-bearing
        /// types `eql` compares by pointer+len, not contents.
        ///
        /// - `self`: the state.
        /// - `new_value`: the value.
        pub fn set(self: *Self, new_value: T) void {
            if (Self.valuesEqual(self.value, new_value)) return;
            self.value = new_value;
            self.notify();
        }

        /// Apply a mutating function to the value, then notify unconditionally.
        ///
        /// - `self`: the state.
        /// - `mutate`: the function, given the value's address.
        pub fn update(self: *Self, comptime mutate: fn (*T) void) void {
            mutate(&self.value);
            self.notify();
        }

        /// Mark every subscriber dirty.
        ///
        /// - `self`: the state.
        pub fn notify(self: *Self) void {
            for (self.subscribers.items) |observer| observer.markDirty();
        }

        /// Add a subscriber (once; subscribing again does nothing).
        ///
        /// - `self`: the state.
        /// - `observer`: the observer.
        /// - Returns: nothing; propagates allocation failure.
        pub fn subscribe(self: *Self, observer: *mod.Observer) !void {
            for (self.subscribers.items) |existing| {
                if (existing == observer) return; // idempotent
            }
            try self.subscribers.append(self.allocator, observer);
        }

        /// Remove a subscriber.
        ///
        /// - `self`: the state.
        /// - `observer`: the observer.
        pub fn unsubscribe(self: *Self, observer: *mod.Observer) void {
            var index: usize = 0;
            while (index < self.subscribers.items.len) {
                if (self.subscribers.items[index] == observer) {
                    _ = self.subscribers.swapRemove(index);
                } else index += 1;
            }
        }

        /// How many observers are subscribed.
        ///
        /// - `self`: the state.
        /// - Returns: the count.
        pub fn subscriberCount(self: *const Self) usize {
            return self.subscribers.items.len;
        }

        /// A two-way binding into this state.
        ///
        /// - `self`: the state; must outlive the binding.
        /// - Returns: the binding.
        pub fn binding(self: *Self) mod.Binding(T) {
            return .{
                .context = self,
                .get_fn = Self.bindingGet,
                .set_fn = Self.bindingSet,
            };
        }

        /// A binding's read: the state's value.
        ///
        /// - `context`: the state.
        /// - Returns: the value.
        fn bindingGet(context: *anyopaque) T {
            const self: *Self = @ptrCast(@alignCast(context));
            return self.get();
        }

        /// A binding's write: set the state's value.
        ///
        /// - `context`: the state.
        /// - `value`: the new value.
        fn bindingSet(context: *anyopaque, value: T) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.set(value);
        }

        /// Whether two values count as equal for change notification: exact
        /// equality for floats, `std.meta.eql` otherwise.
        ///
        /// - `left`: the first value.
        /// - `right`: the second value.
        /// - Returns: true when equal.
        fn valuesEqual(left: T, right: T) bool {
            return switch (@typeInfo(T)) {
                .float, .comptime_float => left == right,
                else => std.meta.eql(left, right),
            };
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

/// A mutation for `State.update`'s test.
const AddFive = struct {
    const Self = @This();

    /// Add five.
    ///
    /// - `value`: the value mutated.
    fn apply(value: *i32) void {
        value.* += 5;
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "State: get/set basic value" {
    var state = mod.State(i32).init(std.testing.allocator, 0);
    defer state.deinit();
    try std.testing.expectEqual(@as(i32, 0), state.get());
    state.set(42);
    try std.testing.expectEqual(@as(i32, 42), state.get());
}

test "State: set marks subscribers dirty only when value changes" {
    var state = mod.State(i32).init(std.testing.allocator, 5);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);

    state.set(5); // unchanged -> no dirty
    try std.testing.expect(!observer.dirty);

    state.set(6); // changed -> dirty
    try std.testing.expect(observer.dirty);
}

test "State: multiple subscribers all notified" {
    var state = mod.State(i32).init(std.testing.allocator, 0);
    defer state.deinit();
    var first = mod.Observer{ .dirty = false };
    var second = mod.Observer{ .dirty = false };
    try state.subscribe(&first);
    try state.subscribe(&second);
    state.set(1);
    try std.testing.expect(first.dirty and second.dirty);
}

test "State: subscribe is idempotent" {
    var state = mod.State(i32).init(std.testing.allocator, 0);
    defer state.deinit();
    var observer = mod.Observer{};
    try state.subscribe(&observer);
    try state.subscribe(&observer);
    try std.testing.expectEqual(@as(usize, 1), state.subscriberCount());
}

test "State: unsubscribe stops notifications" {
    var state = mod.State(i32).init(std.testing.allocator, 0);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);
    state.unsubscribe(&observer);
    try std.testing.expectEqual(@as(usize, 0), state.subscriberCount());
    state.set(99);
    try std.testing.expect(!observer.dirty);
}

test "State: update applies mutation and notifies unconditionally" {
    var state = mod.State(i32).init(std.testing.allocator, 10);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);
    state.update(AddFive.apply);
    try std.testing.expectEqual(@as(i32, 15), state.get());
    try std.testing.expect(observer.dirty);
}

test "Binding: two-way read/write routes through state" {
    var state = mod.State(i32).init(std.testing.allocator, 1);
    defer state.deinit();
    const binding = state.binding();
    try std.testing.expectEqual(@as(i32, 1), binding.get());
    binding.set(7);
    try std.testing.expectEqual(@as(i32, 7), state.get());
    // mutating the state is visible through the binding
    state.set(9);
    try std.testing.expectEqual(@as(i32, 9), binding.get());
}

test "Binding: setting through binding marks subscribers dirty" {
    var state = mod.State(bool).init(std.testing.allocator, false);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);
    const binding = state.binding();
    binding.set(true);
    try std.testing.expect(observer.dirty);
    try std.testing.expect(state.get());
}

test "State: works with float type (exact equality guard)" {
    var state = mod.State(f32).init(std.testing.allocator, 1.5);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);
    state.set(1.5);
    try std.testing.expect(!observer.dirty);
    state.set(2.5);
    try std.testing.expect(observer.dirty);
}
