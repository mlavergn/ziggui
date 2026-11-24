//! The font families an app registered, by name, for every window and
//! headless frame of the process: `FontSet.familyCache` draws from them.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_registry);
const mod = @import("module.zig");

/// One style of a registered family.
const FaceStyle = enum {
    const Self = @This();

    /// Upright, regular weight.
    regular,
    /// Upright, bold.
    bold,
    /// Italic, regular weight.
    italic,
    /// Italic, bold.
    boldItalic,

    /// How many styles there are.
    const count = @typeInfo(Self).@"enum".field_names.len;

    /// The style a text style asks for.
    ///
    /// - `style`: the weight and italic asked for.
    /// - Returns: the face style.
    fn of(style: mod.FontStyle) Self {
        const heavy = switch (style.weight) {
            .semibold, .bold, .heavy, .black => true,
            else => false,
        };
        if (style.italic) return if (heavy) .boldItalic else .italic;
        return if (heavy) .bold else .regular;
    }
};

/// A registered family: its name and faces, and the bytes the faces read, all owned.
const RegisteredFamily = struct {
    const Self = @This();

    /// The family's name.
    name: []u8,

    /// Each style's face (heap-allocated, so `FontSet` can key on its
    /// address), or null where the family lacks it.
    faces: [FaceStyle.count]?*mod.TtfFont = @splat(null),

    /// Each face's bytes.
    bytes: [FaceStyle.count]?[]u8 = @splat(null),

    /// What it was allocated from.
    allocator: std.mem.Allocator,

    /// Frees the family.
    ///
    /// - `self`: the family.
    fn deinit(self: *Self) void {
        for (self.faces) |slot| if (slot) |kept| self.allocator.destroy(kept);
        for (self.bytes) |bytes| if (bytes) |kept| self.allocator.free(kept);
        self.allocator.free(self.name);
    }

    /// The face for a text style: the style itself, else regular.
    ///
    /// - `self`: the family.
    /// - `style`: the weight and italic asked for.
    /// - Returns: the face.
    fn face(self: *const Self, style: mod.FontStyle) *const mod.TtfFont {
        const wanted = FaceStyle.of(style);
        if (self.faces[@backingInt(wanted)]) |kept| return kept;
        // Bold italic falls back to italic, then bold, then regular.
        if (wanted == .boldItalic) {
            if (self.faces[@backingInt(FaceStyle.italic)]) |kept| return kept;
            if (self.faces[@backingInt(FaceStyle.bold)]) |kept| return kept;
        }
        return self.faces[@backingInt(FaceStyle.regular)].?;
    }
};

/// The process's registered font families. Register from the UI thread,
/// at any time; a view asks for one by name (`.font(.custom(name, size))`).
/// The bundled faces answer to `bundled_sans` and `bundled_mono` without
/// being registered. Registering a name again replaces the family for
/// new text, keeping the old faces in memory (glyph caches may still point
/// at them) until `reset`.
pub const FontRegistry = struct {
    const Self = @This();

    /// The bundled proportional family's name (Inter).
    pub const bundled_sans = "Inter";

    /// The bundled monospaced family's name (JetBrains Mono).
    pub const bundled_mono = "JetBrains Mono";

    /// The families, in the order registered.
    families: std.ArrayList(*RegisteredFamily) = .empty,

    /// Families a later registration replaced, kept alive until `reset`.
    retired: std.ArrayList(*RegisteredFamily) = .empty,

    /// What the two lists grow in: the first registration's allocator.
    list_allocator: ?std.mem.Allocator = null,

    /// The process's registry.
    var shared_registry: Self = .{};

    /// The process's registry.
    ///
    /// - Returns: the shared registry.
    pub fn shared() *Self {
        return &shared_registry;
    }

    /// Copies a family's bytes and parses each face, replacing a family of
    /// the same name. A face that does not parse fails the whole family,
    /// which is then not kept.
    ///
    /// - `self`: the registry.
    /// - `allocator`: where the family is kept until `reset`.
    /// - `family`: the family.
    /// - Returns: nothing; propagates allocation failure, `error.ReservedName`
    ///   for a bundled family's name, and a face's parse error.
    pub fn register(self: *Self, allocator: std.mem.Allocator, family: mod.FontFamily) !void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        if (Self.isBundled(family.name)) return error.ReservedName;
        const registered = try allocator.create(RegisteredFamily);
        registered.* = .{ .name = &.{}, .allocator = allocator };
        errdefer {
            registered.deinit();
            allocator.destroy(registered);
        }
        registered.name = try allocator.dupe(u8, family.name);
        const sources = [FaceStyle.count]?[]const u8{ family.regular, family.bold, family.italic, family.bold_italic };
        for (sources, 0..) |source, index| {
            const bytes = source orelse continue;
            const copy = try allocator.dupe(u8, bytes);
            registered.bytes[index] = copy;
            const parsed = try allocator.create(mod.TtfFont);
            registered.faces[index] = parsed;
            parsed.* = try mod.TtfFont.parse(copy);
        }
        const lists = self.list_allocator orelse allocator;
        self.list_allocator = lists;
        try self.families.ensureUnusedCapacity(lists, 1);
        if (self.indexOf(family.name)) |index| {
            try self.retired.ensureUnusedCapacity(lists, 1);
            self.retired.appendAssumeCapacity(self.families.items[index]);
            self.families.items[index] = registered;
        } else self.families.appendAssumeCapacity(registered);
    }

    /// Forgets every registered family and frees them: for tests and a
    /// process's end, once no `FontSet` draws with them.
    ///
    /// - `self`: the registry.
    pub fn reset(self: *Self) void {
        for (self.families.items) |family| Self.free(family);
        for (self.retired.items) |family| Self.free(family);
        if (self.list_allocator) |lists| {
            self.families.deinit(lists);
            self.retired.deinit(lists);
        }
        self.* = .{};
    }

    /// The face a family draws a style in.
    ///
    /// - `self`: the registry.
    /// - `name`: the family's name.
    /// - `style`: the weight and italic asked for.
    /// - Returns: the face, or null for a name not registered.
    pub fn face(self: *const Self, name: []const u8, style: mod.FontStyle) ?*const mod.TtfFont {
        const index = self.indexOf(name) orelse return null;
        return self.families.items[index].face(style);
    }

    /// Whether a name is a bundled family's.
    ///
    /// - `name`: the name.
    /// - Returns: true for `bundled_sans` and `bundled_mono`.
    pub fn isBundled(name: []const u8) bool {
        return std.mem.eql(u8, name, bundled_sans) or std.mem.eql(u8, name, bundled_mono);
    }

    /// Every family a view can name: the bundled two, then the registered ones in order.
    ///
    /// - `self`: the registry.
    /// - `allocator`: where the list goes (the build arena).
    /// - Returns: the names, borrowed from the registry until a family is replaced; propagates allocation failure.
    pub fn namesAlloc(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
        const names = try allocator.alloc([]const u8, 2 + self.families.items.len);
        names[0] = bundled_sans;
        names[1] = bundled_mono;
        for (self.families.items, 2..) |family, index| names[index] = family.name;
        return names;
    }

    /// How many families a view can name: the bundled two and the registered ones.
    ///
    /// - `self`: the registry.
    /// - Returns: the count.
    pub fn familyCount(self: *const Self) usize {
        return 2 + self.families.items.len;
    }

    /// A family's place in `namesAlloc`'s order, the bundled ones first.
    ///
    /// - `self`: the registry.
    /// - `name`: the family's name.
    /// - Returns: its place, or null for a name no family has.
    pub fn familyIndex(self: *const Self, name: []const u8) ?usize {
        if (std.mem.eql(u8, name, bundled_sans)) return 0;
        if (std.mem.eql(u8, name, bundled_mono)) return 1;
        return if (self.indexOf(name)) |index| index + 2 else null;
    }

    /// A family's name by its place in `namesAlloc`'s order, without allocating.
    ///
    /// - `self`: the registry.
    /// - `index`: the place.
    /// - Returns: the name, or null past the last.
    pub fn familyName(self: *const Self, index: usize) ?[]const u8 {
        return switch (index) {
            0 => bundled_sans,
            1 => bundled_mono,
            else => if (index - 2 < self.families.items.len) self.families.items[index - 2].name else null,
        };
    }

    /// Where a family sits in `families`.
    ///
    /// - `self`: the registry.
    /// - `name`: the family's name.
    /// - Returns: its index, or null.
    fn indexOf(self: *const Self, name: []const u8) ?usize {
        for (self.families.items, 0..) |family, index| if (std.mem.eql(u8, family.name, name)) return index;
        return null;
    }

    /// Frees a family and its record.
    ///
    /// - `family`: the family.
    fn free(family: *RegisteredFamily) void {
        const allocator = family.allocator;
        family.deinit();
        allocator.destroy(family);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "registry: a family registers, a missing style draws regular, a name is replaced, bad bytes are refused" {
    const allocator = std.testing.allocator;
    const registry = FontRegistry.shared();
    defer registry.reset();
    try registry.register(allocator, .{ .name = "Sans", .regular = mod.TtfFont.inter_ttf });
    const regular = registry.face("Sans", .{}).?;
    try std.testing.expect(registry.face("Sans", .{ .weight = .bold, .italic = true }).? == regular);
    try std.testing.expect(registry.face("Nope", .{}) == null);
    // Again under the same name: new text gets the new face.
    try registry.register(allocator, .{ .name = "Sans", .regular = mod.TtfFont.inter_ttf, .bold = mod.TtfFont.inter_ttf });
    try std.testing.expect(registry.face("Sans", .{}).? != regular);
    try std.testing.expect(registry.face("Sans", .{ .weight = .bold }).? != registry.face("Sans", .{}).?);
    try std.testing.expectError(error.InvalidFont, registry.register(allocator, .{ .name = "Broken", .regular = "not a font" }));
    try std.testing.expect(registry.face("Broken", .{}) == null);
    try std.testing.expectError(error.ReservedName, registry.register(allocator, .{ .name = FontRegistry.bundled_sans, .regular = mod.TtfFont.inter_ttf }));
    const names = try registry.namesAlloc(allocator);
    defer allocator.free(names);
    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("Sans", names[2]);
    try std.testing.expectEqual(@as(usize, 3), registry.familyCount());
    try std.testing.expectEqualStrings(FontRegistry.bundled_mono, registry.familyName(1).?);
    try std.testing.expect(registry.familyName(3) == null);
    try std.testing.expectEqual(@as(?usize, 2), registry.familyIndex("Sans"));
    try std.testing.expect(registry.familyIndex("Nope") == null);
}
