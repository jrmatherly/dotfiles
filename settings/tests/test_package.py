"""Checks the package adapter against a stubbed mise. Run: python3 test_package.py"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import mise, registry
from dotfiles_settings.adapters import ADAPTERS
from dotfiles_settings.adapters.package import PackageAdapter, summarize
from dotfiles_settings.model import Setting, SettingsError, Source


def setting(id: str, key: str) -> Setting:
    return Setting(id=id, section="Packages", label=id, help="", kind="package", key=key, type="string", access="ro")


STATUS = {"brew": {"available": True, "packages": [
    {"package": "ack", "state": "installed", "installed_version": "3.10.0"},
    {"package": "rustup", "state": "needs_repair", "installed_version": "1.29.3"}]},
  "brew-cask": {"available": True, "packages": [
    {"package": "utm", "state": "installed", "installed_version": "5.0.8", "managed_by": "homebrew"},
    {"package": "codex", "state": "missing", "installed_version": ""}]}}
calls = []
def fake(args, stdin=None):
    calls.append(args)
    if args[:3] == ["bootstrap", "packages", "status"]: return json.dumps(STATUS)
    if args[0] == "ls": return json.dumps({"node": [{"version": "24.1.0", "requested_version": "24", "installed": True}],
                                           "hunk": [{"version": "0.24.1", "requested_version": "latest", "installed": False}]})
    return ""
mise.run_mise = fake
a = PackageAdapter()
assert summarize(STATUS["brew"]["packages"]) == ("1 installed, 1 not: rustup (needs_repair)", True)
assert summarize([{"package": "x", "state": "installed"}] * 3) == ("3 installed", False)
many = [{"package": f"p{i}", "state": "missing"} for i in range(12)]
assert summarize(many) == ("0 installed, 12 not: " + ", ".join(f"p{i} (missing)" for i in range(10)) + ", and 2 more", True)
v = a.read(setting("packages.casks", "brew-cask"))
assert v.value == "1 installed, 1 not: codex (missing); 1 still managed by Homebrew" and v.drift is True and v.source is Source.SEED
assert v.seed == v.value
v = a.read(setting("packages.vscode", "vscode"))
assert v.value == "not available" and v.source is Source.UNSET and v.drift is False
assert sum(c[:3] == ["bootstrap", "packages", "status"] for c in calls) == 1, "status is read once for several entries"
v = a.read(setting("packages.tools", "tools"))
assert v.value == "1 installed, 1 not: hunk@latest" and v.drift is True
calls.clear()
assert a.apply([setting("packages.casks", "brew-cask"), setting("packages.formulae", "brew")]) == ["brew: applied", "brew-cask: applied"]
assert calls == [["bootstrap", "packages", "apply", "--yes", "--manager", "brew"],
                 ["bootstrap", "packages", "apply", "--yes", "--manager", "brew-cask"]]
calls.clear()
assert a.apply([setting("packages.tools", "tools")]) == ["tools: applied"] and calls == [["install", "--yes"]]
for op in (lambda: a.write(setting("packages.formulae", "brew"), "x"), lambda: a.reset(setting("packages.formulae", "brew"))):
    try: op(); raise AssertionError("read-only")
    except SettingsError: pass
assert ADAPTERS["package"].__class__ is PackageAdapter and "package" in registry.KINDS
def broken(args, stdin=None): raise SettingsError("mise ERROR x\ncode --list-extensions exited 1")
mise.run_mise = broken
b = PackageAdapter()
v = b.read(setting("packages.formulae", "brew"))
assert v.value == "status failed: code --list-extensions exited 1" and v.source is Source.UNSET and v.drift is True
mise.run_mise = fake
assert b.read(setting("packages.casks", "brew-cask")).value.startswith("status failed: "), "the failure is cached too"
mise.run_mise = broken
try: PackageAdapter().apply([setting("packages.formulae", "brew")]); raise AssertionError("apply raises on a mise failure")
except SettingsError as e: assert str(e) == "code --list-extensions exited 1"

by_id = {s.id: s for s in registry.load()}
for id, key in (("packages.formulae", "brew"), ("packages.casks", "brew-cask"), ("packages.vscode", "vscode"),
                ("packages.tools", "tools")):
    s = by_id[id]
    assert (s.kind, s.access, s.key, s.section, s.type) == ("package", "ro", key, "Packages", "string"), id
print("ok")
