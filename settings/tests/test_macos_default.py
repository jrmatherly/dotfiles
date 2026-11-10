"""Checks the macos-default adapter against a temp fragment, a stubbed mise and stubbed defaults. Run: python3 test_macos_default.py"""
import atexit, contextlib, io, json, os, shutil, sys, tempfile, tomllib
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
from dotfiles_settings import cli, mise, registry
from dotfiles_settings.adapters import ADAPTERS, macos_default
from dotfiles_settings.adapters.macos_default import (MacosDefaultAdapter, fragment_path, remove_key, set_key,
                                                      to_literal)
from dotfiles_settings.model import InvalidValue, Setting, SettingsError, Source

FRAGMENT = '''# header comment
[bootstrap.macos.defaults.NSGlobalDomain]
# key repeat why
KeyRepeat = 1
"com.apple.springing.enabled" = true

[bootstrap.macos.defaults."com.apple.dock"]
# size why
tilesize = 38 # trailing why
autohide = true
FXInfo = { General = true }

[[bootstrap.macos.defaults_entries]]
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

# a new key lands in its table, a new table lands at the end
out = set_key(FRAGMENT, "com.apple.dock", "show-recents", "false")
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.dock"]["show-recents"] is False
assert out.index("show-recents") < out.index("[[bootstrap.macos.defaults_entries]]")
out = set_key(FRAGMENT, "com.apple.screencapture", "name", '"Shot"')
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.screencapture"] == {"name": "Shot"}

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
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.screencapture"]["name"] == nasty
# and again when it replaces a value that already has a trailing comment
out = set_key(out.replace(to_literal(s, nasty), to_literal(s, nasty) + " # why"), "com.apple.screencapture", "name", to_literal(s, "a # b"))
assert tomllib.loads(out)["bootstrap"]["macos"]["defaults"]["com.apple.screencapture"]["name"] == "a # b" and out.endswith('"a # b" # why\n')

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

# apply is the only whole-fragment path
status([entry])
assert adapter.apply([dock]) == ["macOS preferences applied"]
assert ["bootstrap", "macos", "defaults", "apply", "--yes"] in calls

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

assert ADAPTERS["macos-default"].__class__ is MacosDefaultAdapter and "macos-default" in registry.KINDS
print("ok")
