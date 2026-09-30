# Firefox Developer Edition Setup

> [!NOTE]  
> Optional — not installed by setup; install manually if you use it. This config targets **Firefox Developer Edition** only (it isn't in the Brewfile, and regular Firefox profiles are not touched).

## Configuration and UI styles

`user.js` (preferences), `chrome/userChrome.css` (browser UI) and `chrome/userContent.css` (web content) are applied by [setup/symlinks.sh](../setup/symlinks.sh):

- It finds the Developer Edition profile with [lib/get-firefox-dev-path](lib/get-firefox-dev-path) (a `*dev-edition*` profile folder, or the `dev-edition` entry in `profiles.ini`).
- It **hard-links** the three files into that profile (`user.js` at the profile root, the CSS files in `chrome/`).
- If no Developer Edition profile exists, it skips this step with a warning.

After installing Developer Edition, launch it once so it creates its profile, quit it, then re-run `setup/symlinks.sh`.

## Install theme

- [Squirrelsong Light](https://addons.mozilla.org/en-US/firefox/addon/squirrelsong-light/)

## Install extensions

- [uBlock Origin](https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/) — _Run in Private Windows_
  - Set up your [blocking mode](https://github.com/gorhill/uBlock/wiki/Blocking-mode)
  - Enable `AdGuard URL Tracking Protection`
  - Enable `EasyList – Cookie Notices`
  - Import [Actually Legitimate URL Shortener Tool](https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt)
    - Check `Import…` under `Filter lists`
    - Paste in the linked URL above
    - Click `Apply changes`
- [Privacy Badger](https://addons.mozilla.org/en-US/firefox/addon/privacy-badger17/) — _Run in Private Windows_
  - Firefox [includes tracker blocking](https://blog.mozilla.org/security/2021/02/23/total-cookie-protection/) already; Privacy Badger is optional on top of it.
- [1Password: Password Manager](https://addons.mozilla.org/en-US/firefox/addon/1password-x-password-manager/) — pairs with the 1Password app installed by the Brewfile
- [UnTrap for YouTube](https://addons.mozilla.org/en-US/firefox/addon/untrap-for-youtube/)
  - [Settings](./settings/untrap.txt)
- [Instapaper](https://addons.mozilla.org/en-US/firefox/addon/instapaper-official/)
- [EditThisCookie2](https://addons.mozilla.org/en-US/firefox/addon/etc2/)
- [Refined GitHub](https://addons.mozilla.org/en-US/firefox/addon/refined-github-/)
- [Catppuccin for Web File Explorer Icons](https://addons.mozilla.org/en-US/firefox/addon/catppuccin-web-file-icons/)
- [LanguageTool](https://addons.mozilla.org/en-US/firefox/addon/languagetool/)
- [Blank Sky New Tab Page](https://addons.mozilla.org/en-US/firefox/addon/blank-sky-new-tab-page/) — _Run in Private Windows_
- [Video Speed Controller](https://addons.mozilla.org/en-US/firefox/addon/videospeed/)
- [Obsidian Web Clipper](https://addons.mozilla.org/en-US/firefox/addon/web-clipper-obsidian/)
