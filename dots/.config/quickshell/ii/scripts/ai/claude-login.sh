#!/usr/bin/env bash
# Log in to a Claude (Pro/Max) subscription via OAuth in the browser.
# No API key involved. Uses whichever sign-in path is available:
#   1) the `ant` (Anthropic) CLI  -> `ant auth login`
#   2) Claude Code (`claude`)      -> opens it so you can run `/login`
# Both write a credential that scripts/ai/claude-token.sh can read.
set -uo pipefail

# Prefer the configured terminal so the flow can be completed interactively.
term=""
command -v kitty >/dev/null 2>&1 && term="kitty --class quickshell-claude-login -e"

if command -v ant >/dev/null 2>&1; then
    if [ -n "$term" ]; then
        setsid -f $term ant auth login >/dev/null 2>&1
    else
        setsid -f ant auth login >/dev/null 2>&1
    fi
    echo "Opened a login window (ant). Finish signing in in your browser, then reselect a Claude model."
    exit 0
fi

if command -v claude >/dev/null 2>&1; then
    if [ -n "$term" ]; then
        setsid -f $term claude >/dev/null 2>&1
        echo "Opened Claude Code. Type /login there, finish in the browser, then reselect a Claude model."
    else
        echo "Claude Code is installed. Run 'claude' in a terminal, type /login, then reselect a Claude model."
    fi
    exit 0
fi

echo "No Claude sign-in tool found. Install one (no API key needed):"
echo "  • Claude Code:  https://claude.com/claude-code   then run 'claude' and /login"
echo "  • Anthropic CLI 'ant':  go install github.com/anthropics/anthropic-cli/cmd/ant@latest"
echo "Then pick a Claude model again."
exit 1
