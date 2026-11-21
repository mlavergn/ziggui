//! A gallery card: a headline over a rounded group holding what it shows,
//! with the names of what it shows under it.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_card);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The card every gallery section is built of: its headline, the content on
/// the secondary ground in the theme's corner radius, and a names line
/// (`CardName`) under it.
pub const Card = struct {
    const Self = @This();

    /// The room around the content inside the card, in points.
    const inset: f32 = 14;

    /// A card.
    ///
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the card's headline.
    /// - `names`: what it shows, as code names it (`ziggui.Table`, a modifier
    ///   as `.popover`), drawn under it.
    /// - `content`: what it shows; wrapped before the card pads it, so its own
    ///   padding, frame and ground stay its own.
    /// - Returns: the card.
    pub fn view(theme: ziggui.Theme, title: []const u8, names: []const u8, content: ziggui.View) ziggui.View {
        return ziggui.VStack(.{
            ziggui.Text(title).font(.headline).frameMaxWidth().frameAlign(.leading),
            ziggui.VStack(.{
                ziggui.StackBuilder.make(.vertical, 0, .leading, .{content})
                    .frameMaxWidth()
                    .padding(inset)
                    .background(theme.colors.secondary_background)
                    .cornerRadius(theme.metrics.corner_radius)
                    .frameMaxWidth(),
                gallery.CardName.shared().view(names, theme.colors.secondary_label),
            }).spacing(4).frameMaxWidth(),
        }).spacing(8).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Card);
    // Nothing here does I/O to trace.
    _ = log;
}
