"""Checks the tool adapter (Hindsight, Claude Code, jstack, plugin stack) against scratch files. Run: python3 test_tool.py"""
import atexit, json, os, shutil, stat, subprocess, sys, tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
repo = Path(__file__).resolve().parents[2]

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import cli, registry
from dotfiles_settings.adapters import ADAPTERS, tool
from dotfiles_settings.model import InvalidValue, Setting, SettingsError, Source, Value

run_real = tool.run
A = tool.ToolAdapter()
assert isinstance(ADAPTERS["tool"], tool.ToolAdapter)


def load_one(fragment):
    path = Path(tempfile.mkstemp(dir=tmp.parent, suffix=".toml")[1])
    atexit.register(path.unlink, True)
    path.write_text(f'[[setting]]\nid = "t.one"\nsection = "T"\nlabel = "L"\nhelp = "H"\naccess = "rw"\n{fragment}\n')
    return registry.load(path)[0]


def setting(**fields):
    return Setting(**{**dict(id="t.one", section="T", label="L", help="H", kind="tool", key="x:y", type="string",
                             access="rw"), **fields})


def all_settings():
    return registry.load(repo / "settings/registry.toml")


def by_id(id):
    return next(s for s in all_settings() if s.id == id)


def raises(fn, needle):
    try:
        fn()
    except SettingsError as e:
        return needle in str(e)
    return False


def raises_type(fn, cls):
    try:
        fn()
    except cls:
        return True
    except Exception:
        return False
    return False


def stub_run(stdout="", stderr="", returncode=0):
    calls = []
    tool.run = lambda argv, cwd=None: calls.append(argv) or subprocess.CompletedProcess(argv, returncode, stdout, stderr)
    return calls


def test_registry_accepts_the_tool_kind():
    s = load_one('kind = "tool"\nkey = "jstack:bug-fix"\ntype = "string"\nwidget = "seats"')
    assert (s.kind, s.widget) == ("tool", "seats")


def test_edit_file_keeps_mode_and_symlink():
    d = tmp / "edit"; d.mkdir()
    real = d / "real.json"; real.write_text("a\n"); real.chmod(0o600)
    link = d / "link.json"; link.symlink_to(real)
    tool.edit_file(link, lambda t: t + "b\n")
    assert link.is_symlink() and real.read_text() == "a\nb\n"
    assert stat.S_IMODE(real.stat().st_mode) == 0o600
    assert [p.name for p in d.iterdir() if p.name not in ("real.json", "link.json")] == []


def test_edit_file_retries_when_the_file_changes():
    f = tmp / "race.txt"; f.write_text("one\n"); calls = []
    def change(text):
        calls.append(text)
        if len(calls) == 1:
            f.write_text("one\nother\n")      # another writer lands mid-edit
        return text + "mine\n"
    tool.edit_file(f, change)
    assert f.read_text() == "one\nother\nmine\n" and len(calls) == 2


def test_unknown_tool_key_is_a_settings_error():
    assert raises(lambda: tool.ToolAdapter().read(setting(key="nope:x")), "nope")


def test_claude_panel_is_an_env_bool():
    s = by_id("ui.claude_panel")
    assert (s.kind, s.key, s.type, s.true_value, s.access) == ("env", "DOTFILES_UI_CLAUDE_PANEL", "bool", "1", "rw")


for name, fn in list(globals().items()):
    if name.startswith("test_") and callable(fn):
        try:
            fn()
        except AssertionError as e:
            raise AssertionError(f"{name}: {e}") from None
        finally:
            tool.run = run_real
print("ok")
