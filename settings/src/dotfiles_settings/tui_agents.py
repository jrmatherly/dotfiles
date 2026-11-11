"""The Agents section's widgets: a path list, a jstack role's seats, and the project plugin stack screen."""
from pathlib import Path

from textual import events, work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.message import Message
from textual.screen import Screen
from textual.widget import Widget
from textual.widgets import Button, DataTable, Footer, Select, Static, TextArea

from .adapters import tool
from .model import SettingsError

NO_EFFORT = ("inherit", "codex")


class LinesEditor(TextArea):
    DEFAULT_CSS = "LinesEditor { width: 1fr; max-width: 40; height: 5; }"

    class Submitted(Message):
        def __init__(self, editor: "LinesEditor", value: str):
            super().__init__()
            self.editor, self.value = editor, value

        @property
        def control(self) -> "LinesEditor":
            return self.editor

    def __init__(self, value: str, **kw):
        super().__init__(value, **kw)
        self.saved = value

    @property
    def value(self) -> str:
        return "\n".join(line.strip() for line in self.text.splitlines() if line.strip())

    @value.setter
    def value(self, value: str) -> None:
        self.saved = value
        if self.value != value:
            self.text = value

    def on_blur(self, event: events.Blur) -> None:
        if self.value != self.saved:
            self.post_message(self.Submitted(self, self.value))


class SeatsEditor(Widget):
    DEFAULT_CSS = """
    SeatsEditor { width: 1fr; max-width: 60; height: auto; }
    SeatsEditor Horizontal { height: auto; }
    SeatsEditor Select { width: 1fr; }
    """

    class Changed(Message):
        def __init__(self, editor: "SeatsEditor", value: str):
            super().__init__()
            self.editor, self.value = editor, value

        @property
        def control(self) -> "SeatsEditor":
            return self.editor

    def __init__(self, role: str, value: str, **kw):
        super().__init__(**kw)
        self.role = role
        self.seats = self.parse(value)

    @staticmethod
    def parse(value: str) -> list[list[str]]:
        # Lenient on purpose: a model-only seat such as `opus` must open without being rewritten
        return [list(seat.partition(" ")[::2]) for seat in value.split(", ")]

    @property
    def value(self) -> str:
        return ", ".join(f"{m} {e}" if e else m for m, e in self.seats if m)

    @value.setter
    def value(self, value: str) -> None:
        if value != self.value:
            self.seats = self.parse(value)
            self.refresh(recompose=True)

    def seat_row(self, n: int) -> Horizontal:
        model, effort = self.seats[n]
        names = [*tool.MODELS, "inherit", *(["codex"] if self.role in tool.CODEX_ROLES else [])]
        if model and model not in names:
            names.append(model)  # a full model id stays selectable, so opening the row never changes it
        return Horizontal(
            Select([(m, m) for m in names], value=model or Select.NULL, allow_blank=not model, prompt="unset",
                   id=f"model-{n}"),
            Select([(e, e) for e in tool.EFFORTS], value=effort or "medium", allow_blank=False, id=f"effort-{n}",
                   disabled=model in NO_EFFORT),
            classes="seat")

    def compose(self) -> ComposeResult:
        for n in range(len(self.seats)):
            yield self.seat_row(n)
        if self.role in tool.LIST_ROLES:
            yield Horizontal(Button("Add seat", id="add-seat"), Button("Remove seat", id="remove-seat"))

    def on_select_changed(self, event: Select.Changed) -> None:
        event.stop()  # nested selects are not settings, so the app must not see them
        kind, _, n = (event.select.id or "").partition("-")
        n = int(n)
        if n >= len(self.seats):
            return
        model, effort = self.seats[n]
        new = "" if event.value == Select.NULL else str(event.value)
        # Mounting a select posts its first value too; only a value that differs from the seat is the user's
        if kind == "model" and new != model:
            effort_select = self.query_one(f"#effort-{n}", Select)
            effort_select.disabled = new in NO_EFFORT
            self.seats[n] = [new, "" if new in NO_EFFORT else str(effort_select.value)]
        elif kind == "effort" and model not in NO_EFFORT and new != (effort or "medium"):
            self.seats[n] = [model, new]
        else:
            return
        self.post_message(self.Changed(self, self.value))

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        event.stop()
        if event.button.id == "add-seat":
            self.seats.append(["opus", "medium"])
            await self.mount(self.seat_row(len(self.seats) - 1), before=event.button.parent)
        elif len(self.seats) > 1:
            self.seats.pop()
            await self.query(".seat").last().remove()
        else:
            return
        self.post_message(self.Changed(self, self.value))


class StackScreen(Screen):
    BINDINGS = [
        Binding("k", "apply('keep')", "Keep"),
        Binding("o", "apply('off')", "Turn off"),
        Binding("escape", "app.pop_screen", "Close"),
    ]

    def __init__(self, cwd: Path):
        super().__init__()
        self.cwd = cwd
        self.rows: list[tool.StackRow] = []

    def compose(self) -> ComposeResult:
        yield Static(f"Plugins for {self.cwd}", id="stack-title")
        yield Static("Scanning", id="stack-state")
        yield DataTable(id="stack", cursor_type="row")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#stack", DataTable).add_columns("state", "plugin", "why")
        self.run_stack()

    @work(thread=True, exclusive=True)
    def run_stack(self, keep: tuple[str, ...] = (), off: tuple[str, ...] = ()) -> None:
        # claude-stack scan took about 3 s here, so it runs off the UI thread
        try:
            if keep or off:
                self.app.call_from_thread(self.notify, tool.stack_apply(self.cwd, keep=list(keep), off=list(off)))
            rows, state = tool.stack_scan(self.cwd), ""
        except SettingsError as e:
            self.app.call_from_thread(self.notify, str(e), severity="error")
            rows, state = self.rows, "Scan failed"
        self.app.call_from_thread(self.fill, rows, state)

    def fill(self, rows: list[tool.StackRow], state: str) -> None:
        self.rows = rows
        self.query_one("#stack-state", Static).update(state)
        table = self.query_one("#stack", DataTable)
        table.clear()
        for row in rows:
            table.add_row(*row)

    def action_apply(self, how: str) -> None:
        table = self.query_one("#stack", DataTable)
        if not self.rows or table.cursor_row >= len(self.rows):
            return
        key = self.rows[table.cursor_row].key
        self.query_one("#stack-state", Static).update("Applying")
        self.run_stack(keep=(key,) if how == "keep" else (), off=(key,) if how == "off" else ())
