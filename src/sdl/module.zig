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
const views = @import("views");

/// The OS this runtime is built for (a compile-time invariant).
pub const os_tag = builtin.os.tag;
/// The CPU this runtime is built for (a compile-time invariant).
pub const cpu_arch = builtin.cpu.arch;

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
/// Where the main window is and how big.
pub const WindowFrame = @import("window_frame.zig").WindowFrame;
/// The event loop `App.run` drives for one app state type.
pub const EventLoop = @import("event_loop.zig").EventLoop;
/// A mouse event in the main window, in points.
pub const MouseEvent = @import("mouse_event.zig").MouseEvent;
/// What a `MouseEvent` reports: a press, a release, a move or a wheel turn.
pub const MouseEventKind = @import("mouse_event.zig").MouseEventKind;
/// The OS light/dark preference.
pub const SystemTheme = @import("system_theme.zig").SystemTheme;
/// One native menu-bar menu (macOS): the core's, so a `MenuTable` builds it.
pub const CommandMenu = views.CommandMenu;
/// One entry of a `CommandMenu`: the core's.
pub const CommandItem = views.CommandItem;
/// The popover panel window a status-item click opens.
pub const Panel = @import("panel.zig").Panel;
/// What the popover panel shows and how big it is.
pub const PanelSpecification = @import("panel_specification.zig").PanelSpecification;
/// The system clipboard and the OS URL handler.
pub const Clipboard = @import("clipboard.zig").Clipboard;
/// Shows a local file in the system's file manager.
pub const FileManager = @import("file_manager.zig").FileManager;
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
pub const StatusNotifier = @import("linux/module.zig").StatusNotifier;
/// The Linux freedesktop entry for the running executable.
pub const DesktopInstall = @import("linux/module.zig").DesktopInstall;
/// Where the running executable's freedesktop entry stands.
pub const DesktopEntryState = views.DesktopEntryState;
/// The bits of AppKit SDL does not expose, through the Objective-C runtime.
pub const Cocoa = @import("macos/module.zig").Cocoa;
/// The Win32 calls SDL does not make: the notification-area icon and the icon resource.
pub const Win32 = @import("windows/module.zig").Win32;
/// The window manager's hit test: the drag band and the resize edges.
pub const WindowHitTest = @import("window_hit_test.zig").WindowHitTest;
/// The SDL_GPU backend.
pub const Gpu = @import("gpu/gpu.zig").Gpu;
/// This OS's media player for `Player`, and the placement of its pictures.
pub const VideoBackend = @import("video_backend.zig").VideoBackend;
/// A video frame the player hands the renderer to draw under the surface (Windows).
pub const VideoUnderlay = @import("video_underlay.zig").VideoUnderlay;
/// The macOS media player: AVFoundation, its pictures behind the Metal view.
pub const AvFoundationPlayer = @import("macos/module.zig").AvFoundationPlayer;
/// The Windows media player: Media Foundation, its frames drawn under the surface.
pub const MediaFoundationPlayer = @import("windows/module.zig").MediaFoundationPlayer;
/// The Linux media player (GStreamer): a stub for now.
pub const GstreamerPlayer = @import("linux/module.zig").GstreamerPlayer;
/// This OS's host for `NativeView`: placement, overlay hiding and keyboard focus.
pub const NativeBackend = @import("native_backend.zig").NativeBackend;
/// Asks for frames for a moment after the window's content resizes, so placed views land.
pub const ResizeSettle = @import("resize_settle.zig").ResizeSettle;
/// This OS's web view for `WebPage`, installed as the loop starts.
pub const WebBackend = @import("web_backend.zig").WebBackend;
/// The macOS web view: a `WKWebView` per `WebPage`, placed by the native-view host.
pub const WkWebViewBackend = @import("macos/module.zig").WkWebViewBackend;
/// The Linux web view (WebKitGTK): a stub for now.
pub const WebKitGtkBackend = @import("linux/module.zig").WebKitGtkBackend;
/// The Windows web view: a WebView2 controller per `WebPage`, placed by the native-view host.
pub const WebView2Backend = @import("windows/module.zig").WebView2Backend;
/// The macOS native-view host: app `NSView`s above the Metal view.
pub const AppKitNativeHost = @import("macos/module.zig").AppKitNativeHost;
/// The Linux native-view host: a stub for now.
pub const NativeHostStub = @import("native_host_stub.zig").NativeHostStub;
/// The Windows native-view host: child windows above SDL's swapchain.
pub const Win32NativeHost = @import("windows/module.zig").Win32NativeHost;
/// The bits of COM the Windows web view and player share.
pub const Com = @import("windows/module.zig").Com;
/// The Objective-C runtime bridge the AVFoundation player uses.
pub const ObjectiveC = @import("macos/module.zig").ObjectiveC;
/// An Objective-C object pointer (`id`).
pub const Id = @import("macos/module.zig").Id;
/// One method a class `ObjectiveC.defineClass` registers answers.
pub const ObjectiveCMethod = @import("macos/module.zig").ObjectiveCMethod;
/// Core Graphics' `CGPoint`.
pub const CGPoint = @import("macos/module.zig").CGPoint;
/// Core Graphics' `CGSize`.
pub const CGSize = @import("macos/module.zig").CGSize;
/// Core Graphics' `CGRect`.
pub const CGRect = @import("macos/module.zig").CGRect;
/// Core Media's `CMTime`.
pub const CMTime = @import("macos/module.zig").CMTime;
/// Core Media's `CMTimeRange`.
pub const CMTimeRange = @import("macos/module.zig").CMTimeRange;

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
        /// and the structs built for one OS (`Cocoa`, `AvFoundationPlayer`,
        /// `AppKitNativeHost`, `WkWebViewBackend` and `ObjectiveC` on macOS, `Win32`, `Win32NativeHost`, `Com`, `WebView2Backend` and `MediaFoundationPlayer` on Windows, `StatusNotifier`
        /// on Linux) on any other, so a cross-compiled `zig build test-sdl`
        /// analyzes what that platform builds.
        ///
        /// - `name`: the declaration's name.
        /// - Returns: true when the test references its declarations.
        fn descends(comptime name: []const u8) bool {
            if (std.mem.eql(u8, name, "sdl_c")) return false;
            if (std.mem.eql(u8, name, "Cocoa") or std.mem.eql(u8, name, "AvFoundationPlayer") or std.mem.eql(u8, name, "AppKitNativeHost") or std.mem.eql(u8, name, "WkWebViewBackend") or std.mem.eql(u8, name, "ObjectiveC")) return os_tag == .macos;
            if (std.mem.eql(u8, name, "Win32") or std.mem.eql(u8, name, "Win32NativeHost") or std.mem.eql(u8, name, "Com") or std.mem.eql(u8, name, "WebView2Backend") or std.mem.eql(u8, name, "MediaFoundationPlayer")) return os_tag == .windows;
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
