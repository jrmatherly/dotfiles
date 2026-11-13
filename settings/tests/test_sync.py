"""Checks the record of tool settings in tools.toml and its replay, against fake adapters, and the sync commands
against stub gh, mise, rotm-user-layer and rotm-modules scripts. Run: python3 test_sync.py"""
import atexit, os, shutil, sys, tempfile, tomllib
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
home, conf, stubs, log, answers = (tmp / n for n in ("home", "conf", "stubs", "log", "answers"))
for d in (home, conf, stubs / "bin/lib", answers):
    d.mkdir(parents=True)
os.environ.update(ROTM_USER_DIR=str(tmp / "user"), XDG_STATE_HOME=str(tmp / "state"), HOME=str(home),
                  MISE_CONFIG_DIR=str(conf), DOTFILES=str(stubs), DOTFILES_SETTINGS_MISE=str(stubs / "mise"),
                  DOTFILES_SETTINGS_GH=str(stubs / "gh"), PATH=f"{stubs}:{os.environ['PATH']}")
# Each stub logs its call and answers from answers/<call>.out, .err and .code
for name, path in (("gh", "gh"), ("mise", "mise"), ("defaults", "defaults"),
                   ("rotm-user-layer", "bin/lib/rotm-user-layer"), ("rotm-modules", "bin/lib/rotm-modules")):
    (stubs / path).write_text(f'''#!/bin/sh
echo "{name} $*" >> "{log}"
f="{answers}/$(echo "{name} $*" | tr ' /' '__')"
[ -f "$f.out" ] && cat "$f.out"
[ -f "$f.err" ] && cat "$f.err" >&2
[ -f "$f.code" ] && exit "$(cat "$f.code")"
exit 0
''')
    (stubs / path).chmod(0o755)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import profile, sync
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
    values = {"a.lines": "~/dev\n/opt/src", "b.quote": 'say "hi" \\ back', "c.wide": "café \U0001f600",
              "d.del": "a\x7fb"}
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
    assert lines == ["Skipped gone.away: this version has no such setting."], lines
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


URL = "https://github.com/octo/rotm-settings.git"
CONNECTED = f"{URL} (branch main) declared in ~/.config/mise/config.local.toml; mode manual\n"
CONFLICT = "Conflict: ~/.config/rotm/config.override.toml (unsaved edits: save or discard them first)\n"
seen = []                                              # every call of every test, for the last check
real_replay = sync.replay


def logged_replay(settings, adapters):
    with log.open("a") as f:
        f.write("replay\n")
    return real_replay(settings, adapters)


sync.replay = logged_replay


def answer(call, out="", err="", code=0):
    f = answers / call.replace(" ", "_").replace("/", "_")
    for ext, text in ((".out", out), (".err", err), (".code", str(code))):
        Path(f"{f}{ext}").write_text(text)


def fresh(repo="rotm-settings"):
    """An empty folder, config dir and state, a signed-in gh, no such repository, a connected origin, no conflict."""
    seen.extend(calls())
    log.unlink(missing_ok=True)
    for d in (answers, sync.user_dir(), conf, tmp / "state"):
        shutil.rmtree(d, True)
        d.mkdir(parents=True)
    answer("gh api user --jq .login", "octo\n")
    answer(f"gh repo view octo/{repo} --json isEmpty --jq .isEmpty", err="GraphQL: Could not resolve", code=1)
    answer(f"gh repo view octo/{repo} --json visibility --jq .visibility", "PRIVATE\n")
    answer("mise dot origin", CONNECTED)
    answer("mise dot conflicts", err="mise no sharing conflicts\n")


def calls():
    return log.read_text().splitlines() if log.exists() else []


def raises(fn, *args):
    try:
        fn(*args)
    except SettingsError as e:
        return str(e)
    raise AssertionError(f"{fn.__name__} did not raise")


def test_on_creates_a_repository_and_connects_it():
    fresh()
    lines = sync.on("rotm-settings")
    assert calls() == ["gh auth status", "gh api user --jq .login",
                       "gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty",
                       "gh repo create rotm-settings --private", "rotm-user-layer ensure", "rotm-user-layer track",
                       "mise dot save", f"mise dot origin set {URL} --sync manual --yes", "mise dot sync",
                       "mise dot conflicts"], calls()
    assert any("sync now" in l for l in lines), lines
    assert not any("setup-git" in c for c in calls())
    assert not [p for p in home.rglob(".gitconfig*")]
    # A module already off on this Mac is not news to its first apply
    fresh()
    (conf / "modules-off.local").write_text("fonts\n")
    sync.on("rotm-settings")
    assert not any("rotm install" in l for l in sync.apply())


def test_on_an_empty_repository_is_not_created_again():
    fresh()
    answer("gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty", "true\n")
    sync.on("rotm-settings")
    assert "gh repo create rotm-settings --private" not in calls() and "mise dot save" in calls(), calls()


def test_on_another_name_is_used_everywhere():
    fresh("mine")
    sync.on("mine")
    named = [c for c in calls() if "rotm-settings" in c or "mine" in c]
    assert named and all("mine" in c and "rotm-settings" not in c for c in named), calls()
    assert "mise dot origin set https://github.com/octo/mine.git --sync manual --yes" in calls()


def test_on_refuses_a_name_that_is_not_a_repository_name():
    fresh()
    assert "--repo" in raises(sync.on, "someone/else") and calls() == []


def test_on_restores_a_settings_repository():
    fresh()
    answer("gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty", "false\n")
    sync.on("rotm-settings")
    got = calls()
    touching = [c for c in got if c.startswith(("rotm-user-layer", "mise dot save"))]
    assert touching == [f"rotm-user-layer restore {URL}"], got
    # rotm-user-layer restore checks for a conflict itself, before anything is applied
    assert got[got.index(touching[0]) + 1:] == ["rotm-modules sync", "replay"], got
    assert "gh repo create rotm-settings --private" not in got


def test_on_refuses_a_repository_that_is_not_private():
    for empty in ("true\n", "false\n"):
        fresh()
        answer("gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty", empty)
        answer("gh repo view octo/rotm-settings --json visibility --jq .visibility", "PUBLIC\n")
        assert "not a private repository" in raises(sync.on, "rotm-settings")
        assert not [c for c in calls() if c.startswith(("mise", "rotm-user-layer"))], calls()


def test_on_refuses_a_repository_that_holds_something_else():
    fresh()
    answer("gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty", "false\n")
    answer("gh api repos/octo/rotm-settings/contents/.mise-history/format.toml", code=1)
    assert "--repo" in raises(sync.on, "rotm-settings")
    assert not [c for c in calls() if c.startswith(("mise", "rotm-"))], calls()


def test_on_without_gh_login_and_no_terminal_names_the_login():
    fresh()
    answer("gh auth status", code=1)
    assert "gh auth login" in raises(sync.on, "rotm-settings") and calls() == ["gh auth status"]


def test_on_without_gh_login_on_a_terminal_signs_in():
    fresh()
    answer("gh auth status", code=1)
    stdin = sys.stdin
    sys.stdin = type("Tty", (), {"isatty": lambda self: True})()
    try:
        sync.on("rotm-settings")
    finally:
        sys.stdin = stdin
    assert calls()[1] == "gh auth login --hostname github.com --git-protocol https --web", calls()
    assert "mise dot sync" in calls()


def test_a_secret_or_a_stray_file_stops_before_the_first_save():
    for bad, name in ((sync.user_dir() / "config.override.toml", "GITHUB_TOKEN"),
                      (sync.user_dir() / "notes.txt", "notes.txt")):
        for fn, args in ((sync.on, ("rotm-settings",)), (sync.now, ())):
            fresh()
            bad.write_text('[env]\nGITHUB_TOKEN = "x"\nPLAIN = "y"\n')
            message = raises(fn, *args)
            assert name in message and "PLAIN" not in message, (fn.__name__, message)
            assert "mise dot save" not in calls(), (fn.__name__, calls())


def test_the_secret_rule_reads_every_env_table_in_any_case():
    for body, name in (('[[env]]\nPLAIN = "y"\n[[env]]\nGITHUB_TOKEN = "x"\n', "GITHUB_TOKEN"),
                       ('[env]\ngithub_token = "x"\n', "github_token"), ('[env]\nDB_PASSWORD = "x"\n', "DB_PASSWORD"),
                       ('[env]\nAWS_SECRET_ACCESS_KEY = "x"\n', "AWS_SECRET_ACCESS_KEY")):
        fresh()
        (sync.user_dir() / "config.override.toml").write_text(body)
        assert name in raises(sync.now) and "mise dot save" not in calls(), (body, calls())
    for body in ('[[env]]\nPLAIN = "y"\n[[env]]\n_.path = ["~/bin"]\n', 'env = "GITHUB_TOKEN"\n'):
        fresh()
        (sync.user_dir() / "config.override.toml").write_text(body)
        sync.now()
        assert "mise dot save" in calls(), (body, calls())


def test_a_machine_setting_left_in_the_override_file_stops_a_save():
    for fn, args in ((sync.on, ("rotm-settings",)), (sync.now, ())):
        fresh()
        (sync.user_dir() / "config.override.toml").write_text(
            '[env]\nDOTFILES_MACOS_COMPUTER_NAME = "Studio"\nPLAIN = "y"\n')
        message = raises(fn, *args)
        assert all(s in message for s in ("DOTFILES_MACOS_COMPUTER_NAME", "rotm settings set macos.computer_name"))
        assert "PLAIN" not in message and "mise dot save" not in calls(), (fn.__name__, message, calls())


def test_a_mise_error_is_not_a_conflict():
    fresh()
    answer("mise dot conflicts", err="mise ERROR unrecognized subcommand dot\n", code=2)
    message = raises(sync.now)
    assert "unrecognized subcommand" in message and "--take-remote" not in message, message
    assert "mise dot save" not in calls(), calls()
    text = "\n".join(sync.status())
    assert "unrecognized subcommand" in text and "--take-remote" not in text, text
    fresh()
    answer("mise dot conflicts", "nothing to report\n")
    sync.now()
    assert not any("--take-remote" in l for l in sync.status())


def test_now_needs_a_connection():
    fresh()
    answer("mise dot origin", "no setup repository is connected; `mise dot origin set <url>` connects one\n")
    assert "sync on" in raises(sync.now) and "mise dot save" not in calls()


def test_now_saves_syncs_pulls_then_applies():
    fresh()
    lines = sync.now()
    assert calls() == ["mise dot origin", "mise dot conflicts", "mise dot save", "mise dot sync", "mise dot pull",
                       "mise dot conflicts", "rotm-user-layer ensure", "rotm-modules sync", "replay"], calls()
    assert lines, lines


def test_apply_is_offline():
    fresh()
    sync.apply()
    assert calls() == ["rotm-modules sync", "replay"], calls()


def test_apply_names_what_it_cannot_act_on_once():
    fresh()
    (conf / "modules-off.local").write_text("fonts\n")
    assert any("Nothing was installed or removed" in l and "rotm install" in l for l in sync.apply())
    assert not any("rotm install" in l for l in sync.apply())
    (conf / "config.override.toml").write_text('[bootstrap.packages]\n"brew:p" = { state = "absent" }\n')
    assert any("rotm install" in l for l in sync.apply())
    (conf / "config.override.toml").write_text('[bootstrap.settings.macos.defaults."com.apple.dock"]\nautohide = true\n')
    lines = sync.apply()
    assert any("set-defaults" in l for l in lines) and any("rotm install" in l for l in lines), lines
    assert not sync.apply()
    assert not [c for c in calls() if c.startswith("defaults")], calls()


def test_apply_right_after_setup_installed_leaves_out_only_the_install_line():
    fresh()
    (conf / "modules-off.local").write_text("fonts\n")
    (conf / "config.override.toml").write_text('[bootstrap.settings.macos.defaults."com.apple.dock"]\nautohide = true\n')
    os.environ["ROTM_JUST_INSTALLED"] = "1"
    try:
        lines = sync.apply()
    finally:
        del os.environ["ROTM_JUST_INSTALLED"]
    assert any("set-defaults" in l for l in lines) and not any("rotm install" in l for l in lines), lines
    assert not sync.apply()


def test_a_conflict_stops_on_and_now_with_the_commands_that_decide_it():
    def check(fn, *args):
        message = raises(fn, *args)
        assert all(s in message for s in ("config.override.toml", "--take-remote", "copy yours back")), message
        assert "--keep-local" not in message and "replay" not in calls(), calls()
        if fn is sync.now:
            assert "mise dot save" not in calls(), calls()
    for fn, args in ((sync.on, ("rotm-settings",)), (sync.now, ())):
        fresh()
        answer("mise dot conflicts", CONFLICT)
        check(fn, *args)
    fresh()
    answer("mise dot conflicts", CONFLICT)
    answer("mise dot pull", err="mise ERROR sync paused", code=1)
    check(sync.now)
    fresh()
    answer("gh repo view octo/rotm-settings --json isEmpty --jq .isEmpty", "false\n")
    answer(f"rotm-user-layer restore {URL}", err="rotm-user-layer: the restored settings conflict", code=1)
    answer("mise dot conflicts", CONFLICT)
    check(sync.on, "rotm-settings")


def test_off_only_disconnects():
    fresh()
    (sync.user_dir() / "modules-off.local").write_text("fonts\n")
    lines = sync.off()
    assert calls() == ["mise dot origin --remove"] and (sync.user_dir() / "modules-off.local").exists(), calls()
    assert any("sync on" in l for l in lines), lines


def test_status():
    fresh()
    answer("mise dot origin", "no setup repository is connected; `mise dot origin set <url>` connects one\n")
    assert any("not connected" in l for l in sync.status())
    fresh()
    answer("mise dot status", "\nTracking\n  ✓ 1 entry · 1 file\n  ⚠ unsaved changes: 1 path(s) since the latest "
           "checkpoint (~/.config/rotm/config.override.toml)\n\nRepository\n  Branch: main · Mode: manual\n")
    answer("mise dot conflicts", CONFLICT)
    text = "\n".join(sync.status())
    assert URL in text and "unsaved changes" in text and CONFLICT.strip() in text and "Tracking" not in text, text


def use(name):
    """The saved env line, as profile.use leaves it."""
    (conf / "miserc.local.toml").write_text(f'env = ["rotm-installed", "rotm-p-{name}"]\n' if name else "")


def test_a_profile_records_and_replays_its_own_tool_settings():
    fresh(); clean()
    s, extra = setting("claude.model"), setting("jstack.role")
    work = profile.tools_path("work")
    sync.record(s, "opus")
    use("work")
    sync.record(s, "haiku")
    sync.record(extra, "fable")
    assert tools(sync.tools_path()) == {"claude.model": "opus"}, "a profile's record changed tools.toml"
    assert tools(work) == {"claude.model": "haiku", "jstack.role": "fable"}
    fake = Fake({"claude.model": "opus"})
    sync.replay([s, extra], {"fake": fake})
    assert fake.values == {"claude.model": "haiku", "jstack.role": "fable"}, fake.values
    # leaving the profile: the shared value returns, and what only the profile set is reset
    use(None)
    lines = sync.replay([s, extra], {"fake": fake})
    assert fake.values == {"claude.model": "opus"} and any("Reset jstack.role" in l for l in lines), (fake.values, lines)
    # --shared writes tools.toml while the profile keeps its value
    use("work")
    profile.shared = True
    try:
        assert sync.masked(s) and not sync.masked(setting("other.id"))
        sync.record(s, "sonnet")
    finally:
        profile.shared = False
    assert tools(sync.tools_path()) == {"claude.model": "sonnet"} and tools(work)["claude.model"] == "haiku"
    # forget takes the profile's value and keeps the id applied, since the shared file still sets it
    sync.forget(s)
    assert "claude.model" not in tools(work) and "claude.model" in tools(sync.applied_path())
    assert sync.wanted_tools() == {"claude.model": "sonnet", "jstack.role": "fable"}
    clean()


def test_the_guards_cover_a_profiles_files():
    folder = sync.user_dir()
    fresh()
    for name in ("config.rotm-p-work.override.toml", "modules-off.rotm-p-work.local", "tools.rotm-p-work.toml"):
        (folder / name).write_text("")
    sync.now()
    assert "mise dot save" in calls()
    fresh()
    (folder / "tools.rotm-p-work.toml").write_text("")
    (folder / "notes.txt").write_text("x")
    assert "notes.txt" in raises(sync.now) and "tools.rotm-p-work.toml" not in raises(sync.now)
    for body, key in (('[env]\nGITHUB_TOKEN = "x"\n', "GITHUB_TOKEN"),
                      ('[env]\nDOTFILES_MACOS_COMPUTER_NAME = "Studio"\n', "DOTFILES_MACOS_COMPUTER_NAME")):
        fresh()
        bad = folder / "config.rotm-p-work.override.toml"
        bad.write_text(body)
        message = raises(sync.now)
        assert f"{key} in {bad}" in message and f"mise unset --file {bad} {key}" in message, message
        assert "unset --override" not in message and "mise dot save" not in calls(), message


def test_apply_compares_the_files_in_effect():
    fresh()
    sync.apply()
    (conf / "modules-off.rotm-p-work.local").write_text("fonts\n")
    (conf / "config.rotm-p-work.override.toml").write_text(
        '[bootstrap.settings.macos.defaults."com.apple.dock"]\nautohide = true\n')
    assert not sync.apply(), "a profile that is not in use changed what apply reports"
    use("work")
    lines = sync.apply()
    assert sync.INSTALL in lines and sync.DEFAULTS in lines and len(lines) == 2, lines
    assert not sync.apply()
    use(None)
    lines = sync.apply()
    assert sync.INSTALL in lines and sync.DEFAULTS in lines, lines
    # the profile's table is laid over the shared one, key by key
    (conf / "config.override.toml").write_text(
        '[bootstrap.settings.macos.defaults."com.apple.dock"]\ntilesize = 64\nautohide = false\n')
    use("work")
    assert sync._effective()["macos"] == {"com.apple.dock": {"tilesize": 64, "autohide": True}}
    assert not (tmp / "state/rotm/config.override.toml.applied").exists()
    use(None)


def test_no_call_tracks_and_every_connect_carries_yes():
    seen.extend(calls())
    assert seen and not [c for c in seen if "dot track" in c]
    assert all("--yes" in c and "--sync manual" in c for c in seen if " origin set " in c)


for name, fn in list(globals().items()):
    if name.startswith("test_") and callable(fn):
        try:
            fn()
        except AssertionError as e:
            raise AssertionError(f"{name}: {e}") from None
print("ok")
