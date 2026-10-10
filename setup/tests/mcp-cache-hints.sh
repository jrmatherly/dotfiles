#!/bin/bash
#
# Tests bin/mcp-cache-hints against a fake stdio MCP server. Run by bin/lib/check.

set -u

repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
fails=0

check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fails=$((fails + 1))
  fi
}

# A server that answers initialize, tools/list and an unrelated result, and
# echoes what it read on stdin to stderr so passthrough can be checked
fake='read -r first; echo "server got: $first" >&2
printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-03-26\"}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"t\"}]}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"content\":[]}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"resources\":[]}}"'
# shellcheck disable=SC2034 # read inside the eval'd checks
out=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | "$repo/bin/mcp-cache-hints" bash -c "$fake" 2> /dev/null)
# shellcheck disable=SC2034 # read inside the eval'd checks
err=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | "$repo/bin/mcp-cache-hints" bash -c "$fake" 2>&1 > /dev/null)

check "client stdin reaches the server" '[ "$err" = "server got: {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}" ]'
check "tools/list result gains ttlMs and cacheScope" '[ "$(jq -c "select(.id == 2) | .result | {ttlMs, cacheScope}" <<< "$out")" = "{\"ttlMs\":0,\"cacheScope\":\"private\"}" ]'
check "resources/list result gains them too" '[ "$(jq -r "select(.id == 4) | .result.ttlMs" <<< "$out")" = 0 ]'
check "other results are untouched" '[ "$(jq -c "select(.id == 1 or .id == 3) | .result" <<< "$out" | tr "\n" " ")" = "{\"protocolVersion\":\"2025-03-26\"} {\"content\":[]} " ]'
check "one output line per input line" '[ "$(wc -l <<< "$out" | tr -d " ")" = 4 ]'
check "no arguments is a usage error" '! "$repo/bin/mcp-cache-hints" > /dev/null 2>&1'

exit $fails
