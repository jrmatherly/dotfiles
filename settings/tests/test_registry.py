"""Checks the registry loader, its validation and the shipped registry.toml. Run: python3 test_registry.py"""
import atexit, json, re, shutil, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from dotfiles_settings import model, registry
from dotfiles_settings.model import SettingsError

tmp = Path(tempfile.mkdtemp())
atexit.register(shutil.rmtree, tmp, True)

VALID = dict(id="a.b", section="S", label="L", help="H", kind="env", key="A_B", type="string",
             true_value="", choices=[], default="", access="rw")


def load_text(toml_text):
    path = tmp / "registry.toml"
    path.write_text(toml_text)
    return registry.load(path)


def bad(toml_text, needle):
    try:
        load_text(toml_text)
    except SettingsError as e:
        assert needle in str(e), (needle, str(e))
        return
    raise AssertionError(f"expected SettingsError: {needle}")


def render(fields):
    return "[[setting]]\n" + "".join(f"{k} = {json.dumps(v)}\n" for k, v in fields.items())


def table(**fields):
    return render({**VALID, **fields})


def table_without(*names):
    return render({k: v for k, v in VALID.items() if k not in names})


def two_tables_with_id(id):
    return table(id=id) + "\n" + table(id=id)


settings = registry.load()
ids = [s.id for s in settings]
assert len(ids) == len(set(ids))                         # unique ids, no total: later plans append
assert {s.kind for s in settings} <= set(registry.KINDS)
by_id = {s.id: s for s in settings}
assert by_id["macos.hidpi"].true_value == "1"
assert by_id["apps.vscode_font_preset"].choices == ("iosevka", "warp", "warp-terminal", "fira")
assert all(s.access == "ro" for s in settings if s.section == "Privacy")
assert sum(s.section == "Privacy" for s in settings) == 22
# settings that describe one Mac never sync
machine = {"macos.computer_name", "macos.local_hostname", "hindsight.paths"}
assert {s.id for s in settings if s.scope == "machine"} == machine
assert all(s.scope == "user" for s in settings if s.id not in machine)

# every read-only opt-out is still exported by zsh/env.zsh
env_zsh = (Path(__file__).resolve().parents[2] / "zsh/env.zsh").read_text()
for s in settings:
    if s.section == "Privacy":
        assert re.search(rf"^export {s.key}=", env_zsh, re.M), s.key

# the Hindsight models are shown, never edited, and tilde/.zshenv still exports each (spec decision 3)
zshenv = (Path(__file__).resolve().parents[2] / "tilde/.zshenv").read_text()
models = [s for s in settings if s.kind == "env" and s.key.startswith("HINDSIGHT_API_")]
assert {s.key for s in models} == {"HINDSIGHT_API_LLM_MODEL", "HINDSIGHT_API_RETAIN_LLM_MODEL",
                                   "HINDSIGHT_API_CONSOLIDATION_LLM_MODEL"}
for s in models:
    assert s.access == "ro", s.id
    assert re.search(rf"^export {s.key}=", zshenv, re.M), s.key

bad(two_tables_with_id("a.b"), "duplicate id: a.b")
bad(table(kind="nope"), "a.b: unknown kind 'nope'")
bad(table(type="float"), "a.b: unknown type 'float'")
bad(table(type="enum", choices=[]), "a.b: enum needs choices")
bad(table(type="bool", true_value=""), "a.b: bool needs true_value")
bad(table(access="wo"), "a.b: access must be rw or ro")
bad(table(key="lower case"), "a.b: env key must match [A-Z_][A-Z0-9_]*")
bad(table(default="x", type="enum", choices=["y"]), "a.b: default 'x' is not one of the choices")
bad(table_without("label"), "a.b: missing field 'label'")
bad(table_without("access"), "a.b: missing field 'access'")
bad(table(extra=1), "a.b: unknown field 'extra'")
bad(table(widget="grid"), "a.b: unknown widget 'grid'")
bad(table(scope="everyone"), "a.b: scope must be user or machine")

# a short entry: the optional fields take their defaults
short = load_text(table_without("true_value", "choices", "default"))[0]
assert (short.true_value, short.choices, short.default, short.widget, short.scope) == ("", (), "", "", "user")
assert load_text(table(scope="machine"))[0].scope == "machine"
assert load_text(table(widget="seats"))[0].widget == "seats"
# a bool may be on by default: A3's switches set default equal to true_value (spec decisions 2 and 9)
on = load_text(table(type="bool", true_value="1", default="1", section="macOS (this Mac)"))[0]
assert (on.default, on.true_value, on.section) == ("1", "1", "macOS (this Mac)")


# write_note may be absent, a string or a method
class Plain: write_note = "note"


class PerSetting:
    def write_note(self, s): return "tracked" if s.id == "a.b" else ""


assert [model.note_for(a, short) for a in (object(), Plain(), PerSetting())] == ["", "note", "tracked"]
assert model.note_for(PerSetting(), by_id["shell.editor"]) == ""
menubar = by_id["modules.menubar"]
assert (menubar.kind, menubar.key, menubar.default) == ("module", "menubar", "on"), menubar
bad(table(id="Bad Id"), "id must be dotted lowercase: 'Bad Id'")
bad("not toml [", "registry.toml")           # the message names the file
bad("", "no settings")
print("ok")
