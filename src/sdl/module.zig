//! The SDL runtime barrel: the `sdl` build module, which the app `ziggui`
//! (`linkApp`) imports and re-exports. It opens the window, drives the event
//! loop, presents frames on the GPU or the software rasterizer, and reaches
//! the OS for menus, the tray, the clipboard and file dialogs.
//!
//! Only application executables compile this module; the core library and
//! its tests never link SDL, so `zig build test` stays headless.

const std = @import("std");
const log = std.log.scoped(.ziggui_sdl_module);
const builtin = @import("builtin");

/// The OS this runtime is built for (a compile-time invariant).
pub const os_tag = builtin.os.tag;

/// SDL3's C API, translated from `c.h` (keycodes, modifier masks, events).
pub const sdl_c = @import("sdl_c");

/// The running app: its window, loop flag, handlers, and `run`.
pub const App = @import("app.zig").App;
/// How `App.run` opens the window and renders.
pub const AppConfig = @import("app_config.zig").AppConfig;
/// Why the runtime could not start.
pub const AppError = @import("app_error.zig").AppError;
/// A window or tray icon as RGBA8 pixels.
pub const WindowIcon = @import("window_icon.zig").WindowIcon;
/// The event loop `App.run` drives for one app state type.
pub const EventLoop = @import("event_loop.zig").EventLoop;
/// A mouse event in the main window, in points.
pub const MouseEvent = @import("mouse_event.zig").MouseEvent;
/// What a `MouseEvent` reports: a press, a release, a move or a wheel turn.
pub const MouseEventKind = @import("mouse_event.zig").MouseEventKind;
/// The OS light/dark preference.
pub const SystemTheme = @import("system_theme.zig").SystemTheme;
/// One native menu-bar menu (macOS).
pub const CommandMenu = @import("command_menu.zig").CommandMenu;
/// One entry of a `CommandMenu`.
pub const CommandItem = @import("command_menu.zig").CommandItem;
/// The popover panel window a status-item click opens.
pub const Panel = @import("panel.zig").Panel;
/// What the popover panel shows and how big it is.
pub const PanelSpecification = @import("panel_specification.zig").PanelSpecification;
/// The system clipboard and the OS URL handler.
pub const Clipboard = @import("clipboard.zig").Clipboard;
/// The native open-file and open-folder dialogs.
pub const FileDialog = @import("file_dialog.zig").FileDialog;
/// What a finished `FileDialog` returned.
pub const FileDialogResult = @import("file_dialog.zig").FileDialogResult;
/// A `FileDialog` file filter.
pub const FileFilter = @import("file_dialog.zig").FileFilter;
/// A system-tray icon with an OS-drawn menu.
pub const MenuBarExtra = @import("menu_bar_extra.zig").MenuBarExtra;
/// A `MenuBarExtra` menu or submenu.
pub const MenuBarExtraMenu = @import("menu_bar_extra.zig").MenuBarExtraMenu;
/// One `MenuBarExtra` menu entry.
pub const MenuBarExtraEntry = @import("menu_bar_extra.zig").MenuBarExtraEntry;
/// A plain status icon whose click runs a callback (no menu).
pub const StatusItem = @import("status_item.zig").StatusItem;
/// The Linux status item over D-Bus.
pub const StatusNotifier = @import("status_notifier.zig").StatusNotifier;
/// The Linux freedesktop entry for the running executable.
pub const DesktopInstall = @import("desktop_install.zig").DesktopInstall;
/// Where the running executable's freedesktop entry stands.
pub const DesktopEntryState = @import("desktop_install.zig").DesktopEntryState;
/// The bits of AppKit SDL does not expose, through the Objective-C runtime.
pub const Cocoa = @import("cocoa.zig").Cocoa;
/// The Win32 calls SDL does not make: the notification-area icon and the icon resource.
pub const Win32 = @import("win32.zig").Win32;
/// The window manager's hit test: the drag band and the resize edges.
pub const WindowHitTest = @import("window_hit_test.zig").WindowHitTest;
/// The SDL_GPU backend.
pub const Gpu = @import("gpu/gpu.zig").Gpu;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    // Zig compiles only what is referenced, and `refAllDecls(@This())`
    // resolves each declaration (importing every file, so each file's own
    // tests run on every platform) but none of a struct's own declarations,
    // so code no app calls on a platform would go unchecked.
    const Reach = struct {
        const Self = @This();

        /// An app state for the generic types, which only hand it to the bodies.
        const Probe = struct {
            const Self = @This();
        };

        /// Reports whether the test references a barrel declaration's own
        /// declarations: every struct's, except `sdl_c` (all of SDL's C API)
        /// and the structs built for one OS (`Cocoa` on macOS, `Win32` on
        /// Windows, `StatusNotifier` on Linux) on any other, so a
        /// cross-compiled `zig build test-sdl` analyzes what that platform
        /// builds.
        ///
        /// - `name`: the declaration's name.
        /// - Returns: true when the test references its declarations.
        fn descends(comptime name: []const u8) bool {
            if (std.mem.eql(u8, name, "sdl_c")) return false;
            if (std.mem.eql(u8, name, "Cocoa")) return os_tag == .macos;
            if (std.mem.eql(u8, name, "Win32")) return os_tag == .windows;
            if (std.mem.eql(u8, name, "StatusNotifier")) return os_tag == .linux;
            return true;
        }
    };

    std.testing.refAllDecls(@This());
    inline for (comptime std.meta.declarations(@This())) |name| {
        const value = @field(@This(), name);
        if (comptime @TypeOf(value) == type and Reach.descends(name)) switch (@typeInfo(value)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => std.testing.refAllDecls(value),
            else => {},
        };
    }
    // The generic types, instantiated over the probe state.
    std.testing.refAllDecls(EventLoop(Reach.Probe));
    std.testing.refAllDecls(PanelSpecification(Reach.Probe));
    // Nothing here does I/O to trace.
    _ = log;
}
