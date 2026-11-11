"""The terminal UI: sections on the left, the highlighted section's settings on the right."""
from pathlib import Path

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widget import Widget
from textual.widgets import Button, Footer, Input, Label, ListItem, ListView, Select, Static, Switch

from . import registry
from .cli import normalize
from .adapters import tool
from .model import Adapter, Setting, SettingsError, Source, Value, note_for
from .tui_agents import LinesEditor, SeatsEditor, StackScreen

CSS = """
#sections { width: 24; border-right: solid $panel; }
#error { background: $error; color: $text; padding: 0 1; }
.row { height: auto; margin: 1 1 0 1; }
.line { height: auto; }
.label { width: 30; padding: 1 1 0 0; }
.line Input, .line Select { width: 1fr; max-width: 40; }
.line Button { min-width: 9; }
.marker { width: auto; padding: 1 1 0 1; color: $text-muted; }
.marker.-override { color: $warning; text-style: bold; }
.help { color: $text-muted; }
"""


def slug(s: Setting) -> str:
    return s.id.replace(".", "-")


def widget_for(s: Setting, v: Value) -> Widget:
    ro = s.access == "ro"
    if s.widget == "lines":
        return LinesEditor(v.value or "", id=f"w-{slug(s)}", disabled=ro)
    if s.widget == "seats":
        return SeatsEditor(s.key.partition(":")[2], v.value or "", id=f"w-{slug(s)}", disabled=ro)
    if s.type == "bool":
        return Switch(value=v.value == s.true_value, id=f"w-{slug(s)}", disabled=ro)
    if s.type == "enum":
        current = v.value if v.value in s.choices else Select.NULL
        return Select([(c, c) for c in s.choices], allow_blank=True, value=current, id=f"w-{slug(s)}", disabled=ro)
    return Input(v.value or "", type="integer" if s.type == "int" else "text", id=f"w-{slug(s)}", disabled=ro)


def marker_text(v: Value) -> str:
    if v.source is not Source.OVERRIDE:
        return v.source.value
    return f"override  seed: {v.seed if v.seed is not None else 'unset'}"


class SettingsApp(App):
    CSS = CSS
    BINDINGS = [Binding("ctrl+r", "reset", "Reset the focused setting"), Binding("p", "stack", "Project plugins")]

    def __init__(self, settings: list[Setting] | None = None, adapters: dict[str, Adapter] | None = None):
        super().__init__()
        if adapters is None:
            from .adapters import ADAPTERS
            adapters = ADAPTERS
        self.settings = registry.load() if settings is None else settings
        self.adapters = adapters
        self.by_slug = {slug(s): s for s in self.settings}
        self.sections = list(dict.fromkeys(s.section for s in self.settings))
        self.values: dict[str, Value] = {}
        self.mtimes: dict[Path, float | None] = {}
        self.error: str | None = None

    def compose(self) -> ComposeResult:
        with Horizontal():
            yield ListView(*(ListItem(Label(name)) for name in self.sections), id="sections")
            # Not focusable, so Tab goes from the sections straight to the first setting
            yield VerticalScroll(id="rows", can_focus=False)
        yield Footer()

    def on_mount(self) -> None:
        self.mtimes = self.watched()
        self.read_all()
        rows = self.query_one("#rows")
        for i, name in enumerate(self.sections):
            box = Vertical(classes="section")
            box.display = i == 0
            rows.mount(box)
            for s in (s for s in self.settings if s.section == name):
                v = self.values.get(s.id) or Value(s.id, None, Source.UNSET, None, False)
                box.mount(self.row(s, v))
        self.show_state()
        self.set_interval(2.0, self.poll)

    def row(self, s: Setting, v: Value) -> Widget:
        marker = Static(marker_text(v), id=f"m-{slug(s)}", classes="marker")
        marker.set_class(v.source is Source.OVERRIDE, "-override")
        line = Horizontal(Label(s.label, classes="label"), widget_for(s, v), marker, classes="line")
        if v.source is Source.OVERRIDE and s.access != "ro":
            line.compose_add_child(Button("Reset", id=f"r-{slug(s)}"))
        return Vertical(line, Static(s.help, classes="help"), classes="row")

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        for i, box in enumerate(self.query(".section")):
            box.display = i == event.list_view.index

    def watched(self) -> dict[Path, float | None]:
        paths = {p for a in self.adapters.values() if hasattr(a, "watch_paths") for p in a.watch_paths()}
        return {p: p.stat().st_mtime if p.exists() else None for p in paths}

    def read_all(self) -> dict[str, Value]:
        """Re-read every value; returns the ones that changed. A failure sets self.error."""
        try:
            fresh = {s.id: self.adapters[s.kind].read(s) for s in self.settings}
        except SettingsError as e:
            self.error = str(e)
            return {}
        self.error = None
        changed = {k: v for k, v in fresh.items() if self.values.get(k) != v}
        self.values = fresh
        return changed

    def show_state(self) -> None:
        banner = self.query("#error")
        if self.error and not banner:
            self.mount(Static(self.error, id="error"), before=0)
        elif self.error:
            banner.first(Static).update(self.error)
        else:
            banner.remove()
        for s in self.settings:
            for w in self.query(f"#w-{slug(s)}, #r-{slug(s)}"):
                w.disabled = bool(self.error) or s.access == "ro"

    def redraw(self, s: Setting) -> None:
        v = self.values.get(s.id)
        if v is None:
            return
        # self.values is current before the widget changes, so the Changed event this fires is a no-op
        w = self.query_one(f"#w-{slug(s)}")
        if isinstance(w, Switch):
            w.value = v.value == s.true_value
        elif isinstance(w, Select):
            if v.value in s.choices:
                w.value = v.value
            else:
                w.clear()
        else:
            w.value = v.value or ""
        marker = self.query_one(f"#m-{slug(s)}", Static)
        marker.update(marker_text(v))
        marker.set_class(v.source is Source.OVERRIDE, "-override")
        button = self.query(f"#r-{slug(s)}")
        if v.source is Source.OVERRIDE and s.access != "ro":
            if not button:
                marker.parent.mount(Button("Reset", id=f"r-{slug(s)}"))
        else:
            button.remove()

    def refresh_values(self, force: Setting | None = None) -> None:
        changed = self.read_all()
        for s in self.settings:
            if s.id in changed or s is force:
                self.redraw(s)
        self.show_state()

    def poll(self) -> None:
        now = self.watched()
        if now != self.mtimes or self.error:
            self.mtimes = now
            self.refresh_values()

    def commit(self, s: Setting, raw: str) -> None:
        adapter = self.adapters[s.kind]
        try:
            value = normalize(s, raw)
            if value == (self.values[s.id].value or ""):
                return
            adapter.write(s, value)
        except SettingsError as e:
            self.notify(str(e), severity="error")
            self.refresh_values(force=s)
            return
        self.refresh_values(force=s)
        if note := note_for(adapter, s):
            self.notify(note)

    def reset(self, s: Setting) -> None:
        if s.access == "ro" or self.values[s.id].source is not Source.OVERRIDE:
            return
        adapter = self.adapters[s.kind]
        try:
            adapter.reset(s)
        except SettingsError as e:
            self.notify(str(e), severity="error")
            self.refresh_values(force=s)
            return
        self.refresh_values(force=s)
        if note := note_for(adapter, s):
            self.notify(note)

    def setting_of(self, w: Widget | None) -> Setting | None:
        return self.by_slug.get((w.id or "")[2:]) if w is not None else None

    def on_switch_changed(self, event: Switch.Changed) -> None:
        if s := self.setting_of(event.switch):
            self.commit(s, "on" if event.value else "off")

    def on_select_changed(self, event: Select.Changed) -> None:
        s = self.setting_of(event.select)
        if s and event.value != Select.NULL:
            self.commit(s, str(event.value))

    def on_input_submitted(self, event: Input.Submitted) -> None:
        s = self.setting_of(event.input)
        if s and event.value != (self.values[s.id].value or ""):
            self.commit(s, event.value)

    def on_lines_editor_submitted(self, event: LinesEditor.Submitted) -> None:
        if s := self.setting_of(event.editor):
            self.commit(s, event.value)

    def on_seats_editor_changed(self, event: SeatsEditor.Changed) -> None:
        if s := self.setting_of(event.editor):
            self.commit(s, event.value)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if s := self.setting_of(event.button):
            self.reset(s)

    def action_reset(self) -> None:
        if s := self.setting_of(self.focused):
            self.reset(s)

    def action_stack(self) -> None:
        if not isinstance(self.screen, StackScreen):
            self.push_screen(StackScreen(tool.launch_dir()))


def run() -> None:
    SettingsApp().run()
