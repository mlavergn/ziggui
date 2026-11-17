//! Runs GLib's default main context (GTK's, WebKit's) inside the SDL loop.
//! GLib needs its sources dispatched on the thread that owns them, the UI
//! thread, but SDL's wait only wakes for SDL's events. So around each wait
//! the loop calls `beforeWait`, which dispatches what is ready and hands the
//! context's file descriptors and timeout to a watcher thread, and
//! `afterWait`, which takes them back and dispatches again. The watcher
//! polls them while SDL waits, and when one is ready (or GLib's next timer is
//! due) posts an SDL event of its own (`isWake`), which wakes the wait
//! without asking for a frame.
//!
//! The two threads hand over through eventfds: `go` (the descriptors are the
//! watcher's), `done` (they are the loop's again) and `interrupt` (stop
//! polling now), so the descriptor table is only ever read by one of them.

const std = @import("std");
const log = std.log.scoped(.ziggui_glib_pump);
const mod = @import("module.zig");
const sdl_c = @import("sdl_c");

/// The GLib main-context pump. One per process (`shared`), started with GTK.
pub const GlibPump = struct {
    const Self = @This();

    /// The most descriptors one wait watches; GLib's context rarely holds a
    /// handful (the X connection, WebKit's sockets, its own wakeup).
    const max_descriptors = 64;

    /// How many ready sources one dispatch runs before it lets SDL in.
    const max_dispatches = 64;

    /// `EFD_CLOEXEC`.
    const eventfd_cloexec: c_uint = 0o2000000;

    /// `EFD_NONBLOCK`.
    const eventfd_nonblock: c_uint = 0o4000;

    /// `POLLIN`.
    const poll_in: c_ushort = 1;

    /// GLib's default main context, owned by the UI thread.
    context: ?*anyopaque = null,

    /// The descriptors the watcher polls: GLib's, then `interrupt`. GLib's
    /// record has `struct pollfd`'s layout, so `poll` takes them as they are.
    descriptors: [max_descriptors + 1]mod.GpollFd = undefined,

    /// How many of `descriptors` are GLib's.
    count: usize = 0,

    /// GLib's timeout for the poll, in milliseconds; -1 for none.
    timeout_ms: c_int = -1,

    /// Signalled when the descriptors are the watcher's to poll.
    go: c_int = -1,

    /// Signalled when the watcher is done with them.
    done: c_int = -1,

    /// Signalled to cut the watcher's poll short.
    interrupt: c_int = -1,

    /// The SDL event type the watcher posts.
    wake_type: u32 = 0,

    /// The watcher holds the descriptors now.
    watching: bool = false,

    /// The process's pump.
    var shared_pump: Self = .{};

    /// The process's pump.
    ///
    /// - Returns: the shared pump.
    pub fn shared() *Self {
        return &shared_pump;
    }

    /// Takes GLib's default context for the UI thread and starts the watcher.
    /// GTK must be running; the calling thread is the UI thread.
    ///
    /// - `self`: the pump.
    /// - `api`: GTK's entry points.
    /// - Returns: false when an eventfd, the SDL event type or the thread
    ///   could not be had; GLib then runs only as SDL events come.
    pub fn start(self: *Self, api: *const mod.GtkApi) bool {
        if (self.context != null) return true;
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const context = api.g_main_context_default() orelse return false;
        if (api.g_main_context_acquire(context) == 0) return false;
        self.context = context;
        // Two, keeping the second: the first may be `SDL_EVENT_USER` itself,
        // which `App.wake` posts without registering it, and a wake taken for
        // the pump's would draw no frame.
        const first = sdl_c.SDL_RegisterEvents(2);
        if (first == 0) return false;
        self.wake_type = first + 1;
        self.go = std.c.eventfd(0, eventfd_cloexec);
        self.done = std.c.eventfd(0, eventfd_cloexec);
        self.interrupt = std.c.eventfd(0, eventfd_cloexec | eventfd_nonblock);
        if (self.go < 0 or self.done < 0 or self.interrupt < 0) return false;
        const thread = std.Thread.spawn(.{}, Self.watch, .{self}) catch return false;
        thread.detach();
        log.debug("GLib pump watching, wake event 0x{x}", .{self.wake_type});
        return true;
    }

    /// Runs what GLib has ready, then lets the watcher poll GLib's
    /// descriptors while SDL waits. The loop calls it before each wait.
    ///
    /// - `self`: the pump.
    pub fn beforeWait(self: *Self) void {
        const api = mod.Gtk.running() orelse return;
        if (self.wake_type == 0 or self.watching) return;
        self.dispatch(api);
        var priority: c_int = 0;
        _ = api.g_main_context_prepare(self.context, &priority);
        var timeout: c_int = -1;
        const wanted = api.g_main_context_query(self.context, priority, &timeout, &self.descriptors, max_descriptors);
        self.count = @intCast(@min(@max(wanted, 0), max_descriptors));
        if (wanted > max_descriptors) log.warn("GLib wants {d} descriptors watched; {d} are", .{ wanted, max_descriptors });
        self.timeout_ms = timeout;
        self.descriptors[self.count] = .{ .fd = self.interrupt, .events = poll_in, .revents = 0 };
        self.watching = true;
        Self.signal(self.go);
    }

    /// Takes the descriptors back from the watcher, then runs what GLib has
    /// ready. The loop calls it after each wait.
    ///
    /// - `self`: the pump.
    pub fn afterWait(self: *Self) void {
        const api = mod.Gtk.running() orelse return;
        if (!self.watching) return;
        Self.signal(self.interrupt);
        Self.take(self.done);
        // The watcher is done: whatever it left of the interrupt goes.
        Self.take(self.interrupt);
        self.watching = false;
        self.dispatch(api);
    }

    /// Reports whether an SDL event is the watcher's: it wakes the loop for
    /// GLib and asks for no frame.
    ///
    /// - `self`: the pump.
    /// - `event_type`: the event's type.
    /// - Returns: true for the watcher's event.
    pub fn isWake(self: *const Self, event_type: u32) bool {
        return self.wake_type != 0 and event_type == self.wake_type;
    }

    /// Dispatches GLib's ready sources, a bounded number of them.
    ///
    /// - `self`: the pump.
    /// - `api`: GTK's entry points.
    fn dispatch(self: *Self, api: *const mod.GtkApi) void {
        var runs: usize = 0;
        while (runs < max_dispatches and api.g_main_context_iteration(self.context, 0) != 0) runs += 1;
    }

    /// The watcher thread: polls each set of descriptors it is handed, posting
    /// the wake event when GLib has work (not when interrupted), and hands
    /// them back.
    ///
    /// - `self`: the pump.
    fn watch(self: *Self) void {
        while (true) {
            Self.take(self.go);
            const result = std.c.poll(@ptrCast(&self.descriptors), @intCast(self.count + 1), self.timeout_ms);
            const interrupted = result > 0 and (self.descriptors[self.count].revents & poll_in) != 0;
            if (!interrupted) {
                var event = std.mem.zeroes(sdl_c.SDL_Event);
                event.type = self.wake_type;
                _ = sdl_c.SDL_PushEvent(&event);
            }
            Self.signal(self.done);
        }
    }

    /// Adds one to an eventfd's count, waking a reader.
    ///
    /// - `descriptor`: the eventfd.
    fn signal(descriptor: c_int) void {
        const one: u64 = 1;
        _ = std.c.write(descriptor, std.mem.asBytes(&one), @sizeOf(u64));
    }

    /// Reads an eventfd's count to zero, blocking until it is set unless the
    /// eventfd is non-blocking.
    ///
    /// - `descriptor`: the eventfd.
    fn take(descriptor: c_int) void {
        var count: u64 = 0;
        _ = std.c.read(descriptor, std.mem.asBytes(&count), @sizeOf(u64));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the pump does nothing before GTK runs" {
    // Its eventfds and poll are Linux's.
    if (comptime mod.os_tag != .linux) return error.SkipZigTest;
    const pump = GlibPump.shared();
    pump.beforeWait();
    pump.afterWait();
    try std.testing.expect(!pump.watching);
    try std.testing.expect(!pump.isWake(sdl_c.SDL_EVENT_USER));
}
