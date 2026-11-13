"""Checks tilde/.config/mise/conf.d/20-macos.toml: it parses clean under mise and no
declared type contradicts the live one. Drift only warns. Run: python3 setup/tests/macos-defaults.py"""
import json, os, shutil, subprocess, sys, tempfile, tomllib
from pathlib import Path

FRAGMENT = Path(__file__).resolve().parents[2] / "tilde/.config/mise/conf.d/20-macos.toml"
# bool before int: bool is a subclass of int
TYPES = [(bool, "boolean"), (int, "integer"), (float, "float"), (str, "string"), (list, "array"), (dict, "dictionary")]


def type_name(t):
    return next(name for base, name in TYPES if issubclass(t, base))


def parse(path):
    return tomllib.loads(path.read_text())["bootstrap"]["settings"]["macos"]


def fragment_types(path) -> dict[tuple[str, str], type]:
    return {(domain, key): type(value)
            for domain, table in parse(path)["defaults"].items() for key, value in table.items()}


def check_security_opt_ins_untracked(macos):
    for domain in ("com.apple.LaunchServices", "com.apple.frameworks.diskimages"):
        assert domain not in macos["defaults"], f"{domain} belongs in config.local.toml, not the fragment"


def mise_status():
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "conf.d").mkdir()
        shutil.copy(FRAGMENT, Path(tmp) / "conf.d" / FRAGMENT.name)
        r = subprocess.run(["mise", "bootstrap", "macos", "defaults", "status", "--json"], cwd=tmp,
                           env={**os.environ, "MISE_CONFIG_DIR": tmp}, capture_output=True, text=True)
    assert r.returncode == 0, f"mise status exited {r.returncode}: {r.stderr}"
    assert "WARN" not in r.stderr, f"mise warned on the fragment: {r.stderr}"
    return json.loads(r.stdout).get("macos_defaults", {}).get("entries", [])


def check_entry_count(macos, entries):
    declared = sum(len(t) for t in macos["defaults"].values()) + len(macos.get("defaults_entries", []))
    assert len(entries) == declared, f"mise lists {len(entries)} entries, the fragment declares {declared}"


def check_live_types(macos, entries):
    declared = {(d, k, "any"): t for (d, k), t in fragment_types(FRAGMENT).items()}
    declared |= {(e["domain"], e["key"], e.get("host", "any")): type(e["value"])
                 for e in macos.get("defaults_entries", []) if "path" not in e}
    for e in entries:
        if e["state"] != "differs" or e["path"] is not None:
            continue
        host = ["-currentHost"] if e["host"] == "current" else []
        live = subprocess.run(["defaults", *host, "read-type", e["domain"], e["key"]],
                              capture_output=True, text=True, check=True).stdout.split()[-1]
        want = type_name(declared[(e["domain"], e["key"], e["host"])])
        assert live == want, f"{e['domain']} {e['key']}: declared {want}, live {live}"


def warn_drift(entries):
    drift = sum(e["state"] in ("differs", "unset") for e in entries)
    if drift:
        print(f"check: {drift} macOS preference(s) differ from 20-macos.toml "
              "(mise bootstrap macos defaults status)", file=sys.stderr)


def main():
    macos = parse(FRAGMENT)
    check_security_opt_ins_untracked(macos)
    if shutil.which("mise"):
        entries = mise_status()
        check_entry_count(macos, entries)
        # A CI runner has none of these preferences applied, so there is nothing to compare
        if not os.environ.get("CI"):
            check_live_types(macos, entries)
            warn_drift(entries)
    print("ok")


main()
