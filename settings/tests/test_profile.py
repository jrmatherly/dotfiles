"""Checks profiles against a stub mise and the real rotm-user-layer in a temp home. Run: python3 test_profile.py"""
import atexit, os, shutil, stat, sys, tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
repo = Path(__file__).resolve().parents[2]
cfg, user, log = tmp / "home/.config/mise", tmp / "home/.config/rotm", tmp / "calls"
cfg.mkdir(parents=True)


def script(path: Path, body: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/bin/bash\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return str(path)


# One log for both, so the order of an ensure and a mise call can be read
script(tmp / "dotfiles/bin/lib/rotm-user-layer", f'echo "ensure" >> {log}\nexec {repo}/bin/lib/rotm-user-layer "$@"')
os.environ.update(HOME=str(tmp / "home"), MISE_CONFIG_DIR=str(cfg), ROTM_USER_DIR=str(user), DOTFILES=str(tmp / "dotfiles"),
                  XDG_STATE_HOME=str(tmp / "state"),
                  DOTFILES_SETTINGS_MISE=script(tmp / "mise", f'echo "mise $*" >> {log}'))
os.environ.pop("MISE_ENV", None)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import profile, sync
from dotfiles_settings.model import InvalidValue, SettingsError

sync.apply = lambda: ["APPLIED"]
rc = cfg / "miserc.local.toml"


def calls() -> list[str]:
    return log.read_text().splitlines() if log.exists() else []


def raises(fn, kind, needle, *args):
    try:
        fn(*args)
    except kind as e:
        assert needle in str(e), e
    else:
        raise AssertionError(f"{fn.__name__}{args} did not raise")


def linked(name: str) -> bool:
    return (cfg / name).is_symlink() and (cfg / name).resolve() == user / name


# new: the two files in the user's folder, linked, and the choice of profile untouched
(cfg / "modules-off.local").write_text("cloud\n")
rc.write_text('env = ["rotm-installed"]\n')
profile.new("work")
assert (user / "config.rotm-p-work.override.toml").read_text() == "" and linked("config.rotm-p-work.override.toml")
assert (user / "modules-off.rotm-p-work.local").read_text() == "cloud\n" and linked("modules-off.rotm-p-work.local")
assert calls() == ["ensure"] and rc.read_text() == 'env = ["rotm-installed"]\n'
assert profile.names() == ["work"] and profile.override_path("work") == cfg / "config.rotm-p-work.override.toml"
assert profile.tools_path("work") == user / "tools.rotm-p-work.toml"
raises(profile.new, InvalidValue, "already exists", "work")
before = sorted(p.name for p in user.iterdir())
for bad in ("Work", "my work", "../x", "", "default", "a" * 40):
    raises(profile.new, InvalidValue, "profile name", bad)
assert sorted(p.name for p in user.iterdir()) == before

# use: mise writes the env line, other names keep their order, and ensure runs first
log.unlink()
out = profile.use("work")
assert calls() == ["ensure", "mise -E rotm-installed,rotm-p-work bootstrap --save-env --only final-hook"], calls()
assert out[1:] == ["APPLIED", "Open a new shell to pick this up."], out
profile.new("home")
rc.write_text('env = ["rotm-installed", "rotm-p-home", "staging"]\n')
profile.use("work")
assert calls()[-1] == "mise -E rotm-installed,staging,rotm-p-work bootstrap --save-env --only final-hook"

# use default: mise drops the profile, or the line goes when nothing else is in it
rc.write_text('env = ["rotm-installed", "rotm-p-work"]\n')
profile.use("default")
assert calls()[-1] == "mise -E rotm-installed bootstrap --save-env --only final-hook"
rc.write_text('env = ["rotm-p-work"]\nignored_config_paths = ["conf.d/60-rotm-fonts.toml"]\n')
log.unlink()
profile.use("default")
assert calls() == ["ensure"] and rc.read_text() == 'ignored_config_paths = ["conf.d/60-rotm-fonts.toml"]\n'

# use refuses an unknown profile and an env list it cannot rewrite
raises(profile.use, InvalidValue, "Profiles: default, home, work", "nope")
split = 'env = [\n  "rotm-installed",\n]\n'
rc.write_text(split)
raises(profile.use, SettingsError, "spans several lines", "work")
assert rc.read_text() == split

# a one-line list with brackets in a trailing comment is not a multi-line list
rc.write_text('env = ["rotm-installed"] # was [x]]\n')
profile.use("work")
assert calls()[-1] == "mise -E rotm-installed,rotm-p-work bootstrap --save-env --only final-hook"
# a line this module cannot remove is an error, not a false "now using the shared settings"
quoted = '"env" = ["rotm-p-work"]\n'
rc.write_text(quoted)
raises(profile.use, SettingsError, "edit it by hand", "default")
assert rc.read_text() == quoted
# an env that is not a list of names is one line, not a traceback
for bad in ("env = 5\n", "env = [1]\n"):
    rc.write_text(bad)
    raises(profile.listing, SettingsError, "env")

# active and target
rc.write_text('env = ["rotm-installed", "rotm-p-work"]\n')
assert profile.active() == profile.target() == "work"
profile.shared = True
assert profile.target() is None and profile.active() == "work"
profile.shared = False
rc.write_text('env = ["rotm-installed"]\n')
assert profile.active() is None
rc.unlink()
assert profile.selected() == [] and profile.active() is None

# listing
assert profile.listing() == ["* default", "  home", "  work"]
rc.write_text('env = ["rotm-installed", "rotm-p-work"]\n')
assert profile.listing() == ["  default", "  home", "* work"]
# MISE_ENV replaces the saved list in mise, so the saved profile is not the one in effect in that shell
os.environ["MISE_ENV"] = "staging"
assert profile.active() is None and profile.selected() == ["rotm-installed", "rotm-p-work"]
assert profile.listing() == ["* default", "  home", "  work",
                             "MISE_ENV is set in this shell, and mise uses it in place of the saved profile."]
os.environ["MISE_ENV"] = "staging,rotm-p-work"
assert profile.active() == "work" and profile.listing()[2] == "* work"
del os.environ["MISE_ENV"]
rc.write_text('env = ["rotm-p-gone"]\n')
assert profile.listing() == ["* default", "  home", "  work", "The saved profile gone has no settings file on this Mac."]

# state: what listing prints, as data
assert profile.state() == {"active": "default", "names": ["home", "work"], "missing": "gone", "mise_env": False}
rc.write_text('env = ["rotm-installed", "rotm-p-work"]\n')
assert profile.state() == {"active": "work", "names": ["home", "work"], "missing": None, "mise_env": False}
os.environ["MISE_ENV"] = "staging"
assert profile.state() == {"active": "default", "names": ["home", "work"], "missing": None, "mise_env": True}
del os.environ["MISE_ENV"]
rc.unlink()
assert profile.state()["active"] == "default" and profile.state()["missing"] is None

print("ok")
