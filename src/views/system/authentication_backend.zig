//! The platform's device-owner authentication (Touch ID, or the login
//! password), as function pointers: the SDL runtime installs its own as its
//! loop starts (as it does a `PlayerBackend`), so the views stay free of
//! platform code, and tests install `TestAuthentication`. The values are
//! LocalAuthentication's (`LAPolicy`, `LABiometryType`, `LAError`), named as
//! Swift names them.

const std = @import("std");
const log = std.log.scoped(.ziggui_authentication_backend);

/// What the owner must prove: LocalAuthentication's `LAPolicy`.
pub const AuthenticationPolicy = enum {
    const Self = @This();

    /// Biometrics alone (Touch ID): `.deviceOwnerAuthenticationWithBiometrics`.
    biometrics,
    /// Biometrics, else the login password: `.deviceOwnerAuthentication`.
    deviceOwner,
};

/// The biometry the device has: LocalAuthentication's `LABiometryType`.
pub const BiometryType = enum {
    const Self = @This();

    /// None, or none the system will say.
    none,
    /// Touch ID.
    touchId,
    /// Face ID.
    faceId,
    /// Optic ID.
    opticId,

    /// The biometry's name, as a button names it.
    ///
    /// - `self`: the biometry.
    /// - Returns: "Touch ID", "Face ID", "Optic ID", or "Biometrics" for none.
    pub fn label(self: *const Self) []const u8 {
        return switch (self.*) {
            .none => "Biometrics",
            .touchId => "Touch ID",
            .faceId => "Face ID",
            .opticId => "Optic ID",
        };
    }
};

/// Whether a policy can be evaluated now: `canEvaluatePolicy`'s answer.
pub const AuthenticationAvailability = enum {
    const Self = @This();

    /// It can.
    available,
    /// No biometry (none fitted, a lid closed over the sensor, no backend).
    notAvailable,
    /// Biometry with no finger enrolled.
    notEnrolled,
    /// Biometry locked after too many failures, until the password is entered.
    lockout,
    /// The account has no password.
    passcodeNotSet,

    /// A short sentence saying whether Touch ID can be used, and if not what to do.
    ///
    /// - `self`: the availability.
    /// - Returns: the sentence, static.
    pub fn message(self: *const Self) []const u8 {
        return switch (self.*) {
            .available => "Touch ID is available.",
            .notAvailable => "Touch ID is not available on this Mac.",
            .notEnrolled => "Touch ID has no fingerprint enrolled; add one in System Settings.",
            .lockout => "Touch ID is locked after too many tries; enter your login password once to turn it back on.",
            .passcodeNotSet => "This account has no password, so Touch ID cannot be used.",
        };
    }
};

/// Why an evaluation did not succeed: LocalAuthentication's `LAError`.
pub const AuthenticationFailure = enum {
    const Self = @This();

    /// The owner was not recognized (`.authenticationFailed`).
    failed,
    /// The owner cancelled the prompt (`.userCancel`).
    userCancel,
    /// The owner chose to enter a password instead (`.userFallback`), the
    /// app's own way in.
    userFallback,
    /// The system cancelled it (another app came forward: `.systemCancel`).
    systemCancel,
    /// The app cancelled it (`AuthenticationContext.invalidate`: `.appCancel`).
    appCancel,
    /// No biometry now (`.biometryNotAvailable`, or no backend).
    notAvailable,
    /// No finger enrolled (`.biometryNotEnrolled`).
    notEnrolled,
    /// Locked after too many failures (`.biometryLockout`).
    lockout,
    /// The account has no password (`.passcodeNotSet`).
    passcodeNotSet,
    /// Anything else the system reports.
    other,

    /// Whether the owner (or the app) ended it, so a message would only repeat what they did.
    ///
    /// - `self`: the failure.
    /// - Returns: true for a cancel or a fallback.
    pub fn isCancel(self: *const Self) bool {
        return switch (self.*) {
            .userCancel, .userFallback, .systemCancel, .appCancel => true,
            else => false,
        };
    }

    /// A short sentence saying what happened, for a status line.
    ///
    /// - `self`: the failure.
    /// - Returns: the sentence, static.
    pub fn message(self: *const Self) []const u8 {
        return switch (self.*) {
            .failed => "Not recognized.",
            .userCancel, .systemCancel, .appCancel => "Cancelled.",
            .userFallback => "Enter the password instead.",
            .notAvailable => AuthenticationAvailability.notAvailable.message(),
            .notEnrolled => AuthenticationAvailability.notEnrolled.message(),
            .lockout => AuthenticationAvailability.lockout.message(),
            .passcodeNotSet => AuthenticationAvailability.passcodeNotSet.message(),
            .other => "Authentication failed.",
        };
    }
};

/// How an evaluation ended.
pub const AuthenticationResult = union(enum) {
    const Self = @This();

    /// The owner proved who they are.
    succeeded,
    /// It did not succeed, and why.
    failed: AuthenticationFailure,
};

/// One platform's authentication. Every pointer runs on the UI thread; a
/// request's reply lands on the platform's own thread, and the backend wakes
/// the window (`FrameClock.wake`) once it has.
pub const AuthenticationBackend = struct {
    const Self = @This();

    /// Asks whether `policy` can be evaluated now, prompting no one.
    ///
    /// - `policy`: the policy.
    /// - Returns: available, or why not.
    availability: *const fn (policy: AuthenticationPolicy) AuthenticationAvailability,
    /// Asks which biometry the device has, prompting no one.
    ///
    /// - Returns: the biometry; none when there is none.
    biometry_type: *const fn () BiometryType,
    /// Shows the system's prompt and returns at once; the request lives
    /// until `take` returns its result or `cancel` lets it go.
    ///
    /// - `policy`: what the owner must prove.
    /// - `reason`: why, in the prompt ("unlock vault"); UTF-8, not empty.
    /// - `fallback_title`: the fallback button's title (`localizedFallbackTitle`):
    ///   null for the system's ("Use Password…"), empty to hide it.
    /// - Returns: the request, or null when it could not start.
    begin: *const fn (policy: AuthenticationPolicy, reason: []const u8, fallback_title: ?[]const u8) ?*anyopaque,
    /// Takes a request's result once it has landed, freeing the request.
    ///
    /// - `request`: what `begin` returned.
    /// - Returns: the result, or null while the prompt is still up (the request lives on).
    take: *const fn (request: *anyopaque) ?AuthenticationResult,
    /// Closes a request's prompt and lets the request go: it is freed when
    /// its reply lands, never read again by the caller.
    ///
    /// - `request`: what `begin` returned.
    cancel: *const fn (request: *anyopaque) void,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a failure says whether it was a cancel, and what happened" {
    try std.testing.expect(AuthenticationFailure.userCancel.isCancel());
    try std.testing.expect(!AuthenticationFailure.lockout.isCancel());
    try std.testing.expectEqualStrings("Not recognized.", AuthenticationFailure.failed.message());
    try std.testing.expectEqualStrings("Touch ID", BiometryType.touchId.label());
    try std.testing.expectEqualStrings(AuthenticationAvailability.lockout.message(), AuthenticationFailure.lockout.message());
}
