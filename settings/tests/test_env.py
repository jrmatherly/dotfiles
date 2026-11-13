"""Checks the mise helper and the env adapter against an isolated mise config. Run: python3 test_env.py"""
import atexit, json, os, shutil, sys, tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp())
atexit.register(shutil.rmtree, tmp, True)
home, conf, cwd, zdot = (tmp / n for n in ("home", "conf", "cwd", "zdot"))
for d in (home, conf, cwd, zdot):
    d.mkdir()
os.environ.update(HOME=str(home), MISE_CONFIG_DIR=str(conf), VSCODE_SETTINGS_ENV=str(tmp / "vscode.env"))
os.environ.pop("DOTFILES_SETTINGS_MISE", None)
(cwd / "mise.toml").write_text('[env]\nT_PROJECT = "x"\n')  # never trusted
os.chdir(cwd)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import mise, profile
from dotfiles_settings.adapters import ADAPTERS, env
from dotfiles_settings.model import InvalidValue, Setting, SettingsError, Source, Value, note_for

seed_env_real = env.seed_env
assert isinstance(ADAPTERS["env"], env.EnvAdapter)


def S(key, type="string", default="", true_value="", scope="user"):
    return Setting(id=key.lower(), section="T", label=key, help="", kind="env", key=key, type=type,
                   access="rw", default=default, true_value=true_value, scope=scope)


def raises(fn, cls, needle):
    try:
        fn()
    except cls as e:
        assert needle in str(e), (needle, str(e))
        return
    raise AssertionError(f"expected {cls.__name__}: {needle}")


def fake(text):
    path = tmp / f"fake-mise-{abs(hash(text))}"
    path.write_text(f"#!/bin/sh\necho '{text}'\n")
    path.chmod(0o755)
    return str(path)


if shutil.which("mise"):
    env.seed_env = lambda keys: {"T_LOCAL": "from-zsh-local", "T_SEEDED": "seed"}
    a = env.EnvAdapter()
    assert a.read(S("T_NONE")) == Value("t_none", None, Source.UNSET, None, False)
    assert a.read(S("T_DEF", default="10")) == Value("t_def", "10", Source.DEFAULT, "10", False)
    assert a.read(S("T_SEEDED")).source is Source.SEED

    # run_mise runs from $HOME: the untrusted mise.toml in the cwd is never read.
    # Measured without cwd=Path.home(): `mise env --json` exits 1 here with "not trusted".
    assert "T_PROJECT" not in json.loads(mise.run_mise(["env", "--json"]))

    for raw in ("hello world", "a=b=c", "it's \"q\" \\ back", "`id` ; rm -rf / | #c", "--help -x", "café ☕", ""):
        a.write(S("T_VAL"), raw)
        assert a.read(S("T_VAL")).value == raw, raw
        assert json.loads(mise.run_mise(["env", "--json"]))["T_VAL"] == raw, raw

    for raw, needle in (("{{ x }}", "{{"), ("{% if %}", "{%"), ("{# c #}", "{#"), ("$HOME/x", "$"), ("a\nb", "line break")):
        raises(lambda: a.write(S("T_VAL"), raw), InvalidValue, needle)
    assert a.read(S("T_VAL")).value == ""

    # a switch that is on by default (A3): unset reads as on, off is stored as "" and the key stays, reset restores the default
    ON = S("T_ON", type="bool", default="1", true_value="1")
    assert a.read(ON) == Value("t_on", "1", Source.DEFAULT, "1", False)
    a.write(ON, "")
    assert a.read(ON) == Value("t_on", "", Source.OVERRIDE, "1", False) and env.read_override()["T_ON"] == ""
    a.reset(ON)
    assert a.read(ON).source is Source.DEFAULT and "T_ON" not in env.read_override()

    # a key ~/.zsh.local also exports: the override wins, the seed is what reset restores
    a.write(S("T_LOCAL"), "ui")
    assert a.read(S("T_LOCAL")) == Value("t_local", "ui", Source.OVERRIDE, "from-zsh-local", False)
    a.reset(S("T_LOCAL"))
    assert a.read(S("T_LOCAL")) == Value("t_local", "from-zsh-local", Source.SEED, "from-zsh-local", False)
    a.reset(S("T_LOCAL"))

    # the VS Code preset: the saved file is the seed when no shell exports the key
    P = S("VSCODE_FONT_PRESET", default="iosevka")
    assert a.read(P) == Value("vscode_font_preset", "iosevka", Source.DEFAULT, "iosevka", False)
    env.vscode_env_path().write_text("VSCODE_FONT_PRESET=warp\n")
    assert a.read(P) == Value("vscode_font_preset", "warp", Source.SEED, "warp", False)
    a.write(P, "fira")
    assert a.read(P) == Value("vscode_font_preset", "fira", Source.OVERRIDE, "warp", False)
    a.reset(P)
    assert a.read(P).value == "warp"
    env.vscode_env_path().write_text("VSCODE_FONT_PRESET='quoted'\n")
    assert env.file_seed("VSCODE_FONT_PRESET") == "quoted"
    assert env.file_seed("T_VAL") is None
    assert a.watch_paths() == [env.override_path(), env.local_path(), env.vscode_env_path(), profile.miserc()]

    # a machine setting lives in config.local.toml, which never syncs
    M = S("DOTFILES_MACOS_COMPUTER_NAME", scope="machine")
    local = str(mise.config_dir() / "config.local.toml")
    assert env.local_path() == Path(local)
    real, calls = mise.run_mise, []
    mise.run_mise = lambda args, stdin=None: calls.append(args) or real(args, stdin)
    a.write(M, "Studio")
    assert calls == [["set", "--file", local, "DOTFILES_MACOS_COMPUTER_NAME=Studio"]], calls
    assert a.read(M) == Value(M.id, "Studio", Source.OVERRIDE, None, False)
    assert "DOTFILES_MACOS_COMPUTER_NAME" not in env.read_override()
    calls.clear()
    a.reset(M)
    assert calls == [["unset", "--file", local, "DOTFILES_MACOS_COMPUTER_NAME"]], calls
    assert a.read(M).source is Source.UNSET
    # a value the override file kept from before scope existed is read, and the next write moves it
    real(["set", "--override", "DOTFILES_MACOS_COMPUTER_NAME=old"])
    assert a.read(M) == Value(M.id, "old", Source.OVERRIDE, None, False)
    calls.clear()
    a.write(M, "Studio")
    assert calls == [["set", "--file", local, "DOTFILES_MACOS_COMPUTER_NAME=Studio"],
                     ["unset", "--override", "DOTFILES_MACOS_COMPUTER_NAME"]], calls
    assert "DOTFILES_MACOS_COMPUTER_NAME" not in env.read_override() and a.read(M).value == "Studio"
    a.reset(M)
    mise.run_mise = real

    # a second writer between our write and our re-read is reported
    real = mise.run_mise

    def then_clobber(args, stdin=None):
        out = real(args, stdin)
        real(["set", "--override", "T_RACE=other"])
        return out

    mise.run_mise = then_clobber
    raises(lambda: a.write(S("T_RACE"), "mine"), SettingsError, "changed by another writer")
    mise.run_mise = real

    # invalid TOML: the error names the file
    env.override_path().write_text("[env]\nbroken = [\n")
    raises(lambda: a.read(S("T_VAL")), SettingsError, "config.override.toml")
    env.override_path().unlink()
    assert env.read_override() == {} and not env.override_path().exists()
    a.reset(S("T_VAL"))
    assert not env.override_path().exists()

    # a profile: its override file is a link into the user's folder, as rotm-user-layer ensure leaves it
    K, rc, work = S("T_PROF"), profile.miserc(), profile.override_path("work")
    (tmp / "rotm").mkdir()
    (tmp / "rotm" / work.name).touch()
    work.symlink_to(tmp / "rotm" / work.name)
    rc.write_text('env = ["rotm-p-work"]\n')
    real, calls = mise.run_mise, []
    mise.run_mise = lambda args, stdin=None: calls.append(args) or real(args, stdin)
    assert a.watch_paths()[-2:] == [rc, work]
    # a key the profile does not set comes from the shared file
    real(["set", "--override", "T_PROF=shared"])
    assert a.read(K).value == "shared"
    # a write goes to the profile's file, through its link, and is what mise then exports
    a.write(K, "x")
    assert calls == [["set", "--file", str(work), "T_PROF=x"]], calls
    assert a.read(K) == Value(K.id, "x", Source.OVERRIDE, None, False) and env.read_override() == {"T_PROF": "shared"}
    assert work.is_symlink() and json.loads(real(["env", "--json"]))["T_PROF"] == "x"
    assert note_for(a, K) == "Open a new shell to pick this up."
    # --shared writes the shared file, and the note says the profile still wins
    profile.shared = True
    calls.clear()
    a.write(K, "y")
    assert calls == [["set", "--override", "T_PROF=y"]], calls
    assert env.read_override() == {"T_PROF": "y"} and env.read_env(work) == {"T_PROF": "x"} and a.read(K).value == "x"
    assert "The profile work keeps its own value" in note_for(a, K) and "rotm settings reset t_prof" in note_for(a, K)
    profile.shared = False
    # reset removes the profile's value first, then the shared one
    calls.clear()
    a.reset(K)
    assert calls == [["unset", "--file", str(work), "T_PROF"]] and env.read_override() == {"T_PROF": "y"}, calls
    assert a.read(K).value == "y" and work.is_symlink()
    calls.clear()
    a.reset(K)
    assert calls == [["unset", "--override", "T_PROF"]] and a.read(K).source is Source.UNSET, calls
    # a machine setting ignores the profile
    calls.clear()
    a.write(M, "Studio")
    assert calls == [["set", "--file", local, "DOTFILES_MACOS_COMPUTER_NAME=Studio"]] and env.read_env(work) == {}, calls
    a.reset(M)
    # a saved profile whose file is not on this Mac: reads fall back, a write refuses
    rc.write_text('env = ["rotm-p-gone"]\n')
    real(["set", "--override", "T_PROF=shared"])
    assert a.read(K).value == "shared"
    raises(lambda: a.write(K, "z"), SettingsError, "the profile gone has no settings file on this Mac")
    assert not profile.override_path("gone").exists() and env.read_override() == {"T_PROF": "shared"}
    mise.run_mise = real
    rc.unlink()
    a.reset(K)
else:
    print("skipped: mise not found")

# version floor and a missing binary, through a fake mise script
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.11.7 macos-arm64 (2026-11-11)")
raises(mise.check_version, SettingsError, "needs mise 2026.11.8 or newer, found 2026.11.7")
os.environ["DOTFILES_SETTINGS_MISE"] = fake("2026.12.0 macos-arm64")
mise.check_version()
os.environ["DOTFILES_SETTINGS_MISE"] = str(tmp / "absent")
raises(mise.check_version, SettingsError, "mise is not on PATH")
del os.environ["DOTFILES_SETTINGS_MISE"]

# seed_env against a real zsh with its own ZDOTDIR
(zdot / ".zshrc").write_text("export T_RC=rc\n")
os.environ.update(ZDOTDIR=str(zdot), T_RC="stale", T_ONLY_HERE="stale")
assert seed_env_real({"T_RC", "T_ONLY_HERE"}) == {"T_RC": "rc"}

# A1's cache honours the guard seed_env relies on
guard = Path(__file__).resolve().parents[2] / "zsh/override-env.zsh"
assert "DOTFILES_NO_OVERRIDE_ENV" in guard.read_text()
print("ok")
