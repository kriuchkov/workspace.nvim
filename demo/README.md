# claudespace demos

Real, buildable projects for trying claudespace.nvim hands-on — the multi-repo
workspace, LSP, the task/test runner, markdown preview, and Claude actions all
work out of the box.

| Demo | What it shows | Try |
|------|---------------|-----|
| [`workspace/`](workspace) | **multi-repo** monorepo: Go + Rust services, a shared package, a frontend, deploy | `scripts/demo.sh` |
| [`go/`](go)   | single Go repo | `scripts/demo.sh go` |
| [`rust/`](rust) | single Rust repo | `scripts/demo.sh rust` |

The **workspace** (`orbit`) is the headline demo — shaped like a real monorepo,
six git repos under one `.claudespace/workspace.json` manifest:

- `services/vega` (Go), `services/lyra` (Go), `services/nova` (Rust)
- `packages/nebula` (Go) — shared, depended on by the Go services (`go.work`)
- `frontends/aurora` (Rust), `deploy` (docker-compose)

It has an active (pinned) repo, per-repo git status in the tree (a couple of
repos are left dirty so the ● markers show), cross-repo Fleet commands, and each
repo ships a `tasks.json`, a `CLAUDE.md`, and `.claude/commands` you can fire
with `<leader>cC`.

## Launch

From the repo root:

```bash
scripts/demo.sh                  # multi-repo workspace (default)
scripts/demo.sh workspace tour   # self-driving tour (great for recordings)
scripts/demo.sh go               # or: rust — the single-repo demos
```

The script stages a **clean, isolated copy** into throwaway git repo(s) under
`$TMPDIR` and opens that — so the tree, workspace, git, and LSP see just the
demo (not the surrounding claudespace.nvim checkout). For the workspace, each
member repo (`services/*`, `libs/*`) is `git init`'d on its own. It auto-detects
a normal install, a `NVIM_APPNAME=claudespace` dev symlink, or falls back to
`nvim -u init.lua`.

`tour` mode loads [`scripts/demo_tour.lua`](demo_tour.lua): a timed, caption-
driven walkthrough of the tree (repo roots), the **repos overview**, the active
repo, **LSP** across modules (hover, `gd`, outline), the **test runner**, the
**Fleet** commands, **Claude sessions** in the bottom bar, and **markdown
preview** + theme flip — then it quits itself. LSP/Claude steps need gopls /
the `claude` CLI; without them the tour skips those bits gracefully.

## A 60-second tour

1. `\` — file tree; open a source file (`services/vega/main.go`, `greeter.go`, …).
2. `<leader>ru` — run the tests, watch the results panel.
3. `<leader>cn` — new Claude session (bottom bar); ask it something, `<A-l>`/`<A-h>` to switch.
4. `<leader>cC` — run the `/review` command in the background (spinner → notification).
5. `<leader>cgt` on the file — generate tests; `<leader>gc` — a commit message from the diff.
6. Open the README, `<leader>mp` — markdown preview; `]l` / `<CR>` — follow links.
7. `<leader>ub` — flip the theme dark ⇄ light.

## Record a demo (asciinema)

First record a cast — this is the same for both options below:

```bash
brew install asciinema        # macOS (or your package manager)

# resize the terminal to ~120×32 first, then:
asciinema rec demo.cast --command "scripts/demo.sh workspace tour"
```

The `tour` runs itself and quits, so the recording ends on its own — no manual
driving. (Drop `tour` to record a hands-on session; stop it with Ctrl-D.)
`demo.cast` is a small plain-text file (JSON lines) — edit it to trim dead time.

### Option A — host on asciinema.org (clickable player)

asciinema.org hosts the recording and gives every cast a **clickable SVG
thumbnail** that renders in a GitHub README and opens the player on click. It
does *not* export a GIF — use Option B for an inline animation.

```bash
asciinema upload demo.cast     # prints https://asciinema.org/a/<ID>
```

Then embed the thumbnail in the top-level README:

```markdown
[![claudespace demo](https://asciinema.org/a/<ID>.svg)](https://asciinema.org/a/<ID>)
```

### Option B — inline GIF (agg, local)

For an animated GIF that plays right in the README, convert the cast locally
with [`agg`](https://github.com/asciinema/agg) (asciinema's gif generator):

```bash
brew install agg
agg --theme monokai --font-size 20 --speed 1.5 demo.cast docs/demo.gif
```

Then uncomment the image line in the top-level README.

Tips: run the tour at a calm pace (pauses read well); `--speed` or editing
`demo.cast` trims length; keep the window ≤120 cols so the GIF stays legible.
