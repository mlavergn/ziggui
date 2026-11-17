//! Media playback: a `Player` modeled on AVFoundation's `AVPlayer`, the
//! `PlayerBackend` the SDL runtime plugs a platform player into, and the
//! `VideoPlayer` view that shows a player's picture, with
//! `VideoPlayerControls` for the standard controls over it. Also `NativeView`, which
//! shows a platform view the app owns (a web view, say) where layout puts it.

const std = @import("std");
const log = std.log.scoped(.ziggui_media_module);

/// Whether a player's item can play.
pub const PlayerStatus = @import("player_observation.zig").PlayerStatus;
/// What a player is doing with time: paused, waiting, playing.
pub const PlayerTimeControl = @import("player_observation.zig").PlayerTimeControl;
/// One sample of a player's state (`Player.observe`).
pub const PlayerObservation = @import("player_observation.zig").PlayerObservation;
/// Audio or subtitles, for `Player.tracks` and `selectTrack`.
pub const PlayerTrackKind = @import("player_track.zig").PlayerTrackKind;
/// One audio or subtitle track of a player's item.
pub const PlayerTrack = @import("player_track.zig").PlayerTrack;
/// A platform media player's operations, installed by the SDL runtime.
pub const PlayerBackend = @import("player_backend.zig").PlayerBackend;
/// A media player modeled on `AVPlayer` (`replaceCurrentItem`, `play`, `seek`, `observe`, `tracks`).
pub const Player = @import("player.zig").Player;
/// A player's picture in the view tree.
pub const VideoPlayer = @import("video_player.zig").VideoPlayer;
/// The standard controls over a `VideoPlayer`: full screen, volume, transport, scrubber.
pub const VideoPlayerControls = @import("video_player_controls.zig").VideoPlayerControls;
/// What a `VideoPlayerControls` keeps across frames; app-owned.
pub const VideoPlayerControlsState = @import("video_player_controls_state.zig").VideoPlayerControlsState;
/// A platform view the app owns, placed where layout puts it.
pub const NativeView = @import("native_view.zig").NativeView;
/// What a platform web view reports about its page (`WebPage.update`).
pub const WebPageState = @import("web_page.zig").WebPageState;
/// A message a page posted to a bridge, borrowed for the call.
pub const WebPageMessage = @import("web_page.zig").WebPageMessage;
/// What `WebPage.onMessage` calls with each message.
pub const WebPageMessageCallback = @import("web_page.zig").WebPageMessageCallback;
/// A web page modeled on SwiftUI's `WebPage` (`load`, navigation, bridges, `onChange`).
pub const WebPage = @import("web_page.zig").WebPage;
/// A platform web view's operations, installed by the SDL runtime.
pub const WebPageBackend = @import("web_page_backend.zig").WebPageBackend;
/// A web page's view in the view tree.
pub const WebView = @import("web_view.zig").WebView;

// -----------------------------------------------------------------------------
// From the views module

/// A node of the view tree, from the views module.
pub const View = @import("../module.zig").View;

/// The frame clock a player keys its per-frame sample to, from the views module.
pub const FrameClock = @import("../module.zig").FrameClock;

/// A two-way handle into a value (`Player.volumeBinding`), from the views module.
pub const Binding = @import("../module.zig").Binding;

/// What a control's tap calls, from the views module.
pub const Callback = @import("../module.zig").Callback;

/// The frame's arena and tokens, from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;

/// Stacks built from views, from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;

/// Children side by side, from the views module.
pub const HStack = @import("../module.zig").HStack;

/// Children stacked vertically, from the views module.
pub const VStack = @import("../module.zig").VStack;

/// Children layered front to back, from the views module.
pub const ZStack = @import("../module.zig").ZStack;

/// Flexible space in a stack, from the views module.
pub const Spacer = @import("../module.zig").Spacer;

/// A view that draws nothing, from the views module.
pub const Empty = @import("../module.zig").Empty;

/// A symbol from the icon set, from the views module.
pub const Icon = @import("../module.zig").Icon;

/// A line of text, from the views module.
pub const Text = @import("../module.zig").Text;

/// A value picked along a track, from the views module.
pub const Slider = @import("../module.zig").Slider;

/// Draws and taps views in tests, from the views module.
pub const TestCanvas = @import("../module.zig").TestCanvas;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("player_observation.zig");
    _ = @import("player_track.zig");
    _ = @import("player_backend.zig");
    _ = @import("player.zig");
    _ = @import("video_player.zig");
    _ = @import("native_view.zig");
    _ = @import("video_player_controls_state.zig");
    _ = @import("video_player_controls.zig");
    _ = @import("web_page.zig");
    _ = @import("web_page_backend.zig");
    _ = @import("web_view.zig");
}
