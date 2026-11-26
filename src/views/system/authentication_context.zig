//! Device-owner authentication, after LocalAuthentication's `LAContext`:
//! an app-owned value that asks the installed `AuthenticationBackend`
//! whether Touch ID can be used and shows the system's prompt, then is
//! polled, as `Player` is: the prompt's answer lands on the platform's
//! thread, wakes the window, and `poll` reads it on the UI thread. With no
//! backend (headless, in tests, an OS whose backend is not written yet)
//! nothing is available and an app offers its password alone.
//!
//! The answer is the app's to act on: it proves the owner is present, it is
//! not a key. An app that keeps a secret behind it (a key in the keychain)
//! reads that secret only after `poll` says `.succeeded`.

const std = @import("std");
const log = std.log.scoped(.ziggui_authentication_context);
const mod = @import("module.zig");

/// Where an evaluation stands.
pub const AuthenticationStatus = union(enum) {
    const Self = @This();

    /// None asked for (or `reset` since).
    idle,
    /// The system's prompt is up.
    waiting,
    /// The owner proved who they are.
    succeeded,
    /// It did not succeed, and why.
    failed: mod.AuthenticationFailure,
};

/// One app's authentication: at most one prompt at a time.
pub const AuthenticationContext = struct {
    const Self = @This();

    /// The backend every context asks, installed by the SDL runtime as its
    /// loop starts; null headless and in tests, unless a test installs one.
    var installed_backend: ?*const mod.AuthenticationBackend = null;

    /// The prompt's fallback button, LAContext's `localizedFallbackTitle`:
    /// null for the system's "Use Password…", empty to hide it. Under
    /// `.biometrics` the button hands the owner back to the app
    /// (`.userFallback`), whose own way in it should name ("Use Master
    /// Password"); under `.deviceOwner` the system asks for the login password
    /// itself. Read by `evaluate`.
    localized_fallback_title: ?[]const u8 = null,
    /// The backend the pending request belongs to.
    backend: ?*const mod.AuthenticationBackend = null,
    /// The request the prompt answers, while it is up.
    request: ?*anyopaque = null,
    /// Where it stands, as `poll` last read it.
    state: AuthenticationStatus = .idle,

    /// Installs the backend contexts ask; the SDL runtime calls this as its
    /// loop starts and ends.
    ///
    /// - `backend`: the platform's authentication; null for none.
    pub fn setBackend(backend: ?*const mod.AuthenticationBackend) void {
        installed_backend = backend;
    }

    /// A context with nothing asked.
    ///
    /// - Returns: the context.
    pub fn init() Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{};
        return self;
    }

    /// Closes a prompt still up and lets its request go.
    ///
    /// - `self`: the context.
    pub fn deinit(self: *Self) void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        self.invalidate();
    }

    /// Whether `policy` can be evaluated now, prompting no one.
    ///
    /// - `self`: the context.
    /// - `policy`: the policy.
    /// - Returns: available, or why not; not available without a backend.
    pub fn canEvaluate(self: *const Self, policy: mod.AuthenticationPolicy) mod.AuthenticationAvailability {
        _ = self;
        const backend = installed_backend orelse return .notAvailable;
        return backend.availability(policy);
    }

    /// The biometry the device has, prompting no one.
    ///
    /// - `self`: the context.
    /// - Returns: the biometry; none without a backend.
    pub fn biometryType(self: *const Self) mod.BiometryType {
        _ = self;
        const backend = installed_backend orelse return .none;
        return backend.biometry_type();
    }

    /// Shows the system's prompt, closing one still up; `poll` then reads
    /// `.waiting` until the owner answers.
    ///
    /// - `self`: the context.
    /// - `policy`: what the owner must prove.
    /// - `reason`: why, finishing the prompt's "<app> is trying to …" ("unlock vault").
    pub fn evaluate(self: *Self, policy: mod.AuthenticationPolicy, reason: []const u8) void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        self.invalidate();
        const backend = installed_backend orelse {
            self.state = .{ .failed = .notAvailable };
            return;
        };
        const request = backend.begin(policy, if (reason.len == 0) "authenticate" else reason, self.localized_fallback_title) orelse {
            log.warn("the authentication prompt could not be shown", .{});
            self.state = .{ .failed = .other };
            return;
        };
        self.backend = backend;
        self.request = request;
        self.state = .waiting;
    }

    /// Reads where the evaluation stands, taking the prompt's answer once it
    /// has landed: call it each frame while `.waiting`.
    ///
    /// - `self`: the context.
    /// - Returns: the status, kept until the next `evaluate` or `reset`.
    pub fn poll(self: *Self) AuthenticationStatus {
        const request = self.request orelse return self.state;
        const backend = self.backend orelse return self.state;
        const result = backend.take(request) orelse return self.state;
        self.request = null;
        self.backend = null;
        self.state = switch (result) {
            .succeeded => .succeeded,
            .failed => |failure| .{ .failed = failure },
        };
        return self.state;
    }

    /// Whether the prompt is up.
    ///
    /// - `self`: the context.
    /// - Returns: true while waiting for the owner.
    pub fn isWaiting(self: *const Self) bool {
        return self.request != null;
    }

    /// Closes the prompt if it is up (LAContext's `invalidate`) and forgets
    /// the status.
    ///
    /// - `self`: the context.
    pub fn invalidate(self: *Self) void {
        if (self.request) |request| {
            log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
            if (self.backend) |backend| backend.cancel(request);
        }
        self.request = null;
        self.backend = null;
        self.state = .idle;
    }

    /// Forgets a status read, once the app has acted on it; a prompt still
    /// up stays up.
    ///
    /// - `self`: the context.
    pub fn reset(self: *Self) void {
        if (self.request == null) self.state = .idle;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "authentication: nothing is available without a backend" {
    AuthenticationContext.setBackend(null);
    var context = AuthenticationContext.init();
    defer context.deinit();
    try std.testing.expectEqual(mod.AuthenticationAvailability.notAvailable, context.canEvaluate(.biometrics));
    try std.testing.expectEqual(mod.BiometryType.none, context.biometryType());
    context.evaluate(.biometrics, "unlock");
    try std.testing.expectEqual(AuthenticationStatus{ .failed = .notAvailable }, context.poll());
}

test "authentication: the prompt's answer lands through poll, once" {
    const fake = mod.TestAuthentication.install();
    defer fake.uninstall();
    var context = AuthenticationContext.init();
    defer context.deinit();
    try std.testing.expectEqual(mod.AuthenticationAvailability.available, context.canEvaluate(.biometrics));
    try std.testing.expectEqual(mod.BiometryType.touchId, context.biometryType());

    context.evaluate(.biometrics, "unlock vault");
    try std.testing.expectEqualStrings("unlock vault", fake.reason());
    try std.testing.expectEqual(@as(?[]const u8, null), fake.fallbackTitle());
    try std.testing.expectEqual(AuthenticationStatus.waiting, context.poll());
    try std.testing.expect(context.isWaiting());
    fake.answer(.succeeded);
    try std.testing.expectEqual(AuthenticationStatus.succeeded, context.poll());
    try std.testing.expectEqual(AuthenticationStatus.succeeded, context.poll());
    context.reset();
    try std.testing.expectEqual(AuthenticationStatus.idle, context.poll());

    context.evaluate(.biometrics, "unlock vault");
    fake.answer(.{ .failed = .userCancel });
    try std.testing.expectEqual(AuthenticationStatus{ .failed = .userCancel }, context.poll());
}

test "authentication: the fallback button's title reaches the prompt" {
    const fake = mod.TestAuthentication.install();
    defer fake.uninstall();
    var context = AuthenticationContext.init();
    defer context.deinit();
    context.localized_fallback_title = "Use Master Password";
    context.evaluate(.biometrics, "unlock");
    try std.testing.expectEqualStrings("Use Master Password", fake.fallbackTitle().?);
    context.localized_fallback_title = "";
    context.evaluate(.biometrics, "unlock");
    try std.testing.expectEqualStrings("", fake.fallbackTitle().?);
}

test "authentication: invalidate closes the prompt and a new evaluate replaces it" {
    const fake = mod.TestAuthentication.install();
    defer fake.uninstall();
    var context = AuthenticationContext.init();
    defer context.deinit();
    context.evaluate(.deviceOwner, "unlock");
    context.evaluate(.deviceOwner, "unlock again");
    try std.testing.expectEqual(@as(usize, 1), fake.cancelled);
    try std.testing.expect(fake.isUp());
    context.invalidate();
    try std.testing.expectEqual(@as(usize, 2), fake.cancelled);
    try std.testing.expect(!fake.isUp());
    try std.testing.expectEqual(AuthenticationStatus.idle, context.poll());
}
