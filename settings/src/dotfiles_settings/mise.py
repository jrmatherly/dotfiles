"""Run mise, find its config dir and check the version floor."""
import os, subprocess
from pathlib import Path

from .model import SettingsError

FLOOR = (2026, 11, 5)
MISSING = "dotfiles-settings needs mise 2026.11.5 or newer, and mise is not on PATH"


def run_mise(args: list[str], stdin: str | None = None) -> str:
    # From $HOME, so an untrusted mise.toml in the folder the UI started in never makes mise fail
    try:
        r = subprocess.run([os.environ.get("DOTFILES_SETTINGS_MISE", "mise"), *args], input=stdin,
                           capture_output=True, text=True, cwd=Path.home())
    except FileNotFoundError:
        raise SettingsError(MISSING) from None
    if r.returncode != 0:
        raise SettingsError(r.stderr.strip() or f"mise {' '.join(args)} exited {r.returncode}")
    return r.stdout


def config_dir() -> Path:
    return Path(os.environ.get("MISE_CONFIG_DIR") or Path.home() / ".config/mise")


def installed(path: Path) -> bool:
    """Whether path is inside the copy mise fetched (bin/lib/rotm-mode), which is updated by fast-forward."""
    checkout = Path(os.environ.get("MISE_DATA_DIR") or Path.home() / ".local/share/mise") / "bootstrap-repo"
    return checkout.exists() and path.resolve().is_relative_to(checkout.resolve())


def refuse_installed(path: Path) -> None:
    if installed(path):
        raise SettingsError("an installed copy cannot keep this setting yet: it is stored in a tracked file, "
                            "which rotm update must be able to replace")


def check_version() -> None:
    out = run_mise(["--version"]).split()
    token = out[0] if out else ""
    try:
        version = tuple(int(p) for p in token.split("."))
    except ValueError:
        version = ()
    if version < FLOOR:
        raise SettingsError(f"dotfiles-settings needs mise 2026.11.5 or newer, found {token or 'nothing'}")
