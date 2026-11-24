# fixtures

Fixed files the gallery and checks refer to, so what they show is the same on every machine and every run.

- `file_browser/`: the folder the gallery's File Browser section opens (`gallery.fixtures_path`, set by `build.zig`). It has folders and files of known sizes, a hidden file (`.settings`), and a folder holding only a hidden file (`Photos/`), which shows as empty while hidden names are hidden.
- `fonts/`: Noto Serif, regular and bold (the unhinted `glyf` TrueType builds from notofonts), which the gallery registers at launch (`gallery.fonts_path`) as a third family for the Text Editor's font menus. Licensed under the SIL Open Font License 1.1 (`fonts/OFL.txt`).

Sizes are part of what the screenshots show, so `.gitattributes` keeps line endings as committed. Change a file here and the File Browser screenshot changes with it.
