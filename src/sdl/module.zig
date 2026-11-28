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
/// Whether SDL was built with `macos/metal_interop.m` in place of its Metal
/// GPU backend (macOS, from the release; not a prebuilt `-Dsdl3-prefix` SDL),
/// so `MetalInterop` reaches SDL_GPU's Metal objects (a compile-time invariant).
pub const has_metal_interop = @import("sdl_config").metal_interop;
/// Whether SDL was built with `gpu/vulkan_interop.c` in place of its Vulkan
/// GPU backend (Windows and Linux, from the release; not a prebuilt
/// `-Dsdl3-prefix` SDL), so `VulkanInterop` reaches SDL_GPU's Vulkan objects
/// and a device that can trace rays is made able to (a compile-time invariant).
pub const has_vulkan_interop = @import("sdl_config").vulkan_interop;
/// Whether SDL was built with `windows/d3d12_interop.c` in place of its
/// Direct3D 12 GPU backend (Windows, from the release), so `D3d12Interop`
/// can put it on WARP (a compile-time invariant).
pub const has_d3d12_interop = @import("sdl_config").d3d12_interop;

/// SDL3's C API, translated from `c.h` (keycodes, modifier masks, events).
pub const sdl_c = @import("sdl_c");

/// The running app: its window, loop flag, handlers, and `run`.
pub const App = @import("app.zig").App;
/// How `App.run` opens the window and renders.
pub const AppConfig = @import("app_config.zig").AppConfig;
/// Why the runtime could not start.
pub const AppError = @import("app_error.zig").AppError;
/// One running copy of an app: an OS file lock, and bringing the running copy forward.
pub const AppInstance = @import("app_instance.zig").AppInstance;
/// What `AppInstance.claim` found.
pub const AppInstanceClaim = @import("app_instance.zig").AppInstanceClaim;
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
/// The popover window a status-item click opens.
pub const PopoverWindow = @import("popover_window.zig").PopoverWindow;
/// What the popover window shows and how big it is.
pub const PopoverWindowSpecification = @import("popover_window_specification.zig").PopoverWindowSpecification;
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
/// Draws 3D scenes (`SceneView`) on the GPU device `Gpu` draws with.
pub const SceneRenderer = @import("gpu/scene_renderer.zig").SceneRenderer;
/// The shaders a `SceneRenderer`'s pipelines are made from.
pub const SceneShaders = @import("gpu/scene_renderer.zig").SceneShaders;
/// This OS's media player for `Player`, and the placement of its pictures.
pub const VideoBackend = @import("video_backend.zig").VideoBackend;
/// This OS's audio output listing for `AudioOutputs`.
pub const AudioBackend = @import("audio_backend.zig").AudioBackend;
/// SDL's audio devices for `AudioRecorder` and `AudioClipPlayer`.
pub const SdlAudioDevices = @import("sdl_audio_devices.zig").SdlAudioDevices;
/// A video frame the player hands the renderer to draw under the surface (Windows).
pub const VideoUnderlay = @import("video_underlay.zig").VideoUnderlay;
/// The macOS media player: AVFoundation, its pictures behind the Metal view.
pub const AvFoundationPlayer = @import("macos/module.zig").AvFoundationPlayer;
/// The macOS audio outputs: Core Audio's output devices, by UID.
pub const CoreAudioOutputs = @import("macos/module.zig").CoreAudioOutputs;
/// The Windows media player: Media Foundation, its frames drawn under the surface.
pub const MediaFoundationPlayer = @import("windows/module.zig").MediaFoundationPlayer;
/// The Windows audio outputs: the active render endpoints, by endpoint id.
pub const MmDeviceAudioOutputs = @import("windows/module.zig").MmDeviceAudioOutputs;
/// The Linux media player: GStreamer's `playbin`, its frames drawn by ziggui.
pub const GstreamerPlayer = @import("linux/module.zig").GstreamerPlayer;
/// The Linux audio outputs: GStreamer's device monitor, and a device's sink for a player.
pub const GstreamerAudioOutputs = @import("linux/module.zig").GstreamerAudioOutputs;
/// GStreamer and its app sink (Linux), loaded at run time.
pub const Gstreamer = @import("linux/module.zig").Gstreamer;
/// This OS's host for `NativeView`: placement, overlay hiding and keyboard focus.
pub const NativeBackend = @import("native_backend.zig").NativeBackend;
/// Asks for frames for a moment after the window's content resizes, so placed views land.
pub const ResizeSettle = @import("resize_settle.zig").ResizeSettle;
/// This OS's web view for `WebPage`, installed as the loop starts.
pub const WebBackend = @import("web_backend.zig").WebBackend;
/// The macOS web view: a `WKWebView` per `WebPage`, placed by the native-view host.
pub const WkWebViewBackend = @import("macos/module.zig").WkWebViewBackend;
/// This OS's device-owner authentication for `AuthenticationContext`, installed as the loop starts.
pub const LocalAuthenticationBackend = @import("local_authentication_backend.zig").LocalAuthenticationBackend;
/// The macOS device-owner authentication: LocalAuthentication's `LAContext` (Touch ID).
pub const LaContextBackend = @import("macos/module.zig").LaContextBackend;
/// The Linux web view: a WebKitGTK `WebKitWebView` per `WebPage`, placed by the native-view host.
pub const WebKitGtkBackend = @import("linux/module.zig").WebKitGtkBackend;
/// GTK 3, WebKitGTK and the Xlib calls around them (Linux), loaded at run time.
pub const Gtk = @import("linux/module.zig").Gtk;
/// Runs GLib's main context inside the SDL loop (Linux).
pub const GlibPump = @import("linux/module.zig").GlibPump;
/// The origin rule every web view's bridges apply.
pub const WebOrigin = @import("web_origin.zig").WebOrigin;
/// The Windows web view: a WebView2 controller per `WebPage`, placed by the
/// native-view host.
pub const WebView2Backend = @import("windows/module.zig").WebView2Backend;
/// The macOS native-view host: app `NSView`s above the Metal view.
pub const AppKitNativeHost = @import("macos/module.zig").AppKitNativeHost;
/// The Linux native-view host: app `GtkWidget`s in X11 child windows of SDL's.
pub const GtkNativeHost = @import("linux/module.zig").GtkNativeHost;
/// The native-view host for an OS with none: it places nothing.
pub const NativeHostStub = @import("native_host_stub.zig").NativeHostStub;
/// The Windows native-view host: child windows above SDL's swapchain.
pub const Win32NativeHost = @import("windows/module.zig").Win32NativeHost;
/// The bits of COM the Windows web view and player share.
pub const Com = @import("windows/module.zig").Com;
/// SDL's Direct3D 12 backend put on WARP, the CPU renderer Windows ships.
pub const D3d12Interop = @import("windows/module.zig").D3d12Interop;
/// SDL_GPU's Vulkan device, its functions and command buffers, for Vulkan work SDL_GPU has no API for.
pub const VulkanInterop = @import("gpu/vulkan_interop.zig").VulkanInterop;
/// The Vulkan functions `VulkanInterop` loads from SDL's device.
pub const VulkanFunctions = @import("gpu/vulkan_interop.zig").VulkanFunctions;
/// A buffer of ziggui's own on SDL's Vulkan device (`VulkanInterop.makeBuffer`).
pub const VulkanBuffer = @import("gpu/vulkan_interop.zig").VulkanBuffer;
/// Where a `VulkanBuffer` lives: shared with the CPU, or the GPU's alone.
pub const VulkanMemory = @import("gpu/vulkan_interop.zig").VulkanMemory;
/// SDL_GPU's Metal objects (device, textures, command buffers), for Metal work SDL_GPU has no API for.
pub const MetalInterop = @import("macos/module.zig").MetalInterop;
/// The Metal ray tracing behind a scene's ray-traced shadows and reflections: its shapes' acceleration structures.
pub const MetalSceneRayTracer = @import("macos/module.zig").MetalSceneRayTracer;
/// The Vulkan ray tracing behind a scene's ray-traced shadows and reflections, on SDL's Vulkan device.
pub const VulkanSceneRayTracer = @import("gpu/vulkan_scene_ray_tracer.zig").VulkanSceneRayTracer;
/// The ray tracer where SDL is built with neither interop: never made.
pub const SceneRayTracerStub = @import("gpu/scene_ray_tracer_stub.zig").SceneRayTracerStub;
/// This build's ray tracer, which `SceneRenderer` traces a scene's rays with:
/// Metal's on macOS, Vulkan's where SDL is built with `vulkan_interop.c`
/// (Windows and Linux, from the release), else the stub. Each says whether a
/// device traces rays (`supported`); a Vulkan one on a Windows machine whose
/// SDL chose Direct3D 12 does not.
pub const SceneRayTracer = if (os_tag == .macos) MetalSceneRayTracer else if (has_vulkan_interop) VulkanSceneRayTracer else SceneRayTracerStub;
/// An opaque shape rays meet, as `SceneRayTracer.prepare` takes it.
pub const SceneRayShape = @import("gpu/scene_ray_shape.zig").SceneRayShape;
/// A directional light's cookie, as `SceneRayTracer.bind` takes it.
pub const SceneRayCookie = @import("gpu/scene_ray_cookie.zig").SceneRayCookie;
/// A texture on a plane, as `SceneRayTracer.bind` takes a cookie's or an overlay's.
pub const SceneRayPlane = @import("gpu/scene_ray_plane.zig").SceneRayPlane;
/// A scene's environment, as `SceneRayTracer.bind` takes it.
pub const SceneRayEnvironment = @import("gpu/scene_ray_environment.zig").SceneRayEnvironment;
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
/// A global Objective-C block, laid out by hand, a framework calls back through.
pub const ObjectiveCBlock = @import("macos/module.zig").ObjectiveCBlock;
/// The descriptor an `ObjectiveCBlock` points at.
pub const ObjectiveCBlockDescriptor = @import("macos/module.zig").ObjectiveCBlockDescriptor;

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
        /// `AppKitNativeHost`, `WkWebViewBackend`, `CoreAudioOutputs`,
        /// `ObjectiveC`, `MetalInterop`, `MetalSceneRayTracer` and `LaContextBackend` on macOS,
        /// `Win32`, `Win32NativeHost`, `Com`, `WebView2Backend` and
        /// `MediaFoundationPlayer` and `MmDeviceAudioOutputs` on Windows, `StatusNotifier`, `Gtk`,
        /// `GlibPump`, `GtkNativeHost`, `WebKitGtkBackend`, `Gstreamer`,
        /// `GstreamerPlayer` and `GstreamerAudioOutputs` on Linux) on any
        /// other, nor the Vulkan interop's (`VulkanInterop`, `VulkanFunctions`,
        /// `VulkanBuffer`, `VulkanSceneRayTracer`, and `SceneRayTracer`
        /// off macOS) where SDL is not built with it, so a cross-compiled
        /// `zig build test-sdl` analyzes what that platform builds.
        ///
        /// - `name`: the declaration's name.
        /// - Returns: true when the test references its declarations.
        fn descends(comptime name: []const u8) bool {
            if (std.mem.eql(u8, name, "sdl_c")) return false;
            if (std.mem.eql(u8, name, "Cocoa") or std.mem.eql(u8, name, "AvFoundationPlayer") or std.mem.eql(u8, name, "AppKitNativeHost") or std.mem.eql(u8, name, "WkWebViewBackend") or std.mem.eql(u8, name, "CoreAudioOutputs") or std.mem.eql(u8, name, "ObjectiveC") or std.mem.eql(u8, name, "MetalInterop") or std.mem.eql(u8, name, "MetalSceneRayTracer") or std.mem.eql(u8, name, "LaContextBackend")) return os_tag == .macos;
            if (std.mem.eql(u8, name, "Win32") or std.mem.eql(u8, name, "Win32NativeHost") or std.mem.eql(u8, name, "Com") or std.mem.eql(u8, name, "WebView2Backend") or std.mem.eql(u8, name, "MediaFoundationPlayer") or std.mem.eql(u8, name, "MmDeviceAudioOutputs")) return os_tag == .windows;
            if (std.mem.eql(u8, name, "VulkanInterop") or std.mem.eql(u8, name, "VulkanFunctions") or std.mem.eql(u8, name, "VulkanBuffer") or std.mem.eql(u8, name, "VulkanSceneRayTracer")) return has_vulkan_interop;
            if (std.mem.eql(u8, name, "SceneRayTracer")) return os_tag == .macos or has_vulkan_interop;
            if (std.mem.eql(u8, name, "StatusNotifier") or std.mem.eql(u8, name, "Gtk") or std.mem.eql(u8, name, "GlibPump") or std.mem.eql(u8, name, "GtkNativeHost") or std.mem.eql(u8, name, "WebKitGtkBackend") or std.mem.eql(u8, name, "Gstreamer") or std.mem.eql(u8, name, "GstreamerPlayer") or std.mem.eql(u8, name, "GstreamerAudioOutputs")) return os_tag == .linux;
            return true;
        }
    };

    std.testing.refAllDecls(@This());
    // Every declaration's name is compared with each one-OS name above at
    // compile time, which outruns the default quota.
    @setEvalBranchQuota(10_000);
    inline for (comptime std.meta.declarations(@This())) |name| {
        const value = @field(@This(), name);
        if (comptime @TypeOf(value) == type and Reach.descends(name)) switch (@typeInfo(value)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => std.testing.refAllDecls(value),
            else => {},
        };
    }
    // The generic types, instantiated over the probe state.
    std.testing.refAllDecls(EventLoop(Reach.Probe));
    std.testing.refAllDecls(PopoverWindowSpecification(Reach.Probe));
    // Nothing here does I/O to trace.
    _ = log;
}
