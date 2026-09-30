# macOS Tips & Tricks

## Tip #1

Useful browser shortcuts. These are written for Comet, the default browser on this Mac. Comet is Chromium-based, and most of them also work in Safari.

1. Use ⌘1 through ⌘8 to switch to that tab.
1. ⌘9 always goes to the last tab, however many are open.
1. ⌘⇧[ and ⌘⇧] move one tab left or right.
1. ⌘W closes a tab. ⌘⇧W closes the whole window.
1. ⌘L focuses the address bar.
1. ⌘⌥I opens DevTools. With DevTools focused, ⌘⇧D moves it between its last two dock positions. Docking it to the side makes it easy to resize the page and test responsive breakpoints. In Safari, turn on **Settings** → **Advanced** → **Show features for web developers** first to get the Web Inspector.
1. ⌘⇧T reopens the last closed tab.

## Tip #2

To run a terminal command at a lower priority so it doesn't slow down the rest of the Mac, prefix it with `nice -n 5`.

Example:

`nice -n 5 pnpm test`

The value can be `-20` to `19` (default `0`). `19` is the "nicest" (lowest priority). Only root can use negative values.

## Tip #3

Hold `Option` and click the Wi‑Fi icon in the menu bar to see your IP address and other connection details.

## Tip #4

Every so often, check your globally installed packages and uninstall what you don't use. The global CLIs this setup installs (serverless, `@antfu/ni`, CodeGraph, `tsc`) are mise `npm:` tools: list them with `mise ls`, and remove one by deleting its line from `tilde/.config/mise/config.toml`, then `mise uninstall npm:x`. Anything you `npm install -g` by hand belongs to the active Node version.

```sh
pnpm list --global --depth 0
pnpm remove --global x
```

```sh
npm list --global --depth 0
npm uninstall -g x
```

```sh
yarn global list
yarn global remove x
```

```sh
brew list
brew uninstall x
```

If you don't know what something is:

```sh
[pnpm | npm | yarn | brew] info x
```

## Tip #5

Screenshots on this Mac are handled by CleanShot X (Setapp). It takes over ⌘⇧3 (full screen), ⌘⇧4 (area), and ⌘⇧5 (all-in-one), and the matching system shortcuts are turned off in **System Settings** → **Keyboard** → **Keyboard Shortcuts…** → **Screenshots**.

If you turn the system shortcuts back on: while dragging a ⌘⇧4 selection, hold `Space` to move it, `Option` to resize it from the center, or `Shift` to lock one side. `set-defaults` can optionally set the built-in tool to save PNGs named "Shot" to the Desktop, without shadows and with the pointer shown.

## Tip #6

You can choose what Spotlight searches, which speeds it up and removes irrelevant results. Go to **System Settings** → **Spotlight** → **Search results**. Raycast owns ⌘Space on this Mac, but Finder and other apps still search with Spotlight's index.

[Suggested categories](./macos%20settings.md#spotlight).

## Tip #7

Automate Mac setup: [jrmatherly/dotfiles](https://github.com/jrmatherly/dotfiles).

## Tip #8

Review which folders your apps can access in **System Settings** → **Privacy & Security** → **Files & Folders**. Downloads and Desktop matter most, because bank statements and similar files tend to land there. Include your terminals (Ghostty, Warp, iTerm2, cmux, Terminal) in this check.

## Tip #9

[Add symbols to your keyboard shortcuts](https://twitter.com/jonmajorc/status/1491792400951300102).

## Tip #10

Close running apps.

While you're cycling through apps with ⌘Tab, press `Q` to quit the highlighted app or `H` to hide or show it.

## Tip #11

You can drag the icon next to a window's title to move or copy that file or folder somewhere else, but normally the icon only appears when you hover over the title.

Turn on **System Settings** → **Accessibility** → **Display** → **Show window title icons** to keep the icons visible all the time.

## Tip #12

Fine volume and brightness control.

Hold `Shift` and `Option` while you press the volume or brightness keys to change them in quarter steps. This Mac uses the top-row keys as media keys (the default), so you don't need `Fn`.

## Tip #13

⌘-click a Dock icon to open a Finder window showing that app in its folder.

## Tip #14

Hot Corners.

Hot Corners run an action when the pointer reaches a screen corner, like Mission Control, Show Desktop, or Lock Screen. Set them up in **System Settings** → **Desktop & Dock** → **Hot Corners…**. On this Mac all four corners are set to no action, and running `set-defaults` resets them that way ([details](./macos%20settings.md#desktop--dock)). Remove the hot-corner loop in `setup/macos.sh` if you want to keep your own.

## Tip #15

Advanced Hot Corners.

If you want Hot Corners but keep triggering them by accident, hold down a modifier key (for example `Option`) while you choose the corner's action. The corner then only activates while you hold that key.

## Tip #16

Hide a window.

Press ⌘H to hide the current app. Get it back by clicking its Dock icon or with ⌘Tab.

## Tip #17

Switch between desktops (Spaces).

If you use more than one Space, press `Control` and the left or right arrow to switch between them. These **Move left a Space** / **Move right a Space** shortcuts are on for this Mac.

## Tip #18

Rename files and folders.

Force Click a file or folder name to rename it. Force Click the icon to see a Quick Look preview. On this trackpad, Force Click is turned on (**Look up & data detectors** − `Force Click with One Finger`).

## Tip #19

Turn on Do Not Disturb quickly.

Open Control Center in the menu bar and click **Focus** to switch Do Not Disturb or another Focus on or off. If you have Control Center show **Focus** in the menu bar, that icon works too. The old Option-click on Notification Center no longer exists.

## Tip #20

Back up macOS and app settings.

`set-defaults` makes `~/Library` visible, so you can open it straight from Finder with ⌘⇧G and `~/Library`. Copy `~/Library/Preferences` somewhere safe. Sandboxed apps keep their settings in `~/Library/Containers`. Settings this repo tracks are already in git; for Obsidian, [`bin/obsidian-vault capture`](../bin/obsidian-vault) copies settings and templates you changed in the vault back into the repo (it never deletes anything). The notes themselves live in iCloud Drive → Notes.

## Tip #21

Clean up `node_modules`.

1. `cd` to the folder you want to search.
1. List every `node_modules` folder below it, with sizes and a total:

   ```sh
   node-modules-size
   ```

1. Delete every `node_modules` folder below the current directory:

> [!CAUTION] This can't be undone, and it doesn't ask for confirmation!

```sh
node-modules-clean
```

Both commands are in this repo's [`bin/`](../bin) folder (`bin/node-modules-size`, `bin/node-modules-clean`).

## Tip #22

Manage apps with the `Brewfile`.

The Brewfile lives at [`setup/Brewfile`](../setup/Brewfile), and `HOMEBREW_BUNDLE_FILE` points to it. Raw `brew bundle` commands, including `brew bundle cleanup`, fail on its `manual "MonoLisa"` line (`Invalid Brewfile: undefined method 'manual'`), so strip that line first.

- Install everything: `brewpick --all` (it strips the `manual` lines for you), or run `brewpick` to pick entries with fzf.
- Dump what's currently installed: `brew bundle dump --file Brewfile.dump`
- Preview what isn't in the Brewfile (read-only):

  ```sh
  grep -v '^manual ' "$DOTFILES/setup/Brewfile" | brew bundle cleanup --file -
  ```

- After you've reviewed that list, uninstall everything on it:

  ```sh
  grep -v '^manual ' "$DOTFILES/setup/Brewfile" | brew bundle cleanup --force --file -
  ```

> [!CAUTION] `cleanup --force` also removes VS Code extensions and taps that aren't in the Brewfile. Add anything you want to keep to the Brewfile first.
