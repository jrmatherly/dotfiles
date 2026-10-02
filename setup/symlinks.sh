#!/bin/bash

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}"
TILDE_DIR="$DOTFILES_DIR/tilde"

EXCLUDE_FILES=(".DS_Store" "Brewfile.lock.json" "README.md" ".codex" ".ssh")

indent() {
  sed 's/^/  /'
}

tildify() {
  printf '%s' "${1/#$HOME/~}"
}

info() {
  printf '%s' "$1" | indent
  echo
}

# %b, not %s: callers wrap long prompts with \n
user() {
  printf "\r  [ \033[0;33m?\033[0m ] %b " "$1"
}

success() {
  printf "\r\033[2K   %s\n" "$1"
}

skipped() {
  printf "\r\033[2K  [skipped]  %s\n" "$1"
}

fail() {
  printf "\r\033[2K  [\033[0;31m✖\033[0m] %s\n" "$1"
  echo ''
  exit 1
}

warn() {
  printf "\r\033[2K  [\033[0;33m!\033[0m] %s\n" "$1"
}

symlink_file() {
  local src=$1 dst=$2 isHardLink=${3:-false}

  local overwrite=false
  local backup=false
  local skip=false
  local action=""

  if [ ! -d "$(dirname "$dst")" ]; then
    mkdir -p "$(dirname "$dst")"
  fi

  # First, check if the destination file or folder exists
  if [ -e "$dst" ]; then

    # Check if the destination is a hard link to the same inode as the source
    # (only meaningful when `isHardLink=true`, but `-ef` is harmless otherwise)
    if [ "$isHardLink" = true ] && [ "$dst" -ef "$src" ]; then
      # Already hard linked to the dotfiles source, skip overwriting
      skip=true

    # Check if the destination is a symlink
    elif [ -L "$dst" ]; then

      # Check if the destination is already a symlink to the dotfiles
      readlink_out=$(readlink "$dst")
      local current_src="$readlink_out"

      if [ "$current_src" == "$src" ]; then
        # Skip overwriting
        skip=true
      else
        # If the destination is a symlink to something else, ask to overwrite
        handle_existing_file
      fi

    else

      # If the destination is a regular file or directory, ask to overwrite
      handle_existing_file

    fi

  fi

  # "false" or empty
  if [ "$skip" != "true" ]; then
    local ln_cmd="ln"
    if [ ! -w "$(dirname "$2")" ]; then
      ln_cmd="sudo ln"
    fi

    if [ "$isHardLink" = true ]; then
      $ln_cmd -f "$1" "$2"
      success "$(tildify "$2")"
    else
      # `-n` keeps us from linking *into* an existing symlinked directory
      $ln_cmd -sfn "$1" "$2"
      success "$(tildify "$2")"
    fi
  else
    skipped "$(tildify "$dst")"
  fi
}

handle_existing_file() {
  if [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]; then
    user "File already exists: $dst ($(basename "$src")), what do you want to do?\n\
    [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
    # A closed stdin (non-interactive run) reads as EOF — skip rather than
    # aborting the whole run under `set -e`
    read -rn 1 action || action="s"

    case "$action" in
      o)
        overwrite=true
        ;;
      O)
        overwrite_all=true
        ;;
      b)
        backup=true
        ;;
      B)
        backup_all=true
        ;;
      s)
        skip=true
        ;;
      S)
        skip_all=true
        ;;
      # Anything else (including a bare Enter) skips: never destroy an existing
      # file just because the answer wasn't understood
      *)
        skip=true
        ;;
    esac
  fi

  # A per-file answer wins; otherwise fall back to the "…all" answer
  [ "$overwrite" == "true" ] || overwrite=$overwrite_all
  [ "$backup" == "true" ] || backup=$backup_all
  [ "$skip" == "true" ] || skip=$skip_all

  if [ "$overwrite" == "true" ]; then
    rm -rf "$dst"
    success "removed $dst"
  fi

  if [ "$backup" == "true" ]; then
    mv "$dst" "${dst}.backup"
    success "moved $dst to ${dst}.backup"
  fi
}

install_dotfiles() {
  info 'Syncing dotfiles…'

  local overwrite_all=false
  local backup_all=false
  local skip_all=false

  # Create .config directory if it doesn't exist
  mkdir -p ~/.config

  cd "$TILDE_DIR"

  # Loop through all items in the `tilde` directory
  for item in .* *; do
    # Skip the current and parent directory entries
    if [ "$item" == "." ] || [ "$item" == ".." ]; then
      continue
    fi

    # Ignore exclude files
    for excluded in "${EXCLUDE_FILES[@]}"; do
      if [[ "$item" == "$excluded" ]]; then
        # Skip to the next iteration of the outer loop
        continue 2
      fi
    done

    # is a dotfile
    if [ -f "$item" ]; then
      src="$PWD/$item"
      dest="$HOME/$item"
      symlink_file "$src" "$dest"
    # is a dir with dotfiles
    elif [ -d "$item" ]; then
      if [ "$item" == ".claude" ]; then
        # Claude Code keeps its own state in ~/.claude, and ~/.claude/rules may
        # hold machine-local rules: keep both real directories and link each
        # tracked rule into it, plus top-level files. (~/.claude/CLAUDE.md isn't tracked:
        # `codegraph install` rewrites it.) Migrate the earlier whole-dir link.
        if [ -L "$HOME/.claude/rules" ] && [ "$(readlink "$HOME/.claude/rules")" = "$PWD/.claude/rules" ]; then
          rm "$HOME/.claude/rules"
        fi
        mkdir -p "$HOME/.claude/rules"
        for rule in .claude/rules/*.md; do
          symlink_file "$PWD/$rule" "$HOME/$rule"
        done
        # Top-level files, e.g. the status line script settings.json points at
        for file in .claude/*; do
          if [ -f "$file" ]; then symlink_file "$PWD/$file" "$HOME/$file"; fi
        done
      elif [ "$item" != ".config" ]; then
        src="$PWD/$item"
        dest="$HOME/$item"
        symlink_file "$src" "$dest"
      else
        # Handle the `.config` dir separately
        for config_item in "$item"/*; do
          src="$PWD/$config_item"
          dest="$HOME/$config_item"
          symlink_file "$src" "$dest"
        done
      fi
    fi
  done
}

configure_git_identity() {
  local gitconfig_local="$HOME/.gitconfig.local"

  if [ -f "$gitconfig_local" ]; then
    skipped "$(tildify "$gitconfig_local")"
    return
  fi

  local name="${DOTFILES_GIT_NAME:-}"
  local email="${DOTFILES_GIT_EMAIL:-}"
  local sign_method="${DOTFILES_GIT_SIGN_METHOD:-}" # ssh | gpg | none
  local signing_key="${DOTFILES_GIT_SIGNINGKEY:-}"

  if [ -t 0 ]; then
    [ -z "$name" ] && read -rp "Git user.name: " name
    [ -z "$email" ] && read -rp "Git user.email: " email

    if [ -z "$sign_method" ]; then
      user "Sign commits with [s]sh (e.g. 1Password), [g]pg, or [n]one?"
      read -rn 1 sign_choice
      echo
      case "$sign_choice" in
        s | S) sign_method="ssh" ;;
        g | G) sign_method="gpg" ;;
        *) sign_method="none" ;;
      esac
    fi

    if [ "$sign_method" = "ssh" ] && [ -z "$signing_key" ]; then
      read -rp "SSH public key for signing (e.g. from 1Password: 'ssh-ed25519 AAAA...'): " signing_key
    elif [ "$sign_method" = "gpg" ] && [ -z "$signing_key" ]; then
      read -rp "GPG signing key ID: " signing_key
    fi
  fi

  if [ -z "$name" ] || [ -z "$email" ]; then
    skipped "$(tildify "$gitconfig_local") (no name/email provided — set DOTFILES_GIT_NAME/DOTFILES_GIT_EMAIL, or create it manually)"
    return
  fi

  {
    echo "[user]"
    echo "  name = $name"
    echo "  email = $email"
    [ -n "$signing_key" ] && echo "  signingKey = $signing_key"

    case "$sign_method" in
      ssh)
        echo
        echo "[gpg]"
        echo "  format = ssh"
        echo "[gpg \"ssh\"]"
        echo "  program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign"
        echo
        echo "[commit]"
        echo "  gpgSign = true"
        echo
        echo "[tag]"
        echo "  gpgSign = true"
        ;;
      gpg)
        echo
        echo "[commit]"
        echo "  gpgSign = true"
        echo
        echo "[tag]"
        echo "  gpgSign = true"
        ;;
      *) ;;
    esac
  } > "$gitconfig_local"

  success "$(tildify "$gitconfig_local")"
}

install_ssh_config() {
  local overwrite_all=false
  local backup_all=false
  local skip_all=false
  local ssh_dir="$HOME/.ssh"

  # Earlier versions linked the whole ~/.ssh into the repo. Turn it back into a
  # real directory so no prompt can ever touch key files: remove the link (not
  # the repo folder), then move any machine files ssh wrote through it — e.g.
  # known_hosts, which is gitignored — back where they belong.
  if [ -L "$ssh_dir" ] && [ "$(readlink "$ssh_dir")" = "$TILDE_DIR/.ssh" ]; then
    rm "$ssh_dir"
    mkdir -m 700 "$ssh_dir"
    for item in "$TILDE_DIR/.ssh"/* "$TILDE_DIR/.ssh"/.[!.]*; do
      [ -e "$item" ] || continue
      [ "$(basename "$item")" = "config" ] && continue
      mv "$item" "$ssh_dir/"
    done
    success "migrated ~/.ssh from a repo link to a real directory"
  elif [ -L "$ssh_dir" ]; then
    warn "$(tildify "$ssh_dir") is a symlink to $(readlink "$ssh_dir") — leaving it alone"
    return
  fi

  # Create it if missing, and keep ssh's required permissions either way
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  symlink_file "$TILDE_DIR/.ssh/config" "$ssh_dir/config"

  if [ ! -f "$ssh_dir/github_personal.pub" ]; then
    warn "$(tildify "$ssh_dir")/github_personal.pub not found — GitHub SSH needs it to pick your 1Password key (see tilde/.ssh/config)"
  fi
}

install_extras() {
  local overwrite_all=false
  local backup_all=false
  local skip_all=false

  if [ ! -d "/usr/local/bin" ]; then
    echo "Administrator password required to create /usr/local/bin:"
    sudo mkdir -p "/usr/local/bin"
  fi

  # CotEditor: Install `cot` command-line tool
  if ! command -v cot &> /dev/null; then
    if [ -x "/Applications/CotEditor.app/Contents/SharedSupport/bin/cot" ]; then
      symlink_file "/Applications/CotEditor.app/Contents/SharedSupport/bin/cot" "/usr/local/bin/cot"
    else
      warn "CotEditor not installed — skipping the \`cot\` CLI"
    fi
  fi

  #
  # VSCode
  #

  # Install `code` command in PATH
  if ! command -v code &> /dev/null; then
    if [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
      symlink_file "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "/usr/local/bin/code"
    else
      warn "VSCode not installed — skipping the \`code\` CLI"
    fi
  fi
  # Enable settings sync from dotfiles. The `User` folder only exists once
  # VSCode has been launched at least once, so create the parent ourselves and
  # let `symlink_file` ask before replacing any existing settings.
  symlink_file "$DOTFILES_DIR/vscode/User" "$HOME/Library/Application Support/Code/User"

  # Lazydocker
  symlink_file "$DOTFILES_DIR/lazydocker/config.yml" "$HOME/Library/Application Support/lazydocker/config.yml"

  # Lazygit: config lives in the repo and is passed via the `lg` alias
  # (`--use-config-dir`); `state.yml` is machine-local and gitignored, so
  # there's nothing to link here.

  # GPG — create ~/.gnupg ourselves: `symlink_file`'s `mkdir -p` would leave it
  # 755, and gpg warns "unsafe permissions on homedir" unless it's 700
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  symlink_file "$DOTFILES_DIR/gpg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

  # Quick-Look plugins to enhance experience using file manager
  symlink_file "$DOTFILES_DIR/ql-plugins" "$HOME/Library/QuickLook"

  # Firefox Developer Edition — only when a dev-edition profile exists
  # (an empty path would resolve to `/`, which we must never write to)
  ff_dev_profile_dir="$("$DOTFILES_DIR"/firefox/lib/get-firefox-dev-path)"
  if [ -n "$ff_dev_profile_dir" ] && [ -d "$ff_dev_profile_dir" ]; then
    symlink_file "$DOTFILES_DIR/firefox/user.js" "$ff_dev_profile_dir/user.js" true
    mkdir -p "$ff_dev_profile_dir/chrome"
    ln -f "$DOTFILES_DIR/firefox/chrome/userContent.css" "$ff_dev_profile_dir/chrome/userContent.css"
    ln -f "$DOTFILES_DIR/firefox/chrome/userChrome.css" "$ff_dev_profile_dir/chrome/userChrome.css"
    success "$(tildify "$ff_dev_profile_dir/chrome")"
  else
    warn "No Firefox Developer Edition profile found — skipping Firefox styles"
  fi

  #
  # AI agents
  #

  AGENTS_SETUP_DIR="$DOTFILES_DIR/agents"
  AGENTS_INSTRUCTIONS="$AGENTS_SETUP_DIR/instructions.md"

  #
  # Amp
  #

  # Base instructions: nothing to do. ~/.config/amp links to tilde/.config/amp,
  # whose AGENTS.md is a relative link to agents/instructions.md in the repo.
  # (Linking it here would write *through* the directory link and replace the
  # tracked file.)

  #
  # Codex
  #

  # Base instructions
  symlink_file "$AGENTS_INSTRUCTIONS" "$HOME/.codex/AGENTS.md"
  # Configuration: a copy, not a link (install_codex_config)
  install_codex_config
}

# Codex and apps that register MCP servers (NotchBar, Jean, whose entry carries
# a token) rewrite ~/.codex/config.toml in place. Through a link those writes
# would land in the repo, so the tracked file only seeds a missing config (or
# replaces an old link with a copy). After that, warn about tracked lines the
# live file lacks and leave it alone.
install_codex_config() {
  local src="$DOTFILES_DIR/tilde/.codex/config.toml" dst="$HOME/.codex/config.toml" missing
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] || [ ! -e "$dst" ]; then
    rm -f "$dst"
    cp "$src" "$dst"
    success "$(tildify "$dst") (copied from $(tildify "$src"))"
    return
  fi
  missing=$(grep -vE '^[[:space:]]*(#|$)' "$src" | while IFS= read -r line; do
    grep -qxF -- "$line" "$dst" || printf '      %s\n' "$line"
  done)
  if [ -n "$missing" ]; then
    warn "$(tildify "$dst") lacks these lines from $(tildify "$src") — add them by hand:"
    printf '%s\n' "$missing"
  fi
}

install_dotfiles
install_ssh_config
configure_git_identity
install_extras

# bat only sees custom themes (tilde/.config/bat/themes, now linked) after its
# cache is rebuilt — otherwise BAT_THEME (zsh/env.zsh) warns "Unknown theme"
if command -v bat &> /dev/null; then
  bat cache --build > /dev/null && success "bat theme cache rebuilt"
fi
echo
echo 'Done!' | indent
