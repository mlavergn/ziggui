//! Paints the built-in controls: buttons, switches, sliders, steppers,
//! progress bars, labels, icons, and pickers segmented or as pop-up menus.

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

    /// The shade laid over a glass pill button while it is pressed: darker in
    /// either scheme, as `MacosTheme`'s clear glass does.
    const pressed_shade = renderer.Color.black.withAlpha(0.12);

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
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintButton(context: *const mod.Context, button: mod.ButtonData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const dim: f32 = if (context.disabled) 0.4 else 1.0;
        // The theme's painter draws the button chrome and tells us the label color.
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        const pressed = Self.isPressed(context, rect);
        const surface = context.surface(display_list);
        var label_color: renderer.Color = undefined;
        if (button.icon != null and button.role == .normal and context.theme.painter.glass_surface != null) {
            // Icon-label buttons are the macOS *toolbar pill* style: a freestanding
            // glass capsule rather than the gently-rounded in-content button.
            try context.theme.painter.glass_surface.?(surface, rect, rect.height / 2);
            if (pressed) {
                try surface.fill(rect, rect.height / 2, pressed_shade);
            } else if (hovered and !context.disabled) {
                try surface.fill(rect, rect.height / 2, context.theme.colors.hover);
            }
            label_color = if (context.disabled) context.theme.colors.tertiary_label else context.theme.colors.label;
        } else {
            label_color = try context.theme.painter.button(surface, rect, button.role, .{
                .disabled = context.disabled,
                .hovered = hovered and !context.disabled,
                .pressed = pressed,
            });
            // A plain (text-only) button takes a color asked for with `.foregroundStyle()`.
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
                renderer.TextPainter.shared().drawIcon(display_list, cache, icon.codepoint(), icon_box, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
            }
        }
        const origin = renderer.Point{
            .x = start_x + icon_width,
            .y = rect.y + (rect.height - line_height) / 2,
        };
        context.drawText(display_list, button.label, pixel_size, color, origin) catch |err| log.debug("text not drawn [{t}]", .{err});
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
            }, display_list);
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
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintKeyCap(context: *const mod.Context, key: []const u8, rect: renderer.Rect, colors: KeyCapColors, display_list: *renderer.DisplayList) !void {
        const radius = context.theme.metrics.radius(mod.ControlMetrics.key_cap_radius);
        try display_list.fillRoundedRect(rect, radius, colors.ground);
        if (context.theme.metrics.chiseled) {
            try context.surface(display_list).bevel(rect, false);
        } else try display_list.strokeRoundedRect(rect, radius, 1, colors.border);
        var key_context = context.*;
        key_context.cache = Self.keyCapCache(context);
        const origin = renderer.Point{
            .x = rect.x + mod.ControlMetrics.key_cap_horizontal_padding,
            .y = rect.y + mod.ControlMetrics.key_cap_vertical_padding,
        };
        key_context.drawText(display_list, key, mod.ControlMetrics.key_cap_text_size, colors.text, origin) catch |err| log.debug("text not drawn [{t}]", .{err});
    }

    /// Paints a switch: its label on the leading edge, the track and knob on the
    /// trailing edge.
    ///
    /// - `context`: the context.
    /// - `toggle`: the switch.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintToggle(context: *const mod.Context, toggle: mod.ToggleData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        if (context.resolvedToggleStyle() == .checkbox) return Self.paintCheckbox(context, toggle, rect, display_list);
        const opacity = context.opacity;
        const pixel_size = context.theme.typography.body.size;
        // label on the leading edge
        if (toggle.label.len > 0) {
            const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
            context.drawText(display_list, toggle.label, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
        // switch on the trailing edge
        const track = renderer.Rect{ .x = rect.maxX() - mod.ControlMetrics.switch_width, .y = Self.verticalCenter(rect, mod.ControlMetrics.switch_height), .width = mod.ControlMetrics.switch_width, .height = mod.ControlMetrics.switch_height };
        const on = toggle.value.get();
        // The view layer owns the knob *geometry*; the theme draws both the track
        // and the sliding thumb so the whole control matches the family.
        const surface = context.surface(display_list);
        try context.theme.painter.switch_track(surface, track, on);
        const knob_radius = mod.ControlMetrics.switch_height / 2 - 1.5;
        const knob_center_x = if (on) track.maxX() - knob_radius - 1.5 else track.x + knob_radius + 1.5;
        const knob_rect = renderer.Rect{ .x = knob_center_x - knob_radius, .y = track.midY() - knob_radius, .width = 2 * knob_radius, .height = 2 * knob_radius };
        try context.theme.painter.switch_knob(surface, knob_rect, on);
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .toggle = toggle.value }, .disabled = context.disabled });
    }

    /// Paints a slider: the theme's groove, fill and handle over the view's
    /// geometry; with a `.foregroundStyle` color, flat in that color instead
    /// (`paintTintedSlider`).
    ///
    /// - `context`: the context.
    /// - `slider`: the slider.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintSlider(context: *const mod.Context, slider: mod.SliderData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const track = renderer.Rect{ .x = rect.x + mod.ControlMetrics.slider_knob_radius, .y = rect.midY() - mod.ControlMetrics.slider_track_height / 2, .width = rect.width - 2 * mod.ControlMetrics.slider_knob_radius, .height = mod.ControlMetrics.slider_track_height };
        const denominator = if (slider.max - slider.min == 0) 1 else slider.max - slider.min;
        const fraction = std.math.clamp((slider.value.get() - slider.min) / denominator, 0, 1);
        // The view layer owns the geometry (track + knob square); the theme draws
        // the groove, fill, and handle in its own style.
        const knob_center_x = track.x + track.width * fraction;
        const knob_rect = renderer.Rect{ .x = knob_center_x - mod.ControlMetrics.slider_knob_radius, .y = rect.midY() - mod.ControlMetrics.slider_knob_radius, .width = 2 * mod.ControlMetrics.slider_knob_radius, .height = 2 * mod.ControlMetrics.slider_knob_radius };
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        if (context.tint) |tint| {
            try Self.paintTintedSlider(context.surface(display_list), track, fraction, knob_rect, if (context.disabled) tint.multiplyAlpha(0.4) else tint);
        } else {
            try context.theme.painter.slider(context.surface(display_list), track, fraction, knob_rect, .{
                .disabled = context.disabled,
                .hovered = hovered and !context.disabled,
            });
        }
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
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintStepper(context: *const mod.Context, stepper: mod.StepperData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const opacity = context.opacity;
        const metrics = context.theme.metrics;
        const pixel_size = context.theme.typography.body.size;
        if (stepper.label.len > 0) {
            const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
            context.drawText(display_list, stepper.label, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
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
        try context.theme.painter.stepper_box(context.surface(display_list), control, .{
            .disabled = context.disabled,
            .hovered = hovered and !context.disabled,
        });
        const half = control.height / 2;
        const up = renderer.Rect{ .x = control.x, .y = control.y, .width = control.width, .height = half };
        const down = renderer.Rect{ .x = control.x, .y = control.y + half, .width = control.width, .height = half };
        try display_list.line(.{ .x = control.x + 4, .y = control.midY() }, .{ .x = control.maxX() - 4, .y = control.midY() }, metrics.hairline, context.theme.colors.separator.multiplyAlpha(opacity));
        const mark_color = context.foreground.multiplyAlpha(opacity);
        const chevron_half_width: f32 = 3.5;
        try display_list.line(.{ .x = up.midX() - chevron_half_width, .y = up.midY() + 1.5 }, .{ .x = up.midX(), .y = up.midY() - 2 }, 1.5, mark_color);
        try display_list.line(.{ .x = up.midX(), .y = up.midY() - 2 }, .{ .x = up.midX() + chevron_half_width, .y = up.midY() + 1.5 }, 1.5, mark_color);
        try display_list.line(.{ .x = down.midX() - chevron_half_width, .y = down.midY() - 1.5 }, .{ .x = down.midX(), .y = down.midY() + 2 }, 1.5, mark_color);
        try display_list.line(.{ .x = down.midX(), .y = down.midY() + 2 }, .{ .x = down.midX() + chevron_half_width, .y = down.midY() - 1.5 }, 1.5, mark_color);
        try context.hit_regions.append(context.arena, .{ .rect = up, .action = .{ .step = .{ .binding = stepper.value, .delta = stepper.step, .min = stepper.min, .max = stepper.max } }, .disabled = context.disabled });
        try context.hit_regions.append(context.arena, .{ .rect = down, .action = .{ .step = .{ .binding = stepper.value, .delta = -stepper.step, .min = stepper.min, .max = stepper.max } }, .disabled = context.disabled });
    }

    /// Paints a progress bar.
    ///
    /// - `context`: the context.
    /// - `progress`: the progress bar.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintProgress(context: *const mod.Context, progress: mod.ProgressData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const bar = renderer.Rect{ .x = rect.x, .y = rect.midY() - mod.ControlMetrics.progress_height / 2, .width = rect.width, .height = mod.ControlMetrics.progress_height };
        try context.theme.painter.progress(context.surface(display_list), bar, progress.value);
    }

    /// Paints a label: a color swatch, then the title.
    ///
    /// - `context`: the context.
    /// - `label`: the label.
    /// - `view`: the label's view (its font modifiers).
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintLabel(context: *const mod.Context, label: mod.LabelData, view: mod.View, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const opacity = context.opacity;
        const pixel_size = context.resolvedFontSize(view);
        const swatch = renderer.Rect{ .x = rect.x, .y = Self.verticalCenter(rect, mod.ControlMetrics.label_icon_size), .width = mod.ControlMetrics.label_icon_size, .height = mod.ControlMetrics.label_icon_size };
        try display_list.fillRoundedRect(swatch, 3, label.symbol_color.multiplyAlpha(opacity));
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        context.drawText(display_list, label.title, pixel_size, context.foreground.multiplyAlpha(opacity), .{ .x = rect.x + mod.ControlMetrics.label_icon_size + mod.ControlMetrics.label_gap, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
    }

    /// Paints an icon glyph, centered in its square; nothing without an icon cache.
    ///
    /// - `context`: the context.
    /// - `icon`: the icon.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintIcon(context: *const mod.Context, icon: mod.IconData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const cache = context.icon_cache orelse return; // no icon font wired -> draw nothing
        const color = (icon.color orelse context.foreground).multiplyAlpha(context.opacity);
        // The glyph is centered in its laid-out square (`rect`); `drawIcon` sizes it
        // to the smaller side and handles the HiDPI coverage trick.
        renderer.TextPainter.shared().drawIcon(display_list, cache, icon.icon.codepoint(), rect, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
    }

    /// Paints an icon button: neutral button chrome with the glyph as its label.
    ///
    /// - `context`: the context.
    /// - `icon_button`: the button.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintIconButton(context: *const mod.Context, icon_button: mod.IconButtonData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        // Icon buttons get the same neutral chrome as ordinary buttons (native
        // glass icon buttons are small capsules), with the glyph as the label.
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        const label_color = try context.theme.painter.button(context.surface(display_list), rect, .normal, .{
            .disabled = context.disabled,
            .hovered = hovered and !context.disabled,
            .pressed = Self.isPressed(context, rect),
        });
        const dim: f32 = if (context.disabled) 0.4 else 1;
        const color = label_color.multiplyAlpha(context.opacity * dim);
        // The glyph at its own size, centred: the button may be taller than it
        // and its padding (the theme's control height).
        const box = renderer.Rect{ .x = rect.x + (rect.width - icon_button.size) / 2, .y = rect.y + (rect.height - icon_button.size) / 2, .width = icon_button.size, .height = icon_button.size };
        renderer.TextPainter.shared().drawIcon(display_list, context.icon_cache orelse return, icon_button.icon.codepoint(), box, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .callback = icon_button.action }, .disabled = context.disabled });
    }

    /// Paints a menu-style picker as its theme family draws one (the theme's
    /// `menu_picker`): a button or a field showing the chosen option, the
    /// family's mark at the trailing edge; a tap opens its menu
    /// (`PickerMenu`), which it presents while open.
    ///
    /// - `context`: the context.
    /// - `picker`: the picker.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintMenuPicker(context: *const mod.Context, picker: mod.PickerData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const look = context.theme.menu_picker;
        const surface = context.surface(display_list);
        const hovered = if (context.hover_point) |point| rect.contains(point) else false;
        const state: renderer.ControlState = .{ .disabled = context.disabled, .hovered = hovered and !context.disabled, .pressed = Self.isPressed(context, rect) };
        const dim: f32 = if (context.disabled) 0.4 else 1;
        var label_color = context.theme.colors.label;
        var mark_color = context.theme.colors.label;
        const mark_box = Self.menuPickerMark(look, rect);
        switch (look.chrome) {
            .button => {
                label_color = try context.theme.painter.button(surface, rect, .normal, state);
                mark_color = label_color;
            },
            .field => try context.theme.painter.field(surface, rect, context.theme.metrics.control_corner_radius, state),
            .fieldWithButton => {
                try context.theme.painter.field(surface, rect, context.theme.metrics.control_corner_radius, .{ .disabled = context.disabled });
                mark_color = try context.theme.painter.button(surface, mark_box, .normal, state);
            },
        }
        const pixel_size = context.theme.typography.body.size;
        const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(pixel_size);
        // With nothing chosen, the prompt (if any), dimmed as a field's placeholder.
        const chosen = picker.chosenTitle();
        const title = chosen orelse picker.prompt;
        if (chosen == null) label_color = context.theme.colors.secondary_label;
        const title_x = rect.x + mod.ControlMetrics.control_horizontal_padding;
        const room = mark_box.x - mod.ControlMetrics.popup_chevron_gap - title_x;
        const shown = try context.truncateToWidth(title, pixel_size, room);
        context.drawText(display_list, shown, pixel_size, label_color.multiplyAlpha(context.opacity * dim), .{ .x = title_x, .y = Self.verticalCenter(rect, line_height) }) catch |err| log.debug("text not drawn [{t}]", .{err});
        try Self.paintMenuPickerMark(context, look.indicator, mark_box, mark_color.multiplyAlpha(context.opacity * dim), display_list);
        const ordinal = mod.PickerMenu.shared().nextOrdinal();
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .callback = try mod.PickerMenu.opener(context, picker.selection, ordinal) }, .disabled = context.disabled });
        try mod.PickerMenu.shared().present(context, picker, rect, ordinal);
    }

    /// Where a menu-style picker's trailing mark goes: the sunken field's
    /// own button (Windows 2000), else a square inset from the trailing edge.
    ///
    /// - `look`: the theme family's menu picker.
    /// - `rect`: the picker's frame.
    /// - Returns: the mark's box.
    pub fn menuPickerMark(look: renderer.MenuPickerLook, rect: renderer.Rect) renderer.Rect {
        if (look.chrome == .fieldWithButton) {
            const inset: f32 = 2;
            return .{ .x = rect.maxX() - inset - mod.ControlMetrics.popup_field_button_width, .y = rect.y + inset, .width = mod.ControlMetrics.popup_field_button_width, .height = @max(0, rect.height - 2 * inset) };
        }
        return .{ .x = rect.maxX() - mod.ControlMetrics.popup_chevron_inset - mod.ControlMetrics.popup_chevron_size, .y = Self.verticalCenter(rect, mod.ControlMetrics.popup_chevron_size), .width = mod.ControlMetrics.popup_chevron_size, .height = mod.ControlMetrics.popup_chevron_size };
    }

    /// Paints a segmented picker, its segments in proportion to their labels
    /// (as macOS sizes them to their content): the theme's track, the selected
    /// chip, and a tap region per segment.
    ///
    /// - `context`: the context.
    /// - `picker`: the picker.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintPicker(context: *const mod.Context, picker: mod.PickerData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const opacity = context.opacity;
        const count = picker.options.len;
        if (count == 0) return;
        const surface = context.surface(display_list);
        // The theme draws the segmented track and the selected-segment chip.
        try context.theme.painter.segmented_track(surface, rect);
        const pixel_size = context.theme.typography.body.size;
        const shaper = renderer.TextShaper.init(context.cache.face);
        const line_height = shaper.lineHeight(pixel_size);
        // Segments in proportion to their labels (with the padding), as macOS
        // sizes them to their content: the width measured, or more when stretched.
        const natural = Self.segmentsWidth(context, picker.options);
        const scale = if (natural > 0) rect.width / natural else 0;
        const selected = picker.selection.get();
        var x = rect.x;
        for (picker.options, 0..) |option, index| {
            const text_width = shaper.measureLineWidth(option, pixel_size);
            const segment = renderer.Rect{ .x = x, .y = rect.y, .width = Self.segmentWidth(context, option) * scale, .height = rect.height };
            x += segment.width;
            const is_selected = @as(i64, @intCast(index)) == selected;
            // The theme draws the selection chip and dictates its label color (an
            // accent-filled chip needs `on_accent` text, a pale chip keeps `label`).
            // Native unselected segment labels stay in the primary label color.
            const segment_text = if (is_selected)
                try context.theme.painter.segmented_selection(surface, segment)
            else
                context.theme.colors.label;
            context.drawText(display_list, option, pixel_size, segment_text.multiplyAlpha(opacity), .{
                .x = segment.x + (segment.width - text_width) / 2,
                .y = Self.verticalCenter(segment, line_height),
            }) catch |err| log.debug("text not drawn [{t}]", .{err});
            try context.hit_regions.append(context.arena, .{
                .rect = segment,
                .action = .{ .select = .{ .binding = picker.selection, .value = @intCast(index) } },
                .disabled = context.disabled,
            });
            // Each segment a choice of the group `ViewPainter` emitted for the
            // picker, named by its own title (the picker's label is the group's).
            try context.emitAccessibilityPart(segment, .radioButton, option, is_selected);
        }
    }

    /// A segmented picker's segment at its natural width: its label in the
    /// theme's body text and `ControlMetrics.picker_segment_padding` either side.
    ///
    /// - `context`: the context.
    /// - `option`: the segment's label.
    /// - Returns: the width, in points.
    pub fn segmentWidth(context: *const mod.Context, option: []const u8) f32 {
        const width = renderer.TextShaper.init(context.cache.face).measureLineWidth(option, context.theme.typography.body.size);
        return width + 2 * mod.ControlMetrics.picker_segment_padding;
    }

    /// A segmented picker's natural width: its segments' natural widths summed.
    ///
    /// - `context`: the context.
    /// - `options`: the segments' labels.
    /// - Returns: the width, in points.
    pub fn segmentsWidth(context: *const mod.Context, options: []const []const u8) f32 {
        var width: f32 = 0;
        for (options) |option| width += Self.segmentWidth(context, option);
        return width;
    }

    /// Paints a menu-style picker's mark, centered in `box`: a chevron icon,
    /// or a solid down triangle drawn as narrowing half-point rows (as
    /// Windows 2000 draws its pixel triangle).
    ///
    /// - `context`: the context.
    /// - `indicator`: the mark.
    /// - `box`: where it goes.
    /// - `color`: its color.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintMenuPickerMark(context: *const mod.Context, indicator: renderer.MenuPickerIndicator, box: renderer.Rect, color: renderer.Color, display_list: *renderer.DisplayList) !void {
        const icon: renderer.Icon = switch (indicator) {
            .chevronsUpDown => .chevronsUpDown,
            .chevronDown => .chevronDown,
            .triangle => {
                const row: f32 = 0.5;
                const rows: usize = @intFromFloat(mod.ControlMetrics.popup_triangle_width / 2 / row);
                const top = box.y + (box.height - mod.ControlMetrics.popup_triangle_width / 2) / 2;
                const center_x = box.x + box.width / 2;
                for (0..rows) |index| {
                    const row_width = mod.ControlMetrics.popup_triangle_width * (1 - @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(rows)));
                    try display_list.fillRect(.{ .x = center_x - row_width / 2, .y = top + @as(f32, @floatFromInt(index)) * row, .width = row_width, .height = row }, color);
                }
                return;
            },
        };
        const icon_box = renderer.Rect{ .x = box.x + (box.width - mod.ControlMetrics.popup_chevron_size) / 2, .y = box.y + (box.height - mod.ControlMetrics.popup_chevron_size) / 2, .width = mod.ControlMetrics.popup_chevron_size, .height = mod.ControlMetrics.popup_chevron_size };
        renderer.TextPainter.shared().drawIcon(display_list, context.icon_cache orelse return, icon.codepoint(), icon_box, context.scale, color) catch |err| log.debug("icon not drawn [{t}]", .{err});
    }

    /// Paints a checkbox toggle: a box on the leading edge (the accent with a
    /// check mark while on, the control's ground with its border while off,
    /// or an explicit `CheckboxStyle`'s through `paintStyledBox`), then the
    /// label (a `.compact` one smaller, in the footnote font and the secondary
    /// label color while off). A tap anywhere on it flips it.
    ///
    /// - `context`: the context.
    /// - `toggle`: the toggle.
    /// - `rect`: its frame.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintCheckbox(context: *const mod.Context, toggle: mod.ToggleData, rect: renderer.Rect, display_list: *renderer.DisplayList) !void {
        const colors = &context.theme.colors;
        const dim: f32 = if (context.disabled) 0.4 else 1;
        const opacity = context.opacity * dim;
        const on = toggle.value.get();
        const measures = mod.ControlMetrics.checkbox(context.checkbox_style, &context.theme.typography);
        const box = renderer.Rect{ .x = rect.x, .y = Self.verticalCenter(rect, measures.side), .width = measures.side, .height = measures.side };
        if (context.checkbox_style == .automatic) {
            const radius = context.theme.metrics.radius(mod.ControlMetrics.checkbox_radius);
            const surface = context.surface(display_list);
            if (on) {
                try surface.fill(box, radius, colors.accent.multiplyAlpha(dim));
                Self.paintCheck(context, box, colors.on_accent.multiplyAlpha(opacity), display_list);
            } else {
                try surface.fill(box, radius, colors.control_background.multiplyAlpha(dim));
                try surface.stroke(box, radius, context.theme.metrics.hairline, colors.control_border.multiplyAlpha(dim));
            }
        } else try Self.paintStyledBox(context, box, on, opacity, display_list);
        if (toggle.label.len > 0) {
            const line_height = renderer.TextShaper.init(context.cache.face).lineHeight(measures.label_size);
            const origin = renderer.Point{ .x = box.maxX() + measures.gap, .y = Self.verticalCenter(rect, line_height) };
            const label_color = if (context.checkbox_style == .compact and !on) colors.secondary_label else context.foreground;
            context.drawText(display_list, toggle.label, measures.label_size, label_color.multiplyAlpha(opacity), origin) catch |err| log.debug("text not drawn [{t}]", .{err});
        }
        try context.hit_regions.append(context.arena, .{ .rect = rect, .action = .{ .toggle = toggle.value }, .disabled = context.disabled });
    }

    /// Paints a checkbox's box in one of the explicit `CheckboxStyle`s, the
    /// same under every theme family: outlined, the outline inside the box;
    /// `.rounded` and `.compact` keep it empty with the check in the outline's
    /// color (`.compact`'s the accent while on and the secondary label color
    /// while off), `.square` and `.circular` fill it while on with the check
    /// in the accent's text color.
    ///
    /// - `context`: the context, with the style and the toggle's own tint.
    /// - `box`: the box's frame.
    /// - `on`: whether the toggle is on.
    /// - `opacity`: the opacity it draws at (dimmed while disabled).
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintStyledBox(context: *const mod.Context, box: renderer.Rect, on: bool, opacity: f32, display_list: *renderer.DisplayList) !void {
        const colors = &context.theme.colors;
        const style = context.checkbox_style;
        const color = (switch (style) {
            .rounded => context.tint orelse context.foreground,
            .compact => if (on) context.tint orelse colors.accent else colors.secondary_label,
            .automatic, .square, .circular => context.tint orelse colors.accent,
        }).multiplyAlpha(opacity);
        const radius: f32 = switch (style) {
            .automatic, .rounded => mod.ControlMetrics.checkbox_radius,
            .compact => mod.ControlMetrics.compact_checkbox_radius,
            .square => 0,
            .circular => box.width / 2,
        };
        const line_width = mod.ControlMetrics.checkbox_line_width;
        if (on and (style == .square or style == .circular)) {
            try display_list.fillRoundedRect(box, radius, color);
            try Self.paintBoldCheck(box, colors.on_accent.multiplyAlpha(opacity), display_list);
            return;
        }
        const half = line_width / 2;
        try display_list.strokeRoundedRect(box.insetBy(half, half), @max(radius - half, 0), line_width, color);
        if (on) try Self.paintBoldCheck(box, color, display_list);
    }

    /// Paints the explicit `CheckboxStyle`s' check mark: two round-capped
    /// strokes across most of the box, bolder than the icon's at this size.
    ///
    /// - `box`: the box's frame.
    /// - `color`: the check's color.
    /// - `display_list`: where it is painted.
    /// - Returns: nothing; propagates allocation failure.
    fn paintBoldCheck(box: renderer.Rect, color: renderer.Color, display_list: *renderer.DisplayList) !void {
        const side = box.width;
        const start = renderer.Point{ .x = box.x + side * 0.27, .y = box.y + side * 0.52 };
        const corner = renderer.Point{ .x = box.x + side * 0.43, .y = box.y + side * 0.68 };
        const end = renderer.Point{ .x = box.x + side * 0.74, .y = box.y + side * 0.34 };
        const width = side * mod.ControlMetrics.checkbox_check_weight;
        try display_list.line(start, corner, width, color);
        try display_list.line(corner, end, width, color);
    }

    /// Paints a checkbox's check mark, inset in its box.
    ///
    /// - `context`: the context, with the icon glyphs.
    /// - `box`: the box's frame.
    /// - `color`: the check's color.
    /// - `display_list`: where it is painted.
    fn paintCheck(context: *const mod.Context, box: renderer.Rect, color: renderer.Color, display_list: *renderer.DisplayList) void {
        const cache = context.icon_cache orelse return;
        renderer.TextPainter.shared().drawIcon(display_list, cache, renderer.Icon.check.codepoint(), box.insetBy(2, 2), context.scale, color) catch |err| log.debug("check not drawn [{t}]", .{err});
    }

    /// Paints a slider flat in one color, as media controls draw theirs over
    /// a picture: the groove in the color at a third, the filled part and the
    /// knob in the color, the knob on a soft shadow. It reads on any ground,
    /// which the theme's slider (made for the window's) does not.
    ///
    /// - `surface`: where it is painted.
    /// - `track`: the groove's frame.
    /// - `fraction`: how much of the groove is filled, 0 to 1.
    /// - `knob`: the knob's frame.
    /// - `color`: the slider's color.
    /// - Returns: nothing; propagates allocation failure.
    fn paintTintedSlider(surface: renderer.Surface, track: renderer.Rect, fraction: f32, knob: renderer.Rect, color: renderer.Color) !void {
        const track_radius = track.height / 2;
        try surface.fill(track, track_radius, color.multiplyAlpha(0.35));
        try surface.fill(.{ .x = track.x, .y = track.y, .width = track.width * fraction, .height = track.height }, track_radius, color);
        const radius = knob.width / 2;
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() + 0.75 }, radius, renderer.Color.black.withAlpha(0.25 * color.a));
        try surface.fillCircle(.{ .x = knob.midX(), .y = knob.midY() }, radius, color);
    }

    /// Whether a control draws pressed: enabled, with the primary button held
    /// after going down inside it, and the pointer still over it.
    ///
    /// - `context`: the context, with its press and hover points.
    /// - `rect`: the control's frame.
    /// - Returns: true while it is held.
    fn isPressed(context: *const mod.Context, rect: renderer.Rect) bool {
        if (context.disabled) return false;
        const press = context.press_point orelse return false;
        const hover = context.hover_point orelse return false;
        return rect.contains(press) and rect.contains(hover);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}
