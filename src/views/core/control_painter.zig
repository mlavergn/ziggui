//! Paints the built-in controls: buttons, switches, sliders, steppers,
//! progress bars, labels, icons and segmented pickers.

const std = @import("std");
const log = std.log.scoped(.ziggui_control_painter);
const mod = @import("module.zig");
const renderer = @import("renderer");
/// The colors of a key cap painted inside a control (`ControlPainter.paintKeyCap`).
pub const KeyCapColors = struct {
    const Self = @This();

    /// The cap's fill.
    ground: renderer.Color,
    /// The cap's hairline border.
    border: renderer.Color,
    /// The key's text.
    text: renderer.Color,
};

/// Paints each control kind into its laid-out rect: the view layer owns the
/// geometry, the theme's painter draws the chrome, and each control registers
/// the hit regions that make it work.
pub const ControlPainter = struct {
    const Self = @This();

    /// The y at which something `height` tall is centered in `rect`.
    ///
    /// - `rect`: the rect.
    /// - `height`: the height to center.
    /// - Returns: the top.
    pub fn verticalCenter(rect: renderer.Rect, height: f32) f32 {
        return rect.y + (rect.height - height) / 2;
    }

    /// Paints a push button: theme chrome, an optional glyph and the label.
    ///
    /// - `context`: the context.
    /// - `button`: the button.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintButton(context: *const mod.Context, button: mod.ButtonData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const dim: f32 = if (context.disabled) 0.4 else 1.0;
        // The theme's painter draws the button chrome and tells us the label color.
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        const surface = context.surface(canvas);
        var label_color: renderer.Color = undefined;
        if (button.icon != null and button.role == .normal and context.theme.painter.glass_surface != null) {
            // Icon-label buttons are the macOS *toolbar pill* style: a freestanding
            // glass capsule rather than the gently-rounded in-content button.
            try context.theme.painter.glass_surface.?(surface, rect, rect.height / 2);
            if (hovered and !context.disabled) {
                try surface.fill(rect, rect.height / 2, context.theme.colors.hover);
            }
            label_color = if (context.disabled) context.theme.colors.tertiary_label else context.theme.colors.label;
        } else {
            label_color = try context.theme.painter.button(surface, rect, button.role, .{
                .disabled = context.disabled,
                .hovered = hovered and !context.disabled,
            });
            // A plain (text-only) button takes a color asked for with `.foreground()`.
            if (button.role == .plain and !context.disabled) {
                if (context.tint) |tint| label_color = tint;
            }
        }
        const pixel_size = context.theme.typography.body.size;
        const label_width = renderer.TextShaper.init(context.cache.face).measureLineWidth(button.label, pixel_size);
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        const color = label_color.multiplyAlpha(context.opacity * dim);
        const icon_width: f32 = if (button.icon != null) mod.ControlMetrics.button_icon_size + mod.ControlMetrics.button_icon_gap else 0;
        const key_size: renderer.Size = if (button.shortcut) |key| Self.keyCapSize(context, key) else .{};
        const key_width: f32 = if (button.shortcut != null) mod.ControlMetrics.button_key_gap + key_size.width else 0;
        const start_x = rect.x + (rect.width - (icon_width + label_width + key_width)) / 2;
        if (button.icon) |icon| {
            if (context.icon_cache) |cache| {
                const icon_box = renderer.Rect{
                    .x = start_x,
                    .y = Self.verticalCenter(rect, mod.ControlMetrics.button_icon_size),
                    .width = mod.ControlMetrics.button_icon_size,
                    .height = mod.ControlMetrics.button_icon_size,
                };
                renderer.TextPainter.shared().drawIcon(canvas, cache, icon.codepoint(), icon_box, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
            }
        }
        const origin = renderer.Point{
            .x = start_x + icon_width,
            .y = rect.y + (rect.height - line_height) / 2,
        };
        context.drawText(canvas, button.label, pixel_size, color, origin) catch |err| log.debug("text not drawn [{t}]", .{err});
        if (button.shortcut) |key| {
            const key_rect = renderer.Rect{
                .x = origin.x + label_width + mod.ControlMetrics.button_key_gap,
                .y = Self.verticalCenter(rect, key_size.height),
                .width = key_size.width,
                .height = key_size.height,
            };
            try Self.paintKeyCap(context, key, key_rect, .{
                .ground = label_color.multiplyAlpha(mod.ControlMetrics.button_key_ground_alpha * context.opacity * dim),
                .border = label_color.multiplyAlpha(mod.ControlMetrics.button_key_border_alpha * context.opacity * dim),
                .text = color.multiplyAlpha(mod.ControlMetrics.button_key_text_alpha),
            }, canvas);
        }
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .callback = button.action }, .disabled = context.disabled });
    }

    /// The glyph cache a key cap's text is drawn in: the medium monospaced
    /// face when the context has a font set, else the context's own.
    ///
    /// - `context`: the context.
    /// - Returns: the cache.
    pub fn keyCapCache(context: *const mod.Context) *renderer.GlyphCache {
        const fonts = context.fonts orelse return context.cache;
        return fonts.cache(.{ .weight = .medium, .mono = true });
    }

    /// The size of a key cap drawn inside a control (a `ButtonKeyed`'s shortcut).
    ///
    /// - `context`: the context.
    /// - `key`: the key's text.
    /// - Returns: its size, padding included.
    pub fn keyCapSize(context: *const mod.Context, key: []const u8) renderer.Size {
        const shaper = renderer.TextShaper.init(Self.keyCapCache(context).face);
        return .{
            .width = shaper.measureLineWidth(key, mod.ControlMetrics.key_cap_text_size) + 2 * mod.ControlMetrics.key_cap_horizontal_padding,
            .height = shaper.lineHeight(mod.ControlMetrics.key_cap_text_size) + 2 * mod.ControlMetrics.key_cap_vertical_padding,
        };
    }

    /// Paints a key cap inside a control as a `KeyCap` view draws one: a
    /// rounded ground, a hairline border (a bevel on a chiseled theme) and
    /// the key's text.
    ///
    /// - `context`: the context.
    /// - `key`: the key's text.
    /// - `rect`: the cap's frame (`keyCapSize`).
    /// - `colors`: its ground, border and text.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintKeyCap(context: *const mod.Context, key: []const u8, rect: renderer.Rect, colors: KeyCapColors, canvas: *renderer.Canvas) !void {
        const radius = context.theme.metrics.radius(mod.ControlMetrics.key_cap_radius);
        try canvas.fillRoundedRect(rect, radius, colors.ground);
        if (context.theme.metrics.chiseled) {
            try context.surface(canvas).bevel(rect, false);
        } else try canvas.strokeRoundedRect(rect, radius, 1, colors.border);
        var key_context = context.*;
        key_context.cache = Self.keyCapCache(context);
        const origin = renderer.Point{
            .x = rect.x + mod.ControlMetrics.key_cap_horizontal_padding,
            .y = rect.y + mod.ControlMetrics.key_cap_vertical_padding,
        };
        key_context.drawText(canvas, key, mod.ControlMetrics.key_cap_text_size, colors.text, origin) catch |err| log.debug("text not drawn [{t}]", .{err});
    }

    /// Paints a switch: its label on the leading edge, the track and knob on the
    /// trailing edge.
    ///
    /// - `context`: the context.
    /// - `toggle`: the switch.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintToggle(context: *const mod.Context, toggle: mod.ToggleData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const pixel_size = context.theme.typography.body.size;
        // label on the leading edge
        if (toggle.label.len > 0) {
            const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
            context.drawText(canvas, toggle.label, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
        // switch on the trailing edge
        const track = renderer.Rect{ .x = rect.maxX() - mod.ControlMetrics.switch_width, .y = Self.verticalCenter(rect, mod.ControlMetrics.switch_height), .width = mod.ControlMetrics.switch_width, .height = mod.ControlMetrics.switch_height };
        const on = toggle.value.get();
        // The view layer owns the knob *geometry*; the theme draws both the track
        // and the sliding thumb so the whole control matches the family.
        const surface = context.surface(canvas);
        try context.theme.painter.switch_track(surface, track, on);
        const knob_radius = mod.ControlMetrics.switch_height / 2 - 1.5;
        const knob_center_x = if (on) track.maxX() - knob_radius - 1.5 else track.x + knob_radius + 1.5;
        const knob_rect = renderer.Rect{ .x = knob_center_x - knob_radius, .y = track.midY() - knob_radius, .width = 2 * knob_radius, .height = 2 * knob_radius };
        try context.theme.painter.switch_knob(surface, knob_rect, on);
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .toggle = toggle.value }, .disabled = context.disabled });
    }

    /// Paints a slider: the theme's groove, fill and handle over the view's geometry.
    ///
    /// - `context`: the context.
    /// - `slider`: the slider.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintSlider(context: *const mod.Context, slider: mod.SliderData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const radius = mod.ControlMetrics.slider_knob_radius;
        const track = renderer.Rect{ .x = rect.x + radius, .y = rect.midY() - mod.ControlMetrics.slider_track_height / 2, .width = rect.width - 2 * radius, .height = mod.ControlMetrics.slider_track_height };
        const denominator = if (slider.max - slider.min == 0) 1 else slider.max - slider.min;
        const fraction = std.math.clamp((slider.value.get() - slider.min) / denominator, 0, 1);
        // The view layer owns the geometry (track + knob square); the theme draws
        // the groove, fill, and handle in its own style.
        const knob_center_x = track.x + track.width * fraction;
        const knob_rect = renderer.Rect{ .x = knob_center_x - radius, .y = rect.midY() - radius, .width = 2 * radius, .height = 2 * radius };
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        try context.theme.painter.slider(context.surface(canvas), track, fraction, knob_rect, .{
            .disabled = context.disabled,
            .hovered = hovered and !context.disabled,
        });
        try context.hit_regions.append(context.arena, .{
            .rect = rect,
            .action = .{ .slider = .{ .binding = slider.value, .min = slider.min, .max = slider.max, .track = track } },
            .disabled = context.disabled,
        });
    }

    /// Paints a stepper: its label, then the native single chevron column.
    ///
    /// - `context`: the context.
    /// - `stepper`: the stepper.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintStepper(context: *const mod.Context, stepper: mod.StepperData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const metrics = context.theme.metrics;
        const pixel_size = context.theme.typography.body.size;
        if (stepper.label.len > 0) {
            const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
            context.drawText(canvas, stepper.label, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
        // The native macOS stepper: one small chevron column — up increments,
        // down decrements, split by an inset horizontal divider.
        const control = renderer.Rect{
            .x = rect.maxX() - mod.ControlMetrics.stepper_width,
            .y = Self.verticalCenter(rect, mod.ControlMetrics.stepper_box_height),
            .width = mod.ControlMetrics.stepper_width,
            .height = mod.ControlMetrics.stepper_box_height,
        };
        const hovered = if (context.hover_point) |point| control.contains(point) else false;
        // The theme draws the box chrome; the divider and chevrons stay here.
        try context.theme.painter.stepper_box(context.surface(canvas), control, .{
            .disabled = context.disabled,
            .hovered = hovered and !context.disabled,
        });
        const half = control.height / 2;
        const up = renderer.Rect{ .x = control.x, .y = control.y, .width = control.width, .height = half };
        const down = renderer.Rect{ .x = control.x, .y = control.y + half, .width = control.width, .height = half };
        try canvas.line(.{ .x = control.x + 4, .y = control.midY() }, .{ .x = control.maxX() - 4, .y = control.midY() }, metrics.hairline, context.theme.colors.separator.multiplyAlpha(opacity));
        const mark_color = context.foreground.multiplyAlpha(opacity);
        const chevron_half_width: f32 = 3.5;
        try canvas.line(.{ .x = up.midX() - chevron_half_width, .y = up.midY() + 1.5 }, .{ .x = up.midX(), .y = up.midY() - 2 }, 1.5, mark_color);
        try canvas.line(.{ .x = up.midX(), .y = up.midY() - 2 }, .{ .x = up.midX() + chevron_half_width, .y = up.midY() + 1.5 }, 1.5, mark_color);
        try canvas.line(.{ .x = down.midX() - chevron_half_width, .y = down.midY() - 1.5 }, .{ .x = down.midX(), .y = down.midY() + 2 }, 1.5, mark_color);
        try canvas.line(.{ .x = down.midX(), .y = down.midY() + 2 }, .{ .x = down.midX() + chevron_half_width, .y = down.midY() - 1.5 }, 1.5, mark_color);
        try context.hit_regions.append(context.arena, .{ .rect = up, .action = .{ .step = .{ .binding = stepper.value, .delta = stepper.step, .min = stepper.min, .max = stepper.max } }, .disabled = context.disabled });
        try context.hit_regions.append(context.arena, .{ .rect = down, .action = .{ .step = .{ .binding = stepper.value, .delta = -stepper.step, .min = stepper.min, .max = stepper.max } }, .disabled = context.disabled });
    }

    /// Paints a progress bar.
    ///
    /// - `context`: the context.
    /// - `progress`: the progress bar.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintProgress(context: *const mod.Context, progress: mod.ProgressData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const bar = renderer.Rect{ .x = rect.x, .y = rect.midY() - mod.ControlMetrics.progress_height / 2, .width = rect.width, .height = mod.ControlMetrics.progress_height };
        try context.theme.painter.progress(context.surface(canvas), bar, progress.value);
    }

    /// Paints a label: a color swatch, then the title.
    ///
    /// - `context`: the context.
    /// - `label`: the label.
    /// - `view`: the label's view (its font modifiers).
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintLabel(context: *const mod.Context, label: mod.LabelData, view: mod.View, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const pixel_size = context.resolvedFontSize(view);
        const swatch = renderer.Rect{ .x = rect.x, .y = Self.verticalCenter(rect, mod.ControlMetrics.label_icon_size), .width = mod.ControlMetrics.label_icon_size, .height = mod.ControlMetrics.label_icon_size };
        try canvas.fillRoundedRect(swatch, 3, label.symbol_color.multiplyAlpha(opacity));
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        context.drawText(canvas, label.title, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x + mod.ControlMetrics.label_icon_size + mod.ControlMetrics.label_gap, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
    }

    /// Paints an icon glyph, centered in its square; nothing without an icon cache.
    ///
    /// - `context`: the context.
    /// - `icon`: the icon.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintIcon(context: *const mod.Context, icon: mod.IconData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const cache = context.icon_cache orelse return; // no icon font wired -> draw nothing
        const color = (icon.color orelse context.foreground).multiplyAlpha(context.opacity);
        // The glyph is centered in its laid-out square (`rect`); `drawIcon` sizes it
        // to the smaller side and handles the HiDPI coverage trick.
        renderer.TextPainter.shared().drawIcon(canvas, cache, icon.icon.codepoint(), rect, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
    }

    /// Paints an icon button: neutral button chrome with the glyph as its label.
    ///
    /// - `context`: the context.
    /// - `icon_button`: the button.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintIconButton(context: *const mod.Context, icon_button: mod.IconButtonData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        // Icon buttons get the same neutral chrome as ordinary buttons (native
        // glass icon buttons are small capsules), with the glyph as the label.
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        const label_color = try context.theme.painter.button(context.surface(canvas), rect, .normal, .{
            .disabled = context.disabled,
            .hovered = hovered and !context.disabled,
        });
        const dim: f32 = if (context.disabled) 0.4 else 1;
        const color = label_color.multiplyAlpha(context.opacity * dim);
        const box = rect.insetBy(mod.ControlMetrics.icon_button_padding_x, mod.ControlMetrics.icon_button_padding_y);
        renderer.TextPainter.shared().drawIcon(canvas, context.icon_cache orelse return, icon_button.icon.codepoint(), box, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .callback = icon_button.action }, .disabled = context.disabled });
    }

    /// Paints a segmented picker: the theme's track, the selected chip, and a
    /// tap region per segment.
    ///
    /// - `context`: the context.
    /// - `picker`: the picker.
    /// - `rect`: its frame.
    /// - `canvas`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintPicker(context: *const mod.Context, picker: mod.PickerData, rect: renderer.Rect, canvas: *renderer.Canvas) !void {
        const opacity = context.opacity;
        const count = picker.options.len;
        if (count == 0) return;
        const surface = context.surface(canvas);
        // The theme draws the segmented track and the selected-segment chip.
        try context.theme.painter.segmented_track(surface, rect);
        const segment_width = rect.width / @as(f32, @floatFromInt(count));
        const pixel_size = context.theme.typography.body.size;
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        const selected = picker.selection.get();
        for (picker.options, 0..) |option, index| {
            const segment = renderer.Rect{ .x = rect.x + @as(f32, @floatFromInt(index)) * segment_width, .y = rect.y, .width = segment_width, .height = rect.height };
            const is_selected = @as(i64, @intCast(index)) == selected;
            // The theme draws the selection chip and dictates its label color (an
            // accent-filled chip needs `on_accent` text, a pale chip keeps `label`).
            // Native unselected segment labels stay in the primary label color.
            const segment_text = if (is_selected)
                try context.theme.painter.segmented_selection(surface, segment)
            else
                context.theme.colors.label;
            const text_width = renderer.TextShaper.init(context.cache.face).measureLineWidth(option, pixel_size);
            context.drawText(canvas, option, pixel_size, segment_text.multiplyAlpha(opacity), .{
                .x = segment.x + (segment.width - text_width) / 2,
                .y = Self.verticalCenter(segment, line_height),
            }) catch |err| log.debug("text not drawn [{t}]", .{err});
            try context.hit_regions.append(context.arena, .{
                .rect = segment,
                .action = .{ .select = .{ .binding = picker.selection, .value = @intCast(index) } },
                .disabled = context.disabled,
            });
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
