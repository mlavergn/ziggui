//! Color: an RGBA color with f32 channels in the 0..1 range (straight/
//! non-premultiplied alpha), plus conversions and alpha compositing.

const std = @import("std");
const log = std.log.scoped(.ziggui_color);
const mod = @import("module.zig");

/// An RGBA color with f32 channels in 0..1, straight alpha.
pub const Color = struct {
    const Self = @This();

    /// Red, 0...1.
    r: f32 = 0,
    /// Green, 0...1.
    g: f32 = 0,
    /// Blue, 0...1.
    b: f32 = 0,
    /// Alpha, 0...1.
    a: f32 = 1,

    // -- named colors ---------------------------------------------------------

    /// Fully transparent black.
    pub const clear = Self{ .r = 0, .g = 0, .b = 0, .a = 0 };
    /// Opaque white.
    pub const white = Self{ .r = 1, .g = 1, .b = 1, .a = 1 };
    /// Opaque black.
    pub const black = Self{ .r = 0, .g = 0, .b = 0, .a = 1 };
    /// Fully transparent black.
    pub const transparent = Self{ .r = 0, .g = 0, .b = 0, .a = 0 };
    /// Opaque pure red.
    pub const red = Self{ .r = 1, .g = 0, .b = 0, .a = 1 };
    /// Opaque pure green.
    pub const green = Self{ .r = 0, .g = 1, .b = 0, .a = 1 };
    /// Opaque pure blue.
    pub const blue = Self{ .r = 0, .g = 0, .b = 1, .a = 1 };

    // -- constructors ---------------------------------------------------------

    /// An opaque color from channels in 0...1.
    ///
    /// - `red_channel`: red.
    /// - `green_channel`: green.
    /// - `blue_channel`: blue.
    /// - Returns: the color.
    pub fn rgb(red_channel: f32, green_channel: f32, blue_channel: f32) Self {
        return .{ .r = red_channel, .g = green_channel, .b = blue_channel, .a = 1 };
    }

    /// A color from channels in 0...1.
    ///
    /// - `red_channel`: red.
    /// - `green_channel`: green.
    /// - `blue_channel`: blue.
    /// - `alpha_channel`: alpha.
    /// - Returns: the color.
    pub fn rgba(red_channel: f32, green_channel: f32, blue_channel: f32, alpha_channel: f32) Self {
        return .{ .r = red_channel, .g = green_channel, .b = blue_channel, .a = alpha_channel };
    }

    /// An opaque color from 8-bit channels.
    ///
    /// - `red_channel`: red.
    /// - `green_channel`: green.
    /// - `blue_channel`: blue.
    /// - Returns: the color.
    pub fn fromRgb8(red_channel: u8, green_channel: u8, blue_channel: u8) Self {
        return Self.fromRgba8(red_channel, green_channel, blue_channel, 255);
    }

    /// Opaque color from hue, saturation and value, each 0...1.
    ///
    /// - `hue`: the hue (wraps).
    /// - `saturation`: the saturation.
    /// - `value`: the value (brightness).
    /// - Returns: the color.
    pub fn fromHsv(hue: f32, saturation: f32, value: f32) Self {
        const sector_position = (hue - @floor(hue)) * 6;
        const sector: u32 = @intFromFloat(@floor(sector_position));
        const fraction = sector_position - @floor(sector_position);
        const low = value * (1 - saturation);
        const falling = value * (1 - saturation * fraction);
        const rising = value * (1 - saturation * (1 - fraction));
        const channels: [3]f32 = switch (sector % 6) {
            0 => .{ value, rising, low },
            1 => .{ falling, value, low },
            2 => .{ low, value, rising },
            3 => .{ low, falling, value },
            4 => .{ rising, low, value },
            else => .{ value, low, falling },
        };
        return .{ .r = channels[0], .g = channels[1], .b = channels[2], .a = 1 };
    }

    /// A color from 8-bit channels.
    ///
    /// - `red_channel`: red.
    /// - `green_channel`: green.
    /// - `blue_channel`: blue.
    /// - `alpha_channel`: alpha.
    /// - Returns: the color.
    pub fn fromRgba8(red_channel: u8, green_channel: u8, blue_channel: u8, alpha_channel: u8) Self {
        return .{
            .r = @as(f32, @floatFromInt(red_channel)) / 255.0,
            .g = @as(f32, @floatFromInt(green_channel)) / 255.0,
            .b = @as(f32, @floatFromInt(blue_channel)) / 255.0,
            .a = @as(f32, @floatFromInt(alpha_channel)) / 255.0,
        };
    }

    /// 0xRRGGBB, alpha = 1.
    ///
    /// - `value`: the packed color.
    /// - Returns: the color.
    pub fn hex(value: u24) Self {
        return Self.fromRgb8(
            @intCast((value >> 16) & 0xFF),
            @intCast((value >> 8) & 0xFF),
            @intCast(value & 0xFF),
        );
    }

    /// 0xRRGGBBAA.
    ///
    /// - `value`: the packed color.
    /// - Returns: the color.
    pub fn hexa(value: u32) Self {
        return Self.fromRgba8(
            @intCast((value >> 24) & 0xFF),
            @intCast((value >> 16) & 0xFF),
            @intCast((value >> 8) & 0xFF),
            @intCast(value & 0xFF),
        );
    }

    /// Parse "#RGB", "#RRGGBB", or "#RRGGBBAA" (leading '#' optional).
    ///
    /// - `text`: the color's text.
    /// - Returns: the color; `error.InvalidColor` (or a parse error) when the
    ///   text is not one of those forms.
    pub fn parse(text: []const u8) !Self {
        const digits = if (text.len > 0 and text[0] == '#') text[1..] else text;
        switch (digits.len) {
            3 => {
                const red_channel = try Self.hexDigit(digits[0]);
                const green_channel = try Self.hexDigit(digits[1]);
                const blue_channel = try Self.hexDigit(digits[2]);
                return Self.fromRgb8(red_channel * 17, green_channel * 17, blue_channel * 17); // 0xF -> 0xFF
            },
            6 => return Self.hex(try std.fmt.parseInt(u24, digits, 16)),
            8 => return Self.hexa(try std.fmt.parseInt(u32, digits, 16)),
            else => return error.InvalidColor,
        }
    }

    // -- conversions ----------------------------------------------------------

    /// The color as 8-bit channels, clamped and rounded.
    ///
    /// - `self`: the color.
    /// - Returns: the 8-bit channels.
    pub fn toRgba8(self: *const Self) mod.Rgba8 {
        return .{
            .r = Self.channelByte(self.r),
            .g = Self.channelByte(self.g),
            .b = Self.channelByte(self.b),
            .a = Self.channelByte(self.a),
        };
    }

    // -- operations -----------------------------------------------------------

    /// The color with its alpha replaced.
    ///
    /// - `self`: the color.
    /// - `alpha`: the new alpha.
    /// - Returns: the color.
    pub fn withAlpha(self: *const Self, alpha: f32) Self {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = alpha };
    }

    /// Multiply existing alpha by `factor` (for `.opacity()` modifiers).
    ///
    /// - `self`: the color.
    /// - `factor`: the alpha multiplier.
    /// - Returns: the color.
    pub fn multiplyAlpha(self: *const Self, factor: f32) Self {
        return self.withAlpha(self.a * factor);
    }

    /// Lighten toward white by `amount` (0..1), preserving alpha. Used for the
    /// top sheen of "liquid glass" controls.
    ///
    /// - `self`: the color.
    /// - `amount`: how far toward white.
    /// - Returns: the color.
    pub fn lighten(self: *const Self, amount: f32) Self {
        return .{
            .r = self.r + (1 - self.r) * amount,
            .g = self.g + (1 - self.g) * amount,
            .b = self.b + (1 - self.b) * amount,
            .a = self.a,
        };
    }

    /// Darken toward black by `amount` (0..1), preserving alpha.
    ///
    /// - `self`: the color.
    /// - `amount`: how far toward black.
    /// - Returns: the color.
    pub fn darken(self: *const Self, amount: f32) Self {
        const keep = 1 - amount;
        return .{ .r = self.r * keep, .g = self.g * keep, .b = self.b * keep, .a = self.a };
    }

    /// Linear interpolation per channel; `progress` in 0..1.
    ///
    /// - `self`: the color at 0.
    /// - `other`: the color at 1.
    /// - `progress`: how far from `self` to `other`.
    /// - Returns: the color.
    pub fn lerp(self: *const Self, other: Self, progress: f32) Self {
        return .{
            .r = self.r + (other.r - self.r) * progress,
            .g = self.g + (other.g - self.g) * progress,
            .b = self.b + (other.b - self.b) * progress,
            .a = self.a + (other.a - self.a) * progress,
        };
    }

    /// Premultiplied-alpha form (rgb scaled by alpha).
    ///
    /// - `self`: the color.
    /// - Returns: the premultiplied color.
    pub fn premultiplied(self: *const Self) Self {
        return .{ .r = self.r * self.a, .g = self.g * self.a, .b = self.b * self.a, .a = self.a };
    }

    /// Source-over compositing: `self` painted on top of `destination`
    /// (straight alpha).
    ///
    /// - `self`: the source color.
    /// - `destination`: the color beneath.
    /// - Returns: the composite.
    pub fn over(self: *const Self, destination: Self) Self {
        const out_alpha = self.a + destination.a * (1 - self.a);
        if (out_alpha <= 0) return transparent;
        return .{
            .r = Self.compositeChannel(self.r, self.a, destination.r, destination.a, out_alpha),
            .g = Self.compositeChannel(self.g, self.a, destination.g, destination.a, out_alpha),
            .b = Self.compositeChannel(self.b, self.a, destination.b, destination.a, out_alpha),
            .a = out_alpha,
        };
    }

    /// Relative luminance (Rec. 709 weights) of the RGB, ignoring alpha.
    ///
    /// - `self`: the color.
    /// - Returns: the luminance, 0...1.
    pub fn luminance(self: *const Self) f32 {
        return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b;
    }

    /// Whether the color reads as dark (luminance under one half).
    ///
    /// - `self`: the color.
    /// - Returns: true when dark.
    pub fn isDark(self: *const Self) bool {
        return self.luminance() < 0.5;
    }

    /// Whether every channel is within `tolerance` of `other`'s.
    ///
    /// - `self`: the first color.
    /// - `other`: the second color.
    /// - `tolerance`: the largest difference allowed per channel.
    /// - Returns: true when the colors match.
    pub fn approxEql(self: *const Self, other: Self, tolerance: f32) bool {
        return @abs(self.r - other.r) <= tolerance and @abs(self.g - other.g) <= tolerance and
            @abs(self.b - other.b) <= tolerance and @abs(self.a - other.a) <= tolerance;
    }

    /// One channel of a source-over composite.
    ///
    /// - `source`: the source channel.
    /// - `source_alpha`: the source alpha.
    /// - `destination`: the destination channel.
    /// - `destination_alpha`: the destination alpha.
    /// - `out_alpha`: the composite's alpha.
    /// - Returns: the composite channel.
    fn compositeChannel(source: f32, source_alpha: f32, destination: f32, destination_alpha: f32, out_alpha: f32) f32 {
        return (source * source_alpha + destination * destination_alpha * (1 - source_alpha)) / out_alpha;
    }

    /// A 0...1 channel as a byte, clamped and rounded.
    ///
    /// - `channel`: the channel.
    /// - Returns: the byte.
    fn channelByte(channel: f32) u8 {
        const clamped = std.math.clamp(channel, 0.0, 1.0);
        return @intFromFloat(@round(clamped * 255.0));
    }

    /// The value of one hexadecimal digit.
    ///
    /// - `digit`: the character.
    /// - Returns: 0...15; `error.InvalidColor` when not a hex digit.
    fn hexDigit(digit: u8) !u8 {
        return switch (digit) {
            '0'...'9' => digit - '0',
            'a'...'f' => digit - 'a' + 10,
            'A'...'F' => digit - 'A' + 10,
            else => error.InvalidColor,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "fromHsv: primaries land where they should" {
    const red = mod.Color.fromHsv(0, 1, 1);
    try std.testing.expect(red.r == 1 and red.g == 0 and red.b == 0);
    const green = mod.Color.fromHsv(1.0 / 3.0, 1, 1);
    try std.testing.expect(green.g > 0.99 and green.r < 0.01);
}

test "Color: rgba8 round trip" {
    const color = mod.Color.fromRgba8(255, 128, 0, 255);
    const bytes = color.toRgba8();
    try std.testing.expectEqual(@as(u8, 255), bytes.r);
    try std.testing.expectEqual(@as(u8, 128), bytes.g);
    try std.testing.expectEqual(@as(u8, 0), bytes.b);
    try std.testing.expectEqual(@as(u8, 255), bytes.a);
}

test "Color: hex int constructors" {
    try std.testing.expect(mod.Color.hex(0xFF8000).approxEql(mod.Color.fromRgb8(255, 128, 0), 0.001));
    const color = mod.Color.hexa(0x11223344);
    try std.testing.expect(color.approxEql(mod.Color.fromRgba8(0x11, 0x22, 0x33, 0x44), 0.001));
}

test "Color: parse strings" {
    try std.testing.expect((try mod.Color.parse("#FF8000")).approxEql(mod.Color.fromRgb8(255, 128, 0), 0.001));
    try std.testing.expect((try mod.Color.parse("FF8000")).approxEql(mod.Color.fromRgb8(255, 128, 0), 0.001));
    try std.testing.expect((try mod.Color.parse("#f00")).approxEql(mod.Color.red, 0.001));
    try std.testing.expect((try mod.Color.parse("#80808080")).approxEql(mod.Color.fromRgba8(128, 128, 128, 128), 0.001));
    try std.testing.expectError(error.InvalidColor, mod.Color.parse("#xyz"));
    try std.testing.expectError(error.InvalidColor, mod.Color.parse("#12345"));
}

test "Color: withAlpha and multiplyAlpha" {
    const color = mod.Color.red.withAlpha(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), color.a);
    try std.testing.expectEqual(@as(f32, 0.25), color.multiplyAlpha(0.5).a);
}

test "Color: lerp midpoint" {
    const middle = mod.Color.black.lerp(mod.Color.white, 0.5);
    try std.testing.expect(middle.approxEql(mod.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1 }, 0.001));
}

test "Color: over compositing opaque on opaque" {
    // Opaque src completely covers dst.
    const result = mod.Color.red.over(mod.Color.blue);
    try std.testing.expect(result.approxEql(mod.Color.red, 0.001));
}

test "Color: over compositing transparent src keeps dst" {
    const result = mod.Color.transparent.over(mod.Color.blue);
    try std.testing.expect(result.approxEql(mod.Color.blue, 0.001));
}

test "Color: over compositing half alpha blends" {
    // 50% white over opaque black -> mid grey, fully opaque.
    const result = mod.Color.white.withAlpha(0.5).over(mod.Color.black);
    try std.testing.expect(result.approxEql(mod.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1 }, 0.001));
}

test "Color: premultiplied" {
    const premultiplied = mod.Color.white.withAlpha(0.5).premultiplied();
    try std.testing.expect(premultiplied.approxEql(mod.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.5 }, 0.001));
}

test "Color: luminance and isDark" {
    try std.testing.expect(mod.Color.black.isDark());
    try std.testing.expect(!mod.Color.white.isDark());
    try std.testing.expect(mod.Color.white.luminance() > 0.99);
}

test "Color: channelByte clamps and rounds" {
    const over_white = mod.Color{ .r = 2, .g = -1, .b = 0.5, .a = 1 };
    const bytes = over_white.toRgba8();
    try std.testing.expectEqual(@as(u8, 255), bytes.r);
    try std.testing.expectEqual(@as(u8, 0), bytes.g);
    try std.testing.expectEqual(@as(u8, 128), bytes.b);
}
