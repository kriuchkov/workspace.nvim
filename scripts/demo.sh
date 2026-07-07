#!/usr/bin/env bash
# Launch claudespace.nvim on a demo so you can try it hands-on.
#
#   scripts/demo.sh                   # multi-repo workspace (default)
#   scripts/demo.sh workspace tour    # self-driving tour (for asciinema)
#   scripts/demo.sh go                # single Go repo
#   scripts/demo.sh rust              # single Rust repo
#
# The demos live inside this repo, so opening them in place would make
# claudespace treat the whole claudespace.nvim checkout as the workspace root.
# Instead we stage a clean, tracked-only snapshot into throwaway git repo(s)
# under $TMPDIR and open THAT — so the tree, workspace, git, and LSP see only
# the demo. For the multi-repo workspace, each member (services/*, libs/*) is
# git-init'd as its own repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-workspace}"
MODE="${2:-}"

if [[ ! -d "$ROOT/demo/$TARGET" ]]; then
  echo "Unknown demo '$TARGET'. Available: workspace, go, rust" >&2
  exit 1
fi

# The file to open so the home screen / restore doesn't hijack the session.
case "$TARGET" in
  workspace) ENTRY="services/vega/main.go" ;;
  go)        ENTRY="main.go" ;;
  rust)      ENTRY="src/main.rs" ;;
  *)         ENTRY="." ;;
esac

GIT_ID=(-c user.name=claudespace -c user.email=demo@claudespace.nvim -c commit.gpgsign=false)
init_repo() {
  git -C "$1" init -q
  git -C "$1" "${GIT_ID[@]}" add -A
  git -C "$1" "${GIT_ID[@]}" commit -q -m "demo: initial commit"
}

# Stage a tracked-only snapshot (no build artifacts, no nested .git).
STAGE="${TMPDIR:-/tmp}/claudespace-demo-$TARGET"
rm -rf "$STAGE"; mkdir -p "$STAGE"
git -C "$ROOT" archive "HEAD:demo/$TARGET" | tar -x -C "$STAGE"

if [[ "$TARGET" == "workspace" ]]; then
  for repo in "$STAGE"/services/* "$STAGE"/packages/* "$STAGE"/frontends/* "$STAGE"/deploy; do
    [[ -d "$repo" ]] && init_repo "$repo"
  done
  # Leave a couple of repos with changes so the tree's git-status column has
  # something to show (● modified / untracked), like a real working monorepo.
  printf '\n// TODO: rate-limit this handler\n' >> "$STAGE/services/vega/main.go" 2>/dev/null || true
  printf 'scratch notes\n' > "$STAGE/services/nova/NOTES.md" 2>/dev/null || true
else
  init_repo "$STAGE"
fi
DIR="$STAGE"

# Extra args: in tour mode, load the self-driving director.
NVIM_ARGS=("$ENTRY")
if [[ "$MODE" == "tour" ]]; then
  NVIM_ARGS+=(-c "luafile $ROOT/scripts/demo_tour.lua")
fi

# Pick how to run nvim with the claudespace config:
#   1. NVIM_APPNAME already set → respect it
#   2. ~/.config/claudespace exists (dev symlink) → NVIM_APPNAME=claudespace
#   3. this repo IS ~/.config/nvim → plain nvim
#   4. otherwise → source this repo's init.lua directly
run_nvim() {
  if [[ -n "${NVIM_APPNAME:-}" ]]; then
    nvim "$@"
  elif [[ -d "$HOME/.config/claudespace" ]]; then
    NVIM_APPNAME=claudespace nvim "$@"
  elif [[ "$ROOT" -ef "$HOME/.config/nvim" ]]; then
    nvim "$@"
  else
    # Not installed as a config: run this checkout directly. --cmd runs before
    # init.lua, so putting the repo on rtp/packpath first lets `require
    # 'claudespace.*'` resolve. (First run installs plugins via vim.pack.)
    nvim --cmd "set rtp^=$ROOT packpath^=$ROOT" -u "$ROOT/init.lua" "$@"
  fi
}

echo "Starting claudespace demo: $TARGET  ($DIR)${MODE:+  [$MODE]}"
cd "$DIR"
run_nvim "${NVIM_ARGS[@]}"
