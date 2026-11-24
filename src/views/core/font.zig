//! The font a view asks for with `.font()`, SwiftUI's `Font`: a semantic
//! size of the theme's type scale, a size (`Font.system`), or a registered
//! family at a size (`Font.custom`).

const std = @import("std");
const log = std.log.scoped(.ziggui_font);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A family by name at a size, as `Font.custom` names it.
pub const CustomFont = struct {
    const Self = @This();

    /// The family's name: a `renderer.FontRegistry` family, or a bundled one.
    name: []const u8,

    /// The size, in points.
    size: f32,
};

/// What `.font()` takes: every `FontToken` by its own name (`.font(.body)`),
/// `.system(size)` or `.custom(name, size)`.
pub const Font = union(enum) {
    const Self = @This();

    /// `FontToken.largeTitle`.
    largeTitle,
    /// `FontToken.title`.
    title,
    /// `FontToken.title2`.
    title2,
    /// `FontToken.title3`.
    title3,
    /// `FontToken.headline`.
    headline,
    /// `FontToken.body`.
    body,
    /// `FontToken.callout`.
    callout,
    /// `FontToken.subheadline`.
    subheadline,
    /// `FontToken.footnote`.
    footnote,
    /// `FontToken.caption`.
    caption,
    /// `FontToken.caption2`.
    caption2,
    /// A family at a size.
    named: CustomFont,
    /// A size, in points, in the face around it.
    sized: f32,

    /// A family at a size, as SwiftUI's `Font.custom(_:size:)`.
    ///
    /// - `name`: the family's name; borrowed, so it must outlive the frame.
    /// - `size`: the size, in points.
    /// - Returns: the font.
    pub fn custom(name: []const u8, size: f32) Self {
        return .{ .named = .{ .name = name, .size = size } };
    }

    /// A size, in points, as SwiftUI's `Font.system(size:)`: the face, weight
    /// and monospace around it are kept.
    ///
    /// - `size`: the size, in points.
    /// - Returns: the font.
    pub fn system(size: f32) Self {
        return .{ .sized = size };
    }

    /// A semantic size as a font.
    ///
    /// - `semantic`: the size.
    /// - Returns: the font.
    pub fn of(semantic: mod.FontToken) Self {
        return switch (semantic) {
            inline else => |tag| @unionInit(Self, @tagName(tag), {}),
        };
    }

    /// The semantic size this font is.
    ///
    /// - `self`: the font.
    /// - Returns: the token, or null for a custom font.
    pub fn token(self: *const Self) ?mod.FontToken {
        return switch (self.*) {
            .named, .sized => null,
            inline else => |_, tag| @field(mod.FontToken, @tagName(tag)),
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

test "every font token is a view font of its own name" {
    inline for (@typeInfo(mod.FontToken).@"enum".field_names) |name| {
        const token = @field(mod.FontToken, name);
        const font = Font.of(token);
        try std.testing.expectEqual(token, font.token().?);
    }
    const custom = Font.custom("Serif", 15);
    try std.testing.expect(custom.token() == null);
    try std.testing.expect(Font.system(12).token() == null);
}

test "a custom font draws its view in the registered family's cache at its size" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const font_set = try renderer.FontSet.create(std.testing.allocator);
    defer font_set.destroy();
    defer renderer.FontRegistry.shared().reset();
    try renderer.FontRegistry.shared().register(std.testing.allocator, .{ .name = "Copy", .regular = renderer.TtfFont.inter_ttf });
    var context = environment.context();
    context.fonts = font_set;
    context.applyFontModifiers(mod.Text("a").font(.custom("Copy", 20)));
    try std.testing.expect(context.cache == font_set.familyCache("Copy", .{}));
    try std.testing.expectEqual(@as(f32, 20), context.font_size);
    // A child changing only its weight stays in the family.
    context.applyFontModifiers(mod.Text("b").fontWeight(.bold));
    try std.testing.expect(context.cache == font_set.familyCache("Copy", .{ .weight = .bold }));
}
