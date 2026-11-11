"""Checks the tool adapter (Hindsight, Claude Code, jstack, plugin stack) against scratch files. Run: python3 test_tool.py"""
import atexit, contextlib, http.server, json, os, shutil, stat, subprocess, sys, tempfile, threading
from pathlib import Path

tmp = Path(tempfile.mkdtemp()).resolve()
atexit.register(shutil.rmtree, tmp, True)
repo = Path(__file__).resolve().parents[2]
cfg = tmp / "hindsight/coding-agent.json"
cfg.parent.mkdir()
live, tracked_settings = tmp / "claude/settings.json", tmp / "save/claude-settings.json"
live.parent.mkdir(); tracked_settings.parent.mkdir()
os.environ.update(DOTFILES=str(repo), HINDSIGHT_CONFIG=str(cfg), CLAUDE_CONFIG_DIR=str(live.parent),
                  CLAUDE_CONFIG_SAVE_DIR=str(tracked_settings.parent))

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


@contextlib.contextmanager
def health_server():
    class Health(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200 if self.path == "/health" else 404)
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Health)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        yield server.server_port
    finally:
        server.shutdown()


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


def test_hindsight_flags_round_trip():
    cfg.write_text('{"optInPaths": ["~/dev"]}')
    v = A.read(by_id("hindsight.enabled"))
    assert (v.value, v.source, v.seed, v.drift) == ("true", Source.SEED, "true", False)
    s = by_id("hindsight.enabled")
    assert (cli.normalize(s, "off"), cli.normalize(s, "on")) == ("", "true")
    A.write(s, cli.normalize(s, "off"))         # a false bool arrives as ""
    assert json.loads(cfg.read_text())["disabled"] is True
    assert A.read(by_id("hindsight.enabled")).source is Source.OVERRIDE
    A.reset(by_id("hindsight.enabled"))
    assert json.loads(cfg.read_text())["disabled"] is False
    s = by_id("hindsight.survey")
    A.write(s, cli.normalize(s, "yes"))
    assert json.loads(cfg.read_text())["codebaseSurvey"] is True
    A.write(s, cli.normalize(s, "no"))
    assert json.loads(cfg.read_text())["codebaseSurvey"] is False


def test_hindsight_paths_add_then_remove():
    cfg.write_text('{"optInPaths": ["~/dev", "/opt/old"]}')
    A.write(by_id("hindsight.paths"), "~/dev\n/opt/src\n\n")
    assert json.loads(cfg.read_text())["optInPaths"] == ["~/dev", "/opt/src"]
    assert A.read(by_id("hindsight.paths")).value == "~/dev\n/opt/src"


def test_hindsight_without_config():
    cfg.unlink()
    v = A.read(by_id("hindsight.enabled"))
    assert (v.value, v.source) == (None, Source.UNSET)
    assert raises(lambda: A.write(by_id("hindsight.enabled"), "true"), "hindsight-memory init")
    assert not cfg.exists()
    assert A.read(by_id("hindsight.daemon")).value == "not installed"
    Path(str(cfg) + ".uninstalled").write_text("{}")
    assert A.read(by_id("hindsight.daemon")).value == "uninstalled"


def test_hindsight_daemon_probe():
    cfg.write_text('{"apiPort": 1}')            # port 1 refuses at once, as test-hindsight-memory does
    assert A.read(by_id("hindsight.daemon")).value == "down"
    with health_server() as port:               # http.server thread answering 200 on /health
        cfg.write_text(json.dumps({"apiPort": port}))
        assert A.read(by_id("hindsight.daemon")).value == "running"


def test_hindsight_port_treats_null_as_the_default():
    assert tool.hindsight_port({"apiPort": None}) == 9077     # the live config holds null
    assert tool.hindsight_port({}) == 9077
    assert tool.hindsight_port({"apiPort": 1}) == 1


def test_registry_defaults_match_the_script():
    src = (repo / "bin/hindsight-memory").read_text()
    assert '"optInPaths": ["~/dev"]' in src and '"codebaseSurvey": false' in src and '"disabled"' not in src.split("defaults()")[1].split("EOF")[1]
    assert (by_id("hindsight.paths").default, by_id("hindsight.survey").default, by_id("hindsight.enabled").default) == ("~/dev", "", "true")


LIVE = '{\n  "env": {\n    "K": "v"\n  },\n  "model": "fable",\n  "theme": "dark"\n}\n'


def test_claude_model_seed_and_drift():
    live.write_text(LIVE); tracked_settings.write_text('{"model": "opus"}')
    v = A.read(by_id("claude.model"))
    assert (v.value, v.seed, v.source, v.drift) == ("fable", "opus", Source.OVERRIDE, True)
    tracked_settings.write_text('{"model": "fable"}')
    v = A.read(by_id("claude.model"))
    assert (v.source, v.drift) == (Source.SEED, False)


def test_claude_model_write_changes_only_the_live_model():
    live.write_text(LIVE); live.chmod(0o600); tracked_settings.write_text('{"model": "opus"}')
    before = tracked_settings.read_text()
    A.write(by_id("claude.model"), "sonnet")
    assert live.read_text() == LIVE.replace('"fable"', '"sonnet"')   # every other byte kept
    assert tracked_settings.read_text() == before
    assert stat.S_IMODE(live.stat().st_mode) == 0o600
    A.reset(by_id("claude.model"))
    assert json.loads(live.read_text())["model"] == "opus"


def test_claude_model_reset_without_a_tracked_value_removes_the_key():
    live.write_text(LIVE); tracked_settings.write_text("{}")
    A.reset(by_id("claude.model"))
    assert "model" not in json.loads(live.read_text())
    assert A.read(by_id("claude.model")).source is Source.UNSET


def test_claude_model_rejects_a_bad_name():
    live.write_text(LIVE)
    for bad in ("", "two words", "x;rm"):
        assert raises_type(lambda: A.write(by_id("claude.model"), bad), InvalidValue)
    A.write(by_id("claude.model"), "opus[1m]")
    A.write(by_id("claude.model"), "claude-fable-5-2")


def test_claude_model_refuses_invalid_json():
    live.write_text('{"env": {')
    assert A.read(by_id("claude.model")).value is None
    assert raises_type(lambda: A.write(by_id("claude.model"), "opus"), SettingsError)
    assert live.read_text() == '{"env": {'
    live.unlink()
    assert raises_type(lambda: A.write(by_id("claude.model"), "opus"), SettingsError)
    assert not live.exists()


for name, fn in list(globals().items()):
    if name.startswith("test_") and callable(fn):
        try:
            fn()
        except AssertionError as e:
            raise AssertionError(f"{name}: {e}") from None
        finally:
            tool.run = run_real
print("ok")
