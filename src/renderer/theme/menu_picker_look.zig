//! How a theme family draws a menu-style picker (SwiftUI's
//! `.pickerStyle(.menu)`) and opens its menu, after its platform: macOS's
//! pop-up button, KDE Plasma's combo box, the Windows drop-down list, and
//! Material's exposed dropdown menu.

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_picker_look);

/// What a menu-style picker is drawn as.
pub const MenuPickerChrome = enum {
    const Self = @This();

    /// A push button (macOS, KDE Plasma, Windows 10).
    button,
    /// A field (Material's outlined exposed dropdown).
    field,
    /// A sunken field with its own button at the trailing edge (Windows 2000).
    fieldWithButton,
};

/// The mark at a menu-style picker's trailing edge.
pub const MenuPickerIndicator = enum {
    const Self = @This();

    /// Up and down chevrons (macOS).
    chevronsUpDown,
    /// A down chevron (Windows 10, KDE Plasma).
    chevronDown,
    /// A solid down triangle (Windows 2000, Material).
    triangle,
};

/// How a menu-style picker looks and opens in a theme family.
pub const MenuPickerLook = struct {
    const Self = @This();

    /// macOS's pop-up button: the menu over the button, the chosen option
    /// checked and over the title.
    pub const macos: Self = .{};
    /// KDE Plasma's combo box, as Qt's style lays its popup over the box.
    pub const kde: Self = .{ .indicator = .chevronDown };
    /// The Windows 10 drop-down list: a list below the box, the chosen
    /// option highlighted.
    pub const windows10: Self = .{ .indicator = .chevronDown, .menu_over_control = false, .checks_choice = false };
    /// The Windows 2000 drop-down list: a sunken box with its ▼ button.
    pub const win2000: Self = .{ .chrome = .fieldWithButton, .indicator = .triangle, .menu_over_control = false, .checks_choice = false };
    /// Material's exposed dropdown menu: an outlined field, the menu below it.
    pub const material: Self = .{ .chrome = .field, .indicator = .triangle, .menu_over_control = false, .checks_choice = false };

    /// What the picker is drawn as.
    chrome: MenuPickerChrome = .button,
    /// The mark at its trailing edge.
    indicator: MenuPickerIndicator = .chevronsUpDown,
    /// The menu opens over the picker, the chosen option over its title;
    /// else below it, at least as wide as it.
    menu_over_control: bool = true,
    /// The chosen option is marked with a check; else it is highlighted.
    checks_choice: bool = true,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "each platform's menu picker opens as its platform does" {
    try std.testing.expect(MenuPickerLook.macos.menu_over_control and MenuPickerLook.macos.checks_choice);
    try std.testing.expect(MenuPickerLook.kde.menu_over_control);
    try std.testing.expect(!MenuPickerLook.windows10.menu_over_control and !MenuPickerLook.windows10.checks_choice);
    try std.testing.expectEqual(MenuPickerChrome.fieldWithButton, MenuPickerLook.win2000.chrome);
    try std.testing.expectEqual(MenuPickerIndicator.triangle, MenuPickerLook.material.indicator);
}
