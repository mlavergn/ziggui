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
    /// A checkbox's side (`.toggleStyle(.checkbox)`).
    pub const checkbox_size: f32 = 14;
    /// The gap between a checkbox and its label.
    pub const checkbox_gap: f32 = 6;
    /// A pop-up button's (`.pickerStyle(.menu)`) up-and-down chevron side.
    pub const popup_chevron_size: f32 = 12;
    /// The gap between a pop-up button's title and its chevron.
    pub const popup_chevron_gap: f32 = 8;
    /// A pop-up button's inset from its trailing edge to its chevron.
    pub const popup_chevron_inset: f32 = 7;
    /// The width of a sunken drop-down list's own button (Windows 2000).
    pub const popup_field_button_width: f32 = 16;
    /// A solid down triangle's width (Windows 2000, Material).
    pub const popup_triangle_width: f32 = 8;
    /// A pop-up menu's check-mark column, before each option's title.
    pub const popup_check_width: f32 = 16;
    /// A pop-up menu's inset around its rows.
    pub const popup_menu_inset: f32 = 5;
    /// A pop-up menu row's padding above and below its title.
    pub const popup_row_padding_y: f32 = 3;
    /// A pop-up menu row's padding before its check column and after its title.
    pub const popup_row_padding_x: f32 = 6;
    /// A checkbox's corner radius, before the theme scales it.
    pub const checkbox_radius: f32 = 4;
    /// The outline width of a checkbox in an explicit `CheckboxStyle`.
    pub const checkbox_line_width: f32 = 1.5;
    /// The check mark's stroke width in an explicit `CheckboxStyle`, as a
    /// fraction of the box's side.
    pub const checkbox_check_weight: f32 = 0.13;
    /// A segmented control's track inset around its segments (and between
    /// them).
    pub const segment_track_inset: f32 = 2;
    /// The room either side of a segmented picker's label: each segment is its
    /// label's width and this twice, as macOS sizes segments to their content.
    pub const picker_segment_padding: f32 = 20;
    /// An icon segmented control's segment width.
    pub const icon_segment_width: f32 = 32;
    /// The space inside an in-place field (`EditableText`'s, the file
    /// browser's path field) around its text.
    pub const inline_field_inset: f32 = 2;
    /// An in-place field's corner radius.
    pub const inline_field_radius: f32 = 4;
    /// An in-place field's focus ring width.
    pub const inline_field_ring: f32 = 1.5;
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
    /// The text size of a key cap (`KeyCap`, a `ButtonKeyed`'s shortcut).
    pub const key_cap_text_size: f32 = 11;
    /// A key cap's padding on each side of its text.
    pub const key_cap_horizontal_padding: f32 = 5;
    /// A key cap's padding above and below its text.
    pub const key_cap_vertical_padding: f32 = 1;
    /// A key cap's corner radius.
    pub const key_cap_radius: f32 = 4;
    /// The gap between a `ButtonKeyed`'s label and its key cap.
    pub const button_key_gap: f32 = 6;
    /// The alpha of a `ButtonKeyed`'s key cap ground over its label color.
    pub const button_key_ground_alpha: f32 = 0.14;
    /// The alpha of a `ButtonKeyed`'s key text over its label color.
    pub const button_key_text_alpha: f32 = 0.8;
    /// The alpha of a `ButtonKeyed`'s key cap hairline over its label color:
    /// the cap's border, as a `KeyCap` has one, in a color that reads on the
    /// button's fill.
    pub const button_key_border_alpha: f32 = 0.3;
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
