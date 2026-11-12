//! The containers: stacks, spacers, dividers, scroll views, the geometry
//! reader, lists, grids, tabs, navigation, menus, sidebars, radio groups and
//! tables. View constructors over the view engine in `core/`, and the types
//! they take.

const std = @import("std");
const log = std.log.scoped(.ziggui_containers_module);

/// Children stacked vertically.
pub const VStack = @import("stacks.zig").VStack;
/// Children side by side.
pub const HStack = @import("stacks.zig").HStack;
/// Children layered front to back.
pub const ZStack = @import("stacks.zig").ZStack;
/// A slice mapped to views, spliced into the enclosing stack.
pub const ForEach = @import("stacks.zig").ForEach;
/// Flexible space in a stack.
pub const Spacer = @import("spacer.zig").Spacer;
/// Flexible space with a least length.
pub const MinSpacer = @import("spacer.zig").MinSpacer;
/// A hairline across a stack.
pub const Divider = @import("divider.zig").Divider;
/// A vertical hairline.
pub const VDivider = @import("divider.zig").VDivider;
/// A view that draws nothing.
pub const Empty = @import("empty.zig").Empty;
/// A vertical scroll view at the top.
pub const ScrollView = @import("scroll_view.zig").ScrollView;
/// A scroll view at a fixed offset.
pub const ScrollViewOffset = @import("scroll_view.zig").ScrollViewOffset;
/// A scrolling viewport whose offset lives in a `ScrollState`.
pub const ScrollViewState = @import("scroll_view.zig").ScrollViewState;
/// A viewport that scrolls both ways, its offsets in a `ScrollState`.
pub const ScrollViewStateBoth = @import("scroll_view.zig").ScrollViewStateBoth;
/// Content built from the size it is laid out at.
pub const GeometryReader = @import("geometry_reader.zig").GeometryReader;
/// A scrolling list of divider-separated rows.
pub const List = @import("list.zig").List;
/// A grid that fills rows of a fixed column count.
pub const LazyVGrid = @import("grid.zig").LazyVGrid;
/// A grid that fills columns of a fixed row count.
pub const LazyHGrid = @import("grid.zig").LazyHGrid;
/// One tab of a `TabView`.
pub const Tab = @import("tab.zig").Tab;
/// Tabs over one shown page.
pub const TabView = @import("tab_view.zig").TabView;
/// A navigation stack of routes.
pub const NavigationPath = @import("navigation_path.zig").NavigationPath;
/// A sidebar | detail split with a fixed sidebar.
pub const NavigationSplitView = @import("navigation.zig").NavigationSplitView;
/// A `NavigationSplitView` whose sidebar is an inset panel.
pub const NavigationSplitViewInset = @import("navigation.zig").NavigationSplitViewInset;
/// A button that pushes a route.
pub const NavigationLink = @import("navigation.zig").NavigationLink;
/// A button that pops a route.
pub const NavigationBackButton = @import("navigation.zig").NavigationBackButton;
/// A button that opens a popover of items.
pub const Menu = @import("menu.zig").Menu;
/// A trigger view that opens a popover of items.
pub const ContextMenu = @import("menu.zig").ContextMenu;
/// One row of a `Sidebar`.
pub const SidebarItem = @import("sidebar_item.zig").SidebarItem;
/// How a `Sidebar` highlights its selection.
pub const SidebarStyle = @import("sidebar_style.zig").SidebarStyle;
/// A sidebar list driven by a selection binding.
pub const Sidebar = @import("sidebar.zig").Sidebar;
/// A `Sidebar` with an explicit selection style.
pub const SidebarStyled = @import("sidebar.zig").SidebarStyled;
/// A vertical group of radio buttons.
pub const RadioGroup = @import("radio_group.zig").RadioGroup;
/// One column of a `Table`.
pub const TableColumn = @import("table_column.zig").TableColumn;
/// A multi-column table of text rows.
pub const Table = @import("table.zig").Table;
/// The order a column is sorted in (`.forward`, `.reverse`), as SwiftUI's `SortOrder`.
pub const SortOrder = @import("sort_order.zig").SortOrder;
/// A `DataTable`'s sort column and order.
pub const SortColumn = @import("sort_column.zig").SortColumn;
/// One column of a data table (and of `TableHeader`/`TableRow`).
pub const DataColumn = @import("data_column.zig").DataColumn;
/// A table of view rows with sortable headers.
pub const DataTable = @import("data_table.zig").DataTable;

/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// The build arena (from the views module).
pub const BuildScope = @import("../module.zig").BuildScope;
/// Builds stack views (from the views module).
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A scroll view's app-owned offsets (from the views module).
pub const ScrollState = @import("../module.zig").ScrollState;
/// A read/write handle on a `State` (from the views module).
pub const Binding = @import("../module.zig").Binding;
/// A type-erased tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// The icon font's glyph names (from the views module).
pub const IconName = @import("../module.zig").IconName;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// An icon from the icon font (from the views module).
pub const Icon = @import("../module.zig").Icon;
/// A filled circle (from the views module).
pub const Circle = @import("../module.zig").Circle;
/// A push button (from the views module).
pub const Button = @import("../module.zig").Button;
/// A push button with a role (from the views module).
pub const ButtonRoled = @import("../module.zig").ButtonRoled;
/// A segmented picker over a selection binding (from the views module).
pub const Picker = @import("../module.zig").Picker;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("stacks.zig");
    _ = @import("spacer.zig");
    _ = @import("divider.zig");
    _ = @import("empty.zig");
    _ = @import("scroll_view.zig");
    _ = @import("geometry_reader.zig");
    _ = @import("list.zig");
    _ = @import("grid.zig");
    _ = @import("tab.zig");
    _ = @import("tab_view.zig");
    _ = @import("navigation_path.zig");
    _ = @import("navigation.zig");
    _ = @import("menu.zig");
    _ = @import("sidebar_item.zig");
    _ = @import("sidebar_style.zig");
    _ = @import("sidebar.zig");
    _ = @import("radio_group.zig");
    _ = @import("table_column.zig");
    _ = @import("table.zig");
    _ = @import("sort_order.zig");
    _ = @import("sort_column.zig");
    _ = @import("data_column.zig");
    _ = @import("data_table.zig");
}
