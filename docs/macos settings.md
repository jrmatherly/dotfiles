# macOS Settings

A manual checklist for **System Settings** on this Mac (MacBook Pro, Apple M3 Pro, built-in display, macOS 27). Labels match the macOS 27 System Settings wording.

- **(set-defaults)**: [`set-defaults`](../bin/set-defaults) already applies this setting by running [`setup/macos.sh`](../setup/macos.sh). You don't need to change it by hand, and running `set-defaults` again resets it to the value shown.
- **(set-defaults, prompt)**: `set-defaults` asks before it applies this one.
- Everything else has to be set by hand.

## System Settings

### Apple Account

- **Name, Phone, Email**: turn off Apple's marketing and news email options

### Wi-Fi

- Click **Details…** for the trusted home network you're connected to
  - **Private Wi-Fi Address** − `Rotating`
  - **Limit IP address tracking** − `On`

### Network

- **Firewall** − `On` (set-defaults, prompt)
- **Firewall** → **Options…** → **Enable stealth mode** − `On` (set-defaults, prompt)

### Notifications

- **Show previews** − `When Unlocked`
- Disable **Allow notifications when the screen is locked**
- Disable **Allow notifications when mirroring or sharing the display**
- Disable **Allow notifications from iPhone**
- Turn on and adjust **Summarize notifications**
- Disable notifications for every app except Calendar, Reminders, Screen Time, Wallet, Music, and messaging apps

### Focus

- 4 Focus modes
  - Do Not Disturb
  - Reduce Interruptions
  - Sleep
  - Work
- **Share across devices** − `On`
- **Focus status** − `On`

### Screen Time

- Set up **App Limits**
  - YouTube
  - Messaging apps
  - Email client
- **Share Across Devices** − `On`

### General

- **Software Update** → **Automatic Updates**: turn on every option (set-defaults, prompt: turns on the automatic check, download, and critical/security installs)
- **AutoFill & Passwords** → verification codes → **Delete After Use** − `On`
- **Sharing** → **Content & Media**: turn off every option
- **Sharing** → **Accessories & Internet**: turn off every option
- **Sharing** → **Advanced**: turn off every option
- **Sharing** → **Local hostname**: change it (set-defaults sets it when you type a computer name at its prompt)
- **Time Machine**: backups are off on this Mac (set-defaults, prompt: "Disable Time Machine backups entirely"). A separate prompt stops Time Machine asking to use new disks for backup.

### Appearance

- **Appearance** − `Dark` (this Mac)
- **Liquid Glass** − `Clear` or `Tinted`. On this Mac the tint amount is set to `0.5` (`NSGlassTintAmount`).
- **Theme** − `Multicolor` (this Mac has no custom accent color set)
- **Text highlight color** − default (not customized on this Mac)
- **Icon & widget style** − default (not customized on this Mac)
- **Sidebar icon size** − `Large` (set-defaults)
- **Tint window background with wallpaper color** − `Off`
- **Show scroll bars** − `When scrolling` (set-defaults)

### Accessibility

- **Motion** → **Prefer non-blinking cursor** − `On`
- **Display** → **Pointer size**: between the 1st and 2nd marks
- **Pointer Control** → **Mouse Options…** → **Scroll speed** − Max (only matters with a mouse connected)

Leave **Display** → **Reduce Transparency** off. On this Mac it's off, and the Appearance pane warns that turning Liquid Glass on or off can switch it.

### Control Center

- **Control Center Modules**: set all to `Don't Show in Menu Bar` except:
  - **Wi‑Fi** − `Show in Menu Bar`
  - **Focus** − `Show When Active`
- **Battery** − `Show in Menu Bar`, **Show Percentage** − `On` (this Mac)
- **Menu Bar Only**: set all to `Don't Show in Menu Bar`
  - **Clock Options…** − **Style** `Digital`, **Show date** `When Space Allows`, **Show the day of the week** `On`, **Show AM/PM** `On` (this Mac)

### Apple Intelligence & Siri

- Turn on **Apple Intelligence**
- **Siri Requests** → **Siri** − `On`
- **Siri Requests** → **Listen for** − `Off`
- **Siri Requests** → **Keyboard shortcut** − `⌃S`
- **Siri Requests** → **Language** − `English (United States)`

### Spotlight

Raycast handles ⌘Space on this Mac, and `set-defaults` turns off the Spotlight shortcuts (see [Keyboard](#keyboard)). Spotlight's index still runs searches in Finder and other apps, so trim what it shows:

- **Search results**: keep apps, documents, folders, System Settings, and calculator/conversion/definition results, and turn the rest off. Category names change between macOS versions, so check them in the pane.
- **Help Apple Improve Search** − `Off`

### iCloud

- **Advanced Data Protection** − `On`

### Privacy & Security

- **Location Services** → **System Services**: turn on _only_ these:
  - System customization
  - Find My Mac
  - Networking and wireless
- **Location Services** → **System Services** → **Show location icon in Control Center when System Services request your location** − `On`
- **App Management**: let these apps update or delete other apps:
  - Ghostty (_needed for some patching scripts_)
  - Raycast
- **Analytics & Improvements**: set everything to `Off`
- **Apple Advertising** → **Personalized Ads** − `Off`
- **Security** → **Allow applications from** − `App Store & Known Developers`
- **FileVault** − `On` (this Mac). Nobody can decrypt or read your data without your login password.

### Desktop & Dock

- **Size**: 38 px (set-defaults, `tilesize` 38)
- Remove the Dock icons you don't use
- **Magnification** − `On`, magnified size 52 px (this Mac)
- **Minimized window animation**: set-defaults uses the hidden `suck` effect, which isn't one of the pane's choices (Genie/Scale)
- **Window title bar double-click action** − `Fill` (set-defaults)
- **Minimize windows into application icon** − `On` (set-defaults)
- **Automatically hide and show the Dock** − `On` (set-defaults; reveal delay and slide animation stay at macOS defaults unless you opt in to custom values when prompted)
- **Animate opening applications** − `Off` (set by hand; set-defaults separately turns off Dock icon bouncing)
- **Show indicators for open applications** − `On` (set-defaults)
- **Show suggested and recent apps in Dock** − `Off` (set-defaults)
- **Desktop & Stage Manager** → **Show items** − `On Desktop`
- **Desktop & Stage Manager** → **Click wallpaper to show desktop** − `Only in Stage Manager`
- **Desktop & Stage Manager** → **Stage Manager** − `Off`
- **Desktop & Stage Manager** → **Show recent apps in Stage Manager** − `Off`
- **Widgets** → **Show Widgets** − `On Desktop`
- **Widgets** → **iPhone Widgets** − `Off`
- **Default web browser** − `Comet` (this Mac)
- **Windows** → **Prefer tabs when opening documents** − `In Full Screen`
- **Windows** → **Ask to keep changes when closing documents** − `On`
- **Windows** → **Close windows when quitting an application** − `Off`
- **Windows** → **Drag windows to left or right edge of screen to tile** − `On`
- **Windows** → **Drag windows to menu bar to fill screen** − `Off`
- **Windows** → **Hold ⌥ key while dragging windows to tile** − `On`
- **Windows** → **Tiled windows have margins** − `Off` (this Mac)
- **Mission Control** → **Automatically rearrange Spaces based on most recent use** − `On`
- **Mission Control** → **When switching to an application, switch to a Space with open windows for the application** − `Off`
- **Mission Control** → **Group windows by application** − `On` (set-defaults)
- **Mission Control** → **Displays have separate Spaces** − `On` (window tiling needs this)
- **Shortcuts…** → **Mission Control** − `⌃↑`
- **Shortcuts…** → **Application windows** − `⌃↓`
- **Shortcuts…** → **Show Desktop** − `F11`
- **Hot Corners…**: all four corners set to no action (set-defaults)

### Displays

- **Advanced…** → **Show resolutions as list** − `On`
- Pick a comfortable resolution (the built-in Liquid Retina XDR panel is 3024 × 1964)
- **Brightness**: around `85%`
- **Automatically adjust brightness** − `Off`
- **True Tone** − `On`
- **Color profile** − `Color LCD`
- **Night Shift…** − `Off`
- HiDPI display modes: off unless you opt in (set-defaults, prompt, default No)

### Battery

- **Energy Mode** − `Automatic` on battery and on power adapter (this Mac: Low Power Mode is off in both)
- **Battery Health** → **Optimized Battery Charging** − `On`
- **Options…** → **Slightly dim the display while on battery power** − `On`
- Handled by set-defaults (`pmset`): wake when the lid opens, hard disks sleep after 10 minutes, wake for network access off, hibernate mode 3

### Lock Screen

- **Turn display off on battery when inactive** − `For 2 minutes` (this Mac)
- **Turn display off on power adapter when inactive** − `For 10 minutes` (this Mac)
- **Require password after screen saver begins or display is turned off** − `Immediately`

### Users & Groups

- **Guest User** → **Allow guests to log in to this computer** − `Off` (this Mac)

### Keyboard

- **Key repeat rate** / **Delay until repeat**: set-defaults sets `KeyRepeat` 1 and `InitialKeyRepeat` 10, which are faster and shorter than the sliders' fastest and shortest positions. Moving either slider replaces that value. set-defaults also turns off press-and-hold for accented characters, so holding a key repeats it.
- **Adjust keyboard brightness in low light** − `Off`
- **Keyboard brightness**: around `20%`
- **Turn keyboard backlight off after inactivity** − `After 5 Minutes`
- **Press 🌐︎ key to** − `Change Input Source`
- **Keyboard navigation** − `On`
- **Keyboard Shortcuts…** → **Mission Control**: keep **Mission Control**, **Application windows**, **Show Desktop**, and **Move left a Space** / **Move right a Space** (`⌃←` / `⌃→`, on for this Mac) turned on, and turn the rest off
- **Keyboard Shortcuts…** → **Spotlight**: **Show Spotlight search** and **Show Finder search window** are turned off (set-defaults), which frees ⌘Space for Raycast
- **Keyboard Shortcuts…** → **Screenshots**: the system shortcuts are off on this Mac because CleanShot X uses ⌘⇧3, ⌘⇧4 and ⌘⇧5
- **Text Input** → **Text Replacements…**
  - `@@` → `you@example.com`
  - `->` → `→`
- **Text Input** → **Input Sources** → **Edit…** → **All Input Sources**
  - **Show Input menu in menu bar** − `On`
  - **Automatically switch to a document's input source** − `Off`
  - **Correct spelling automatically** − `Off` (set-defaults)
  - **Capitalize words automatically** − `Off` (set-defaults)
  - **Show inline predictive text** − `Off`
  - **Add period with double-space** − `Off` (set-defaults)
  - **Use smart quotes and dashes** − `Off` (set-defaults)
- Language & region formats: set-defaults sets English (US), USD, inches, and Fahrenheit

### Mouse

No mouse is paired with this Mac. If you connect one:

- **Tracking speed** − `Fast`
- **Natural scrolling** − `On` (macOS shares this setting with the trackpad; set-defaults doesn't change it)
- **Secondary click** − `Click Right Side`
- **Smart zoom** − `Off`
- **Swipe between pages** − `Off`
- **Swipe between full-screen applications** − `On`
- **Mission Control** − `On`

### Trackpad

- **Tracking speed** − `Fast`
- **Click** − `Medium` (this Mac)
- **Tap to click** − `Off` (this Mac)
- **Look up & data detectors** − `Force Click with One Finger` (this Mac)
- **Natural scrolling** − `On` (macOS default; set-defaults leaves it alone)
- **Swipe between pages** − `Off` (set-defaults)
- **Swipe between full-screen applications** − `Swipe Left or Right with Three Fingers` (set-defaults)
- **Notification Center** − `On` (this Mac: swipe left from the right edge with two fingers)
- **Mission Control** − `Swipe Up with Three Fingers` (this Mac)
- **App Exposé** − `Swipe Down with Three Fingers`
- **Apps** − `On` (pinch with thumb and three fingers; this replaced Launchpad, which macOS 27 removed)
- **Show Desktop** − `On`

## Finder

- Put your most-used places in the sidebar so you can reach them quickly:
  - Your home folder
  - The dotfiles repo (`$DOTFILES`, `~/dev/dotfiles` on this Mac)
  - Desktop
  - Applications
  - Downloads
  - Documents
  - `~/Library` (set-defaults unhides it; it also unhides `/Volumes`)
- Settings
  - **General** → **Show these items on the desktop:** − **Hard disks** and **External disks** `On` (set-defaults)
  - **General** → **New Finder windows show:** − your home folder (set-defaults)
  - **General** − Enable **Open folders in tabs instead of new windows**
  - **Tags**: turn off all tags
  - **Sidebar** → **Show these items in the sidebar**:
    - Applications
    - Desktop
    - Documents
    - Downloads
    - Your home folder
    - Hard disks
    - External disks
  - **Advanced** − Enable **Show all filename extensions** (set-defaults)
  - **Advanced** − Disable **Show warning before changing extension** (set-defaults)
  - **Advanced** − Enable **Show warning before removing from iCloud Drive**
  - **Advanced** − Enable **Show warning before emptying the Trash**
  - **Advanced** − Disable **Remove items from the Trash after 30 days**
  - **Advanced** → **Keep folders on top:** − **In windows when sorting by name** (set-defaults) and **On Desktop** (set by hand)
  - **Advanced** → **When performing a search:** − `Search the Current Folder` (set-defaults)
- Hidden files are shown (set-defaults)
- New windows open in list view (set-defaults). The desktop groups files into Stacks by Kind; the desktop and icon views snap to a grid and use 48 px icons (set-defaults).
- **View** → **Show Sidebar** (set-defaults)
- **View** → **Show Preview**
- **View** → **Show Toolbar**
- **View** → **Show Path Bar** (set-defaults)
- **View** → **Show Status Bar** (set-defaults)

### A few tips

- `⌘⇧H`: go to your home folder
- `⌘⇧.`: show or hide hidden files and folders in the current Finder window

## iPhone Mirroring

- **Settings…** → **Require Mac login to access iPhone:** − `Authenticate Automatically`

## Other Defaults

Run [`set-defaults`](../bin/set-defaults) to apply the scripted settings marked above, plus many that have no System Settings control, for example:

- Save and print panels open expanded
- No `.DS_Store` files on network or USB volumes
- Quick Look text selection
- Terminal secure keyboard entry
- Activity Monitor defaults
- Preview doesn't reopen previous files

The script also has optional prompts for screenshot preferences, TextEdit plain text, and download quarantine or disk-image verification (both prompts default to No, which keeps the protection on). It runs [`setup/macos.sh`](../setup/macos.sh).

## Built-in macOS Applications

- Notes
  - **Settings** → **New Notes Start With** − `Title`
  - **Settings** − Disable **Group Notes By Date**
