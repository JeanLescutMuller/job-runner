#!/bin/bash
fails=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', expected '$3'"; fails=$((fails + 1)); fi; }
expect "its own folder" "$(basename "$PWD")" canaries
expect "PATH has ~/.local/bin" "$(echo ":$PATH:" | grep -c ":$HOME/.local/bin:")" 1
expect "LANG is UTF-8" "$(echo "$LANG" | grep -ci 'utf-\?8')" 1
expect "no job-runner-sync token" "${JR_SYNC_TOKEN-unset}" unset
expect "no terminal" "$([ -t 0 ] || [ -t 1 ] && echo tty || echo none)" none
echo "$((5 - fails))/5 ok"; exit $((fails > 0))
