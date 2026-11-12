//! Animation: a tiny tween engine. An `Animator` holds a set of in-flight
//! tweens, each driving a `State(f32)` from one value to another over a
//! duration. The clock is injected — `tick(delta_time)` takes the elapsed time
//! as a parameter (never reads a wall clock) — so animations are fully
//! deterministic and unit-testable headlessly. The app loop supplies a real
//! delta (e.g. from `SDL_GetTicks`) and redraws while `active()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_animator);
const mod = @import("module.zig");

/// The in-flight tweens of an app.
pub const Animator = struct {
    const Self = @This();

    /// The running tweens.
    tweens: std.ArrayList(mod.Tween) = .empty,
    /// The allocator the tween list grows with.
    allocator: std.mem.Allocator,

    /// An animator with no tweens.
    ///
    /// - `allocator`: allocator for the tween list.
    /// - Returns: the animator.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Free the tween list.
    ///
    /// - `self`: the animator.
    pub fn deinit(self: *Self) void {
        self.tweens.deinit(self.allocator);
    }

    /// Whether any tween is running (the app loop should keep redrawing).
    ///
    /// - `self`: the animator.
    /// - Returns: true while animating.
    pub fn active(self: *const Self) bool {
        return self.tweens.items.len > 0;
    }

    /// Animate `target` from its current value to `to` over `duration` seconds.
    /// Any in-flight tween for the same target is replaced. A non-positive
    /// duration snaps to `to` immediately.
    ///
    /// - `self`: the animator.
    /// - `target`: the state animated; must outlive the tween.
    /// - `to`: the ending value.
    /// - `duration`: seconds the animation lasts.
    /// - `easing`: the timing curve.
    /// - Returns: nothing; propagates allocation failure.
    pub fn animateTo(self: *Self, target: *mod.State(f32), to: f32, duration: f32, easing: mod.Easing) !void {
        var index: usize = 0;
        while (index < self.tweens.items.len) {
            if (self.tweens.items[index].target == target) {
                _ = self.tweens.swapRemove(index);
            } else index += 1;
        }
        if (duration <= 0) {
            target.set(to);
            return;
        }
        try self.tweens.append(self.allocator, .{
            .target = target,
            .from = target.get(),
            .to = to,
            .duration = duration,
            .easing = easing,
        });
    }

    /// Advance every tween by `delta_time` seconds, writing the interpolated
    /// value to its target (which marks subscribers dirty), and dropping
    /// completed tweens.
    ///
    /// - `self`: the animator.
    /// - `delta_time`: seconds since the last tick.
    pub fn tick(self: *Self, delta_time: f32) void {
        var index: usize = 0;
        while (index < self.tweens.items.len) {
            const tween = &self.tweens.items[index];
            tween.elapsed += delta_time;
            const progress = std.math.clamp(tween.elapsed / tween.duration, 0, 1);
            const eased = tween.easing.apply(progress);
            tween.target.set(tween.from + (tween.to - tween.from) * eased);
            if (tween.finished()) {
                tween.target.set(tween.to); // snap exactly to the end value
                _ = self.tweens.swapRemove(index);
                // do not advance index: a swapped-in tween now occupies this slot
            } else index += 1;
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "Animator: animateTo interpolates over ticks and drops finished tweens" {
    var state = mod.State(f32).init(std.testing.allocator, 0);
    defer state.deinit();
    var observer = mod.Observer{ .dirty = false };
    try state.subscribe(&observer);

    var animator = mod.Animator.init(std.testing.allocator);
    defer animator.deinit();
    try animator.animateTo(&state, 1.0, 1.0, .linear);
    try std.testing.expect(animator.active());

    animator.tick(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), state.get(), 1e-5); // linear eased(0.5)
    try std.testing.expect(observer.dirty); // subscriber dirtied

    animator.tick(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), state.get(), 1e-5);
    try std.testing.expect(!animator.active()); // completed and dropped
}

test "Animator: zero duration snaps immediately; repeated target replaces tween" {
    var state = mod.State(f32).init(std.testing.allocator, 0);
    defer state.deinit();
    var animator = mod.Animator.init(std.testing.allocator);
    defer animator.deinit();

    try animator.animateTo(&state, 5.0, 0.0, .linear);
    try std.testing.expectEqual(@as(f32, 5.0), state.get());
    try std.testing.expect(!animator.active());

    // starting a new animation for the same target replaces (not stacks) it
    try animator.animateTo(&state, 10.0, 1.0, .linear);
    try animator.animateTo(&state, 20.0, 1.0, .linear);
    try std.testing.expectEqual(@as(usize, 1), animator.tweens.items.len);
    animator.tick(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), state.get(), 1e-5);
}
