# Branding

Two marks for Return of the Mac, drawn on 2026-11-14. The owner chose to keep both and to ship **Comeback** first, because its glyph reads better in the menu bar.

| Directory | Mark | Use |
| --- | --- | --- |
| `comeback/` | A chunky computer inside a return loop | The app icon and menu bar glyph of the first release |
| `prompt/` | `rotm` and a cursor | Kept as the alternative, and for places a wordmark fits better (README, docs, the console window) |

Each directory holds `icon.svg` (the master, 1024 units, the macOS icon shape inset 100 units), `AppIcon.icns` (rendered from it) and `menubar.svg` (an 18 unit template glyph, black on transparent). `comeback/menubar-attention.svg` is the same glyph with a dot for the "needs attention" state.

The letters in `prompt/icon.svg` are drawn as strokes, not set in a font, so the file renders the same everywhere.

## Where the build uses them

`app/scripts/build-app.sh` copies `comeback/AppIcon.icns` (named by `Info.plist.in`), `menubar.svg` and `menubar-attention.svg` into `Contents/Resources`. `StatusItemController` loads the glyph as a template `NSImage`, and draws the SF Symbol `desktopcomputer` (or its badged variant) when the bundle has none, as under `swift run`. Not yet checked in the guest: the glyph at both menu bar appearances, and that macOS 14 loads an SVG into `NSImage` (this Mac's macOS 27 does).

## Rendering an icns again

After editing an `icon.svg`, from `app/branding`:

```bash
d=$(mktemp -d)/AppIcon.iconset && mkdir -p "$d" && for s in 16 32 128 256 512; do sips -s format png -z $s $s comeback/icon.svg --out "$d/icon_${s}x${s}.png" && sips -s format png -z $((s * 2)) $((s * 2)) comeback/icon.svg --out "$d/icon_${s}x${s}@2x.png"; done && iconutil -c icns "$d" -o comeback/AppIcon.icns
```
