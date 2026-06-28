#!/usr/bin/env bash
# Pick a file with a GUI/TUI chooser and print its absolute path to stdout.
# Prefers the user's file manager (yazi in kitty), then common GTK/Qt dialogs.
set -uo pipefail

if command -v yazi >/dev/null 2>&1 && command -v kitty >/dev/null 2>&1; then
    out=$(mktemp)
    kitty --class quickshell-filepicker -e yazi --chooser-file="$out" >/dev/null 2>&1
    path=$(head -n1 "$out" 2>/dev/null)
    rm -f "$out"
    [ -n "${path:-}" ] && printf '%s' "$path"
    exit 0
fi

if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection 2>/dev/null
elif command -v kdialog >/dev/null 2>&1; then
    kdialog --getopenfilename 2>/dev/null
elif command -v qarma >/dev/null 2>&1; then
    qarma --file-selection 2>/dev/null
else
    exit 1
fi
