# Visual Studio Code

> Stock macOS keyboard shortcuts — this repo ships no custom keybindings.

Settings, snippets and tasks come from `vscode/User` (symlinked by setup); Settings Sync is off. `vscode/User/keybindings.json` is intentionally empty (`[]`), so every shortcut below is a VS Code default.

## Commands this setup relies on

Run from the Command Palette (**Cmd+Shift+P**):

- **SpaceBox Enable UI Enhancer**, then quit (**Cmd+Q**) and reopen: turns on the Command Palette and hover blur. Needed again after every VS Code update ([vscode/README.md](../../vscode/README.md#spacebox-ui-enhancer)).
- **TypeScript: Restart TS Server**: makes the editor pick up a new `tsconfig.json` or newly installed type packages (such as `@ampcode/plugin` for the Amp plugins).

## General

- **Cmd+Shift+P** (or **F1**): Command Palette
- **Cmd+P:** Quick Open / go to file
- **Cmd+,:** settings
- **Cmd+K, Cmd+S:** keyboard shortcuts editor
- **Cmd+Shift+N:** new window

## Navigation and search

- **Ctrl+G:** go to line
- **Cmd+Shift+O:** go to symbol in file
- **Cmd+T:** show all symbols in workspace
- **F12:** go to definition
- **Option+F12:** peek definition
- **Shift+F12:** show references
- **Ctrl+- / Ctrl+Shift+-:** go back / forward
- **F8 / Shift+F8:** next / previous error or warning
- **Cmd+F / Option+Cmd+F:** find / replace in file
- **Cmd+G / Cmd+Shift+G:** find next / previous
- **Cmd+Shift+F / Cmd+Shift+H:** search / replace in files

## UI and panels

- **Cmd+B:** toggle primary side bar
- **Option+Cmd+B:** toggle secondary side bar
- **Cmd+J:** toggle bottom panel
- **Ctrl+Backtick:** show integrated terminal; **Ctrl+Shift+Backtick:** new terminal
- **Cmd+Shift+E / Cmd+Shift+X / Ctrl+Shift+G:** Explorer / Extensions / Source Control
- **Cmd+Shift+M:** Problems panel; **Cmd+Shift+U:** Output panel
- **Cmd+Backslash:** split editor; **Cmd+1 / Cmd+2 / Cmd+3:** focus editor group
- **Cmd+Shift+T:** reopen closed editor
- **Cmd+K, Z:** Zen Mode (Esc, Esc to exit)
- **Cmd+Shift+V:** Markdown preview; **Cmd+K, V:** preview to the side

## Editing

- **Cmd+Shift+K:** delete line
- **Option+↑ / Option+↓:** move line up / down
- **Shift+Option+↑ / Shift+Option+↓:** copy line up / down
- **Cmd+Enter / Cmd+Shift+Enter:** insert line below / above
- **Cmd+/:** toggle line comment; **Shift+Option+A:** toggle block comment
- **Cmd+] / Cmd+[:** indent / outdent line
- **Option+Z:** toggle word wrap
- **Shift+Option+F:** format document; **Cmd+K, Cmd+F:** format selection

## Multi-cursor and selection

- **Cmd+D:** add selection to next match; **Cmd+Shift+L:** select all occurrences
- **Option+Cmd+↑ / Option+Cmd+↓:** add cursor above / below
- **Option+click:** insert cursor; **Cmd+U:** undo last cursor operation
- **Shift+Option+I:** cursor at end of each selected line
- **Cmd+L:** select current line
- **Ctrl+Shift+Cmd+→ / ←:** expand / shrink selection

## Refactoring

- **F2:** rename symbol
- **Cmd+F2:** select all occurrences of current word
- **Cmd+.:** Quick Fix / refactor
- **Ctrl+Space:** trigger suggestion; **Cmd+Shift+Space:** parameter hints
- **Cmd+I:** inline chat in the editor

## Tasks and debugging

- **Cmd+Shift+B:** run build task (other tasks: Command Palette → "Tasks: Run Task")
- **F5 / Shift+F5:** start or continue / stop debugging
- **F9:** toggle breakpoint
- **F10 / F11 / Shift+F11:** step over / into / out

## Sources

- https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf
- https://code.visualstudio.com/docs/configure/keybindings
- https://code.visualstudio.com/docs/getstarted/userinterface
- https://code.visualstudio.com/docs/configure/custom-layout
- https://code.visualstudio.com/docs/debugtest/tasks
- https://code.visualstudio.com/docs/copilot/chat/inline-chat
