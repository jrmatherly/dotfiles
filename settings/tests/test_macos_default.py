"""Checks the macos-default adapter against a temp fragment, a stubbed mise and stubbed defaults. Run: python3 test_macos_default.py"""
import atexit, contextlib, io, json, os, re, shutil, sys, tempfile, tomllib
from dataclasses import replace
from pathlib import Path

tmp = Path(tempfile.mkdtemp())
atexit.register(shutil.rmtree, tmp, True)
home, conf = tmp / "home", tmp / "conf"
(conf / "conf.d").mkdir(parents=True)
home.mkdir()
os.environ.update(HOME=str(home), MISE_CONFIG_DIR=str(conf))
os.environ.pop("DOTFILES_SETTINGS_MISE", None)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import cli, mise, profile, registry
from dotfiles_settings.adapters import ADAPTERS, macos_default
from dotfiles_settings.adapters.macos_default import (MacosDefaultAdapter, fragment_path, remove_key, set_key, split_key,
                                                      to_literal)
from dotfiles_settings.model import InvalidValue, Setting, SettingsError, Source

FRAGMENT = '''# header comment
[bootstrap.settings.macos.defaults.NSGlobalDomain]
# key repeat why
KeyRepeat = 1
"com.apple.springing.enabled" = true

[bootstrap.settings.macos.defaults."com.apple.dock"]
# size why
tilesize = 38 # trailing why
autohide = true
FXInfo = { General = true }

[[bootstrap.settings.macos.defaults_entries]]
domain = "com.apple.finder"
key = "DesktopViewSettings"
path = ["GroupBy"]
value = "Kind"
'''

BASE = Setting(id="macos.t", section="T", label="T", help="", kind="macos-default", key="", type="string", access="rw")


def setting(**fields):
    return replace(BASE, **fields)


def raises(exc, fn, contains=""):
    try:
        fn()
    except exc as e:
        assert contains in str(e), (contains, str(e))
        return
    raise AssertionError(f"expected {exc.__name__}: {contains}")


# set_key keeps every comment and touches one line
out = set_key(FRAGMENT, "com.apple.dock", "tilesize", "44")
assert "tilesize = 44 # trailing why" in out and "# size why" in out and "# key repeat why" in out
assert out.replace("tilesize = 44", "tilesize = 38") == FRAGMENT

# quoted keys and bare domains
assert '"com.apple.springing.enabled" = false' in set_key(FRAGMENT, "NSGlobalDomain", "com.apple.springing.enabled", "false")

# the spelling mise 2026.11.8 deprecates is not read
old = '[bootstrap.macos.defaults."com.apple.dock"]\ntilesize = 48\n'
assert macos_default.declared(old, "com.apple.dock", "tilesize") is macos_default.MISSING

# a new key lands in its table, a new table lands at the end
out = set_key(FRAGMENT, "com.apple.dock", "show-recents", "false")
assert tomllib.loads(out)["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.dock"]["show-recents"] is False
assert out.index("show-recents") < out.index("[[bootstrap.settings.macos.defaults_entries]]")
out = set_key(FRAGMENT, "com.apple.screencapture", "name", '"Shot"')
assert tomllib.loads(out)["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.screencapture"] == {"name": "Shot"}

# the type guard: 1 is not true
raises(InvalidValue, lambda: set_key(FRAGMENT, "com.apple.dock", "autohide", "1"))
# not a one-line scalar
raises(SettingsError, lambda: set_key(FRAGMENT, "com.apple.dock", "FXInfo", "true"))

# remove_key drops the line and nothing else
out = remove_key(FRAGMENT, "com.apple.dock", "autohide")
assert "autohide" not in out and "tilesize = 38 # trailing why" in out

# Review Focus 2: a hostile string survives
nasty = 'Sh"ot \\ #1'
s = setting(key="com.apple.screencapture/name", type="string")
out = set_key(FRAGMENT, "com.apple.screencapture", "name", to_literal(s, nasty))
assert tomllib.loads(out)["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.screencapture"]["name"] == nasty
# and again when it replaces a value that already has a trailing comment
out = set_key(out.replace(to_literal(s, nasty), to_literal(s, nasty) + " # why"), "com.apple.screencapture", "name", to_literal(s, "a # b"))
assert tomllib.loads(out)["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.screencapture"]["name"] == "a # b" and out.endswith('"a # b" # why\n')

# to_literal: a bool arrives the way the CLI passes it, "" for false
b = setting(key="com.apple.dock/autohide", type="bool", true_value="true")
assert to_literal(b, cli.normalize(b, "on")) == "true"
for off in ("false", "off", "no", "0"):
    assert to_literal(b, cli.normalize(b, off)) == "false", off
raises(InvalidValue, lambda: to_literal(b, "yes"))
raises(InvalidValue, lambda: to_literal(b, "false"))
raises(InvalidValue, lambda: to_literal(setting(key="com.apple.dock/tilesize", type="int"), "big"))

dock = setting(id="macos.dock.tilesize", key="com.apple.dock/tilesize", type="int")
entry = {"domain": "com.apple.dock", "host": "any", "path": None, "key": "tilesize", "value": 38, "current": "38", "state": "set"}

# Review Focus 4, unstubbed: a fragment outside any git checkout has no HEAD
fragment_path().write_text(FRAGMENT)
assert macos_default.head_text() is None

# Review Focus 5, with the real mise: a config with no macOS section prints {} and reads as unset
if shutil.which("mise"):
    fragment_path().rename(tmp / "aside.toml")
    assert mise.run_mise(["bootstrap", "macos", "defaults", "status", "--json"]).strip() == "{}"
    v = MacosDefaultAdapter().read(dock)
    assert (v.value, v.source, v.drift) == (None, Source.UNSET, False)
    (tmp / "aside.toml").rename(fragment_path())
else:
    print("skipped the real-mise read: mise not found")

calls, written, killed = [], [], []
macos_default.defaults_write = lambda *a: written.append(a)
macos_default.killall = killed.append


def status(entries):
    calls.clear(), written.clear(), killed.clear()
    out = json.dumps({"macos_defaults": {"available": True, "entries": entries}})
    mise.run_mise = lambda args, stdin=None: calls.append(args) or out


def head(text):
    macos_default.head_text = lambda: text


adapter = MacosDefaultAdapter()

# read: committed and applied
status([entry]); head(FRAGMENT)
v = adapter.read(dock)
assert (v.value, v.source, v.seed, v.drift) == ("38", Source.SEED, "38", False)

# read: live value differs
status([{**entry, "current": "64", "state": "differs"}])
assert adapter.read(dock).drift is True

# read: uncommitted change
status([{**entry, "value": 44}])
v = adapter.read(dock)
assert (v.value, v.source, v.seed) == ("44", Source.OVERRIDE, "38")

# read: a key absent at HEAD is an override with no seed, and the domain match ignores case
status([{**entry, "domain": "COM.APPLE.DOCK", "key": "mineffect", "value": "suck"}])
v = adapter.read(setting(key="com.apple.dock/mineffect", type="enum", choices=("suck",)))
assert (v.value, v.source, v.seed) == ("suck", Source.OVERRIDE, None)

# Review Focus 4: no git HEAD
head(None); status([entry])
v = adapter.read(dock)
assert (v.source, v.seed) == (Source.SEED, None)
raises(SettingsError, lambda: adapter.reset(dock), contains="not in git HEAD")

# Review Focus 5: empty status
mise.run_mise = lambda args, stdin=None: "{}"
v = adapter.read(dock)
assert (v.value, v.source, v.drift) == (None, Source.UNSET, False)
assert adapter.read(replace(dock, default="38")).source is Source.DEFAULT

# a path entry or a current-host entry never matches a table key
status([{**entry, "path": ["x"]}, {**entry, "host": "current"}])
assert adapter.read(dock).source is Source.UNSET

# write: edits the file, writes that one key, restarts the Dock, and never applies the fragment
status([{**entry, "value": 44, "current": "44"}]); head(FRAGMENT)
adapter.write(dock, "44")
assert "tilesize = 44 # trailing why" in fragment_path().read_text()
assert written == [("com.apple.dock", "tilesize", "-int", "44")] and killed == ["Dock"]
assert not any("apply" in c for c in calls)

# write: a bool goes off through the CLI's value, and an enum is a string
hide = setting(id="macos.dock.autohide", key="com.apple.dock/autohide", type="bool", true_value="true")
status([{**entry, "key": "autohide", "value": False, "current": "false"}])
adapter.write(hide, cli.normalize(hide, "off"))
assert "autohide = false" in fragment_path().read_text()
assert written == [("com.apple.dock", "autohide", "-bool", "false")]
assert adapter.read(hide).value == ""
effect = setting(id="macos.dock.mineffect", key="com.apple.dock/mineffect", type="enum", choices=("genie", "scale", "suck"))
status([{**entry, "key": "mineffect", "value": "scale", "current": "scale"}])
adapter.write(effect, "scale")
assert written == [("com.apple.dock", "mineffect", "-string", "scale")]

# write: the preference did not take the value
status([{**entry, "value": 50, "current": "38", "state": "differs"}])
raises(SettingsError, lambda: adapter.write(dock, "50"), contains="did not take")

# Review Focus 1: config.local.toml outranks the fragment, no preference is written and the fragment is put back
before = fragment_path().read_text()
status([{**entry, "value": 99}])
raises(SettingsError, lambda: adapter.write(dock, "51"), contains="config.local.toml")
assert written == [] and killed == [] and fragment_path().read_text() == before

# No whole-fragment path: set-defaults owns that, with mise's prompt and the extras script
assert not hasattr(adapter, "apply")

# reset returns to the committed value
fragment_path().write_text(FRAGMENT.replace("tilesize = 38", "tilesize = 44"))
status([entry]); head(FRAGMENT)
adapter.reset(dock)
assert "tilesize = 38 # trailing why" in fragment_path().read_text()
assert written == [("com.apple.dock", "tilesize", "-int", "38")] and not any("apply" in c for c in calls)

# reset of a key HEAD does not declare removes the line and writes no preference
fragment_path().write_text(FRAGMENT.replace("autohide = true", "autohide = true\nshowhidden = true"))
status([{**entry, "key": "showhidden", "value": True, "current": "true"}])
with contextlib.redirect_stderr(io.StringIO()) as err:
    adapter.reset(setting(key="com.apple.dock/showhidden", type="bool", true_value="true"))
assert fragment_path().read_text() == FRAGMENT and written == []
assert 'Run: defaults delete com.apple.dock "showhidden"' in err.getvalue()

# A clone whose override file declares a preference (it arrived by sync from an installed copy) changes it there
override = conf / "config.override.toml"
fragment_path().write_text(FRAGMENT)
override.write_text('[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = 44\n')
status([{**entry, "value": 50, "current": "50"}])
adapter.write(dock, "50")
assert fragment_path().read_text() == FRAGMENT
assert tomllib.loads(override.read_text())["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.dock"] == {"tilesize": 50}
assert written == [("com.apple.dock", "tilesize", "-int", "50")] and str(override) in adapter.write_note(dock)
status([entry])
adapter.reset(dock)
assert fragment_path().read_text() == FRAGMENT and "tilesize" not in override.read_text()
assert written == [("com.apple.dock", "tilesize", "-int", "38")]
override.unlink()

assert ADAPTERS["macos-default"].__class__ is MacosDefaultAdapter and "macos-default" in registry.KINDS

# every macos-default registry entry is declared in the real fragment with a matching type
repo = Path(__file__).resolve().parents[2]
declared = tomllib.loads((repo / "tilde/.config/mise/conf.d/20-macos.toml").read_text())["bootstrap"]["settings"]["macos"]["defaults"]
settings = registry.load()
macos = [s for s in settings if s.kind == "macos-default"]
assert len(macos) == 26
for s in macos:
    domain, key = split_key(s.key)
    value = declared[domain][key]
    assert type(value) is {"bool": bool, "int": int, "string": str, "enum": str}[s.type], s.id
    assert s.type != "enum" or value in s.choices, s.id
    assert s.section == "macOS (tracked in git)" and s.access == "rw", s.id
    assert s.type != "bool" or s.true_value == "true", s.id

# every variable the extras script reads is a setting in "macOS (this Mac)", and the reverse
extras = (repo / "setup/macos-extras.sh").read_text()
local = {s.key: s for s in settings if s.section == "macOS (this Mac)"}
assert set(local) == set(re.findall(r"DOTFILES_MACOS_[A-Z_]+", extras)), sorted(local)
on_by_default = {"DOTFILES_MACOS_SCREENSHOTS", "DOTFILES_MACOS_TIME_MACHINE_NEW_DISKS", "DOTFILES_MACOS_TEXTEDIT",
                 "DOTFILES_MACOS_SOFTWARE_UPDATE", "DOTFILES_MACOS_FIREWALL", "DOTFILES_MACOS_DISABLE_TIME_MACHINE"}
for key, s in local.items():
    assert s.kind == "env" and s.access == "rw", key
    assert s.type == "string" or s.true_value == "1", key
    # on unless switched off: the script's ${VAR-1} and the registry default must agree
    assert (s.default == "1") == (key in on_by_default), key
    assert (f"${{{key}-1}}" in extras) == (key in on_by_default), key
assert "${DOTFILES_MACOS_HIDPI:-}" in extras

# An installed copy: the fragment sits inside mise's checkout, so write and reset edit the user's override file instead
os.environ["MISE_DATA_DIR"] = str(tmp / "data")
(tmp / "data").mkdir()
(tmp / "data" / "bootstrap-repo").symlink_to(conf)
fragment_path().write_text(FRAGMENT)
user = tmp / "rotm"
user.mkdir()
override.symlink_to(user / "config.override.toml")  # as rotm-user-layer links it
override.write_text('[env]\nEDITOR = "vim"\n')
status([{**entry, "value": 44, "current": "44"}])
adapter.write(dock, "44")
assert fragment_path().read_text() == FRAGMENT
data = tomllib.loads(override.read_text())
assert data["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.dock"] == {"tilesize": 44} and data["env"] == {"EDITOR": "vim"}
assert written == [("com.apple.dock", "tilesize", "-int", "44")] and killed == ["Dock"]
assert str(override) in adapter.write_note(dock) and "20-macos.toml" not in adapter.write_note(dock)
status([{**entry, "key": "autohide", "value": False, "current": "false"}])
adapter.write(hide, cli.normalize(hide, "off"))
assert tomllib.loads(override.read_text())["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.dock"] == {"tilesize": 44, "autohide": False}
status([{**entry, "value": 44, "current": "44"}])
v = adapter.read(dock)
assert (v.value, v.source, v.seed) == ("44", Source.OVERRIDE, "38")
status([entry])
adapter.reset(dock)
assert fragment_path().read_text() == FRAGMENT
data = tomllib.loads(override.read_text())
assert data["bootstrap"]["settings"]["macos"]["defaults"]["com.apple.dock"] == {"autohide": False} and data["env"] == {"EDITOR": "vim"}
assert written == [("com.apple.dock", "tilesize", "-int", "38")]
# a reset with nothing to remove writes no file
(user / "config.override.toml").unlink()
status([entry])
adapter.reset(dock)
assert not (user / "config.override.toml").exists() and override.is_symlink()
# the folder behind the link is gone: a one-line error, no traceback
shutil.rmtree(user)
try:
    adapter.write(dock, "44")
    raise AssertionError("no error")
except SettingsError as e:
    assert str(user) in str(e) and "\n" not in str(e), str(e)

# A profile on an installed copy: write, read and reset use its override file, linked like the shared one
DOCK = '[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = {}\n'
user.mkdir()
override.write_text("")
work = profile.override_path("work")
(user / work.name).touch()
work.symlink_to(user / work.name)
profile.miserc().write_text('env = ["rotm-installed", "rotm-p-work"]\n')
status([{**entry, "value": 44, "current": "44"}])
adapter.write(dock, "44")
assert tomllib.loads(work.read_text()) == tomllib.loads(DOCK.format(44)) and work.is_symlink(), work.read_text()
assert override.read_text() == "" and fragment_path().read_text() == FRAGMENT
assert written == [("com.apple.dock", "tilesize", "-int", "44")]
assert adapter.read(dock).source is Source.OVERRIDE and "the profile work's settings" in adapter.write_note(dock)
# reset removes it from the profile only and writes the shared file's value, not the fragment's
override.write_text(DOCK.format(64))
status([entry])
adapter.reset(dock)
assert "tilesize" not in work.read_text() and override.read_text() == DOCK.format(64)
assert written == [("com.apple.dock", "tilesize", "-int", "64")], written
# --shared on a key the profile sets: the shared file changes and nothing is written to the Mac
work.write_text(DOCK.format(44))
profile.shared = True
status([{**entry, "value": 44, "current": "44"}])
adapter.write(dock, "50")
assert override.read_text() == DOCK.format(50) and work.read_text() == DOCK.format(44) and written == []
note = adapter.write_note(dock)
assert "The profile work keeps its own value" in note and f"rotm settings reset {dock.id}" in note, note
profile.shared = False
# a clone with a profile active writes the profile's file too, not the tracked fragment
os.environ["MISE_DATA_DIR"] = str(tmp / "nodata")
work.write_text("")
override.write_text("")
status([{**entry, "value": 44, "current": "44"}])
adapter.write(dock, "44")
assert fragment_path().read_text() == FRAGMENT and "tilesize = 44" in work.read_text()
# a saved profile with no file refuses, and the folder behind the link gone is the same one-line error
profile.miserc().write_text('env = ["rotm-p-gone"]\n')
raises(SettingsError, lambda: adapter.write(dock, "44"), contains="the profile gone has no settings file")
profile.miserc().write_text('env = ["rotm-p-work"]\n')
shutil.rmtree(user)
try:
    adapter.write(dock, "44")
    raise AssertionError("no error")
except SettingsError as e:
    assert str(user) in str(e) and "\n" not in str(e), str(e)
profile.miserc().unlink()
print("ok")
