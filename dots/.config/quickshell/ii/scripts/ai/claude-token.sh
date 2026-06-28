#!/usr/bin/env bash
# Resolve a Claude / Anthropic OAuth *access token* without an API key.
# Prints the bare token to stdout (no trailing newline) and exits 0 on success.
# Tries, in order: the `ant` CLI (auto-refreshes), then the credential files
# written by Claude Code / the `ant` CLI.
set -uo pipefail

emit() { printf '%s' "$1"; exit 0; }

# 1) Anthropic CLI — refreshes the token if needed.
if command -v ant >/dev/null 2>&1; then
    tok=$(ant auth print-credentials --access-token 2>/dev/null || true)
    [ -n "${tok:-}" ] && emit "$tok"
fi

# 2) Claude Code credentials (~/.claude/.credentials.json)
if command -v jq >/dev/null 2>&1; then
    for f in "$HOME/.claude/.credentials.json" "$HOME/.config/claude/.credentials.json"; do
        if [ -f "$f" ]; then
            tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$f" 2>/dev/null || true)
            [ -n "${tok:-}" ] && emit "$tok"
        fi
    done

    # 3) `ant` profile credentials (~/.config/anthropic/credentials/*.json)
    cred_dir="${ANTHROPIC_CONFIG_DIR:-$HOME/.config/anthropic}/credentials"
    if [ -d "$cred_dir" ]; then
        for f in "$cred_dir"/*.json; do
            [ -f "$f" ] || continue
            tok=$(jq -r '.access_token // .accessToken // empty' "$f" 2>/dev/null || true)
            [ -n "${tok:-}" ] && emit "$tok"
        done
    fi
fi

echo "no-claude-credentials" >&2
exit 1
