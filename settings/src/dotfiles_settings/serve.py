"""The browser UI: textual-serve on 127.0.0.1, behind a per-run token, a Host check and a WebSocket Origin check.
textual-serve has none of these, and any page open in the browser could otherwise drive the app over /ws."""
import secrets, shlex, socket, sys, webbrowser
from pathlib import Path

from aiohttp import web
from textual_serve.server import Server

# upstream's app_index.html with the Google Fonts link swapped for its bundled font; redo it when the lock bumps textual-serve
TEMPLATES = Path(__file__).parent / "templates"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def guard(port: int, token: str):
    own = f"127.0.0.1:{port}"
    cookie = f"dotfiles_settings_{port}"  # cookies are shared across ports, so two runs need two names

    @web.middleware
    async def middleware(request: web.Request, handler):
        origin = request.headers.get("Origin")
        if request.headers.get("Host") != own:  # DNS rebinding
            return web.Response(status=403, text="forbidden")
        if origin is not None and origin != f"http://{own}":
            return web.Response(status=403, text="forbidden")
        if request.path == "/ws" and origin is None:
            return web.Response(status=403, text="forbidden")
        if secrets.compare_digest(request.query.get("token", ""), token):
            # the redirect takes the token out of the address bar
            response = web.Response(status=302, headers={"Location": "/"})
            response.set_cookie(cookie, token, httponly=True, samesite="Strict", path="/")
            return response
        if not secrets.compare_digest(request.cookies.get(cookie, ""), token):
            return web.Response(status=403, text="forbidden")
        return await handler(request)

    return middleware


class GuardedServer(Server):
    def __init__(self, command: str, port: int, token: str):
        super().__init__(command, host="127.0.0.1", port=port, title="dotfiles settings", templates_path=TEMPLATES)
        self.token = token

    async def _make_app(self) -> web.Application:
        app = await super()._make_app()
        app.middlewares.append(guard(self.port, self.token))
        return app


def run(open_browser: bool = True) -> None:
    port = free_port()
    token = secrets.token_urlsafe(32)
    url = f"http://127.0.0.1:{port}/?token={token}"
    print(url, flush=True)
    if open_browser:
        webbrowser.open(url)
    GuardedServer(shlex.join([sys.executable, "-m", "dotfiles_settings", "tui"]), port, token).serve()
