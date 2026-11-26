//! The macOS `AuthenticationBackend`: LocalAuthentication's `LAContext`,
//! through the Objective-C runtime. Availability and biometry ask a fresh
//! context and prompt no one; `begin` shows the system's prompt with a new
//! context and returns a heap request, which the reply (an `ObjectiveCBlock`
//! capturing it, copied by LocalAuthentication into memory of its own)
//! reaches on LocalAuthentication's own queue. The reply only stores its
//! result and wakes the window (`FrameClock.wake`); the UI thread reads it
//! with `take`. A request `cancel` lets go of is freed by whichever side
//! finishes with it last: the reply, or `cancel` when the reply came first.
//! Works unsigned and ad-hoc signed; macOS needs no usage string for Touch ID.

const std = @import("std");
const log = std.log.scoped(.ziggui_la_context_backend);
const mod = @import("module.zig");
const views = @import("views");

/// The reply block's function: the block, `success`, the `NSError`.
const ReplyInvoke = fn (block: *anyopaque, success: u8, failure: mod.Id) callconv(.c) void;

/// Where a prompt's answer stands, between the reply's thread and the UI thread.
const RequestState = enum(u8) {
    const Self = @This();

    /// Still waiting for the reply.
    pending,
    /// The reply stored `result`.
    landed,
    /// `cancel` let go of it; the reply frees it.
    abandoned,
};

/// One prompt: its context and where its answer stands.
const Request = struct {
    const Self = @This();

    /// The `LAContext` showing the prompt, owned.
    context: mod.Id,
    /// Where its answer stands.
    state: std.atomic.Value(RequestState) = .init(.pending),
    /// The answer, once `landed`.
    result: views.AuthenticationResult = .succeeded,

    /// Frees the request and its context, from either thread.
    ///
    /// - `self`: the request.
    fn destroy(self: *Self) void {
        mod.ObjectiveC.release(self.context);
        std.heap.c_allocator.destroy(self);
    }
};

/// LocalAuthentication as an `AuthenticationBackend`.
pub const LaContextBackend = struct {
    const Self = @This();

    /// `LAPolicyDeviceOwnerAuthenticationWithBiometrics`.
    const policy_biometrics: isize = 1;
    /// `LAPolicyDeviceOwnerAuthentication`.
    const policy_device_owner: isize = 2;

    /// The backend the event loop installs.
    pub const backend: views.AuthenticationBackend = .{
        .availability = Self.availability,
        .biometry_type = Self.biometryType,
        .begin = Self.begin,
        .take = Self.take,
        .cancel = Self.cancel,
    };

    /// Asks a fresh context whether `policy` can be evaluated.
    ///
    /// - `policy`: the policy.
    /// - Returns: available, or why not.
    fn availability(policy: views.AuthenticationPolicy) views.AuthenticationAvailability {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const context = mod.ObjectiveC.new("LAContext");
        if (context == null) return .notAvailable;
        defer mod.ObjectiveC.release(context);
        var failure: mod.Id = null;
        if (mod.ObjectiveC.send(u8, context, "canEvaluatePolicy:error:", .{ Self.policyCode(policy), &failure }) != 0) return .available;
        return switch (Self.failureOf(failure)) {
            .notEnrolled => .notEnrolled,
            .lockout => .lockout,
            .passcodeNotSet => .passcodeNotSet,
            else => .notAvailable,
        };
    }

    /// Asks a fresh context which biometry the Mac has (it reads none until a
    /// policy has been asked about).
    ///
    /// - Returns: the biometry.
    fn biometryType() views.BiometryType {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const context = mod.ObjectiveC.new("LAContext");
        if (context == null) return .none;
        defer mod.ObjectiveC.release(context);
        var failure: mod.Id = null;
        _ = mod.ObjectiveC.send(u8, context, "canEvaluatePolicy:error:", .{ policy_biometrics, &failure });
        return switch (mod.ObjectiveC.send(isize, context, "biometryType", .{})) {
            1 => .touchId,
            2 => .faceId,
            4 => .opticId,
            else => .none,
        };
    }

    /// Shows the prompt with a new context.
    ///
    /// - `policy`: what the owner must prove.
    /// - `reason`: why, in the prompt.
    /// - `fallback_title`: the fallback button's title; null for the system's, empty to hide it.
    /// - Returns: the request, or null when it could not start.
    fn begin(policy: views.AuthenticationPolicy, reason: []const u8, fallback_title: ?[]const u8) ?*anyopaque {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const reason_text = std.heap.c_allocator.dupeSentinel(u8, reason, 0) catch |err| {
            log.warn("the prompt's reason could not be copied: {s}", .{@errorName(err)});
            return null;
        };
        defer std.heap.c_allocator.free(reason_text);
        const reason_string = mod.ObjectiveC.string(reason_text.ptr);
        if (reason_string == null) return null;
        const context = mod.ObjectiveC.new("LAContext");
        if (context == null) {
            log.warn("LocalAuthentication has no LAContext", .{});
            return null;
        }
        const request = std.heap.c_allocator.create(Request) catch |err| {
            log.warn("the prompt's request could not be made: {s}", .{@errorName(err)});
            mod.ObjectiveC.release(context);
            return null;
        };
        request.* = .{ .context = context };
        if (fallback_title) |title| {
            const title_text = std.heap.c_allocator.dupeSentinel(u8, title, 0) catch |err| {
                log.warn("the prompt's fallback title could not be copied: {s}", .{@errorName(err)});
                request.destroy();
                return null;
            };
            defer std.heap.c_allocator.free(title_text);
            mod.ObjectiveC.send(void, context, "setLocalizedFallbackTitle:", .{mod.ObjectiveC.string(title_text.ptr)});
        }
        // LocalAuthentication copies the block before this returns; the request outlives the copy's call.
        var block = mod.ObjectiveCBlock(ReplyInvoke).init(&Self.reply, request);
        mod.ObjectiveC.send(void, context, "evaluatePolicy:localizedReason:reply:", .{ Self.policyCode(policy), reason_string, @as(*anyopaque, @ptrCast(&block)) });
        return request;
    }

    /// Takes a request's answer once it has landed, freeing the request.
    ///
    /// - `handle`: the request.
    /// - Returns: the answer, or null while the prompt is up.
    fn take(handle: *anyopaque) ?views.AuthenticationResult {
        const request: *Request = @ptrCast(@alignCast(handle));
        if (request.state.load(.acquire) != .landed) return null;
        const result = request.result;
        request.destroy();
        return result;
    }

    /// Closes a request's prompt and lets it go: freed here when the reply
    /// came first, else by the reply that `invalidate` brings.
    ///
    /// - `handle`: the request.
    fn cancel(handle: *anyopaque) void {
        const request: *Request = @ptrCast(@alignCast(handle));
        // Held across the hand-over: once abandoned, the reply may free the request.
        const context = mod.ObjectiveC.retain(request.context);
        defer mod.ObjectiveC.release(context);
        if (request.state.cmpxchgStrong(.pending, .abandoned, .acq_rel, .acquire)) |_| {
            // Landed already: nothing calls back any more.
            request.destroy();
            return;
        }
        mod.ObjectiveC.send(void, context, "invalidate", .{});
    }

    /// The reply, on LocalAuthentication's queue: stores the answer and
    /// wakes the window, or frees a request let go of.
    ///
    /// - `block`: LocalAuthentication's copy of the block, capturing the request.
    /// - `success`: whether the owner proved who they are.
    /// - `failure`: the `NSError` when not.
    fn reply(block: *anyopaque, success: u8, failure: mod.Id) callconv(.c) void {
        const request: *Request = @ptrCast(@alignCast(mod.ObjectiveCBlock(ReplyInvoke).contextOf(block).?));
        request.result = if (success != 0) .succeeded else .{ .failed = Self.failureOf(failure) };
        if (request.state.cmpxchgStrong(.pending, .landed, .acq_rel, .acquire)) |_| {
            request.destroy();
            return;
        }
        views.FrameClock.shared().wake();
    }

    /// `LAPolicy`'s value for a policy.
    ///
    /// - `policy`: the policy.
    /// - Returns: its `NSInteger`.
    fn policyCode(policy: views.AuthenticationPolicy) isize {
        return switch (policy) {
            .biometrics => policy_biometrics,
            .deviceOwner => policy_device_owner,
        };
    }

    /// The failure an `LAError` names.
    ///
    /// - `failure`: the `NSError`, or nil.
    /// - Returns: the failure; `other` for nil or a code not listed.
    fn failureOf(failure: mod.Id) views.AuthenticationFailure {
        if (failure == null) return .other;
        return Self.failureOfCode(mod.ObjectiveC.send(isize, failure, "code", .{}));
    }

    /// The failure an `LAError` code names.
    ///
    /// - `code`: the error's code.
    /// - Returns: the failure; `other` for a code not listed.
    fn failureOfCode(code: isize) views.AuthenticationFailure {
        return switch (code) {
            -1 => .failed,
            -2 => .userCancel,
            -3 => .userFallback,
            -4 => .systemCancel,
            -5 => .passcodeNotSet,
            // Not available, not paired, disconnected: no biometry now.
            -6, -11, -12, -13 => .notAvailable,
            -7 => .notEnrolled,
            -8 => .lockout,
            -9 => .appCancel,
            else => .other,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "LocalAuthentication answers availability and biometry without a prompt" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    // Whatever this Mac has, the answers are consistent: Touch ID is available
    // only where the Mac reports Touch ID.
    const biometry = LaContextBackend.backend.biometry_type();
    const available = LaContextBackend.backend.availability(.biometrics);
    if (available == .available) try std.testing.expect(biometry != .none);
    _ = LaContextBackend.backend.availability(.deviceOwner);
}

test "LAError codes map to failures" {
    try std.testing.expectEqual(views.AuthenticationFailure.userCancel, LaContextBackend.failureOfCode(-2));
    try std.testing.expectEqual(views.AuthenticationFailure.lockout, LaContextBackend.failureOfCode(-8));
    try std.testing.expectEqual(views.AuthenticationFailure.other, LaContextBackend.failureOfCode(-1004));
}

test "a reply lands once, and a cancelled request is freed by its reply" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const pool = mod.ObjectiveC.pushPool();
    defer mod.ObjectiveC.popPool(pool);
    const Block = mod.ObjectiveCBlock(ReplyInvoke);
    // A request whose reply is called by hand through a block capturing it, as LocalAuthentication would.
    const request = try std.heap.c_allocator.create(Request);
    request.* = .{ .context = mod.ObjectiveC.new("NSObject") };
    var block = Block.init(&LaContextBackend.reply, request);
    try std.testing.expectEqual(@as(?views.AuthenticationResult, null), LaContextBackend.take(request));
    LaContextBackend.reply(&block, 1, null);
    try std.testing.expectEqual(@as(?views.AuthenticationResult, .succeeded), LaContextBackend.take(request));

    // Landed, then let go: `cancel` frees it and sends nothing.
    const landed = try std.heap.c_allocator.create(Request);
    landed.* = .{ .context = mod.ObjectiveC.new("NSObject") };
    block = Block.init(&LaContextBackend.reply, landed);
    LaContextBackend.reply(&block, 0, null);
    LaContextBackend.cancel(landed);

    // Let go before its reply: the reply frees it.
    const abandoned = try std.heap.c_allocator.create(Request);
    abandoned.* = .{ .context = mod.ObjectiveC.new("NSObject") };
    abandoned.state.store(.abandoned, .release);
    block = Block.init(&LaContextBackend.reply, abandoned);
    LaContextBackend.reply(&block, 0, null);
}
