#!/usr/bin/env bash
# claudespace.nvim health check script
# Runs: syntax check → module load check → unit tests
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

green() { printf '\033[32m✓\033[0m %s\n' "$*"; }
red()   { printf '\033[31m✗\033[0m %s\n' "$*"; }

# ── 1. Lua syntax check ────────────────────────────────────────────────────────
echo
echo "── Syntax check ──────────────────────────────────────────────────────────"

if ! command -v luac &>/dev/null; then
  echo "  luac not found, skipping syntax check"
else
  while IFS= read -r -d '' file; do
    if luac -p "$file" 2>/tmp/luac_err; then
      green "$file"
      ((PASS++))
    else
      red "$file"
      cat /tmp/luac_err
      ((FAIL++))
    fi
  done < <(find "$ROOT/lua" -name '*.lua' -print0)
fi

# ── 2. Module load check (headless Neovim) ────────────────────────────────────
echo
echo "── Module load check ─────────────────────────────────────────────────────"

if ! command -v nvim &>/dev/null; then
  echo "  nvim not found, skipping load check"
else
  MODULES=(
    "claudespace.options"
    "claudespace.keymaps"
    "claudespace.health"
    "claudespace.theme"
    "claudespace.theme.palette"
    "claudespace.shell"
    "claudespace.repos"
    "claudespace.gotofile"
    "claudespace.mdpreview"
    "claudespace.zen"
    "claudespace.mdtoc"
    "claudespace.claude.bottombar"
    "claudespace.claude.util"
    "claudespace.claude.sessions"
    "claudespace.claude.commands"
    "claudespace.claude.dashboard"
    "claudespace.claude.agents"
    "claudespace.claude.status"
    "claudespace.claude.context"
    "claudespace.claude.git_ops"
    "claudespace.claude.codegen"
    "claudespace.claude.fix"
    "claudespace.claude.assist"
    "claudespace.claude.workspace"
    "claudespace.sidebar"
    "claudespace.layout"
    "claudespace.workspace"
    "claudespace.outline"
  )

  for mod in "${MODULES[@]}"; do
    output=$(nvim --headless \
      -u "$ROOT/tests/minimal_init.lua" \
      -c "lua local ok, err = pcall(require, '$mod'); if not ok then vim.api.nvim_err_writeln('LOAD_FAIL: ' .. tostring(err)) end" \
      -c "qa!" 2>&1 || true)

    if echo "$output" | grep -q "LOAD_FAIL"; then
      red "require('$mod')"
      echo "    $(echo "$output" | grep LOAD_FAIL | head -1)"
      ((FAIL++))
    else
      green "require('$mod')"
      ((PASS++))
    fi
  done
fi

# ── 3. Unit tests (plenary) ───────────────────────────────────────────────────
echo
echo "── Unit tests ────────────────────────────────────────────────────────────"

if ! command -v nvim &>/dev/null; then
  echo "  nvim not found, skipping unit tests"
else
  for spec in "$ROOT/tests/spec/"*_spec.lua; do
    name="$(basename "$spec")"
    output=$(nvim --headless \
      -u "$ROOT/tests/minimal_init.lua" \
      -c "lua require('plenary.test_harness').test_file('$spec')" \
      -c "qa!" 2>&1 || true)

    # plenary reports "Errors : N" and "Failures : N" — fail only if N > 0
    nerrors=$(echo "$output" | grep -oE 'Errors[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || echo 0)
    nfail=$(echo "$output" | grep -oE 'Failures[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || echo 0)
    if [[ "${nerrors:-0}" -gt 0 || "${nfail:-0}" -gt 0 ]] || echo "$output" | grep -q "FAILED"; then
      red "$name"
      echo "$output" | grep -E "FAILED|✗" | head -5 | sed 's/^/    /'
      ((FAIL++))
    else
      green "$name"
      ((PASS++))
    fi
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "── Summary ───────────────────────────────────────────────────────────────"
echo "  Passed: $PASS  Failed: $FAIL"
echo

[[ $FAIL -eq 0 ]]
