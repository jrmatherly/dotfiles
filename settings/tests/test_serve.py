"""Checks the browser wrapper: the token, Host and Origin guard, and a page with no third-party URL. Needs
textual-serve, so it runs through uv: uv run --project settings python settings/tests/test_serve.py"""
import asyncio, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from aiohttp.test_utils import TestClient, TestServer
import textual_serve

from dotfiles_settings import serve

GOOGLE_LINK = '''    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css?family=Roboto%20Mono"
    />
'''
LOCAL_FONT = '''    <style>
      @font-face {
        font-family: "Roboto Mono";
        src: url("{{ config.static.url }}fonts/RobotoMono-VariableFont_wght.ttf");
        font-style: normal;
      }
    </style>
'''

# the shipped copy is upstream's template with only the font link replaced.
# A textual-serve upgrade that changes the template fails here: redo the copy (Task 5).
upstream = (Path(textual_serve.__file__).parent / "templates/app_index.html").read_text()
assert upstream.count(GOOGLE_LINK) == 1, "textual-serve's template changed its font link"
assert (serve.TEMPLATES / "app_index.html").read_text() == upstream.replace(GOOGLE_LINK, LOCAL_FONT), \
    "templates/app_index.html no longer matches textual-serve's template"


def third_party(body, port):
    own = (f"http://127.0.0.1:{port}/", f"ws://127.0.0.1:{port}/")
    urls = re.findall(r"""(?:[a-z]+:)?//[^\s"'<>)]+""", body)
    return [u for u in urls if not u.startswith(own) and u != "http://www.w3.org/2000/svg"]


async def main():
    port = serve.free_port()
    server = serve.GuardedServer("true", port, "tok")
    assert server.host == "127.0.0.1"
    assert server.templates_path == serve.TEMPLATES
    app = await server._make_app()
    origin = f"http://127.0.0.1:{port}"
    async with TestClient(TestServer(app, host="127.0.0.1", port=port)) as c:
        assert (await c.get("/")).status == 403                         # no token
        assert (await c.get("/?token=nope")).status == 403
        assert (await c.get("/static/js/textual.js")).status == 403
        assert (await c.get("/ws", headers={"Origin": origin})).status == 403
        r = await c.get("/?token=tok", allow_redirects=False)
        cookie = r.cookies[f"dotfiles_settings_{port}"]
        assert r.status == 302 and r.headers["Location"] == "/"
        assert cookie.value == "tok" and cookie["httponly"] and cookie["samesite"] == "Strict"
        page = await c.get("/")                                         # the client now holds the cookie
        body = await page.text()
        assert page.status == 200 and "fonts.googleapis.com" not in body
        assert third_party(body, port) == [], third_party(body, port)   # spec decision 4
        assert (await c.get("/static/js/textual.js")).status == 200
        assert (await c.get("/static/fonts/RobotoMono-VariableFont_wght.ttf")).status == 200
        assert (await c.get("/", headers={"Host": f"localhost:{port}"})).status == 403
        assert (await c.get("/", headers={"Host": f"evil.example:{port}"})).status == 403
        assert (await c.get("/", headers={"Origin": "http://evil.example"})).status == 403
        assert (await c.get("/ws")).status == 403                       # cookie, but no Origin
        assert (await c.get("/ws", headers={"Origin": "http://evil.example"})).status == 403
        ws = await c.ws_connect("/ws?width=80&height=24", headers={"Origin": origin})
        await ws.close()
    a, b = serve.free_port(), serve.free_port()
    assert 1024 < a < 65536 and 1024 < b < 65536


asyncio.run(main())
print("ok")
