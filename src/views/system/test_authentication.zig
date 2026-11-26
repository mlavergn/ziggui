//! A fake `AuthenticationBackend` for tests, the views' and an app's: Touch ID
//! available, one prompt at a time, answered by the test with `answer`, as
//! the owner would answer the system's. Its state is one shared value, since
//! a backend's pointers carry no context.

const std = @import("std");
const log = std.log.scoped(.ziggui_test_authentication);
const mod = @import("module.zig");

/// The fake authentication: install it, drive it, uninstall it.
pub const TestAuthentication = struct {
    const Self = @This();

    /// The one fake.
    var instance: Self = .{};
    /// What a request handle points at (its address is all that matters).
    var token: u8 = 0;

    /// The fake's backend.
    const backend: mod.AuthenticationBackend = .{
        .availability = Self.availabilityOf,
        .biometry_type = Self.biometryOf,
        .begin = Self.begin,
        .take = Self.take,
        .cancel = Self.cancel,
    };

    /// What `canEvaluate` answers, whatever the policy.
    availability: mod.AuthenticationAvailability = .available,
    /// What `biometryType` answers.
    biometry: mod.BiometryType = .touchId,
    /// Refuses to show a prompt, as a platform that cannot.
    refuse_begin: bool = false,
    /// How many prompts were shown.
    begun: usize = 0,
    /// How many prompts were closed by the app.
    cancelled: usize = 0,
    /// The last prompt's policy.
    policy: mod.AuthenticationPolicy = .biometrics,
    /// Whether a prompt is up.
    up: bool = false,
    /// The answer given to the prompt up, until taken.
    landed: ?mod.AuthenticationResult = null,
    /// The last prompt's reason, cut to the buffer.
    reason_buffer: [128]u8 = undefined,
    /// How much of `reason_buffer` holds it.
    reason_length: usize = 0,
    /// The last prompt's fallback title, cut to the buffer.
    fallback_buffer: [64]u8 = undefined,
    /// How much of `fallback_buffer` holds it; null when the system's was asked for.
    fallback_length: ?usize = null,

    /// Installs the fake, fresh, as the backend every `AuthenticationContext` asks.
    ///
    /// - Returns: the fake, to drive.
    pub fn install() *Self {
        instance = .{};
        mod.AuthenticationContext.setBackend(&backend);
        return &instance;
    }

    /// Uninstalls the fake.
    ///
    /// - `self`: the fake.
    pub fn uninstall(self: *Self) void {
        _ = self;
        mod.AuthenticationContext.setBackend(null);
    }

    /// Answers the prompt up, as the owner would; nothing without one.
    ///
    /// - `self`: the fake.
    /// - `result`: the answer.
    pub fn answer(self: *Self, result: mod.AuthenticationResult) void {
        if (self.up) self.landed = result;
    }

    /// Whether a prompt is up.
    ///
    /// - `self`: the fake.
    /// - Returns: true while one is.
    pub fn isUp(self: *const Self) bool {
        return self.up;
    }

    /// The last prompt's reason.
    ///
    /// - `self`: the fake.
    /// - Returns: the reason, as far as the buffer holds.
    pub fn reason(self: *const Self) []const u8 {
        return self.reason_buffer[0..self.reason_length];
    }

    /// The last prompt's fallback title.
    ///
    /// - `self`: the fake.
    /// - Returns: the title (empty: hidden), or null for the system's.
    pub fn fallbackTitle(self: *const Self) ?[]const u8 {
        const length = self.fallback_length orelse return null;
        return self.fallback_buffer[0..length];
    }

    /// Answers `canEvaluate`.
    ///
    /// - `policy`: the policy, ignored.
    /// - Returns: the fake's availability.
    fn availabilityOf(policy: mod.AuthenticationPolicy) mod.AuthenticationAvailability {
        _ = policy;
        return instance.availability;
    }

    /// Answers `biometryType`.
    ///
    /// - Returns: the fake's biometry.
    fn biometryOf() mod.BiometryType {
        return instance.biometry;
    }

    /// Shows the fake prompt, closing one still up as the platform would.
    ///
    /// - `policy`: the policy, kept.
    /// - `text`: the reason, kept.
    /// - `fallback_title`: the fallback button's title, kept.
    /// - Returns: the request, or null when refusing.
    fn begin(policy: mod.AuthenticationPolicy, text: []const u8, fallback_title: ?[]const u8) ?*anyopaque {
        if (instance.refuse_begin) return null;
        instance.begun += 1;
        instance.policy = policy;
        instance.up = true;
        instance.landed = null;
        instance.reason_length = @min(text.len, instance.reason_buffer.len);
        @memcpy(instance.reason_buffer[0..instance.reason_length], text[0..instance.reason_length]);
        instance.fallback_length = null;
        if (fallback_title) |title| {
            const length = @min(title.len, instance.fallback_buffer.len);
            @memcpy(instance.fallback_buffer[0..length], title[0..length]);
            instance.fallback_length = length;
        }
        return &token;
    }

    /// Takes the answer once given.
    ///
    /// - `request`: the request, ignored (there is one).
    /// - Returns: the answer, or null while none is given.
    fn take(request: *anyopaque) ?mod.AuthenticationResult {
        _ = request;
        const result = instance.landed orelse return null;
        instance.landed = null;
        instance.up = false;
        return result;
    }

    /// Closes the prompt.
    ///
    /// - `request`: the request, ignored (there is one).
    fn cancel(request: *anyopaque) void {
        _ = request;
        instance.cancelled += 1;
        instance.up = false;
        instance.landed = null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the fake refuses a prompt when told to" {
    const fake = TestAuthentication.install();
    defer fake.uninstall();
    fake.refuse_begin = true;
    var context = mod.AuthenticationContext.init();
    defer context.deinit();
    context.evaluate(.biometrics, "unlock");
    try std.testing.expectEqual(mod.AuthenticationStatus{ .failed = .other }, context.poll());
    try std.testing.expectEqual(@as(usize, 0), fake.begun);
}
