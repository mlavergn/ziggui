//! The Media Audio section's voice memos card: records a memo from the
//! microphone with `AudioRecorder`, keeps it as a WAV file (`AudioClip`), and
//! plays it back with `AudioClipPlayer`, apart from the section's `Player`
//! and the output it plays through. ziggui keeps no files: `main.zig` names
//! the folder (`keep`, a `memos` folder beside the gallery's settings) and
//! the card reads, writes, renames and deletes the files there. Headless and
//! in tests no folder is named, so nothing is read or written and the memos
//! last only while the gallery runs.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_voice_memos);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// One memo: its name (renamed in place), its length, its sound while
/// decoded, and the name its file has on disk.
const Memo = struct {
    const Self = @This();

    /// The name the row shows and renames.
    name: ziggui.EditableTextState,

    /// The sound, owned by the card's allocator: null for a memo read from
    /// the folder until it is played, and again once another plays, so the
    /// card holds one memo's samples however many it lists.
    clip: ?ziggui.AudioClip = null,

    /// How long it plays, in seconds, known without its samples.
    duration: f64,

    /// Its file is in the folder, so its sound can be read again once let go.
    on_disk: bool = false,

    /// The name of its file without its extension, as last written or
    /// renamed; owned by the card's allocator.
    saved_name: []u8,

    /// Its file's extension as found (`.wav`, or `.WAV` and the like for a
    /// file read from the folder), so a case-sensitive file system finds it.
    extension: [VoiceMemos.extension.len]u8 = VoiceMemos.extension.*,

    /// Frees the memo's name, sound and saved name.
    ///
    /// - `self`: the memo.
    /// - `allocator`: the card's allocator.
    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.name.deinit();
        if (self.clip) |*clip| clip.deinit(allocator);
        allocator.free(self.saved_name);
    }
};

/// One of the memos `VoiceMemos.showSample` makes: a tone.
const SampleMemo = struct {
    const Self = @This();

    /// The memo's name.
    name: []const u8,

    /// The tone's pitch, in hertz.
    pitch: f64,

    /// Its length, in seconds.
    seconds: usize,
};

/// The voice memos card and its memos.
pub const VoiceMemos = struct {
    const Self = @This();

    /// The memo files' extension.
    const extension = ".wav";

    /// The largest memo file read, in bytes (ten minutes at 48 kHz is about 55 MB).
    const max_file_bytes = 128 * 1024 * 1024;

    /// The most memos read from the folder.
    const max_memos = 200;

    /// The rate `showSample`'s memos are made at, in samples a second.
    pub const sample_rate: u32 = 8000;

    /// Owns the memos and the folder's path.
    allocator: std.mem.Allocator,

    /// Records the next memo.
    recorder: ziggui.AudioRecorder,

    /// Plays a memo back.
    player: ziggui.AudioClipPlayer = .{},

    /// The memos, oldest first; each on the heap, so its name's state and
    /// its clip (which the player borrows) stay put.
    memos: std.ArrayList(*Memo) = .empty,

    /// The selected row, or null.
    selection: ?usize = null,

    /// Whether the input menu is shown.
    input_menu: ziggui.State(bool),

    /// The chosen input's name as the menu last listed it, for the menu's
    /// label; the devices are listed only while the menu is open, so drawing
    /// the card never starts the system's audio.
    input_name: [96]u8 = undefined,

    /// How many bytes of `input_name` hold it; 0 for the system default.
    input_name_length: usize = 0,

    /// The folder memos are kept in, owned; null keeps them in memory only.
    folder: ?[]u8 = null,

    /// The I/O the folder is read and written through, with `folder`.
    io: ?std.Io = null,

    /// The folder has been read (or there is none to read).
    loaded: bool = false,

    /// The last problem with the files, for the status line (static).
    notice: []const u8 = "",

    /// A card with no memos and no folder.
    ///
    /// - `allocator`: owns the memos; must outlive the card.
    /// - Returns: the card.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .allocator = allocator,
            .recorder = ziggui.AudioRecorder.init(allocator),
            .input_menu = ziggui.State(bool).init(allocator, false),
        };
        return self;
    }

    /// Stops recording and playing and frees the memos (their files stay).
    ///
    /// - `self`: the card.
    pub fn deinit(self: *Self) void {
        // The player first: it borrows a memo's clip.
        self.player.deinit();
        if (self.folder) |folder| self.allocator.free(folder);
        self.input_menu.deinit();
        for (self.memos.items) |memo| {
            memo.deinit(self.allocator);
            self.allocator.destroy(memo);
        }
        self.memos.deinit(self.allocator);
        self.recorder.deinit();
    }

    /// Reads the folder's memos, once (the gallery calls it as the Media
    /// Audio section opens); a file that cannot be read is logged and left.
    ///
    /// - `self`: the card.
    pub fn load(self: *Self) void {
        if (self.loaded) return;
        self.loaded = true;
        const folder = self.folder orelse return;
        const io = self.io.?;
        var dir = std.Io.Dir.cwd().openDir(io, folder, .{ .iterate = true }) catch |err| {
            if (err != error.FileNotFound) {
                log.warn("memos not read from {s}: {s}", .{ folder, @errorName(err) });
                self.notice = "The memos folder could not be read.";
            }
            return;
        };
        defer dir.close(io);
        var entries = dir.iterate();
        while (entries.next(io) catch |err| {
            log.warn("memos not listed in {s}: {s}", .{ folder, @errorName(err) });
            self.notice = "The memos folder could not be read.";
            return;
        }) |entry| {
            if (self.memos.items.len >= max_memos) break;
            if (entry.kind != .file or !Self.isMemoFile(entry.name)) continue;
            self.loadFile(dir, entry.name) catch |err| {
                log.warn("memo {s} not read: {s}", .{ entry.name, @errorName(err) });
                self.notice = "A memo file could not be read.";
            };
        }
        std.mem.sort(*Memo, self.memos.items, {}, Self.namedBefore);
    }

    /// Keeps the memos in a `memos` folder inside `settings`, read as the
    /// section first shows (`load`); `main.zig` calls it as the window opens.
    ///
    /// - `self`: the card.
    /// - `io`: the I/O the files are read and written through.
    /// - `settings`: the gallery's settings folder, or null for none.
    pub fn keep(self: *Self, io: std.Io, settings: ?[]const u8) void {
        const folder = settings orelse return;
        if (self.folder) |old| self.allocator.free(old);
        self.folder = std.fs.path.join(self.allocator, &.{ folder, "memos" }) catch |err| {
            log.warn("memos not kept: {s}", .{@errorName(err)});
            self.folder = null;
            return;
        };
        self.io = io;
        self.loaded = false;
    }

    /// The card: Record and Pause, the take's time and level, the input
    /// menu, a status line, and a row per memo.
    ///
    /// - `self`: the card.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn card(self: *Self, theme: ziggui.Theme) ziggui.View {
        return gallery.Card.view(theme, "AudioRecorder: record a memo from the microphone, keep it as a WAV file, play it back", "ziggui.AudioRecorder · ziggui.AudioClipPlayer · ziggui.AudioClip · ziggui.AudioDevices", ziggui.VStack(.{
            self.controls(),
            self.gainRow(theme),
            ziggui.Text(self.status()).foregroundStyle(theme.colors.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            ziggui.Divider(),
            self.rows(theme),
        }).spacing(10).frameMaxWidth());
    }

    /// Takes what the microphone captured into the take and stops a memo
    /// played to its end; the gallery calls it every frame, whatever section
    /// shows, so a take left recording elsewhere keeps to its limit.
    ///
    /// - `self`: the card.
    pub fn update(self: *Self) void {
        self.recorder.update();
        self.player.update();
    }

    /// Fills the card for a screenshot (`--memos`): two memos of a tone,
    /// the second selected and playing, and a take recording, through the
    /// installed backend (`ziggui.TestAudioDevices` headless).
    ///
    /// - `self`: the card.
    pub fn showSample(self: *Self) void {
        const made = [_]SampleMemo{ .{ .name = "Grocery list", .pitch = 440, .seconds = 2 }, .{ .name = "Interview notes", .pitch = 660, .seconds = 5 } };
        for (made) |sample| {
            const samples = self.allocator.alloc(i16, sample.seconds * sample_rate) catch |err| {
                log.warn("sample memo not made: {s}", .{@errorName(err)});
                return;
            };
            for (samples, 0..) |*value, index| {
                const phase = 2 * std.math.pi * sample.pitch * @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(sample_rate));
                value.* = @intFromFloat(@sin(phase) * 8000);
            }
            var clip: ziggui.AudioClip = .{ .samples = samples, .sample_rate = sample_rate };
            _ = self.add(sample.name, clip, clip.duration()) catch |err| {
                log.warn("sample memo not made: {s}", .{@errorName(err)});
                clip.deinit(self.allocator);
                return;
            };
        }
        self.playTapped(1);
        _ = self.recorder.record();
    }

    /// Gives a key to the memo being renamed: Esc cancels it.
    ///
    /// - `self`: the card.
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when a row took it.
    pub fn keyDown(self: *Self, keycode: u32, modifiers: u16) bool {
        for (self.memos.items) |memo| {
            if (memo.name.keyDown(keycode, modifiers)) return true;
        }
        return false;
    }

    /// The recording row: Record (Stop while a take runs), Pause or Resume,
    /// the take's time, its level, the playback volume, and the input menu
    /// where devices are.
    ///
    /// - `self`: the card.
    /// - Returns: the row.
    fn controls(self: *Self) ziggui.View {
        const available = ziggui.AudioDevices.available();
        const idle = self.recorder.status == .idle;
        const record = if (idle)
            ziggui.ButtonRoled("Record", .prominent, ziggui.Callback.init(Self, self, Self.toggleRecording)).disabled(!available)
        else
            ziggui.ButtonRoled("Stop", .destructive, ziggui.Callback.init(Self, self, Self.toggleRecording));
        const pause = if (idle)
            ziggui.Empty()
        else
            ziggui.Button(if (self.recorder.status == .paused) "Resume" else "Pause", ziggui.Callback.init(Self, self, Self.togglePause)).disabled(self.recorder.reached_limit or self.recorder.out_of_memory);
        const menu = if (available) self.inputMenu() else ziggui.Empty();
        const volume = self.player.volume;
        const speaker: ziggui.IconName = if (volume == 0) .volumeX else if (volume < 0.5) .volume1 else .volume2;
        return ziggui.HStack(.{
            record,
            pause,
            ziggui.Text(Self.clock(self.recorder.currentTime())).monospaced(),
            ziggui.ProgressView(self.recorder.level).frameWidth(120),
            ziggui.Spacer(),
            ziggui.HStack(.{
                ziggui.Icon(speaker, 14, ziggui.BuildScope.shared().tokens().secondary_label),
                ziggui.Slider(self.player.volumeBinding(), 0, 1).frameWidth(110),
            }).spacing(6).help("Playback volume"),
            menu,
        }).spacing(8).frameMaxWidth();
    }

    /// The software gain row: a slider from silent to twice the microphone's
    /// level and the factor, named "Software gain", since it scales the
    /// samples SDL hands the recorder and leaves the microphone's own input
    /// level (the system's sound settings) alone.
    ///
    /// - `self`: the card.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the row.
    fn gainRow(self: *Self, theme: ziggui.Theme) ziggui.View {
        const secondary = theme.colors.secondary_label;
        const factor = ziggui.BuildScope.shared().allocator().print("{d:.2}×", .{self.recorder.gain}) catch @panic("oom");
        return ziggui.HStack(.{
            ziggui.Icon(.mic, 14, secondary),
            ziggui.Text("Software gain"),
            ziggui.Slider(self.recorder.gainBinding(), 0, ziggui.AudioRecorder.max_gain).frameWidth(160),
            ziggui.Text(factor).monospaced().foregroundStyle(secondary),
            ziggui.Text("Not the microphone's input level.").font(.footnote).foregroundStyle(secondary).truncated(),
            ziggui.Spacer(),
        }).spacing(8).frameMaxWidth().help("Software gain: SDL scales the samples before the memo gets them, noise too, and a sample past full scale clips. The microphone's input level is set in the system's sound settings.");
    }

    /// The input menu: the system default and each recording device, the
    /// recorder's ticked; the devices are listed only while it is open.
    ///
    /// - `self`: the card.
    /// - Returns: the menu's button.
    fn inputMenu(self: *Self) ziggui.View {
        const allocator = ziggui.BuildScope.shared().allocator();
        const label = if (self.input_name_length > 0) allocator.print("Input: {s}", .{self.input_name[0..self.input_name_length]}) catch @panic("oom") else "Input: System default";
        if (!self.input_menu.get()) return ziggui.Menu(label, &self.input_menu, .{});
        const devices = ziggui.AudioDevices.list(allocator, .recording) catch @panic("oom");
        const chosen = ziggui.AudioDevices.indexOf(devices, self.recorder.device);
        var items: std.ArrayList(ziggui.View) = .empty;
        items.append(allocator, ziggui.MenuItem(if (chosen == null) "✓ System default" else "   System default", ziggui.Callback.tagged(Self, self, Self.chooseInput, 0))) catch @panic("oom");
        for (devices, 0..) |device, index| {
            const name = ziggui.DisplayText.clean(allocator, device.name);
            const title = allocator.print("{s}{s}", .{ if (chosen == index) "✓ " else "   ", name }) catch @panic("oom");
            // The tag is the device's id plus one, so a list that changed
            // since the menu was drawn never picks another device.
            items.append(allocator, ziggui.MenuItem(title, ziggui.Callback.tagged(Self, self, Self.chooseInput, @as(usize, device.id) + 1))) catch @panic("oom");
        }
        return ziggui.Menu(label, &self.input_menu, items.items);
    }

    /// The status line: why nothing records, what the take is doing, or
    /// where the memos are kept.
    ///
    /// - `self`: the card.
    /// - Returns: the line, static or in the build arena.
    fn status(self: *const Self) []const u8 {
        if (!ziggui.AudioDevices.available()) return "No audio devices here: the gallery records in a window.";
        if (self.recorder.failed) return "The microphone could not be opened (on macOS, allow it under System Settings › Privacy & Security › Microphone).";
        if (self.player.failed) return "The memo could not be played.";
        if (self.recorder.out_of_memory) return "Recording paused: memory ran out. Stop keeps what was recorded.";
        if (self.recorder.reached_limit) return "The take reached its ten-minute limit: Stop keeps it.";
        switch (self.recorder.status) {
            .recording => return "Recording…",
            .paused => return "Paused: Resume adds to the take, Stop keeps it.",
            .idle => {},
        }
        if (self.notice.len > 0) return self.notice;
        const folder = self.folder orelse return "Memos are kept until the gallery quits.";
        const shown = ziggui.DisplayText.clean(ziggui.BuildScope.shared().allocator(), folder);
        return ziggui.BuildScope.shared().allocator().print("Memos are kept in {s}", .{shown}) catch @panic("oom");
    }

    /// The memo rows, or a line saying there are none.
    ///
    /// - `self`: the card.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the rows.
    fn rows(self: *Self, theme: ziggui.Theme) ziggui.View {
        if (self.memos.items.len == 0) return ziggui.Text("No memos yet.").foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading);
        const allocator = ziggui.BuildScope.shared().allocator();
        const views = allocator.alloc(ziggui.View, self.memos.items.len) catch @panic("oom");
        for (self.memos.items, views, 0..) |memo, *row, index| {
            const selected = self.selection == index;
            const color = ziggui.SelectableRowStyle.selectionText(selected, true);
            const secondary = ziggui.SelectableRowStyle.secondaryText(selected, true);
            const tapped = ziggui.Callback.tagged(Self, self, Self.select, index);
            const name = ziggui.EditableText(&memo.name, selected, tapped, ziggui.Callback.tagged(Self, self, Self.renamed, index));
            const playing = self.holds(memo) and self.player.playing;
            const length = memo.duration;
            const time = if (self.holds(memo))
                allocator.print("{s} / {s}", .{ Self.clock(self.player.currentTime()), Self.clock(length) }) catch @panic("oom")
            else
                Self.clock(length);
            const play = ziggui.IconButton(if (playing) .pause else .play, 14, ziggui.Callback.tagged(Self, self, Self.playTapped, index)).help(if (playing) "Pause" else "Play");
            const delete_button = ziggui.IconButton(.trash2, 14, ziggui.Callback.tagged(Self, self, Self.remove, index)).help("Delete");
            // Editing, the field keeps its own colors and takes the rest of the row.
            const content = if (memo.name.editing)
                ziggui.HStack(.{ play, name, delete_button })
            else
                ziggui.HStack(.{ play, name.foregroundStyle(color), ziggui.Spacer(), ziggui.Text(time).monospaced().foregroundStyle(secondary), delete_button });
            row.* = ziggui.SelectableRow(content.spacing(6), selected, true, tapped);
        }
        return ziggui.StackBuilder.fromSlice(.vertical, 2, .leading, views).frameMaxWidth();
    }

    /// Record or Stop: starts a take (stopping a memo playing, so the
    /// speaker is not recorded), or ends it and keeps it as a memo.
    ///
    /// - `self`: the card.
    fn toggleRecording(self: *Self) void {
        if (self.recorder.status != .idle) return self.stopRecording();
        self.player.stop();
        self.notice = "";
        _ = self.recorder.record();
    }

    /// Pause or Resume: holds the take, or adds to it again.
    ///
    /// - `self`: the card.
    fn togglePause(self: *Self) void {
        if (self.recorder.status == .paused) {
            _ = self.recorder.record();
        } else {
            self.recorder.pause();
        }
    }

    /// Ends the take and keeps it as a new memo, named "Memo N", written to
    /// the folder where there is one, and selects it.
    ///
    /// - `self`: the card.
    fn stopRecording(self: *Self) void {
        self.keepTake() catch |err| {
            log.warn("memo not kept: {s}", .{@errorName(err)});
            self.notice = "The memo could not be kept.";
        };
    }

    /// Ends the take and adds it as a memo under the first free name,
    /// selected, and saves it.
    ///
    /// - `self`: the card.
    /// - Returns: nothing; propagates allocation failure, the take then dropped.
    fn keepTake(self: *Self) std.mem.Allocator.Error!void {
        var clip = (try self.recorder.stop()) orelse return;
        errdefer clip.deinit(self.allocator);
        const name = try self.freeName();
        defer self.allocator.free(name);
        const memo = try self.add(name, clip, clip.duration());
        self.selection = self.memos.items.len - 1;
        self.save(memo);
    }

    /// A tap on a row's play button: plays its memo, or pauses it while it plays.
    ///
    /// - `self`: the card.
    /// - `index`: the row.
    fn playTapped(self: *Self, index: usize) void {
        if (index >= self.memos.items.len) return;
        const memo = self.memos.items[index];
        self.selection = index;
        if (self.holds(memo) and self.player.playing) return self.player.pause();
        if (self.recorder.status != .idle) return;
        if (!self.holds(memo)) {
            self.player.stop();
            self.releaseExcept(memo);
        }
        const clip = self.decoded(memo) catch |err| {
            log.warn("memo {s} not read: {s}", .{ memo.saved_name, @errorName(err) });
            self.notice = "The memo could not be read.";
            return;
        };
        _ = self.player.play(clip);
    }

    /// A tap on a row's name or ground: selects it.
    ///
    /// - `self`: the card.
    /// - `index`: the row.
    fn select(self: *Self, index: usize) void {
        self.selection = index;
    }

    /// A row's name was renamed: renames its file, or puts the name back
    /// when it cannot be a file's name or another memo has it.
    ///
    /// - `self`: the card.
    /// - `index`: the row.
    fn renamed(self: *Self, index: usize) void {
        if (index >= self.memos.items.len) return;
        const memo = self.memos.items[index];
        const wanted = std.mem.trim(u8, memo.name.text(), " ");
        const name = self.fileName(wanted) catch |err| {
            log.warn("memo not renamed: {s}", .{@errorName(err)});
            return self.restoreName(memo, "The memo could not be renamed.");
        };
        defer self.allocator.free(name);
        if (name.len == 0) return self.restoreName(memo, "");
        if (std.ascii.eqlIgnoreCase(name, memo.saved_name)) {
            // Only the case changed, or nothing: the file system may not tell the two apart.
            if (std.mem.eql(u8, name, memo.saved_name)) return self.restoreName(memo, "");
        } else if (self.named(name) != null) {
            return self.restoreName(memo, "Another memo has that name.");
        }
        const saved = self.allocator.dupe(u8, name) catch |err| {
            log.warn("memo not renamed: {s}", .{@errorName(err)});
            return self.restoreName(memo, "The memo could not be renamed.");
        };
        if (self.folder != null) {
            self.renameFile(memo, name) catch |err| {
                log.warn("memo file not renamed: {s}", .{@errorName(err)});
                self.allocator.free(saved);
                const why = if (err == error.PathAlreadyExists) "A file in the memos folder has that name." else "The memo's file could not be renamed.";
                return self.restoreName(memo, why);
            };
        }
        self.allocator.free(memo.saved_name);
        memo.saved_name = saved;
        memo.name.setText(name) catch |err| log.warn("memo name not shown: {s}", .{@errorName(err)});
        self.notice = "";
    }

    /// Deletes a memo and its file.
    ///
    /// - `self`: the card.
    /// - `index`: the row.
    fn remove(self: *Self, index: usize) void {
        if (index >= self.memos.items.len) return;
        const memo = self.memos.items[index];
        if (self.holds(memo)) self.player.stop();
        if (self.folder != null) {
            self.deleteFile(memo) catch |err| {
                log.warn("memo file not deleted: {s}", .{@errorName(err)});
                self.notice = "The memo's file could not be deleted.";
                return;
            };
        }
        _ = self.memos.orderedRemove(index);
        memo.deinit(self.allocator);
        self.allocator.destroy(memo);
        if (self.selection) |selected| {
            if (selected == index) self.selection = null else if (selected > index) self.selection = selected - 1;
        }
    }

    /// An input menu entry: records the next take from that device.
    ///
    /// - `self`: the card.
    /// - `tag`: 0 for the system default, else the device's id plus one.
    fn chooseInput(self: *Self, tag: usize) void {
        self.input_menu.set(false);
        self.recorder.device = null;
        self.input_name_length = 0;
        if (tag == 0) return;
        const id: u32 = @intCast(tag - 1);
        const devices = ziggui.AudioDevices.list(self.allocator, .recording) catch |err| {
            log.warn("input not chosen: {s}", .{@errorName(err)});
            return;
        };
        defer ziggui.AudioDevices.free(self.allocator, devices);
        // Unplugged since the menu was drawn: the default stays.
        const index = ziggui.AudioDevices.indexOf(devices, id) orelse return;
        self.recorder.device = id;
        const name = ziggui.DisplayText.clean(self.allocator, devices[index].name);
        defer if (name.ptr != devices[index].name.ptr) self.allocator.free(name);
        self.input_name_length = ziggui.DisplayText.fitLength(name, self.input_name.len);
        @memcpy(self.input_name[0..self.input_name_length], name[0..self.input_name_length]);
    }

    /// Puts a memo's name back as its file has it, saying why.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo.
    /// - `why`: the status line's notice, static; empty for none.
    fn restoreName(self: *Self, memo: *Memo, why: []const u8) void {
        memo.name.setText(memo.saved_name) catch |err| log.warn("memo name not restored: {s}", .{@errorName(err)});
        self.notice = why;
    }

    /// Adds a memo at the end of the list, taking the clip.
    ///
    /// - `self`: the card.
    /// - `name`: its name; copied.
    /// - `clip`: its sound, owned by the card's allocator from now on
    ///   (left to the caller on failure); null for one read when played.
    /// - `duration`: how long it plays, in seconds.
    /// - Returns: the memo; propagates allocation failure.
    fn add(self: *Self, name: []const u8, clip: ?ziggui.AudioClip, duration: f64) std.mem.Allocator.Error!*Memo {
        const memo = try self.allocator.create(Memo);
        errdefer self.allocator.destroy(memo);
        const saved_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(saved_name);
        var state = try ziggui.EditableTextState.init(self.allocator, name);
        errdefer state.deinit();
        try self.memos.ensureUnusedCapacity(self.allocator, 1);
        memo.* = .{ .name = state, .clip = clip, .duration = duration, .saved_name = saved_name };
        self.memos.appendAssumeCapacity(memo);
        return memo;
    }

    /// The first "Memo N" no memo has, case aside, and no file in the
    /// folder has (one the card did not read, say), so saving it never
    /// replaces a file.
    ///
    /// - `self`: the card.
    /// - Returns: the name, owned by the caller; propagates allocation failure.
    fn freeName(self: *const Self) std.mem.Allocator.Error![]u8 {
        var number: usize = self.memos.items.len + 1;
        while (true) : (number += 1) {
            const name = try self.allocator.print("Memo {d}", .{number});
            if (self.named(name) == null and !try self.fileExists(name)) return name;
            self.allocator.free(name);
        }
    }

    /// Whether the folder holds a file a new memo of this name would take.
    ///
    /// - `self`: the card.
    /// - `name`: the name without its extension.
    /// - Returns: true when one is there (or the folder cannot say); false
    ///   with no folder; propagates allocation failure.
    fn fileExists(self: *const Self, name: []const u8) std.mem.Allocator.Error!bool {
        if (self.folder == null) return false;
        const path = try self.pathOf(name, extension);
        defer self.allocator.free(path);
        std.Io.Dir.cwd().access(self.io.?, path, .{}) catch |err| return err != error.FileNotFound;
        return true;
    }

    /// The memo whose file has a name, case aside (as macOS and Windows compare them).
    ///
    /// - `self`: the card.
    /// - `name`: the name without `.wav`.
    /// - Returns: its index, or null.
    fn named(self: *const Self, name: []const u8) ?usize {
        for (self.memos.items, 0..) |memo, index| {
            if (std.ascii.eqlIgnoreCase(memo.saved_name, name)) return index;
        }
        return null;
    }

    /// Writes a memo's file where there is a folder; a failure is logged and
    /// noted, the memo kept in memory.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo.
    fn save(self: *Self, memo: *Memo) void {
        if (self.folder == null) return;
        self.writeFile(memo) catch |err| {
            log.warn("memo {s} not saved: {s}", .{ memo.saved_name, @errorName(err) });
            self.notice = "The memo could not be saved: it is kept until the gallery quits.";
            return;
        };
        memo.on_disk = true;
    }

    /// Writes a new memo's WAV file in the folder, making the folder if need
    /// be, through a temporary file linked into place, so a crash never
    /// leaves a torn one and a file already there is never replaced.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo.
    /// - Returns: nothing; `error.PathAlreadyExists` for a file of its name;
    ///   propagates a failed allocation, encode, create, write or link.
    fn writeFile(self: *Self, memo: *const Memo) !void {
        const folder = self.folder orelse return;
        const io = self.io.?;
        const bytes = try memo.clip.?.encodeWav(self.allocator);
        defer self.allocator.free(bytes);
        const path = try self.pathOf(memo.saved_name, &memo.extension);
        defer self.allocator.free(path);
        try std.Io.Dir.cwd().createDirPath(io, folder);
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{});
        defer atomic.deinit(io);
        try atomic.file.writeStreamingAll(io, bytes);
        try atomic.link(io);
    }

    /// Renames a memo's file in the folder, never over another file. A
    /// change of case alone goes through a temporary name, since a file
    /// system that ignores case sees the new name taken by the file itself.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo, its file under `saved_name`.
    /// - `new`: the new name without its extension.
    /// - Returns: nothing; `error.PathAlreadyExists` for another file of
    ///   that name; propagates a failed allocation or rename.
    fn renameFile(self: *Self, memo: *const Memo, new: []const u8) !void {
        const io = self.io.?;
        const folder = std.Io.Dir.cwd();
        const old_path = try self.pathOf(memo.saved_name, &memo.extension);
        defer self.allocator.free(old_path);
        const new_path = try self.pathOf(new, &memo.extension);
        defer self.allocator.free(new_path);
        if (!std.ascii.eqlIgnoreCase(memo.saved_name, new)) return folder.renamePreserve(old_path, folder, new_path, io);
        const temporary = try self.allocator.print("{s}.renaming", .{old_path});
        defer self.allocator.free(temporary);
        try folder.renamePreserve(old_path, folder, temporary, io);
        folder.renamePreserve(temporary, folder, new_path, io) catch |err| {
            folder.renamePreserve(temporary, folder, old_path, io) catch |undo| log.warn("memo file left at {s}: {s}", .{ temporary, @errorName(undo) });
            return err;
        };
    }

    /// Deletes a memo's file from the folder; one already gone counts as deleted.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo, its file under `saved_name`.
    /// - Returns: nothing; propagates a failed allocation or delete.
    fn deleteFile(self: *Self, memo: *const Memo) !void {
        const path = try self.pathOf(memo.saved_name, &memo.extension);
        defer self.allocator.free(path);
        std.Io.Dir.cwd().deleteFile(self.io.?, path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    /// Lists one memo file from the folder by its header alone: its sound is
    /// read when it is played (`decoded`).
    ///
    /// - `self`: the card.
    /// - `dir`: the folder, open.
    /// - `file_name`: the file's name, with `.wav`.
    /// - Returns: nothing; `error.FileTooBig` past `max_file_bytes`;
    ///   propagates a failed open, read, inspection or allocation.
    fn loadFile(self: *Self, dir: std.Io.Dir, file_name: []const u8) !void {
        const io = self.io.?;
        var file = try dir.openFile(io, file_name, .{});
        defer file.close(io);
        const file_length = std.math.cast(usize, try file.length(io)) orelse return error.FileTooBig;
        if (file_length > max_file_bytes) return error.FileTooBig;
        var header: [ziggui.AudioClip.header_read_length]u8 = undefined;
        const header_length = try file.readPositionalAll(io, &header, 0);
        const info = try ziggui.AudioClip.inspectWav(header[0..header_length], file_length);
        const stem = file_name.len - extension.len;
        const memo = try self.add(file_name[0..stem], null, info.duration());
        memo.on_disk = true;
        @memcpy(&memo.extension, file_name[stem..]);
    }

    /// A memo's sound, read from its file and decoded if it is not held.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo.
    /// - Returns: the clip, which the memo holds until `releaseExcept` lets
    ///   it go; propagates a failed read, decode or allocation.
    fn decoded(self: *Self, memo: *Memo) !*const ziggui.AudioClip {
        if (memo.clip) |*clip| return clip;
        const path = try self.pathOf(memo.saved_name, &memo.extension);
        defer self.allocator.free(path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(self.io.?, path, self.allocator, .limited(max_file_bytes));
        defer self.allocator.free(bytes);
        memo.clip = try ziggui.AudioClip.decodeWav(self.allocator, bytes);
        memo.duration = memo.clip.?.duration();
        return &memo.clip.?;
    }

    /// Lets go of every memo's sound but one's, among those that can read
    /// theirs again from the folder, so the card holds one memo's samples.
    /// The player must not hold any of them.
    ///
    /// - `self`: the card.
    /// - `kept`: the memo whose sound stays.
    fn releaseExcept(self: *Self, kept: *const Memo) void {
        for (self.memos.items) |memo| {
            if (memo == kept or !memo.on_disk) continue;
            if (memo.clip) |*clip| clip.deinit(self.allocator);
            memo.clip = null;
        }
    }

    /// Whether the player holds a memo's sound, playing or paused.
    ///
    /// - `self`: the card.
    /// - `memo`: the memo.
    /// - Returns: true while it does.
    fn holds(self: *const Self, memo: *const Memo) bool {
        if (memo.clip) |*clip| return self.player.holds(clip);
        return false;
    }

    /// A memo's file's path.
    ///
    /// - `self`: the card.
    /// - `name`: its name without its extension.
    /// - `suffix`: the extension, its dot included.
    /// - Returns: the path, owned by the caller; propagates allocation failure.
    fn pathOf(self: *const Self, name: []const u8, suffix: []const u8) std.mem.Allocator.Error![]u8 {
        const file = try self.allocator.print("{s}{s}", .{ name, suffix });
        defer self.allocator.free(file);
        return std.fs.path.join(self.allocator, &.{ self.folder.?, file });
    }

    /// A name made safe for a file: the characters no file system takes in
    /// a name (path separators, `:*?"<>|`, control characters) become `-`,
    /// and a leading dot is dropped, so a memo never hides.
    ///
    /// - `self`: the card.
    /// - `name`: the typed name.
    /// - Returns: the name, owned by the caller (empty for none); propagates allocation failure.
    fn fileName(self: *const Self, name: []const u8) std.mem.Allocator.Error![]u8 {
        const kept = std.mem.trimStart(u8, name, ".");
        // Cut on a character, so the name stays valid UTF-8.
        const result = try self.allocator.dupe(u8, kept[0..ziggui.DisplayText.fitLength(kept, 120)]);
        for (result) |*byte| {
            if (byte.* < 0x20 or std.mem.findScalar(u8, "/\\:*?\"<>|", byte.*) != null) byte.* = '-';
        }
        return result;
    }

    /// Whether a folder entry is a memo file (`.wav`, case aside, with a name before it).
    ///
    /// - `file`: the entry's name.
    /// - Returns: true for one.
    fn isMemoFile(file: []const u8) bool {
        return file.len > extension.len and file[0] != '.' and std.ascii.endsWithIgnoreCase(file, extension);
    }

    /// Orders memos by name, case aside, for the list read from the folder.
    ///
    /// - `context`: unused.
    /// - `left`: one memo.
    /// - `right`: another.
    /// - Returns: true when `left` comes first.
    fn namedBefore(context: void, left: *Memo, right: *Memo) bool {
        _ = context;
        return std.ascii.lessThanIgnoreCase(left.saved_name, right.saved_name);
    }

    /// Seconds as a clock, `m:ss`.
    ///
    /// - `seconds`: the time.
    /// - Returns: the text, in the build arena.
    fn clock(seconds: f64) []const u8 {
        // Clamped: a value past what fits must not trap the cast.
        const longest: f64 = std.math.maxInt(u32);
        const whole: u64 = if (std.math.isFinite(seconds)) @intFromFloat(std.math.clamp(seconds, 0, longest)) else 0;
        return ziggui.BuildScope.shared().allocator().print("{d}:{d:0>2}", .{ whole / 60, whole % 60 }) catch @panic("oom");
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "voice memos: a take becomes a memo, plays, renames and is deleted, in memory" {
    ziggui.TestAudioDevices.install();
    defer ziggui.TestAudioDevices.uninstall();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();
    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();

    memos.toggleRecording();
    try std.testing.expectEqual(ziggui.AudioRecorderStatus.recording, memos.recorder.status);
    ziggui.TestAudioDevices.capture(&.{ 1, 2, 3, 4 });
    memos.update();
    _ = memos.card(ziggui.MacosTheme.light);
    memos.toggleRecording();
    try std.testing.expectEqual(@as(usize, 1), memos.memos.items.len);
    try std.testing.expectEqualStrings("Memo 1", memos.memos.items[0].name.text());
    try std.testing.expectEqual(@as(?usize, 0), memos.selection);

    memos.playTapped(0);
    try std.testing.expect(memos.holds(memos.memos.items[0]) and memos.player.playing);
    memos.playTapped(0);
    try std.testing.expect(!memos.player.playing);

    // A second take is "Memo 2"; renaming the first to it is refused, to a free name kept.
    memos.toggleRecording();
    ziggui.TestAudioDevices.capture(&.{5});
    memos.toggleRecording();
    try std.testing.expectEqualStrings("Memo 2", memos.memos.items[1].saved_name);
    try memos.memos.items[0].name.setText("Memo 2");
    memos.renamed(0);
    try std.testing.expectEqualStrings("Memo 1", memos.memos.items[0].name.text());
    try memos.memos.items[0].name.setText(" ../Lecture: part 1 ");
    memos.renamed(0);
    try std.testing.expectEqualStrings("-Lecture- part 1", memos.memos.items[0].saved_name);

    memos.remove(0);
    try std.testing.expectEqual(@as(usize, 1), memos.memos.items.len);
    try std.testing.expect(!memos.holds(memos.memos.items[0]));
    try std.testing.expectEqual(@as(?usize, 0), memos.selection);
}

test "voice memos: memos are written to, renamed and deleted in the folder, and read back" {
    ziggui.TestAudioDevices.install();
    defer ziggui.TestAudioDevices.uninstall();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const settings = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(settings);

    {
        var memos = VoiceMemos.init(std.testing.allocator);
        defer memos.deinit();
        memos.keep(io, settings);
        memos.load();
        memos.toggleRecording();
        ziggui.TestAudioDevices.capture(&.{ 10, -10 });
        memos.toggleRecording();
        memos.toggleRecording();
        ziggui.TestAudioDevices.capture(&.{7});
        memos.toggleRecording();
        try memos.memos.items[0].name.setText("Groceries");
        memos.renamed(0);
        memos.remove(1);
        try std.testing.expectEqualStrings("", memos.notice);
    }

    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();
    memos.keep(io, settings);
    memos.load();
    try std.testing.expectEqual(@as(usize, 1), memos.memos.items.len);
    try std.testing.expectEqualStrings("Groceries", memos.memos.items[0].name.text());
    // Listed by its header: no samples until it is played.
    try std.testing.expect(memos.memos.items[0].clip == null);
    try std.testing.expectApproxEqAbs(2.0 / @as(f64, ziggui.AudioClip.default_sample_rate), memos.memos.items[0].duration, 1e-12);
    memos.playTapped(0);
    try std.testing.expectEqualSlices(i16, &.{ 10, -10 }, memos.memos.items[0].clip.?.samples);
}

test "voice memos: the card holds one played memo's samples, however many it lists" {
    ziggui.TestAudioDevices.install();
    defer ziggui.TestAudioDevices.uninstall();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "memos");
    for ([_][]const u8{ "memos/A.wav", "memos/B.wav" }) |path| {
        var samples = [_]i16{ 1, 2, 3 };
        const clip = ziggui.AudioClip{ .samples = &samples };
        const bytes = try clip.encodeWav(std.testing.allocator);
        defer std.testing.allocator.free(bytes);
        try temporary.dir.writeFile(io, .{ .sub_path = path, .data = bytes });
    }
    const settings = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(settings);
    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();
    memos.keep(io, settings);
    memos.load();
    try std.testing.expectEqual(@as(usize, 2), memos.memos.items.len);
    memos.playTapped(0);
    try std.testing.expect(memos.memos.items[0].clip != null and memos.memos.items[1].clip == null);
    memos.playTapped(1);
    try std.testing.expect(memos.memos.items[0].clip == null and memos.memos.items[1].clip != null);
    try std.testing.expect(memos.holds(memos.memos.items[1]));
    // Played again, the first is read back from its file.
    memos.playTapped(0);
    try std.testing.expectEqualSlices(i16, &.{ 1, 2, 3 }, memos.memos.items[0].clip.?.samples);
    try std.testing.expect(memos.memos.items[1].clip == null);
}

test "voice memos: a file the card did not read is never replaced, and a .WAV file keeps its name" {
    ziggui.TestAudioDevices.install();
    defer ziggui.TestAudioDevices.uninstall();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "memos");
    // A file the card cannot read takes "Memo 1"; another memo is in capitals.
    try temporary.dir.writeFile(io, .{ .sub_path = "memos/Memo 1.wav", .data = "not a wave" });
    var samples = [_]i16{ 3, 4 };
    const loud = ziggui.AudioClip{ .samples = &samples };
    const bytes = try loud.encodeWav(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try temporary.dir.writeFile(io, .{ .sub_path = "memos/Loud.WAV", .data = bytes });
    const settings = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(settings);

    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();
    memos.keep(io, settings);
    memos.load();
    try std.testing.expectEqual(@as(usize, 1), memos.memos.items.len);

    // The new take skips the unread file's name rather than replacing it.
    memos.toggleRecording();
    ziggui.TestAudioDevices.capture(&.{5});
    memos.toggleRecording();
    try std.testing.expectEqualStrings("Memo 2", memos.memos.items[1].saved_name);
    const kept = try temporary.dir.readFileAlloc(io, "memos/Memo 1.wav", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings("not a wave", kept);

    // Renaming onto the unread file's name is refused, and the file stays.
    try memos.memos.items[1].name.setText("Memo 1");
    memos.renamed(1);
    try std.testing.expectEqualStrings("Memo 2", memos.memos.items[1].saved_name);
    try std.testing.expectEqualStrings("A file in the memos folder has that name.", memos.notice);

    // The capitalised file is renamed (by case alone, too) and deleted under its own extension.
    try memos.memos.items[0].name.setText("loud");
    memos.renamed(0);
    try std.testing.expectEqualStrings("loud", memos.memos.items[0].saved_name);
    try temporary.dir.access(io, "memos/loud.WAV", .{});
    memos.remove(0);
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(io, "memos/loud.WAV", .{}));
}

test "voice memos: a recording on another section keeps to its limit, and its status says why it paused" {
    ziggui.TestAudioDevices.install();
    defer ziggui.TestAudioDevices.uninstall();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ziggui.BuildScope.shared().begin(arena.allocator());
    defer ziggui.BuildScope.shared().end();
    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();
    memos.recorder.sample_rate = 2;
    memos.recorder.limit_seconds = 1;
    memos.toggleRecording();
    // No card drawn: the gallery's frame still updates it.
    ziggui.TestAudioDevices.capture(&.{ 1, 2, 3 });
    memos.update();
    try std.testing.expect(memos.recorder.reached_limit);
    try std.testing.expectEqualStrings("The take reached its ten-minute limit: Stop keeps it.", memos.status());
    memos.toggleRecording();
    try std.testing.expectEqual(@as(usize, 1), memos.memos.items.len);
    try std.testing.expect(!std.mem.startsWith(u8, memos.status(), "The take reached"));
}

test "voice memos: a file name drops what no file system takes" {
    var memos = VoiceMemos.init(std.testing.allocator);
    defer memos.deinit();
    const name = try memos.fileName("..a/b\\c:d*e?\"<>|\x01");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("a-b-c-d-e------", name);
    // Cut at 120 bytes on a character, never inside one.
    var typed: [1 + 70 * 2]u8 = undefined;
    typed[0] = 'a';
    for (0..70) |index| @memcpy(typed[1 + index * 2 ..][0..2], "é");
    const long = try memos.fileName(&typed);
    defer std.testing.allocator.free(long);
    try std.testing.expectEqual(@as(usize, 119), long.len);
    try std.testing.expect(std.unicode.utf8ValidateSlice(long));
    try std.testing.expect(VoiceMemos.isMemoFile("Memo 1.WAV"));
    try std.testing.expect(!VoiceMemos.isMemoFile(".wav"));
    try std.testing.expect(!VoiceMemos.isMemoFile(".hidden.wav"));
    try std.testing.expect(!VoiceMemos.isMemoFile("notes.txt"));
}
