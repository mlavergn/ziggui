//! The geometry of the built-in controls, shared by layout and painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_control_metrics);

/// Control sizes, sampled from native macOS 26 controls, that layout reserves
/// and painting draws into.
pub const ControlMetrics = struct {
    const Self = @This();

    /// A button's horizontal padding on each side of its label.
    pub const control_horizontal_padding: f32 = 11;
    /// A switch's width.
    pub const switch_width: f32 = 36;
    /// A switch's height.
    pub const switch_height: f32 = 16;
    /// A slider's height.
    pub const slider_height: f32 = 20;
    /// A slider knob's radius.
    pub const slider_knob_radius: f32 = 8;
    /// A slider track's thickness.
    pub const slider_track_height: f32 = 5;
    /// A progress bar's thickness.
    pub const progress_height: f32 = 7;
    /// The native stepper is a single chevron column (up over down), not +/- boxes.
    pub const stepper_width: f32 = 22;
    /// The stepper box's height.
    pub const stepper_box_height: f32 = 24;
    /// A `Label`'s swatch side.
    pub const label_icon_size: f32 = 14;
    /// The gap between a `Label`'s swatch and its title.
    pub const label_gap: f32 = 6;
    /// Padding around the glyph in an `IconButton` (wider than tall, like the
    /// native glass icon-button capsule), enlarging its tap target.
    pub const icon_button_padding_x: f32 = 9;
    /// The vertical padding around an `IconButton`'s glyph.
    pub const icon_button_padding_y: f32 = 4;
    /// Leading-glyph size inside an icon-label button.
    pub const button_icon_size: f32 = 14;
    /// The gap between an icon-label button's glyph and its label.
    pub const button_icon_gap: f32 = 5;
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
