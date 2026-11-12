//! The view engine's pipeline tests: views built, lowered, laid out, painted
//! and tapped through `ViewRenderer` and `PointerInput`, as an app runs them.

const std = @import("std");
const log = std.log.scoped(.ziggui_view_engine_test);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Counts the taps `Callback.action` handlers make.
const Counter = struct {
    const Self = @This();

    /// Primary taps.
    var value: u32 = 0;

    /// Secondary taps.
    var secondary: u32 = 0;

    /// Counts a primary tap.
    fn increment() void {
        value += 1;
    }

    /// Counts a secondary tap.
    fn incrementSecondary() void {
        secondary += 1;
    }
};

/// Records an armed drag's travel and its end.
const DragProbe = struct {
    const Self = @This();

    /// How far the pointer moved down.
    var travel: f32 = 0;

    /// How many times the drag ended.
    var ended: u32 = 0;

    /// Adds a move's vertical delta.
    ///
    /// - `delta_y`: how far the pointer moved down.
    fn move(_: ?*anyopaque, _: f32, delta_y: f32) void {
        travel += delta_y;
    }

    /// Counts the drag's end.
    fn end() void {
        ended += 1;
    }
};

/// Builders and probes the tests share.
const Fixtures = struct {
    const Self = @This();

    /// A row for `ForEach`.
    ///
    /// - `string`: the row's text.
    /// - Returns: the row.
    fn makeRow(string: []const u8) mod.View {
        return mod.Text(string);
    }

    /// A grid cell of a color, 20 points tall.
    ///
    /// - `cell_color`: the cell's color.
    /// - Returns: the cell.
    fn gridCell(cell_color: renderer.Color) mod.View {
        return mod.Rectangle(cell_color).frameHeight(20);
    }

    /// The coverage width of the first glyph a canvas holds.
    ///
    /// - `canvas`: the commands.
    /// - Returns: the width, or null without a glyph.
    fn firstGlyphCoverageWidth(canvas: *const renderer.Canvas) ?u32 {
        for (canvas.commands.items) |command| {
            if (command == .glyph) return command.glyph.coverage.width;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: modifiers chain and set fields" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const view = mod.Text("Hi").padding(8).foreground(renderer.Color.red).font(.title).opacity(0.5);
    try std.testing.expectEqual(renderer.EdgeInsets.all(8), view.modifiers.padding.?);
    try std.testing.expectEqual(renderer.Color.red, view.modifiers.foreground.?);
    try std.testing.expectEqual(mod.FontToken.title, view.modifiers.font.?);
    try std.testing.expectEqual(@as(f32, 0.5), view.modifiers.opacity);
}

test "view: frameMinWidth floors a filling frame's width, and a wider proposal still fills" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const tree = mod.Text("Hi").frameMaxWidth().frameMinWidth(300);
    try std.testing.expectApproxEqAbs(@as(f32, 300), (try mod.ViewRenderer.measure(&context, tree, .{ .width = 200, .height = null })).width, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 500), (try mod.ViewRenderer.measure(&context, tree, .{ .width = 500, .height = null })).width, 0.5);
}

test "view: fixedSize keeps a Toggle at its ideal width beside a Spacer" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    var on = renderer.State(bool).init(std.testing.allocator, false);
    defer on.deinit();
    const ideal = (try mod.ViewRenderer.measure(&context, mod.Toggle("Amend", on.binding()), .unspecified)).width;
    // Alone it fills what it is offered; fixed, it stays at its ideal width.
    try std.testing.expectApproxEqAbs(@as(f32, 400), (try mod.ViewRenderer.measure(&context, mod.Toggle("Amend", on.binding()), .{ .width = 400, .height = null })).width, 0.5);
    try std.testing.expectApproxEqAbs(ideal, (try mod.ViewRenderer.measure(&context, mod.Toggle("Amend", on.binding()).fixedSize(), .{ .width = 400, .height = null })).width, 0.5);
    // In a row the Spacer takes all the slack, so the switch stays by its label.
    const row = mod.HStack(.{ mod.Toggle("Amend", on.binding()).fixedSize(), mod.Spacer() });
    try mod.ViewRenderer.render(&context, row, .{ .x = 0, .y = 0, .width = 400, .height = 30 }, &canvas);
    try std.testing.expectEqual(@as(usize, 1), environment.hits.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), environment.hits.items[0].rect.x, 0.5);
    try std.testing.expectApproxEqAbs(ideal, environment.hits.items[0].rect.width, 0.5);
}

test "view: VStack measures to sum of child heights plus spacing" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const tree = mod.VStack(.{ mod.Text("AAAA"), mod.Text("B") }).spacing(10);
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(environment.context().theme.typography.body.size);
    try std.testing.expectApproxEqAbs(2 * line_height + 10, size.height, 0.5);
    // width = wider of the two lines (the 4-char line)
    const four_width = renderer.TextShaper.init(&environment.font.face).measureLineWidth("AAAA", context.theme.typography.body.size);
    try std.testing.expectApproxEqAbs(four_width, size.width, 0.5);
}

test "view: Rectangle fills its frame with color" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.Rectangle(renderer.Color.red);
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 20, .height = 20 }, &canvas);

    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    try std.testing.expect(framebuffer.at(10, 10).approxEql(renderer.Color.red, 0.02));
}

test "view: padding insets the content" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // A red rectangle padded 5 inside a 20x20 frame -> red only in the inner 10x10.
    const tree = mod.Rectangle(renderer.Color.red).padding(5);
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 20, .height = 20 }, &canvas);

    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    try std.testing.expect(framebuffer.at(10, 10).approxEql(renderer.Color.red, 0.02)); // inside
    try std.testing.expect(framebuffer.at(1, 1).approxEql(renderer.Color.white, 0.05)); // padding margin
}

test "view: background paints behind text" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.Text("A").padding(4).background(renderer.Color.blue);
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    try mod.ViewRenderer.render(&context, tree, renderer.Rect.fromOriginSize(.{}, size), &canvas);
    // first command should be the background fill
    try std.testing.expect(canvas.commands.items[0] == .fillRoundedRect);
    try std.testing.expect(canvas.commands.items[0].fillRoundedRect.color.approxEql(renderer.Color.blue, 0.02));
}

test "view: Button registers a hit region and tap fires the action" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();

    Counter.value = 0;
    const tree = mod.Button("Click", mod.Callback.action(Counter.increment));
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    try mod.ViewRenderer.render(&context, tree, renderer.Rect.fromOriginSize(.{}, size), &canvas);

    try std.testing.expectEqual(@as(usize, 1), environment.hits.items.len);
    // tap inside -> fires
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = size.width / 2, .y = size.height / 2 }));
    try std.testing.expectEqual(@as(u32, 1), Counter.value);
    // tap outside -> nothing
    try std.testing.expect(!mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 9999, .y = 9999 }));
    try std.testing.expectEqual(@as(u32, 1), Counter.value);
}

test "view: disabled view's tap region does not fire" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    Counter.value = 0;
    const tree = mod.Rectangle(renderer.Color.red).frame(20, 20).onTap(mod.Callback.action(Counter.increment)).disabled(true);
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 20, .height = 20 }, &canvas);
    try std.testing.expect(!mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 0), Counter.value);
}

test "view: a right-click handler fires on secondary only, a tap on primary only" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    Counter.value = 0;
    const tree = mod.Rectangle(renderer.Color.red).frame(20, 20).onTap(mod.Callback.action(Counter.increment)).onSecondaryTap(mod.Callback.action(Counter.incrementSecondary));
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 20, .height = 20 }, &canvas);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 1), Counter.value);
    try std.testing.expectEqual(@as(u32, 0), Counter.secondary);
    try std.testing.expect(mod.PointerInput.shared().secondaryTap(environment.hits.items, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 1), Counter.value);
    try std.testing.expectEqual(@as(u32, 1), Counter.secondary);
    try std.testing.expect(!mod.PointerInput.shared().secondaryTap(environment.hits.items, .{ .x = 99, .y = 99 }));
}

test "view: a tap handler can arm a drag from its own press; the end hook fires once" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    DragProbe.travel = 0;
    DragProbe.ended = 0;
    const tree = mod.Rectangle(renderer.Color.red).frame(20, 20).onTap(mod.Callback.action(struct {
        fn arm() void {
            mod.PointerInput.shared().armDrag(.{ .function = DragProbe.move });
        }
    }.arm));
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 20, .height = 20 }, &canvas);
    mod.PointerInput.shared().setDragEndHook(DragProbe.end);
    defer mod.PointerInput.shared().setDragEndHook(null);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 10, .y = 4 }));
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 10, .y = 14 });
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 10, .y = 19 });
    try std.testing.expectEqual(@as(f32, 15), DragProbe.travel);
    mod.PointerInput.shared().endDrag();
    mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(@as(u32, 1), DragProbe.ended);
}

test "view: ForEach expands into stack children" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const items = [_][]const u8{ "a", "b", "c" };
    const tree = mod.VStack(.{mod.ForEach(&items, Fixtures.makeRow)});
    try std.testing.expectEqual(@as(usize, 3), tree.kind.stack.children.len);
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    try std.testing.expect(size.height > 0);
}

test "view: HStack lays children left to right" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const tree = mod.HStack(.{ mod.Rectangle(renderer.Color.red).frame(10, 10), mod.Rectangle(renderer.Color.blue).frame(10, 10) }).spacing(5);
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    try std.testing.expectApproxEqAbs(@as(f32, 25), size.width, 0.01); // 10 + 5 + 10
    try std.testing.expectApproxEqAbs(@as(f32, 10), size.height, 0.01);
}

test "view: fmt allocates state-derived text in the build arena" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const text = mod.BuildScope.shared().print("Count: {d}", .{42});
    try std.testing.expectEqualStrings("Count: 42", text);
}

test "view: Toggle reflects and mutates its binding" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var value = renderer.State(bool).init(std.testing.allocator, false);
    defer value.deinit();

    // off: little/no accent in the switch
    var off_framebuffer = try environment.renderToFramebuffer(&context, mod.Toggle("", value.binding()).frame(60, 30), .{ .x = 0, .y = 0, .width = 60, .height = 30 }, 60, 30);
    defer off_framebuffer.deinit();
    const off_blue = mod.TestEnvironment.countBlue(&off_framebuffer);

    // tapping flips the binding
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 45, .y = 15 }));
    try std.testing.expect(value.get());

    // on: accent track now visible
    environment.hits.clearRetainingCapacity();
    var on_framebuffer = try environment.renderToFramebuffer(&context, mod.Toggle("", value.binding()).frame(60, 30), .{ .x = 0, .y = 0, .width = 60, .height = 30 }, 60, 30);
    defer on_framebuffer.deinit();
    try std.testing.expect(mod.TestEnvironment.countBlue(&on_framebuffer) > off_blue + 20);
}

test "view: Slider sets value from tap position" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var value = renderer.State(f32).init(std.testing.allocator, 0);
    defer value.deinit();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.Slider(value.binding(), 0, 1), .{ .x = 0, .y = 0, .width = 100, .height = 20 }, 100, 20);
    defer framebuffer.deinit();
    // tap near the right end -> value near max
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 95, .y = 10 }));
    try std.testing.expect(value.get() > 0.8);
    // tap near the left -> value near min
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 5, .y = 10 }));
    try std.testing.expect(value.get() < 0.2);
}

test "view: Slider follows mouse drag after press" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var value = renderer.State(f32).init(std.testing.allocator, 0);
    defer value.deinit();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.Slider(value.binding(), 0, 1), .{ .x = 0, .y = 0, .width = 100, .height = 20 }, 100, 20);
    defer framebuffer.deinit();

    // Press near the left arms a drag.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 5, .y = 10 }));
    try std.testing.expect(value.get() < 0.2);
    // Dragging the mouse right (button held) tracks the knob.
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 95, .y = 10 });
    try std.testing.expect(value.get() > 0.8);
    // Dragging past the right edge clamps to max, not beyond.
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 500, .y = 10 });
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), value.get(), 0.001);
    // After release, a stray move no longer changes the value.
    mod.PointerInput.shared().endDrag();
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 5, .y = 10 });
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), value.get(), 0.001);
}

test "view: Icon paints a glyph from the bundled set" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.Icon(.heart, 24, renderer.Color.red), .{ .x = 0, .y = 0, .width = 24, .height = 24 }, 24, 24);
    defer framebuffer.deinit();
    // Some red pixels were inked somewhere in the box.
    var inked: usize = 0;
    var y: u32 = 0;
    while (y < 24) : (y += 1) {
        var x: u32 = 0;
        while (x < 24) : (x += 1) {
            if (framebuffer.at(x, y).r > 0.3) inked += 1;
        }
    }
    try std.testing.expect(inked > 0);
}

test "view: ButtonIcon reserves space for its leading glyph" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const plain = try mod.ViewRenderer.measure(&context, mod.Button("Think", mod.Callback.action(Counter.increment)), .unspecified);
    const iconed = try mod.ViewRenderer.measure(&context, mod.ButtonIcon("Think", .sparkles, mod.Callback.action(Counter.increment)), .unspecified);
    try std.testing.expectEqual(plain.height, iconed.height);
    try std.testing.expectEqual(plain.width + mod.ControlMetrics.button_icon_size + mod.ControlMetrics.button_icon_gap, iconed.width);
}

test "view: glassEffect draws the theme's glass surface behind content" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // The macOS painter's glass surface starts with a backdrop frost.
    try mod.ViewRenderer.render(&context, mod.Empty().frame(80, 28).glassEffect(), .{ .x = 0, .y = 0, .width = 80, .height = 28 }, &canvas);
    var saw_blur = false;
    for (canvas.commands.items) |command| {
        if (command == .blurRect) saw_blur = true;
    }
    try std.testing.expect(saw_blur);
}

test "view: SidebarStyled prominent selection is the accent row" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const items = [_]mod.SidebarItem{
        .{ .label = "New Chat", .detail = "just now" },
        .{ .label = "Older", .detail = "4h ago" },
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.SidebarStyled(&items, selection.binding(), .prominent), .{ .x = 0, .y = 0, .width = 220, .height = 200 }, &canvas);
    var has_accent_row = false;
    for (canvas.commands.items) |command| {
        if (command == .fillRoundedRect and command.fillRoundedRect.color.approxEql(context.theme.colors.selection, 0.05)) has_accent_row = true;
    }
    try std.testing.expect(has_accent_row);
}

test "view: IconButton fires its callback on tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const TapCounter = struct {
        const Self = @This();
        var hits: u32 = 0;
        fn tap(_: ?*anyopaque) void {
            hits += 1;
        }
    };
    TapCounter.hits = 0;
    const callback = mod.Callback{ .function = TapCounter.tap };
    var framebuffer = try environment.renderToFramebuffer(&context, mod.IconButton(.trash, 20, callback), .{ .x = 0, .y = 0, .width = 32, .height = 32 }, 32, 32);
    defer framebuffer.deinit();
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 16, .y = 16 }));
    try std.testing.expectEqual(@as(u32, 1), TapCounter.hits);
}

test "view: Icon paints nothing when no icon cache is wired" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    context.icon_cache = null; // simulate an app that didn't wire the icon font
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.Icon(.heart, 24, renderer.Color.red), .{ .x = 0, .y = 0, .width = 24, .height = 24 }, &canvas);
    // No glyph command emitted for the icon.
    for (canvas.commands.items) |command| try std.testing.expect(command != .glyph);
}

test "view: Stepper increments and clamps" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var value = renderer.State(i64).init(std.testing.allocator, 5);
    defer value.deinit();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.Stepper("Count", value.binding(), 0, 6, 1), .{ .x = 0, .y = 0, .width = 120, .height = 28 }, 120, 28);
    defer framebuffer.deinit();
    // the chevron column hugs the trailing edge: up = top half increments
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 110, .y = 6 }));
    try std.testing.expectEqual(@as(i64, 6), value.get());
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 110, .y = 6 })); // clamp at max
    try std.testing.expectEqual(@as(i64, 6), value.get());
    // down = bottom half decrements
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 110, .y = 22 }));
    try std.testing.expectEqual(@as(i64, 5), value.get());
}

test "view: ProgressView fills proportionally" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.ProgressView(0.5), .{ .x = 0, .y = 0, .width = 100, .height = 20 }, 100, 20);
    defer framebuffer.deinit();
    try std.testing.expect(framebuffer.at(10, 10).b > framebuffer.at(10, 10).r); // left half accent
    try std.testing.expect(!(framebuffer.at(90, 10).b > framebuffer.at(90, 10).r + 0.2)); // right half unfilled
}

test "view: LinearGradient interpolates across its frame" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var framebuffer = try environment.renderToFramebuffer(&context, mod.LinearGradient(renderer.Color.red, renderer.Color.blue, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }), .{ .x = 0, .y = 0, .width = 100, .height = 10 }, 100, 10);
    defer framebuffer.deinit();
    try std.testing.expect(framebuffer.at(2, 5).r > 0.8);
    try std.testing.expect(framebuffer.at(97, 5).b > 0.8);
}

test "view: Image blits pixels" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    // 4x4 opaque green image; an Image keeps its intrinsic size by default.
    var pixels: [64]u8 = undefined;
    for (0..16) |index| pixels[index * 4 ..][0..4].* = .{ 0, 255, 0, 255 };
    const image = renderer.Image{ .width = 4, .height = 4, .pixels = &pixels };
    var framebuffer = try environment.renderToFramebuffer(&context, mod.Image(image), .{ .x = 0, .y = 0, .width = 4, .height = 4 }, 4, 4);
    defer framebuffer.deinit();
    try std.testing.expect(framebuffer.at(2, 2).approxEql(renderer.Color.green, 0.02));
}

test "view: Label draws an icon swatch then the title" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.Label("Wi-Fi", renderer.Color.blue);
    const size = try mod.ViewRenderer.measure(&context, tree, .unspecified);
    try mod.ViewRenderer.render(&context, tree, renderer.Rect.fromOriginSize(.{}, size), &canvas);
    try std.testing.expect(canvas.commands.items[0] == .fillRoundedRect); // the icon swatch
    try std.testing.expect(canvas.commands.items[0].fillRoundedRect.color.approxEql(renderer.Color.blue, 0.02));
    try std.testing.expect(canvas.count() > 1); // plus glyphs
}

test "view: WrappedText measures taller at a narrow width than a wide one" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const sentence = "the quick brown fox jumps over the lazy dog";
    const pixel_size = context.theme.typography.body.size;
    const full = renderer.TextShaper.init(&environment.font.face).measureLineWidth(sentence, pixel_size);
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(pixel_size);

    const tree = mod.WrappedText(sentence);
    // proposed half the single-line width -> wraps to at least two lines
    const narrow = try mod.ViewRenderer.measure(&context, tree, .{ .width = full / 2, .height = null });
    try std.testing.expect(narrow.height >= 2 * line_height - 0.5);
    try std.testing.expect(narrow.width <= full / 2 + 0.5);
    // proposed the full width -> a single line
    const wide = try mod.ViewRenderer.measure(&context, tree, .{ .width = full + 10, .height = null });
    try std.testing.expectApproxEqAbs(line_height, wide.height, 0.5);
}

test "view: WrappedText breaks on an explicit newline" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const pixel_size = context.theme.typography.body.size;
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(pixel_size);
    const size = try mod.ViewRenderer.measure(&context, mod.WrappedText("a\nb"), .{ .width = 1000, .height = null });
    try std.testing.expectApproxEqAbs(2 * line_height, size.height, 0.5);
}

test "view: WrappedText renders ink spanning more than one line vertically" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const sentence = "hello wonderful wrapping world";
    const pixel_size = context.theme.typography.body.size;
    const full = renderer.TextShaper.init(&environment.font.face).measureLineWidth(sentence, pixel_size);
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(pixel_size);
    const width: u32 = @intFromFloat(@ceil(full / 2));
    const tree = mod.WrappedText(sentence).foreground(renderer.Color.black);
    var framebuffer = try environment.renderToFramebuffer(&context, tree, .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = 120 }, width, 120);
    defer framebuffer.deinit();
    // top-most and bottom-most inked rows should differ by more than a line —
    // proof the text occupies at least two stacked lines.
    var top: ?u32 = null;
    var bottom: u32 = 0;
    var y: u32 = 0;
    while (y < framebuffer.height) : (y += 1) {
        var inked = false;
        var x: u32 = 0;
        while (x < framebuffer.width) : (x += 1) {
            if (framebuffer.at(x, y).luminance() < 0.5) {
                inked = true;
                break;
            }
        }
        if (inked) {
            if (top == null) top = y;
            bottom = y;
        }
    }
    try std.testing.expect(top != null);
    try std.testing.expect(@as(f32, @floatFromInt(bottom - top.?)) > line_height);
}

test "view: ScrollViewState registers one region and offset moves the content" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var regions: std.ArrayList(mod.ScrollRegion) = .empty;
    context.scroll_regions = &regions;
    var scroll_state = mod.ScrollState{};
    const content = mod.VStack(.{
        mod.Rectangle(renderer.Color.red).frame(50, 30),
        mod.Rectangle(renderer.Color.blue).frame(50, 30),
    }).spacing(0);

    // offset 0: content top (red) is visible, geometry recorded, one region.
    var framebuffer0 = try environment.renderToFramebuffer(&context, mod.ScrollViewState(&scroll_state, content), .{ .x = 0, .y = 0, .width = 50, .height = 40 }, 50, 40);
    defer framebuffer0.deinit();
    try std.testing.expectEqual(@as(usize, 1), regions.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 60), scroll_state.content_height, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 40), scroll_state.viewport_height, 0.5);
    try std.testing.expect(framebuffer0.at(25, 8).approxEql(renderer.Color.red, 0.05));

    // scroll to the bottom: the second (blue) rectangle is now at the bottom.
    scroll_state.scrollToBottom();
    regions.clearRetainingCapacity();
    environment.hits.clearRetainingCapacity();
    var framebuffer1 = try environment.renderToFramebuffer(&context, mod.ScrollViewState(&scroll_state, content), .{ .x = 0, .y = 0, .width = 50, .height = 40 }, 50, 40);
    defer framebuffer1.deinit();
    try std.testing.expect(framebuffer1.at(25, 35).approxEql(renderer.Color.blue, 0.05));
}

test "view: ScrollView clips content to its frame" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    // content is taller (60) than the scroll frame (40)
    const content = mod.VStack(.{
        mod.Rectangle(renderer.Color.red).frame(50, 30),
        mod.Rectangle(renderer.Color.blue).frame(50, 30),
    }).spacing(0);
    const tree = mod.ScrollView(content);
    var framebuffer = try environment.renderToFramebuffer(&context, tree, .{ .x = 0, .y = 0, .width = 50, .height = 40 }, 50, 80);
    defer framebuffer.deinit();
    try std.testing.expect(framebuffer.at(25, 10).approxEql(renderer.Color.red, 0.05)); // visible top
    try std.testing.expect(framebuffer.at(25, 60).approxEql(renderer.Color.white, 0.05)); // below frame -> clipped
}

test "view: EditorMetrics.prefixWidth snaps tabs to tab stops" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const face = &environment.font.face;
    const pixel_size: f32 = 14;
    const tab_width = mod.EditorMetrics.init(face, pixel_size).tabMetrics().tab;
    // A leading tab advances exactly one tab stop.
    try std.testing.expectApproxEqAbs(tab_width, mod.EditorMetrics.init(face, pixel_size).prefixWidth("\t"), 0.01);
    // Text then a tab snaps forward to the *next* stop (never less than the text).
    const ab_width = renderer.TextShaper.init(face).measureLineWidth("ab", pixel_size);
    const after = mod.EditorMetrics.init(face, pixel_size).prefixWidth("ab\t");
    try std.testing.expect(after > ab_width);
    try std.testing.expectApproxEqAbs(@as(f32, 0), @mod(after, tab_width), 0.01);
}

test "view: TextEditor paints line numbers and places the caret on click" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var editor = mod.TextFieldState.init(std.testing.allocator);
    defer editor.deinit();
    defer mod.PointerInput.shared().endDrag(); // a tap arms a text drag on it
    defer mod.Focus.shared().clear(); // a tap focuses it
    var scroll = mod.ScrollState{};
    try editor.setText("alpha\nbeta\ngamma");
    editor.caret = 0;
    editor.last_caret = 0;

    var framebuffer = try environment.renderToFramebuffer(&context, mod.TextEditor(&editor, &scroll, true), .{ .x = 0, .y = 0, .width = 300, .height = 200 }, 300, 200);
    defer framebuffer.deinit();
    // The editor registers one hit region (the whole rect) carrying a text_click.
    try std.testing.expectEqual(@as(usize, 1), environment.hits.items.len);
    try std.testing.expect(environment.hits.items[0].action == .textClick);

    // Click on the second visible line -> caret lands on line 1 ("beta").
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(context.theme.typography.body.size);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 200, .y = 8 + line_height + 2 }));
    try std.testing.expect(editor.focused);
    try std.testing.expectEqual(@as(usize, 1), mod.TextLines.init(editor.text()).lineIndex(editor.caret));
}

test "view: TextEditor mouse drag selects a range" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var editor = mod.TextFieldState.init(std.testing.allocator);
    defer editor.deinit();
    defer mod.PointerInput.shared().endDrag(); // a tap arms a text drag on it
    defer mod.Focus.shared().clear(); // a tap focuses it
    var scroll = mod.ScrollState{};
    try editor.setText("alpha\nbeta\ngamma");

    var framebuffer = try environment.renderToFramebuffer(&context, mod.TextEditor(&editor, &scroll, true), .{ .x = 0, .y = 0, .width = 300, .height = 200 }, 300, 200);
    defer framebuffer.deinit();
    const line_height = renderer.TextShaper.init(&environment.font.face).lineHeight(context.theme.typography.body.size);

    // Press near the start of line 0 ("alpha"), then drag to the end of line 1.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 2, .y = 8 + 2 }));
    try std.testing.expect(!editor.hasSelection()); // a press alone is just a caret
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 250, .y = 8 + line_height + 2 });
    const range = editor.selectionRange().?;
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 10), range.end); // through the end of "beta"
    mod.PointerInput.shared().endDrag();
    // After the drag ends, a further "motion" must not change the selection.
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 10, .y = 8 + 2 });
    try std.testing.expectEqual(@as(usize, 10), editor.selectionRange().?.end);
}

test "view: TextField paints, focuses on tap, and shows a caret" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.PointerInput.shared().endDrag(); // a tap arms a text drag on it
    defer mod.Focus.shared().clear(); // a tap focuses it
    try field.setText("hi");

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.TextField("type…", &field), .{ .x = 0, .y = 0, .width = 180, .height = 28 }, &canvas);
    const before = canvas.count();
    // tap focuses
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 20, .y = 14 }));
    try std.testing.expect(field.focused);

    // focused render draws an extra caret line
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, mod.TextField("type…", &field), .{ .x = 0, .y = 0, .width = 180, .height = 28 }, &canvas);
    var has_line = false;
    for (canvas.commands.items) |command| {
        if (command == .line) has_line = true;
    }
    try std.testing.expect(has_line);
    _ = before;
}

test "view: onSubmit fires only for a focused field with a callback" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    Counter.value = 0;
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();

    // Focus this field directly (avoids touching any stale global focus pointer
    // a prior test may have left behind).
    field.focused = true;
    mod.Focus.shared().focused_field = &field;
    defer mod.Focus.shared().clear();

    // Focused but no onSubmit -> Focus.submit is a no-op.
    try mod.ViewRenderer.render(&context, mod.TextField("msg", &field), .{ .x = 0, .y = 0, .width = 180, .height = 28 }, &canvas);
    mod.Focus.shared().submit();
    try std.testing.expectEqual(@as(u32, 0), Counter.value);

    // With onSubmit, render (stashing it on the focused field) then submit fires.
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, mod.TextField("msg", &field).onSubmit(mod.Callback.action(Counter.increment)), .{ .x = 0, .y = 0, .width = 180, .height = 28 }, &canvas);
    mod.Focus.shared().submit();
    try std.testing.expectEqual(@as(u32, 1), Counter.value);
}

test "view: Picker selects a segment on tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const options = [_][]const u8{ "Low", "Medium", "High" };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.Picker(selection.binding(), &options), .{ .x = 0, .y = 0, .width = 300, .height = 28 }, &canvas);
    try std.testing.expectEqual(@as(usize, 3), environment.hits.items.len); // one region per segment
    // tap the third segment (x ~ 250)
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 250, .y = 14 }));
    try std.testing.expectEqual(@as(i64, 2), selection.get());
}

test "view: RadioGroup selects an option on tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const options = [_][]const u8{ "One", "Two", "Three" };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.RadioGroup(selection.binding(), &options), .{ .x = 0, .y = 0, .width = 200, .height = 120 }, &canvas);
    try std.testing.expectEqual(@as(usize, 3), environment.hits.items.len); // one tap target per option
    // tapping the second row sets the binding to index 1
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, environment.hits.items[1].rect.center()));
    try std.testing.expectEqual(@as(i64, 1), selection.get());
}

test "view: Sidebar selects a row on tap and highlights the selection" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const items = [_]mod.SidebarItem{
        .{ .label = "Inbox", .icon = .mail },
        .{ .label = "Sent" },
        .{ .label = "Drafts" },
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.Sidebar(&items, selection.binding()), .{ .x = 0, .y = 0, .width = 220, .height = 300 }, &canvas);
    try std.testing.expectEqual(@as(usize, 3), environment.hits.items.len);
    // the selected (row 0) draws the neutral selection wash behind it
    var has_selection = false;
    for (canvas.commands.items) |command| {
        if (command == .fillRoundedRect and command.fillRoundedRect.color.approxEql(context.theme.colors.quaternary_fill, 0.05)) has_selection = true;
    }
    try std.testing.expect(has_selection);
    // tapping the third row selects it
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, environment.hits.items[2].rect.center()));
    try std.testing.expectEqual(@as(i64, 2), selection.get());
}

test "view: Table shows a header + rows and selects a row on tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, -1);
    defer selection.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Age", .width = 60 } };
    const rows = [_][]const []const u8{
        &.{ "Ada", "36" },
        &.{ "Alan", "41" },
        &.{ "Grace", "45" },
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.Table(&columns, &rows, selection.binding()), .{ .x = 0, .y = 0, .width = 300, .height = 200 }, &canvas);
    // selection enabled -> one callback tap target per data row (header has none)
    var row_hits: usize = 0;
    var second: ?renderer.Rect = null;
    for (environment.hits.items) |region| {
        if (region.action == .callback) {
            if (row_hits == 1) second = region.rect;
            row_hits += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), row_hits);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, second.?.center()));
    try std.testing.expectEqual(@as(i64, 1), selection.get());
}

test "view: DataTable sortable header toggles the sort binding" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var sort = renderer.State(mod.SortColumn).init(std.testing.allocator, .{});
    defer sort.deinit();
    const columns = [_]mod.DataColumn{
        .{ .title = "Name" }, // not sortable -> no tap target
        .{ .title = "Size", .width = 80, .sortable = true, .trailing = true },
    };
    const rows = [_][]const mod.View{
        &.{ mod.Text("Ada"), mod.Text("6 GB") },
        &.{ mod.Text("Alan"), mod.Text("9 GB") },
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.DataTable(&columns, &rows, sort.binding(), null), .{ .x = 0, .y = 0, .width = 300, .height = 200 }, &canvas);

    // Only the one sortable header registers a tap target.
    var header_hit: ?renderer.Rect = null;
    var count: usize = 0;
    for (environment.hits.items) |region| {
        if (region.action == .callback) {
            header_hit = region.rect;
            count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), count);

    // First tap on a fresh column sorts by it, in reverse (descending).
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, header_hit.?.center()));
    try std.testing.expectEqual(@as(i64, 1), sort.get().index);
    try std.testing.expectEqual(mod.SortOrder.reverse, sort.get().order);

    // Tapping the same column again toggles to forward (ascending).
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, header_hit.?.center()));
    try std.testing.expectEqual(mod.SortOrder.forward, sort.get().order);
}

test "view: truncateToWidth shortens overflowing text with an ellipsis" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const long = "Qwen3.6-40B-Claude-4.6-Opus-Deckard-Heretic-Uncensored-Thinking-NEO-CODE";
    const pixel_size: f32 = 13;
    const full = renderer.TextShaper.init(context.cache.face).measureLineWidth(long, pixel_size);

    // Ample room → returned unchanged.
    try std.testing.expectEqualStrings(long, try context.truncateToWidth(long, pixel_size, full + 10));

    // Constrained → shortened, ends with the ellipsis, and fits the budget.
    const out = try context.truncateToWidth(long, pixel_size, full / 2);
    try std.testing.expect(out.len < long.len);
    try std.testing.expect(std.mem.endsWith(u8, out, "…"));
    try std.testing.expect(renderer.TextShaper.init(context.cache.face).measureLineWidth(out, pixel_size) <= full / 2);
}

test "view: LazyVGrid lays items into ceil(n/cols) rows of horizontal stacks" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const items = [_]renderer.Color{ renderer.Color.red, renderer.Color.green, renderer.Color.blue, renderer.Color.red, renderer.Color.green };
    const tree = mod.LazyVGrid(2, 4, &items, Fixtures.gridCell);
    // a vertical stack of 3 rows (ceil(5/2))
    try std.testing.expect(tree.kind == .stack);
    try std.testing.expectEqual(renderer.Direction.vertical, tree.kind.stack.direction);
    try std.testing.expectEqual(@as(usize, 3), tree.kind.stack.children.len);
    // each row is a horizontal stack of `cols` cells
    const row0 = tree.kind.stack.children[0];
    try std.testing.expect(row0.kind == .stack);
    try std.testing.expectEqual(renderer.Direction.horizontal, row0.kind.stack.direction);
    try std.testing.expectEqual(@as(usize, 2), row0.kind.stack.children.len);
    // measured height ≈ 3 rows·20 + 2 gaps·4
    const size = try mod.ViewRenderer.measure(&context, tree, .{ .width = 200, .height = null });
    try std.testing.expectApproxEqAbs(@as(f32, 3 * 20 + 2 * 4), size.height, 0.5);
}

test "view: LazyVGrid renders cells across rows and columns" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const items = [_]renderer.Color{ renderer.Color.red, renderer.Color.red, renderer.Color.red, renderer.Color.red };
    const tree = mod.LazyVGrid(2, 0, &items, Fixtures.gridCell);
    var framebuffer = try environment.renderToFramebuffer(&context, tree, .{ .x = 0, .y = 0, .width = 40, .height = 40 }, 40, 40);
    defer framebuffer.deinit();
    // 2×2 grid of 20×20 cells -> all four cell centers are red
    try std.testing.expect(framebuffer.at(10, 5).approxEql(renderer.Color.red, 0.05)); // row0 col0
    try std.testing.expect(framebuffer.at(30, 5).approxEql(renderer.Color.red, 0.05)); // row0 col1
    try std.testing.expect(framebuffer.at(10, 25).approxEql(renderer.Color.red, 0.05)); // row1 col0
    try std.testing.expect(framebuffer.at(30, 25).approxEql(renderer.Color.red, 0.05)); // row1 col1
}

test "view: LazyHGrid lays items into ceil(n/rows) columns of vertical stacks" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const items = [_]renderer.Color{ renderer.Color.red, renderer.Color.green, renderer.Color.blue };
    const tree = mod.LazyHGrid(2, 4, &items, Fixtures.gridCell);
    // a horizontal stack of 2 columns (ceil(3/2))
    try std.testing.expect(tree.kind == .stack);
    try std.testing.expectEqual(renderer.Direction.horizontal, tree.kind.stack.direction);
    try std.testing.expectEqual(@as(usize, 2), tree.kind.stack.children.len);
    try std.testing.expectEqual(renderer.Direction.vertical, tree.kind.stack.children[0].kind.stack.direction);
}

test "view: NavigationLink pushes its route, NavigationBackButton pops" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var navigation = mod.NavigationPath.init(std.testing.allocator);
    defer navigation.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.NavigationLink("Details", 42, &navigation), .{ .x = 0, .y = 0, .width = 120, .height = 28 }, &canvas);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 60, .y = 14 }));
    try std.testing.expectEqual(@as(usize, 1), navigation.depth());
    try std.testing.expectEqual(@as(i64, 42), navigation.top().?);

    // a back button pops it
    environment.hits.clearRetainingCapacity();
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, mod.NavigationBackButton("Back", &navigation), .{ .x = 0, .y = 0, .width = 80, .height = 28 }, &canvas);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 40, .y = 14 }));
    try std.testing.expectEqual(@as(usize, 0), navigation.depth());
}

test "view: NavigationSplitView is a 220 sidebar, divider, filling detail" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const context = environment.context();
    const tree = mod.NavigationSplitView(mod.Text("Sidebar"), mod.Text("Detail"), context.theme.colors.secondary_background);
    try std.testing.expect(tree.kind == .stack);
    try std.testing.expectEqual(renderer.Direction.horizontal, tree.kind.stack.direction);
    try std.testing.expectEqual(@as(usize, 3), tree.kind.stack.children.len);
    // sidebar fixed 220 wide with a themed background
    try std.testing.expectEqual(@as(f32, 220), tree.kind.stack.children[0].modifiers.frame.?.width.?);
    try std.testing.expect(tree.kind.stack.children[0].modifiers.background != null);
    // vertical hairline in the middle
    try std.testing.expect(tree.kind.stack.children[1].kind == .verticalDivider);
    // detail fills remaining width
    try std.testing.expectEqual(std.math.inf(f32), tree.kind.stack.children[2].modifiers.frame.?.max_width.?);
}

test "view: renderScaled rasterizes glyphs at device resolution (crisp, not upscaled)" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    const tree = mod.Text("A").font(.title);

    var canvas1 = renderer.Canvas.init(std.testing.allocator);
    defer canvas1.deinit();
    try mod.ViewRenderer.renderScaled(&context, tree, root, 1, &canvas1);

    var canvas2 = renderer.Canvas.init(std.testing.allocator);
    defer canvas2.deinit();
    try mod.ViewRenderer.renderScaled(&context, tree, root, 2, &canvas2);

    const scale1_width = Fixtures.firstGlyphCoverageWidth(&canvas1).?;
    const scale2_width = Fixtures.firstGlyphCoverageWidth(&canvas2).?;
    // the 2× coverage bitmap is genuinely ~2× wider — rasterized at device px,
    // not a stretched 1× glyph (which would keep the same coverage width)
    try std.testing.expect(scale2_width >= scale1_width * 2 - 2 and scale2_width <= scale1_width * 2 + 2);
}

test "view: renderScaled doubles shape coordinates and ~4×s glyph ink at scale 2" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();

    // (a) a shape's device coordinates scale by the factor
    const shape_tree = mod.Rectangle(renderer.Color.red).frame(10, 10);
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 40, .height = 40 };
    var shape_canvas1 = renderer.Canvas.init(std.testing.allocator);
    defer shape_canvas1.deinit();
    try mod.ViewRenderer.renderScaled(&context, shape_tree, root, 1, &shape_canvas1);
    var framebuffer1 = try renderer.Framebuffer.init(std.testing.allocator, 40, 40);
    defer framebuffer1.deinit();
    framebuffer1.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer1).render(shape_canvas1.commands.items);

    var shape_canvas2 = renderer.Canvas.init(std.testing.allocator);
    defer shape_canvas2.deinit();
    try mod.ViewRenderer.renderScaled(&context, shape_tree, root, 2, &shape_canvas2);
    var framebuffer2 = try renderer.Framebuffer.init(std.testing.allocator, 80, 80);
    defer framebuffer2.deinit();
    framebuffer2.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer2).render(shape_canvas2.commands.items);

    // the 10×10 shape is centered at point (20,20); at scale 2 its center lands
    // at device (40,40) and it is absent where the scale-1 block sat (20,20)
    try std.testing.expect(framebuffer1.at(20, 20).approxEql(renderer.Color.red, 0.1));
    try std.testing.expect(framebuffer2.at(40, 40).approxEql(renderer.Color.red, 0.1));
    try std.testing.expect(framebuffer2.at(20, 20).approxEql(renderer.Color.white, 0.1));

    // (b) glyph ink area roughly quadruples (2× linear) between scales
    const text_tree = mod.Text("Ag").font(.title);
    var text_canvas1 = renderer.Canvas.init(std.testing.allocator);
    defer text_canvas1.deinit();
    try mod.ViewRenderer.renderScaled(&context, text_tree, .{ .x = 0, .y = 0, .width = 80, .height = 40 }, 1, &text_canvas1);
    var text_framebuffer1 = try renderer.Framebuffer.init(std.testing.allocator, 80, 40);
    defer text_framebuffer1.deinit();
    text_framebuffer1.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &text_framebuffer1).render(text_canvas1.commands.items);

    var text_canvas2 = renderer.Canvas.init(std.testing.allocator);
    defer text_canvas2.deinit();
    try mod.ViewRenderer.renderScaled(&context, text_tree, .{ .x = 0, .y = 0, .width = 80, .height = 40 }, 2, &text_canvas2);
    var text_framebuffer2 = try renderer.Framebuffer.init(std.testing.allocator, 160, 80);
    defer text_framebuffer2.deinit();
    text_framebuffer2.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &text_framebuffer2).render(text_canvas2.commands.items);

    const ink1 = mod.TestEnvironment.countDark(&text_framebuffer1);
    const ink2 = mod.TestEnvironment.countDark(&text_framebuffer2);
    try std.testing.expect(ink1 > 10);
    try std.testing.expect(ink2 > ink1 * 3); // ~4× the inked area
}

test "view: backgroundMaterial frosts the backdrop drawn beneath it" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // a sharp red→blue gradient backdrop, then a centered 40×40 material panel
    const tree = mod.ZStack(.{
        mod.LinearGradient(renderer.Color.red, renderer.Color.blue, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }).frameMaxWidth().frameMaxHeight(),
        mod.Empty().frame(40, 40).backgroundMaterial(.regular),
    });
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    try mod.ViewRenderer.render(&context, tree, root, &canvas);

    // the material emits a blur command
    var has_blur = false;
    for (canvas.commands.items) |command| {
        if (command == .blurRect) has_blur = true;
    }
    try std.testing.expect(has_blur);

    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 100, 100);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    // inside the panel the frost lightens the gradient vs. the raw backdrop above it
    try std.testing.expect(framebuffer.at(50, 50).luminance() > framebuffer.at(50, 5).luminance() + 0.2);
}

test "a11y: emits a node per meaningful component with roles, labels, values" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var a11y: std.ArrayList(mod.A11yNode) = .empty;
    context.a11y = &a11y;
    var on = renderer.State(bool).init(std.testing.allocator, true);
    defer on.deinit();
    var amount = renderer.State(f32).init(std.testing.allocator, 0.5);
    defer amount.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.VStack(.{
        mod.Text("Title"),
        mod.Button("Increment", mod.Callback.action(Counter.increment)),
        mod.Toggle("Wi-Fi", on.binding()),
        mod.Slider(amount.binding(), 0, 1),
    });
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 200, .height = 200 }, &canvas);

    var has_text = false;
    var has_button = false;
    var switch_on = false;
    var has_slider = false;
    for (a11y.items) |node| {
        switch (node.role) {
            .staticText => if (std.mem.eql(u8, node.label, "Title")) {
                has_text = true;
            },
            .button => if (std.mem.eql(u8, node.label, "Increment")) {
                has_button = true;
            },
            .toggle => if (std.mem.eql(u8, node.value, "on")) {
                switch_on = true;
            },
            .slider => has_slider = true,
            else => {},
        }
    }
    try std.testing.expect(has_text);
    try std.testing.expect(has_button);
    try std.testing.expect(switch_on);
    try std.testing.expect(has_slider);
}

test "a11y: a field's text and a slider's value are built only for an accessibility pass" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    var editor = mod.TextFieldState.init(std.testing.allocator);
    defer editor.deinit();
    var scroll = mod.ScrollState{};
    var amount = renderer.State(f32).init(std.testing.allocator, 0.5);
    defer amount.deinit();
    const long_text: [4096]u8 = @splat('x');
    try field.setText(&long_text);
    try editor.setText(&long_text);
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.VStack(.{
        mod.TextField("ph", &field),
        mod.TextEditor(&editor, &scroll, false).frameHeight(60),
        mod.Slider(amount.binding(), 0, 1),
    });

    // The same frame twice, counting what it asks of the arena: without an
    // accessibility sink, then with one.
    var counted: [2]usize = undefined;
    for (&counted, 0..) |*bytes, pass| {
        var counting = std.testing.FailingAllocator.init(environment.arena_state.allocator(), .{});
        var context = environment.context();
        context.arena = counting.allocator();
        environment.hits = .empty;
        var a11y: std.ArrayList(mod.A11yNode) = .empty;
        if (pass == 1) context.a11y = &a11y;
        canvas.clearCommands();
        try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 300, .height = 200 }, &canvas);
        bytes.* = counting.allocated_bytes;
        for (a11y.items) |node| if (node.role == .textField) try std.testing.expectEqual(long_text.len, node.value.len);
    }
    // Only the accessibility pass copies the two buffers.
    try std.testing.expect(counted[1] >= counted[0] + 2 * long_text.len);
}

test "a11y: accessibilityHidden drops a node; accessibilityLabel overrides it" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var a11y: std.ArrayList(mod.A11yNode) = .empty;
    context.a11y = &a11y;

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const tree = mod.VStack(.{
        mod.Text("secret").accessibilityHidden(true),
        mod.Text("raw").accessibilityLabel("Friendly"),
    });
    try mod.ViewRenderer.render(&context, tree, .{ .x = 0, .y = 0, .width = 200, .height = 100 }, &canvas);

    var saw_secret = false;
    var saw_friendly = false;
    var saw_raw = false;
    for (a11y.items) |node| {
        if (std.mem.eql(u8, node.label, "secret")) saw_secret = true;
        if (std.mem.eql(u8, node.label, "Friendly")) saw_friendly = true;
        if (std.mem.eql(u8, node.label, "raw")) saw_raw = true;
    }
    try std.testing.expect(!saw_secret); // hidden from the tree
    try std.testing.expect(saw_friendly); // label overridden
    try std.testing.expect(!saw_raw); // original label replaced, not duplicated
}

test "view: sheet enqueues an overlay, draws a scrim over content, dismisses on scrim tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 200, .height = 200 };
    const sheet_content = mod.Rectangle(renderer.Color.red).frame(120, 60);
    try mod.ViewRenderer.render(&context, mod.Text("Base").sheet(presented.binding(), sheet_content), root, &canvas);

    // one overlay collected with the right style
    try std.testing.expectEqual(@as(usize, 1), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.sheet, overlays.items[0].style);

    // a full-root, semi-transparent scrim fill is appended AFTER the base content
    var scrim_index: ?usize = null;
    for (canvas.commands.items, 0..) |command, index| {
        if (command == .fillRoundedRect) {
            const fill = command.fillRoundedRect;
            if (fill.rect.width == 200 and fill.rect.height == 200 and fill.color.a > 0 and fill.color.a < 0.5) scrim_index = index;
        }
    }
    try std.testing.expect(scrim_index != null);
    try std.testing.expect(scrim_index.? > 0); // base glyphs were drawn first

    // dismiss region is last; tapping the scrim flips presented to false
    const last = environment.hits.items[environment.hits.items.len - 1];
    try std.testing.expect(last.action == .dismiss);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 5, .y = 5 }));
    try std.testing.expect(!presented.get());

    // sheet content inks over the root, and the top is dimmed by the scrim
    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 200, 200);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    try std.testing.expect(mod.TestEnvironment.countRed(&framebuffer) > 100);
    try std.testing.expect(framebuffer.at(100, 20).luminance() < 0.95);
}

test "view: chaining .sheet and .alert keeps both overlays (neither clobbers)" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var sheet_on = renderer.State(bool).init(std.testing.allocator, true);
    defer sheet_on.deinit();
    var alert_on = renderer.State(bool).init(std.testing.allocator, false);
    defer alert_on.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 200, .height = 200 };
    const base = mod.Text("Base")
        .sheet(sheet_on.binding(), mod.Rectangle(renderer.Color.red).frame(80, 40))
        .alert(alert_on.binding(), mod.Rectangle(renderer.Color.blue).frame(80, 40));

    // Only the sheet is presented → exactly one overlay, and it's the sheet.
    try mod.ViewRenderer.render(&context, base, root, &canvas);
    try std.testing.expectEqual(@as(usize, 1), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.sheet, overlays.items[0].style);

    // Turn the alert on too → both present (the .alert did not overwrite .sheet).
    overlays.clearRetainingCapacity();
    environment.hits.clearRetainingCapacity();
    canvas.clearCommands();
    alert_on.set(true);
    try mod.ViewRenderer.render(&context, base, root, &canvas);
    try std.testing.expectEqual(@as(usize, 2), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.sheet, overlays.items[0].style);
    try std.testing.expectEqual(mod.OverlayStyle.alert, overlays.items[1].style);
}

test "view: onHover fires once on enter and once on leave, and only on movement" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var hovers: std.ArrayList(mod.HoverRegion) = .empty;
    context.hover_regions = &hovers;

    const Probe = struct {
        const Self = @This();
        var enters: u32 = 0;
        var leaves: u32 = 0;
        fn seen(_: ?*anyopaque, inside: bool) void {
            if (inside) enters += 1 else leaves += 1;
        }
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 200, .height = 200 };
    const tree = mod.VStack(.{
        mod.Rectangle(renderer.Color.red).frame(100, 40).onHover(.{ .function = Probe.seen }),
        mod.Rectangle(renderer.Color.blue).frame(100, 40).onHover(.{ .function = Probe.seen }).disabled(true),
        mod.Spacer(),
    }).alignment(.leading).frameMaxWidth().frameMaxHeight();
    try mod.ViewRenderer.render(&context, tree, root, &canvas);
    try std.testing.expectEqual(@as(usize, 2), hovers.items.len);
    const box = hovers.items[0].rect;
    const inside = renderer.Point{ .x = box.x + 10, .y = box.y + 10 };
    const outside = renderer.Point{ .x = 190, .y = 190 };

    // No movement, or movement within or outside the frame: nothing fires.
    try std.testing.expect(!mod.PointerInput.shared().hover(hovers.items, inside, inside));
    try std.testing.expect(!mod.PointerInput.shared().hover(hovers.items, outside, .{ .x = 180, .y = 180 }));
    try std.testing.expect(!mod.PointerInput.shared().hover(hovers.items, inside, .{ .x = box.x + 20, .y = box.y + 20 }));
    // Entering fires once; leaving (or the pointer leaving the window) once.
    try std.testing.expect(mod.PointerInput.shared().hover(hovers.items, outside, inside));
    try std.testing.expect(mod.PointerInput.shared().hover(hovers.items, inside, null));
    try std.testing.expectEqual(@as(u32, 1), Probe.enters);
    try std.testing.expectEqual(@as(u32, 1), Probe.leaves);
    // The disabled view never fires.
    const disabled_rect = hovers.items[1].rect;
    try std.testing.expect(!mod.PointerInput.shared().hover(hovers.items, outside, .{ .x = disabled_rect.x + 5, .y = disabled_rect.y + 5 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.enters);
}

test "view: a popoverPassthrough view takes taps while a popover is open" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();

    const Probe = struct {
        const Self = @This();
        var taps: u32 = 0;
        fn tapped(_: ?*anyopaque) void {
            taps += 1;
        }
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 300, .height = 300 };
    const tree = mod.VStack(.{
        mod.HStack(.{
            mod.Rectangle(renderer.Color.red).frame(60, 30).popover(presented.binding(), mod.Rectangle(renderer.Color.blue).frame(80, 80)),
            mod.Rectangle(renderer.Color.green).frame(60, 30).onTap(.{ .function = Probe.tapped }).popoverPassthrough(),
            mod.Spacer(),
        }),
        mod.Spacer(),
    }).frameMaxWidth().frameMaxHeight();
    try mod.ViewRenderer.render(&context, tree, root, &canvas);

    // The second box sits at x 60..120 on the top row: a tap there reaches it
    // and leaves the popover up.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 90, .y = 15 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.taps);
    try std.testing.expect(presented.get());
    // A tap anywhere else outside the popover still closes it.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 250, .y = 250 }));
    try std.testing.expect(!presented.get());
    try std.testing.expectEqual(@as(u32, 1), Probe.taps);
}

test "view: a modalPassthrough view takes taps under an alert; a popoverPassthrough one does not" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();

    const Probe = struct {
        const Self = @This();
        var modal: u32 = 0;
        var popover: u32 = 0;
        fn modalTap(_: ?*anyopaque) void {
            modal += 1;
        }
        fn popoverTap(_: ?*anyopaque) void {
            popover += 1;
        }
    };
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 300, .height = 300 };
    const tree = mod.VStack(.{
        mod.HStack(.{
            mod.Rectangle(renderer.Color.green).frame(60, 30).onTap(.{ .function = Probe.modalTap }).modalPassthrough(),
            mod.Rectangle(renderer.Color.red).frame(60, 30).onTap(.{ .function = Probe.popoverTap }).popoverPassthrough(),
            mod.Spacer(),
        }),
        mod.Spacer(),
    }).frameMaxWidth().frameMaxHeight().alert(presented.binding(), mod.Rectangle(renderer.Color.blue).frame(80, 80));
    try mod.ViewRenderer.render(&context, tree, root, &canvas);

    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 30, .y = 15 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.modal);
    try std.testing.expect(presented.get());
    // The popover's passthrough means nothing to a modal: the scrim takes it.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 90, .y = 15 }));
    try std.testing.expectEqual(@as(u32, 0), Probe.popover);
    try std.testing.expect(!presented.get());
}

test "view: a popover taller than the window is cut to fit and scrolls" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var scrolls: std.ArrayList(mod.ScrollRegion) = .empty;
    context.scroll_regions = &scrolls;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 300, .height = 300 };
    const tree = mod.VStack(.{ mod.Spacer(), mod.Text("anchor").popover(presented.binding(), mod.Rectangle(renderer.Color.blue).frame(80, 2000)) });
    // The app paints after the build pass ends; so does this test.
    mod.BuildScope.shared().end();
    try mod.ViewRenderer.render(&context, tree, root, &canvas);
    // A scroll region for the popover, inside the window.
    try std.testing.expectEqual(@as(usize, 1), scrolls.items.len);
    try std.testing.expect(scrolls.items[0].rect.y >= 0 and scrolls.items[0].rect.maxY() <= 300);
}

test "view: press-drag over selectable text selects it for copying" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 400, .height = 40 };
    const tree = mod.RichText(&.{.{ .text = "hello world" }}).selectable().frameMaxWidth().frameAlign(.leading);
    try mod.ViewRenderer.render(&context, tree, root, &canvas);
    // Press at the far left, drag past the end: the whole text.
    try std.testing.expect(mod.PointerInput.shared().tap(context.hit_regions.items, .{ .x = 1, .y = 20 }));
    mod.PointerInput.shared().drag(context.hit_regions.items, .{ .x = 399, .y = 20 });
    mod.PointerInput.shared().endDrag();
    try mod.ViewRenderer.render(&context, tree, root, &canvas); // paints the highlight, refreshes the text
    try std.testing.expectEqualStrings("hello world", mod.TextSelection.shared().selectedText().?);
    // A press elsewhere clears it.
    _ = mod.PointerInput.shared().tap(&.{}, .{ .x = 500, .y = 500 });
    try std.testing.expect(mod.TextSelection.shared().selectedText() == null);
}

test "view: identical selectable paragraphs select apart, and stay apart frame to frame and scrolled" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    defer mod.TextSelection.shared().current = null;
    var scroll = mod.ScrollState{};
    const Transcript = struct {
        const Self = @This();

        /// Two "OK" replies, 100 points apart, in a scroll view (a chat transcript).
        ///
        /// - `scroll_state`: the transcript's scroll.
        /// - Returns: the transcript.
        fn build(scroll_state: *mod.ScrollState) mod.View {
            const reply = mod.RichText(&.{.{ .text = "OK" }});
            return mod.ScrollViewState(scroll_state, mod.VStack(.{
                reply.selectable().frameMaxWidth().frameAlign(.leading),
                mod.Rectangle(renderer.Color.white).frame(10, 100),
                reply.selectable().frameMaxWidth().frameAlign(.leading),
            }).spacing(0));
        }

        /// The frame's selectable paragraphs, top to bottom.
        ///
        /// - `regions`: the frame's hit regions.
        /// - `found`: where they go.
        /// - Returns: how many there are.
        fn selectables(regions: []const mod.HitRegion, found: []*const mod.SelectHit) usize {
            var count: usize = 0;
            for (regions) |region| switch (region.action) {
                .textSelect => |hit| {
                    found[count] = hit;
                    count += 1;
                },
                else => {},
            };
            return count;
        }
    };
    var found: [4]*const mod.SelectHit = undefined;

    // Both shown: they are told apart, and a drag over the second selects it alone.
    try mod.ViewRenderer.render(&context, Transcript.build(&scroll), .{ .x = 0, .y = 0, .width = 400, .height = 200 }, &canvas);
    try std.testing.expectEqual(@as(usize, 2), Transcript.selectables(environment.hits.items, &found));
    const first_key = found[0].key;
    const second_key = found[1].key;
    try std.testing.expect(first_key != second_key);
    const second_y = found[1].origin.y + 5;
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 1, .y = second_y }));
    mod.PointerInput.shared().drag(environment.hits.items, .{ .x = 399, .y = second_y });
    mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(second_key, mod.TextSelection.shared().current.?.key);
    try std.testing.expectEqual(@as(usize, 2), mod.TextSelection.shared().current.?.head);

    // The next frame builds them anew: the same keys, the selection stays put.
    mod.BuildScope.shared().begin(environment.arena_state.allocator());
    environment.hits.clearRetainingCapacity();
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, Transcript.build(&scroll), .{ .x = 0, .y = 0, .width = 400, .height = 200 }, &canvas);
    try std.testing.expectEqual(@as(usize, 2), Transcript.selectables(environment.hits.items, &found));
    try std.testing.expectEqual(first_key, found[0].key);
    try std.testing.expectEqual(second_key, found[1].key);
    try std.testing.expectEqualStrings("OK", mod.TextSelection.shared().selectedText().?);

    // Scrolled so the first is hidden (not painted): the second keeps its key.
    for (0..2) |_| {
        mod.BuildScope.shared().begin(environment.arena_state.allocator());
        environment.hits.clearRetainingCapacity();
        canvas.clearCommands();
        try mod.ViewRenderer.render(&context, Transcript.build(&scroll), .{ .x = 0, .y = 0, .width = 400, .height = 40 }, &canvas);
        scroll.scrollToBottom();
    }
    try std.testing.expectEqual(@as(usize, 1), Transcript.selectables(environment.hits.items, &found));
    try std.testing.expectEqual(second_key, found[0].key);

    // An explicit id stands in for the text and its order.
    const tagged = mod.RichText(&.{.{ .text = "OK" }}).selectable().selectionId(7);
    const retagged = mod.RichText(&.{.{ .text = "other" }}).selectable().selectionId(7);
    const spans = [_]mod.Span{.{ .text = "OK" }};
    try std.testing.expectEqual(mod.TextSelection.keyFor(&spans, 13, &tagged.modifiers), mod.TextSelection.keyFor(&spans, 13, &retagged.modifiers));
    try std.testing.expect(mod.TextSelection.keyFor(&spans, 13, &tagged.modifiers) != first_key);
}

test "view: ScrollViewStateBoth lays content out at its width and scrolls it sideways" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var regions: std.ArrayList(mod.ScrollRegion) = .empty;
    context.scroll_regions = &regions;
    var scroll_state = mod.ScrollState{};
    const content = mod.HStack(.{
        mod.Rectangle(renderer.Color.red).frame(30, 20),
        mod.Rectangle(renderer.Color.blue).frame(30, 20),
    }).spacing(0);

    // offset 0: the left (red) half shows, the width is recorded, one horizontal region.
    var framebuffer0 = try environment.renderToFramebuffer(&context, mod.ScrollViewStateBoth(&scroll_state, content), .{ .x = 0, .y = 0, .width = 40, .height = 20 }, 40, 20);
    defer framebuffer0.deinit();
    try std.testing.expectEqual(@as(usize, 1), regions.items.len);
    try std.testing.expect(regions.items[0].horizontal);
    try std.testing.expectApproxEqAbs(@as(f32, 60), scroll_state.content_width, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 40), scroll_state.viewport_width, 0.5);
    try std.testing.expect(framebuffer0.at(5, 10).approxEql(renderer.Color.red, 0.05));

    // Past the end clamps to it: the right (blue) half reaches the right edge.
    scroll_state.offset_x = 1000;
    regions.clearRetainingCapacity();
    environment.hits.clearRetainingCapacity();
    var framebuffer1 = try environment.renderToFramebuffer(&context, mod.ScrollViewStateBoth(&scroll_state, content), .{ .x = 0, .y = 0, .width = 40, .height = 20 }, 40, 20);
    defer framebuffer1.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 20), scroll_state.offset_x, 0.5);
    try std.testing.expect(framebuffer1.at(35, 10).approxEql(renderer.Color.blue, 0.05));

    // A plain ScrollViewState records no width and registers a vertical region.
    var plain = mod.ScrollState{};
    regions.clearRetainingCapacity();
    environment.hits.clearRetainingCapacity();
    var framebuffer2 = try environment.renderToFramebuffer(&context, mod.ScrollViewState(&plain, content), .{ .x = 0, .y = 0, .width = 40, .height = 20 }, 40, 20);
    defer framebuffer2.deinit();
    try std.testing.expect(!regions.items[0].horizontal);
    try std.testing.expectEqual(@as(f32, 0), plain.content_width);
}

test "view: a Drawing paints into its frame" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const Box = struct {
        const Self = @This();
        color: renderer.Color,
        fn draw(self: *const Self, pen: *mod.Pen, rect: renderer.Rect) std.mem.Allocator.Error!void {
            try pen.fill(.{ .x = rect.x, .y = rect.y, .width = rect.width / 2, .height = rect.height }, 0, self.color);
        }
    };
    const box = Box{ .color = renderer.Color.blue };
    try mod.ViewRenderer.render(&context, mod.Drawing(Box, &box, Box.draw).frame(40, 20), .{ .x = 0, .y = 0, .width = 40, .height = 20 }, &canvas);
    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 40, 20);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    try std.testing.expect(framebuffer.at(5, 10).b > 0.9 and framebuffer.at(5, 10).r < 0.1);
    try std.testing.expect(framebuffer.at(35, 10).r > 0.9);
}

test "view: an alert widens to content that cannot be narrower" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();
    var choice = renderer.State(i64).init(std.testing.allocator, 0);
    defer choice.deinit();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 900, .height = 400 };
    const options = [_][]const u8{ "A long first option", "A long second option", "A long third option", "Fourth" };
    const picker = mod.Picker(choice.binding(), &options);
    const least = try mod.ViewRenderer.measure(&context, picker, .{ .width = 0, .height = null });
    try std.testing.expect(least.width > 320);
    // A filling picker under a heading, padded: as a settings sheet is built.
    const content = mod.VStack(.{ mod.Text("Settings"), picker.frameMaxWidth() }).alignment(.leading).padding(20);
    const tree = mod.Rectangle(renderer.Color.white).alert(presented.binding(), content);
    mod.BuildScope.shared().end();
    try mod.ViewRenderer.render(&context, tree, root, &canvas);
    // The panel holds every segment: none reaches its clip, which is the panel.
    var clip: ?renderer.Rect = null;
    for (canvas.commands.items) |command| if (command == .pushClip) {
        clip = command.pushClip.rect;
    };
    try std.testing.expect(clip.?.width >= least.width + 40 - 0.5);
    try std.testing.expect(clip.?.x >= 0 and clip.?.maxX() <= root.width);
    for (context.hit_regions.items) |region| if (region.action == .select) {
        try std.testing.expect(region.rect.x >= clip.?.x - 0.5 and region.rect.maxX() <= clip.?.maxX() + 0.5);
    };
}

test "view: popover content is positioned near its (top) anchor" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const root = renderer.Rect{ .x = 0, .y = 0, .width = 300, .height = 300 };
    const popover_content = mod.Rectangle(renderer.Color.blue).frame(80, 40);
    const tree = mod.VStack(.{ mod.Text("anchor").popover(presented.binding(), popover_content), mod.Spacer() });
    try mod.ViewRenderer.render(&context, tree, root, &canvas);
    try std.testing.expectEqual(@as(usize, 1), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.popover, overlays.items[0].style);

    var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, 300, 300);
    defer framebuffer.deinit();
    framebuffer.clear(renderer.Color.white);
    try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    // the anchor sits at the top, so the popover renders in the top half only
    var top_blue: u32 = 0;
    var bottom_blue: u32 = 0;
    var y: u32 = 0;
    while (y < 300) : (y += 1) {
        var x: u32 = 0;
        while (x < 300) : (x += 1) {
            const pixel = framebuffer.at(x, y);
            if (pixel.b > pixel.r + 0.2 and pixel.b > 0.4) {
                if (y < 150) top_blue += 1 else bottom_blue += 1;
            }
        }
    }
    try std.testing.expect(top_blue > 100);
    try std.testing.expectEqual(@as(u32, 0), bottom_blue);
}

test "view: nested overlays drain once each without recursion" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var outer = renderer.State(bool).init(std.testing.allocator, true);
    defer outer.deinit();
    var inner = renderer.State(bool).init(std.testing.allocator, true);
    defer inner.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // the sheet's content itself presents an alert
    const inner_content = mod.Rectangle(renderer.Color.green).frame(60, 40);
    const sheet_content = mod.Text("sheet").alert(inner.binding(), inner_content);
    try mod.ViewRenderer.render(&context, mod.Text("base").sheet(outer.binding(), sheet_content), .{ .x = 0, .y = 0, .width = 200, .height = 200 }, &canvas);

    try std.testing.expectEqual(@as(usize, 2), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.sheet, overlays.items[0].style);
    try std.testing.expectEqual(mod.OverlayStyle.alert, overlays.items[1].style);
}

test "view: double-click selects the word; TextField exposes text_click" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();

    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear(); // a double-click focuses it
    try field.setText("foo barbaz qux");

    // selectWordAt expands to the word boundaries around an index.
    field.selectWordAt(5); // inside "barbaz"
    const range = field.selectionRange().?;
    try std.testing.expectEqualStrings("barbaz", field.text()[range.start..range.end]);

    // A run of whitespace selects together (not a word).
    field.selectWordAt(3); // the space after "foo"
    const space_range = field.selectionRange().?;
    try std.testing.expectEqualStrings(" ", field.text()[space_range.start..space_range.end]);

    // The single-line field now registers a `text_click`, so a double-click
    // dispatch near the left edge selects the first word.
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.TextField("ph", &field), .{ .x = 0, .y = 0, .width = 200, .height = 40 }, &canvas);
    try std.testing.expectEqual(@as(usize, 1), environment.hits.items.len);
    try std.testing.expect(environment.hits.items[0].action == .textClick);
    try std.testing.expect(mod.PointerInput.shared().doubleClick(environment.hits.items, .{ .x = 12, .y = 20 }));
    const word_range = field.selectionRange().?;
    try std.testing.expectEqualStrings("foo", field.text()[word_range.start..word_range.end]);

    // Triple-click selects the whole field.
    try std.testing.expect(mod.PointerInput.shared().tripleClick(environment.hits.items, .{ .x = 12, .y = 20 }));
    const whole_range = field.selectionRange().?;
    try std.testing.expectEqual(@as(usize, 0), whole_range.start);
    try std.testing.expectEqual(field.text().len, whole_range.end);
}

test "view: TextField selection highlight is visible" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();

    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("hello");
    mod.Focus.shared().set(&field);
    defer mod.Focus.shared().clear();

    const rect = renderer.Rect{ .x = 0, .y = 0, .width = 140, .height = 36 };

    // The focus border is also blue, so diff a no-selection render against a
    // fully-selected one — the difference is the highlight block.
    field.selection_anchor = null; // just a caret
    var framebuffer0 = try environment.renderToFramebuffer(&context, mod.TextField("ph", &field), rect, 140, 36);
    defer framebuffer0.deinit();
    const before = mod.TestEnvironment.countBlue(&framebuffer0);

    environment.hits.clearRetainingCapacity();
    field.selectAll();
    var framebuffer1 = try environment.renderToFramebuffer(&context, mod.TextField("ph", &field), rect, 140, 36);
    defer framebuffer1.deinit();
    const after = mod.TestEnvironment.countBlue(&framebuffer1);

    try std.testing.expect(after > before + 50); // the selection adds a solid blue block
}

test "view: Menu toggles a popover of items" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var open = renderer.State(bool).init(std.testing.allocator, false);
    defer open.deinit();

    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // closed: no overlay; tapping the button opens the menu
    try mod.ViewRenderer.render(&context, mod.Menu("Options", &open, .{mod.Button("A", mod.Callback.action(Counter.increment))}), .{ .x = 0, .y = 0, .width = 100, .height = 200 }, &canvas);
    try std.testing.expectEqual(@as(usize, 0), overlays.items.len);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 50, .y = 14 }));
    try std.testing.expect(open.get());

    // open: a single popover overlay holds the menu items
    environment.hits.clearRetainingCapacity();
    overlays.clearRetainingCapacity();
    canvas.clearCommands();
    try mod.ViewRenderer.render(&context, mod.Menu("Options", &open, .{mod.Button("A", mod.Callback.action(Counter.increment))}), .{ .x = 0, .y = 0, .width = 100, .height = 200 }, &canvas);
    try std.testing.expectEqual(@as(usize, 1), overlays.items.len);
    try std.testing.expectEqual(mod.OverlayStyle.popover, overlays.items[0].style);
}

test "view: TabView shows the selected tab and switches on tab-bar tap" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    const tabs = [_]mod.Tab{
        .{ .label = "One", .content = mod.Rectangle(renderer.Color.red).frame(80, 40) },
        .{ .label = "Two", .content = mod.Rectangle(renderer.Color.blue).frame(80, 40) },
    };
    // tab 0 selected -> red content shows. (The tab bar's selected segment is
    // an accent chip, so some blue is always present; the blue *content* is
    // asserted as a large relative jump after switching tabs.)
    var framebuffer0 = try environment.renderToFramebuffer(&context, mod.TabView(selection.binding(), &tabs), .{ .x = 0, .y = 0, .width = 200, .height = 100 }, 200, 100);
    defer framebuffer0.deinit();
    try std.testing.expect(mod.TestEnvironment.countRed(&framebuffer0) > 100);
    const blue_with_red_tab = mod.TestEnvironment.countBlue(&framebuffer0);

    // tap the second tab-bar segment (a .select hit region targeting value 1)
    var tapped = false;
    for (environment.hits.items) |region| {
        if (region.action == .select and region.action.select.value == 1) {
            try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, region.rect.center()));
            tapped = true;
            break;
        }
    }
    try std.testing.expect(tapped);
    try std.testing.expectEqual(@as(i64, 1), selection.get());

    // re-render -> tab 1 (blue) content now shows, red is gone
    environment.hits.clearRetainingCapacity();
    var framebuffer1 = try environment.renderToFramebuffer(&context, mod.TabView(selection.binding(), &tabs), .{ .x = 0, .y = 0, .width = 200, .height = 100 }, 200, 100);
    defer framebuffer1.deinit();
    try std.testing.expect(mod.TestEnvironment.countBlue(&framebuffer1) > blue_with_red_tab + 100);
    try std.testing.expect(mod.TestEnvironment.countRed(&framebuffer1) < 100);
}

test "view: List wraps rows in a scroll + divider-separated stack" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const tree = mod.List(.{ mod.Text("a"), mod.Text("b") });
    try std.testing.expect(tree.kind == .scroll);
    const inner = tree.kind.scroll.content.*;
    try std.testing.expect(inner.kind == .stack);
    // 2 rows + 1 divider between them
    try std.testing.expectEqual(@as(usize, 3), inner.kind.stack.children.len);
}

// ── Painter seam ────────────────────────────────────────────────────────────

test "painter: macOS draws glass where Win2000 chisels a bevel" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const tree = mod.Button("OK", mod.Callback.action(Counter.increment));

    // macOS prominent button: a blue glass gradient.
    const prominent = mod.ButtonRoled("OK", .prominent, mod.Callback.action(Counter.increment));
    var macos_context = environment.context();
    macos_context.theme = renderer.MacosTheme.light;
    const macos_size = try mod.ViewRenderer.measure(&macos_context, prominent, .unspecified);
    const macos_width: u32 = @intFromFloat(@ceil(macos_size.width));
    const macos_height: u32 = @intFromFloat(@ceil(macos_size.height));
    environment.hits.clearRetainingCapacity();
    var macos_framebuffer = try environment.renderToFramebuffer(&macos_context, prominent, renderer.Rect.fromOriginSize(.{}, macos_size), macos_width, macos_height);
    defer macos_framebuffer.deinit();

    // Win2000 button: a silver face with a dark-shadow bottom bevel.
    var win2000_context = environment.context();
    win2000_context.theme = renderer.Win2000Theme.light;
    const win2000_size = try mod.ViewRenderer.measure(&win2000_context, tree, .unspecified);
    const win2000_width: u32 = @intFromFloat(@ceil(win2000_size.width));
    const win2000_height: u32 = @intFromFloat(@ceil(win2000_size.height));
    environment.hits.clearRetainingCapacity();
    var win2000_framebuffer = try environment.renderToFramebuffer(&win2000_context, tree, renderer.Rect.fromOriginSize(.{}, win2000_size), win2000_width, win2000_height);
    defer win2000_framebuffer.deinit();

    // Win2000's outer bottom edge is the dark-shadow grey; macOS's body is blue.
    const win2000_bottom = win2000_framebuffer.at(win2000_width / 2, win2000_height - 1);
    try std.testing.expect(win2000_bottom.approxEql(renderer.Win2000Theme.light.colors.control_dark_shadow, 0.2));
    const macos_middle = macos_framebuffer.at(macos_width / 2, macos_height / 2);
    try std.testing.expect(macos_middle.b > macos_middle.r); // glass gradient is blue, not grey
    // ...and that same spot in Win2000 is the neutral silver face, not blue.
    const win2000_middle = win2000_framebuffer.at(win2000_width / 2, win2000_height / 2);
    try std.testing.expect(!(win2000_middle.b > win2000_middle.r + 0.1));
}

test "painter: Material tint follows the color scheme" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    // A frosted panel over a known (white) backdrop: the glass tint comes from
    // the theme's scheme-correct `Palette.glass`, so light vs dark differ.
    const tree = mod.Empty().frame(40, 40).backgroundMaterial(.regular);
    const rect = renderer.Rect{ .x = 0, .y = 0, .width = 40, .height = 40 };

    var light_context = environment.context();
    light_context.theme = renderer.MacosTheme.light;
    var light_framebuffer = try environment.renderToFramebuffer(&light_context, tree, rect, 40, 40);
    defer light_framebuffer.deinit();

    var dark_context = environment.context();
    dark_context.theme = renderer.MacosTheme.dark;
    var dark_framebuffer = try environment.renderToFramebuffer(&dark_context, tree, rect, 40, 40);
    defer dark_framebuffer.deinit();

    // Light glass keeps the white backdrop bright; dark glass darkens it.
    try std.testing.expect(light_framebuffer.at(20, 20).luminance() > dark_framebuffer.at(20, 20).luminance() + 0.2);
}

test "painter: every family paints all controls without error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const families = [_]renderer.Theme{
        renderer.MacosTheme.light,
        renderer.MacosTheme.dark,
        renderer.Win2000Theme.light,
        renderer.Windows10Theme.light,
        renderer.Windows10Theme.dark,
        renderer.KdeTheme.light,
        renderer.KdeTheme.dark,
        renderer.MuiTheme.light,
        renderer.MuiTheme.dark,
    };
    const rect = renderer.Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    const knob = renderer.Rect{ .x = 0, .y = 0, .width = 18, .height = 18 };
    for (families) |theme| {
        var canvas = renderer.Canvas.init(arena.allocator());
        const surface = renderer.Surface{ .canvas = &canvas, .palette = &theme.colors, .metrics = &theme.metrics, .scheme = theme.scheme };
        const painter = theme.painter;
        _ = try painter.button(surface, rect, .normal, .{});
        try painter.field(surface, rect, 4, .{});
        try painter.segmented_track(surface, rect);
        _ = try painter.segmented_selection(surface, rect);
        try painter.switch_track(surface, rect, true);
        try painter.switch_knob(surface, knob, true);
        try painter.slider(surface, rect, 0.5, knob, .{});
        try painter.stepper_box(surface, rect, .{});
        try painter.progress(surface, rect, 0.5);
        try painter.panel(surface, rect, 8, .modal);
        try painter.panel(surface, rect, 8, .popover);
        try std.testing.expect(canvas.commands.items.len > 0);
    }
}

test "view: GeometryReader builds its content for the size it is laid out at" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const Probe = struct {
        const Self = @This();
        seen: renderer.Size = .{},
        fn body(self: *const Self, size: renderer.Size) mod.View {
            @constCast(self).seen = size;
            // Red on the left half, blue on the right: the halves follow the size.
            return mod.HStack(.{
                mod.Rectangle(renderer.Color.red).frame(size.width / 2, size.height),
                mod.Rectangle(renderer.Color.blue).frame(size.width / 2, size.height),
            }).spacing(0);
        }
    };
    var probe: Probe = .{};
    const view = mod.GeometryReader(Probe, &probe, Probe.body);
    var framebuffer = try environment.renderToFramebuffer(&context, view, .{ .x = 0, .y = 0, .width = 100, .height = 40 }, 100, 40);
    defer framebuffer.deinit();
    try std.testing.expectEqual(@as(f32, 100), probe.seen.width);
    try std.testing.expectEqual(@as(f32, 40), probe.seen.height);
    try std.testing.expect(framebuffer.at(30, 20).r > framebuffer.at(30, 20).b);
    try std.testing.expect(framebuffer.at(70, 20).b > framebuffer.at(70, 20).r);
}

test "view: clipped keeps content inside the frame" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    // A 90-wide red row centered in a 40-wide clipped frame (x -25..65)
    // paints only the frame.
    const view = mod.HStack(.{
        mod.HStack(.{ mod.Rectangle(renderer.Color.red).frame(30, 20), mod.Rectangle(renderer.Color.red).frame(60, 20) }).spacing(0).frame(40, 20).clipped(),
        mod.Spacer(),
    }).spacing(0).frameMaxWidth().frameAlign(.leading);
    var framebuffer = try environment.renderToFramebuffer(&context, view, .{ .x = 0, .y = 0, .width = 100, .height = 20 }, 100, 20);
    defer framebuffer.deinit();
    try std.testing.expect(framebuffer.at(20, 10).r > 0.9 and framebuffer.at(20, 10).g < 0.2);
    try std.testing.expect(framebuffer.at(55, 10).g > 0.9);
}

test "view: clipped content takes no taps outside the frame" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const Probe = struct {
        const Self = @This();
        var taps: u32 = 0;
        fn tapped(_: ?*anyopaque) void {
            taps += 1;
        }
    };
    // A 90-wide row centered in a 40-wide frame overflows it: its tappable
    // second box spans x 5..65, but only x 5..40 is visible, so only that
    // part takes taps.
    const view = mod.HStack(.{
        mod.HStack(.{
            mod.Rectangle(renderer.Color.red).frame(30, 20),
            mod.Rectangle(renderer.Color.red).frame(60, 20).onTap(.{ .function = Probe.tapped }),
        }).spacing(0).frame(40, 20).clipped(),
        mod.Spacer(),
    }).spacing(0).frameMaxWidth().frameAlign(.leading);
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, view, .{ .x = 0, .y = 0, .width = 100, .height = 20 }, &canvas);
    try std.testing.expect(!mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 55, .y = 10 }));
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 20, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.taps);
}

test "view: a row scrolled up under a header leaves the header its taps" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    const Probe = struct {
        const Self = @This();
        var header: u32 = 0;
        var rows: u32 = 0;
        fn headerTap(_: ?*anyopaque) void {
            header += 1;
        }
        fn rowTap(_: ?*anyopaque) void {
            rows += 1;
        }
    };
    var scroll: mod.ScrollState = .{ .offset = 30 };
    const row = mod.Rectangle(renderer.Color.blue).frame(200, 40).onTap(.{ .function = Probe.rowTap });
    // Scrolled by 30, the first row's frame (y 0..40) reaches up over the
    // header (y 0..30), though the viewport (y 30..130) hides that part.
    const view = mod.VStack(.{
        mod.Rectangle(renderer.Color.red).frame(200, 30).onTap(.{ .function = Probe.headerTap }),
        mod.ScrollViewState(&scroll, mod.VStack(.{ row, row, row, row, row }).spacing(0)).frameHeight(100),
        mod.Spacer(),
    }).spacing(0).frameMaxWidth().frameMaxHeight();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, view, .{ .x = 0, .y = 0, .width = 200, .height = 200 }, &canvas);
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 100, .y = 15 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.header);
    try std.testing.expectEqual(@as(u32, 0), Probe.rows);
    // Inside the viewport the row still takes it.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 100, .y = 35 }));
    try std.testing.expectEqual(@as(u32, 1), Probe.rows);
}

test "view: a passthrough row scrolled under a header leaves no hole there" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
    context.overlays = &overlays;
    var presented = renderer.State(bool).init(std.testing.allocator, true);
    defer presented.deinit();

    var scroll: mod.ScrollState = .{ .offset = 30 };
    const row = mod.Rectangle(renderer.Color.blue).frame(200, 40);
    // Scrolled by 30, the passthrough row's frame (y 0..40) reaches up over
    // the header (y 0..30), though the viewport (y 30..130) hides that part.
    const view = mod.VStack(.{
        mod.Rectangle(renderer.Color.red).frame(200, 30),
        mod.ScrollViewState(&scroll, mod.VStack(.{ row.popoverPassthrough(), row, row, row, row }).spacing(0)).frameHeight(100),
        mod.Rectangle(renderer.Color.green).frame(60, 30).popover(presented.binding(), mod.Rectangle(renderer.Color.white).frame(40, 40)),
        mod.Spacer(),
    }).spacing(0).frameMaxWidth().frameMaxHeight();
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, view, .{ .x = 0, .y = 0, .width = 200, .height = 200 }, &canvas);
    // The header is no hole: a tap there dismisses the popover.
    try std.testing.expect(mod.PointerInput.shared().tap(environment.hits.items, .{ .x = 100, .y = 15 }));
    try std.testing.expect(!presented.get());
}

test "a soft-wrap editor ending in a newline has a row for its empty last line" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    try field.setText("abc\n");
    mod.Focus.shared().set(&field);
    defer mod.Focus.shared().clear();
    var scroll: mod.ScrollState = .{};
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.TextEditor(&field, &scroll, false).softWrap(), .{ .x = 0, .y = 0, .width = 300, .height = 200 }, &canvas);

    // Two rows tall, and a click on the second line puts the caret after the newline.
    var clicked: ?usize = null;
    for (environment.hits.items) |hit| switch (hit.action) {
        .textClick => |click| {
            try std.testing.expectEqual(@as(usize, 2), click.rows.len);
            try std.testing.expectEqual(2 * click.line_height, scroll.content_height);
            clicked = click.caretIndexAt(.{ .x = click.origin.x + 2, .y = click.origin.y + click.line_height * 1.5 });
        },
        else => {},
    };
    try std.testing.expectEqual(@as(?usize, 4), clicked);
}
