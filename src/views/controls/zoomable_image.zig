//! A picture that zooms and pans, with an overlay drawn through its geometry.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_zoomable_image);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The picture a `ZoomableImage` shows.
pub const ZoomPicture = struct {
    const Self = @This();

    /// The pixels; borrowed for the frame.
    image: renderer.Image,
    /// The picture's identity for its texture (`GraphicsContext.picture`): its
    /// pixels' address, say.
    key: usize,
    /// Bumped when the pixels behind `key` change, so the texture uploads afresh.
    generation: u64 = 1,
    /// What the zoom chip says after the zoom level.
    fit_hint: []const u8 = "click to fit",
    /// Whether the zoom chip shows while zoomed or panned; an app that fits the
    /// picture its own way (a key, a menu) may leave it out.
    zoom_chip: bool = true,
};

/// What a `ZoomableImage`'s canvas draws with: the app's context and overlay,
/// the state and the picture, kept in the build arena for the frame.
///
/// - `T`: the overlay context's type.
/// - `overlay`: draws over the picture, given its geometry.
/// - Returns: the model type.
fn ZoomableImageModel(comptime T: type, comptime overlay: fn (*const T, *mod.GraphicsContext, mod.ZoomGeometry) std.mem.Allocator.Error!void) type {
    return struct {
        const Self = @This();

        /// The app's context for `overlay`.
        context: *const T,
        /// The zoom and pan, written back with the layout and the chip.
        state: *mod.ZoomState,
        /// The picture.
        picture: ZoomPicture,

        /// Lays the picture out at the state's zoom, draws it, the app's
        /// overlay over it, and while zoomed or panned the chip that fits it.
        ///
        /// - `self`: the model.
        /// - `graphics`: what it draws with.
        /// - `frame`: the view's frame.
        /// - Returns: nothing; propagates allocation failure.
        fn draw(self: *const Self, graphics: *mod.GraphicsContext, frame: renderer.Rect) std.mem.Allocator.Error!void {
            const image = self.picture.image;
            const geometry = self.state.layout(frame, @floatFromInt(image.width), @floatFromInt(image.height));
            // Only the part on screen takes gestures.
            self.state.clipVisible(graphics.context.visible);
            try graphics.picture(geometry.contentRect(), image, self.picture.key, self.picture.generation);
            try overlay(self.context, graphics, geometry);
            self.state.chip = null;
            if (self.state.isFit() or !self.picture.zoom_chip) return;
            const colors = graphics.context.theme.colors;
            const words = try graphics.print("{d:.0}% · {s}", .{ self.state.zoom * 100, self.picture.fit_hint });
            self.state.chip = try mod.CanvasMarkers.chip(graphics, frame, words, colors.label.withAlpha(0.72), colors.window_background);
        }
    };
}

/// A picture fitted to its frame, zoomed and panned by an app-owned
/// `ZoomState`, with an overlay the app draws through the layout's
/// `ZoomGeometry` (`at` maps the picture's pixels to the view). While zoomed or
/// panned a chip at its foot says how far; a click on it (`ZoomState.chipContains`)
/// should fit it again. `ZoomPicture.zoom_chip` false leaves the chip out. It fills the space it is offered and clips to it.
///
/// The gestures stay the app's, since what a drag or a click does on a picture
/// is its own: `ZoomState.panDrag` pans for an `.onDrag`, `ZoomState.wheel`
/// and `ZoomState.pinch` take the event loop's wheel turns and pinches, and a
/// press `ZoomState.chipContains` finds on the chip calls `ZoomState.fit` and
/// is consumed before it starts a drag. They act only on the visible part the
/// last frame drew; the view cannot see an overlay presented over it, so the
/// app passes no events while a sheet, alert or popover is up.
///
/// - `T`: the overlay context's type.
/// - `context`: what `overlay` gets back; must outlive the frame.
/// - `overlay`: draws over the picture, given its geometry.
/// - `state`: the zoom and pan; must outlive the frame.
/// - `picture`: what to show.
/// - Returns: the view.
pub fn ZoomableImage(comptime T: type, context: *const T, comptime overlay: fn (*const T, *mod.GraphicsContext, mod.ZoomGeometry) std.mem.Allocator.Error!void, state: *mod.ZoomState, picture: ZoomPicture) mod.View {
    const Model = ZoomableImageModel(T, overlay);
    const model = mod.BuildScope.shared().allocator().create(Model) catch @panic("oom");
    model.* = .{ .context = context, .state = state, .picture = picture };
    return mod.Canvas(Model, model, Model.draw).frameMaxWidth().frameMaxHeight().clipped();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
