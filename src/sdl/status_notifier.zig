//! The Linux status item: a StatusNotifierItem published over D-Bus, so a
//! click on the tray icon reaches the app as `Activate` (the macOS status-item
//! click) instead of opening a menu. SDL's tray goes through AppIndicator,
//! which answers `Activate` with an error and leaves hosts to show its menu.
//!
//! libdbus is loaded at run time (as SDL does), so the build needs no D-Bus
//! headers and a system without it falls back to SDL's tray. Setup runs on the
//! caller's thread; afterwards one detached thread owns the connection, and a
//! click crosses to the UI loop through `StatusNotifier.takeClick`.

const std = @import("std");
const log = std.log.scoped(.ziggui_status_notifier);
const mod = @import("module.zig");

/// A libdbus connection.
const DbusConnection = opaque {};

/// A libdbus message.
const DbusMessage = opaque {};

/// libdbus's `dbus_bool_t`.
const DbusBool = u32;

/// libdbus's `DBusError`.
const DbusError = extern struct {
    const Self = @This();

    /// The error's name.
    name: ?[*:0]const u8 = null,
    /// The error's message.
    message: ?[*:0]const u8 = null,
    /// libdbus's private bit fields.
    bits: c_uint = 0,
    /// libdbus's private padding.
    padding: ?*anyopaque = null,
};

/// DBusMessageIter is a public struct of opaque fields: 72 bytes on 64-bit.
const MessageIter = extern struct {
    const Self = @This();

    /// libdbus's private fields.
    opaque_fields: [10]u64 = @splat(0),
};

/// What a libdbus message handler did with a message.
const HandlerResult = enum(c_int) {
    const Self = @This();

    /// The message was handled.
    handled = 0,
    /// Another handler should look at it.
    notYetHandled = 1,
    /// Out of memory; libdbus retries.
    needMemory = 2,
};

/// A libdbus message handler.
const MessageFn = *const fn (*DbusConnection, *DbusMessage, ?*anyopaque) callconv(.c) HandlerResult;

/// libdbus's `DBusObjectPathVTable`.
const VTable = extern struct {
    const Self = @This();

    /// Called when the path is unregistered.
    unregister: ?*const anyopaque = null,
    /// Called for each message to the path.
    message: MessageFn,
    /// libdbus's reserved slots.
    pad: [4]?*const anyopaque = @splat(null),
};

/// The libdbus entry points used, resolved from libdbus-1.so.3.
const DbusApi = struct {
    const Self = @This();

    error_init: *const fn (*DbusError) callconv(.c) void,
    error_free: *const fn (*DbusError) callconv(.c) void,
    bus_get_private: *const fn (c_int, *DbusError) callconv(.c) ?*DbusConnection,
    set_exit_on_disconnect: *const fn (*DbusConnection, DbusBool) callconv(.c) void,
    request_name: *const fn (*DbusConnection, [*:0]const u8, c_uint, *DbusError) callconv(.c) c_int,
    add_match: *const fn (*DbusConnection, [*:0]const u8, ?*DbusError) callconv(.c) void,
    add_filter: *const fn (*DbusConnection, MessageFn, ?*anyopaque, ?*const anyopaque) callconv(.c) DbusBool,
    register_object_path: *const fn (*DbusConnection, [*:0]const u8, *const VTable, ?*anyopaque, *DbusError) callconv(.c) DbusBool,
    read_write_dispatch: *const fn (*DbusConnection, c_int) callconv(.c) DbusBool,
    send: *const fn (*DbusConnection, *DbusMessage, ?*u32) callconv(.c) DbusBool,
    send_with_reply_and_block: *const fn (*DbusConnection, *DbusMessage, c_int, *DbusError) callconv(.c) ?*DbusMessage,
    new_method_call: *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.c) ?*DbusMessage,
    new_method_return: *const fn (*DbusMessage) callconv(.c) ?*DbusMessage,
    unref: *const fn (*DbusMessage) callconv(.c) void,
    is_method_call: *const fn (*DbusMessage, [*:0]const u8, [*:0]const u8) callconv(.c) DbusBool,
    is_signal: *const fn (*DbusMessage, [*:0]const u8, [*:0]const u8) callconv(.c) DbusBool,
    iter_init: *const fn (*DbusMessage, *MessageIter) callconv(.c) DbusBool,
    iter_init_append: *const fn (*DbusMessage, *MessageIter) callconv(.c) void,
    iter_get_arg_type: *const fn (*MessageIter) callconv(.c) c_int,
    iter_get_basic: *const fn (*MessageIter, *anyopaque) callconv(.c) void,
    iter_next: *const fn (*MessageIter) callconv(.c) DbusBool,
    iter_append_basic: *const fn (*MessageIter, c_int, *const anyopaque) callconv(.c) DbusBool,
    iter_append_fixed_array: *const fn (*MessageIter, c_int, *const anyopaque, c_int) callconv(.c) DbusBool,
    iter_open_container: *const fn (*MessageIter, c_int, ?[*:0]const u8, *MessageIter) callconv(.c) DbusBool,
    iter_close_container: *const fn (*MessageIter, *MessageIter) callconv(.c) DbusBool,
};

/// The Linux status item's D-Bus state. One per process (`shared`); after
/// `create`, the D-Bus thread and the UI loop share it, the click crossing
/// through the atomics.
pub const StatusNotifier = struct {
    const Self = @This();

    /// `DBUS_BUS_SESSION`.
    const bus_session: c_int = 0;
    /// `DBUS_NAME_FLAG_DO_NOT_QUEUE`.
    const name_do_not_queue: c_uint = 4;
    /// D-Bus type codes.
    const type_int: c_int = 'i';
    const type_string: c_int = 's';
    const type_bool: c_int = 'b';
    const type_byte: c_int = 'y';
    const type_array: c_int = 'a';
    const type_variant: c_int = 'v';
    const type_struct: c_int = 'r';
    const type_dict_entry: c_int = 'e';

    /// Each `DbusApi` field and the libdbus symbol it is resolved from.
    const symbols = .{
        .{ "error_init", "dbus_error_init" },
        .{ "error_free", "dbus_error_free" },
        .{ "bus_get_private", "dbus_bus_get_private" },
        .{ "set_exit_on_disconnect", "dbus_connection_set_exit_on_disconnect" },
        .{ "request_name", "dbus_bus_request_name" },
        .{ "add_match", "dbus_bus_add_match" },
        .{ "add_filter", "dbus_connection_add_filter" },
        .{ "register_object_path", "dbus_connection_try_register_object_path" },
        .{ "read_write_dispatch", "dbus_connection_read_write_dispatch" },
        .{ "send", "dbus_connection_send" },
        .{ "send_with_reply_and_block", "dbus_connection_send_with_reply_and_block" },
        .{ "new_method_call", "dbus_message_new_method_call" },
        .{ "new_method_return", "dbus_message_new_method_return" },
        .{ "unref", "dbus_message_unref" },
        .{ "is_method_call", "dbus_message_is_method_call" },
        .{ "is_signal", "dbus_message_is_signal" },
        .{ "iter_init", "dbus_message_iter_init" },
        .{ "iter_init_append", "dbus_message_iter_init_append" },
        .{ "iter_get_arg_type", "dbus_message_iter_get_arg_type" },
        .{ "iter_get_basic", "dbus_message_iter_get_basic" },
        .{ "iter_next", "dbus_message_iter_next" },
        .{ "iter_append_basic", "dbus_message_iter_append_basic" },
        .{ "iter_append_fixed_array", "dbus_message_iter_append_fixed_array" },
        .{ "iter_open_container", "dbus_message_iter_open_container" },
        .{ "iter_close_container", "dbus_message_iter_close_container" },
    };

    const item_path = "/StatusNotifierItem";
    const item_iface = "org.kde.StatusNotifierItem";
    const properties_interface = "org.freedesktop.DBus.Properties";
    const watcher = "org.kde.StatusNotifierWatcher";

    /// The item's object-path handlers (static, as libdbus keeps the pointer).
    const vtable: VTable = .{ .message = Self.handle };

    /// No `Menu`: hosts then send `Activate`/`ContextMenu` for both buttons.
    const property_names = [_][:0]const u8{ "Category", "Id", "Title", "Status", "ItemIsMenu", "IconPixmap", "ToolTip" };

    /// The resolved libdbus entry points.
    api: DbusApi = undefined,

    /// The item's bus name.
    bus_name: [64:0]u8 = @splat(0),

    /// The item's title and tooltip.
    title: [128:0]u8 = @splat(0),

    /// The icon as ARGB32 in network byte order, the StatusNotifierItem pixmap format.
    argb: []u8 = &.{},

    /// The icon's width, in pixels.
    icon_width: i32 = 0,

    /// The icon's height, in pixels.
    icon_height: i32 = 0,

    /// A click is waiting for the UI loop.
    click_pending: std.atomic.Value(bool) = .init(false),

    /// The waiting click's x, in screen coordinates.
    click_x: std.atomic.Value(i32) = .init(0),

    /// The waiting click's y, in screen coordinates.
    click_y: std.atomic.Value(i32) = .init(0),

    /// The process's status notifier.
    var shared_notifier: Self = .{};

    /// The process's status notifier.
    ///
    /// - Returns: the shared status notifier.
    pub fn shared() *Self {
        return &shared_notifier;
    }

    /// Publishes the item and registers it with the desktop's
    /// StatusNotifierWatcher. After a click the D-Bus thread wakes the app
    /// (`App.wake`), so a UI loop blocked on input picks it up via `takeClick`.
    ///
    /// - `self`: the status notifier.
    /// - `allocator`: owns the icon's ARGB copy for the process's life.
    /// - `rgba`: the icon, row-major RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    /// - `tooltip`: the item's title and tooltip.
    /// - Returns: false when `rgba` is not `width * height * 4` bytes, or
    ///   there is no D-Bus or no tray host listening; the caller then falls
    ///   back to SDL's tray.
    pub fn create(self: *Self, allocator: std.mem.Allocator, rgba: []const u8, width: c_int, height: c_int, tooltip: []const u8) bool {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        // The pixmap is sent as `width` x `height`; other bytes would misdraw.
        if (!mod.WindowIcon.pixelsMatch(rgba, width, height)) return false;
        if (!self.load()) return false;
        var dbus_error: DbusError = .{};
        self.api.error_init(&dbus_error);
        defer self.api.error_free(&dbus_error);
        const connection = self.api.bus_get_private(Self.bus_session, &dbus_error) orelse return false;
        self.api.set_exit_on_disconnect(connection, 0);

        _ = std.fmt.bufPrintSentinel(&self.bus_name, "org.kde.StatusNotifierItem-{d}-1", .{std.os.linux.getpid()}, 0) catch return false;
        if (self.api.request_name(connection, &self.bus_name, Self.name_do_not_queue, &dbus_error) != 1) return false;
        if (self.api.register_object_path(connection, Self.item_path, &Self.vtable, null, &dbus_error) == 0) return false;

        // Pixmap first: the watcher asks for properties as soon as we register.
        self.argb = allocator.alloc(u8, rgba.len) catch return false;
        var index: usize = 0;
        while (index + 3 < rgba.len) : (index += 4) {
            self.argb[index] = rgba[index + 3];
            self.argb[index + 1] = rgba[index];
            self.argb[index + 2] = rgba[index + 1];
            self.argb[index + 3] = rgba[index + 2];
        }
        self.icon_width = width;
        self.icon_height = height;
        const title = Self.utf8Prefix(tooltip, self.title.len);
        self.title = @splat(0);
        @memcpy(self.title[0..title.len], title);

        const register = self.registerMessage() orelse return false;
        defer self.api.unref(register);
        const reply = self.api.send_with_reply_and_block(connection, register, 2000, &dbus_error) orelse return false;
        self.api.unref(reply);

        // A restarted tray host (the panel reloading) forgets the item: register
        // again when the watcher's name gets a new owner.
        self.api.add_match(connection, "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='" ++ Self.watcher ++ "'", null);
        _ = self.api.add_filter(connection, Self.watcherChanged, null, null);

        const thread = std.Thread.spawn(.{}, Self.serve, .{connection}) catch return false;
        thread.detach();
        return true;
    }

    /// Takes the click since the last call, if any.
    ///
    /// - `self`: the status notifier.
    /// - Returns: the screen position the host reported, (0, 0) when it sends
    ///   none (COSMIC), or null with no click.
    pub fn takeClick(self: *Self) ?[2]i32 {
        if (!self.click_pending.swap(false, .acquire)) return null;
        return .{ self.click_x.load(.monotonic), self.click_y.load(.monotonic) };
    }

    /// Resolves the libdbus entry points.
    fn load(self: *Self) bool {
        const library = std.c.dlopen("libdbus-1.so.3", .{ .LAZY = true }) orelse return false;
        inline for (Self.symbols) |symbol| {
            const pointer = std.c.dlsym(library, symbol[1]) orelse return false;
            @field(self.api, symbol[0]) = @ptrCast(@alignCast(pointer));
        }
        return true;
    }

    /// The D-Bus thread: dispatches until the connection drops.
    fn serve(connection: *DbusConnection) void {
        const self = Self.shared();
        while (self.api.read_write_dispatch(connection, -1) != 0) {}
    }

    /// A `RegisterStatusNotifierItem` call carrying the item's bus name.
    fn registerMessage(self: *Self) ?*DbusMessage {
        const message = self.api.new_method_call(Self.watcher, "/StatusNotifierWatcher", Self.watcher, "RegisterStatusNotifierItem") orelse return null;
        var iterator: MessageIter = .{};
        self.api.iter_init_append(message, &iterator);
        const name_pointer: [*:0]const u8 = &self.bus_name;
        _ = self.api.iter_append_basic(&iterator, Self.type_string, @ptrCast(&name_pointer));
        return message;
    }

    /// The watcher's owner changed: register again with the new one.
    fn watcherChanged(connection: *DbusConnection, message: *DbusMessage, _: ?*anyopaque) callconv(.c) HandlerResult {
        const self = Self.shared();
        if (self.api.is_signal(message, "org.freedesktop.DBus", "NameOwnerChanged") == 0) return .notYetHandled;
        // Arguments: name, old owner, new owner; an empty new owner means it left.
        var iterator: MessageIter = .{};
        var new_owner: [*:0]const u8 = "";
        if (self.api.iter_init(message, &iterator) != 0 and self.api.iter_next(&iterator) != 0 and self.api.iter_next(&iterator) != 0 and self.api.iter_get_arg_type(&iterator) == Self.type_string)
            self.api.iter_get_basic(&iterator, @ptrCast(&new_owner));
        if (new_owner[0] != 0) if (self.registerMessage()) |register| {
            _ = self.api.send(connection, register, null);
            self.api.unref(register);
        };
        return .notYetHandled;
    }

    /// The item's object-path handler: clicks, and the property reads.
    fn handle(connection: *DbusConnection, message: *DbusMessage, _: ?*anyopaque) callconv(.c) HandlerResult {
        const self = Self.shared();
        if (self.api.is_method_call(message, Self.item_iface, "Activate") != 0 or
            self.api.is_method_call(message, Self.item_iface, "SecondaryActivate") != 0 or
            self.api.is_method_call(message, Self.item_iface, "ContextMenu") != 0)
        {
            var iterator: MessageIter = .{};
            var x: i32 = 0;
            var y: i32 = 0;
            if (self.api.iter_init(message, &iterator) != 0 and self.api.iter_get_arg_type(&iterator) == Self.type_int) {
                self.api.iter_get_basic(&iterator, &x);
                if (self.api.iter_next(&iterator) != 0 and self.api.iter_get_arg_type(&iterator) == Self.type_int) self.api.iter_get_basic(&iterator, &y);
            }
            self.click_x.store(x, .monotonic);
            self.click_y.store(y, .monotonic);
            self.click_pending.store(true, .release);
            mod.App.shared().wake();
            return self.replyEmpty(connection, message);
        }
        if (self.api.is_method_call(message, Self.item_iface, "Scroll") != 0 or
            self.api.is_method_call(message, Self.item_iface, "ProvideXdgActivationToken") != 0)
            return self.replyEmpty(connection, message);
        if (self.api.is_method_call(message, Self.properties_interface, "GetAll") != 0) {
            const reply = self.api.new_method_return(message) orelse return .needMemory;
            defer self.api.unref(reply);
            var iterator: MessageIter = .{};
            self.api.iter_init_append(reply, &iterator);
            var dictionary: MessageIter = .{};
            _ = self.api.iter_open_container(&iterator, Self.type_array, "{sv}", &dictionary);
            for (Self.property_names) |name| {
                var entry: MessageIter = .{};
                _ = self.api.iter_open_container(&dictionary, Self.type_dict_entry, null, &entry);
                self.appendString(&entry, name);
                self.appendProperty(&entry, name);
                _ = self.api.iter_close_container(&dictionary, &entry);
            }
            _ = self.api.iter_close_container(&iterator, &dictionary);
            _ = self.api.send(connection, reply, null);
            return .handled;
        }
        if (self.api.is_method_call(message, Self.properties_interface, "Get") != 0) {
            var iterator: MessageIter = .{};
            var name: [*:0]const u8 = "";
            if (self.api.iter_init(message, &iterator) != 0 and self.api.iter_next(&iterator) != 0 and self.api.iter_get_arg_type(&iterator) == Self.type_string)
                self.api.iter_get_basic(&iterator, @ptrCast(&name));
            const property = std.mem.span(name);
            for (Self.property_names) |property_name| if (std.mem.eql(u8, property_name, property)) {
                const reply = self.api.new_method_return(message) orelse return .needMemory;
                defer self.api.unref(reply);
                var out: MessageIter = .{};
                self.api.iter_init_append(reply, &out);
                self.appendProperty(&out, property_name);
                _ = self.api.send(connection, reply, null);
                return .handled;
            };
        }
        // libdbus answers anything else with UnknownMethod.
        return .notYetHandled;
    }

    /// Answers a method call with an empty return.
    fn replyEmpty(self: *Self, connection: *DbusConnection, message: *DbusMessage) HandlerResult {
        const reply = self.api.new_method_return(message) orelse return .needMemory;
        _ = self.api.send(connection, reply, null);
        self.api.unref(reply);
        return .handled;
    }

    /// Appends property `name` as a variant.
    fn appendProperty(self: *Self, iterator: *MessageIter, name: []const u8) void {
        const signature: [:0]const u8 = if (std.mem.eql(u8, name, "ItemIsMenu"))
            "b"
        else if (std.mem.eql(u8, name, "IconPixmap"))
            "a(iiay)"
        else if (std.mem.eql(u8, name, "ToolTip"))
            "(sa(iiay)ss)"
        else
            "s";
        var variant: MessageIter = .{};
        _ = self.api.iter_open_container(iterator, Self.type_variant, signature, &variant);
        if (std.mem.eql(u8, name, "Category")) {
            self.appendString(&variant, "ApplicationStatus");
        } else if (std.mem.eql(u8, name, "Id")) {
            self.appendString(&variant, std.mem.sliceTo(&self.title, 0));
        } else if (std.mem.eql(u8, name, "Title")) {
            self.appendString(&variant, std.mem.sliceTo(&self.title, 0));
        } else if (std.mem.eql(u8, name, "Status")) {
            self.appendString(&variant, "Active");
        } else if (std.mem.eql(u8, name, "ItemIsMenu")) {
            const item_is_menu: DbusBool = 0;
            _ = self.api.iter_append_basic(&variant, Self.type_bool, &item_is_menu);
        } else if (std.mem.eql(u8, name, "IconPixmap")) {
            self.appendPixmaps(&variant, true);
        } else if (std.mem.eql(u8, name, "ToolTip")) {
            var tip: MessageIter = .{};
            _ = self.api.iter_open_container(&variant, Self.type_struct, null, &tip);
            self.appendString(&tip, "");
            self.appendPixmaps(&tip, false);
            self.appendString(&tip, std.mem.sliceTo(&self.title, 0));
            self.appendString(&tip, "");
            _ = self.api.iter_close_container(&variant, &tip);
        }
        _ = self.api.iter_close_container(iterator, &variant);
    }

    /// Appends an `a(iiay)` holding the icon, or empty.
    fn appendPixmaps(self: *Self, iterator: *MessageIter, with_icon: bool) void {
        var array: MessageIter = .{};
        _ = self.api.iter_open_container(iterator, Self.type_array, "(iiay)", &array);
        if (with_icon) {
            var pixmap: MessageIter = .{};
            _ = self.api.iter_open_container(&array, Self.type_struct, null, &pixmap);
            _ = self.api.iter_append_basic(&pixmap, Self.type_int, &self.icon_width);
            _ = self.api.iter_append_basic(&pixmap, Self.type_int, &self.icon_height);
            var bytes: MessageIter = .{};
            _ = self.api.iter_open_container(&pixmap, Self.type_array, "y", &bytes);
            const pointer: [*]const u8 = self.argb.ptr;
            _ = self.api.iter_append_fixed_array(&bytes, Self.type_byte, @ptrCast(&pointer), @intCast(self.argb.len));
            _ = self.api.iter_close_container(&pixmap, &bytes);
            _ = self.api.iter_close_container(&array, &pixmap);
        }
        _ = self.api.iter_close_container(iterator, &array);
    }

    /// Appends a string, cut to 256 bytes on a code-point boundary.
    fn appendString(self: *Self, iterator: *MessageIter, string: []const u8) void {
        var buffer: [256:0]u8 = @splat(0);
        const prefix = Self.utf8Prefix(string, buffer.len);
        @memcpy(buffer[0..prefix.len], prefix);
        const pointer: [*:0]const u8 = &buffer;
        _ = self.api.iter_append_basic(iterator, Self.type_string, @ptrCast(&pointer));
    }

    /// The longest prefix of `string` at most `limit` bytes long that ends on
    /// a code-point boundary. libdbus aborts the process on invalid UTF-8, so a
    /// string that is not valid UTF-8 becomes "".
    ///
    /// - `string`: the string to cut.
    /// - `limit`: the most bytes the prefix may hold.
    /// - Returns: the prefix, valid UTF-8.
    fn utf8Prefix(string: []const u8, limit: usize) []const u8 {
        var count = @min(string.len, limit);
        // Back off continuation bytes (10xxxxxx) so the cut lands before a lead byte.
        while (count > 0 and count < string.len and string[count] & 0xC0 == 0x80) count -= 1;
        const prefix = string[0..count];
        return if (std.unicode.utf8ValidateSlice(prefix)) prefix else "";
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "status_notifier: utf8Prefix cuts on a code-point boundary" {
    // "é" is two bytes and "€" three: a byte cut inside either backs off before it.
    try std.testing.expectEqualStrings("ab", StatusNotifier.utf8Prefix("abé", 3));
    try std.testing.expectEqualStrings("abé", StatusNotifier.utf8Prefix("abé", 4));
    try std.testing.expectEqualStrings("a", StatusNotifier.utf8Prefix("a€", 3));
    try std.testing.expectEqualStrings("a€", StatusNotifier.utf8Prefix("a€", 8));
    try std.testing.expectEqualStrings("", StatusNotifier.utf8Prefix("\xff\xfe", 8));
}
