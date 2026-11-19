//! System information: how the window draws (noted by the SDL runtime), the
//! media player behind `Player`, and the audio outputs, read into a
//! `SystemReport` and shown by `SystemInfoView`, an app's "System Info" sheet.

const std = @import("std");
const log = std.log.scoped(.ziggui_system_module);

/// How the window's frames are drawn: GPU, software, or not yet known.
pub const GraphicsRenderer = @import("system_report.zig").GraphicsRenderer;
/// One reading of the system (`SystemInfo.report`).
pub const SystemReport = @import("system_report.zig").SystemReport;
/// The system facts the runtime notes, and the report over them.
pub const SystemInfo = @import("system_info.zig").SystemInfo;
/// A `SystemReport` as a columned form.
pub const SystemInfoView = @import("system_info_view.zig").SystemInfoView;
/// How the window draws and the media player, as a columned form.
pub const VideoInfoView = @import("system_info_view.zig").VideoInfoView;
/// The audio output in use and the devices, as a columned form.
pub const AudioInfoView = @import("system_info_view.zig").AudioInfoView;

// -----------------------------------------------------------------------------
// From the views module

/// A node of the view tree, from the views module.
pub const View = @import("../module.zig").View;
/// The frame's arena and tokens, from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// Stacks built from slices, from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A line of text, from the views module.
pub const Text = @import("../module.zig").Text;
/// Text made safe to draw, from the views module.
pub const DisplayText = @import("../module.zig").DisplayText;
/// A columned form, from the views module.
pub const Form = @import("../module.zig").Form;
/// A form's section, from the views module.
pub const Section = @import("../module.zig").Section;
/// A form's labeled row, from the views module.
pub const LabeledContent = @import("../module.zig").LabeledContent;
/// One audio output, from the views module.
pub const AudioOutput = @import("../module.zig").AudioOutput;
/// The audio outputs, from the views module.
pub const AudioOutputs = @import("../module.zig").AudioOutputs;
/// The media player (its installed backend's name and version), from the views module.
pub const Player = @import("../module.zig").Player;
/// A headless window for the unit tests (from the views module).
pub const TestWindow = @import("../module.zig").TestWindow;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("system_report.zig");
    _ = @import("system_info.zig");
    _ = @import("system_info_view.zig");
}
