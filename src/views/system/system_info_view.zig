//! A `SystemReport` as columned forms: `VideoInfoView` (how the window draws
//! and the media player), `AudioInfoView` (the output in use and the
//! devices), and `SystemInfoView`, both in one form, an app's "System Info"
//! sheet's body.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_system_info_view);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds the form's rows.
const Rows = struct {
    const Self = @This();

    /// A row: its label and a selectable value ("Unknown" for an empty one).
    ///
    /// - `label`: the label, its colon included.
    /// - `value`: the value.
    /// - Returns: the row.
    fn row(label: []const u8, value: []const u8) mod.View {
        return mod.LabeledContent(label, mod.Text(mod.DisplayText.clean(mod.BuildScope.shared().allocator(), mod.SystemReport.orUnknown(value))).textSelection(.enabled));
    }

    /// The audio devices, one a line, the system's default marked.
    ///
    /// - `report`: the report.
    /// - Returns: the lines, or "None listed".
    fn devices(report: *const mod.SystemReport) mod.View {
        const allocator = mod.BuildScope.shared().allocator();
        if (report.audio_outputs.len == 0) return mod.Text("None listed").foregroundStyle(mod.BuildScope.shared().tokens().secondary_label);
        var lines: std.ArrayList(mod.View) = .empty;
        for (report.audio_outputs) |output| {
            const line = allocator.print("{s}{s}", .{ output.name, output.defaultMark() }) catch @panic("oom");
            lines.append(allocator, mod.Text(mod.DisplayText.clean(allocator, line)).textSelection(.enabled)) catch @panic("oom");
        }
        return mod.StackBuilder.fromSlice(.vertical, 4, .leading, lines.items);
    }

    /// The drawing section: the renderer, the graphics driver, the GPU and its
    /// driver's version.
    ///
    /// - `report`: the report.
    /// - Returns: the section.
    fn graphics(report: *const mod.SystemReport) mod.View {
        return mod.Section(.{
            Self.row("Renderer:", report.renderer.label()),
            Self.row("Graphics driver:", report.graphics_driver),
            Self.row("GPU:", report.gpu),
            Self.row("GPU driver version:", report.gpu_driver_version),
        });
    }

    /// The player section: the media player and its version.
    ///
    /// - `report`: the report.
    /// - Returns: the section.
    fn player(report: *const mod.SystemReport) mod.View {
        return mod.Section(.{
            Self.row("Player:", report.playerName()),
            Self.row("Player version:", report.player_version),
        });
    }

    /// The audio section: the output in use and every device.
    ///
    /// - `report`: the report.
    /// - `audio_output`: the output in use (its id), or null for the system default.
    /// - Returns: the section.
    fn audio(report: *const mod.SystemReport, audio_output: ?[]const u8) mod.View {
        const output = report.outputName(audio_output) orelse
            mod.BuildScope.shared().allocator().print("{s}{s}", .{ audio_output.?, mod.SystemReport.not_connected }) catch @panic("oom");
        return mod.Section(.{
            Self.row("Audio output:", output),
            mod.LabeledContent("Audio devices:", Self.devices(report)),
        });
    }
};

/// A `SystemReport` as a columned form: the renderer, the graphics driver,
/// the GPU and its driver's version; the player and its version; the output
/// a player plays through and every audio device. Values are selectable, so
/// they can be copied; `SystemReport.text` gives the whole report as lines.
///
/// - `report`: what `SystemInfo.report` found; it must outlive the frame.
/// - `audio_output`: the output the app's player plays through (its id), or null for the system default.
/// - Returns: the form.
pub fn SystemInfoView(report: *const mod.SystemReport, audio_output: ?[]const u8) mod.View {
    return mod.Form(.{ Rows.graphics(report), Rows.player(report), Rows.audio(report, audio_output) });
}

/// The video half of a `SystemReport` as a columned form: the renderer, the
/// graphics driver, the GPU and its driver's version; the player and its version.
///
/// - `report`: what `SystemInfo.report` found; it must outlive the frame.
/// - Returns: the form.
pub fn VideoInfoView(report: *const mod.SystemReport) mod.View {
    return mod.Form(.{ Rows.graphics(report), Rows.player(report) });
}

/// The audio half of a `SystemReport` as a columned form: the output a player
/// plays through and every audio device, the system's default marked.
///
/// - `report`: what `SystemInfo.report` found; it must outlive the frame.
/// - `audio_output`: the output the player plays through (its id), or null for the system default.
/// - Returns: the form.
pub fn AudioInfoView(report: *const mod.SystemReport, audio_output: ?[]const u8) mod.View {
    return mod.Form(.{Rows.audio(report, audio_output)});
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the system info view draws a report" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const outputs = [_]mod.AudioOutput{.{ .id = "spk", .name = "Speakers", .is_default = true }};
    const report: mod.SystemReport = .{ .renderer = .software, .graphics_driver = "opengl", .audio_outputs = &outputs };
    window.begin(renderer.MacosTheme.light);
    const views = [_]mod.View{ SystemInfoView(&report, null), VideoInfoView(&report), AudioInfoView(&report, "spk") };
    window.end();
    for (views) |view| {
        var frame = try window.render(view, 480, 360);
        frame.deinit();
    }
}
