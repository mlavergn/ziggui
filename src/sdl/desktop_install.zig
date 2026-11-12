//! Linux desktop integration: the running executable's freedesktop entry
//! (`.desktop` file) and icon, installed, checked and removed.

const std = @import("std");
const log = std.log.scoped(.ziggui_desktop_install);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// Where the running executable's freedesktop entry stands (see
/// `DesktopInstall.install`).
pub const DesktopEntryState = enum {
    const Self = @This();

    /// No entry of its own, and none installed system-wide.
    missing,
    /// Its entry runs this executable.
    current,
    /// Its entry runs another path (the executable moved).
    stale,
    /// A package installed one under `/usr/share` or `/usr/local/share`.
    system,
    /// Not Linux.
    unsupported,
};

/// The per-user entry's path for the running executable, and its app ID.
const EntryPaths = struct {
    const Self = @This();

    /// The `.desktop` file's path.
    desktop: [:0]const u8,
    /// The icon's path.
    icon: [:0]const u8,
    /// The app ID (the executable's basename).
    id: []const u8,
    /// The running executable's path.
    executable: []const u8,
};

/// Installs, checks and removes the running executable's freedesktop entry.
/// Stateless: every call reads the file system.
pub const DesktopInstall = struct {
    const Self = @This();

    /// Installs a freedesktop entry for the running executable:
    /// `$XDG_DATA_HOME/applications/<exe>.desktop` (default `~/.local/share`)
    /// plus the icon at `icons/hicolor/256x256/apps/<exe>.png`.
    ///
    /// Why: on Wayland a runtime window icon (`AppConfig.icon_png`) needs the
    /// `xdg_toplevel_icon_v1` protocol, which KDE Plasma supports but GNOME does
    /// not; GNOME instead matches the window's app ID (SDL uses the executable
    /// name) to a .desktop file and shows *its* icon (Dock, Activities, Alt-Tab).
    /// The entry also puts the app in the launcher. Re-run after moving the
    /// executable.
    ///
    /// - `name`: the app's display name.
    /// - `icon_png`: the icon as PNG bytes.
    /// - Returns: false off Linux or on any I/O failure (logged).
    pub fn install(name: []const u8, icon_png: []const u8) bool {
        if (mod.os_tag != .linux) return false;
        var executable_buffer: [4096]u8 = undefined;
        var data_buffer: [4096]u8 = undefined;
        var desktop_buffer: [4096]u8 = undefined;
        var icon_buffer: [4096]u8 = undefined;
        const paths = Self.entryPaths(&executable_buffer, &data_buffer, &desktop_buffer, &icon_buffer) orelse {
            std.log.err("ziggui: no desktop entry: cannot find the executable's path or the data folder", .{});
            return false;
        };
        if (!Self.createParentDirectory(paths.icon)) return false;
        if (!sdl_c.SDL_SaveFile(paths.icon.ptr, icon_png.ptr, icon_png.len)) return Self.logInstallError(paths.icon);
        if (!Self.createParentDirectory(paths.desktop)) return false;
        // Each value escaped per the Desktop Entry Specification, so a path with
        // spaces, quotes, `$`, `%` or backslashes means what it says (a path that
        // cannot be written, with a control character in it, is refused). Exec is
        // quoted; Icon is the absolute path so no icon-theme cache refresh is
        // needed; StartupWMClass ties X11 windows to the entry too (Wayland
        // matches by file name = app ID). Sized for the worst case: every byte of
        // a 4096-byte path escaped to four.
        var exec_value_buffer: [4 * 4096 + 8]u8 = undefined;
        var name_buffer: [2 * 256]u8 = undefined;
        var icon_value_buffer: [2 * 4096]u8 = undefined;
        var id_buffer: [2 * 4096]u8 = undefined;
        const exec_value = views.DesktopEntry.execValue(&exec_value_buffer, paths.executable, false) orelse return Self.logUnwritable("executable path", paths.executable);
        const name_value = views.DesktopEntry.stringValue(&name_buffer, name) orelse return Self.logUnwritable("name", name);
        const icon_value = views.DesktopEntry.stringValue(&icon_value_buffer, paths.icon) orelse return Self.logUnwritable("icon path", paths.icon);
        const id_value = views.DesktopEntry.stringValue(&id_buffer, paths.id) orelse return Self.logUnwritable("app ID", paths.id);
        var entry_buffer: [exec_value_buffer.len + name_buffer.len + icon_value_buffer.len + id_buffer.len + 256]u8 = undefined;
        const entry = std.fmt.bufPrint(&entry_buffer,
            \\[Desktop Entry]
            \\Type=Application
            \\Name={s}
            \\Exec={s}
            \\Icon={s}
            \\StartupWMClass={s}
            \\Terminal=false
            \\Categories=Utility;
            \\
        , .{ name_value, exec_value, icon_value, id_value }) catch return false;
        if (!sdl_c.SDL_SaveFile(paths.desktop.ptr, entry.ptr, entry.len)) return Self.logInstallError(paths.desktop);
        std.log.info("ziggui: installed {s} (icon {s})", .{ paths.desktop, paths.icon });
        return true;
    }

    /// Reports whether the running executable has a desktop entry, and whether
    /// it still points here. Linux only.
    ///
    /// - Returns: the entry's state.
    pub fn state() DesktopEntryState {
        if (mod.os_tag != .linux) return .unsupported;
        var executable_buffer: [4096]u8 = undefined;
        var data_buffer: [4096]u8 = undefined;
        var desktop_buffer: [4096]u8 = undefined;
        var icon_buffer: [4096]u8 = undefined;
        const paths = Self.entryPaths(&executable_buffer, &data_buffer, &desktop_buffer, &icon_buffer) orelse return .missing;
        for ([_][]const u8{ "/usr/share/applications", "/usr/local/share/applications" }) |directory| {
            var system_buffer: [4096]u8 = undefined;
            const system_path = std.fmt.bufPrintSentinel(&system_buffer, "{s}/{s}.desktop", .{ directory, paths.id }, 0) catch continue;
            if (sdl_c.SDL_GetPathInfo(system_path.ptr, null)) return .system;
        }
        var size: usize = 0;
        const data = sdl_c.SDL_LoadFile(paths.desktop.ptr, &size) orelse return .missing;
        defer sdl_c.SDL_free(data);
        const contents = @as([*]const u8, @ptrCast(data))[0..size];
        // The Exec line `install` writes for this path, escaped alike.
        var wanted_buffer: [4 * 4096 + 16]u8 = undefined;
        @memcpy(wanted_buffer[0..5], "Exec=");
        const exec_value = views.DesktopEntry.execValue(wanted_buffer[5..], paths.executable, false) orelse return .stale;
        return if (std.mem.find(u8, contents, wanted_buffer[0 .. 5 + exec_value.len]) != null) .current else .stale;
    }

    /// Removes the running executable's per-user desktop entry and its icon. A
    /// missing entry counts as removed.
    ///
    /// - Returns: false off Linux or when the entry could not be removed (logged).
    pub fn remove() bool {
        if (mod.os_tag != .linux) return false;
        var executable_buffer: [4096]u8 = undefined;
        var data_buffer: [4096]u8 = undefined;
        var desktop_buffer: [4096]u8 = undefined;
        var icon_buffer: [4096]u8 = undefined;
        const paths = Self.entryPaths(&executable_buffer, &data_buffer, &desktop_buffer, &icon_buffer) orelse return false;
        for ([_][:0]const u8{ paths.desktop, paths.icon }) |path| {
            if (!sdl_c.SDL_GetPathInfo(path.ptr, null)) continue;
            if (!sdl_c.SDL_RemovePath(path.ptr)) return Self.logInstallError(path);
        }
        return true;
    }

    /// Creates the folder `path` goes in, and any missing above it (logged on
    /// failure).
    fn createParentDirectory(path: []const u8) bool {
        const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return true;
        var buffer: [4096]u8 = undefined;
        const directory = std.fmt.bufPrintSentinel(&buffer, "{s}", .{path[0..slash]}, 0) catch return false;
        if (!sdl_c.SDL_CreateDirectory(directory.ptr)) return Self.logInstallError(directory);
        return true;
    }

    /// The running executable's path, its app ID, and where its per-user entry
    /// and icon go (`$XDG_DATA_HOME`, default `~/.local/share`). Null when the
    /// executable's path or the data folder cannot be found, or a path is too
    /// long.
    fn entryPaths(executable_buffer: *[4096]u8, data_buffer: *[4096]u8, desktop_buffer: *[4096]u8, icon_buffer: *[4096]u8) ?EntryPaths {
        const length = std.c.readlink("/proc/self/exe", executable_buffer, executable_buffer.len);
        // A path that fills the buffer may have been cut short.
        if (length <= 0 or length >= executable_buffer.len) return null;
        const executable = executable_buffer[0..@intCast(length)];
        // SDL's default app ID is the executable's basename; match it.
        const id = executable[(std.mem.lastIndexOfScalar(u8, executable, '/') orelse return null) + 1 ..];
        const xdg_data_home: ?[]const u8 = if (sdl_c.SDL_getenv("XDG_DATA_HOME")) |value| std.mem.span(value) else null;
        const home: ?[]const u8 = if (sdl_c.SDL_getenv("HOME")) |value| std.mem.span(value) else null;
        const data_directory = Self.dataDirectory(xdg_data_home, home, data_buffer) orelse return null;
        const desktop = std.fmt.bufPrintSentinel(desktop_buffer, "{s}/applications/{s}.desktop", .{ data_directory, id }, 0) catch return null;
        const icon = std.fmt.bufPrintSentinel(icon_buffer, "{s}/icons/hicolor/256x256/apps/{s}.png", .{ data_directory, id }, 0) catch return null;
        return .{ .desktop = desktop, .icon = icon, .id = id, .executable = executable };
    }

    /// The per-user data folder: `$XDG_DATA_HOME` when it is set to an
    /// absolute path (the XDG spec ignores an empty or relative one, which
    /// would put the entry under `/` or the working folder), else
    /// `$HOME/.local/share`.
    ///
    /// - `xdg_data_home`: `$XDG_DATA_HOME`, or null when unset.
    /// - `home`: `$HOME`, or null when unset.
    /// - `data_buffer`: holds the `$HOME`-based path.
    /// - Returns: the folder, or null when neither gives one or it is too long.
    fn dataDirectory(xdg_data_home: ?[]const u8, home: ?[]const u8, data_buffer: *[4096]u8) ?[]const u8 {
        if (xdg_data_home) |value| if (value.len > 0 and value[0] == '/') return value;
        const home_directory = home orelse return null;
        if (home_directory.len == 0) return null;
        return std.fmt.bufPrint(data_buffer, "{s}/.local/share", .{home_directory}) catch null;
    }

    /// Logs why `value` cannot go in a desktop entry. The value itself is left
    /// out: a control character in it would be written to the log raw.
    fn logUnwritable(what: []const u8, value: []const u8) bool {
        for (value) |byte| if (byte < 0x20 or byte == 0x7f) {
            std.log.err("ziggui: no desktop entry: its {s} has a control character", .{what});
            return false;
        };
        std.log.err("ziggui: no desktop entry: its {s} is too long ({d} bytes)", .{ what, value.len });
        return false;
    }

    /// Logs a failed write of `path` with SDL's error.
    fn logInstallError(path: []const u8) bool {
        std.log.err("ziggui: cannot write {s} ({s})", .{ path, sdl_c.SDL_GetError() });
        return false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(DesktopInstall);
    // Nothing here does I/O to trace.
    _ = log;
}

test "desktop install: XDG_DATA_HOME counts only when absolute" {
    var data_buffer: [4096]u8 = undefined;
    try std.testing.expectEqualStrings("/data", DesktopInstall.dataDirectory("/data", "/home/user", &data_buffer).?);
    try std.testing.expectEqualStrings("/home/user/.local/share", DesktopInstall.dataDirectory(null, "/home/user", &data_buffer).?);
    try std.testing.expectEqualStrings("/home/user/.local/share", DesktopInstall.dataDirectory("", "/home/user", &data_buffer).?);
    try std.testing.expectEqualStrings("/home/user/.local/share", DesktopInstall.dataDirectory("relative/data", "/home/user", &data_buffer).?);
    try std.testing.expect(DesktopInstall.dataDirectory("", null, &data_buffer) == null);
    try std.testing.expect(DesktopInstall.dataDirectory(null, "", &data_buffer) == null);
}
