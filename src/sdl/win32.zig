//! The Win32 calls SDL does not make: a notification-area icon whose click
//! runs a callback (the counterpart of the macOS status item; SDL's tray opens
//! its menu on either button and offers no click callback), and the check for
//! an embedded icon resource. Windows only: every call site is behind
//! `os_tag == .windows` except `hasIconResource`, which checks it first.

const std = @import("std");
const log = std.log.scoped(.ziggui_win32);
const mod = @import("module.zig");
const views = @import("views");

/// A window handle.
const HWND = ?*anyopaque;
/// A message's word parameter.
const WPARAM = usize;
/// A message's long parameter.
const LPARAM = isize;
/// A window procedure's result.
const LRESULT = isize;
/// A window procedure.
const WndProc = *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;

/// Win32's `WNDCLASSEXW`.
const WNDCLASSEXW = extern struct {
    const Self = @This();

    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: WndProc,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?*anyopaque,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: ?*anyopaque = null,
};

/// Win32's `NOTIFYICONDATAW`.
const NOTIFYICONDATAW = extern struct {
    const Self = @This();

    cbSize: u32 = @sizeOf(NOTIFYICONDATAW),
    hWnd: HWND = null,
    uID: u32 = 1,
    uFlags: u32 = 0,
    uCallbackMessage: u32 = 0,
    hIcon: ?*anyopaque = null,
    szTip: [128]u16 = @splat(0),
    dwState: u32 = 0,
    dwStateMask: u32 = 0,
    szInfo: [256]u16 = @splat(0),
    uVersion: u32 = 0,
    szInfoTitle: [64]u16 = @splat(0),
    dwInfoFlags: u32 = 0,
    guidItem: [16]u8 = @splat(0),
    hBalloonIcon: ?*anyopaque = null,
};

/// Win32's `BITMAPINFOHEADER`.
const BITMAPINFOHEADER = extern struct {
    const Self = @This();

    biSize: u32 = @sizeOf(BITMAPINFOHEADER),
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16 = 1,
    biBitCount: u16 = 32,
    biCompression: u32 = 0, // BI_RGB
    biSizeImage: u32 = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: u32 = 0,
    biClrImportant: u32 = 0,
};

/// Win32's `ICONINFO`.
const ICONINFO = extern struct {
    const Self = @This();

    fIcon: i32 = 1,
    xHotspot: u32 = 0,
    yHotspot: u32 = 0,
    hbmMask: ?*anyopaque,
    hbmColor: ?*anyopaque,
};

/// The notification-area icon and the message-only window it talks to (on
/// the UI thread; SDL's event pump dispatches its messages). One per process
/// (`shared`).
pub const Win32 = struct {
    const Self = @This();

    const NIM_ADD = 0;
    const NIM_DELETE = 2;
    const NIM_SETVERSION = 4;
    const NIF_MESSAGE = 0x1;
    const NIF_ICON = 0x2;
    const NIF_TIP = 0x4;
    const NIF_SHOWTIP = 0x80;
    const NOTIFYICON_VERSION_4 = 4;
    const NIN_SELECT = 0x400;
    const NIN_KEYSELECT = 0x401;
    const WM_CONTEXTMENU = 0x7B;
    const WM_TRAYICON = 0x8000 + 1; // WM_APP + 1
    const HWND_MESSAGE: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -3))));
    /// `RT_GROUP_ICON`, passed as a MAKEINTRESOURCE integer.
    const RT_GROUP_ICON: usize = 14;

    /// The icon's registration with the shell.
    notify_icon: NOTIFYICONDATAW = .{},

    /// The icon's click callback.
    status_callback: ?views.Callback = null,

    /// Explorer broadcasts this after it restarts; the icon must be added again.
    taskbar_created: u32 = 0,

    /// The process's Win32 state.
    var shared_win32: Self = .{};

    extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
    // Resource names/types are passed as MAKEINTRESOURCE integers.
    extern "kernel32" fn FindResourceW(module: ?*anyopaque, name: usize, kind: usize) callconv(.winapi) ?*anyopaque;
    extern "user32" fn RegisterClassExW(window_class: *const WNDCLASSEXW) callconv(.winapi) u16;
    extern "user32" fn CreateWindowExW(extended_style: u32, class: [*:0]const u16, title: [*:0]const u16, style: u32, x: i32, y: i32, width: i32, height: i32, parent: HWND, menu: ?*anyopaque, instance: ?*anyopaque, parameter: ?*anyopaque) callconv(.winapi) HWND;
    extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.winapi) i32;
    extern "user32" fn DefWindowProcW(hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;
    extern "user32" fn RegisterWindowMessageW(name: [*:0]const u16) callconv(.winapi) u32;
    extern "user32" fn CreateIconIndirect(icon_info: *const ICONINFO) callconv(.winapi) ?*anyopaque;
    extern "user32" fn DestroyIcon(icon: ?*anyopaque) callconv(.winapi) i32;
    extern "gdi32" fn CreateDIBSection(hdc: ?*anyopaque, bitmap_info: *const BITMAPINFOHEADER, usage: u32, bits: *?*anyopaque, section: ?*anyopaque, offset: u32) callconv(.winapi) ?*anyopaque;
    extern "gdi32" fn CreateBitmap(width: i32, height: i32, planes: u32, bits_per_pixel: u32, bits: ?*const anyopaque) callconv(.winapi) ?*anyopaque;
    extern "gdi32" fn DeleteObject(object: ?*anyopaque) callconv(.winapi) i32;
    extern "shell32" fn Shell_NotifyIconW(message: u32, data: *NOTIFYICONDATAW) callconv(.winapi) i32;

    /// The process's Win32 state.
    ///
    /// - Returns: the shared Win32 state.
    pub fn shared() *Self {
        return &shared_win32;
    }

    /// Reports whether this Windows .exe embeds an icon resource
    /// (RT_GROUP_ICON id 1, as assets/icon/ziggui.rc declares). SDL registers
    /// its window class with that icon at every size, so a single-image
    /// `SDL_SetWindowIcon` would only make it worse.
    ///
    /// - Returns: true when it does; always false elsewhere.
    pub fn hasIconResource() bool {
        if (mod.os_tag != .windows) return false;
        return FindResourceW(GetModuleHandleW(null), 1, Self.RT_GROUP_ICON) != null;
    }

    /// Creates the notification-area icon; either button's click runs
    /// `on_click`.
    ///
    /// - `self`: the Win32 state.
    /// - `rgba`: the icon, row-major straight-alpha RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    /// - `tooltip`: the hover text (ASCII).
    /// - `on_click`: runs on a click.
    /// - Returns: false when any Win32 step failed.
    pub fn createStatusItem(self: *Self, rgba: []const u8, width: c_int, height: c_int, tooltip: [:0]const u8, on_click: views.Callback) bool {
        const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigguiStatusItem");
        const instance = GetModuleHandleW(null);
        if (RegisterClassExW(&.{ .lpfnWndProc = Self.windowProcedure, .hInstance = instance, .lpszClassName = class }) == 0) return false;
        const hwnd = CreateWindowExW(0, class, class, 0, 0, 0, 0, 0, Self.HWND_MESSAGE, null, instance, null) orelse return false;
        const icon = Self.makeIcon(rgba, width, height) orelse {
            _ = DestroyWindow(hwnd);
            return false;
        };
        self.taskbar_created = RegisterWindowMessageW(std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated"));
        self.notify_icon = .{ .hWnd = hwnd, .uFlags = Self.NIF_MESSAGE | Self.NIF_ICON | Self.NIF_TIP | Self.NIF_SHOWTIP, .uCallbackMessage = Self.WM_TRAYICON, .hIcon = icon };
        // ASCII tooltips are all callers pass; widen byte by byte.
        for (tooltip[0..@min(tooltip.len, self.notify_icon.szTip.len - 1)], 0..) |character, index| self.notify_icon.szTip[index] = character;
        self.status_callback = on_click;
        self.add();
        return true;
    }

    /// Removes the notification-area icon and its window.
    ///
    /// - `self`: the Win32 state.
    pub fn destroyStatusItem(self: *Self) void {
        if (self.notify_icon.hWnd == null) return;
        _ = Shell_NotifyIconW(Self.NIM_DELETE, &self.notify_icon);
        _ = DestroyIcon(self.notify_icon.hIcon);
        _ = DestroyWindow(self.notify_icon.hWnd);
        self.notify_icon = .{};
        self.status_callback = null;
    }

    /// The message-only window's procedure: a click on the icon runs the
    /// callback; Explorer restarting re-adds the icon.
    fn windowProcedure(hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const self = Self.shared();
        if (message == Self.WM_TRAYICON) {
            // Version 4: the event is in the low word of lParam. Either button
            // opens the panel, which carries everything the menu did.
            switch (@as(u16, @truncate(@as(usize, @bitCast(lparam))))) {
                Self.NIN_SELECT, Self.NIN_KEYSELECT, Self.WM_CONTEXTMENU => if (self.status_callback) |callback| {
                    if (!mod.Panel.shared().statusClickCounts()) return 0;
                    callback.call();
                    mod.App.shared().wake();
                },
                else => {},
            }
            return 0;
        }
        if (message == self.taskbar_created and self.taskbar_created != 0) self.add();
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }

    /// Registers the icon with the shell, on notification version 4.
    fn add(self: *Self) void {
        _ = Shell_NotifyIconW(Self.NIM_ADD, &self.notify_icon);
        self.notify_icon.uVersion = Self.NOTIFYICON_VERSION_4;
        _ = Shell_NotifyIconW(Self.NIM_SETVERSION, &self.notify_icon);
    }

    /// An HICON from straight-alpha RGBA: a top-down 32-bit BGRA DIB (its
    /// alpha is the icon's transparency) plus the mask CreateIconIndirect requires.
    /// Null when `rgba` is not `width * height * 4` bytes or Win32 refused.
    fn makeIcon(rgba: []const u8, width: c_int, height: c_int) ?*anyopaque {
        // The DIB holds exactly width * height pixels; the copy below fills it
        // from `rgba`, so a longer buffer would write past it.
        if (!mod.WindowIcon.pixelsMatch(rgba, width, height)) return null;
        var bits: ?*anyopaque = null;
        const color = CreateDIBSection(null, &.{ .biWidth = width, .biHeight = -height }, 0, &bits, null, 0) orelse return null;
        defer _ = DeleteObject(color);
        const destination: [*]u8 = @ptrCast(bits orelse return null);
        var index: usize = 0;
        while (index + 3 < rgba.len) : (index += 4) {
            destination[index] = rgba[index + 2];
            destination[index + 1] = rgba[index + 1];
            destination[index + 2] = rgba[index];
            destination[index + 3] = rgba[index + 3];
        }
        const mask = CreateBitmap(width, height, 1, 1, null) orelse return null;
        defer _ = DeleteObject(mask);
        return CreateIconIndirect(&.{ .hbmMask = mask, .hbmColor = color });
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
