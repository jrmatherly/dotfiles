#!/bin/bash

# ~/.macos — https://mths.be/macos

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Configuring macOS with sane defaults…"
  echo
else
  exit 0
fi

# Prompt for a computer name so this script is reusable across machines.
# Leave blank to skip renaming this Mac.
# For non-interactive/scripted runs, pre-set COMPUTERNAME (and optionally
# LOCALHOSTNAME) as environment variables to skip the prompt entirely.
if [[ -z "${COMPUTERNAME:-}" && -t 0 ]]; then
  read -rp "Computer name (e.g. 'Jason's MacBook Pro'), leave blank to skip: " COMPUTERNAME
fi

if [[ -n "${COMPUTERNAME:-}" && -z "${LOCALHOSTNAME:-}" ]]; then
  # Suggest a Bonjour-safe local hostname derived from the computer name
  suggested_hostname=$(echo "$COMPUTERNAME" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9]+/-/g; s/^-+|-+\$//g")
  if [[ -t 0 ]]; then
    read -rp "Local hostname [$suggested_hostname]: " LOCALHOSTNAME
  fi
  LOCALHOSTNAME="${LOCALHOSTNAME:-$suggested_hostname}"
fi

# Close System Settings, to prevent it from overriding settings we’re about to
# change (it was "System Preferences" before macOS 13)
osascript -e 'tell application "System Settings" to quit'

# Ask for the administrator password upfront
sudo -v

# Keep-alive: *extend* the sudo timestamp until this script finishes
# (`sudo -n true` only checks it, so it would still expire after 5 minutes)
while true; do
  sudo -n -v
  sleep 60
  kill -0 "$$" || exit
done 2> /dev/null &

# Ask a yes/no question for optional/impactful setting groups below, so the
# same script can be reused on machines that want different answers (e.g. a
# work laptop with its firewall managed by MDM). Honors DOTFILES_MACOS_YES=1 /
# DOTFILES_MACOS_NO=1 to force all answers for non-interactive runs.
confirm() {
  local prompt="$1" default="${2:-Y}" reply hint
  [[ -n "${DOTFILES_MACOS_YES:-}" ]] && return 0
  [[ -n "${DOTFILES_MACOS_NO:-}" ]] && return 1
  if [[ ! -t 0 ]]; then
    [[ "$default" == "Y" ]]
    return
  fi
  hint="y/N"
  [[ "$default" == "Y" ]] && hint="Y/n"
  read -rp "$prompt [$hint] " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

###############################################################################
# General UI/UX                                                               #
###############################################################################

# Set computer name (as done via System Settings → General → Sharing)
if [[ -n "${COMPUTERNAME:-}" ]]; then
  sudo scutil --set ComputerName "$COMPUTERNAME"
  sudo scutil --set HostName "$COMPUTERNAME"
  sudo scutil --set LocalHostName "$LOCALHOSTNAME"
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$LOCALHOSTNAME"
else
  echo "Skipping computer name change (none provided)."
fi

# Set sidebar icon size to Large
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 3

# Show scroll bars when scrolling
# Possible values: `WhenScrolling`, `Automatic` and `Always`
defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Automatically quit printer app once the print jobs complete
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Fill window when double-clicking its title bar
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Fill"

# Download quarantine is a real protection (the “downloaded from the internet —
# are you sure?” check), so turning it off is opt-in
if confirm "Disable the 'downloaded from the internet' confirmation for new apps? (weakens security)" "N"; then
  defaults write com.apple.LaunchServices LSQuarantine -bool false
fi

# Disable the crash reporter
defaults write com.apple.CrashReporter DialogType -string "none"

# Set Help Viewer windows to non-floating mode
defaults write com.apple.helpviewer DevMode -bool true

# Disable automatic capitalization as it’s annoying when typing code
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable smart dashes as they’re annoying when typing code
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable automatic period substitution as it’s annoying when typing code
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Disable smart quotes as they’re annoying when typing code
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

###############################################################################
# Trackpad, mouse, keyboard, and input                                        #
###############################################################################

# Trackpad: disable swipe between pages
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 2

# Disable press-and-hold for keys in favor of key repeat
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Set a blazingly fast keyboard repeat rate
defaults write NSGlobalDomain KeyRepeat -int 1
# Set a shorter Delay until key repeat
defaults write NSGlobalDomain InitialKeyRepeat -int 10

# Set language and text formats
defaults write NSGlobalDomain AppleLanguages -array "en-US"
defaults write NSGlobalDomain AppleLocale -string "en_US@currency=USD"
defaults write NSGlobalDomain AppleMeasurementUnits -string "Inches"
defaults write NSGlobalDomain AppleTemperatureUnit -string "Fahrenheit"
defaults write NSGlobalDomain AppleMetricUnits -bool false

# Set the timezone; see `sudo systemsetup -listtimezones` for other values
#sudo systemsetup -settimezone "Europe/Brussels" > /dev/null

###############################################################################
# Energy saving                                                               #
###############################################################################

# Enable lid wakeup
sudo pmset -a lidwake 1

# Put the hard disk(s) to sleep when possible: 10 min
sudo pmset -a disksleep 10

# Disable wake for network access
sudo pmset -a womp 0

# Hibernation mode
# 0: Disable hibernation (speeds up entering sleep mode)
# 3: Copy RAM to disk so the system state can still be restored in case of a
#    power failure.
sudo pmset -a hibernatemode 3

###############################################################################
# Screen                                                                      #
###############################################################################

# (Password-after-sleep lives in System Settings → Lock Screen; the old
# com.apple.screensaver askForPassword keys have had no effect since macOS 13.)

if confirm "Apply custom screenshot preferences (save to Desktop as PNG, no shadow, show cursor, name 'Shot')?" "Y"; then
  # Save screenshots to the desktop
  defaults write com.apple.screencapture location -string "$HOME/Desktop"
  # Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
  defaults write com.apple.screencapture type png
  # Disable shadow in window captures
  defaults write com.apple.screencapture disable-shadow -bool true
  # Show the mouse pointer in screenshots
  defaults write com.apple.screencapture showsCursor -bool true
  # Change the default screenshot name
  defaults write com.apple.screencapture name "Shot"
else
  echo "Skipping screenshot preference changes."
fi

if confirm "Enable HiDPI display modes (requires restart)?" "N"; then
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
else
  echo "Skipping HiDPI (leaving as-is)."
fi

###############################################################################
# Security                                                                    #
###############################################################################

if confirm "Enable macOS Firewall + Stealth Mode?" "N"; then
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
else
  echo "Skipping firewall changes (leaving as-is)."
fi

###############################################################################
# Finder                                                                      #
###############################################################################

# Open new Finder windows in the home folder
# (other options: "PfDe" Desktop, "PfDo" Documents, "PfLo" custom path)
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

# Show icons for hard drives and external disks on the desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true

# Finder: show hidden files by default
defaults write com.apple.finder AppleShowAllFiles -bool true

# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Finder: show sidebar
defaults write com.apple.finder ShowSidebar -bool true

# Finder: show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Finder: show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Finder: allow text selection in Quick Look
defaults write com.apple.finder QLEnableTextSelection -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# When performing a search, search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Enable spring loading for directories
defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# Spring loading delay for directories (macOS default: 0.5s)
defaults write NSGlobalDomain com.apple.springing.delay -float 0.5

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Disk image checksum verification catches corrupted/tampered .dmg files, so
# skipping it is opt-in
if confirm "Skip disk image (.dmg) verification? (faster mounts, weakens security)" "N"; then
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
fi

# Enable snap-to-grid for icons on the desktop and in other icon views
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist

# Increase grid spacing for icons on the desktop and in other icon views
#/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
#/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
#/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist

# Increase the size of icons on the desktop and in other icon views
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 48" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 48" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 48" ~/Library/Preferences/com.apple.finder.plist

# Enable Stacks view on the desktop
defaults write com.apple.finder DesktopViewSettings -dict-add GroupBy -string "Kind"

# Use list view in all Finder windows by default
# Four-letter codes for the other view modes: `icnv`, `clmv`, `glyv`
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Finder: disable sounds
# defaults write com.apple.finder FinderSounds -boolean false

# Show the ~/Library folder
# First set the attribute if it doesn't exist, then show folder
xattr -w com.apple.FinderInfo "" ~/Library 2> /dev/null || true
chflags nohidden ~/Library
xattr -d com.apple.FinderInfo ~/Library 2> /dev/null || true

# Show the /Volumes folder
sudo chflags nohidden /Volumes

# Expand the following File Info panes:
# “General”, “More Info”, “Open with”, “Preview”, and “Sharing & Permissions”
defaults write com.apple.finder FXInfoPanesExpanded -dict \
  General -bool true \
  MetaData -bool true \
  OpenWith -bool true \
  Preview -bool true \
  Privileges -bool true

###############################################################################
# Dock and hot corners                                                        #
###############################################################################

# Enable highlight hover effect for the grid view of a stack (Dock)
defaults write com.apple.dock mouse-over-hilite-stack -bool true

# Set the icon size of Dock items to 38 pixels
defaults write com.apple.dock tilesize -int 38

# Change minimize/maximize window effect
defaults write com.apple.dock mineffect -string "suck"

# Minimize windows into their application’s icon
defaults write com.apple.dock minimize-to-application -bool true

# Enable spring loading for all Dock items
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

# Show indicator lights for open applications in the Dock
defaults write com.apple.dock show-process-indicators -bool true

# Show only currently running applications in the Dock
#defaults write com.apple.dock static-only -bool true

# Group windows by application in Mission Control
defaults write com.apple.dock expose-group-by-app -bool true

# Disable icon bouncing
defaults write com.apple.dock no-bouncing -bool true

# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool true

# Dock auto-hide timing: macOS defaults unless you opt in to custom values.
# autohide-delay is how long the pointer rests at the edge before the Dock
# appears; autohide-time-modifier is the slide animation's length (0 = none).
# Declining deletes both keys, so a re-run also clears earlier overrides.
if confirm "Customize Dock auto-hide timing (reveal delay / slide animation)?" "N"; then
  dock_delay=0.2 dock_anim=0
  if [[ -t 0 && -z "${DOTFILES_MACOS_YES:-}" ]]; then
    read -rp "  Reveal delay in seconds [$dock_delay]: " reply
    dock_delay="${reply:-$dock_delay}"
    read -rp "  Slide animation in seconds, 0 for none [$dock_anim]: " reply
    dock_anim="${reply:-$dock_anim}"
  fi
  for value in "$dock_delay" "$dock_anim"; do
    if [[ ! "$value" =~ ^[0-9]*\.?[0-9]+$ ]]; then
      echo "  '$value' isn't a number of seconds; using macOS defaults instead."
      dock_delay="" dock_anim=""
      break
    fi
  done
fi
if [[ -n "${dock_delay:-}" ]]; then
  defaults write com.apple.dock autohide-delay -float "$dock_delay"
  defaults write com.apple.dock autohide-time-modifier -float "$dock_anim"
else
  defaults delete com.apple.dock autohide-delay 2> /dev/null
  defaults delete com.apple.dock autohide-time-modifier 2> /dev/null
fi

# Make Dock icons of hidden applications translucent
defaults write com.apple.dock showhidden -bool true

# Don’t show suggested and recent applications in Dock
defaults write com.apple.dock show-recents -bool false

# Add iOS & Watch Simulator to Launchpad
#sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" "/Applications/Simulator.app"
#sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator (Watch).app" "/Applications/Simulator (Watch).app"

# Hot corners: all four set to no action.
# (Values: 1 no action, 2 Mission Control, 3 application windows, 4 Desktop,
#  5 start screen saver, 6 disable screen saver, 10 display sleep,
#  12 Notification Center, 13 Lock Screen, 14 Quick Note.)
for corner in tl tr bl br; do
  defaults write com.apple.dock "wvous-${corner}-corner" -int 1
  defaults write com.apple.dock "wvous-${corner}-modifier" -int 0
done

###############################################################################
# Mail                                                                        #
###############################################################################

# Disable send and reply animations in Mail.app
#defaults write com.apple.mail DisableReplyAnimations -bool true
#defaults write com.apple.mail DisableSendAnimations -bool true

# Copy email addresses as `foo@example.com` instead of `Foo Bar <foo@example.com>` in Mail.app
#defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

# Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app
#defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@\U21a9"

# Display emails in threaded mode, sorted by date (oldest at the top)
#defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
#defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
#defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"

# Disable inline attachments (just show the icons)
#defaults write com.apple.mail DisableInlineAttachmentViewing -bool true

###############################################################################
# Safari & WebKit                                                             #
###############################################################################

# Safari is sandboxed on modern macOS: its preferences live in its container
# and plain `defaults write com.apple.Safari …` from a terminal does not reach
# them. Configure Safari in Safari → Settings instead (search suggestions,
# Develop menu, fraud/HTTP warnings, AutoFill).

###############################################################################
# Spotlight                                                                   #
###############################################################################

# Remove Spotlight from menu bar (and subsequent helper)
#sudo chmod 600 /System/Library/CoreServices/Search.bundle/Contents/MacOS/Search

# Search categories: set in System Settings → Spotlight. (The old
# com.apple.spotlight `orderedItems` list no longer exists — current macOS
# stores Spotlight settings as DisabledUTTypes/EnabledPreferenceRules — and
# rebuilding the whole-disk index on every run was dropped.)

# Spotlight search shortcut: none
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "{ enabled = 0; value = { parameters = (65535, 49, 1048576); type = standard; }; }"

# Menu Bar Spotlight shortcut: none
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 "{ enabled = 0; value = { parameters = (65535, 49, 1572864); type = standard; }; }"

###############################################################################
# Terminal                                                                    #
###############################################################################

# Only use UTF-8 in Terminal.app
defaults write com.apple.terminal StringEncodings -array 4

# Enable “focus follows mouse” for Terminal.app and all X11 apps
# i.e. hover over a window and start typing in it without clicking first
#defaults write com.apple.terminal FocusFollowsMouse -bool true
#defaults write org.x.X11 wm_ffm -bool true

# Enable Secure Keyboard Entry in Terminal.app
# See: https://security.stackexchange.com/a/47786/8918
defaults write com.apple.terminal SecureKeyboardEntry -bool true

# Disable the annoying line marks
defaults write com.apple.Terminal ShowLineMarks -int 0

###############################################################################
# Time Machine                                                                #
###############################################################################

if confirm "Suppress Time Machine's 'use as backup disk?' prompt for new drives?" "Y"; then
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
fi

# WARNING: this fully disables local Time Machine backups/snapshots.
if confirm "Disable Time Machine backups entirely on this Mac? (WARNING: stops all TM backups)" "N"; then
  hash tmutil &> /dev/null && sudo tmutil disable
else
  echo "Leaving Time Machine backups enabled."
fi

###############################################################################
# Activity Monitor                                                            #
###############################################################################

# Show the main window when launching Activity Monitor
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

# Visualize CPU usage in the Activity Monitor Dock icon
defaults write com.apple.ActivityMonitor IconType -int 5

# Show all processes, hierarchically
defaults write com.apple.ActivityMonitor ShowCategory -int 102

# Sort Activity Monitor results by CPU usage
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0

###############################################################################
# TextEdit and QuickTime Player                                               #
###############################################################################

if confirm "Default TextEdit to plain text + UTF-8?" "Y"; then
  defaults write com.apple.TextEdit RichText -int 0
  defaults write com.apple.TextEdit PlainTextEncoding -int 4
  defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
fi

# Auto-play videos when opened with QuickTime Player
defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true

###############################################################################
# Mac App Store                                                               #
###############################################################################

if confirm "Enable automatic Software Update checks/downloads/installs?" "Y"; then
  # Enable the automatic update check
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  # Check for software updates daily, not just once per week
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  # Download newly available updates in background
  defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
  # Install system data files & security updates
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
else
  echo "Skipping Software Update automation changes (leaving MDM/manual policy as-is)."
fi

###############################################################################
# Preview                                                                     #
###############################################################################

# Do not open previous previewed files (e.g. PDFs) when opening a new one
defaults write com.apple.Preview ApplePersistenceIgnoreState YES

###############################################################################
# Photos                                                                      #
###############################################################################

# Prevent Photos from opening automatically when devices are plugged in
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

###############################################################################
# Messages                                                                    #
###############################################################################

# Disable automatic emoji substitution (i.e. use plain text smileys)
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false

# Disable smart quotes as it’s annoying for messages that contain code
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false

# Disable continuous spell checking
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false

###############################################################################
# Kill affected applications                                                  #
###############################################################################

for app in "Activity Monitor" \
  "Dock" \
  "Finder" \
  "Messages" \
  "NotificationCenter" \
  "SystemUIServer" \
  "Terminal"; do
  killall "$app" > /dev/null 2>&1
done
echo "Done! Note that some of these changes require a logout/restart to take effect."
