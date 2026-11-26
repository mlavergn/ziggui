//! The Forms & Settings section's Touch ID card: an `AuthenticationContext`
//! asked whether Touch ID can be used, two buttons that show the system's
//! prompt (Touch ID alone, its fallback button hidden; or Touch ID else the
//! login password, which the prompt's "Use Password…" asks for), Cancel
//! while it is up, and what the last prompt answered. The prompt is polled
//! every frame from `Gallery.body` (`update`), whatever section shows.
//! Headless there is no backend, so the card says Touch ID is not available.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_authentication_demo);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The Touch ID card and its context.
pub const AuthenticationDemo = struct {
    const Self = @This();

    /// The prompt.
    context: ziggui.AuthenticationContext,
    /// Whether `availability` and `biometry` have been read (on the card's first draw, then after each answer).
    checked: bool = false,
    /// Whether Touch ID alone can be used, as last read.
    availability: ziggui.AuthenticationAvailability = .notAvailable,
    /// Whether Touch ID or the login password can be used, as last read.
    owner_availability: ziggui.AuthenticationAvailability = .notAvailable,
    /// The Mac's biometry, as last read.
    biometry: ziggui.BiometryType = .none,
    /// What the last prompt answered; static text.
    outcome: []const u8 = "Not asked yet.",
    /// Whether the last prompt succeeded.
    succeeded: bool = false,

    /// A demo with nothing asked.
    ///
    /// - Returns: the demo.
    pub fn init() Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .context = ziggui.AuthenticationContext.init() };
        return self;
    }

    /// Closes a prompt still up.
    ///
    /// - `self`: the demo.
    pub fn deinit(self: *Self) void {
        self.context.deinit();
    }

    /// Takes the prompt's answer once it lands: call it every frame.
    ///
    /// - `self`: the demo.
    pub fn update(self: *Self) void {
        switch (self.context.poll()) {
            .idle, .waiting => return,
            .succeeded => {
                self.outcome = "Succeeded: the owner is here.";
                self.succeeded = true;
            },
            .failed => |failure| {
                self.outcome = failure.message();
                self.succeeded = false;
            },
        }
        self.context.reset();
        self.checked = false;
    }

    /// The card.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card's view.
    pub fn card(self: *Self, theme: ziggui.Theme) ziggui.View {
        const tokens = ziggui.BuildScope.shared().tokens();
        if (!self.checked) self.check();
        const waiting = self.context.isWaiting();
        const status = if (waiting) "Waiting for the prompt…" else self.outcome;
        const status_color = if (waiting) tokens.secondary_label else if (self.succeeded) tokens.added else tokens.secondary_label;
        const content = ziggui.VStack(.{
            ziggui.HStack(.{
                ziggui.Icon(.fingerprint, 22, if (self.availability == .available) tokens.accent else tokens.secondary_label),
                ziggui.WrappedText(if (self.availability == .available and self.biometry != .touchId) "Biometrics are available on this device." else self.availability.message()).frameMaxWidth().frameAlign(.leading),
            }).spacing(10).frameMaxWidth(),
            ziggui.HStack(.{
                ziggui.ButtonRoled("Touch ID", .prominent, ziggui.Callback.init(Self, self, Self.askBiometrics)).disabled(waiting or self.availability != .available).help("Show the Touch ID prompt, with no password button"),
                ziggui.ButtonRoled("Touch ID or Password", .normal, ziggui.Callback.init(Self, self, Self.askOwner)).disabled(waiting or self.owner_availability != .available).help("Show the prompt, with the login password as its fallback"),
                ziggui.ButtonRoled("Cancel", .normal, ziggui.Callback.init(Self, self, Self.cancel)).disabled(!waiting).help("Close the prompt"),
            }).spacing(8),
            ziggui.Text(status).font(.callout).foregroundStyle(status_color),
        }).spacing(12).alignment(.leading).frameMaxWidth();
        return gallery.Card.view(theme, "Touch ID", "ziggui.AuthenticationContext · ziggui.AuthenticationPolicy · ziggui.BiometryType", content);
    }

    /// The Touch ID button: the prompt, Touch ID alone.
    ///
    /// - `self`: the demo.
    fn askBiometrics(self: *Self) void {
        // No fallback button: under `.biometrics` it would only hand the
        // owner back here, and the card has no password of its own.
        self.context.localized_fallback_title = "";
        self.context.evaluate(.biometrics, "show the gallery's Touch ID card");
    }

    /// The Touch ID or Password button: the prompt, the login password its fallback.
    ///
    /// - `self`: the demo.
    fn askOwner(self: *Self) void {
        // The system's "Use Password…", which asks for the login password in the prompt.
        self.context.localized_fallback_title = null;
        self.context.evaluate(.deviceOwner, "show the gallery's Touch ID card");
    }

    /// The Cancel button: closes the prompt.
    ///
    /// - `self`: the demo.
    fn cancel(self: *Self) void {
        self.context.invalidate();
        self.outcome = "Cancelled by the app.";
        self.succeeded = false;
    }

    /// Reads what can be used, prompting no one.
    ///
    /// - `self`: the demo.
    fn check(self: *Self) void {
        self.availability = self.context.canEvaluate(.biometrics);
        self.owner_availability = self.context.canEvaluate(.deviceOwner);
        self.biometry = self.context.biometryType();
        self.checked = true;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "authentication demo: asks, shows the answer, and reads again" {
    const fake = ziggui.TestAuthentication.install();
    defer fake.uninstall();
    var demo = AuthenticationDemo.init();
    defer demo.deinit();
    demo.check();
    try std.testing.expectEqual(ziggui.AuthenticationAvailability.available, demo.availability);

    demo.askBiometrics();
    try std.testing.expect(fake.isUp());
    try std.testing.expectEqual(ziggui.AuthenticationPolicy.biometrics, fake.policy);
    try std.testing.expectEqualStrings("", fake.fallbackTitle().?);
    fake.answer(.succeeded);
    demo.update();
    try std.testing.expect(demo.succeeded and !demo.checked);

    demo.askOwner();
    try std.testing.expectEqual(ziggui.AuthenticationPolicy.deviceOwner, fake.policy);
    try std.testing.expectEqual(@as(?[]const u8, null), fake.fallbackTitle());
    demo.cancel();
    try std.testing.expect(!fake.isUp() and !demo.succeeded);
    try std.testing.expectEqualStrings("Cancelled by the app.", demo.outcome);
}
