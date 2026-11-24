//! The look the media controls share (`VideoPlayerControls`,
//! `AudioPlayerControls`): white symbols and labels lit under the pointer, on
//! translucent gray pills, and times as a player shows them.

const std = @import("std");
const log = std.log.scoped(.ziggui_media_control_style);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The media controls' shared parts.
pub const MediaControlStyle = struct {
    const Self = @This();

    /// The ground of each group of controls: a translucent gray, lighter than
    /// a black picture and darker than a pale one, so white symbols read on
    /// any (a blur cannot see the picture, which the platform draws).
    pub const pill = renderer.Color.fromRgb8(72, 72, 72).withAlpha(0.75);

    /// The symbols' and labels' color.
    pub const ink = renderer.Color.white;

    /// The controls' height inside a group.
    pub const height: f32 = 30;

    /// A tappable symbol: white, lit under the pointer.
    ///
    /// - `icon`: the symbol.
    /// - `size`: its size.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    pub fn symbol(icon: renderer.Icon, size: f32, action: mod.Callback) mod.View {
        return Self.button(mod.HStack(.{mod.Icon(icon, size, ink)}), action);
    }

    /// A round button of the controls' height around `content`, lit under
    /// the pointer: what `symbol` and the audio bar's skips are drawn in.
    ///
    /// - `content`: what the button shows, centred.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    pub fn button(content: mod.View, action: mod.Callback) mod.View {
        return content
            .frame(height, height)
            .hoverFill(ink.withAlpha(0.15))
            .cornerRadius(height / 2)
            .onTapGesture(action);
    }

    /// A tappable label (the speed), white, lit under the pointer.
    ///
    /// - `text`: the label.
    /// - `action`: what a tap does.
    /// - Returns: the button.
    pub fn label(text: []const u8, action: mod.Callback) mod.View {
        return mod.Text(text).font(.footnote).fontWeight(.semibold).foregroundStyle(ink)
            .paddingInsets(.{ .leading = 8, .trailing = 8 })
            .frameHeight(height)
            .hoverFill(ink.withAlpha(0.15))
            .cornerRadius(height / 2)
            .onTapGesture(action);
    }

    /// A group of controls on its rounded ground.
    ///
    /// - `content`: the controls.
    /// - Returns: the group.
    pub fn group(content: mod.View) mod.View {
        return mod.StackBuilder.make(.horizontal, 0, .center, .{content})
            .paddingInsets(.{ .top = 6, .leading = 10, .bottom = 6, .trailing = 10 })
            .background(pill)
            .cornerRadius((height + 12) / 2);
    }

    /// The mute button's symbol: crossed out while muted or silent, one wave
    /// up to half volume, two above it.
    ///
    /// - `player`: the player.
    /// - Returns: the symbol.
    pub fn volumeIcon(player: *const mod.Player) renderer.Icon {
        if (player.muted or player.volume == 0) return .volumeX;
        return if (player.volume <= 0.5) .volume1 else .volume2;
    }

    /// A time as the controls show it: `m:ss`, or `h:mm:ss` from an hour.
    ///
    /// - `seconds`: the time.
    /// - Returns: the label, in the build arena.
    pub fn clock(seconds: f64) []const u8 {
        const allocator = mod.BuildScope.shared().allocator();
        // Clamped: a backend reporting an absurd time must not trap the cast.
        const longest: f64 = std.math.maxInt(u32);
        const whole: u64 = if (std.math.isFinite(seconds)) @intFromFloat(std.math.clamp(seconds, 0, longest)) else 0;
        if (whole >= 3600) return allocator.print("{d}:{d:0>2}:{d:0>2}", .{ whole / 3600, whole / 60 % 60, whole % 60 }) catch @panic("oom");
        return allocator.print("{d}:{d:0>2}", .{ whole / 60, whole % 60 }) catch @panic("oom");
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the controls' clock reads minutes, and hours from an hour" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    defer window.end();
    try std.testing.expectEqualStrings("0:04", MediaControlStyle.clock(4.9));
    try std.testing.expectEqualStrings("9:59", MediaControlStyle.clock(599));
    try std.testing.expectEqualStrings("1:02:03", MediaControlStyle.clock(3723));
    try std.testing.expectEqualStrings("0:00", MediaControlStyle.clock(std.math.nan(f64)));
    try std.testing.expectEqualStrings("1193046:28:15", MediaControlStyle.clock(1e30));
}
