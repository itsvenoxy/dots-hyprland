#!/usr/bin/env bash
# Log in to a Claude (Pro/Max) subscription via OAuth in the browser.
# No API key involved. Opens a terminal (kitty) running `ant auth login`,
# which spins up the browser-based OAuth flow.
set -uo pipefail

if ! command -v ant >/dev/null 2>&1; then
    echo "The 'ant' (Anthropic) CLI is not installed."
    echo "Install it, or log in once with Claude Code, then pick a Claude model again."
    exit 1
fi

# Prefer the configured terminal so the user can complete the flow interactively.
if command -v kitty >/dev/null 2>&1; then
    setsid -f kitty --class quickshell-claude-login -e ant auth login >/dev/null 2>&1
    echo "Opened a login window. Complete the sign-in in your browser, then reselect a Claude model."
else
    setsid -f ant auth login >/dev/null 2>&1
    echo "Started the Claude login flow in your browser. Reselect a Claude model when done."
fi
