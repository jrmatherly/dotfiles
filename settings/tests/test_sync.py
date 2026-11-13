"""Checks the record of tool settings in tools.toml and its replay, against fake adapters. Run: python3 test_sync.py"""
import atexit, os, shutil, sys, tempfile, tomllib
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
os.environ.update(ROTM_USER_DIR=str(tmp / "user"), XDG_STATE_HOME=str(tmp / "state"))

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import sync
from dotfiles_settings.model import Setting, SettingsError, Source, Value


def setting(id, scope="user"):
    return Setting(id=id, section="T", label="L", help="H", kind="fake", key="x:y", type="string", access="rw",
                   scope=scope)


class Fake:
    def __init__(self, values, fail=()):
        self.values, self.fail, self.calls = dict(values), set(fail), []

    def read(self, s):
        return Value(s.id, self.values.get(s.id), Source.SEED, None, False)

    def write(self, s, value):
        self.calls.append(("write", s.id, value))
        if s.id in self.fail:
            raise SettingsError(f"{s.id} broke")
        self.values[s.id] = value

    def reset(self, s):
        self.calls.append(("reset", s.id))
        self.values.pop(s.id, None)


def tools(path):
    return tomllib.loads(path.read_text())["tools"] if path.exists() else {}


def clean():
    for p in (sync.tools_path(), sync.applied_path()):
        p.unlink(missing_ok=True)


def test_paths_follow_the_environment():
    assert sync.user_dir() == tmp / "user"
    assert sync.tools_path() == tmp / "user/tools.toml"
    assert sync.applied_path() == tmp / "state/rotm/tools.applied.toml"


def test_record_keeps_ids_sorted_and_is_stable():
    clean()
    sync.record(setting("b.two"), "2")
    sync.record(setting("a.one"), "1")
    text = sync.tools_path().read_text()
    assert text == '[tools]\n"a.one" = "1"\n"b.two" = "2"\n', text
    assert tools(sync.applied_path()) == {"a.one": "1", "b.two": "2"}
    sync.record(setting("a.one"), "1")
    assert sync.tools_path().read_text() == text


def test_forget_removes_from_both_and_ignores_unknown():
    clean()
    sync.record(setting("a.one"), "1"); sync.record(setting("b.two"), "2")
    sync.forget(setting("a.one"))
    assert tools(sync.tools_path()) == {"b.two": "2"} and tools(sync.applied_path()) == {"b.two": "2"}
    before = sync.tools_path().read_bytes()
    sync.forget(setting("never.recorded"))
    assert sync.tools_path().read_bytes() == before
    clean()
    sync.forget(setting("never.recorded"))
    assert not sync.tools_path().exists() and not sync.applied_path().exists()


def test_machine_scope_is_never_recorded():
    clean()
    sync.record(setting("m.one", scope="machine"), "x")
    assert not sync.tools_path().exists() and not sync.applied_path().exists()
    sync.record(setting("m.one"), "x")
    sync.forget(setting("m.one", scope="machine"))
    assert tools(sync.tools_path()) == {"m.one": "x"}


def test_awkward_values_round_trip():
    clean()
    values = {"a.lines": "~/dev\n/opt/src", "b.quote": 'say "hi" \\ back', "c.wide": "café \U0001f600"}
    for id, v in values.items():
        sync.record(setting(id), v)
    assert tools(sync.tools_path()) == values


def test_replay_writes_only_what_differs():
    clean()
    sync.record(setting("a.one"), "1"); sync.record(setting("b.two"), "2")
    fake = Fake({"a.one": "1", "b.two": "old"})
    lines = sync.replay([setting("a.one"), setting("b.two")], {"fake": fake})
    assert fake.calls == [("write", "b.two", "2")] and len(lines) == 1 and "b.two" in lines[0], lines
    assert sync.applied_path().read_text() == sync.tools_path().read_text()


def test_replay_resets_what_another_mac_reset():
    clean()
    sync.record(setting("a.one"), "1"); sync.record(setting("b.two"), "2")
    sync.tools_path().write_text('[tools]\n"b.two" = "2"\n')   # the other Mac's reset, arrived by sync
    fake = Fake({"a.one": "1", "b.two": "2"})
    lines = sync.replay([setting("a.one"), setting("b.two")], {"fake": fake})
    assert fake.calls == [("reset", "a.one")] and len(lines) == 1, lines
    assert tools(sync.applied_path()) == {"b.two": "2"}


def test_replay_skips_an_unknown_id():
    clean()
    sync.record(setting("gone.away"), "1")
    lines = sync.replay([], {"fake": Fake({})})
    assert lines == ["skipped gone.away: not a setting here"], lines
    assert tools(sync.tools_path()) == {"gone.away": "1"}


def test_replay_carries_on_after_a_failure():
    clean()
    sync.record(setting("a.one"), "1"); sync.record(setting("b.two"), "2")
    sync.applied_path().unlink()                       # a new Mac: nothing applied yet
    before = sync.tools_path().read_bytes()
    fake = Fake({}, fail={"a.one"})
    lines = sync.replay([setting("a.one"), setting("b.two")], {"fake": fake})
    assert any("a.one broke" in l for l in lines) and fake.values == {"b.two": "2"}, lines
    assert sync.tools_path().read_bytes() == before
    assert tools(sync.applied_path()) == {"b.two": "2"}
    fake.fail.clear(); fake.calls.clear()
    sync.replay([setting("a.one"), setting("b.two")], {"fake": fake})
    assert fake.calls == [("write", "a.one", "1")]
    assert tools(sync.applied_path()) == {"a.one": "1", "b.two": "2"}


def test_replay_retries_a_failed_reset():
    clean()
    sync.record(setting("a.one"), "1")
    sync.tools_path().write_text("[tools]\n")
    fake = Fake({"a.one": "1"})
    fake.reset = lambda s: (_ for _ in ()).throw(SettingsError("reset broke"))
    lines = sync.replay([setting("a.one")], {"fake": fake})
    assert any("reset broke" in l for l in lines), lines
    assert tools(sync.applied_path()) == {"a.one": "1"}


def test_a_broken_tools_file_is_a_settings_error():
    clean()
    sync.user_dir().mkdir(parents=True, exist_ok=True)
    sync.tools_path().write_text("[tools\n")
    try:
        sync.replay([], {})
    except SettingsError as e:
        assert str(sync.tools_path()) in str(e)
    else:
        raise AssertionError("no error")


for name, fn in list(globals().items()):
    if name.startswith("test_") and callable(fn):
        try:
            fn()
        except AssertionError as e:
            raise AssertionError(f"{name}: {e}") from None
print("ok")
