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

print("ok")
