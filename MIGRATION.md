# Text editing changes (the release after 3.6.0)

Most code builds as it is. What changes:

- `ziggui.Font` is now the font a view draws in, SwiftUI's `Font`; the font file loader it named before is `ziggui.FontFile` (`FontFile.default()`, `.fromBytes`, …). `.font()` takes a `ziggui.Font`, not a `FontToken`. `.font(.body)` and every other literal read as before; a token held in a variable needs `.font(.of(token))`. `.font(.custom("Noto Serif", 15))` names a family registered with `ziggui.FontRegistry.shared().register`.
- `TextFieldState.revision` names the text's content: each edit still gives it a new value, but undo and redo give back an older one. Compare it for equality (`!=` a saved value), never order it.
- In a `TextEditor`, Tab inserts spaces up to the next stop (it inserted four spaces) or a tab (`indentation.style = .tabs`), ⇧Tab outdents, and Backspace in leading spaces goes back to the previous stop. A one-line field's Tab still moves the focus.
- ⌘Z and ⇧⌘Z (Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y off macOS) undo and redo in the focused field, after the app's key handler declines them. Every field records its edits (at most 1,000 steps, zeroed as they are freed; none for a secure field).
- Pasting into a `TextEditor` turns `\r\n` and a lone `\r` into `\n`; a one-line field takes the bytes as they are.
- The text field context menu adds Undo and Redo rows.

# SwiftUI names (the release after 3.6.0)

These modifiers and views take SwiftUI's names. Each is a rename: the old name is gone, and the new one draws the same (but for `.font(token)` followed by `.size(n)` on one view, noted below).

| Before | After | Notes |
|---|---|---|
| `.foreground(color)` | `.foregroundStyle(color)` | |
| `.weight(w)` | `.fontWeight(w)` | |
| `.mono()` | `.monospaced()` | |
| `.size(n)` | `.font(.system(n))` | `Font.system(size)`. Like `.size`, it keeps the weight, italic, monospace and family around it, and sets no semantic size of its own: `.font(.headline).font(.system(20))` is 20 points regular, since the second `.font` replaces the first (write `.font(.system(20)).fontWeight(.semibold)`). |
| `.onTap(callback)` | `.onTapGesture(callback)` | |
| `.selectable()` | `.textSelection(.enabled)` | `ziggui.TextSelectability`: `.enabled`, `.disabled`. |
| `TextField(placeholder, &state).secure()` | `SecureField(placeholder, &state)` | The `.secure()` modifier is gone. |
| `ziggui.Font` (the font file loader) | `ziggui.FontFile` | `ziggui.Font` is now the view font `.font()` takes. |
| `.chromeless(p)` on a `TextField` | `.textFieldStyle(.plain)` | `ziggui.TextFieldStyle`: `.automatic`, `.plain`. Inherited: set on a container, every field in it is plain. A field ignored `p`. |
| `.chromeless(p)` on a `TextEditor` | `.textEditorStyle(.plain).contentMargins(p)` | `ziggui.TextEditorStyle`, inherited the same way. `.contentMargins(p)` sets the editor's inner margin (8pt without it) with or without chrome. |

Most call sites change with a text replacement, in this order:

```sh
sed -E -i '' \
  -e 's/\.foreground\(/.foregroundStyle(/g' \
  -e 's/\.weight\(/.fontWeight(/g' \
  -e 's/\.mono\(\)/.monospaced()/g' \
  -e 's/\.onTap\(/.onTapGesture(/g' \
  -e 's/\.selectable\(\)/.textSelection(.enabled)/g' \
  -e 's/TextField\(([^()]*)\)\.secure\(\)/SecureField(\1)/g' \
  app/*.zig
```

Check each match before running it: a method of your own named `weight`, `onTap` or `selectable` (a `MenuBarMenu` item's `selectable()` is one) must keep its name. Change `.size(n)` by hand, since `Rect.size()` and other `size` methods share the name.

The ones still to come are listed in CLAUDE.md (`ContextMenu` → `.contextMenu`, `RichTextSpaced`/`RichTextPreformatted` → `.lineSpacing`/`.preformatted`, `ScrollViewOffset` → `.scrollPosition`, `.onDrag` → `.gesture(DragGesture(…))`, the frame modifiers → `.frame(.{ … })`, `.truncated()` → `.lineLimit(1)`).

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
