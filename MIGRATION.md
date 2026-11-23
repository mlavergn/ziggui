# Migrating to the one `Table` (ziggui 3.3.0)

`Table`, `TableResizable`, `DataTable`, `LazyTable`, `TableHeader` and `TableRow` are now one `Table`:

```zig
ziggui.Table(T, context, columns, count, cellFn, idFn, state, options)
```

- `cellFn(context, row, column)` makes a cell; `idFn(context, row)` gives a row's ID, or `null` (one row selects, by position).
- `state: ?*ziggui.TableState`: app-owned at a stable address, or `null` for a table that keeps nothing (fitted, selecting, sorting and resizing nothing).
- `options: ziggui.TableOptions(T)`: `layout` (`.scrolling`, `.fitted`), `column_headers` (`.automatic`, `.visible`, `.hidden`), `row_height`, `header_height`, `selection_mode`, `multiple_selection`, `on_activate`, `on_sort`, `on_selection`, `highlighted`, `header_accessory`, `empty`, `resizable`.
- Rows of text: `ziggui.TableRows.table(rows, columns, state, options)`, or `ziggui.TableRows.of(rows)` as the context and `ziggui.TableRows.cell` as `cellFn`.
- The context must last the frame: `TableRows.of` puts it in the build arena; an app's own context is usually its state.

## `LazyTable`

Renamed; nothing else changes.

| Before | After |
|---|---|
| `LazyTable` | `Table` |
| `LazyTableState` | `TableState` |
| `LazyTableColumn` | `TableColumn` |
| `LazyTableOptions` | `TableOptions` |
| `LazyTableSelectionMode` | `TableSelectionMode` |
| `LazyTableCell` | `TableCell` |
| `LazyTableIdSource` | `TableIdSource` |
| `LazyTableSpan` | `TableSpan` |
| `LazyTableState.cell_spacing` | `TableState.side_inset` (columns abut now) |

## `Table` (text rows)

```zig
// Before
ziggui.Table(&columns, rows, selection_binding)            // columns: []const ziggui.TableColumn

// After: a table that selects
ziggui.TableRows.table(rows, &columns, &self.table_state, .{})
// After: a static table (no selection)
ziggui.TableRows.table(rows, &columns, null, .{})
```

- `TableColumn` keeps `title`, `width`, `min_width`.
- The selected row: `TableState.cursor.?.row` (no ID source) instead of a `Binding(i64)`; `on_selection` reports changes.
- A short table inside a larger pane: `.layout = .fitted` (every row built, height fitted to them).

## `TableResizable`

```zig
// Before
ziggui.TableResizable(&columns, rows, selection_binding, &self.customization)

// After
ziggui.TableRows.table(rows, &columns, &self.table_state, .{})
```

- `TableColumnCustomization` is gone; `TableState` keeps the dragged widths (`columnWidth`, `resetWidths`).
- A drag now widens only its column; the table grows and scrolls sideways (Finder's), instead of trading width with the next column. A fitted table does not resize.

## `DataTable`

```zig
// Before
ziggui.DataTable(&data_columns, view_rows, sort_binding, &self.scroll)

// After
ziggui.Table(App, self, &columns, count, App.cell, App.id, &self.table_state, .{ .on_sort = ziggui.Callback.init(App, self, App.sorted) })
```

- `DataColumn` → `TableColumn`: same `title`, `width`, `sortable`, `trailing`.
- Rows: a `cellFn` instead of a slice of view rows.
- Sort: `TableState.sort` (a `SortColumn`) instead of a `Binding(SortColumn)`; re-sort in `on_sort`.
- Scroll: `TableState.scroll` instead of the `ScrollState` argument.

## `TableHeader` + `TableRow`

```zig
// Before: a header over rows the app stacked or put in a `VirtualList`
sections.append(ziggui.TableHeader(&columns));
for (items, 0..) |item, index| rows[index] = ziggui.TableRow(&columns, cells, index, selected);

// After
ziggui.Table(App, self, &columns, items.len, App.cell, null, null, .{ .layout = .fitted })
```

- `DataColumn` → `TableColumn`.
- Several static tables in one pane (a schema's columns and its indexes): one fitted `Table` each, given no state.
- A long, selectable list of rows: `.layout = .scrolling` with a `TableState` (rows built only while in view, as `VirtualList` built them).
- Selection: `TableState` (`select`, `isRowSelected`) instead of each row's `selected` flag.

## Look

Every table draws as the old `Table` did: rows a body line and 5 points above and below, the header a subheadline line and the same, columns abutting with 8 points at each end, header titles in the label color, a selected row filled in the selection color with its text on the accent. A press anywhere on a row lands on it, and the cell cursor fills its cell.

## Removed with no replacement

`SortHeader`: the header cell is the `Table`'s own.
