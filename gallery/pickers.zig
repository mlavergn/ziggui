//! The Pickers panel: `Picker` in a `Form`, where SwiftUI's `.automatic`
//! style is a pop-up menu (laid out after Mail's Composing settings), and
//! the same choices outside one, segmented and as `.pickerStyle(.menu)`.
//! Each theme family draws and opens the menu as its platform does.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_pickers);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The message formats.
const format_options = [_][]const u8{ "Plain Text", "Rich Text" };
/// When spelling is checked.
const spelling_options = [_][]const u8{ "As I Type", "When I Click Send", "Never" };
/// Who a copy goes to.
const copy_options = [_][]const u8{ "Cc:", "Bcc:" };
/// How long a sent message can be taken back.
const delay_options = [_][]const u8{ "Off", "10 Seconds", "20 Seconds", "30 Seconds" };
/// The dictionaries to check spelling against; none is chosen at first.
const dictionary_options = [_][]const u8{ "English (US)", "English (UK)", "Français", "Deutsch" };

/// The Pickers panel's choices.
pub const Pickers = struct {
    const Self = @This();

    /// The message format (Rich Text).
    format: ziggui.State(i64),
    /// When spelling is checked (As I Type).
    spelling: ziggui.State(i64),
    /// The dictionary spelling is checked against; -1 until one is chosen.
    dictionary: ziggui.State(i64),
    /// Whether a copy goes to myself.
    copy_myself: ziggui.State(bool),
    /// Who the copy goes to (Cc:).
    copy_kind: ziggui.State(i64),
    /// The undo send delay (10 Seconds).
    delay: ziggui.State(i64),
    /// The color picker's color (the blue accent).
    color: ziggui.State(ziggui.Color),

    /// Makes the panel's choices.
    ///
    /// - `allocator`: owns the choices; must outlive the panel.
    /// - Returns: the panel.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{
            .format = ziggui.State(i64).init(allocator, 1),
            .spelling = ziggui.State(i64).init(allocator, 0),
            .dictionary = ziggui.State(i64).init(allocator, -1),
            .copy_myself = ziggui.State(bool).init(allocator, false),
            .copy_kind = ziggui.State(i64).init(allocator, 0),
            .delay = ziggui.State(i64).init(allocator, 1),
            .color = ziggui.State(ziggui.Color).init(allocator, ziggui.Accent.blue.color()),
        };
        return self;
    }

    /// Frees the choices.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.color.deinit();
        self.delay.deinit();
        self.copy_kind.deinit();
        self.copy_myself.deinit();
        self.dictionary.deinit();
        self.spelling.deinit();
        self.format.deinit();
    }

    /// Opens the first picker's menu (`--picker-menu`), as a tap on it does.
    ///
    /// - `self`: the panel.
    pub fn openMenu(self: *Self) void {
        ziggui.PickerMenu.shared().open(self.format.binding());
    }

    /// The color picker's card: the picker, and a sample drawn in its color.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn colorCard(self: *Self, theme: ziggui.Theme) ziggui.View {
        const chosen = self.color.get();
        return gallery.Card.view(theme, "ColorPicker: one palette under every theme, the choice marked", "ziggui.ColorPicker", ziggui.VStack(.{
            ziggui.ColorPicker("Highlight", self.color.binding()),
            ziggui.HStack(.{
                ziggui.RoundedRectangle(chosen, 4).frame(48, 20),
                ziggui.Text("Text drawn in the color chosen").foregroundStyle(chosen),
            }).spacing(10),
        }).spacing(12).alignment(.leading).frameMaxWidth().frameAlign(.leading));
    }

    /// The Pickers panel.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the panel's view.
    pub fn panel(self: *Self, theme: ziggui.Theme) ziggui.View {
        return ziggui.VStack(.{
            gallery.Card.view(theme, "Picker in a Form: a pop-up menu, as the platform draws it", "ziggui.Picker · ziggui.Form · .pickerStyle(.automatic)", ziggui.Form(.{
                ziggui.Section(.{
                    ziggui.LabeledContent("Message format:", ziggui.Picker(self.format.binding(), &format_options)),
                    ziggui.LabeledContent("Check spelling:", ziggui.Picker(self.spelling.binding(), &spelling_options)),
                    ziggui.LabeledContent("", ziggui.HStack(.{
                        ziggui.Toggle("Automatically", self.copy_myself.binding()),
                        ziggui.Picker(self.copy_kind.binding(), &copy_options),
                        ziggui.Text("myself"),
                    }).spacing(8)),
                }),
                ziggui.Section(.{
                    ziggui.LabeledContent("Undo send delay:", ziggui.Picker(self.delay.binding(), &delay_options)),
                }),
            })),
            gallery.Card.view(theme, "Outside a Form: segmented, a menu asked for, and a menu's prompt while nothing is chosen", "ziggui.Picker · .pickerStyle(.segmented) · .pickerStyle(.menu) · .prompt", ziggui.VStack(.{
                ziggui.HStack(.{ ziggui.Picker(self.spelling.binding(), &spelling_options), ziggui.Spacer() }),
                ziggui.HStack(.{ ziggui.Picker(self.spelling.binding(), &spelling_options).pickerStyle(.menu), ziggui.Spacer() }),
                ziggui.HStack(.{ ziggui.Picker(self.dictionary.binding(), &dictionary_options).pickerStyle(.menu).prompt("Choose a dictionary"), ziggui.Spacer() }),
            }).spacing(12).alignment(.leading)),
            ziggui.Text("Each theme opens the menu as its platform does; switch themes in the sidebar.")
                .foregroundStyle(theme.colors.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            ziggui.Text("Over the picker, choice checked: macOS, KDE. Below it, choice highlighted: Windows, Material.")
                .foregroundStyle(theme.colors.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            ziggui.Text("While the menu is open: ↑ ↓ move, Return chooses, Esc closes.")
                .foregroundStyle(theme.colors.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
        }).spacing(16);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}
