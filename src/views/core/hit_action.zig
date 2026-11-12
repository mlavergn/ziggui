//! What a tap region does when tapped.

const std = @import("std");
const log = std.log.scoped(.ziggui_hit_action);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A slider's track: a tap or drag at x sets its value.
pub const SliderTrack = struct {
    const Self = @This();

    /// The value the slider sets.
    binding: mod.Binding(f32),

    /// The value at the track's leading end.
    min: f32,

    /// The value at its trailing end.
    max: f32,

    /// The track.
    track: renderer.Rect,

    /// Maps an x-coordinate within the track to a value.
    ///
    /// - `self`: the track.
    /// - `x`: the pointer's x.
    /// - Returns: the value there, clamped to the track.
    pub fn valueForX(self: *const Self, x: f32) f32 {
        if (self.track.width <= 0) return self.min;
        const fraction = std.math.clamp((x - self.track.x) / self.track.width, 0, 1);
        return self.min + (self.max - self.min) * fraction;
    }
};

/// One of a stepper's halves: adds `delta`, clamped.
pub const StepAction = struct {
    const Self = @This();

    /// The value the stepper steps.
    binding: mod.Binding(i64),

    /// What a tap adds.
    delta: i64,

    /// The least value.
    min: i64,

    /// The greatest value.
    max: i64,
};

/// A picker segment: a tap selects its value.
pub const SelectValue = struct {
    const Self = @This();

    /// The selection.
    binding: mod.Binding(i64),

    /// The value a tap selects.
    value: i64,
};

/// What a hit region does when tapped. Controls bind directly to state so the
/// per-frame view value need not be captured by a closure.
pub const HitAction = union(enum) {
    const Self = @This();

    /// Call a callback.
    callback: mod.Callback,
    /// Flip a switch.
    toggle: mod.Binding(bool),
    /// Set a slider's value from a tap/drag x within its track rect.
    slider: SliderTrack,
    /// Add `delta` to a clamped integer stepper.
    step: StepAction,
    /// Focus a text field (the app is responsible for unfocusing others).
    focus: *mod.TextFieldState,
    /// Focus a `TextEditor` and place the caret at the clicked point. Carries the
    /// font metrics and the text-area origin/scroll so the byte index can be
    /// resolved when performed (with only the tap point, no `Context`).
    /// The same payload also drives mouse drag-selection (see `PointerInput.drag`).
    textClick: mod.TextClick,
    /// Select a specific value (e.g. a picker segment).
    select: SelectValue,
    /// An overlay's tap-to-dismiss region: flips the overlay's binding, as
    /// `toggle` does. Its own variant so the app can tell it from content
    /// (a custom title bar still drags under it; see `WindowHitTest`).
    dismiss: mod.Binding(bool),
    /// Arm a drag-area handler (see `View.onDrag`).
    drag: mod.DragCallback,
    /// A right-click handler; never fires on a primary click (`PointerInput.tap` skips it).
    secondary: mod.Callback,
    /// Press-drag text selection in a selectable rich-text view.
    textSelect: *const mod.SelectHit,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
