"""Checks the CLI contract (subcommands, JSON, exit codes) against an isolated mise config. Run: python3 test_cli.py"""
import atexit, contextlib, io, json, os, shutil, sys, tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp())
atexit.register(shutil.rmtree, tmp, True)
home, conf, cwd = (tmp / n for n in ("home", "conf", "cwd"))
for d in (home, conf, cwd):
    d.mkdir()
(tmp / "registry.toml").write_text('''
[[setting]]
id = "t.flag"
section = "One"
label = "Flag"
help = ""
kind = "env"
key = "T_FLAG"
type = "bool"
access = "rw"
true_value = "1"

[[setting]]
id = "t.count"
section = "One"
label = "Count"
help = ""
kind = "env"
key = "T_COUNT"
type = "int"
access = "rw"
default = "10"

[[setting]]
id = "t.pick"
section = "Two"
label = "Pick"
help = ""
kind = "env"
key = "T_PICK"
type = "enum"
access = "rw"
choices = ["a", "b"]

[[setting]]
id = "t.dir"
section = "Two"
label = "Dir"
help = ""
kind = "env"
key = "T_DIR"
type = "path"
access = "rw"

[[setting]]
id = "t.locked"
section = "Two"
label = "Locked"
help = ""
kind = "env"
key = "T_LOCKED"
type = "string"
access = "ro"
''')
os.environ.update(HOME=str(home), MISE_CONFIG_DIR=str(conf), VSCODE_SETTINGS_ENV=str(tmp / "vscode.env"),
                  DOTFILES_SETTINGS_REGISTRY=str(tmp / "registry.toml"))
os.environ.pop("DOTFILES_SETTINGS_MISE", None)
os.chdir(cwd)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import cli
from dotfiles_settings.adapters import env

env.seed_env = lambda keys: {"T_LOCKED": "1"}


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            cli.main(list(argv))
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


def fake(text):
    path = tmp / f"fake-mise-{abs(hash(text))}"
    path.write_text(f"#!/bin/sh\necho '{text}'\n")
    path.chmod(0o755)
    return str(path)


if shutil.which("mise"):
    code, out, _ = run("list", "--json")
    rows = json.loads(out)
    assert code == 0 and [r["setting_id"] for r in rows] == ["t.flag", "t.count", "t.pick", "t.dir", "t.locked"]
    assert set(rows[0]) == {"setting_id", "value", "source", "seed", "drift", "label", "section", "type",
                            "choices", "widget", "access"}
    assert rows[2]["choices"] == ["a", "b"] and rows[0]["choices"] == [] and rows[0]["widget"] == ""
    assert rows[1]["value"] == "10" and rows[1]["source"] == "default"
    assert rows[0]["value"] is None and rows[0]["source"] == "unset"

    assert run("set", "t.flag", "on")[0] == 0
    assert json.loads(run("get", "t.flag", "--json")[1]) == {
        "setting_id": "t.flag", "value": "1", "source": "override", "seed": None, "drift": False,
        "label": "Flag", "section": "One", "type": "bool", "choices": [], "widget": "", "access": "rw"}
    assert run("set", "t.flag", "off")[0] == 0 and run("get", "t.flag")[1] == "\n"
    code, _, err = run("reset", "t.flag")
    assert code == 0 and "Open a new shell" in err
    assert json.loads(run("get", "t.flag", "--json")[1])["source"] == "unset"

    assert run("set", "t.count", "007")[0] == 0 and run("get", "t.count")[1] == "7\n"
    assert run("set", "t.dir", "~/x")[0] == 0 and run("get", "t.dir")[1] == str(Path.home() / "x") + "\n"
    assert len(json.loads(run("list", "--section", "one", "--json")[1])) == 2

    for argv, code in ((("get", "nope"), 2), (("set", "nope", "1"), 2), (("reset", "nope"), 2),
                       (("set", "t.flag", "maybe"), 2), (("set", "t.count", "ten"), 2),
                       (("set", "t.pick", "c"), 2), (("set", "t.dir", "relative/x"), 2),
                       (("set", "t.pick", "{{ a }}"), 2), (("list", "--section", "nope"), 2),
                       (("apply", "nope"), 2), (("set", "t.locked", "0"), 3), (("reset", "t.locked"), 3)):
        got, _, err = run(*argv)
        assert got == code and err.startswith("dotfiles-settings: ") and "Traceback" not in err, (argv, got, err)
    assert "T_LOCKED" not in env.read_override()
    assert run("apply", "env") == (0, "env: nothing to apply\n", "")

    # invalid TOML in the override file
    env.override_path().write_text("[env]\nbroken = [\n")
    code, _, err = run("list", "--json")
    assert code == 1 and "config.override.toml" in err and "Traceback" not in err
    env.override_path().unlink()
else:
    print("skipped: mise not found")

# mise older than the floor, then missing: every subcommand exits 1 with one line
for fake_mise, needle in ((fake("2026.11.4"), "found 2026.11.4"), (str(tmp / "absent"), "not on PATH")):
    os.environ["DOTFILES_SETTINGS_MISE"] = fake_mise
    for argv in (("list",), ("get", "t.flag"), ("set", "t.flag", "on"), ("tui",), ("serve", "--no-open")):
        code, out, err = run(*argv)
        assert (code, out) == (1, "") and needle in err and err.count("\n") == 1, (argv, err)

assert run("sync")[0] == 2
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.11.8 no setup repository is connected")
code, out, _ = run("sync", "status")
assert code == 0 and "not connected" in out, (code, out)

# profile: the three actions reach profile.py, a refused or unknown name exits 2, and --shared sets profile.shared
from dotfiles_settings import profile
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.11.8 macos-arm64")
helper = tmp / "dotfiles/bin/lib/rotm-user-layer"  # profile use links a profile's files before it looks for one
helper.parent.mkdir(parents=True)
helper.write_text("#!/bin/sh\n")
helper.chmod(0o755)
os.environ["DOTFILES"] = str(tmp / "dotfiles")
profile.listing = lambda: ["* default", "  work"]
assert run("profile", "list") == (0, "* default\n  work\n", "")
code, out, err = run("profile", "use", "nope")
assert (code, out) == (2, "") and "no profile named nope" in err, (code, err)
code, out, err = run("profile", "new", "Work")
assert (code, out) == (2, "") and "profile name" in err, (code, err)
code, _, err = run("profile")
assert code == 2 and "usage:" in err, (code, err)
seen = []
real_use, profile.use = profile.use, lambda name: seen.append(name) or [f"Now using {name}."]
assert run("profile", "use", "work") == (0, "Now using work.\n", "") and seen == ["work"]
profile.use = real_use


class Spy:
    write_note = ""

    def write(self, s, value):
        seen.append(("set", profile.shared))

    def reset(self, s):
        seen.append(("reset", profile.shared))


cli.ADAPTERS["env"], seen = Spy(), []
for argv in (("set", "--shared", "t.flag", "on"), ("set", "t.flag", "on"), ("reset", "--shared", "t.flag"),
             ("reset", "t.flag")):
    assert run(*argv)[0] == 0, argv
assert seen == [("set", True), ("set", False), ("reset", True), ("reset", False)], seen
print("ok")
