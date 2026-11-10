"""Drives the terminal UI against a fake adapter with Textual's pilot. Needs Textual, so it runs through uv:
uv run --project settings python settings/tests/test_tui.py"""
import asyncio, atexit, shutil, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from textual.widgets import Input, Label, ListView, Select, Static, Switch

from dotfiles_settings.model import Setting, SettingsError, Source, Value
from dotfiles_settings.tui import SettingsApp

tmp = Path(tempfile.mkdtemp())
atexit.register(shutil.rmtree, tmp, True)


class FakeAdapter:
    write_note = "noted"

    def __init__(self, seeds: dict[str, str]):
        self.overrides: dict[str, str] = {}
        self.seeds = seeds
        self.fail: str | None = None
        self.refuse: str | None = None
        self.writes: list[tuple[str, str]] = []
        self.path = tmp / "watched"
        self.ticks = 0
        self.touch()

    def touch(self):
        self.ticks += 1
        self.path.write_text(str(self.ticks))

    def watch_paths(self) -> list[Path]:
        return [self.path]

    def read(self, s: Setting) -> Value:
        if self.fail:
            raise SettingsError(self.fail)
        seed = self.seeds.get(s.key)
        if s.key in self.overrides:
            return Value(s.id, self.overrides[s.key], Source.OVERRIDE, seed, False)
        if seed is not None:
            return Value(s.id, seed, Source.SEED, seed, False)
        return Value(s.id, None, Source.UNSET, None, False)

    def write(self, s: Setting, value: str) -> None:
        if self.refuse:
            raise SettingsError(self.refuse)
        self.writes.append((s.key, value))
        self.overrides[s.key] = value

    def reset(self, s: Setting) -> None:
        self.overrides.pop(s.key, None)


def S(id, key, type, section="One", access="rw", **kw):
    return Setting(id=id, section=section, label=id, help=f"help for {id}", kind="env", key=key, type=type,
                   access=access, **kw)


SETTINGS = [
    S("t.flag", "T_FLAG", "bool", true_value="1"),
    S("t.name", "T_NAME", "string"),
    S("t.pick", "T_PICK", "enum", choices=("a", "b")),
    S("t.locked", "T_LOCKED", "string", access="ro"),
    S("u.other", "U_OTHER", "string", section="Two"),
]


async def main():
    fake = FakeAdapter(seeds={"T_NAME": "seeded"})
    app = SettingsApp(SETTINGS, {"env": fake})
    async with app.run_test(size=(120, 40), notifications=True) as pilot:
        await pilot.pause()
        assert [str(i.query_one(Label).content) for i in app.query_one("#sections", ListView).children] == ["One", "Two"]
        assert isinstance(app.query_one("#w-t-flag"), Switch)
        assert isinstance(app.query_one("#w-t-pick"), Select)
        assert isinstance(app.query_one("#w-t-name"), Input) and app.query_one("#w-t-name", Input).value == "seeded"
        assert app.query_one("#w-t-locked").disabled and not app.query("#r-t-locked")
        assert fake.writes == [], "mounting wrote nothing"
        assert "seed" in str(app.query_one("#m-t-name", Static).content)

        app.query_one("#w-t-flag").focus(); await pilot.press("enter"); await pilot.pause()
        assert fake.writes == [("T_FLAG", "1")]
        assert app.query_one("#m-t-flag").has_class("-override")
        assert "override" in str(app.query_one("#m-t-flag", Static).content)
        assert any("noted" in str(n.message) for n in app._notifications)

        await pilot.press("ctrl+r"); await pilot.pause()
        assert "T_FLAG" not in fake.overrides and not app.query_one("#m-t-flag").has_class("-override"), "ctrl+r reset the focused row"
        assert app.query_one("#w-t-flag", Switch).value is False

        app.query_one("#w-t-name", Input).focus()
        await pilot.press("end", "!", "enter"); await pilot.pause()
        assert fake.overrides["T_NAME"] == "seeded!"
        await pilot.click("#r-t-name"); await pilot.pause()
        assert app.query_one("#w-t-name", Input).value == "seeded"
        app.query_one("#w-t-name", Input).focus()
        await pilot.press("end", "!", "enter"); await pilot.pause()
        app.query_one("#r-t-name").focus(); await pilot.press("enter"); await pilot.pause()
        assert app.focused is app.query_one("#w-t-name"), "focus stays on the row after Reset removes its button"

        fake.refuse = "nope"
        app.query_one("#w-t-name", Input).focus()
        await pilot.press("end", "?", "enter"); await pilot.pause()
        assert app.query_one("#w-t-name", Input).value == "seeded", "a refused value does not stay on screen"
        assert any(n.severity == "error" and "nope" in str(n.message) for n in app._notifications)
        fake.refuse = None

        fake.overrides["T_PICK"] = "b"; fake.touch()
        await pilot.pause(2.5)
        assert app.query_one("#w-t-pick", Select).value == "b", "a second UI's write shows up"

        fake.fail = "config.override.toml: bad"; fake.touch()
        await pilot.pause(2.5)
        assert "config.override.toml" in str(app.query_one("#error", Static).content)
        assert app.query_one("#w-t-flag").disabled
        fake.fail = None; fake.touch()
        await pilot.pause(2.5)
        assert not app.query("#error") and not app.query_one("#w-t-flag").disabled, "a fixed file clears the banner"

    empty = SettingsApp([], {})
    async with empty.run_test(size=(120, 40)) as pilot:
        await pilot.pause()
        assert not empty.query("#sections ListItem"), "empty means empty, not the real registry"

asyncio.run(main())
print("ok")
