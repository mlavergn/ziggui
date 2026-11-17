//! The macOS platform code: the Objective-C runtime bridge and what is built
//! on it (AppKit window chrome, AVFoundation video, the AppKit native-view
//! host, WebKit web pages). Other targets reach none of it but through the
//! compile-time selectors in the parent module (`VideoBackend`,
//! `NativeBackend`, `WebBackend`) and the macOS branches of `App` and the
//! event loop, so their builds never link the Objective-C runtime.

const std = @import("std");
const log = std.log.scoped(.ziggui_macos_module);

/// The typed `objc_msgSend` bridge and the runtime calls around it.
pub const ObjectiveC = @import("objective_c.zig").ObjectiveC;
/// An Objective-C object pointer (`id`), nil as null.
pub const Id = @import("objective_c.zig").Id;
/// One method a class `ObjectiveC.defineClass` registers answers.
pub const ObjectiveCMethod = @import("objective_c.zig").ObjectiveCMethod;
/// Core Graphics' `CGPoint` (AppKit's `NSPoint`).
pub const CGPoint = @import("objective_c.zig").CGPoint;
/// Core Graphics' `CGSize` (AppKit's `NSSize`).
pub const CGSize = @import("objective_c.zig").CGSize;
/// Core Graphics' `CGRect` (AppKit's `NSRect`).
pub const CGRect = @import("objective_c.zig").CGRect;
/// Core Media's `CMTime`: a rational time.
pub const CMTime = @import("objective_c.zig").CMTime;
/// Core Media's `CMTimeRange`: a start and a duration.
pub const CMTimeRange = @import("objective_c.zig").CMTimeRange;
/// AppKit through the Objective-C runtime: the unified title bar, the menu bar, template tray icons.
pub const Cocoa = @import("cocoa.zig").Cocoa;
/// The macOS media player: AVFoundation, its pictures behind the Metal view.
pub const AvFoundationPlayer = @import("av_foundation_player.zig").AvFoundationPlayer;
/// The macOS native-view host: app `NSView`s above the Metal view.
pub const AppKitNativeHost = @import("app_kit_native_host.zig").AppKitNativeHost;
/// The macOS web view: a `WKWebView` per `WebPage`, placed by the native-view host.
pub const WkWebViewBackend = @import("wk_web_view_backend.zig").WkWebViewBackend;

// -----------------------------------------------------------------------------
// From the sdl module

/// The app and its window (`Cocoa` reaches the window), from the sdl module.
pub const App = @import("../module.zig").App;
/// The native app menu's data (`Cocoa` installs it), from the sdl module.
pub const CommandMenu = @import("../module.zig").CommandMenu;
/// The window's icon (`Cocoa` sets the Dock's), from the sdl module.
pub const WindowIcon = @import("../module.zig").WindowIcon;
/// Frames for a moment after a resize (the video and native-view hosts), from the sdl module.
pub const ResizeSettle = @import("../module.zig").ResizeSettle;
/// The target OS, from the sdl module.
pub const os_tag = @import("../module.zig").os_tag;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
