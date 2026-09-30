#!/bin/bash
#
# Self-check for lint-edited.sh — run: .claude/hooks/test-lint-edited.sh

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
hook=.claude/hooks/lint-edited.sh
tmp=hooktest-$$
mkdir -p "$tmp" private
trap 'rm -rf "$root/$tmp" "$root/private/hooktest-$$.sh"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
# Feed the hook a PostToolUse payload; prints nothing, returns the hook's exit code
run() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
    | CLAUDE_PROJECT_DIR=$root "$hook" 2> /dev/null
}

# 1. Unformatted Markdown gets formatted, exit 0
printf '# T\n\n* a\n' > "$tmp/a.md"
run "$root/$tmp/a.md" || fail "markdown: non-zero exit"
grep -q '^- a$' "$tmp/a.md" || fail "markdown: not formatted"

# 2. Bash syntax error → exit 2
printf '#!/bin/bash\nif then\n' > "$tmp/b.sh"
set +e
run "$root/$tmp/b.sh"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "bash syntax error: expected exit 2, got $rc"

# 3. Valid zsh is never reformatted
printf '(( $+functions[fast-theme] )) && true\n' > "$tmp/c.zsh"
cp "$tmp/c.zsh" "$tmp/c.orig"
run "$root/$tmp/c.zsh" || fail "zsh: non-zero exit on valid file"
cmp -s "$tmp/c.zsh" "$tmp/c.orig" || fail "zsh: file was modified"

# 4. Invalid zsh → exit 2
printf 'if [[ ; then\n' > "$tmp/d.zsh"
set +e
run "$root/$tmp/d.zsh"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "zsh syntax error: expected exit 2, got $rc"

# 5. Paths outside the project and missing paths are ignored
run /etc/hosts || fail "outside path: non-zero exit"
run "$root/$tmp/missing.md" || fail "missing path: non-zero exit"

# 6. Gitignored files are skipped (private/ is gitignored)
printf '#!/bin/bash\nif then\n' > "private/hooktest-$$.sh"
run "$root/private/hooktest-$$.sh" || fail "gitignored file: should be skipped"

# 7. Extensionless non-bash script in bin/ (Swift) is skipped untouched
cp bin/ocr "$tmp/ocr.orig"
run "$root/bin/ocr" || fail "bin/ocr: non-zero exit"
cmp -s bin/ocr "$tmp/ocr.orig" || fail "bin/ocr: file was modified"

# 8. Serena's edit tools send a project-relative path
printf '# T\n\n* b\n' > "$tmp/e.md"
printf '{"tool_name":"mcp__serena__replace_content","tool_input":{"relative_path":"%s"}}' "$tmp/e.md" \
  | CLAUDE_PROJECT_DIR=$root "$hook" 2> /dev/null || fail "serena relative_path: non-zero exit"
grep -q '^- b$' "$tmp/e.md" || fail "serena relative_path: not formatted"

# 9. A .sh file outside pnpm check's shellcheck set (like colors/*.sh, sourced,
#    no shebang) is formatted but not shellchecked → exit 0
printf 'export FOO=1\n' > "$tmp/theme.sh"
run "$root/$tmp/theme.sh" || fail "ungated .sh: should not be shellchecked"

# 10. bin/lib/ isn't in pnpm check's scope → untouched, exit 0
lib=bin/lib/hooktest-$$
printf '#!/bin/bash\nf() { local x=$(date); echo "$x"; }\n' > "$lib"
cp "$lib" "$tmp/lib.orig"
run "$root/$lib"
rc=$?
rm -f "$lib"
[ "$rc" -eq 0 ] || fail "bin/lib: expected exit 0, got $rc"

echo "lint-edited: all checks passed"
