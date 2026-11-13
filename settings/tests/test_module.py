"""Checks the module adapter against a stubbed rotm-modules. Run: python3 test_module.py"""
import atexit, os, shutil, stat, sys, tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
repo = Path(__file__).resolve().parents[2]
# The stub sits inside a fetched copy's checkout, so a write that refused installed copies would fail here
data = tmp / "data"
dotfiles = data / "bootstrap-repo"
helper = dotfiles / "bin/lib/rotm-modules"
helper.parent.mkdir(parents=True)
off, log = tmp / "off", tmp / "calls"
helper.write_text(f"""#!/bin/bash
echo "$*${{ROTM_SHARED:+ shared}}" >> {log}
[ -z "${{STUB_FAIL:-}}" ] || {{ echo "rotm-modules: $STUB_FAIL" >&2; exit 2; }}
touch {off}
case $1 in
  off) cat {off} ;;
  set) grep -vxF "$2" {off} > {off}.new || true; mv {off}.new {off}; [ "$3" = on ] || echo "$2" >> {off} ;;
esac
""")
helper.chmod(helper.stat().st_mode | stat.S_IXUSR)
os.environ.update(DOTFILES=str(dotfiles), MISE_DATA_DIR=str(data))

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import registry
from dotfiles_settings.adapters import ADAPTERS
from dotfiles_settings.model import InvalidValue, SettingsError, Source, note_for

A = ADAPTERS["module"]
assert "module" in registry.KINDS
rows = [s for s in registry.load(repo / "settings/registry.toml") if s.kind == "module"]
by_key = {s.key: s for s in rows}
s = by_key["security"]


def calls():
    return [line.split() for line in log.read_text().splitlines()] if log.exists() else []


v = A.read(s)
assert (v.value, v.source, v.seed, v.drift) == ("on", Source.SEED, "on", False), v
A.write(s, "")
assert calls()[-1] == ["set", "security", "off"]
v = A.read(s)
assert (v.value, v.source) == ("", Source.OVERRIDE), v
assert A.read(by_key["fonts"]).value == "on", "one module off leaves the others on"
try:
    A.write(s, "maybe"); raise AssertionError("maybe was accepted")
except InvalidValue:
    pass
A.write(s, "on")
assert calls()[-1] == ["set", "security", "on"]
A.write(s, "")
A.reset(s)
assert calls()[-1] == ["set", "security", "on"] and A.read(s).value == "on"

# --shared reaches the helper, which then changes the shared list while a profile is active
from dotfiles_settings import profile
profile.shared = True
A.write(s, "")
assert calls()[-1] == ["set", "security", "off", "shared"]
profile.shared = False
A.write(s, "on")
assert calls()[-1] == ["set", "security", "on"]

note = note_for(A, s)
for words in ("no package is uninstalled", "mise bootstrap packages prune --dry-run", "sysup removes its mise tools"):
    assert words in note, words

os.environ["STUB_FAIL"] = "no mise config dir at /x"
try:
    A.write(s, ""); raise AssertionError("a helper failure passed")
except SettingsError as e:
    assert str(e) == "rotm-modules: no mise config dir at /x", e
v = A.read(s)
assert (v.value, v.source) == (None, Source.UNSET), "a failed read is unset, so one bad row does not stop list"
del os.environ["STUB_FAIL"]

del os.environ["DOTFILES"]
try:
    A.write(s, ""); raise AssertionError("no DOTFILES passed")
except SettingsError as e:
    assert str(e) == "DOTFILES is not set"
os.environ["DOTFILES"] = str(dotfiles)

assert all((r.section, r.type, r.true_value, r.default, r.access, r.id) == ("Modules", "bool", "on", "on", "rw", f"modules.{r.key}")
           for r in rows), rows
assert all(r.help for r in rows)
print("ok")
