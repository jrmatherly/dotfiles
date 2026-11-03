"""Checks claude-stack's evidence, decisions, writes and rule. Run: python3 test_stack.py"""
import json, os, subprocess, tempfile
from collections import Counter
from pathlib import Path

# Before the import: stack.py's own git calls inherit these, so results match on this Mac and on CI
os.environ.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                  GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
import stack as s

tmp = Path(tempfile.mkdtemp()).resolve()


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


def repo(path):
    path.mkdir(parents=True)
    git(path, "init", "-q")
    git(path, "commit", "-q", "--allow-empty", "-m", "init")
    return path


def raises(fn, needle):
    try:
        fn()
    except s.StackError as e:
        assert needle in str(e), (needle, str(e))
        return
    raise AssertionError(f"expected StackError: {needle}")


cat = {"items": [],
       "plugins": [dict(key="cloudflare@m", name="cloudflare", enabled=True),
                   dict(key="pydantic-ai@m", name="ai", enabled=True),
                   dict(key="off-already@m", name="off-already", enabled=False),
                   dict(key="core@m", name="core", enabled=True)],
       "signals": {"cloudflare@m": {"paths": ["(^|/)wrangler\\.jsonc?$"], "deps": ["@cloudflare/"]},
                   "pydantic-ai@m": {"deps": ["pydantic[-_]ai"]},
                   "off-already@m": {}}}

d = s.decide(["src/wrangler.jsonc"], "", {}, cat)
assert d["cloudflare@m"] == {"state": "keep", "why": "path: src/wrangler.jsonc"}
assert d["pydantic-ai@m"] == {"state": "off", "why": "no signal"}
assert "core@m" not in d, "unnamed plugins are core and never touched"
assert "off-already@m" not in d, "a plugin off at user scope is left alone"
assert s.decide([], "pydantic_ai==1", {}, cat)["pydantic-ai@m"]["why"] == "dependency: pydantic[-_]ai"
assert s.decide([], "", {"pydantic-ai@m": 2}, cat)["pydantic-ai@m"]["why"] == "used here 2 times"
assert s.decide([], "", {}, cat, keep=["pydantic-ai@m"])["pydantic-ai@m"]["why"] == "kept by hand"
assert s.decide(["wrangler.jsonc"], "", {}, cat, off=["cloudflare@m"])["cloudflare@m"] == {"state": "off", "why": "turned off by hand"}

# usage: only this repo's slug and its worktrees, only real calls
root = tmp / "proj"
projects = tmp / "projects"
slug = str(root).replace("/", "-").replace("_", "-").replace(".", "-")
assert s.slug(root) == slug, s.slug(root)


def transcript(rel, *lines):
    f = projects / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text("\n".join(lines) + "\n")


skill = lambda n: '{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}' % n
transcript(f"{slug}/a.jsonl", skill("ai:x"), '{"name":"Agent","input":{"subagent_type":"ai:y"}}',
           r'{"content":"<command-message>z</command-message>\n<command-name>/ai:z</command-name>"}',
           '{"name":"mcp__plugin_ai_srv__t","description":"a definition, not a call"}',
           '{"text":"prose quoting <command-name>/ai:z here"}', skill("ai"), skill("unknown:x"))
transcript(f"{slug}/u/subagents/agent-1.jsonl", '{"name":"mcp__plugin_ai_srv__t","input":{}}')
transcript(f"{slug}--claude-worktrees-t/b.jsonl", skill("ai:w"))
transcript(f"{slug}-other/c.jsonl", skill("ai:nope"))
assert s.usage_counts(root, cat["plugins"], projects) == Counter({"pydantic-ai@m": 5})
assert s.usage_counts(root, cat["plugins"], tmp / "missing") == Counter()

# project_root: where Claude Code reads local settings from
main = repo(tmp / "main")
git(main, "worktree", "add", "-q", str(tmp / "linked"))
assert s.project_root(tmp / "linked") == main
assert s.project_root(main) == main
(main / "sub").mkdir()
assert s.project_root(main / "sub") == main
inner = repo(tmp / "inner")
sup = repo(tmp / "super")
git(sup, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(inner), "s")
assert s.project_root(sup / "s") == sup / "s"
git(tmp, "clone", "-q", "--bare", str(inner), "b.git")
git(tmp / "b.git", "worktree", "add", "-q", str(tmp / "bw"))
assert s.project_root(tmp / "bw") == tmp / "bw"
(tmp / "p").mkdir()
git(tmp, "clone", "-q", "--bare", str(inner), "p/.git")
git(tmp / "p/.git", "worktree", "add", "-q", str(tmp / "p/wk"))
assert s.project_root(tmp / "p/wk") == tmp / "p/wk"
(tmp / "plain").mkdir()
raises(lambda: s.project_root(tmp / "plain"), "not a git repository")
raises(lambda: s.project_root(tmp / "b.git"), "no work tree")

# evidence: tracked files only, allowlisted manifests only
r = repo(tmp / "ev")
(r / "node_modules/x").mkdir(parents=True)
(r / "node_modules/x/package.json").write_text("{}")
(r / "pkg").mkdir()
(r / "pkg/package.json").write_text('{"dependencies":{"wrangler":"1"}}')
(r / ".env").write_text("SECRET=ioredis")
(r / "linked.json").write_text('{"evil":"qdrant"}')
(r / "go.mod").symlink_to(r / "linked.json")
git(r, "add", "-f", ".")
files = s.tracked_files(r)
assert "pkg/package.json" in files and not any("node_modules" in f for f in files), files
text = s.manifest_text(r, files)
assert "wrangler" in text
assert "SECRET" not in text and "qdrant" not in text, text

# merge_settings: only ever touch our own false entries
cur = {"permissions": {"allow": ["Bash(ls)"]}, "enabledPlugins": {"mine@m": True, "old@m": False}}
new, owned = s.merge_settings(cur, {"a@m", "mine@m"}, {"old@m"})
assert new["permissions"] == cur["permissions"]
assert new["enabledPlugins"] == {"mine@m": True, "a@m": False}, "user's entry wins, stale owned entry goes"
assert owned == {"a@m"}
assert "enabledPlugins" not in s.merge_settings({}, set(), set())[0]
new, owned = s.merge_settings({"enabledPlugins": {"x@m": True}}, {"x@m"}, {"x@m"})
assert new["enabledPlugins"] == {"x@m": True} and owned == set(), "a user's edit to an owned key sticks"

# apply and reset on real repos
IGNORE = ".claude/settings.local.json\n.claude/skill-stack.json\n.claude/rules/skill-stack.md\n"
empty = tmp / "no-history"
counter = iter(range(1000))


def stack_repo(ignore=IGNORE):
    r = repo(tmp / f"sr{next(counter)}")
    (r / ".gitignore").write_text(ignore)
    return r


def paths(r):
    return r / ".claude/settings.local.json", r / ".claude/skill-stack.json", r / ".claude/rules/skill-stack.md"


def apply(r, keep=(), off=(), **kw):
    return s.apply_stack(r, kw.pop("catalog", cat), keep, off, projects_dir=kw.pop("projects", empty), **kw)


def settings(r):
    return json.loads(paths(r)[0].read_text())


r = stack_repo()
m = apply(r)
assert settings(r)["enabledPlugins"] == {"cloudflare@m": False, "pydantic-ai@m": False}
assert m["schema"] == 1 and sorted(m["owned"]) == ["cloudflare@m", "pydantic-ai@m"]
assert all(p.exists() for p in paths(r))
before = [p.read_bytes() for p in paths(r)]
apply(r)
assert [p.read_bytes() for p in paths(r)] == before, "re-apply is byte-identical"

# reset removes what apply wrote, and only that
r = stack_repo()
s_file, m_file, rule = paths(r)
s_file.parent.mkdir()
s_file.write_text(json.dumps({"permissions": {"allow": ["Bash(ls)"]}, "enabledPlugins": {"mine@m": True, "theirs@m": False}}))
apply(r)
assert settings(r)["enabledPlugins"]["mine@m"] is True and settings(r)["permissions"]["allow"] == ["Bash(ls)"]
s.reset_stack(r)
assert settings(r) == {"permissions": {"allow": ["Bash(ls)"]}, "enabledPlugins": {"mine@m": True, "theirs@m": False}}
assert not m_file.exists() and not rule.exists()
s.reset_stack(r)  # a no-op without a manifest
r = stack_repo()
apply(r)
s.reset_stack(r)
assert not paths(r)[0].exists(), "no settings file before apply, none after reset"

# bad JSON aborts with nothing written
r = stack_repo()
s_file, m_file, rule = paths(r)
s_file.parent.mkdir()
s_file.write_text("{nope")
raises(lambda: apply(r), "settings.local.json")
assert s_file.read_text() == "{nope" and not m_file.exists() and not rule.exists()
r = stack_repo()
apply(r)
paths(r)[0].write_text("{nope")
raises(lambda: s.reset_stack(r), "settings.local.json")
assert paths(r)[0].read_text() == "{nope" and paths(r)[1].exists()

# refuses to dirty a repo that doesn't ignore these files
r = stack_repo(ignore=".claude/settings.local.json\n")
raises(lambda: apply(r), ".claude/skill-stack.json")
assert not any(p.exists() for p in paths(r))
r = stack_repo()
paths(r)[0].parent.mkdir()
paths(r)[0].write_text("{}")
git(r, "add", "-f", ".claude/settings.local.json")
raises(lambda: apply(r), ".claude/settings.local.json")
assert not paths(r)[1].exists()

# sticky flags
r = stack_repo()
apply(r, keep=["pydantic-ai@m"])
m = apply(r)
assert m["decisions"]["pydantic-ai@m"]["why"] == "kept by hand" and "pydantic-ai@m" not in settings(r)["enabledPlugins"]
r = stack_repo()
apply(r, off=["pydantic-ai@m"])
assert settings(r)["enabledPlugins"]["pydantic-ai@m"] is False
apply(r, keep=["pydantic-ai@m"])
assert "pydantic-ai@m" not in settings(r)["enabledPlugins"], "the restore path the rule advertises"
raises(lambda: apply(stack_repo(), keep=["cloudflare@m"], off=["cloudflare@m"]), "cloudflare@m")
raises(lambda: apply(stack_repo(), keep=["core@m"]), "core@m")
raises(lambda: apply(stack_repo(), off=["off-already@m"]), "off-already@m")
r = stack_repo()
paths(r)[0].parent.mkdir()
paths(r)[0].write_text(json.dumps({"enabledPlugins": {"pydantic-ai@m": False}}))
raises(lambda: apply(r, keep=["pydantic-ai@m"]), "pydantic-ai@m")

# status follows the evidence
r = stack_repo()
assert s.stack_status(r, cat, empty) == "none"
apply(r)
assert s.stack_status(r, cat, empty) == "current"
(r / "wrangler.jsonc").write_text("{}")
git(r, "add", "wrangler.jsonc")
assert s.stack_status(r, cat, empty).startswith("stale: cloudflare@m"), s.stack_status(r, cat, empty)
r = stack_repo()
apply(r)
hist = tmp / "hist"
(hist / s.slug(r)).mkdir(parents=True)
(hist / s.slug(r) / "a.jsonl").write_text(skill("ai:x") + "\n")
assert s.stack_status(r, cat, hist).startswith("stale: pydantic-ai@m")

# the CLI: expected failures exit 2 with no traceback, and paths resolve from the caller's directory
script = Path(s.__file__)


def cli(*args, catalog=None, cwd=None):
    env = {**os.environ, "CLAUDE_STACK_CATALOG": str(catalog), "CLAUDE_CONFIG_DIR": str(tmp / "cfg")}
    return subprocess.run(["python3", str(script), *args], capture_output=True, text=True, env=env, cwd=str(cwd or tmp))


r = stack_repo()
for bad in (tmp / "absent.json", tmp / "bad.json"):
    (tmp / "bad.json").write_text("{nope")
    p = cli("scan", str(r), catalog=bad)
    assert p.returncode == 2 and "run claude-catalog first" in p.stderr and "Traceback" not in p.stderr, p.stderr
good = tmp / "good.json"
good.write_text(json.dumps({**cat, "plugins": [dict(pl, cost=7) for pl in cat["plugins"]]}))
p = cli("scan", catalog=good, cwd=r)
assert p.returncode == 0 and "off cloudflare@m" in p.stdout and "14" in p.stdout and "history: 0 plugin" in p.stdout and "applied: none" in p.stdout, p.stdout
assert not paths(r)[1].exists(), "scan writes nothing"
p = cli("apply", catalog=good, cwd=r)
assert p.returncode == 0 and paths(r)[1].exists(), p.stderr
assert "applied: current" in cli("scan", catalog=good, cwd=r).stdout
p = cli("apply", "--keep", "core@m", catalog=good, cwd=r)
assert p.returncode == 2 and "core@m" in p.stderr and "Traceback" not in p.stderr, p.stderr
assert cli("reset", catalog=tmp / "absent.json", cwd=r).returncode == 0, "reset needs no catalog"
assert not paths(r)[1].exists()
p = cli("scan", catalog=good, cwd=tmp / "plain")
assert p.returncode == 2 and "not a git repository" in p.stderr, p.stderr

# picks: validated against the catalog, because they become an auto-loaded rule
c2 = {"plugins": [dict(key="pydantic-ai@m", name="ai", enabled=True), dict(key="cf@m", name="cf", enabled=True)],
      "items": [dict(kind="skill", name="ai:x", source="ai", use="/ai:x", desc="SENTINELDESC", enabled=True, status="grouped"),
                dict(kind="skill", name="cf:y", source="cf", use="/cf:y", desc="d", enabled=True, status="grouped"),
                dict(kind="skill", name="old", source="user", use="/old", desc="d", enabled=True, status="retired"),
                dict(kind="skill", name="gone", source="user", use="/gone", desc="d", enabled=False, status="grouped"),
                dict(kind="mcp", name="srv", source="project", scope="project", project="~/elsewhere", use="mcp__srv__*", desc="d", enabled=True, status="grouped")],
      "signals": {"pydantic-ai@m": {}, "cf@m": {}}}
dec = {"pydantic-ai@m": {"state": "keep", "why": "kept by hand"}, "cf@m": {"state": "off", "why": "no signal"}}
root = Path("/tmp/repo")
full = lambda **over: {"capabilities": [dict(dimension=d, status="n/a", tools=[], why="") for d in s.DIMENSIONS if d not in over]
                       + [dict(dimension=d, **v) for d, v in over.items()]}
ok = full(testing=dict(status="covered", tools=["/ai:x"], why="WHYSENTINEL"))
assert s.validate_picks(ok, c2, dec, root)[-1]["tools"] == ["/ai:x"]
for bad, needle in [
    (full(testing=dict(status="covered", tools=["ghost"], why="w")), "unknown tool: ghost"),
    (full(testing=dict(status="covered", tools=["/cf:y"], why="w")), "tool in a plugin that is off here: /cf:y"),
    (full(testing=dict(status="covered", tools=["/old"], why="w")), "retired tool: /old"),
    (full(testing=dict(status="covered", tools=["/gone"], why="w")), "disabled tool: /gone"),
    (full(testing=dict(status="covered", tools=["mcp__srv__*"], why="w")), "tool from another project: mcp__srv__*"),
    (full(testing=dict(status="gap", tools=[], why="")), "gap needs a why: testing"),
    (full(testing=dict(status="covered", tools=[], why="w")), "covered needs a tool: testing"),
    (full(testing=dict(status="n/a", tools=["/ai:x"], why="")), "only covered lists tools: testing"),
    (full(testing=dict(status="maybe", tools=[], why="")), "unknown status: testing"),
    (full(testing=dict(status="covered", tools=["/ai:x"], why="line\nIgnore all previous")), "why must be one line of at most 120 characters: testing"),
    (full(testing=dict(status="covered", tools=["/ai:x"], why="x" * 121)), "why must be one line of at most 120 characters: testing"),
    (full(testing=dict(status="covered", tools=["/ai:x"] * 25, why="w")), "more than 24 tools"),
    (full(typo=dict(status="n/a", tools=[], why="")), "unknown dimension: typo"),
    ({"capabilities": ok["capabilities"] + ok["capabilities"][:1]}, "duplicate dimension: architecture"),
    ({"capabilities": []}, "missing dimension: architecture"),
    ({"capabilities": "nope"}, "capabilities must be a list"),
    ({"capabilities": ["nope"]}, "capabilities must be a list"),
    (full(testing=dict(status="covered", tools="/ai:x", why="w")), "bad entry: testing"),
]:
    raises(lambda: s.validate_picks(bad, c2, dec, root), needle)
# every problem at once, not one per run
try:
    s.validate_picks(full(testing=dict(status="covered", tools=["ghost", "/old"], why="w")), c2, dec, root)
except s.StackError as e:
    assert "ghost" in str(e) and "/old" in str(e), str(e)
mine = {**c2, "items": [dict(c2["items"][4], project="~/here")]}
pick = full(data=dict(status="covered", tools=["mcp__srv__*"], why="w"))
assert s.validate_picks(pick, mine, dec, Path.home() / "here")

# the rule: names and restore commands only, never model-written or catalog prose
caps = s.validate_picks(full(testing=dict(status="covered", tools=["/ai:x"], why="WHYSENTINEL"),
                             security=dict(status="gap", tools=[], why="WHYSENTINEL")), c2, dec, root)
dec3 = {**dec, "user-off@m": {"state": "off", "why": "no signal"}}
text = s.render_rule(caps, dec3, {"cf@m"})
assert text.startswith("Generated by claude-stack, do not edit. Run /project-stack to change it.\n"), text
assert "testing: `/ai:x`" in text and "security" in text
assert "claude-stack apply --keep <key>" in text and "`cf@m`" in text
assert "user-off@m" not in text, "a plugin the user owns isn't reported as ours"
assert "SENTINELDESC" not in text and "WHYSENTINEL" not in text
assert "maintenance" not in text, "n/a stays in the manifest"
worst_caps = [dict(dimension="testing", status="covered", tools=[f"Agent(subagent_type=\"plugin-{i:02d}-{'x' * 40}\")" for i in range(24)], why="")]
worst_dec = {f"plugin-{i:02d}-xxxxxxxxxx@claude-plugins-official": {"state": "off", "why": ""} for i in range(23)}
text = s.render_rule(worst_caps, worst_dec, set(worst_dec))
assert len(text.encode()) <= 4000 and all(len(l) <= 1000 for l in text.splitlines()), len(text)
huge = {f"{'k' * 200}{i}@m": {"state": "off", "why": ""} for i in range(30)}
raises(lambda: s.render_rule([], huge, set(huge)), "4,000 bytes")

# apply writes it, later applies keep it, and a pick whose plugin went off stops the apply
c3 = {**c2, "signals": {"pydantic-ai@m": {"paths": ["KEEPAI"]}, "cf@m": {"paths": ["KEEPCF"]}}}
r = stack_repo()
(r / "KEEPAI").write_text("x")
git(r, "add", "KEEPAI")
rule_text = lambda r: paths(r)[2].read_text()
apply(r, catalog=c3)
assert "claude-stack apply --keep <key>" in rule_text(r) and "`cf@m`" in rule_text(r), "off plugins listed with no picks"
assert "/ai:x" not in rule_text(r)
m = apply(r, catalog=c3, picks=ok)
assert "testing: `/ai:x`" in rule_text(r) and "WHYSENTINEL" not in rule_text(r)
assert m["capabilities"][-1]["why"] == "WHYSENTINEL", "why stays in the manifest"
before = paths(r)[2].read_bytes()
apply(r, catalog=c3)
assert paths(r)[2].read_bytes() == before, "a later apply keeps the picks"
raises(lambda: apply(r, catalog=c3, off=["pydantic-ai@m"]), "/ai:x")
assert settings(r)["enabledPlugins"] == {"cf@m": False}, "a refused apply writes nothing"
raises(lambda: apply(stack_repo(), catalog=c3, picks=ok), "/ai:x")
# earlier picks gone stale block a flag-only apply, so the refusal has to name the way out
renamed = {**c3, "items": [i for i in c3["items"] if i["use"] != "/ai:x"]}
raises(lambda: apply(r, catalog=renamed), "unknown tool: /ai:x")
raises(lambda: apply(r, catalog=renamed), "claude-stack reset")
raises(lambda: apply(r, catalog=renamed), "/project-stack")
s.reset_stack(r)
assert "cf@m" not in apply(r, catalog=renamed, keep=["cf@m"])["owned"], "the advertised restore works after the way out"

# --picks through the CLI, relative to the caller's directory
good3 = tmp / "good3.json"
good3.write_text(json.dumps(c3))
r = stack_repo()
(r / "KEEPAI").write_text("x")
git(r, "add", "KEEPAI")
(r / "picks.json").write_text(json.dumps(ok))
p = cli("apply", "--picks", "picks.json", catalog=good3, cwd=r)
assert p.returncode == 0, p.stderr
assert "/ai:x" in rule_text(r)
for name, body in (("absent.json", None), ("broken.json", "{nope")):
    if body:
        (r / name).write_text(body)
    p = cli("apply", "--picks", name, catalog=good3, cwd=r)
    assert p.returncode == 2 and name in p.stderr and "Traceback" not in p.stderr, p.stderr

print("ok")
