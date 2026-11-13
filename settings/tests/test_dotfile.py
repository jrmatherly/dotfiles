"""Checks the dotfile adapter against a stub mise. Run: python3 test_dotfile.py"""
import json, os, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import registry
from dotfiles_settings.adapters import ADAPTERS, dotfile
from dotfiles_settings.adapters.dotfile import DotfileAdapter
from dotfiles_settings.model import Setting, SettingsError, Source

stub = Path(tempfile.mkdtemp())
(stub / "mise").write_text("""#!/bin/bash
echo "$*" >> "$STUB/log"
case "$1 $2" in
  "dotfiles status") cat "$STUB/status.json" ;;
  "dotfiles apply") cat "$STUB/apply.err" >&2; exit "$(cat "$STUB/apply.code")" ;;
  *) echo "2026.11.8 macos-arm64 (2026-11-13)" ;;
esac
""")
(stub / "mise").chmod(0o755)
os.environ["STUB"] = str(stub)
os.environ["DOTFILES_SETTINGS_MISE"] = str(stub / "mise")


def put(files, edits=()):
    (stub / "status.json").write_text(json.dumps({"files": list(files), "edits": list(edits), "history": {}}))


def set_apply(code, err):
    (stub / "apply.code").write_text(str(code))
    (stub / "apply.err").write_text(err)


S = Setting(id="dotfiles.links", section="Dotfiles", label="", help="", kind="dotfile", key="all", type="string",
            access="ro")
A = DotfileAdapter()

ok = {"target": "~/.zshrc", "mode": "symlink", "state": "applied"}
real = {"target": "~/.config/gh", "mode": "symlink", "state": "differs", "reason": "exists but is not a symlink"}
gone = {"target": "~/.ackrc", "mode": "symlink", "state": "missing"}
edit = {"path": "~/.zshrc", "edit": "block:aliases", "state": "missing"}

put([ok, ok])
v = A.read(S)
assert (v.value, v.source, v.seed, v.drift) == ("2 of 2 applied", Source.SEED, None, False)

put([ok, real, gone], [edit])
v = A.read(S)
assert v.drift is True
assert v.value == ("1 of 4 applied; ~/.config/gh: differs (exists but is not a symlink); "
                   "~/.ackrc: missing; ~/.zshrc (block:aliases): missing")

put([{"target": "~/.x", "mode": "track", "state": "tracked"}])
assert A.read(S).drift is False

(stub / "status.json").write_text("not json")
v = A.read(S)
assert v.value.startswith("status failed: ") and v.source is Source.UNSET and v.drift is True, "bad JSON is a value"
(stub / "status.json").unlink()
v = A.read(S)
assert v.value.startswith("status failed: ") and v.drift is True, "a failed status call is a value"

ERR = ("mise ERROR files: refusing to overwrite existing files (use --force):\n"
       "  ~/.zshrc\n  ~/.config/gh\n"
       "mise ERROR Version: 2026.11.8 macos-arm64 (2026-11-13)\n"
       "mise ERROR Run with --verbose or MISE_VERBOSE=1 for more information\n")
assert dotfile.conflicts(ERR) == ["~/.zshrc", "~/.config/gh"]
assert dotfile.conflicts("mise ERROR files: sources do not exist:\n  x\n") == []

set_apply(1, ERR)
try:
    A.apply([S]); raise AssertionError("a conflict did not raise")
except SettingsError as e:
    assert "2 path(s) in the way, nothing was changed: ~/.zshrc, ~/.config/gh." in str(e)
    assert "mise dotfiles add" in str(e) and "--force" not in str(e)

set_apply(1, "mise ERROR files: sources do not exist:\n  [dotfiles].\"~/.zshrc\": ~/dotfiles/tilde/.zshrc\n"
             "mise ERROR Version: 2026.11.8 macos-arm64 (2026-11-13)\n")
try:
    A.apply([S]); raise AssertionError("a missing source did not raise")
except SettingsError as e:
    assert "sources do not exist" in str(e) and "~/dotfiles/tilde/.zshrc" in str(e) and "Version" not in str(e)

set_apply(1, "mise ERROR edits: cannot apply these entries, fix them manually:\n"
             "  \"~/.codex/config.toml\" (merge:defaults): failed to parse the TOML target: TOML parse error at line 1, column 9\n"
             "mise ERROR Version: 2026.11.8 macos-arm64 (2026-11-13)\n")
try:
    A.apply([S]); raise AssertionError("an invalid merge target did not raise")
except SettingsError as e:
    assert "~/.codex/config.toml" in str(e) and "failed to parse" in str(e)

set_apply(0, "mise files: created symlink ~/.ackrc -> ~/dotfiles/tilde/.ackrc\nmise files: applied ~/.ackrc\n")
assert A.apply([S]) == ["files: created symlink ~/.ackrc -> ~/dotfiles/tilde/.ackrc", "files: applied ~/.ackrc"]

calls = [l for l in (stub / "log").read_text().splitlines() if l.startswith("dotfiles apply")]
assert calls and all(c == "dotfiles apply --yes" for c in calls), "apply never passes --force or -f"
assert not {"--force", "-f"} & set(dotfile.APPLY)

for call in (lambda: A.write(S, "x"), lambda: A.reset(S)):
    try:
        call(); raise AssertionError("write or reset did not raise")
    except SettingsError as e:
        assert "40-dotfiles.toml" in str(e)

assert ADAPTERS["dotfile"].__class__ is DotfileAdapter and "dotfile" in registry.KINDS
links = [s for s in registry.load() if s.kind == "dotfile"]
assert [(s.id, s.access, s.type) for s in links] == [("dotfiles.links", "ro", "string")]
print("ok")
